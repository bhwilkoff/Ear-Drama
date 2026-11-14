"""Build the play library published beside the catalog (Decision 075): every Project
Gutenberg play whose rights are castable AND whose text parses clean, as an index plus
one script file per play. Nothing here writes a word; each script is the parser's exact
slices (build_castable_scripts.script_entry), so a play the apps already bundle comes out
here with the same id and revision (and the same entry as a fresh bundle build; the shipped
bundle predates `sections`, Decision 076 S0).

    python3 tools/harvest_gutenberg_plays.py --rsync-castable   # caches every cleared text
    python3 tools/build_play_library.py                         # writes out/plays-library/
    python3 tools/build_play_library.py --check                 # build in memory, write nothing, print the report

Output (catalog/out/plays-library/, served at <site>/data/plays/library/):
    index.json              one row per play; the shelf Record browses
    scripts/<id>.json       {"format": 1, "scripts": [<one script entry>]}: the same shape as
                            plays/castable-scripts.json, so one decoder reads both

The id is the record's own (`gut-<Gutenberg ebook number>`), never reissued; a script whose
text changes keeps its id and gets a new `revision`. A play split out of a collected volume is
`gut-<ebook>-<n>`, n counting every play the volume holds in text order (script_parse.split_volume).
The same work under several ids is kept once (dedupe); every drop is listed in the report.
"""
import collections
import datetime
import gzip
import json
import math
import os
import re
import sys
import zlib

sys.path.insert(0, os.path.dirname(__file__))
import build_castable_scripts as B
import script_parse as P
import script_rights as R

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "out", "plays-library")
BUNDLE = os.path.join(HERE, "..", "plays", "castable-scripts.json")
FORMAT = 1
WORDS_PER_MINUTE = 150


def failure_reason(rights, parsed):
    """Why a rights-cleared text is not in the library: one reason, the first that applies."""
    if not rights["castable"]:
        return "rights_" + rights["bucket"]
    if parsed.get("status") == "stub":
        return "stub_" + parsed.get("stub_kind", "?")
    if parsed.get("status") != "parsed":
        return "parse_" + ",".join(parsed.get("issues") or [parsed.get("status", "?")])
    for issue in ("several_plays_in_one_text", "fewer_than_two_castable_roles", "mostly_set_aside",
                  "unclassified_over_5pct", "role_only_before_play"):
        if issue in parsed["issues"]:
            return "unclean_" + issue
    return "unclean_other"


def title_unusable(entry):
    """A title cut off by the record's own punctuation ("The", "The Collected Works of") names no play,
    nor does the name of a volume ("Hecuba and other plays") shown as if it were one play."""
    words = entry["title"].lower().split()
    if VOLUME_TITLE.search(entry["title"]):
        return True
    return not words or words[-1] in B.SMALL or (len(words) == 1 and "collection" in entry and words[0] in B.SMALL)


NOT_A_TITLE = re.compile(r"\b(PRINTERS?|PUBLISHERS?|LTD|COPYRIGHT|CONTENTS|ILLUSTRATIONS?|CURTAIN|FINIS|LITERATURE|"
                         r"DISPOSITION|SCENE)\b|^[IVXL]+[.\s]|^(THE|A|AN|BY)$|^OR\b")
VOLUME_TITLE = re.compile(r"\b(Works|Volume|Vol\.|Collection|Plays|Dramas|Farces|Comediettas|Tragedies|Comedies|Representative)\b|"
                          r"\band other\b|\[", re.I)


def volume_play_title(title, record):
    """The title a volume prints above a play, cased for a list, or None when it names no play: a
    bare article, a section or publisher line, a roman-numeral heading, or the name of the volume's
    author or translator (a half-title page, not a play)."""
    if not title:
        return None
    printed = title.strip(" ;:,.")
    if not printed or NOT_A_TITLE.search(printed):
        return None
    names = set()
    for who in (record.get("authors") or []) + (record.get("translators") or []):
        for tok in re.split(r"[\s,()]+", who.get("name") or ""):
            if len(tok) > 2:
                names.add(tok.upper().strip("."))
    words = [w.strip(".,;:") for w in printed.upper().split()]
    if names and sum(w in names for w in words) >= max(1, len(words) - 1):
        return None
    return B.cased_title(printed)


