"""Wikidata humans for credited radio people, and the Commons pages of their portraits.

    python3 tools/harvest_people_wikidata.py                 # all three phases, resumable
    python3 tools/harvest_people_wikidata.py --top 2000      # only the 2,000 most-credited
    python3 tools/harvest_people_wikidata.py --phase commons # one phase
    python3 tools/harvest_people_wikidata.py --phase dims    # each file's width and height

Reads out/radio-catalog.sqlite (people + episode_credits) for the names, most
credited first, and writes under .cache/people_wd/:
  names.json.gz     {name variant: [qid of each human (P31 Q5) whose en/mul label
                     or alias is exactly that string]}
  entities.json.gz  {qid: label, description, birth/death (day precision or
                     coarser, with the years at year precision or better),
                     occupations (en labels), images (P18), imdb (P345),
                     commons_category (P373), enwiki}
  files.json.gz     {file name: licence class, template, author, date, source
                     links, page status} for each P18 of a MATCHED person and each
                     of Track D's Commons files whose Structured Data depicts one;
                     the dims phase adds the original's width and height, read
                     from the Action API's imageinfo (size only), 50 files a call
  failed.json       requests that could not be read
Both files are rewritten as each batch lands, so a killed run resumes where it
stopped. All Wikidata reads go through the query service (SPARQL), whose bodies
harvest_ext_wm.call also caches; Commons pages through index.php?action=raw,
1.5 s apart (the Action API answered this egress 429 on 2026-10-19). Track D's
cached Commons pages (.cache/commons/raw) are read first. No image binary is
ever downloaded. Exits non-zero when nothing could be read.
"""
import argparse
import gzip
import hashlib
import json
import os
import sqlite3
import sys
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ia_lib import CACHE, write_json  # noqa: E402
import harvest_ext_wm as wm  # noqa: E402
import enrich_people_art as P  # noqa: E402

DIR = os.path.join(CACHE, "people_wd")
HOST = "commons.wikimedia.org"


def _rj(name, default):
    p = os.path.join(DIR, name)
    if not os.path.exists(p):
        return default
    with gzip.open(p, "rt", encoding="utf-8") as f:
        return json.load(f)


def _lit(s):
    return json.dumps(s, ensure_ascii=False)


