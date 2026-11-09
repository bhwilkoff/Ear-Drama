"""The lead of each matched series' English Wikipedia article, for its "about" text.

    python3 tools/harvest_ext_wikipedia_about.py [--db out/radio-catalog.sqlite]   # after enrich_external.py
    python3 tools/harvest_ext_wikipedia_about.py --report                         # the match list, no fetching

Reads every `series_wikidata` row with an English article (enrich_external.py's
evidence-gated Wikidata match) and asks en.wikipedia.org's Action API, 20 titles a
request, for the plain-text intro (`prop=extracts&exintro&explaintext`), the page's
own Wikidata id and short description (`pageprops`), and its canonical URL. Raw
answers are cached under .cache/wikipedia/about_api/ (harvest_ext_wm.call), so a
rerun resumes; Wikipedia's terms are CC BY-SA 4.0 and every row keeps its URL.

Writes .cache/wikipedia/about.json, {"pages": {asked title: {title, qid, shortdesc,
extract, url, revid, fetched, missing, disambiguation}}}: what Wikipedia said, not
what we decided. series_about.py decides (in enrich_external.py) and --report prints
each series' verdict and evidence. Exits non-zero when no page could be read.
"""
import argparse
import datetime
import json
import os
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ia_lib import CACHE, OUT, write_json  # noqa: E402
import harvest_ext_wm as wm  # noqa: E402
import series_about as SA  # noqa: E402

PATH = os.path.join(CACHE, "wikipedia", "about.json")
BATCH = 20   # TextExtracts' limit for whole intros per request


def load(path=PATH):
    try:
        return json.load(open(path, encoding="utf-8"))
    except FileNotFoundError:
        return None


def fetch(titles, old):
    pages, today = {}, datetime.date.today().isoformat()
    titles = sorted(set(titles))
    for i in range(0, len(titles), BATCH):
        chunk = titles[i:i + BATCH]
        d = wm.call(wm.EN_API, {"action": "query", "format": "json", "formatversion": "2",
                                "prop": "extracts|pageprops|info", "inprop": "url", "exintro": "1",
                                "explaintext": "1", "exlimit": "max", "redirects": "1",
                                "ppprop": "wikibase_item|wikibase-shortdesc|disambiguation",
                                "titles": "|".join(chunk)}, cache_dir="wikipedia/about_api")
        if d is None:
            continue
        q = d.get("query", {})
        to = {}
        for kind in ("normalized", "redirects"):
            for r in q.get(kind, []):
                to[r["from"]] = r["to"]
        by_title = {p["title"]: p for p in q.get("pages", [])}
        for t in chunk:
            r = t
            for _ in range(3):
                r = to.get(r, r)
            p = by_title.get(r)
            if p is None:
                continue
            pp = p.get("pageprops", {})
            row = {"title": p["title"], "qid": pp.get("wikibase_item"), "shortdesc": pp.get("wikibase-shortdesc"),
                   "extract": p.get("extract"), "url": p.get("canonicalurl") or p.get("fullurl"),
                   "revid": p.get("lastrevid"), "missing": bool(p.get("missing")),
                   "disambiguation": "disambiguation" in pp}
            prev = (old or {}).get(t)
            row["fetched"] = prev["fetched"] if prev and prev.get("revid") == row["revid"] else today
            pages[t] = row
        print(f"  about {min(i + BATCH, len(titles))}/{len(titles)}", flush=True)
    return pages


def rows(db):
    return list(db.execute("SELECT w.series_key, w.qid, w.enwiki, w.confidence, w.match_evidence, w.in_db, "
                           "s.name, s.first_date, s.last_date FROM series_wikidata w "
                           "LEFT JOIN series s ON s.key = w.series_key WHERE w.enwiki IS NOT NULL ORDER BY w.series_key"))


def report(db, pages):
    kept, dropped = [], {}
    rejects = SA.load_rejects()
    year = lambda d: int(d[:4]) if d and d[:4].isdigit() else None  # noqa: E731
    for key, qid, enwiki, conf, ev, in_db, name, first, last in rows(db):
        if not in_db:
            continue
        page = pages.get(enwiki)
        about, why = SA.about_of(page, qid, (year(first), year(last)), SA.rejected_for(rejects, key, page))
        e = json.loads(ev)
        line = (f"{key} | {name} {str(first)[:4]}-{str(last)[:4]} | {qid} {enwiki!r} | {e.get('name_kind')} "
                f"years={e.get('years')} wd={e.get('wd_years')} conf={conf} | "
                f"{(pages.get(enwiki) or {}).get('shortdesc')!r}")
        if about:
            kept.append(line)
        else:
            dropped.setdefault(why, []).append(line)
    print(f"KEPT {len(kept)}")
    for ln in kept:
        print("  " + ln)
    for why, lns in sorted(dropped.items()):
        print(f"DROPPED {why}: {len(lns)}")
        for ln in lns:
            print("  " + ln)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=os.path.join(OUT, "radio-catalog.sqlite"))
    ap.add_argument("--report", action="store_true", help="print the match list from the cache; fetch nothing")
    a = ap.parse_args()
    db = sqlite3.connect(f"file:{a.db}?mode=ro", uri=True)
    old = (load() or {}).get("pages", {})
    if a.report:
        report(db, old)
        return
    titles = {r[2] for r in rows(db)}
    pages = fetch(titles, old)
    write_json(PATH, {"source": "https://en.wikipedia.org/w/api.php (prop=extracts, exintro, explaintext)",
                      "license": SA.LICENSE, "pages": dict(sorted(pages.items()))})
    write_json(os.path.join(CACHE, "wikipedia", "about_failed.json"), wm.FAILED)
    print(f"{len(pages)} of {len(titles)} articles read, {len(wm.FAILED)} failed requests")
    if not pages:
        sys.exit(1)


if __name__ == "__main__":
    main()
