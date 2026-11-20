"""Round 3 V2: more real images (R3b section 5.1: H3, H4, H7, H9). Polite, cached, resumable.

    python3 tools/harvest_art_v2.py --phase lead        # H3: enwiki lead images of the matched articles
    python3 tools/harvest_art_v2.py --phase search      # H4: Commons search by program name (--top N)
    python3 tools/harvest_art_v2.py --phase pages       # license pages + sizes of every candidate file
    python3 tools/harvest_art_v2.py --phase plays       # H7: play works, authors, pre-1931 editions
    python3 tools/harvest_art_v2.py --phase liveness    # H9: HEAD every served file on a TTL
    python3 tools/harvest_art_v2.py --phase faces --detector /tmp/face_boxes   # Mac only, served files only

Run after enrich_external.py (series_wikidata) and enrich_series_art.py (series_art.served): it reads the
database and writes under .cache/art_v2/ (every response also cached by harvest_ext_wm / ia_lib, so a killed
run resumes):
  lead.json.gz       {enwiki title: {free, any}}: pageprops.page_image_free and the page image, whichever license
  search.json.gz     {series key: [Commons file names]} for the program's name
  files.json.gz      {file: license class, template, author, date, categories, own_work, width, height, mime}
  commons_raw/       each file page's wikitext (the shape enrich_series_art._page reads)
  plays.json.gz      {play id: {work, edition, author}} candidates, judged by art_policy in enrich_series_art
  liveness.json.gz   {file: {verdict ok|gone, day}}
Wikimedia throttles hard: harvest_ext_wm honors 429 and Retry-After; this module never sends two requests at once.
"""
import argparse
import datetime
import gzip
import hashlib
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
from ia_lib import CACHE, OUT, write_json  # noqa: E402
import ia_lib  # noqa: E402
import harvest_ext_wm as wm  # noqa: E402
import art_policy as AP  # noqa: E402

DIR = os.path.join(CACHE, "art_v2")
RAW = os.path.join(DIR, "commons_raw")
HOST = "commons.wikimedia.org"
PAGE_BATCH = 25


def rj(name, default):
    p = os.path.join(DIR, name)
    if not os.path.exists(p):
        return default
    with gzip.open(p, "rt", encoding="utf-8") as f:
        return json.load(f)


def wj(name, obj):
    write_json(os.path.join(DIR, name), obj, gz=True)


def db_connect(path):
    return sqlite3.connect(f"file:{path}?mode=ro", uri=True)


# ---------------------------------------------------------------- H3: enwiki lead images

def phase_lead(con, lead, batch=50):
    titles = sorted({t for (t,) in con.execute(
        "SELECT enwiki FROM series_wikidata WHERE in_db = 1 AND enwiki IS NOT NULL AND enwiki != ''")} - set(lead))
    print(f"lead: {len(titles)} articles to read", flush=True)
    for i in range(0, len(titles), batch):
        chunk = titles[i:i + batch]
        obj = wm.call(wm.EN_API, {"action": "query", "format": "json", "prop": "pageimages|pageprops",
                                  "piprop": "name", "pilicense": "any", "pilimit": str(batch),
                                  "ppprop": "page_image_free|page_image", "redirects": "1",
                                  "titles": "|".join(chunk)}, cache_dir="art_v2/enwiki")
        if not obj:
            continue
        q = obj.get("query") or {}
        back = {}
        for n in (q.get("normalized") or []) + (q.get("redirects") or []):
            back[n["to"]] = n["from"]
        pages = {}
        for page in (q.get("pages") or {}).values():
            t = page.get("title")
            origin = back.get(t, t)
            origin = back.get(origin, origin)
            props = page.get("pageprops") or {}
            pages[origin] = {"free": props.get("page_image_free"), "any": page.get("pageimage") or props.get("page_image")}
        for t in chunk:
            lead[t] = pages.get(t, {"free": None, "any": None, "missing": True})
        wj("lead.json.gz", lead)
        print(f"  lead {min(i + batch, len(titles))}/{len(titles)}", flush=True)
    wj("lead.json.gz", lead)


# ---------------------------------------------------------------- H4: Commons by name