def is_volume(raw, record):
    """A text the whole-text parse passed as one play that is really a volume: two or more of the plays
    split_volume finds each parse clean under a printed title."""
    segs = P.split_volume(raw)
    if len(segs) < 2:
        return False
    whole = 0
    for _, title, text in segs:
        if volume_play_title(title, record) and P.parse(text, "stage").get("clean"):
            whole += 1
            if whole == 2:
                return True
    return False


BARE_HONORIFIC = re.compile(r"^(MRS?|MISS|MS|DR|ST|MME|MLLE)\.?$")
HEADING_ROLE = re.compile(r"^(THE (SUBJECT|SUMMARY|ARGUMENT)\b|(ANTI)?STROPHE\b|EPODE\b|TABLEAU\b|DIALOGUE$|(FIRST|SECOND|THIRD|FOURTH|FIFTH) (SCENE|ACT)$)")


def role_artifact(entry):
    """A role the parser read out of something that is not a speaker: a bare honorific (a cast list's
    "MRS. CRILLY" split at the period), the play's own title, a translator's heading, or a chorus
    or tableau marker. Names it, or None."""
    title = entry["title"].upper().strip(" .")
    for r in entry["roles"]:
        name = r["name"].upper().strip(" .")
        if BARE_HONORIFIC.match(name) or HEADING_ROLE.match(name) or name == title or name == "THE " + title:
            return r["name"]
    return None


def volume_entries(record, rights, raw, report):
    """The plays of a collected volume that parse clean, as script entries `gut-<ebook>-<n>`. Only a
    volume with one named author is split (the volume's author is each play's author; an anthology
    does not say which of its authors wrote which). Rights are the volume's own evidence."""
    if len(record.get("authors") or []) != 1:
        report["volumes_held_not_one_author"] = report.get("volumes_held_not_one_author", 0) + 1
        return []
    out = []
    for n, title, text in P.split_volume(raw):
        report["split_segments"] = report.get("split_segments", 0) + 1
        parsed = P.parse(text, "stage")
        why = None
        printed = volume_play_title(title, record)
        if parsed.get("status") != "parsed":
            why = "split_not_a_play"
        elif not printed:
            why = "split_no_printed_title"
        elif not B.offered(rights, parsed):
            why = "split_" + failure_reason(rights, parsed)
        if why:
            report["split_failures"][why] = report["split_failures"].get(why, 0) + 1
            continue
        entry = B.script_entry({**record, "id": f"{record['id']}-{n}"}, rights, parsed)
        entry["collection"] = B.clean_title(record["title"])
        entry["title"] = B.clean_title(printed)
        entry["sort_name"] = B.sort_name(entry["title"])
        if role_artifact(entry):
            report["split_failures"]["split_role_artifact"] = report["split_failures"].get("split_role_artifact", 0) + 1
            continue
        if title_unusable(entry):
            report["split_failures"]["split_title_cut_off_or_a_volume"] = report["split_failures"].get(
                "split_title_cut_off_or_a_volume", 0) + 1
            continue
        out.append(entry)
    return out


SHINGLE, SAMPLE = 5, 4
SAME_WORK = 0.55
SIMILAR_SIZE = 0.4
SAME_TITLE_AND_AUTHOR = 0.2


def shingles(entry):
    words = []
    for l in entry["lines"]:
        if l["kind"] == "speech":
            words += re.findall(r"[a-z0-9']+", " ".join(p["say"] for p in l["parts"] if "say" in p).lower())
    return {h for h in (zlib.crc32(" ".join(words[i:i + SHINGLE]).encode()) for i in range(len(words) - SHINGLE + 1))
            if h % SAMPLE == 0}


def work_key(entry):
    title = re.split(r"[;:]| or,? ", entry["title"].lower())[0]
    title = re.sub(r"^(the|a|an)\s+", "", re.sub(r"[^a-z0-9 ]", "", title)).strip()
    return title, tuple(sorted(a["name"] for a in entry["authors"] if a.get("name")))


def prefer(entry, protect):
    """Higher wins: a bundled play (never reissued), then a single-play text over a volume's
    play, then the fuller cast list, then the longer text, then the lower ebook number."""
    voices = sum(1 for r in entry["roles"] if r["lines"] >= P.CASTABLE_LINES)
    words = sum(r["words"] for r in entry["roles"])
    ebook = [int(x) for x in entry["id"][4:].split("-")]
    return (entry["id"] in protect, "collection" not in entry or entry["id"][4:].isdigit(), voices, words,
            [-x for x in ebook])


