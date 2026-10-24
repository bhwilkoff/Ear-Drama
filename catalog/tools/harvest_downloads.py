"""archive.org's own download count for every harvested item (Decision 067: Listen's
popularity shelf is data, never a pick).

    python3 tools/harvest_downloads.py [--batch 100] [--pause 1.0] [--limit N]

Reads the identifiers in .cache/meta/ and asks advancedsearch for each batch's
`downloads` field (`identifier:(a OR b ...)`, the small batched lookup the
internet-archive-source skill names; one call at a time, a pause between, the
honest User-Agent of ia_lib). Writes .cache/downloads.json:
{"fetched_at", "items": {id: downloads}, "unread": [ids]}. A batch that could not
be read leaves its ids in `unread` and keeps the counts a previous run read; it is
never written as zero (a throttled call is not "nobody listened"). build_db.py
reads this file over the counts the seed scrape kept in seeds.json.
"""
import argparse
import datetime
import glob
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import ia_lib as ia

OUT = os.path.join(ia.CACHE, "downloads.json")


def identifiers():
    return sorted(os.path.basename(p)[: -len(".json.gz")] for p in glob.glob(os.path.join(ia.CACHE, "meta", "*.json.gz")))


def query(ids):
    return "identifier:(" + " OR ".join('"' + i.replace('"', "") + '"' for i in ids) + ")"


def read_batch(ids, pause, get=ia.get):
    """{id: downloads} for the ids archive.org answered, or None when the call could not be read."""
    d = get(ia.ADV, {"q": query(ids), "fl[]": ["identifier", "downloads"], "rows": len(ids) + 10,
                     "output": "json"}, pause=pause)
    if d is None or "response" not in d:
        return None
    return {r["identifier"]: r["downloads"] for r in d["response"].get("docs", [])
            if isinstance(r.get("downloads"), int) and r.get("identifier") in ids}


def harvest(ids, batch, pause, previous=None, get=ia.get):
    items = dict((previous or {}).get("items") or {})
    unread = []
    for k in range(0, len(ids), batch):
        part = ids[k:k + batch]
        got = read_batch(part, pause, get)
        if got is None:
            unread += part
            continue
        items.update(got)
    return {"fetched_at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
            "items": dict(sorted(items.items())), "unread": unread}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--batch", type=int, default=100)
    ap.add_argument("--pause", type=float, default=1.0)
    ap.add_argument("--limit", type=int)
    a = ap.parse_args()
    ids = identifiers()[: a.limit] if a.limit else identifiers()
    previous = ia.read_json(OUT) if os.path.exists(OUT) else None
    doc = harvest(ids, a.batch, a.pause, previous)
    ia.write_json(OUT, doc)
    print(f"downloads: {len(doc['items'])} items counted of {len(ids)}; {len(doc['unread'])} unread")
    return 1 if doc["unread"] and len(doc["unread"]) == len(ids) else 0


if __name__ == "__main__":
    sys.exit(main())
