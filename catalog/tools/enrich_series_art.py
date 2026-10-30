"""The evidence a series' picture is chosen from (contract section 3.3a): show images, marked stars,
and how many Wikipedias cover each person.

    python3 tools/harvest_series_art.py     # first: fills .cache/series_art/
    python3 tools/enrich_series_art.py      # POST-BUILD, after enrich_external and enrich_people_art

Called by enrich_people_art.py at its end, so the publish runs it with no new step. It drops and
rebuilds only its own tables and reads the caches only (no network):

  series_art            one row per (series, candidate show image): the series' Wikidata item,
                        how the series was matched to it (art_policy.series_identity), where the
                        file came from, its license class read again from its Commons page, size,
                        face box, and whether art_policy.show_served passes it
  series_marks          the people the program's own OTRRpedia record marks as its star (title
                        role, star, host: art_policy.marks_star), with the character as written
  wikipedia_sitelinks   {qid: Wikipedias with an article}, for people and series
Nothing is served from here unless build_projection.py passes it through art_policy again.
"""
import gzip
import json
import os
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ia_lib import CACHE, OUT  # noqa: E402
import art_policy as AP  # noqa: E402

DIR = os.path.join(CACHE, "series_art")
DB = os.path.join(OUT, "radio-catalog.sqlite")
if "--db" in sys.argv:
    DB = sys.argv[sys.argv.index("--db") + 1]

SCHEMA = """
DROP TABLE IF EXISTS series_art;
DROP TABLE IF EXISTS series_marks;
DROP TABLE IF EXISTS wikipedia_sitelinks;
CREATE TABLE series_art (
  series_key TEXT, qid TEXT, file TEXT, source TEXT, identity TEXT,
  license_class TEXT, template TEXT, author TEXT, width INTEGER, height INTEGER, face TEXT,
  categories TEXT, date_field TEXT, served INTEGER, evidence_url TEXT, own_work INTEGER,
  PRIMARY KEY (series_key, file)
);
CREATE TABLE series_marks (series_key TEXT, person_id TEXT, character TEXT, PRIMARY KEY (series_key, person_id));
CREATE TABLE wikipedia_sitelinks (qid TEXT PRIMARY KEY, n INTEGER NOT NULL);
"""


def _rj(path, default):
    if not os.path.exists(path):
        return default
    with gzip.open(path, "rt", encoding="utf-8") as f:
        return json.load(f)


def candidates(qid, cat, items, depicts, trackd):
    """(file, source) for one item, each file once, at its best source."""
    out = []
    for prop in ("P18", "P154", "P3383", "P2716", "P6802"):
        out += [(f, "wikidata:" + prop) for f in (items.get(qid) or {}).get(prop, [])]
    out += [(f, "commons:P180") for f in depicts.get(qid, [])]
    if cat:
        c = "Category:" + cat
        out += [(t.split(":", 1)[1], "commons:category") for t, v in sorted(trackd.items())
                if c in (v.get("categories") or [])]
    seen, rows = set(), []
    for f, src in out:
        f = f.replace("_", " ")
        if f not in seen:
            seen.add(f)
            rows.append((f, src))
    return rows


