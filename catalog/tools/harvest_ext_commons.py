"""Wikimedia Commons radio artwork, each file with the licence template that frees it.

    python3 tools/harvest_ext_commons.py      # after harvest_ext_wikidata.py

Files come from four places:
  1. the network publicity-photo categories (NBC/CBS/ABC/Mutual/Blue Radio
     publicity photos) and their subcategories, to depth 2;
  2. CirrusSearch: deepcat:"Radio programs from the United States" with each
     PD template (03-metadata-sources §0 C3 measured 452 no-notice, 147 not-renewed);
  3. P18 image / P154 logo of the Wikidata radio items;
  4. the Commons category (P373) of each US radio item, depth 1.
Listing and image info go through the query service's MWAPI bridge, the file
page's wikitext through action=raw (templates, categories, the |source= field),
and Structured Data "depicts" (P180) through Special:EntityData/M<pageid>: the
Commons Action API answered this IP 429 throughout 2026-10-19.

The file page is the evidence a reader opens; whether its evidence holds up
(the back of the print, the press stamp) is NOT judged here — the source links
from |source= are recorded so a person can. Never archive.org uploader art.

Writes .cache/commons/files.json.gz {title: {...}}, depicts_labels.json and
failed.json; exits non-zero when no file could be read.
"""
import gzip
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ia_lib import CACHE, write_json  # noqa: E402
import harvest_ext_wm as wm  # noqa: E402

DIR = os.path.join(CACHE, "commons")
HOST = "commons.wikimedia.org"
PUBLICITY = ["Category:NBC Radio publicity photos", "Category:CBS Radio publicity photos",
             "Category:ABC Radio publicity photos", "Category:Mutual Broadcasting System publicity photos",
             "Category:Blue Network publicity photos"]
SEARCH_TEMPLATES = ["PD-US-no notice", "PD-US-not renewed", "PD-US-expired",
                    "PD-US-no notice advertisement"]
# Template names (and the redirects seen on file pages) -> the class we record.
PD_ALIASES = {
    "pdusnonotice": "PD-US-no notice", "pdnonotice": "PD-US-no notice",
    "pdusnotrenewed": "PD-US-not renewed", "pdnotrenewed": "PD-US-not renewed",
    "pdusexpired": "PD-US-expired", "pd1923": "PD-US-expired", "pdus1923": "PD-US-expired",
    "pdusnonoticeadvertisement": "PD-US-no notice advertisement",
    "pdusdefectivenotice": "PD-US-defective notice", "pdus197889": "PD-US-1978-89",
}
OUTPUTS = {"title": "@title", "ns": "@ns", "pageid": "@pageid", "url": "imageinfo/ii/@url",
           "w": "imageinfo/ii/@width", "h": "imageinfo/ii/@height", "mime": "imageinfo/ii/@mime"}


def _add(files, rows, tag):
    for r in rows or []:
        if r.get("ns", "6") != "6":
            continue
        e = files.setdefault(r["title"], {"found_via": set()})
        e["found_via"].add(tag)
        if r.get("url"):
            e.update({"pageid": int(r["pageid"]), "url": r["url"].split("?utm_")[0],
                      "width": int(r["w"]) if r.get("w") else None,
                      "height": int(r["h"]) if r.get("h") else None, "mime": r.get("mime")})


def members(cat, depth, files, seen, limit=None):
    if cat in seen:
        return
    seen.add(cat)
    rows = wm.mwapi(HOST, {"generator": "categorymembers", "gcmtitle": cat.replace('"', '\\"'),
                           "gcmtype": "file|subcat", "gcmlimit": "max", "prop": "imageinfo",
                           "iiprop": "url|size|mime"}, OUTPUTS, "commons/mwapi", limit=limit)
    if rows is None:
        print(f"  {cat}: FAILED", file=sys.stderr)
        return
    _add(files, rows, cat)
    if depth > 0:
        for r in rows:
            if r.get("ns") == "14":
                members(r["title"], depth - 1, files, seen, limit)


def search(q, files, tag):
    rows = wm.mwapi(HOST, {"generator": "search", "gsrsearch": q.replace('"', '\\"'), "gsrnamespace": "6",
                           "gsrlimit": "max", "prop": "imageinfo", "iiprop": "url|size|mime"},
                    OUTPUTS, "commons/mwapi")
    if rows is None:
        print(f"  search {q}: FAILED", file=sys.stderr)
    _add(files, rows, tag)


def by_title(title, files, tag):
    """One named file (a Wikidata P18): its image info, via allimages from its name."""
    name = title.split(":", 1)[1].replace(" ", "_")
    rows = wm.mwapi(HOST, {"generator": "allimages", "gaifrom": name.replace('"', '\\"'), "gailimit": "1",
                           "prop": "imageinfo", "iiprop": "url|size|mime"}, OUTPUTS, "commons/mwapi")
    rows = [r for r in rows or [] if r["title"].replace(" ", "_") == "File:" + name]
    if rows:
        _add(files, rows, tag)


