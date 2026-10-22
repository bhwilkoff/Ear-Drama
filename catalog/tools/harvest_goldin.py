"""Harvest RadioGOLDINdex (radiogoldin.library.umkc.edu), J. David Goldin's
index of recorded radio programs, through the JSON endpoint its own search page
calls (`POST /Home/radioGoldIndexSearch`, found in
/Scripts/Custom/Home/RadioGoldinSearch.js; robots.txt is 404). MEASURED
2026-10-19: 124,919 records; `count=1000` with `sortby=CATALOGNUM-ASC` returns
1,000 rows per page in catalogue-number order, ~5 s a page.

Every page is cached as it arrives (`.cache/goldin/pages/NNNN.json.gz`), so a
killed run resumes where it stopped. A page that could not be read is recorded
in `failed.json` and the run exits non-zero; it is never written as empty.

FACTS are free (Feist): program, date, title, artists and roles, source
(network + recording source), duration, quality, completeness. The PLOT field
is Goldin's prose: it is cached here because the pipeline needs it for matching
and search, and enrich_db.py stores it with `display_allowed = 0` and its
provenance. The owner must get permission before any client shows it.

The JSON's SPONSOR field is always null; the record page
(`/ProgramMoreinfo/<CATALOGNUM>`) shows one. `--record-pages N` fetches a sample
of N record pages so the gap can be measured, not guessed.

    python3 tools/harvest_goldin.py                  # all pages, ~3 s apart
    python3 tools/harvest_goldin.py --record-pages 300
"""
import argparse
import glob
import gzip
import html
import json
import os
import random
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(__file__))
import ia_lib as ia

RG = "https://radiogoldin.library.umkc.edu"
SEARCH = RG + "/Home/radioGoldIndexSearch"
UA = "Mozilla/5.0 ArchiveWatch-RadioCatalog (catalog build; credits RadioGOLDINdex)"
OUT = os.path.join(ia.CACHE, "goldin")
PAGES = os.path.join(OUT, "pages")
RECORDS = os.path.join(OUT, "records")
PER_PAGE = 1000
DELAY = 3.0


def post(form, tries=6, timeout=300):
    data = urllib.parse.urlencode(form).encode()
    delay = 5.0
    for attempt in range(tries):
        req = urllib.request.Request(SEARCH, data=data, headers={"User-Agent": UA})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                d = json.loads(r.read())
            if d.get("status") != "Ok":
                raise ValueError(f"status {d.get('status')}")
            return d["filters"]
        except (urllib.error.URLError, TimeoutError, ConnectionError, ValueError, KeyError) as e:
            print(f"retry {attempt}: {e}", file=sys.stderr, flush=True)
            time.sleep(delay)
            delay *= 2
    return None


def form(page, count=PER_PAGE):
    return {"programName": "", "artistName": "", "dateRange": "", "count": count, "pageNo": page,
            "sortby": "CATALOGNUM-ASC", "radioGoldinFilterRequest": "PROGNUMB", "searchCategory": "All"}


KEEP = ("CATALOGNUM", "PROGNAME", "SDATE", "TITLE", "PLOT", "ARTIST", "SOURCE", "DURATION",
        "QUALITY", "COMPLETE", "PROGNUMB", "SPONSOR")


def page_path(n):
    return os.path.join(PAGES, f"{n:04d}.json.gz")


def harvest_pages():
    os.makedirs(PAGES, exist_ok=True)
    head = post(form(1, 1))
    if head is None:
        raise SystemExit("RadioGOLDINdex unreadable (count probe failed)")
    total = int(head["programsCount"])
    pages = (total + PER_PAGE - 1) // PER_PAGE
    print(f"{total} records, {pages} pages", file=sys.stderr, flush=True)
    failed = []
    for n in range(1, pages + 1):
        if os.path.exists(page_path(n)):
            continue
        f = post(form(n))
        time.sleep(DELAY)
        if f is None:
            failed.append(n)
            continue
        rows = [{k: r.get(k) for k in KEEP} for r in f.get("programsList") or []]
        if not rows:
            failed.append(n)
            print(f"page {n}: no rows (recorded as failed, not empty)", file=sys.stderr)
            continue
        ia.write_json(page_path(n), {"page": n, "total": int(f["programsCount"]),
                                     "fetched": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                                     "rows": rows}, gz=True)
        if n % 10 == 0:
            print(f"page {n}/{pages}", file=sys.stderr, flush=True)
    ia.write_json(os.path.join(OUT, "failed.json"), failed)
    return total, failed