def series_art_rows(con, items, depicts, files, trackd, marks=()):
    import enrich_people_art as P
    deaths = {}
    if "people_wikidata" in {r[0] for r in con.execute("SELECT name FROM sqlite_master")}:
        deaths = AP.earliest_death((k, d) for k, pid, _c in marks for (d,) in con.execute(
            "SELECT death FROM people_wikidata WHERE person_id = ? AND death IS NOT NULL", (pid,)))
    nets = {k: json.loads(n) if n else [] for k, n in con.execute("SELECT key, networks FROM series")}
    run = AP.run_dates(con)
    wd = _rj(os.path.join(CACHE, "wikidata", "items.json.gz"), {})
    rows = []
    for key, qid, ev, bc, cat in con.execute(
            "SELECT series_key, qid, match_evidence, broadcaster, commons_category FROM series_wikidata "
            "WHERE in_db = 1 ORDER BY series_key"):
        identity = AP.series_identity(json.loads(ev or "{}"), nets.get(key),
                                      [b.get("label") for b in json.loads(bc or "[]")],
                                      (wd.get(qid) or {}).get("description"))
        for f, src in candidates(qid, cat, items, depicts, trackd):
            fv = dict(files.get(f) or files.get(f.replace(" ", "_")) or {})
            page = _page(f)
            if page is not None:   # classed again from the page, so a rule change needs no re-harvest
                fv["class"], fv["template"], _ = P.license_class(page)
                fv.update(P.file_facts(page))
            cats = fv.get("categories") or []
            cls = fv.get("class", "unread")
            served = AP.show_served(identity, src, cls, fv.get("author"), fv.get("width"), fv.get("height"), f, cats,
                                    fv.get("date_field"), *reversed(run.get(key, (None, None))),
                                    bool(fv.get("own_work")), deaths.get(key))
            rows.append((key, qid, f, src, identity, cls, fv.get("template"), fv.get("author"),
                         fv.get("width"), fv.get("height"), AP.face_text(fv.get("face")), json.dumps(cats), fv.get("date_field"),
                         int(served), AP.evidence_url(f), int(bool(fv.get("own_work")))))
    return rows


def _page(f):
    import enrich_people_art as P
    import hashlib
    title = "File:" + f
    key = hashlib.sha1(("commons.wikimedia.org|" + title).encode()).hexdigest() + ".json.gz"
    for d in (os.path.join(DIR, "commons_raw"), os.path.join(CACHE, "commons", "raw")):
        p = os.path.join(d, key)
        if os.path.exists(p):
            with gzip.open(p, "rt", encoding="utf-8") as fh:
                return json.load(fh).get("text")
    return P.page_text(f)


def mark_rows(con):
    """series_marks from each series' OTRRpedia program records (.cache/otrrpedia/programs)."""
    people = {pid for (pid,) in con.execute("SELECT id FROM people")}
    rows = {}
    for key, name, progs in con.execute("SELECT key, name, otrr_programs FROM series WHERE otrr_programs IS NOT NULL"):
        for idp in json.loads(progs or "[]"):
            rec = _rj(os.path.join(CACHE, "otrrpedia", "programs", f"{idp}.json.gz"), {})
            for p in rec.get("people") or []:
                pid = "otrr:" + str(p.get("idperson"))
                if p.get("f") == "Noted Role" and pid in people and AP.marks_star(p.get("character"), name):
                    rows.setdefault((key, pid), p.get("character"))
    return [(k, pid, ch) for (k, pid), ch in sorted(rows.items())]


def write(con):
    items = _rj(os.path.join(DIR, "items.json.gz"), {})
    depicts = _rj(os.path.join(DIR, "depicts.json.gz"), {})
    files = _rj(os.path.join(DIR, "files.json.gz"), {})
    sitelinks = _rj(os.path.join(DIR, "sitelinks.json.gz"), {})
    trackd = _rj(os.path.join(CACHE, "commons", "files.json.gz"), {})
    con.executescript(SCHEMA)
    tables = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
    marks = mark_rows(con) if {"series", "people"} <= tables else []   # a fixture without them marks none
    art = series_art_rows(con, items, depicts, files, trackd, marks) if {"series_wikidata", "series"} <= tables else []
    con.executemany("INSERT OR IGNORE INTO series_art VALUES (" + ",".join("?" * 16) + ")", art)
    con.executemany("INSERT INTO series_marks VALUES (?,?,?)", marks)
    con.executemany("INSERT INTO wikipedia_sitelinks VALUES (?,?)", sorted(sitelinks.items()))
    con.commit()
    rep = {"series_art_rows": len(art), "series_art_served": sum(r[13] for r in art),
           "series_with_served_show_image": len({r[0] for r in art if r[13]}),
           "series_marks": len(marks), "sitelinks": len(sitelinks),
           "absent": [n for n, v in (("series_art", items), ("sitelinks", sitelinks)) if not v]}
    print(json.dumps({"seriesArt": rep}))
    return rep


if __name__ == "__main__":
    write(sqlite3.connect(DB))
