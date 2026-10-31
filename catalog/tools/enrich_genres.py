#!/usr/bin/env python3
"""POST-BUILD step: a genre for a series no OTRRpedia label, RadioEchoes tag or LibriVox listing
places, from evidence its own records carry (catalog DECISIONS 024). Reads caches only (no network):
.cache/meta/<archive id>.json.gz (archive.org's own metadata, harvest_ia.py) and
.cache/wikidata/items.json.gz. Adds ONLY its own table to out/radio-catalog.sqlite, dropping and
rebuilding it each run:

  series_genre   (series_key, genre, source, evidence, items)
                 source   wikidata:genre | archive.org
                 evidence JSON: the Wikidata genre labels, or {word: items that carry it} where a
                          word is "subject:<keyword>" or "file:<ID3 genre>"
                 items    how many archive.org items the series' default copies come from

A series gets a Wikidata genre when its item is matched on more than its title
(art_policy.series_identity: the years or the network) and its `genre` statements map to exactly
one of the eight (genres.WIKIDATA). Else it gets the one genre that more than half of its items
name in their own keywords or file genre tag (genres.archive_genre). An item counts only when every
served default copy in it belongs to this one series: a day's broadcasts or a collector's compilation
carries keywords for the item, not for any one program in it. Two genres that both pass, or none,
leave the series unassigned: never a guess from a title, and not knowing is not a genre. A series genres.genre_of already places keeps that genre; this step never changes it.

Run: python3 tools/enrich_genres.py
"""
import collections
import json
import os
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ia_lib as L
import art_policy as AP
import genres as G

DB = os.path.join(L.OUT, "radio-catalog.sqlite")
if "--db" in sys.argv:
    DB = sys.argv[sys.argv.index("--db") + 1]
META = os.path.join(L.CACHE, "meta")
WD = os.path.join(L.CACHE, "wikidata", "items.json.gz")
REPORT = os.path.join(L.OUT, "enrich_genres_report.json")
SERVED = ("keep_clean", "keep_unclaimed")


def terms(value):
    """archive.org's subject field: a string or a list; a string may hold several keywords."""
    parts = [value] if isinstance(value, str) else list(value or [])
    return [t.strip() for p in parts for q in p.split(";") for t in q.split(",") if t.strip()]


def item_record(archive_id, files):
    """(subjects, genre tags of the named files) from the cached metadata, or None."""
    path = os.path.join(META, archive_id + ".json.gz")
    if not os.path.exists(path):
        return None
    j = L.read_json(path)
    it = j.get("item") or {}
    tags = [f.get("genre") for f in j.get("files") or [] if f.get("name") in files and f.get("genre")]
    return terms(it.get("subject")), tags


def wikidata_genre(labels_json):
    """The one genre every mapped statement agrees on, or None; and the labels read."""
    rows = json.loads(labels_json or "[]")
    mapped = {G.WIKIDATA[r["qid"]] for r in rows if r.get("qid") in G.WIKIDATA}
    return (mapped.pop() if len(mapped) == 1 else None), [r.get("label") for r in rows]


def run(con):
    existing = {}
    for key, otrr, re_tag, lv in con.execute("SELECT key, genres_otrr, genre, is_librivox FROM series"):
        existing[key] = G.genre_of(json.loads(otrr) if otrr else None, re_tag, bool(lv))[0]
    nets = {k: json.loads(n) if n else [] for k, n in con.execute("SELECT key, networks FROM series")}
    wd = L.read_json(WD) if os.path.exists(WD) else {}

    served = set()
    files = collections.defaultdict(lambda: collections.defaultdict(set))   # series -> archive id -> file names
    shared = collections.defaultdict(set)                                   # archive id -> series it feeds
    q = ",".join("?" * len(SERVED))
    for key, aid, f in con.execute(
            f"SELECT e.series_key, r.archive_id, r.file FROM episodes e JOIN recordings r "
            f"ON r.episode_id = e.id AND r.rank = 0 WHERE e.state IN ({q})", SERVED):
        files[key][aid].add(f)
        shared[aid].add(key)
        served.add(key)

    rows, stats = [], collections.Counter()
    wikidata = {}
    for key, qid, ev, bc, genre_json in con.execute(
            "SELECT series_key, qid, match_evidence, broadcaster, genre FROM series_wikidata WHERE in_db = 1"):
        g, labels = wikidata_genre(genre_json)
        identity = AP.series_identity(json.loads(ev or "{}"), nets.get(key), [b.get("label") for b in json.loads(bc or "[]")],
                                      (wd.get(qid) or {}).get("description"))
        if g and identity in AP.IDENTITY_SERVED:
            wikidata[key] = (g, labels)
    cache = {}
    for key in sorted(served):
        if existing.get(key):
            continue
        stats["without a genre"] += 1
        if key in wikidata:
            g, labels = wikidata[key]
            rows.append((key, g, "wikidata:genre", json.dumps(labels), len(files[key])))
            stats["wikidata:genre"] += 1
            continue
        per_item, unread = [], 0
        for aid in sorted(files[key]):
            if len(shared[aid]) > 1:
                stats["items shared by several series"] += 1
                continue
            if aid not in cache:
                rec = item_record(aid, files[key][aid])
                cache[aid] = None if rec is None else G.item_genres(*rec)
            if cache[aid] is None:
                unread += 1
            else:
                per_item.append(cache[aid])
        g, words = G.archive_genre(per_item)
        if g:
            rows.append((key, g, "archive.org", json.dumps(dict(sorted(words.items())), ensure_ascii=False), len(per_item)))
            stats["archive.org"] += 1
        else:
            stats["unassigned"] += 1
    return rows, stats


def main():
    con = sqlite3.connect(DB)
    rows, stats = run(con)
    con.executescript("DROP TABLE IF EXISTS series_genre; CREATE TABLE series_genre ("
                      "series_key TEXT PRIMARY KEY, genre TEXT NOT NULL, source TEXT NOT NULL, "
                      "evidence TEXT NOT NULL, items INTEGER NOT NULL)")
    con.executemany("INSERT INTO series_genre VALUES (?,?,?,?,?)", rows)
    con.commit()
    by_genre = collections.Counter(r[1] for r in rows)
    report = {"seriesWithoutGenre": stats["without a genre"], "assigned": len(rows),
              "bySource": {k: stats[k] for k in ("wikidata:genre", "archive.org")},
              "byGenre": dict(sorted(by_genre.items())), "unassigned": stats["unassigned"]}
    L.write_json(REPORT, report)
    print(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