def phase_search(con, search, top=500):
    rows = con.execute("SELECT key, name FROM series WHERE episodes IS NOT NULL ORDER BY episodes DESC, key LIMIT ?"
                       if "episodes" in {r[1] for r in con.execute("PRAGMA table_info(series)")} else
                       "SELECT key, name FROM series ORDER BY key LIMIT ?", (top,)).fetchall()
    todo = [(k, n) for k, n in rows if k not in search and sum(len(w) for w in AP._title_words(n)) >= AP.TITLE_MIN]
    print(f"search: {len(todo)} program names to ask", flush=True)
    for i, (key, name) in enumerate(todo):
        q = '"' + re.sub(r'["\\]', " ", re.sub(r"\(.*?\)", " ", name)).strip() + '" filetype:bitmap'
        obj = wm.call(wm.COMMONS_API, {"action": "query", "format": "json", "list": "search", "srsearch": q,
                                       "srnamespace": "6", "srlimit": "30"}, cache_dir="art_v2/search")
        if obj is None:
            continue
        search[key] = [h["title"].split(":", 1)[1] for h in (obj.get("query") or {}).get("search", [])]
        if i % 25 == 0 or i == len(todo) - 1:
            wj("search.json.gz", search)
            print(f"  search {i + 1}/{len(todo)}", flush=True)
    wj("search.json.gz", search)


# ---------------------------------------------------------------- license pages and sizes

def _raw_path(title):
    return os.path.join(RAW, hashlib.sha1((HOST + "|" + title).encode()).hexdigest() + ".json.gz")


def known_page(title):
    """A file page's (text, status) from this track's cache or any earlier one, else None."""
    import harvest_people_wikidata as HP
    p = _raw_path(title)
    if os.path.exists(p):
        with gzip.open(p, "rt", encoding="utf-8") as f:
            o = json.load(f)
        return o["text"], o["status"]
    key = hashlib.sha1((HOST + "|" + title).encode()).hexdigest() + ".json.gz"
    for d in (os.path.join(CACHE, "series_art", "commons_raw"), os.path.join(CACHE, "people_wd", "commons_raw")):
        q = os.path.join(d, key)
        if os.path.exists(q):
            with gzip.open(q, "rt", encoding="utf-8") as f:
                o = json.load(f)
            return o["text"], o["status"]
    return HP._trackd_page(title)


def phase_pages(names, files):
    """Read each candidate's wikitext (license, categories, date) and its size in batches through the Action
    API, one request at a time; a page found in any earlier cache is not asked again."""
    import enrich_people_art as P
    todo = []
    for fn in dict.fromkeys(n.replace("_", " ") for n in names):
        if fn in files and files[fn].get("page_status") == "ok" and files[fn].get("width"):
            continue
        hit = known_page("File:" + fn)
        if hit and hit[1] == "ok" and fn not in files:
            text = hit[0]
            cls, tmpl, _ = P.license_class(text)
            files[fn] = {"class": cls, "template": tmpl, "page_status": "ok",
                         "categories": sorted({c.strip() for c in re.findall(r"\[\[\s*Category\s*:\s*([^\]|]+)", text, re.I)}),
                         **P.file_facts(text)}
        if fn not in files or not files[fn].get("width"):
            if not (fn in files and files[fn].get("page_status") in ("missing",)):
                todo.append(fn)
    print(f"pages: {len(todo)} files to read ({len(files)} known)", flush=True)
    os.makedirs(RAW, exist_ok=True)
    for i in range(0, len(todo), PAGE_BATCH):
        chunk = todo[i:i + PAGE_BATCH]
        obj = wm.call(wm.COMMONS_API, {"action": "query", "format": "json", "formatversion": "2",
                                       "prop": "revisions|imageinfo", "rvprop": "content", "rvslots": "main",
                                       "iiprop": "size|mime", "redirects": "1",
                                       "titles": "|".join("File:" + c for c in chunk)}, cache_dir="art_v2/pages")
        if not obj:
            continue
        q = obj.get("query") or {}
        back = {}
        for n in (q.get("normalized") or []) + (q.get("redirects") or []):
            back[n["to"]] = n["from"]
        for page in q.get("pages") or []:
            title = page.get("title", "")
            origin = back.get(title, title)
            origin = back.get(origin, origin)
            fn = origin.split(":", 1)[-1]
            if fn not in chunk:
                continue
            if page.get("missing") or not page.get("revisions"):
                files[fn] = {"class": "missing", "page_status": "missing"}
                continue
            text = page["revisions"][0]["slots"]["main"]["content"]
            with gzip.open(_raw_path("File:" + fn) + ".tmp", "wt", encoding="utf-8") as f:
                json.dump({"title": "File:" + fn, "text": text, "status": "ok", "fetched": time.strftime("%Y-%m-%d")}, f)
            os.replace(_raw_path("File:" + fn) + ".tmp", _raw_path("File:" + fn))
            cls, tmpl, _ = P.license_class(text)
            v = {"class": cls, "template": tmpl, "page_status": "ok",
                 "categories": sorted({c.strip() for c in re.findall(r"\[\[\s*Category\s*:\s*([^\]|]+)", text, re.I)})}
            v.update(P.file_facts(text))
            info = (page.get("imageinfo") or [None])[0]
            if info and info.get("width") and info.get("height"):
                v["width"], v["height"], v["mime"] = int(info["width"]), int(info["height"]), info.get("mime")
            files[fn] = v
        wj("files.json.gz", files)
        print(f"  pages {min(i + PAGE_BATCH, len(todo))}/{len(todo)}", flush=True)
    wj("files.json.gz", files)


