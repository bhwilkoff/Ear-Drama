"""Harvest Project Gutenberg's drama shelf as castable-play candidates: facts
and evidence only, never a summary.

Gutenberg's robot policy (read 2026-10-22, gutenberg.org/policy/robot_access.html):
"The Project Gutenberg website is intended for human users only", and catalog
data comes from the offline catalogs, which "are granted to the public domain"
(gutenberg.org/ebooks/offline_catalogs.html: "Please use one of these files ...
instead of crawling or roboting the website"). robots.txt disallows only
/ebooks/search. So this reads two files from /cache/epub/feeds/ (the weekly CSV
and the daily RDF tarball), once each, and plain texts only from a mirror
(aleph.pglaf.org), one at a time with a pause, and only with --texts.

What it records for each English drama record (title, authors with their
dates, translators, Gutenberg's own rights statement, the source URL, a
LibriVox cast size where LibriVox read the same text) is a fact with a link.
Gutenberg's metadata "does not include the original print source publication
date(s)" (offline catalogs page), so `year` is set only from evidence a reader
can open: a copyright line in the text's own front matter (with --texts) or
the source year LibriVox recorded for its reading of this exact text.

    python3 tools/harvest_gutenberg_plays.py            # catalog + RDF, no texts
    python3 tools/harvest_gutenberg_plays.py --texts 20 # plus a seeded sample of texts
    python3 tools/harvest_gutenberg_plays.py --rsync-castable   # every rights-cleared play's text, one rsync session

Decision 075: the library is every rights-cleared play that parses clean. Texts for all of
them come over the project's own rsync mirror (aleph.gutenberg.org::gutenberg, the route its
mirroring page documents for bulk copies): one session, a file list of the three plain-text
names per id, no per-file website requests.
Output: .cache/gutenberg/plays.json
"""
import bz2
import csv
import gzip
import io
import json
import os
import random
import re
import shutil
import subprocess
import sys
import tarfile
import time
import urllib.request
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(__file__))
import ia_lib as ia

UA = "EarDrama/0.1 (+https://eardrama.org)"
FEEDS = "https://www.gutenberg.org/cache/epub/feeds/"
MIRROR = "https://aleph.pglaf.org"
DELAY = 3
SHELF = "Category: Plays/Films/Dramas"
NS = {"rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#", "dcterms": "http://purl.org/dc/terms/",
      "pgterms": "http://www.gutenberg.org/2009/pgterms/", "marcrel": "http://id.loc.gov/vocabulary/relators/"}
COPYRIGHT_LINE = re.compile(r"^.{0,40}\bcopyright(?:ed)?\b[^\n]{0,40}?\b(1[89]\d\d)\b.*$", re.I | re.M)
PG_ID = re.compile(r"gutenberg\.org/(?:ebooks|etext|files)/(\d+)")


