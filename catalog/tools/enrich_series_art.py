"""The evidence a series' picture is chosen from (contract section 3.3a): show images, marked stars,
and how many Wikipedias cover each person.

    python3 tools/harvest_series_art.py     # first: fills .cache/series_art/
    python3 tools/enrich_series_art.py      # POST-BUILD, after enrich_external and enrich_people_art

Called by enrich_people_art.py at its end, so the publish runs it with no new step. It drops and
rebuilds only its own tables and reads the caches only (no network):

  series_art            one row per (series, candidate show image): the series' Wikidata item,
                        how the series was matched to it (art_policy.series_identity), where the
                        file came from, its license class read again from its Commons page, size,
                        face box, and whether art_policy.show_served and names_the_show pass it
  series_marks          the people the program's own OTRRpedia record marks as its star (title
                        role, star, host: art_policy.marks_star), with the character as written
  wikipedia_sitelinks   {qid: Wikipedias with an article}, for people and series
Nothing is served from here unless build_projection.py passes it through art_policy again.
"""
import gzip
import json
import os
import re
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


def word_index(trackd):
    """{word: {file name}} over the words of each Track D file's own title and categories, so the program
    names a file can carry are found without comparing every name to every file."""
    idx = {}
    for t, v in trackd.items():
        fn = t.split(":", 1)[-1]
        for w in set(AP._words(re.sub(r"\.[A-Za-z0-9]{2,5}$", "", fn) + " " + " ".join(v.get("categories") or []))):
            idx.setdefault(w, set()).add(fn)
    return idx


def name_candidates(name, idx, search_hits=()):
    """The files that may carry this program's name (H4): its Commons search hits, and the Track D files
    whose title or categories hold every word of it. Whether they do, as whole words in order, and the rest of
    rule 6, is `art_policy.name_hit_served`."""
    need = AP._title_words(name)
    out = list(search_hits)
    if need and sum(len(w) for w in need) >= AP.TITLE_MIN:
        sets = [idx.get(w, set()) for w in need]
        out += sorted(set.intersection(*sets)) if all(sets) else []
    return list(dict.fromkeys(out))