def template_class(text):
    """(class, template as written) of the first PD-US template on a file page."""
    for m in re.finditer(r"\{\{\s*([^|{}]+?)\s*(?:\||\}\})", text or ""):
        k = re.sub(r"[^a-z0-9]", "", m.group(1).lower())
        if k in PD_ALIASES:
            return PD_ALIASES[k], m.group(1).strip()
    return None, None


def license_short(text):
    m = re.search(r"\{\{\s*(cc-[a-z0-9.\-]+|PD-[A-Za-z0-9 .\-]+|GFDL[^|}]*|Copyrighted[^|}]*)", text or "", re.I)
    return m.group(1).strip() if m else None


def page_facts(text):
    cats = [c.strip() for c in re.findall(r"\[\[\s*Category\s*:\s*([^\]|]+)", text or "", re.I)]
    src = re.search(r"\|\s*source\s*=(.*?)(?:\n\s*\||\}\})", text or "", re.S | re.I)
    links = re.findall(r"https?://[^\s\]|}<]+", src.group(1))[:5] if src else []
    date = re.search(r"\|\s*date\s*=\s*([^\n|]*)", text or "", re.I)
    return {"categories": ["Category:" + c for c in cats], "source_links": links,
            "date_field": (date.group(1).strip()[:60] if date else None)}


def main():
    os.makedirs(DIR, exist_ok=True)
    files = {}
    seen = set()
    for c in PUBLICITY:
        members(c, 2, files, seen)
    print(f"publicity categories: {len(files)} files", flush=True)
    for t in SEARCH_TEMPLATES:
        search(f'deepcat:"Radio programs from the United States" hastemplate:"{t}"', files, f"search:{t}")
    print(f"+ search: {len(files)} files", flush=True)
    ip = os.path.join(CACHE, "wikidata", "items.json.gz")
    items = json.load(gzip.open(ip, "rt")) if os.path.exists(ip) else {}
    enw = os.path.join(CACHE, "wikidata", "enwiki_radio.json")
    american = {v["qid"] for v in json.load(open(enw)).values()} if os.path.exists(enw) else set()
    for q, it in items.items():
        us = "Q30" in it["props"].get("country", []) or q in american
        if not (us and it.get("radio_class")):
            continue
        for f in it["props"].get("image", []) + it["props"].get("logo", []):
            by_title("File:" + f, files, f"wikidata:{q}")
        for c in it["props"].get("commons_category", []):
            members("Category:" + c, 1, files, seen, limit=300)
    print(f"+ wikidata images and categories: {len(files)} files", flush=True)
    titles = sorted(t for t, v in files.items() if v.get("url"))
    for i, t in enumerate(titles):
        v = files[t]
        text, status = wm.raw_page(HOST, t, "commons/raw")
        v["page"] = "https://commons.wikimedia.org/wiki/" + t.replace(" ", "_")
        v["page_status"] = status
        if text is not None:
            v.update(page_facts(text))
            v["pd_class"], v["template"] = template_class(text)
            v["license_short"] = v["template"] or license_short(text)
        ed = wm.entity_data(HOST, f"M{v['pageid']}", "commons/sdc")
        st = (ed or {}).get("entities", {}).get(f"M{v['pageid']}", {}).get("statements") or {}
        v["depicts"] = [c["mainsnak"]["datavalue"]["value"]["id"] for c in
                        (st.get("P180", []) if isinstance(st, dict) else []) if c["mainsnak"].get("datavalue")]
        if i % 100 == 0:
            print(f"  pages {i}/{len(titles)}", flush=True)
    for v in files.values():
        v["found_via"] = sorted(v["found_via"])
    info = {t: files[t] for t in titles}
    dq = sorted({q for v in info.values() for q in v.get("depicts", [])})
    labels = {}
    for i in range(0, len(dq), 300):
        vals = " ".join("wd:" + q for q in dq[i:i + 300])
        rows = wm.sparql(f"""SELECT ?x ?l ?h WHERE {{ VALUES ?x {{ {vals} }}
            OPTIONAL {{ ?x rdfs:label ?l FILTER(lang(?l)="en") }}
            BIND(EXISTS {{ ?x wdt:P31 wd:Q5 }} AS ?h) }}""", cache_dir="commons/depicts")
        for r in rows or []:
            labels[wm.qid(r["x"])] = {"label": r.get("l"), "human": r.get("h") == "true"}
    write_json(os.path.join(DIR, "depicts_labels.json"), labels)
    write_json(os.path.join(DIR, "files.json.gz"), info, gz=True)
    write_json(os.path.join(DIR, "failed.json"), wm.FAILED)
    pd = sum(1 for v in info.values() if v.get("pd_class"))
    unread = sum(1 for v in info.values() if v.get("page_status") == "failed")
    print(f"{len(info)} files, {pd} with a PD-US template, {unread} pages unread; failed calls {len(wm.FAILED)}")
    if not info:
        sys.exit(1)


if __name__ == "__main__":
    main()
