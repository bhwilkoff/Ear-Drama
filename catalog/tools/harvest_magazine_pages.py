#!/usr/bin/env python3
"""Pages of period radio magazines whose issue is not under copyright, as text we can tie to a program (R3b V5,
Decision 040). The rights evidence is the issue-year row of `magazine_rights` (harvest_magazine_rights.py): an
issue whose year was not renewed, or is public domain by age. A page that carries its own notice is judged on
the page (art_policy.magazine_page_served); the harvest only reads.

    python3 tools/harvest_magazine_pages.py [--max-items N] [--pace SECONDS]

Sources, all archive.org (keyless, one request every --pace seconds, Retry-After honored, every issue cached
under .cache/magazine_pages/ so a re-run resumes):
  * Media History Digital Library volumes already listed in .cache/magazines/evidence.json;
  * the per-issue collections `radioguide`, `radiostarsmagazine`, `radiomirror` (listed by advancedsearch).
An issue is read from its `_hocr_searchtext.txt.gz` with `_hocr_pageindex.json.gz` (small) and else from
`_djvu.xml` (page objects). Only a SHORT page is kept (6 to 450 words, text cut to 1500 characters): a page of
close print is not a picture of a program, and the cache stays small. The page's image is archive.org's own
`/download/<id>/page/n<leaf>_w800.jpg`, fetched by the client, never by this tool.

Output: .cache/magazine_pages/listing.json and .cache/magazine_pages/items/<id>.json.gz
"""
import argparse
import gzip
import json
import os
import re
import sqlite3
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ia_lib as L

DIR = os.path.join(L.CACHE, "magazine_pages")
ITEMS = os.path.join(DIR, "items")
LISTING = os.path.join(DIR, "listing.json")
EVIDENCE = os.path.join(L.CACHE, "magazines", "evidence.json")
DB = os.path.join(L.OUT, "radio-catalog.sqlite")
COLLECTIONS = {"radioguide": "Radio Guide", "radiostarsmagazine": "Radio Stars", "radiomirror": "Radio Mirror"}
MIN_WORDS, MAX_WORDS, KEEP_CHARS = 6, 450, 1500
DOWNLOAD = "https://archive.org/download/{id}/{name}"


def usable_years(con):
    """{(magazine, year)} the issue-year rows call not under copyright (not_renewed or pd_by_age)."""
    return {(t, y) for t, y in con.execute("SELECT title, year FROM magazine_rights WHERE usable = 1")}


def years_in(title, year):
    """Every year a volume's own title spans ('Radio mirror (Nov 1938-Apr 1939)' is 1938 and 1939)."""
    ys = {int(y) for y in re.findall(r"\b(19[0-4]\d)\b", title or "")}
    return sorted(ys | ({int(year)} if isinstance(year, int) else set()))


def listing(con, force=False):
    """The issues worth reading: {id: {title, magazine, years, source}}, each year usable."""
    if os.path.exists(LISTING) and not force:
        return L.read_json(LISTING)
    ok = usable_years(con)
    out = {}
    ev = L.read_json(EVIDENCE) if os.path.exists(EVIDENCE) else {}
    for m in ev.get("mhdl", []):
        ys = years_in(m.get("title"), m.get("year") if isinstance(m.get("year"), int) else None)
        if ys and all((m["canonical"], y) in ok for y in ys):
            out[m["id"]] = {"title": m["title"], "magazine": m["canonical"], "years": ys, "source": "mhdl"}
    for coll, magazine in COLLECTIONS.items():
        cursor = None
        while True:
            p = {"q": f"collection:{coll} AND mediatype:texts", "fields": "identifier,title,year,date", "count": 1000}
            if cursor:
                p["cursor"] = cursor
            d = L.get(L.SCRAPE, p)
            if d is None:
                raise RuntimeError(f"could not list {coll}")
            for it in d.get("items", []):
                try:
                    y = int(str(it.get("year") or it.get("date"))[:4])
                except ValueError:
                    continue
                if (magazine, y) in ok:
                    out[it["identifier"]] = {"title": it.get("title"), "magazine": magazine, "years": [y],
                                             "source": coll}
            cursor = d.get("cursor")
            if not cursor:
                break
            time.sleep(2)
    L.write_json(LISTING, out)
    return out


