"""Build the castable-scripts file the apps bundle for plays phase 1 (PLAYS-DESIGN §3, §8 rule 1).

A script is written only when script_rights.judge returns `castable` AND its text
parses clean (script_parse). Nothing here writes a word: every line is the
parser's exact slices, and the rights line is the record's own evidence.

Phase 1 bundles the file in the apps (it works offline, and nothing is fetched to
cast a play); it moves beside the catalog once the library outgrows a bundle.
Only texts already in the cache are read, so the harvest decides what grows it:

    python3 tools/harvest_gutenberg_plays.py --texts N   # caches texts
    python3 tools/build_castable_scripts.py              # writes plays/castable-scripts.json
"""
import datetime
import gzip
import hashlib
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import script_parse as P
import script_rights as R

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "plays", "castable-scripts.json")
FORMAT = 1


def compact_line(line):
    out = {"id": line["id"], "kind": line["kind"]}
    if line["kind"] == "speech":
        out["role"] = line["role"]
        out["parts"] = line["parts"]
    else:
        out["source"] = line["source"]
    return out


def script_entry(record, rights, parsed):
    lines = [compact_line(l) for l in parsed["lines"]]
    body = json.dumps(lines, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return {
        "id": record["id"],
        "revision": hashlib.sha256(body.encode()).hexdigest()[:12],
        "kind": record["kind"],
        "title": record["title"],
        "authors": [{"name": a.get("name"), "born": a.get("born"), "died": a.get("died")}
                    for a in record.get("authors") or []],
        "source": {"name": record["source"]["name"], "url": record["source"]["url"]},
        "rights": {"bucket": rights["bucket"], "evidence": rights["evidence"]},
        "roles": [{"name": r["name"], "lines": r["lines"], "words": r["words"]} for r in parsed["roles"]],
        "lines": lines,
    }


def offered(rights, parsed):
    return rights["castable"] and parsed.get("status") == "parsed" and parsed.get("clean") is True


def main():
    today = datetime.date.today()
    ev = json.load(open(R.EDITORIAL))
    ren = json.load(gzip.open(os.path.join(R.CACHE, "cce_drama_renewals.json.gz"), "rt"))
    ctx = {"renewals": R.renewal_index(ren), "takedowns": ev.get("takedowns", {}), "today": today}
    plays = json.load(open(os.path.join(R.CACHE, "gutenberg", "plays.json")))["plays"]
    text_dir = os.path.join(R.CACHE, "gutenberg", "text")
    scripts, seen, skipped = [], 0, {}
    for p in plays:
        path = os.path.join(text_dir, p["id"][4:] + ".txt")
        if not os.path.exists(path):
            continue
        seen += 1
        record = R.from_gutenberg(p)
        rights = R.judge(record, ctx)
        parsed = P.parse(open(path, encoding="utf-8", errors="replace").read(), record["kind"])
        if offered(rights, parsed):
            scripts.append(script_entry(record, rights, parsed))
        else:
            why = rights["bucket"] if not rights["castable"] else "parse_" + parsed.get("status", "?") + (
                "_unclean" if parsed.get("status") == "parsed" else "")
            skipped[why] = skipped.get(why, 0) + 1
    scripts.sort(key=lambda s: (s["title"].lower(), s["id"]))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump({"format": FORMAT, "scripts": scripts}, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")
    print(json.dumps({"texts_read": seen, "written": len(scripts), "skipped": skipped,
                      "bytes": os.path.getsize(OUT)}), file=sys.stderr)
    if not scripts:
        sys.exit(1)


if __name__ == "__main__":
    main()
