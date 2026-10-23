"""What a publish changes, and the guard that refuses a shrunken one (docs/CATALOG-CONTRACT.md §7).

    python3 tools/publish_diff.py --old-manifest live/manifest.json --new-manifest out/publish/manifest.json
    python3 tools/publish_diff.py ... --old-db live/ear-drama.sqlite.zz --new-db out/publish/ear-drama.sqlite \\
        --old-research out/restored.sqlite --research out/radio-catalog.sqlite
    python3 tools/publish_diff.py ... --max-shrink 0.02 --reason "takedown of series X, 2026-11-02"

Prints, as Markdown, every count and byte total in the two manifests side by
side; with the databases, which episode ids came and went and why each one
left (aliased to a new id, now hidden by the audit, or gone without either);
with the research databases, the episode count per rights state.

The guard: when the new manifest has fewer episodes than the published one by
more than --max-shrink (a fraction), the publish is refused (exit 1) unless a
--reason is given; the reason is printed into the run's summary, so a shrink
is always on the record (Archive Watch Decision 020). A missing old manifest is
a first run and passes. A change of `cleanOnly` (the public-web gate opening or
closing) is reported and not judged: that change is the reason.
"""
import argparse
import json
import os
import sqlite3
import sys
import tempfile
import zlib

SKIP_BYTES = {"maxRaw", "maxGzip", "maxFile"}


def load_manifest(path):
    if not path or not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def flat(obj, prefix=""):
    """Numeric leaves of a nested dict, keyed by their dotted path."""
    out = {}
    for k, v in (obj or {}).items():
        if k in SKIP_BYTES:
            continue
        key = f"{prefix}{k}"
        if isinstance(v, dict):
            out.update(flat(v, key + "."))
        elif isinstance(v, (int, float)) and not isinstance(v, bool):
            out[key] = v
    return out


def counts_of(m):
    c = dict((m or {}).get("counts") or {})
    if "episodes" in c and "clean" in c:
        c["unclaimed"] = c["episodes"] - c["clean"]
    return c


def table(title, old, new, cols=("published", "this run")):
    keys = sorted(set(old) | set(new))
    lines = [f"**{title}**", "", f"| | {cols[0]} | {cols[1]} | change |", "|---|---:|---:|---:|"]
    for k in keys:
        a, b = old.get(k), new.get(k)
        if a is None:
            d = "new"
        elif b is None:
            d = "gone"
        else:
            d = f"{b - a:+,}" if b != a else "0"
        lines.append(f"| {k} | {'' if a is None else f'{a:,}'} | {'' if b is None else f'{b:,}'} | {d} |")
    return lines + [""]


def open_db(path, tmpdir):
    """A read-only connection; a raw-DEFLATE `.zz` (wbits -15) is inflated to a temp file first."""
    if path.endswith(".zz"):
        dst = os.path.join(tmpdir, os.path.basename(path)[:-3] + f".{len(os.listdir(tmpdir))}")
        d = zlib.decompressobj(-15)
        with open(path, "rb") as f, open(dst, "wb") as o:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                o.write(d.decompress(chunk))
            o.write(d.flush())
        path = dst
    return sqlite3.connect(f"file:{path}?mode=ro", uri=True)


def ids_of(con):
    return {r[0] for r in con.execute("SELECT id FROM episodes")}


def id_changes(old_db, new_db, research, tmpdir):
    o, n = open_db(old_db, tmpdir), open_db(new_db, tmpdir)
    old_ids, new_ids = ids_of(o), ids_of(n)
    aliases = dict(n.execute("SELECT old_id, new_id FROM episode_aliases"))
    o.close()
    n.close()
    added, removed = new_ids - old_ids, old_ids - new_ids
    states = {}
    if research:
        r = open_db(research, tmpdir)
        states = {i: (s, b) for i, s, b in r.execute("SELECT id, state, rec_bucket FROM episodes")}
        r.close()
    why = {"aliased": [], "hidden": [], "unexplained": []}
    for i in sorted(removed):
        if aliases.get(i) in new_ids:
            why["aliased"].append(i)
        elif i in states and not states[i][0].startswith("keep_"):
            why["hidden"].append(f"{i} ({states[i][0]}: {states[i][1]})")
        else:
            why["unexplained"].append(i)
    return added, removed, why, bool(research)