_last = [0.0]


def fetch(url, pace):
    """Bytes, or None for a 404 (a file the item does not have). A 429 or 5xx waits for Retry-After (else a
    growing delay); a failure that is not a 404 raises, so it is never read as 'nothing there'."""
    delay = 5.0
    for _ in range(6):
        wait = pace - (time.time() - _last[0])
        if wait > 0:
            time.sleep(wait)
        _last[0] = time.time()
        req = urllib.request.Request(url, headers={"User-Agent": L.UA})
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            if e.code in (429, 500, 502, 503, 504):
                retry = e.headers.get("Retry-After") if e.headers else None
                time.sleep(min(int(retry), 600) if retry and retry.isdigit() else delay)
                delay *= 2
                continue
            raise
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            time.sleep(delay)
            delay *= 2
    raise RuntimeError(f"could not read {url}")


def pages_from_hocr(sid, pace):
    st = fetch(DOWNLOAD.format(id=sid, name=f"{sid}_hocr_searchtext.txt.gz"), pace)
    pi = fetch(DOWNLOAD.format(id=sid, name=f"{sid}_hocr_pageindex.json.gz"), pace) if st else None
    if not st or not pi:
        return None
    text = gzip.decompress(st)   # the index counts bytes
    index = json.loads(gzip.decompress(pi))
    return [text[a:b].decode("utf-8", "replace") for a, b, *_ in index]


def pages_from_djvu(sid, pace):
    raw = fetch(DOWNLOAD.format(id=sid, name=f"{sid}_djvu.xml"), pace)
    if not raw:
        return None
    xml = raw.decode("utf-8", "replace")
    pages = []
    for obj in re.split(r"<OBJECT\b", xml)[1:]:
        words = re.findall(r">([^<]+)</WORD>", obj)
        pages.append(" ".join(w.strip() for w in words))
    return pages


def read_issue(sid, meta, pace):
    pages = pages_from_hocr(sid, pace)
    how = "hocr"
    if pages is None:
        pages, how = pages_from_djvu(sid, pace), "djvu"
    if pages is None:
        return None
    keep = []
    for leaf, t in enumerate(pages):
        t = re.sub(r"\s+", " ", t or "").strip()
        n = len(t.split())
        if MIN_WORDS <= n <= MAX_WORDS:
            keep.append([leaf, n, t[:KEEP_CHARS]])
    return {"id": sid, "title": meta["title"], "magazine": meta["magazine"], "years": meta["years"],
            "leaves": len(pages), "read": how, "pages": keep}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-items", type=int, default=100000)
    ap.add_argument("--pace", type=float, default=2.0)
    ap.add_argument("--relist", action="store_true")
    a = ap.parse_args()
    os.makedirs(ITEMS, exist_ok=True)
    con = sqlite3.connect(DB)
    todo = listing(con, a.relist)
    print(f"{len(todo)} issues in unrenewed years", file=sys.stderr)
    done = failed = skipped = 0
    for sid, meta in sorted(todo.items()):
        path = os.path.join(ITEMS, re.sub(r"[^\w.-]", "_", sid) + ".json.gz")
        if os.path.exists(path):
            skipped += 1
            continue
        if done >= a.max_items:
            break
        try:
            rec = read_issue(sid, meta, a.pace)
        except Exception as e:   # a failure is recorded in the log and retried next run, never cached as empty
            failed += 1
            print(f"FAILED {sid}: {e}", file=sys.stderr)
            continue
        if rec is None:
            rec = {"id": sid, "title": meta["title"], "magazine": meta["magazine"], "years": meta["years"],
                   "leaves": 0, "read": "no-text", "pages": []}
        L.write_json(path, rec, gz=True)
        done += 1
        if done % 25 == 0:
            print(f"{done} read, {skipped} cached, {failed} failed", file=sys.stderr)
    print(f"read {done}, already cached {skipped}, failed {failed}, of {len(todo)}", file=sys.stderr)
    if failed:
        sys.exit(3)


if __name__ == "__main__":
    main()
