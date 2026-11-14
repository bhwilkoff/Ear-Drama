"""Build the castable-scripts file the apps bundle for plays phase 1 (PLAYS-DESIGN §3, §8 rule 1).

A script is written only when script_rights.judge returns `castable` AND its text
parses clean (script_parse). Nothing here writes a word: every line is the
parser's exact slices, and the rights line is the record's own evidence.

Phase 1 bundles the file in the apps (it works offline, and nothing is fetched to
cast a play); it moves beside the catalog once the library outgrows a bundle.
Only the BUNDLE_IDS plays are read, and the file is refused unless all of them parse clean, so a
fuller text cache never grows the bundle:

    python3 tools/build_castable_scripts.py              # writes plays/castable-scripts.json
"""
import datetime
import gzip
import hashlib
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import script_parse as P
import script_rights as R
from sort_name import sort_name

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "plays", "castable-scripts.json")
FORMAT = 1
# The bundle is these plays and no others (the library, build_play_library.py, holds the rest). A
# change to this list is a change to what every app ships and needs a new Decision.
BUNDLE_IDS = ("gut-49295", "gut-7364", "gut-28051", "gut-12039", "gut-2265", "gut-67583", "gut-1502", "gut-27357",
              "gut-5071", "gut-28527", "gut-47826", "gut-49916", "gut-54702", "gut-28511", "gut-76327")


def compact_line(line):
    out = {"id": line["id"], "kind": line["kind"]}
    if line["kind"] == "speech":
        out["role"] = line["role"]
        out["parts"] = line["parts"]
    else:
        out["source"] = line["source"]
    return out


COLLECTION = re.compile(r"\b(Works|Volume|Vol\.|Collection)\b", re.I)
SMALL = {"a", "an", "and", "as", "at", "by", "for", "in", "of", "on", "or", "the", "to"}


def display_title(record, parsed):
    """The record's title, unless the record names a collected volume and the text prints
    the play's own title: then that title, cased for a list, and the volume kept beside it."""
    printed = parsed.get("printed_title")
    if not (COLLECTION.search(record["title"]) and printed):
        return record["title"], None
    return cased_title(printed), record["title"]


def cased_title(printed):
    words = printed.lower().split()
    return " ".join(w if i and w in SMALL else w[:1].upper() + w[1:] for i, w in enumerate(words))


CATALOG_NOTE = re.compile(r",?\s+with\s+(?:notes|an?\s+introduction|introduction|a\s+commentary)\b.*$", re.I)


def clean_title(title):
    """A catalog title without its cataloguer's boilerplate ("..., with Notes and Introduction") or stray spaces."""
    return re.sub(r"\s{2,}", " ", CATALOG_NOTE.sub("", title or "")).strip()


def author_display(name):
    """"Baker, George M. (George Melville)" -> "George Melville Baker": the record's own parenthetical fills the
    initials it follows, and the surname moves last. A name with no comma is returned as it is."""
    if not name or "," not in name:
        return name
    last, rest = (p.strip() for p in name.split(",", 1))
    full = re.search(r"\(([^)]+)\)", rest)
    given = full.group(1).strip() if full else rest
    return f"{given} {last}".strip()


def script_entry(record, rights, parsed):
    lines = [compact_line(l) for l in parsed["lines"]]
    body = json.dumps(lines, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    title, collection = display_title(record, parsed)
    title = clean_title(title)
    return {
        "id": record["id"],
        "revision": hashlib.sha256(body.encode()).hexdigest()[:12],
        "kind": record["kind"],
        "title": title,
        "sort_name": sort_name(title),
        **({"collection": collection} if collection else {}),
        # A play is marked only by facts from its record (Decision 067): the year is the
        # record's own publication year, never estimated.
        **({"year": record["published"]["year"]} if (record.get("published") or {}).get("year") else {}),
        "authors": [{"name": a.get("name"), "display": author_display(a.get("name")), "born": a.get("born"), "died": a.get("died")}
                    for a in record.get("authors") or []],
        "source": {"name": record["source"]["name"], "url": record["source"]["url"]},
        "rights": {"bucket": rights["bucket"], "evidence": rights["evidence"]},
        "roles": [{"name": r["name"], "lines": r["lines"], "words": r["words"]} for r in parsed["roles"]],
        "lines": lines,
        # Printed act and scene headings the parser set aside, verbatim, each at the line it opens
        # (Decision 076, S0). A heading printed as a stage direction stays a line.
        **({"sections": parsed["sections"]} if parsed.get("sections") else {}),
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
        if p["id"] not in BUNDLE_IDS:
            continue
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
    scripts.sort(key=lambda s: (s["sort_name"], s["id"]))
    if sorted(s["id"] for s in scripts) != sorted(BUNDLE_IDS):
        sys.exit("the bundle must be exactly BUNDLE_IDS; missing: " + ", ".join(sorted(set(BUNDLE_IDS) - {s["id"] for s in scripts})))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump({"format": FORMAT, "scripts": scripts}, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")
    print(json.dumps({"texts_read": seen, "written": len(scripts), "skipped": skipped,
                      "bytes": os.path.getsize(OUT)}), file=sys.stderr)


if __name__ == "__main__":
    main()