def download(url, path):
    if os.path.exists(path):
        return path
    os.makedirs(os.path.dirname(path), exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    tmp = path + ".part"
    with urllib.request.urlopen(req, timeout=600) as r, open(tmp, "wb") as f:
        while chunk := r.read(1 << 20):
            f.write(chunk)
    os.replace(tmp, path)
    time.sleep(DELAY)
    return path


def is_drama(row):
    shelves = [s.strip() for s in (row["Bookshelves"] or "").split(";")]
    subjects = [s.strip() for s in (row["Subjects"] or "").split(";")]
    return SHELF in shelves or any(re.search(r"\bDrama\b", s) for s in subjects)


def read_catalog(path):
    with gzip.open(path, "rt", encoding="utf-8", newline="") as f:
        return [row for row in csv.DictReader(f) if row["Type"] == "Text"]


def _agent(el):
    a = el.find("pgterms:agent", NS)
    if a is None:
        return None
    def txt(tag):
        e = a.find(tag, NS)
        return e.text.strip() if e is not None and e.text else None
    born, died = txt("pgterms:birthdate"), txt("pgterms:deathdate")
    return {"name": txt("pgterms:name"), "born": int(born) if born and born.lstrip("-").isdigit() else None,
            "died": int(died) if died and died.lstrip("-").isdigit() else None}


def parse_rdf(blob):
    root = ET.fromstring(blob)
    eb = root.find("pgterms:ebook", NS)
    if eb is None:
        return None
    def vals(path):
        return [v.text.strip() for v in eb.findall(path, NS) if v.text]
    people = []
    for tag, role in (("dcterms:creator", "author"), ("marcrel:trl", "translator"), ("marcrel:edt", "editor"),
                      ("marcrel:aui", "introduction")):
        for el in eb.findall(tag, NS):
            a = _agent(el)
            if a:
                people.append({**a, "role": role})
    rights = vals("dcterms:rights")
    return {"rights": rights[0] if rights else None, "people": people,
            "issued": (vals("dcterms:issued") or [None])[0],
            "subjects": vals("dcterms:subject/rdf:Description/rdf:value"),
            "shelves": vals("pgterms:bookshelf/rdf:Description/rdf:value"),
            "language": vals("dcterms:language/rdf:Description/rdf:value")}


def read_rdf(path, wanted):
    out = {}
    with tarfile.open(path, "r|bz2") as tar:
        for m in tar:
            mm = re.search(r"/pg(\d+)\.rdf$", m.name)
            if not mm or mm.group(1) not in wanted:
                continue
            rec = parse_rdf(tar.extractfile(m).read())
            if rec:
                out[mm.group(1)] = rec
    return out


def librivox_casts():
    """Gutenberg id -> LibriVox projects that read that exact text, with the cast size
    LibriVox printed (role names only are counted; no description text is kept)."""
    path = os.path.join(ia.CACHE, "librivox.json.gz")
    if not os.path.exists(path):
        return {}
    out = {}
    for b in json.load(gzip.open(path, "rt")):
        m = PG_ID.search(b.get("url_text_source") or "")
        if not m:
            continue
        desc = b.get("description") or ""
        cast = None
        c = re.search(r"cast(?: list)?\s*:?\s*(?:</b>)?\s*<br\s*/?>(.*)", desc, re.I | re.S)
        if c:
            rows = []
            for line in re.split(r"<br\s*/?>", c.group(1)):
                t = re.sub(r"<[^>]+>", "", line).strip()
                if not t:
                    if rows:
                        break
                    continue
                if not re.search(r"\s[-:–]\s|:\s", t):
                    break
                rows.append(t)
            cast = len(rows) or None
        yr = b.get("copyright_year")
        out.setdefault(m.group(1), []).append({
            "id": b["id"], "url": b.get("url_librivox"), "cast_size": cast,
            "source_year": int(yr) if yr and yr.isdigit() else None})
    return out


def text_path(pid):
    return os.path.join(ia.CACHE, "gutenberg", "text", pid + ".txt")


def fetch_text(pid):
    path = text_path(pid)
    if os.path.exists(path):
        return path
    d = "/".join(pid[:-1]) if len(pid) > 1 else "0"
    for name in (f"{pid}-0.txt", f"{pid}.txt", f"{pid}-8.txt"):
        body = ia.get(f"{MIRROR}/{d}/{pid}/{name}", ua=UA, raw=True, tries=2, timeout=90)
        time.sleep(DELAY)
        if body:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as f:
                f.write(body)
            return path
    return None


RSYNC = "aleph.gutenberg.org::gutenberg"


def rsync_dir(pid):
    return "/".join(pid[:-1]) if len(pid) > 1 else "0"


def rsync_texts(pids):
    """Fetch the plain texts of `pids` that are not cached, in one rsync session. Of the names a
    book may carry, -0.txt (UTF-8) wins over .txt over -8.txt, as fetch_text's order does."""
    todo = [p for p in sorted(pids) if not os.path.exists(text_path(p))]
    if not todo:
        return 0
    stage = os.path.join(ia.CACHE, "gutenberg", "rsync")
    os.makedirs(stage, exist_ok=True)
    names = [f"{rsync_dir(p)}/{p}/{p}{suf}.txt" for p in todo for suf in ("-0", "", "-8")]
    listing = os.path.join(stage, "files-from.txt")
    with open(listing, "w") as f:
        f.write("\n".join(names) + "\n")
    # Exit 23/24 mean some listed names do not exist (a book has one of three names): expected.
    r = subprocess.run(["rsync", "-rt", "--files-from", listing, "--timeout=120", RSYNC + "/", stage + "/"],
                       capture_output=True, text=True)
    if r.returncode not in (0, 23, 24):
        raise SystemExit(f"rsync failed ({r.returncode}): {r.stderr[-400:]}")
    got = 0
    for p in todo:
        for suf in ("-0", "", "-8"):
            src = os.path.join(stage, rsync_dir(p), p, f"{p}{suf}.txt")
            if os.path.exists(src):
                os.makedirs(os.path.dirname(text_path(p)), exist_ok=True)
                shutil.copyfile(src, text_path(p))
                got += 1
                break
    shutil.rmtree(stage)
    return got


def castable_ids(plays):
    import datetime
    import script_rights as R
    ev = json.load(open(R.EDITORIAL))
    ren = json.load(gzip.open(os.path.join(R.CACHE, "cce_drama_renewals.json.gz"), "rt"))
    ctx = {"renewals": R.renewal_index(ren), "takedowns": ev.get("takedowns", {}), "today": datetime.date.today()}
    return [p["id"][4:] for p in plays if R.judge(R.from_gutenberg(p), ctx)["castable"]]


def front_matter_year(path):
    t = open(path, encoding="utf-8", errors="replace").read()
    a = re.search(r"\*\*\* ?START OF TH(?:E|IS) PROJECT GUTENBERG[^\n]*\n", t)
    head = t[a.end() if a else 0:][:6000]
    m = COPYRIGHT_LINE.search(head)
    return (int(m.group(1)), m.group(0).strip()) if m else (None, None)


def record(row, rdf, lv):
    pid = row["Text#"]
    people = (rdf or {}).get("people") or []
    rec = {"id": f"gut-{pid}", "source": "Project Gutenberg", "title": row["Title"].replace("\n", " ").strip(),
           "authors": [p for p in people if p["role"] == "author"],
           "translators": [p for p in people if p["role"] == "translator"],
           "year": None, "year_basis": None,
           "source_url": f"https://www.gutenberg.org/ebooks/{pid}",
           "rights": {"text": (rdf or {}).get("rights"), "src": f"https://www.gutenberg.org/ebooks/{pid}.rdf"},
           "subjects": (rdf or {}).get("subjects") or [s.strip() for s in row["Subjects"].split(";") if s.strip()],
           "shelves": (rdf or {}).get("shelves") or [s.strip() for s in row["Bookshelves"].split(";") if s.strip()],
           "librivox": lv or [], "evidence": []}
    if rec["rights"]["text"]:
        rec["evidence"].append({"claim": rec["rights"]["text"], "src": rec["rights"]["src"]})
    years = [p["source_year"] for p in lv or [] if p.get("source_year")]
    if years:
        rec["year"], rec["year_basis"] = min(years), "librivox_source_year"
        rec["evidence"].append({"claim": f"LibriVox source year {min(years)}", "src": lv[0]["url"]})
    return rec


def main():
    out = os.path.join(ia.CACHE, "gutenberg")
    cat = read_catalog(download(FEEDS + "pg_catalog.csv.gz", os.path.join(out, "pg_catalog.csv.gz")))
    drama = [r for r in cat if is_drama(r)]
    english = [r for r in drama if "en" in (r["Language"] or "").split("; ")]
    if len(english) < 1000:
        raise SystemExit(f"only {len(english)} English drama records: the catalog shape changed")
    rdf = read_rdf(download(FEEDS + "rdf-files.tar.bz2", os.path.join(out, "rdf-files.tar.bz2")),
                   {r["Text#"] for r in english})
    lv = librivox_casts()
    plays = [record(r, rdf.get(r["Text#"]), lv.get(r["Text#"])) for r in english]
    n = int(sys.argv[sys.argv.index("--texts") + 1]) if "--texts" in sys.argv else 0
    if n:
        pool = [p for p in plays if (p["rights"]["text"] or "").startswith("Public domain")]
        random.Random(20261022).shuffle(pool)
        got = 0
        for p in pool:
            if got >= n:
                break
            path = fetch_text(p["id"][4:])
            if not path:
                continue
            got += 1
            p["text_cached"] = True
            y, line = front_matter_year(path)
            if y and (p["year"] is None or y < p["year"]):
                p["year"], p["year_basis"] = y, "front_matter_copyright"
                p["evidence"].append({"claim": line[:160], "src": p["source_url"]})
    if "--rsync-castable" in sys.argv:
        ids = castable_ids(plays)
        got = rsync_texts(ids)
        have = sum(os.path.exists(text_path(p)) for p in ids)
        print(f"rights-cleared {len(ids)}, fetched {got}, cached {have}", file=sys.stderr)
    ia.write_json(os.path.join(out, "plays.json"), {"catalog_rows": len(cat), "drama_all_languages": len(drama),
                                                   "english": len(english), "rdf_read": len(rdf), "plays": plays})
    print(f"{len(cat)} texts, {len(drama)} drama, {len(english)} English, {len(rdf)} RDF records", file=sys.stderr)
    if not plays or len(rdf) < len(english) * 0.9:
        sys.exit(1)


if __name__ == "__main__":
    main()
