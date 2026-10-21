#!/usr/bin/env python3
"""Library of Congress Prints & Photographs: radio performers, studios,
broadcasts, microphones and receivers, as metadata and image URLs (never the
image binaries). reports/F-photo-archives.md.

loc.gov's JSON API is keyless; its documented limit (loc.gov/apis/json-and-yaml/
working-within-limits, read 2026-10-21) is 20 requests a minute, with a ONE-HOUR
block that restarts on any request made during it. So: one request every 6 s
(10/min; the egress IP is shared and a first run at 4 s was blocked after
~30 requests in five minutes), and a 429 or a CAPTCHA page STOPS the run (exit 3) rather than
retrying into the block. Every response is cached under .cache/loc/, so a
re-run (after a restart, or the next day) resumes where it stopped.

Phases:
  search  topic queries (radio, microphone, broadcasting ... 1920-1965), the
          named collections (Bain, Harris & Ewing, FSA/OWI, World-Telegram, Look),
          and a quoted-name query for each of the top series and people in
          out/radio-catalog.sqlite. Search pages carry title, date, rights
          advisory, subjects, contributors, call number and preview image URLs.
  items   for each record that photo_match ties to a series or person and whose
          rights class is usable, the item JSON, which lists every file (the
          TIFF master and the largest JPEG). Others keep the search page's
          largest preview URL.

Output: .cache/loc/records.json.gz — {id: record} (see `record()`), plus
.cache/loc/failures.json. Run:
    python3 tools/harvest_loc_photos.py [--phase search|items|all] [--max-requests N]
"""
import argparse
import gzip
import hashlib
import http.client
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
import photo_match as M

DIR = os.path.join(L.CACHE, "loc")
QDIR = os.path.join(DIR, "q")
IDIR = os.path.join(DIR, "item")
RECORDS = os.path.join(DIR, "records.json.gz")
FAILS = os.path.join(DIR, "failures.json")
DB = os.path.join(L.OUT, "radio-catalog.sqlite")
BASE = "https://www.loc.gov/photos/"
PACE = 6.0
PER = 50

TOPICS = ["radio", "microphone", "broadcasting", "radio station", "radio program", "radio announcer",
          "radio receiver", "radio set", "radio actors", "radio studio", "sound effects",
          "National Broadcasting Company", "Columbia Broadcasting System", "Mutual Broadcasting",
          "Blue Network", "network broadcast", "transcription"]
# (label, q, fa) — measured facet slugs; World-Telegram and Look are not
# facets on /photos/, so their prints are found by a text query (the call
# number NYWTS / the Look job numbers are in the record).
COLLECTIONS = [
    ("bain", "radio", "partof:bain collection"),
    ("harris_ewing", "radio", "partof:harris & ewing collection"),
    ("fsa_owi", "radio", "partof:farm security administration/office of war information black-and-white negatives"),
    ("fsa_owi_color", "radio", "partof:farm security administration/office of war information color photographs"),
    ("world_telegram", "radio world-telegram", None),
    ("world_telegram_nywts", "radio NYWTS", None),
    ("look", "radio look magazine", None),
    ("ftp", "radio", "partof:federal theatre project, 1935 to 1939"),
]


class Blocked(Exception):
    pass


_last = [0.0]
_count = [0]