def dedupe(entries, protect=()):
    """One entry per work. Entries are taken best first (see prefer) and one is dropped when it is the
    same work as an entry already kept: its spoken text overlaps the kept one's by at least SAME_WORK of
    the smaller (5-word shingles, sampled), or by SAME_TITLE_AND_AUTHOR when the normalized title and
    the authors also match (two editors' texts of one play share about a third of their shingles).
    Texts of very different length are never the same work, so a bundle never swallows its plays.
    Returns (kept, rows for the report, same title and author with different text: reported, kept)."""
    sh = {e["id"]: shingles(e) for e in entries}
    keyed = {e["id"]: work_key(e) for e in entries}
    by_hash = collections.defaultdict(list)
    for eid in sorted(sh):
        for h in sh[eid]:
            by_hash[h].append(eid)
    common = collections.Counter()
    for ids in by_hash.values():
        for i, x in enumerate(ids):
            for y in ids[i + 1:]:
                common[(x, y)] += 1
    near = collections.defaultdict(dict)
    for (x, y), n in sorted(common.items()):
        small, big = sorted((len(sh[x]), len(sh[y])))
        c = n / max(1, small)
        if small / max(1, big) >= SIMILAR_SIZE and (c >= SAME_WORK or (
                c >= SAME_TITLE_AND_AUTHOR and keyed[x] == keyed[y] and keyed[x][1])):
            near[x][y] = near[y][x] = round(c, 3)
    kept, rows, kept_ids = [], [], set()
    for e in sorted(entries, key=lambda e: prefer(e, protect), reverse=True):
        hit = sorted((k for k in near[e["id"]] if k in kept_ids), key=lambda k: -near[e["id"]][k])
        if not hit:
            kept.append(e)
            kept_ids.add(e["id"])
            continue
        k = next(x for x in kept if x["id"] == hit[0])
        rows.append({"kept": k["id"], "dropped": e["id"], "title": e["title"], "kept_title": k["title"],
                     "overlap": near[e["id"]][k["id"]],
                     "reason": "same work; kept " + ("the bundled play" if k["id"] in protect else
                               "the single-play text" if "collection" in e and "collection" not in k
                               else "the fuller cast and text")})
    rows.sort(key=lambda r: (r["kept"], r["dropped"]))
    keys = collections.defaultdict(list)
    for e in kept:
        keys[keyed[e["id"]]].append(e["id"])
    shared = [sorted(ids) for k, ids in sorted(keys.items()) if len(ids) > 1 and k[1]]
    return kept, rows, shared


def index_row(entry):
    voices = sum(1 for r in entry["roles"] if r["lines"] >= P.CASTABLE_LINES)
    words = sum(r["words"] for r in entry["roles"])
    row = {
        "id": entry["id"],
        "revision": entry["revision"],
        "title": entry["title"],
        "sort_name": entry["sort_name"],
        "kind": entry["kind"],
        "authors": [a["display"] for a in entry["authors"] if a.get("display")],
        "voices": voices,
        "roles": len(entry["roles"]),
        # Each named role's speeches, largest first: the cast window and fingerprint a list draws
        # without fetching the script (Decision 076, WEB-DESIGN §4.15).
        "cast": sorted((r["lines"] for r in entry["roles"]), reverse=True),
        "lines": sum(1 for l in entry["lines"] if l["kind"] == "speech"),
        "words": words,
        "minutes": max(1, math.ceil(words / WORDS_PER_MINUTE)),
        "rights": entry["rights"],
        "source": entry["source"],
        "path": f"scripts/{entry['id']}.json",
    }
    if "year" in entry:
        row["year"] = entry["year"]
    if "collection" in entry:
        row["collection"] = entry["collection"]
    return row


def script_file(entry):
    return {"format": FORMAT, "scripts": [entry]}


