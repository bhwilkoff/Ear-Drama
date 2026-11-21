"""Pages of unrenewed radio magazine issues that name a program or one of its marked people (R3b V5, Decision 040).

    python3 tools/harvest_magazine_pages.py   # first: fills .cache/magazine_pages/
    (run by enrich_series_art.write, after series_marks; no network)

Rebuilds one table, `magazine_pages`: a row per (series, issue page) that `art_policy.magazine_page_served`
accepts: the issue-year row of `magazine_rights` is not_renewed or pd_by_age, the page carries no notice of its
own, its text names the program (or a person its record marks), and the issue's year lies inside the run. The
projection judges each row again (build_projection.served_magazine_rows) and serves at most a few per program.
"""
import glob
import gzip
import json
import os
import re
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ia_lib import CACHE, OUT  # noqa: E402
import art_policy as AP  # noqa: E402
import photo_match as M  # noqa: E402

DIR = os.path.join(CACHE, "magazine_pages", "items")
PER_SERIES = 12

SCHEMA = """
DROP TABLE IF EXISTS magazine_pages;
CREATE TABLE magazine_pages (
  series_key TEXT, item_id TEXT, leaf INTEGER, magazine TEXT, issue_title TEXT, year INTEGER,
  tie TEXT, matched TEXT, words INTEGER, status TEXT, evidence_url TEXT, image_url TEXT,
  PRIMARY KEY (series_key, item_id, leaf)
);
"""


def page_url(item, leaf):
    return f"https://archive.org/download/{item}/page/n{leaf}_w800.jpg"


def issues():
    for path in sorted(glob.glob(os.path.join(DIR, "*.json.gz"))):
        with gzip.open(path, "rt", encoding="utf-8") as f:
            yield json.load(f)


def rows(con):
    tables = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
    if not {"series", "magazine_rights"} <= tables:
        return []
    status = {(t, y): st for t, y, st in con.execute("SELECT title, year, status FROM magazine_rights")}
    run = AP.run_dates(con)
    names = {k: n for k, n in con.execute("SELECT key, name FROM series") if M.series_name_ok(n)}
    pname = dict(con.execute("SELECT id, name FROM people")) if "people" in tables else {}
    marked = {}
    if "series_marks" in tables:
        for k, pid in con.execute("SELECT series_key, person_id FROM series_marks"):
            if pname.get(pid):
                marked.setdefault(k, []).append(pname[pid])
    by_first = {}
    for k, n in names.items():
        w = [x for x in M.fold(re.sub(r"^the ", "", M.fold(n))).split() if x]
        if w:
            by_first.setdefault(w[0], []).append((k, frozenset(w)))
    for k, people in marked.items():
        for p in people:
            w = M.fold(p).split()
            if len(w) >= 2:
                by_first.setdefault(w[0], []).append((k, frozenset(w)))
    out, per = [], {}
    for rec in issues():
        for leaf, nwords, text in rec["pages"]:
            folded = M.fold(text)
            words = set(folded.split())
            for first in words & by_first.keys():
                for k, need in by_first[first]:
                    if not need <= words:   # every word of the name must be on the page before the policy reads it
                        continue
                    year = rec["years"][0]
                    st = status.get((rec["magazine"], year))
                    if any(status.get((rec["magazine"], y)) not in AP.MAGAZINE_STATUS for y in rec["years"]):
                        continue
                    first_date, last_date = run.get(k, (None, None))
                    tie = AP.magazine_page_served(st, nwords, text, year, names.get(k), marked.get(k, ()),
                                                  first_date, last_date, folded, rec["magazine"])
                    if tie and (k, rec["id"], leaf) not in per:
                        per[(k, rec["id"], leaf)] = 1
                        out.append((k, rec["id"], leaf, rec["magazine"], rec["title"], year, tie,
                                    names.get(k) if tie == "name" else "; ".join(marked.get(k, ())), nwords, st,
                                    f"https://archive.org/details/{rec['id']}/page/n{leaf}", page_url(rec["id"], leaf)))
    kept, count = [], {}
    for r in sorted(out, key=lambda r: (r[0], r[6] != "name", r[8], r[5], r[1], r[2])):
        count[r[0]] = count.get(r[0], 0) + 1
        if count[r[0]] <= PER_SERIES:
            kept.append(r)
    return kept


def write(con):
    con.executescript(SCHEMA)
    got = rows(con) if os.path.isdir(DIR) else []
    con.executemany("INSERT OR IGNORE INTO magazine_pages VALUES (?,?,?,?,?,?,?,?,?,?,?,?)", got)
    con.commit()
    rep = {"pages": len(got), "series": len({r[0] for r in got}),
           "by_magazine": {m: sum(1 for r in got if r[3] == m) for m in sorted({r[3] for r in got})}}
    print(json.dumps({"magazinePages": rep}))
    return rep


if __name__ == "__main__":
    write(sqlite3.connect(os.path.join(OUT, "radio-catalog.sqlite")))