def merge(total):
    """One file of all records, keyed by CATALOGNUM; report gaps between the
    claimed total and what the pages hold (a re-sorted index shifts pages)."""
    recs = {}
    for p in sorted(glob.glob(os.path.join(PAGES, "*.json.gz"))):
        with gzip.open(p, "rt") as f:
            for r in json.load(f)["rows"]:
                recs[r["CATALOGNUM"]] = r
    rows = [recs[k] for k in sorted(recs)]
    ia.write_json(os.path.join(OUT, "records.json.gz"), rows, gz=True)
    cov = {k: sum(1 for r in rows if (str(r.get(k) or "").strip() not in ("", "*"))) for k in KEEP}
    rep = {"claimed_total": total, "records": len(rows), "missing_vs_claimed": total - len(rows),
           "field_nonempty": cov}
    ia.write_json(os.path.join(OUT, "harvest_report.json"), rep)
    print(json.dumps(rep, indent=1), file=sys.stderr)
    return rows


def strip_tags(s):
    return html.unescape(re.sub(r"<[^>]+>", " ", s)).strip()


def record_page(cat):
    """The label/value pairs on /ProgramMoreinfo/<cat>, as the page prints them."""
    path = os.path.join(RECORDS, f"{cat}.json")
    if os.path.exists(path):
        with open(path) as f:
            return json.load(f)
    body = ia.get(f"{RG}/ProgramMoreinfo/{cat}", ua=UA, raw=True, timeout=90)
    time.sleep(DELAY)
    if body is None:
        return None
    text = body.decode("utf-8", "replace")
    pairs = {lab: strip_tags(val) for lab, val in
             re.findall(r'<td data-label="([^"]+)">(.*?)</td>', text, flags=re.S)}
    if not pairs:
        print(f"record {cat}: no fields parsed", file=sys.stderr)
        return None
    ia.write_json(path, {"cat": cat, "fields": pairs})
    return {"cat": cat, "fields": pairs}


def sample_records(rows, n):
    os.makedirs(RECORDS, exist_ok=True)
    rng = random.Random(1947)
    pick = rng.sample(rows, min(n, len(rows)))
    got, failed, sponsor = 0, 0, 0
    for r in pick:
        d = record_page(r["CATALOGNUM"])
        if d is None:
            failed += 1
            continue
        got += 1
        sp = next((v for k, v in d["fields"].items() if k.lower().startswith("sponsor")), "")
        sponsor += bool(sp.strip())
    rep = {"sampled": len(pick), "read": got, "failed": failed, "with_sponsor": sponsor}
    ia.write_json(os.path.join(OUT, "record_sample_report.json"), rep)
    print(json.dumps(rep), file=sys.stderr)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--record-pages", type=int, default=0)
    ap.add_argument("--offline", action="store_true", help="merge cached pages only")
    a = ap.parse_args()
    if a.offline:
        rep = os.path.join(OUT, "harvest_report.json")
        total = json.load(open(rep))["claimed_total"] if os.path.exists(rep) else 0
        failed = []
    else:
        total, failed = harvest_pages()
    rows = merge(total)
    if a.record_pages:
        sample_records(rows, a.record_pages)
    if not rows:
        raise SystemExit("read nothing")
    if failed:
        raise SystemExit(f"{len(failed)} pages failed: {failed[:10]}")


if __name__ == "__main__":
    main()