def state_counts(path, tmpdir):
    con = open_db(path, tmpdir)
    out = dict(con.execute("SELECT state, COUNT(*) FROM episodes GROUP BY state"))
    con.close()
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--old-manifest", default="")
    ap.add_argument("--new-manifest", required=True)
    ap.add_argument("--old-db", default="")
    ap.add_argument("--new-db", default="")
    ap.add_argument("--old-research", default="")
    ap.add_argument("--research", default="")
    ap.add_argument("--label", default="catalog")
    ap.add_argument("--max-shrink", type=float, default=None,
                    help="refuse when episodes fall by more than this fraction of the published count")
    ap.add_argument("--research-floor", type=float, default=None,
                    help="refuse when the rebuilt research database serves this fraction fewer episodes than the "
                         "restored one (a restore or build that read less than it should)")
    ap.add_argument("--reason", default="", help="a recorded reason that lets a larger shrink through")
    ap.add_argument("--summary", default="", help="append the Markdown here too (e.g. $GITHUB_STEP_SUMMARY)")
    a = ap.parse_args()

    new = load_manifest(a.new_manifest)
    if new is None:
        print(f"::error::no new manifest at {a.new_manifest}: this run built nothing")
        return 1
    old = load_manifest(a.old_manifest)
    out = [f"### {a.label}: what this publish changes", ""]
    if old is None:
        out += ["First publish: nothing published to compare against.", ""]
    else:
        out += [f"Published {old.get('generatedAt', '?')}; this run {new.get('generatedAt', '?')}.", ""]
    out += table("Counts", counts_of(old), counts_of(new))
    out += table("Bytes", flat((old or {}).get("bytes")), flat(new.get("bytes")))

    with tempfile.TemporaryDirectory() as tmp:
        research_kept = None
        if a.old_research and a.research and os.path.exists(a.old_research) and os.path.exists(a.research):
            before_states, after_states = state_counts(a.old_research, tmp), state_counts(a.research, tmp)
            out += table("Research database, episodes per rights state",
                         before_states, after_states, ("restored snapshot", "rebuilt"))
            kept = lambda st: sum(n for k, n in st.items() if k.startswith("keep_"))
            research_kept = (kept(before_states), kept(after_states))
        if a.old_db and a.new_db and os.path.exists(a.old_db):
            added, removed, why, judged = id_changes(a.old_db, a.new_db, a.research, tmp)
            out += [f"**Episode ids**: {len(added):,} added, {len(removed):,} removed "
                    f"({len(why['aliased']):,} aliased to a new id, {len(why['hidden']):,} now hidden by the audit, "
                    f"{len(why['unexplained']):,} {'gone without either' if judged else 'not judged (no research database)'}).", ""]
            for k in ("hidden", "unexplained"):
                if why[k]:
                    out += [f"First {k}: " + ", ".join(why[k][:10]), ""]
            if judged and why["unexplained"]:
                # Report, not a gate: contract §9.6 wants every leaving id aliased or taken down,
                # and an id that leaves silently breaks a saved history or share link.
                print(f"::warning::{len(why['unexplained'])} episode ids left the {a.label} with no alias "
                      f"and no hide (contract §9.6)")

    verdict = 0
    if a.research_floor is not None and research_kept:
        # Not policy but plumbing: a rebuild from a half-restored cache serves far fewer rows than
        # the snapshot it was restored with, and this catches that even on a first publish.
        before, after = research_kept
        if before and after < before * (1 - a.research_floor):
            if a.reason:
                print(f"::warning::the rebuild serves {after} episodes against the restored snapshot's {before}; "
                      f"allowed by the recorded reason: {a.reason}")
            else:
                out += [f"**Refused**: the rebuild serves {after:,} episodes, the restored snapshot {before:,}; "
                        f"past the {a.research_floor:.0%} floor, so the restore or the build read less than it "
                        f"should have.", ""]
                print(f"::error::the rebuild serves {after} episodes against the restored snapshot's {before} "
                      f"(past the {a.research_floor:.0%} floor); not publishing")
                verdict = 1
        else:
            out += [f"Rebuild check: {before:,} -> {after:,} served episodes against the restored snapshot, "
                    f"within the {a.research_floor:.0%} floor.", ""]
    if a.max_shrink is not None and old is not None:
        before, after = counts_of(old).get("episodes", 0), counts_of(new).get("episodes", 0)
        if old.get("cleanOnly") != new.get("cleanOnly"):
            out += [f"The public-web gate changed (cleanOnly {old.get('cleanOnly')} -> {new.get('cleanOnly')}); "
                    f"the episode count is not judged against the other gate's.", ""]
        elif before and after < before * (1 - a.max_shrink):
            lost = before - after
            if a.reason:
                out += [f"**Shrink allowed**: {before:,} -> {after:,} episodes (-{lost:,}, "
                        f"{lost / before:.1%}). Recorded reason: {a.reason}", ""]
                print(f"::warning::{a.label} shrank {before} -> {after} episodes; allowed by the recorded reason: {a.reason}")
            else:
                out += [f"**Refused**: {before:,} -> {after:,} episodes (-{lost:,}, {lost / before:.1%}) is past the "
                        f"floor of {a.max_shrink:.1%}. Re-run with a recorded reason to publish it.", ""]
                print(f"::error::refusing to publish the {a.label}: {before} -> {after} episodes "
                      f"(-{lost / before:.1%}) is past the {a.max_shrink:.1%} floor and no reason was recorded")
                verdict = 1
        else:
            out += [f"Guard: {before:,} -> {after:,} episodes, within the {a.max_shrink:.1%} floor.", ""]

    text = "\n".join(out)
    print(text)
    if a.summary:
        with open(a.summary, "a", encoding="utf-8") as f:
            f.write(text + "\n")
    return verdict


if __name__ == "__main__":
    sys.exit(main())
