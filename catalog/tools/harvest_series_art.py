"""Show-level pictures for series matched to Wikidata, and how many Wikipedias cover each person.

    python3 tools/harvest_series_art.py                    # items, depicts, pages, dims, sitelinks
    python3 tools/harvest_series_art.py --phase depicts    # one phase
    swiftc -O -o /tmp/face_boxes tools/face_boxes.swift && \
    python3 tools/harvest_series_art.py --phase faces --detector /tmp/face_boxes   # Mac only

Run after enrich_external.py (series_wikidata) and enrich_people_art.py (people_wikidata):
it reads which Wikidata items our series and people were matched to from
out/radio-catalog.sqlite, and writes under .cache/series_art/:
  items.json.gz      {qid: {"P18": [file], "P154": [...], "P3383": [...], "P2716": [...],
                     "P6802": [...]}}: the item's own image, logo, poster, collage and
                     related-image statements
  depicts.json.gz    {qid: [file]}: Commons files whose Structured Data says they depict the
                     item (P180), from Commons' own search (haswbstatement:P180=<qid>)
  files.json.gz      {file: class, template, author, categories, page status} for every
                     candidate (the above, and Track D's files in the item's own P373
                     category); the dims phase adds width/height, the faces phase the face box
                     (contract section 3.3a), as harvest_people_wikidata.py does for portraits
  sitelinks.json.gz  {qid: number of Wikipedias with an article about it} for every matched
                     person and series: the recognizability measure (art_policy.series_star)
  failed.json        requests that could not be read
Rewritten as each batch lands, so a killed run resumes. Exits non-zero when nothing was read.
"""
import argparse
import gzip
import json
import os
import re
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ia_lib import CACHE, OUT, write_json  # noqa: E402
import harvest_ext_wm as wm  # noqa: E402
import harvest_people_wikidata as HP  # noqa: E402
import enrich_people_art as P  # noqa: E402

DIR = os.path.join(CACHE, "series_art")
HOST = "commons.wikimedia.org"
# The item's own pictures: image, logo, film poster, collage image, related image.
PICTURE_PROPS = ("P18", "P154", "P3383", "P2716", "P6802")


def _rj(name, default):
    p = os.path.join(DIR, name)
    if not os.path.exists(p):
        return default
    with gzip.open(p, "rt", encoding="utf-8") as f:
        return json.load(f)


def _file(v):
    return v.split("Special:FilePath/", 1)[1] if "Special:FilePath/" in v else v


def matched_qids(con):
    tables = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
    series = sorted({q for (q,) in con.execute("SELECT qid FROM series_wikidata WHERE in_db = 1 AND qid != ''")}) \
        if "series_wikidata" in tables else []
    people = sorted({q for (q,) in con.execute("SELECT qid FROM people_wikidata WHERE qid IS NOT NULL AND qid != ''")}) \
        if "people_wikidata" in tables else []
    return series, people


def phase_items(qids, items, batch=100):
    import urllib.parse
    todo = [q for q in qids if q not in items]
    print(f"items: {len(todo)} to read", flush=True)
    for i in range(0, len(todo), batch):
        chunk = todo[i:i + batch]
        vals = " ".join("wd:" + q for q in chunk)
        union = " UNION ".join(f'{{ ?x wdt:{p} ?v BIND("{p}" AS ?k) }}' for p in PICTURE_PROPS)
        rows = wm.sparql(f"SELECT ?x ?k ?v WHERE {{ VALUES ?x {{ {vals} }} {union} }}", cache_dir="series_art/sparql")
        if rows is None:
            continue
        got = {q: {p: [] for p in PICTURE_PROPS} for q in chunk}
        for r in rows:
            fn = urllib.parse.unquote(_file(r["v"]))
            lst = got[wm.qid(r["x"])][r["k"]]
            if fn not in lst:
                lst.append(fn)
        items.update(got)
        write_json(os.path.join(DIR, "items.json.gz"), items, gz=True)
    print(f"  items {len(items)}", flush=True)


def phase_depicts(qids, depicts):
    todo = [q for q in qids if q not in depicts]
    print(f"depicts: {len(todo)} items to search", flush=True)
    for i, q in enumerate(todo):
        obj = wm.call(wm.COMMONS_API, {"action": "query", "format": "json", "list": "search",
                                       "srsearch": f"haswbstatement:P180={q}", "srnamespace": "6",
                                       "srlimit": "50"}, cache_dir="series_art/search")
        if obj is None:
            continue
        depicts[q] = [h["title"].split(":", 1)[1] for h in (obj.get("query") or {}).get("search", [])]
        if i % 25 == 0 or i == len(todo) - 1:
            write_json(os.path.join(DIR, "depicts.json.gz"), depicts, gz=True)
            print(f"  depicts {i + 1}/{len(todo)}", flush=True)
    write_json(os.path.join(DIR, "depicts.json.gz"), depicts, gz=True)


def category_files(con):
    """Track D's Commons files whose own categories hold a matched item's P373 category."""
    p = os.path.join(CACHE, "commons", "files.json.gz")
    if not os.path.exists(p):
        return []
    cats = {"Category:" + c for (cj,) in con.execute(
        "SELECT commons_category FROM series_wikidata WHERE in_db = 1 AND commons_category IS NOT NULL")
        for c in (json.loads(cj) if cj.startswith("[") else [cj])}
    files = json.load(gzip.open(p, "rt"))
    return sorted(t.split(":", 1)[1] for t, v in files.items() if cats & set(v.get("categories") or []))


