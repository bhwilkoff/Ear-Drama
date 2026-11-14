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
text changes keeps its id and gets a new `revision`.
"""
import datetime
import gzip
import json
import math
import os
import sys

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
    """A title cut off by the record's own punctuation ("The", "The Collected Works of") names no play."""
    words = entry["title"].lower().split()
    return not words or words[-1] in B.SMALL or (len(words) == 1 and "collection" in entry and words[0] in B.SMALL)


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


def build(plays, ctx, read_text):
    """plays: harvest records; read_text(id) -> text or None. Returns (entries, report)."""
    entries, failures, seen, uncached = [], {}, 0, 0
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
        entry = B.script_entry(record, rights, parsed) if B.offered(rights, parsed) else None
        if entry and title_unusable(entry):
            failures["unclean_title_cut_off"] = failures.get("unclean_title_cut_off", 0) + 1
        elif entry:
            entries.append(entry)
        else:
            why = failure_reason(rights, parsed)
            failures[why] = failures.get(why, 0) + 1
    entries.sort(key=lambda s: (s["sort_name"], s["id"]))
    report = {"rights_cleared_uncached": uncached, "parsed": seen, "clean": len(entries),
              "failures": dict(sorted(failures.items()))}
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

    entries, report = build(plays, ctx, read_text)
    bundled = {s["id"] for s in json.load(open(BUNDLE))["scripts"]}
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