def phase_names(people, names_idx, batch=150):
    todo = []
    for p in people:
        for v in P.name_variants(p["name"], p["names"], p["birth_name"]):
            if v not in names_idx and v not in todo:
                todo.append(v)
    print(f"names: {len(todo)} variants to ask", flush=True)
    for i in range(0, len(todo), batch):
        chunk = todo[i:i + batch]
        vals = " ".join(f"{_lit(v)}@en {_lit(v)}@mul" for v in chunk)
        rows = wm.sparql(f"""SELECT ?name ?x WHERE {{ VALUES ?name {{ {vals} }}
            ?x rdfs:label|skos:altLabel ?name . ?x wdt:P31 wd:Q5 }}""", cache_dir="people_wd/sparql")
        if rows is None:
            print(f"  names batch {i}: FAILED", file=sys.stderr)
            continue
        got = {v: [] for v in chunk}
        for r in rows:
            q = wm.qid(r["x"])
            if r["name"] in got and q not in got[r["name"]]:
                got[r["name"]].append(q)
        names_idx.update(got)
        if (i // batch) % 10 == 0 or i + batch >= len(todo):
            write_json(os.path.join(DIR, "names.json.gz"), names_idx, gz=True)
            print(f"  names {i + len(chunk)}/{len(todo)}", flush=True)
    write_json(os.path.join(DIR, "names.json.gz"), names_idx, gz=True)


def fetch_entities(qids):
    vals = " ".join("wd:" + q for q in qids)
    base = wm.sparql(f"""SELECT ?x ?l ?lm ?d ?en WHERE {{ VALUES ?x {{ {vals} }}
        OPTIONAL {{ ?x rdfs:label ?l FILTER(lang(?l)="en") }}
        OPTIONAL {{ ?x rdfs:label ?lm FILTER(lang(?lm)="mul") }}
        OPTIONAL {{ ?x schema:description ?d FILTER(lang(?d)="en") }}
        OPTIONAL {{ ?en schema:about ?x ; schema:isPartOf <https://en.wikipedia.org/> }} }}""",
                     cache_dir="people_wd/sparql")
    dates = wm.sparql(f"""SELECT ?x ?k ?t ?prec WHERE {{ VALUES ?x {{ {vals} }}
        {{ ?x p:P569/psv:P569 [ wikibase:timeValue ?t ; wikibase:timePrecision ?prec ] BIND("b" AS ?k) }} UNION
        {{ ?x p:P570/psv:P570 [ wikibase:timeValue ?t ; wikibase:timePrecision ?prec ] BIND("d" AS ?k) }} }}""",
                      cache_dir="people_wd/sparql")
    claims = wm.sparql(f"""SELECT ?x ?k ?v ?vl WHERE {{ VALUES ?x {{ {vals} }}
        {{ ?x wdt:P106 ?v . OPTIONAL {{ ?v rdfs:label ?vl FILTER(lang(?vl)="en") }} BIND("occ" AS ?k) }} UNION
        {{ ?x wdt:P18 ?v BIND("img" AS ?k) }} UNION {{ ?x wdt:P345 ?v BIND("imdb" AS ?k) }} UNION
        {{ ?x wdt:P373 ?v BIND("cat" AS ?k) }} }}""", cache_dir="people_wd/sparql")
    if base is None or dates is None or claims is None:
        return None
    out = {q: {"label": None, "description": None, "enwiki": None, "birth": None, "death": None,
               "birth_years": [], "death_years": [], "occupations": [], "images": [], "imdb": [],
               "commons_category": []} for q in qids}
    for r in base:
        e = out[wm.qid(r["x"])]
        e["label"] = r.get("l") or r.get("lm") or e["label"]
        e["description"] = r.get("d") or e["description"]
        if r.get("en"):
            e["enwiki"] = urllib.parse.unquote(r["en"].rsplit("/wiki/", 1)[1]).replace("_", " ")
    for r in dates:
        e = out[wm.qid(r["x"])]
        prec = int(r.get("prec") or 0)
        t = r.get("t") or ""
        if prec < 9 or not t or t.startswith("-"):
            continue
        y = int(t[:4])
        k = "birth" if r["k"] == "b" else "death"
        if y not in e[k + "_years"]:
            e[k + "_years"].append(y)
        if e[k] is None:
            e[k] = t[:10] if prec >= 11 else (t[:7] if prec == 10 else t[:4])
    for r in claims:
        e = out[wm.qid(r["x"])]
        v = r.get("v")
        if r["k"] == "occ":
            v = r.get("vl") or wm.qid(v)
            lst = e["occupations"]
        elif r["k"] == "img":
            v = urllib.parse.unquote(v.split("Special:FilePath/", 1)[1]) if "Special:FilePath/" in v else v
            lst = e["images"]
        elif r["k"] == "imdb":
            lst = e["imdb"]
        else:
            lst = e["commons_category"]
        if v not in lst:
            lst.append(v)
    return out


def phase_entities(people, names_idx, ents, batch=200):
    todo = []
    seen = set(ents)
    for p in people:
        for v in P.name_variants(p["name"], p["names"], p["birth_name"]):
            for q in names_idx.get(v, []):
                if q not in seen:
                    seen.add(q)
                    todo.append(q)
    print(f"entities: {len(todo)} to fetch", flush=True)
    for i in range(0, len(todo), batch):
        got = fetch_entities(todo[i:i + batch])
        if got is None:
            print(f"  entities batch {i}: FAILED", file=sys.stderr)
            continue
        ents.update(got)
        if (i // batch) % 5 == 0 or i + batch >= len(todo):
            write_json(os.path.join(DIR, "entities.json.gz"), ents, gz=True)
            print(f"  entities {i + len(got)}/{len(todo)}", flush=True)
    write_json(os.path.join(DIR, "entities.json.gz"), ents, gz=True)


def _trackd_page(title):
    path = os.path.join(CACHE, "commons", "raw", hashlib.sha1((HOST + "|" + title).encode()).hexdigest() + ".json.gz")
    if os.path.exists(path):
        with gzip.open(path, "rt", encoding="utf-8") as f:
            o = json.load(f)
        return o["text"], o["status"]
    return None


def phase_commons(people, names_idx, ents, files, max_files=None):
    res = P.match_all(people, names_idx, ents)
    dep = P.depicts_index()
    todo = []
    for p in people:
        q = res[p["id"]][0]
        if not q:
            continue
        for fn in (ents[q].get("images") or []) + [t.split(":", 1)[1] for t in dep.get(q, [])]:
            if fn not in files and fn not in todo:
                todo.append(fn)
    if max_files:
        todo = todo[:max_files]
    print(f"commons: {len(todo)} file pages to read", flush=True)
    for i, fn in enumerate(todo):
        title = "File:" + fn.replace("_", " ")
        hit = _trackd_page(title)
        text, status = hit if hit else wm.raw_page(HOST, title, "people_wd/commons_raw")
        cls, tmpl, _ = P.license_class(text) if status == "ok" else (status, None, None)
        v = {"class": cls if status == "ok" else ("missing" if status == "missing" else "unread"),
             "template": tmpl, "page_status": status, "via_trackd_cache": bool(hit)}
        if text:
            v.update(P.file_facts(text))
        files[fn] = v
        if i % 50 == 0 or i == len(todo) - 1:
            write_json(os.path.join(DIR, "files.json.gz"), files, gz=True)
            print(f"  pages {i + 1}/{len(todo)}", flush=True)
    write_json(os.path.join(DIR, "files.json.gz"), files, gz=True)


def phase_dims(files, batch=50):
    """The original's width and height for each file page read: a client lays a portrait out
    by its shape before the image arrives (contract section 3.3), so the shape is published once."""
    todo = sorted(fn for fn, v in files.items() if v.get("page_status") == "ok" and "width" not in v)
    print(f"dims: {len(todo)} files to size", flush=True)
    for i in range(0, len(todo), batch):
        chunk = todo[i:i + batch]
        titles = {"File:" + fn.replace("_", " "): fn for fn in chunk}
        obj = wm.call(wm.COMMONS_API, {"action": "query", "format": "json", "prop": "imageinfo",
                                       "iiprop": "size", "titles": "|".join(titles)},
                      cache_dir="people_wd/imageinfo")
        if not obj:
            continue
        q = obj.get("query") or {}
        alias = {n["to"]: n["from"] for n in q.get("normalized") or []}
        for page in (q.get("pages") or {}).values():
            fn = titles.get(alias.get(page.get("title"), page.get("title")))
            info = (page.get("imageinfo") or [None])[0]
            if fn and info and info.get("width") and info.get("height"):
                files[fn]["width"], files[fn]["height"] = int(info["width"]), int(info["height"])
        write_json(os.path.join(DIR, "files.json.gz"), files, gz=True)
        print(f"  sized {min(i + batch, len(todo))}/{len(todo)}", flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--phase", choices=["names", "entities", "commons", "dims", "all"], default="all")
    ap.add_argument("--top", type=int, default=None, help="only the N most-credited people")
    ap.add_argument("--max-files", type=int, default=None)
    a = ap.parse_args()
    os.makedirs(DIR, exist_ok=True)
    con = sqlite3.connect(P.DB)
    people = P.ranked_people(con)[:a.top] if a.top else P.ranked_people(con)
    names_idx, ents, files = _rj("names.json.gz", {}), _rj("entities.json.gz", {}), _rj("files.json.gz", {})
    if a.phase in ("names", "all"):
        phase_names(people, names_idx)
    if a.phase in ("entities", "all"):
        phase_entities(people, names_idx, ents)
    if a.phase in ("commons", "all"):
        phase_commons(people, names_idx, ents, files, a.max_files)
    if a.phase in ("dims", "all"):
        phase_dims(files)
    write_json(os.path.join(DIR, "failed.json"), wm.FAILED)
    print(f"names {len(names_idx)}, entities {len(ents)}, files {len(files)}, failed {len(wm.FAILED)}")
    if not names_idx:
        sys.exit(1)


if __name__ == "__main__":
    main()