def series_art_rows(con, items, depicts, files, trackd, marks=(), lead=None, search=None, v2files=None):
    """`lead`: {enwiki title: {free, any}} (H3); `search`: {series key: [file]} (H4); `v2files`: the files
    cache of harvest_art_v2.py, read beside `files`."""
    import enrich_people_art as P
    lead, search, v2files = lead or {}, search or {}, v2files or {}
    deaths = {}
    if "people_wikidata" in {r[0] for r in con.execute("SELECT name FROM sqlite_master")}:
        deaths = AP.earliest_death((k, d) for k, pid, _c in marks for (d,) in con.execute(
            "SELECT death FROM people_wikidata WHERE person_id = ? AND death IS NOT NULL", (pid,)))
    nets = {k: json.loads(n) if n else [] for k, n in con.execute("SELECT key, networks FROM series")}
    names = dict(con.execute("SELECT key, name FROM series"))
    people = AP.show_people(con)   # series_marks is rebuilt after this: this run's marks are added below
    pname = dict(con.execute("SELECT id, name FROM people"))
    for k, pid, _c in marks:
        if pname.get(pid):
            people.setdefault(k, []).append(pname[pid])
    run = AP.run_dates(con)
    import enrich_external as EX
    wd = EX.load_items()
    rows = []
    widx = word_index(trackd)

    def facts(f):
        fv = dict(files.get(f) or files.get(f.replace(" ", "_")) or v2files.get(f) or {})
        t = trackd.get("File:" + f) or trackd.get("File:" + f.replace(" ", "_")) or {}
        for k in ("width", "height"):   # Track D read the size of the files it crawled
            if not fv.get(k) and t.get(k):
                fv[k] = t[k]
        page = _page(f)
        if page is not None:   # classed again from the page, so a rule change needs no re-harvest
            fv["class"], fv["template"], _ = P.license_class(page)
            fv.update(P.file_facts(page))
        if not fv.get("categories") and t.get("categories"):
            fv["categories"] = [c.split(":", 1)[-1] for c in t["categories"]]
        return fv

    def one(key, qid, f, src, identity, cat):
        fv = facts(f)
        cats = fv.get("categories") or []
        cls = fv.get("class", "unread")
        first, last = run.get(key, (None, None))
        tie = identity
        if src == AP.NAME_SOURCE:
            tie = AP.NAME_IDENTITY if identity != "television" and AP.name_hit_served(
                f, cats, fv.get("date_field"), names.get(key), first, last) else "title"
        served = AP.show_served(tie, src, cls, fv.get("author"), fv.get("width"), fv.get("height"), f, cats,
                                fv.get("date_field"), last, first, bool(fv.get("own_work")), deaths.get(key)) and \
            AP.names_the_show(f, cats, names.get(key), people.get(key, ()), cat, nets.get(key))
        return (key, qid, f, src, tie, cls, fv.get("template"), fv.get("author"),
                fv.get("width"), fv.get("height"), AP.face_text(fv.get("face")), json.dumps(cats), fv.get("date_field"),
                int(served), AP.evidence_url(f), int(bool(fv.get("own_work"))))

    wdkeys = set()
    for key, qid, ev, bc, cat, enwiki in con.execute(
            "SELECT series_key, qid, match_evidence, broadcaster, commons_category, enwiki FROM series_wikidata "
            "WHERE in_db = 1 ORDER BY series_key"):
        wdkeys.add(key)
        identity = AP.series_identity(json.loads(ev or "{}"), nets.get(key),
                                      [b.get("qid") for b in json.loads(bc or "[]")],
                                      (wd.get(qid) or {}).get("description"))
        cands = candidates(qid, cat, items, depicts, trackd)
        free = (lead.get(enwiki) or {}).get("free") if enwiki else None
        if free:   # H3: only a lead image Wikipedia calls free, whose file page is on Commons
            status = (facts(free).get("page_status") or ("ok" if _page(free) is not None else None))
            if AP.lead_image_served(free, status) and free.replace("_", " ") not in {c[0] for c in cands}:
                cands.append((free.replace("_", " "), "commons:enwiki"))
        seen = {c[0] for c in cands}
        for f in name_candidates(names.get(key) or "", widx, search.get(key, ())):
            if f.replace("_", " ") not in seen:
                cands.append((f.replace("_", " "), AP.NAME_SOURCE))
        for f, src in cands:
            rows.append(one(key, qid, f, src, identity, cat))
    for key in sorted(set(names) - wdkeys):   # H4 needs no Wikidata item: the file's own name and date are its tie
        for f in name_candidates(names.get(key) or "", widx, search.get(key, ())):
            rows.append(one(key, "", f.replace("_", " "), AP.NAME_SOURCE, "title", None))
    return rows


def _page(f):
    import enrich_people_art as P
    import hashlib
    title = "File:" + f
    key = hashlib.sha1(("commons.wikimedia.org|" + title).encode()).hexdigest() + ".json.gz"
    for d in (os.path.join(DIR, "commons_raw"), os.path.join(CACHE, "art_v2", "commons_raw"),
              os.path.join(CACHE, "commons", "raw")):
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
    v2 = os.path.join(CACHE, "art_v2")
    lead, search, v2files = (_rj(os.path.join(v2, n), {}) for n in ("lead.json.gz", "search.json.gz", "files.json.gz"))
    con.executescript(SCHEMA)
    tables = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
    marks = mark_rows(con) if {"series", "people"} <= tables else []   # a fixture without them marks none
    art = series_art_rows(con, items, depicts, files, trackd, marks, lead, search, v2files) if {"series_wikidata", "series"} <= tables else []
    con.executemany("INSERT OR IGNORE INTO series_art VALUES (" + ",".join("?" * 16) + ")", art)
    con.executemany("INSERT INTO series_marks VALUES (?,?,?)", marks)
    con.executemany("INSERT INTO wikipedia_sitelinks VALUES (?,?)", sorted(sitelinks.items()))
    con.commit()
    rep = {"series_art_rows": len(art), "series_art_served": sum(r[13] for r in art),
           "series_with_served_show_image": len({r[0] for r in art if r[13]}),
           "series_served_by_source": {src: len({r[0] for r in art if r[13] and r[3] == src})
                                       for src in sorted({r[3] for r in art})},
           "series_marks": len(marks), "sitelinks": len(sitelinks),
           "absent": [n for n, v in (("series_art", items), ("sitelinks", sitelinks)) if not v],
           "v2": {"lead": len(lead), "search": len(search), "files": len(v2files)}}
    print(json.dumps({"seriesArt": rep}))
    return rep


if __name__ == "__main__":
    write(sqlite3.connect(DB))