def build(plays, ctx, read_text, protect=()):
    """plays: harvest records; read_text(id) -> text or None. Returns (entries, report)."""
    entries, failures, seen, uncached = [], {}, 0, 0
    report = {"split_failures": {}}
    for p in sorted(plays, key=lambda x: x["id"]):
        record = R.from_gutenberg(p)
        rights = R.judge(record, ctx)
        if not rights["castable"]:
            continue
        text = read_text(p["id"][4:])
        if text is None:
            uncached += 1
            continue
        seen += 1
        parsed = P.parse(text, record["kind"])
        if record["kind"] == "stage" and parsed.get("status") == "parsed" and p["id"] not in protect and (
                "several_plays_in_one_text" in parsed["issues"] or (parsed.get("clean") and is_volume(text, record))):
            report["volumes"] = report.get("volumes", 0) + 1
            split = volume_entries(record, rights, text, report)
            report["split_clean"] = report.get("split_clean", 0) + len(split)
            entries += split
            continue
        entry = B.script_entry(record, rights, parsed) if B.offered(rights, parsed) else None
        if entry and VOLUME_TITLE.search(entry["title"]):
            printed = volume_play_title(parsed.get("printed_title"), record)
            if printed:
                entry["collection"] = B.clean_title(record["title"])
                entry["title"] = B.clean_title(printed)
                entry["sort_name"] = B.sort_name(entry["title"])
        if entry and title_unusable(entry):
            failures["unclean_title_cut_off"] = failures.get("unclean_title_cut_off", 0) + 1
        elif entry:
            entries.append(entry)
        else:
            why = failure_reason(rights, parsed)
            failures[why] = failures.get(why, 0) + 1
    report["split_failures"] = dict(sorted(report["split_failures"].items()))
    report["single_play_texts_with_a_role_artifact"] = sorted(e["id"] for e in entries if role_artifact(e))
    before = len(entries)
    entries, dups, same_title = dedupe(entries, set(protect))
    entries.sort(key=lambda s: (s["sort_name"], s["id"]))
    report.update({"rights_cleared_uncached": uncached, "parsed": seen, "clean": len(entries),
                   "clean_before_dedupe": before, "failures": dict(sorted(failures.items())),
                   "duplicates_dropped": dups, "same_title_and_author_different_text_kept": same_title})
    return entries, report


def index_doc(entries, report):
    return {"format": FORMAT, "count": len(entries), "wordsPerMinute": WORDS_PER_MINUTE,
            "report": report, "plays": [index_row(e) for e in entries]}


def write(entries, report, out=OUT):
    os.makedirs(os.path.join(out, "scripts"), exist_ok=True)
    keep = set()
    for e in entries:
        name = f"{e['id']}.json"
        keep.add(name)
        with open(os.path.join(out, "scripts", name), "w", encoding="utf-8") as f:
            json.dump(script_file(e), f, ensure_ascii=False, separators=(",", ":"))
            f.write("\n")
    for name in sorted(os.listdir(os.path.join(out, "scripts"))):
        if name not in keep:
            os.remove(os.path.join(out, "scripts", name))
    with open(os.path.join(out, "index.json"), "w", encoding="utf-8") as f:
        json.dump(index_doc(entries, report), f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")


def main():
    ev = json.load(open(R.EDITORIAL))
    ren = json.load(gzip.open(os.path.join(R.CACHE, "cce_drama_renewals.json.gz"), "rt"))
    ctx = {"renewals": R.renewal_index(ren), "takedowns": ev.get("takedowns", {}), "today": datetime.date.today()}
    plays = json.load(open(os.path.join(R.CACHE, "gutenberg", "plays.json")))["plays"]
    text_dir = os.path.join(R.CACHE, "gutenberg", "text")

    def read_text(pid):
        path = os.path.join(text_dir, pid + ".txt")
        return open(path, encoding="utf-8", errors="replace").read() if os.path.exists(path) else None

    bundled = {s["id"] for s in json.load(open(BUNDLE))["scripts"]}
    entries, report = build(plays, ctx, read_text, bundled)
    missing = sorted(bundled - {e["id"] for e in entries})
    report["bundled"] = len(bundled)
    report["bundled_missing_from_library"] = missing
    print(json.dumps(report, indent=1))
    if missing:
        sys.exit("a bundled play is not in the library: " + ", ".join(missing))
    if "--check" not in sys.argv:
        write(entries, report)
        size = sum(os.path.getsize(os.path.join(OUT, "scripts", n)) for n in os.listdir(os.path.join(OUT, "scripts")))
        print(f"wrote {len(entries)} scripts, {size} bytes, to {os.path.relpath(OUT)}", file=sys.stderr)


if __name__ == "__main__":
    main()