def all_candidate_names(con, lead, search, plays):
    """Every file any V2 stage would consider: lead images Wikipedia calls free, search hits, the free
    publicity crawl's files whose title or categories name a program, and the plays' work and author files."""
    out = []
    for t, v in sorted(lead.items()):
        if v.get("free"):
            out.append(v["free"])
    for k in sorted(search):
        out += search[k]
    for pid in sorted(plays):
        p = plays[pid]
        out += (p.get("work") or {}).get("files", [])
        out += (p.get("author") or {}).get("files", [])
    return out


# ---------------------------------------------------------------- H7: plays

def library_plays():
    """The play library's works: (id, title, [authors: name, born, died]) from the Gutenberg harvest, restricted
    to the ids of the published library when its index is at hand (catalog/out/plays-library/index.json)."""
    plays = json.load(open(os.path.join(CACHE, "gutenberg", "plays.json")))["plays"]
    keep = None
    idx = os.path.join(OUT, "plays-library", "index.json")
    if os.path.exists(idx):
        keep = {re.sub(r"^(gut-[0-9]+)-[0-9]+$", r"\1", r["id"]) for r in json.load(open(idx))["plays"]}
    out = []
    for p in plays:
        if keep is not None and p["id"] not in keep:
            continue
        out.append((p["id"], p["title"], [a for a in p.get("authors") or [] if a.get("role", "author") == "author"]))
    return out


def author_person(a):
    """A Gutenberg author as the people harvest's person dict (Last, First flipped)."""
    name = a["name"]
    if "," in name:
        last, first = [x.strip() for x in name.split(",", 1)]
        name = f"{first} {last}".strip()
    return {"id": "gut-author:" + a["name"], "name": name, "names": [], "birth_name": None,
            "birth": str(a["born"]) if a.get("born") else None, "death": str(a["died"]) if a.get("died") else None,
            "first_year": None}


def play_title(t):
    return AP.play_title(t)