def phase_pages(names, files):
    todo = [fn for fn in names if fn not in files]
    print(f"pages: {len(todo)} file pages to read", flush=True)
    for i, fn in enumerate(todo):
        title = "File:" + fn.replace("_", " ")
        hit = HP._trackd_page(title)
        text, status = hit if hit else wm.raw_page(HOST, title, "series_art/commons_raw")
        cls, tmpl, _ = P.license_class(text) if status == "ok" else (status, None, None)
        v = {"class": cls if status == "ok" else ("missing" if status == "missing" else "unread"),
             "template": tmpl, "page_status": status, "via_trackd_cache": bool(hit),
             "categories": sorted({c.strip() for c in re.findall(r"\[\[\s*Category\s*:\s*([^\]|]+)", text or "", re.I)})}
        if text:
            v.update(P.file_facts(text))
        files[fn] = v
        if i % 50 == 0 or i == len(todo) - 1:
            write_json(os.path.join(DIR, "files.json.gz"), files, gz=True)
            print(f"  pages {i + 1}/{len(todo)}", flush=True)
    write_json(os.path.join(DIR, "files.json.gz"), files, gz=True)


# Sitelinks that are not a language's Wikipedia, though their site id also ends in "wiki".
NOT_WIKIPEDIA = {"commonswiki", "specieswiki", "metawiki", "mediawikiwiki", "wikidatawiki", "sourceswiki",
                 "wikimaniawiki", "outreachwiki", "incubatorwiki", "foundationwiki", "wikifunctionswiki", "testwiki",
                 "test2wiki", "testwikidatawiki", "strategywiki", "donatewiki", "nostalgiawiki", "tenwiki"}


def wikipedias(entity):
    """How many Wikipedias have an article about the entity: its sitelinks whose site id is a
    language's Wikipedia ('enwiki', 'dewiki'), never Commons, Wikiquote ('enwikiquote') or Meta."""
    return sum(1 for site in (entity.get("sitelinks") or {})
               if site.endswith("wiki") and site not in NOT_WIKIPEDIA)


def phase_sitelinks(qids, sitelinks, batch=50):
    """How many Wikipedias (any language) have an article about each item, from the Wikidata
    API's sitelinks (wbgetentities, 50 ids a call; a SPARQL count over schema:about timed out)."""
    todo = [q for q in qids if q not in sitelinks]
    print(f"sitelinks: {len(todo)} to count", flush=True)
    for i in range(0, len(todo), batch):
        chunk = todo[i:i + batch]
        obj = wm.call(wm.WD_API, {"action": "wbgetentities", "format": "json", "props": "sitelinks",
                                  "ids": "|".join(chunk)}, cache_dir="series_art/wbgetentities")
        if not obj or "entities" not in obj:
            continue
        for q, e in obj["entities"].items():
            if "missing" not in e:
                sitelinks[q] = wikipedias(e)
        write_json(os.path.join(DIR, "sitelinks.json.gz"), sitelinks, gz=True)
        if (i // batch) % 10 == 0 or i + batch >= len(todo):
            print(f"  sitelinks {len(sitelinks)}", flush=True)


def candidates(items, depicts, cat_files):
    out = []
    for q in sorted(items):
        for p in PICTURE_PROPS:
            out += items[q].get(p, [])
    for q in sorted(depicts):
        out += depicts[q]
    return list(dict.fromkeys(out + cat_files))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--phase", choices=["items", "depicts", "pages", "dims", "sitelinks", "faces", "all"],
                    default="all")
    ap.add_argument("--db", default=os.path.join(OUT, "radio-catalog.sqlite"))
    ap.add_argument("--detector", help="faces: the compiled face_boxes.swift")
    ap.add_argument("--thumbs", default=os.path.join(os.environ.get("TMPDIR", "/tmp"), "eardrama-face-thumbs"))
    a = ap.parse_args()
    os.makedirs(DIR, exist_ok=True)
    con = sqlite3.connect(f"file:{a.db}?mode=ro", uri=True)
    series, people = matched_qids(con)
    items, depicts = _rj("items.json.gz", {}), _rj("depicts.json.gz", {})
    files, sitelinks = _rj("files.json.gz", {}), _rj("sitelinks.json.gz", {})
    fpath = os.path.join(DIR, "files.json.gz")
    if a.phase in ("items", "all"):
        phase_items(series, items)
    if a.phase in ("depicts", "all"):
        phase_depicts(series, depicts)
    if a.phase in ("pages", "all"):
        phase_pages(candidates(items, depicts, category_files(con)), files)
    if a.phase in ("dims", "all"):
        HP.phase_dims(files, out=fpath, cache_dir="series_art/imageinfo")
    if a.phase in ("sitelinks", "all"):
        phase_sitelinks(people + series, sitelinks)
    if a.phase == "faces":  # Mac only (Apple Vision), so never part of "all"
        if not a.detector:
            ap.error("--phase faces needs --detector (swiftc -O -o face_boxes tools/face_boxes.swift)")
        HP.phase_faces(files, a.detector, a.thumbs, out=fpath)
    write_json(os.path.join(DIR, "failed.json"), wm.FAILED)
    print(f"items {len(items)}, depicts {sum(map(len, depicts.values()))}, files {len(files)}, "
          f"sitelinks {len(sitelinks)}, failed {len(wm.FAILED)}")
    if not (items or sitelinks):
        sys.exit(1)


if __name__ == "__main__":
    main()