def fetch(url, budget):
    if _count[0] >= budget:
        raise Blocked(f"request budget {budget} spent")
    wait = PACE - (time.time() - _last[0])
    if wait > 0:
        time.sleep(wait)
    for attempt in range(3):
        _last[0] = time.time()
        _count[0] += 1
        req = urllib.request.Request(url, headers={"User-Agent": L.UA, "Accept": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=90) as r:
                body = r.read()
        except urllib.error.HTTPError as e:
            if e.code == 429:
                raise Blocked(f"429 from loc.gov at {url}")
            if e.code in (500, 502, 503, 504):
                time.sleep(20 * (attempt + 1))
                continue
            return None, f"HTTP {e.code}"
        except (urllib.error.URLError, TimeoutError, ConnectionError, http.client.IncompleteRead) as e:
            time.sleep(20 * (attempt + 1))
            continue
        try:
            return json.loads(body), None
        except json.JSONDecodeError:
            if b"captcha" in body[:20000].lower():
                raise Blocked(f"CAPTCHA page from loc.gov at {url}")
            time.sleep(20 * (attempt + 1))
            continue
    return None, "no JSON after 3 tries"


def qkey(params):
    return hashlib.sha1(json.dumps(params, sort_keys=True).encode()).hexdigest()[:20]


def trim(d):
    return {"pagination": d.get("pagination"), "results": d.get("results", [])}


def search(label, params, budget, fails):
    """Every page of one query, cached page by page."""
    page = 1
    out = []
    while True:
        p = dict(params, fo="json", c=PER, sp=page, at="results,pagination")
        path = os.path.join(QDIR, qkey(p) + ".json.gz")
        if os.path.exists(path):
            d = L.read_json(path)
        else:
            url = BASE + "?" + urllib.parse.urlencode({k: v for k, v in p.items() if v is not None})
            d, err = fetch(url, budget)
            if d is None:
                fails.append({"query": label, "params": p, "error": err})
                return out, False
            d = trim(d)
            L.write_json(path, d, gz=True)
        res = d.get("results") or []
        for r in res:
            r["_query"] = label
        out.extend(res)
        pg = d.get("pagination") or {}
        if not pg.get("next") or not res or page * PER >= 5000:
            return out, True
        page += 1


def record(r):
    it = r.get("item") or {}
    imgs = [u.split("#")[0] for u in (r.get("image_url") or [])]
    jpgs = [u for u in imgs if u.endswith(".jpg")]
    largest = jpgs[-1] if jpgs else (imgs[-1] if imgs else None)
    contributors = r.get("contributor") or it.get("contributors") or []
    rights = it.get("rights_advisory") or it.get("rights_information") or ""
    if isinstance(rights, list):  # some records carry the advisory as a list of sentences
        rights = " ".join(map(str, rights))
    partof = r.get("partof") or []
    call = it.get("call_number") or ""
    if isinstance(call, list):
        call = " | ".join(map(str, call))
    creator_text = " | ".join(map(str, contributors + partof + [call]))
    cls, why = M.rights_class(rights, creator_text)
    online = bool(largest) and not r.get("access_restricted")
    lid = (r.get("id") or "").rstrip("/").split("/")[-1]
    return {
        "id": lid, "url": r.get("url") or r.get("id"), "title": r.get("title"),
        "date": r.get("date"), "dates": r.get("dates"),
        "created_published": it.get("created_published"),
        "description": (r.get("description") or [None])[0] if isinstance(r.get("description"), list) else r.get("description"),
        "summary": it.get("summary"), "notes": it.get("notes"),
        "subjects": it.get("subjects") or [], "subject_headings": it.get("subject_headings") or [],
        "contributors": contributors, "partof": partof, "call_number": call,
        "rights": rights, "rights_class": cls, "rights_why": why, "online": online,
        "access_restricted": r.get("access_restricted"),
        "image_largest": largest, "image_urls": imgs, "files": None,
        "queries": [r.get("_query")],
    }


def db_terms():
    c = sqlite3.connect(DB)
    ser = [n for (n,) in c.execute(
        "select name from series where name is not null and (first_date is null or first_date < '1966') "
        "order by episodes desc limit 400")]
    ser = [n for n in ser if M.series_name_ok(n)][:60]
    ppl = [n for (n,) in c.execute(
        "select p.name from episode_credits e join people p on p.id = e.person_id "
        "group by e.person_id order by count(distinct e.episode_id) desc limit 500")]
    ppl = [n for n in ppl if M.name_ok(n)][:100]
    return ser, ppl


def run_search(budget, fails, recs):
    jobs = [("topic:" + t, {"q": t, "dates": "1920/1965"}) for t in TOPICS]
    jobs += [("coll:" + lab, {"q": q, "fa": fa}) for lab, q, fa in COLLECTIONS]
    ser, ppl = db_terms()
    jobs += [("series:" + n, {"q": f'"{n}"', "dates": "1920/1975"}) for n in ser]
    jobs += [("person:" + n, {"q": f'"{n}"', "dates": "1915/1980"}) for n in ppl]
    done = 0
    for label, params in jobs:
        res, ok = search(label, params, budget, fails)
        for r in res:
            if "photo" not in " ".join(r.get("original_format") or []).lower() and r.get("original_format"):
                continue
            rec = record(r)
            if not rec["id"]:
                continue
            if rec["id"] in recs:
                if label not in recs[rec["id"]]["queries"]:
                    recs[rec["id"]]["queries"].append(label)
            else:
                recs[rec["id"]] = rec
        done += ok
    return len(jobs), done


def item_files(rec, budget, fails):
    path = os.path.join(IDIR, re.sub(r"[^\w.-]", "_", rec["id"]) + ".json.gz")
    if os.path.exists(path):
        d = L.read_json(path)
    else:
        d, err = fetch(f"https://www.loc.gov/item/{rec['id']}/?fo=json", budget)
        if d is None:
            fails.append({"item": rec["id"], "error": err})
            return
        d = {"resources": d.get("resources"), "item": {k: (d.get("item") or {}).get(k) for k in
                                                       ("rights_advisory", "rights_information", "title")}}
        L.write_json(path, d, gz=True)
    files = []
    for res in d.get("resources") or []:
        for group in res.get("files") or []:
            for f in group:
                files.append({k: f.get(k) for k in ("url", "mimetype", "width", "height", "size")})
    rec["files"] = files
    jp = [f for f in files if f["mimetype"] == "image/jpeg" and f.get("width")]
    if jp:
        rec["image_largest"] = max(jp, key=lambda f: f["width"] or 0)["url"]
    tif = [f for f in files if f["mimetype"] == "image/tiff"]
    rec["image_master"] = tif[0]["url"] if tif else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--phase", default="all", choices=["search", "items", "all"])
    ap.add_argument("--max-requests", type=int, default=2000)
    ap.add_argument("--max-items", type=int, default=150,
                    help="item JSON fetches this run (the rest keep the search page's largest preview)")
    a = ap.parse_args()
    os.makedirs(QDIR, exist_ok=True)
    os.makedirs(IDIR, exist_ok=True)
    fails = []
    recs = {}
    status = "complete"
    try:
        n, ok = run_search(a.max_requests, fails, recs)
        print(f"search: {ok}/{n} queries complete, {len(recs)} photo records", file=sys.stderr)
        if a.phase in ("items", "all"):
            import enrich_photo_archives as E
            targets = E.loc_targets(list(recs.values()))
            print(f"items: {len(targets)} usable matched records", file=sys.stderr)
            todo = [rid for rid in targets if not os.path.exists(
                os.path.join(IDIR, re.sub(r"[^\w.-]", "_", rid) + ".json.gz"))]
            for rid in todo[:a.max_items]:
                item_files(recs[rid], a.max_requests, fails)
            print(f"items: fetched {min(len(todo), a.max_items)} of {len(todo)} not yet cached", file=sys.stderr)
    except Blocked as e:
        status = f"stopped: {e}"
        print(status, file=sys.stderr)
    # files already cached are folded in even on a search-only pass
    for rec in recs.values():
        if rec["files"] is None and os.path.exists(os.path.join(IDIR, re.sub(r"[^\w.-]", "_", rec["id"]) + ".json.gz")):
            item_files(rec, 0, fails)
    L.write_json(RECORDS, recs, gz=True)
    L.write_json(FAILS, {"status": status, "requests_this_run": _count[0], "failures": fails})
    print(f"{len(recs)} records; {_count[0]} requests; {len(fails)} failures; {status}", file=sys.stderr)
    if not recs:
        sys.exit(1)
    if status != "complete":
        sys.exit(3)


if __name__ == "__main__":
    main()