def phase_plays(plays_out, limit=None):
    import harvest_people_wikidata as HP
    import enrich_people_art as P
    works = library_plays()
    if limit:
        works = works[:limit]
    print(f"plays: {len(works)} works", flush=True)
    # authors: the same dated person match the radio people get (enrich_people_art.decide)
    authors = {}
    for _id, _t, auths in works:
        for a in auths:
            if a.get("born") or a.get("died"):
                authors.setdefault(a["name"], author_person(a))
    people = sorted(authors.values(), key=lambda p: p["id"])
    names_idx, ents = HP._rj("names.json.gz", {}), HP._rj("entities.json.gz", {})
    HP.phase_names(people, names_idx)
    HP.phase_entities(people, names_idx, ents)
    res = P.match_all(people, names_idx, ents)
    matched = {p["name"]: res[p["id"]] for p in people}
    author_of = {}
    for key, p in authors.items():
        q, basis, detail, _vs = res[p["id"]]
        if q and AP.dated_match(basis):
            author_of[key] = {"qid": q, "basis": basis, "died": (ents[q].get("death") or p["death"]),
                              "files": list(ents[q].get("images") or [])}
    # works: a Wikidata item labelled with the title, with an author (P50) and an image or scan
    titles = sorted({play_title(t) for _i, t, _a in works if len(play_title(t)) >= 4})
    work_rows = {}
    for i in range(0, len(titles), 100):
        chunk = titles[i:i + 100]
        vals = " ".join(f"{HP._lit(t)}@en" for t in chunk)
        rows = wm.sparql(f"""SELECT ?t ?x ?al ?d ?img ?scan WHERE {{ VALUES ?t {{ {vals} }}
            ?x rdfs:label ?t ; wdt:P50 ?a . ?a rdfs:label ?al FILTER(lang(?al)="en")
            OPTIONAL {{ ?x schema:description ?d FILTER(lang(?d)="en") }}
            OPTIONAL {{ ?x wdt:P18 ?img }} OPTIONAL {{ ?x wdt:P996 ?scan }} }}""", cache_dir="art_v2/sparql")
        if rows is None:
            print(f"  works batch {i}: FAILED", file=sys.stderr)
            continue
        for r in rows:
            w = work_rows.setdefault((r["t"], wm.qid(r["x"])), {"label": r["t"], "qid": wm.qid(r["x"]), "authors": [],
                                                                  "description": r.get("d"), "files": []})
            if r["al"] not in w["authors"]:
                w["authors"].append(r["al"])
            for k in ("img", "scan"):
                if r.get(k) and "Special:FilePath/" in r[k]:
                    fn = urllib.parse.unquote(r[k].split("Special:FilePath/", 1)[1])
                    if fn not in w["files"]:
                        w["files"].append(fn)
        print(f"  works {min(i + 100, len(titles))}/{len(titles)}", flush=True)
    by_title = {}
    for (t, _q), w in work_rows.items():
        by_title.setdefault(t, []).append(w)
    out = plays_out
    for n, (pid, title, auths) in enumerate(works, 1):
        names = [a["name"] for a in auths]
        surnames = sorted({AP.surname_of(n) for n in names})
        rec = out.setdefault(pid, {})
        rec["title"], rec["authors"] = title, names
        pt = play_title(title)
        rec["work"] = next(({"qid": w["qid"], "files": w["files"], "label": w["label"]}
                            for w in by_title.get(pt, []) if w["files"] and AP.work_served(pt, surnames, w)), None)
        arec = next((author_of[n] for n in names if n in author_of), None)
        rec["author"] = arec
        if "edition" not in rec or (rec["edition"] or {}).get("failed") or rec.get("edition_v") != 2:
            rec["edition_v"] = 2
            rec["edition"] = find_edition(pt, surnames)
        if n % 50 == 0:
            wj("plays.json.gz", out)
    wj("plays.json.gz", out)
    print(f"plays: {sum(1 for r in out.values() if r.get('work'))} works with a file, "
          f"{sum(1 for r in out.values() if r.get('author'))} authors matched on a date, "
          f"{sum(1 for r in out.values() if r.get('edition'))} editions", flush=True)


IA_FIELDS = ["identifier", "title", "creator", "year", "date", "mediatype"]


def find_edition(title, surnames):
    """The earliest archive.org text a play's edition rule (art_policy.edition_served) passes, with the leaf its own
    scan data types as the title page; None when none passes (a missing title page is no edition here)."""
    if len(title) < 4 or not surnames or not any(len(s) >= 3 for s in surnames):
        return None
    sn = " OR ".join(s for s in surnames if len(s) >= 3)
    t = re.sub(r'["\\\[\]{}()^~*?:!<>=/+-]', " ", title).strip()
    q = (f'title:("{t}") AND creator:({sn}) AND mediatype:texts AND date:[1400-01-01 TO {AP.EDITION_LAST_YEAR}-12-31]')
    d = cached_ia(ia_lib.ADV, {"q": q, "fl[]": IA_FIELDS, "rows": 25, "output": "json", "sort[]": "date asc"})
    if d is None or "response" not in d:
        return {"failed": True}
    docs = [x for x in d["response"]["docs"] if AP.edition_served(title, surnames, x)]
    for x in docs[:3]:   # the earliest three that pass the edition rule; each costs two reads
        leaf = title_leaf(x["identifier"], title, surnames)
        if leaf:
            return {"id": x["identifier"], "title": x.get("title"), "creator": x.get("creator"), "year": x.get("year"),
                    "leaf": leaf["index"], "width": leaf["width"], "height": leaf["height"]}
    return None


