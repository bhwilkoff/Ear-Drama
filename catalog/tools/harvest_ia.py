"""Enumerate archive.org's old-time radio items and cache a slim copy of each
item's metadata (item fields + per-file audio rows + review summary).

    python3 tools/harvest_ia.py [--workers 3] [--limit N] [--refresh] [--ids FILE]

Beyond the five seeds it enumerates editorial/extra_seeds.json (written by
tools/discover_corpus.py): its "queries" are scraped like seeds, its "ids" are
taken as given. --ids adds a file of identifiers (one per line). An item whose
metadata discover_corpus already fetched is copied from .cache/discover/meta/
rather than fetched twice.

Seeds and the never-enumerate list come from docs/research/radio/07 (MEASURED
2026-10-17). Output: .cache/seeds.json, .cache/meta/<id>.json.gz,
.cache/harvest_report.json (counts, and every item that could not be read).
"""
import argparse
import concurrent.futures as cf
import os
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
import ia_lib as ia

SEEDS = {
    "oldtimeradio": "collection:oldtimeradio",
    "otrr_ids": "identifier:OTRR_*",
    "subject_otr": 'subject:"old time radio"',
    "subject_otrr": 'subject:"otrr"',
    "lumedwards": "collection:lumedwards",
}
FIELDS = "identifier,mediatype,collection,downloads,item_size,title"
AUDIO_EXT = (".mp3", ".ogg", ".flac", ".wav", ".m4a", ".opus", ".wma", ".aiff")
TEXT_SUFFIX = (".vtt", ".srt", "_asr.txt", ".asr.json")
ITEM_KEYS = ("identifier", "title", "creator", "date", "year", "subject", "collection",
             "licenseurl", "rights", "uploader", "publicdate", "addeddate", "mediatype",
             "language", "description", "contributor", "publisher", "source", "notes")
FILE_KEYS = ("name", "source", "format", "size", "length", "md5", "title", "album",
             "track", "creator", "artist", "genre", "original", "private", "bitrate")


def load_extra(ids_file=None):
    """(queries {name: q}, ids {id: seed label}) from extra_seeds.json and --ids."""
    queries, ids = {}, {}
    path = os.path.join(ia.EDITORIAL, "extra_seeds.json")
    if os.path.exists(path):
        ex = ia.read_json(path)
        queries = dict(ex.get("queries") or {})
        for i in ex.get("ids") or {}:
            ids[i] = "extra_seeds"
    if ids_file:
        with open(ids_file) as f:
            for line in f:
                if line.strip() and not line.startswith("#"):
                    ids.setdefault(line.strip(), "ids_file")
    return queries, ids


def enumerate_seeds(extra_queries=None, extra_ids=None):
    ids = {}
    counts = {}
    for name, q in list(SEEDS.items()) + list((extra_queries or {}).items()):
        n = 0
        for it in ia.scrape(q, FIELDS):
            ids.setdefault(it["identifier"], {"seeds": [], "mediatype": it.get("mediatype"),
                                              "downloads": it.get("downloads"),
                                              "item_size": it.get("item_size")})
            ids[it["identifier"]]["seeds"].append(name)
            n += 1
        expected = ia.num_found(q)
        counts[name] = {"scraped": n, "numFound": expected}
        if expected is not None and n < expected * 0.98:
            raise RuntimeError(f"seed {name}: scraped {n} of numFound {expected}")
        print(f"seed {name}: {n} (numFound {expected})", file=sys.stderr)
    added = 0
    for i, label in (extra_ids or {}).items():
        if i not in ids:
            added += 1
        ids.setdefault(i, {"seeds": []})["seeds"].append(label)
    counts["extra_ids"] = {"listed": len(extra_ids or {}), "new": added}
    print(f"extra ids: {len(extra_ids or {})} listed, {added} not in any seed", file=sys.stderr)
    return ids, counts


def slim(md):
    m = md.get("metadata") or {}
    item = {k: m[k] for k in ITEM_KEYS if k in m}
    if isinstance(item.get("description"), str):
        item["description"] = item["description"][:4000]
    files, texts = [], []
    for f in md.get("files") or []:
        n = f.get("name", "")
        low = n.lower()
        if low.endswith(AUDIO_EXT):
            files.append({k: f[k] for k in FILE_KEYS if k in f})
        elif low.endswith(TEXT_SUFFIX):
            texts.append(n)
    revs = md.get("reviews") or []
    stars = [float(r["stars"]) for r in revs if str(r.get("stars", "")).replace(".", "").isdigit()]
    return {"item": item, "files": files, "transcripts": texts,
            "is_dark": bool(md.get("is_dark")), "server": md.get("server"),
            "reviews": {"count": len(revs),
                        "avg_stars": round(sum(stars) / len(stars), 2) if stars else None,
                        "texts": [{"title": r.get("reviewtitle"), "body": (r.get("reviewbody") or "")[:1500],
                                   "stars": r.get("stars"), "date": r.get("reviewdate")} for r in revs[:50]]}}


def fetch(ident, refresh):
    path = os.path.join(ia.CACHE, "meta", ident + ".json.gz")
    if os.path.exists(path) and not refresh:
        return ident, "cached"
    found = os.path.join(ia.CACHE, "discover", "meta", ident + ".json.gz")
    if os.path.exists(found) and not refresh:
        ia.write_json(path, ia.read_json(found), gz=True)
        return ident, "copied"
    md = ia.get(ia.META + ident, timeout=120)
    if md is None:
        return ident, "failed"
    if not md:
        return ident, "empty"
    ia.write_json(path, slim(md), gz=True)
    return ident, "fetched"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--limit", type=int)
    ap.add_argument("--refresh", action="store_true")
    ap.add_argument("--ids", help="file of extra archive.org identifiers, one per line")
    a = ap.parse_args()
    t0 = time.time()
    xq, xi = load_extra(a.ids)
    ids, counts = enumerate_seeds(xq, xi)
    ia.write_json(os.path.join(ia.CACHE, "seeds.json"), {"counts": counts, "items": ids})
    todo = sorted(ids)[: a.limit] if a.limit else sorted(ids)
    status = {}
    with cf.ThreadPoolExecutor(a.workers) as ex:
        for i, (ident, st) in enumerate(ex.map(lambda x: fetch(x, a.refresh), todo), 1):
            status[ident] = st
            if i % 250 == 0:
                print(f"{i}/{len(todo)} {time.time() - t0:.0f}s", file=sys.stderr, flush=True)
    tally = {s: sum(1 for v in status.values() if v == s) for s in set(status.values())}
    report = {"seeds": counts, "unique_items": len(ids), "attempted": len(todo), "status": tally,
              "failed": sorted(k for k, v in status.items() if v in ("failed", "empty")),
              "seconds": round(time.time() - t0)}
    ia.write_json(os.path.join(ia.CACHE, "harvest_report.json"), report)
    print(report["status"], file=sys.stderr)
    # A harvest that read nothing new and cached nothing is a failed harvest.
    if not tally.get("fetched") and not tally.get("cached") and not tally.get("copied"):
        sys.exit(1)


if __name__ == "__main__":
    main()