def cached_ia(url, params, pause=1.0):
    key = hashlib.sha1((url + json.dumps(params, sort_keys=True)).encode()).hexdigest()
    p = os.path.join(DIR, "ia", key + ".json.gz")
    if os.path.exists(p):
        with gzip.open(p, "rt", encoding="utf-8") as f:
            return json.load(f)
    d = ia_lib.get(url, params, pause=pause)
    if d is not None and "response" in d:
        write_json(p, d, gz=True)
    return d


def _range(url, nbytes):
    req = urllib.request.Request(url, headers={"User-Agent": wm.UA, "Range": f"bytes=0-{nbytes}"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=90) as r:
                return r.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as e:
            if e.code == 429:
                ra = e.headers.get("Retry-After")
                time.sleep(max(5.0, float(ra) if ra and ra.isdigit() else 5.0))
                continue
            return None
        except Exception:  # noqa: BLE001
            time.sleep(3)
    return None


def scan_title_leaf(xml):
    """(index among the leaves in the page list, width, height) of the leaf typed Title in archive.org's scan data:
    a leaf with addToAccessFormats false is not in the page list, so it does not count in the index."""
    index = 0
    for m in re.finditer(r"<page\b[^>]*>(.*?)</page>", xml, re.S):
        pg = m.group(1)
        if re.search(r"<addToAccessFormats>\s*false\s*<", pg):
            continue
        if re.search(r"<pageType>\s*Title\s*</pageType>", pg):
            w, h = re.search(r"<origWidth>(\d+)", pg), re.search(r"<origHeight>(\d+)", pg)
            return (index, int(w.group(1)), int(h.group(1))) if w and h else None
        index += 1
    return None


def ocr_pages(xml):
    objs = re.findall(r"<OBJECT\b[^>]*>(.*?)(?=<OBJECT\b|$)", xml, re.S)
    return [re.sub(r"\s+", " ", " ".join(re.findall(r">([^<]+)</WORD>", o))) for o in objs]


def title_leaf(identifier, title, surnames):
    """{index, width, height} of the leaf that is this edition's title page, as the `n<index>` of archive.org's
    page-image URL, or None. Two of archive.org's own records must agree (art_policy.title_page_agrees): the scan
    data's Title leaf and a leaf whose OCR is a title page of this play (art_policy.title_page_ocr)."""
    key = hashlib.sha1((identifier + "|" + title).encode()).hexdigest()
    p = os.path.join(DIR, "ia", "titleleaf-" + key + ".json.gz")
    if os.path.exists(p):
        with gzip.open(p, "rt", encoding="utf-8") as f:
            return json.load(f)
    scan = _range(f"https://archive.org/download/{identifier}/{identifier}_scandata.xml", 100000)
    time.sleep(1.0)
    leaf = None
    if scan:
        st = scan_title_leaf(scan)
        ocr = _range(f"https://archive.org/download/{identifier}/{identifier}_djvu.xml", 260000)
        time.sleep(1.0)
        if st and ocr:
            oi = AP.title_page_ocr(ocr_pages(ocr), title, surnames)
            if AP.title_page_agrees(st[0], oi):
                leaf = {"index": st[0], "width": st[1], "height": st[2]}
    write_json(p, leaf, gz=True)
    return leaf


# ---------------------------------------------------------------- H9: liveness

def head(url):
    """The final status of a HEAD, following redirects (Commons' FilePath redirects to upload.wikimedia.org);
    None for a 429, a 5xx or a failure: a transient answer is never a death."""
    delay = 5.0
    for _ in range(4):
        req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": wm.UA})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.status
        except urllib.error.HTTPError as e:
            if e.code == 429:
                ra = e.headers.get("Retry-After")
                time.sleep(max(delay, float(ra) if ra and ra.isdigit() else 0))
                delay = min(delay * 2, 120)
                continue
            return e.code
        except Exception:  # noqa: BLE001 - recorded as unknown
            time.sleep(delay)
            delay = min(delay * 2, 120)
    return None


def phase_liveness(files, live, today=None):
    today = today or datetime.date.today().toordinal()
    todo = [f for f in files if AP.liveness_stale(live.get(f), today)]
    print(f"liveness: {len(todo)} of {len(files)} files to check", flush=True)
    for i, f in enumerate(todo):
        url = f if f.startswith("http") else AP.image_url(f) + "?width=330"
        verdict = AP.liveness_verdict(head(url))
        if verdict:
            live[f] = {"verdict": verdict, "day": today}
        time.sleep(1.0)
        if i % 50 == 0 or i == len(todo) - 1:
            wj("liveness.json.gz", live)
            print(f"  liveness {i + 1}/{len(todo)} (gone {sum(1 for v in live.values() if v['verdict'] == 'gone')})", flush=True)
    wj("liveness.json.gz", live)


def served_files(con):
    """Every file this stage's output may serve: the served show images and the plays' pictures."""
    import play_art
    return sorted(set(f for (f,) in con.execute("SELECT DISTINCT file FROM series_art WHERE served = 1"))
                  | set(play_art.liveness_files()))


def play_page_url(e):
    return f"https://archive.org/download/{e['id']}/page/n{e['leaf']}_w800.jpg"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--phase", choices=["lead", "search", "pages", "plays", "liveness", "faces", "all"], default="all")
    ap.add_argument("--db", default=os.path.join(OUT, "radio-catalog.sqlite"))
    ap.add_argument("--top", type=int, default=500, help="search: the N most-heard programs")
    ap.add_argument("--limit", type=int, help="plays: only the first N works (a trial)")
    ap.add_argument("--detector", help="faces: the compiled face_boxes.swift")
    ap.add_argument("--thumbs", default=os.path.join(os.environ.get("TMPDIR", "/tmp"), "eardrama-face-thumbs"))
    a = ap.parse_args()
    os.makedirs(DIR, exist_ok=True)
    con = db_connect(a.db)
    lead, search, files, plays, live = (rj(n, {}) for n in ("lead.json.gz", "search.json.gz", "files.json.gz",
                                                          "plays.json.gz", "liveness.json.gz"))
    if a.phase in ("lead", "all"):
        phase_lead(con, lead)
    if a.phase in ("search", "all"):
        phase_search(con, search, a.top)
    if a.phase in ("plays", "all"):
        phase_plays(plays, a.limit)
    if a.phase in ("pages", "all"):
        phase_pages(all_candidate_names(con, lead, search, plays), files)
    if a.phase == "liveness":
        phase_liveness(served_files(con), live)
    if a.phase == "faces":
        import harvest_people_wikidata as HP
        if not a.detector:
            ap.error("--phase faces needs --detector (swiftc -O -o face_boxes tools/face_boxes.swift)")
        import play_art
        served = {f for (f,) in con.execute("SELECT DISTINCT file FROM series_art WHERE served = 1")}
        served |= set(play_art.served_files())   # a playwright's portrait is cropped on the face too
        sub = {f: v for f, v in files.items() if f in served}
        HP.phase_faces(sub, a.detector, a.thumbs, out=os.path.join(DIR, "faces-tmp.json.gz"))
        fresh = rj("files.json.gz", {})   # another phase may have written since this one began: merge the faces in
        for f, v in sub.items():
            fresh.setdefault(f, {}).update({k: v[k] for k in ("faces", "face", "face_by") if k in v})
        wj("files.json.gz", fresh)
        files = fresh
    write_json(os.path.join(DIR, "failed.json"), wm.FAILED)
    print(f"lead {len(lead)}, search {len(search)}, files {len(files)}, plays {len(plays)}, live {len(live)}, "
          f"failed {len(wm.FAILED)}")


if __name__ == "__main__":
    main()
