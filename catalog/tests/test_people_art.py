"""People -> Wikidata matching and portrait licence classes (tools/enrich_people_art.py).

    python3 tests/test_people_art.py

Synthetic people, candidates and Commons pages only; never the live caches or
the live database, so it runs anywhere. Broken controls, 2026-10-21, each run
against a deliberately loosened copy of the tool (the count is what that copy
scored; every one fails at least one case here):

    a date conflict ignored when the other date agrees      65/66
    a year one apart counted as agreement                   65/66
    a month-day match alone counted as agreement            65/66
    undated: the first candidate taken, not exactly one     65/66
    undated: occupation not required                        65/66
    undated: era not checked                                64/66
    every licence class marked usable                       65/66
    a deletion request ignored                              64/66
    PD-old-70 (no US template) treated as PD in the US      64/66
    a middle initial dropped when the FIRST token is one    65/66

The first control PASSED (56/56) against its mutation until a case was added
where one date agrees and the other conflicts (a namesake born the same year).
"""
import json
import os
import shutil
import sqlite3
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import enrich_people_art as P  # noqa: E402

PASS = []
FAIL = []


def check(name, cond):
    (PASS if cond else FAIL).append(name)
    if not cond:
        print("FAIL", name)


def ent(label, by=None, dy=None, b=None, d=None, occ=("actor",), images=()):
    return {"label": label, "description": None, "enwiki": None,
            "birth": b or (str(by) if by else None), "death": d or (str(dy) if dy else None),
            "birth_years": [by] if by else [], "death_years": [dy] if dy else [],
            "occupations": list(occ), "images": list(images), "imdb": [], "commons_category": []}


# ------------------------------------------------------------ name variants
v = P.name_variants("Kenneth 'Ken' Carpenter")
check("nickname: without it", "Kenneth Carpenter" in v)
check("nickname: nickname + surname", "Ken Carpenter" in v)
check("parenthesized nickname", "Dick Aurandt" in P.name_variants("Richard (Dick) Aurandt"))
check("middle initial dropped", "Chester Lauck" in P.name_variants("Chester A. Lauck"))
check("leading initial keeps the middle one", P.name_variants("E. G. Marshall") == ["E. G. Marshall"])
check("Jr forms", {"Ivan Allen", "Ivan Allen Jr."} <= set(P.name_variants("Ivan Allen, Jr.")))
check("particle case", "Harry von Zell" in P.name_variants("Harry Von Zell"))
check("a group is never a person", P.name_variants("Phil Harris and His Orchestra") == []
      and P.name_variants("Honey Dreamers, The") == [] and P.name_variants("The King's Men") == [])
check("single word refused", P.name_variants("Rochester") == [])
check("aliases and birth name searched",
      {"Lenore Jewell", "Lee Allman"} <= set(P.name_variants("Lee Allman", ["Lee Allman"], "Lenore Jewell")))

# ------------------------------------------------------------ dated matching
welles = {"birth": "1915-05-06", "death": "1985-10-10", "first_year": 1936}
q, basis, _ = P.decide(welles, {"Q24829": ent("Orson Welles", 1915, 1985, "1915-05-06", "1985-10-10"),
                                "Q999": ent("Orson Welles", 1950, None, occ=("politician",))})
check("dated: the agreeing candidate wins", q == "Q24829" and basis == "name+birth_day+death_day")
q, basis, _ = P.decide(welles, {"Q1": ent("Orson Welles", 1950, 2001)})
check("dated: a conflicting candidate is refused", q is None and basis == "dates_disagree")
q, basis, _ = P.decide(welles, {"Q1": ent("Orson Welles", 1915, 2001)})
check("dated: one year agreeing and the other conflicting is refused", q is None)
q, basis, _ = P.decide(welles, {"Q1": ent("Orson Welles")})
check("dated: a candidate with no years is refused", q is None)
kearns = {"birth": "1904-02-12", "death": "1962-02-17"}
q, basis, _ = P.decide(kearns, {"Q2410098": ent("Joseph Kearns", 1907, 1962, "1907-02-12", "1962-02-17")})
check("dated: a shaved birth year beside an exact death", q == "Q2410098" and "birth_monthday" in basis)
q, basis, _ = P.decide({"birth": "1908-06-23"}, {"Q1": ent("Mary L", 1905, None, "1905-06-23")})
check("dated: month-day alone is not agreement", q is None)
q, basis, _ = P.decide({"birth": "1908-01-01"}, {"Q1": ent("X Y", 1909)})
check("dated: one year apart alone is not agreement", q is None)
q, basis, _ = P.decide({"birth": "1908-01-01", "death": "1970-05-05"}, {"Q1": ent("X Y", 1909, 1970)})
check("dated: one year apart beside an exact year", q == "Q1")
q, basis, _ = P.decide({"death": "1984-10-16"}, {"Q1": ent("Ken C", 1900, 1984), "Q2": ent("Ken C", 1950, 1984)})
check("dated: two agreeing on one year are ambiguous", q is None and basis == "ambiguous_dated")
q, basis, _ = P.decide({"birth": "1900-08-21", "death": "1984-10-16"},
                       {"Q1": ent("Ken C", 1900, 1984), "Q2": ent("Ken C", 1900, 1990)})
check("dated: the one agreeing on both wins", q == "Q1")
q, basis, _ = P.decide({"birth": "1900-00-00", "death": "1984-00-00"}, {"Q1": ent("Ken C", 1900, 1984, "1900-08-21")})
check("dated: a zero month-day is a year, never a day", q == "Q1" and "day" not in basis)

# ------------------------------------------------------------ undated matching
lauck = {"first_year": 1931}
q, basis, _ = P.decide(lauck, {"Q5093638": ent("Chester Lauck", 1902, 1980, occ=("radio personality",))})
check("undated: one candidate, radio occupation, right era", q == "Q5093638" and basis == "name+occupation+unique")
q, basis, _ = P.decide(lauck, {"Q1": ent("A", 1902, 1980), "Q2": ent("A", 1890, 1950)})
check("undated: two candidates refused", q is None and basis == "ambiguous_undated")
q, basis, _ = P.decide(lauck, {"Q1": ent("A", 1902, 1980, occ=("Canadian football player",))})
check("undated: unrelated occupation refused", q is None and basis == "undated_occupation_unrelated")
q, basis, _ = P.decide(lauck, {"Q1": ent("A", 1950, 2010)})
check("undated: born after the credits refused", q is None and basis == "undated_era_mismatch")
q, basis, _ = P.decide(lauck, {"Q1": ent("A", 1850, 1920)})
check("undated: dead before the credits refused", q is None and basis == "undated_era_mismatch")
q, basis, _ = P.decide(lauck, {"Q1": ent("A")})
check("undated: no Wikidata year refused", q is None and basis == "undated_no_wikidata_year")
check("no candidate", P.decide(lauck, {})[1] == "no_candidate")

# ------------------------------------------------------------ licences
LC = P.license_class
check("PD-US-no notice", LC("{{Information}}\n{{PD-US-no notice}}")[0] == "pd_us")
check("PD-Pre1978 redirect", LC("{{PD-Pre1978}}")[0] == "pd_us")
check("PD-US-not renewed", LC("{{PD-US-not renewed}}")[0] == "pd_us")
check("PD-USGov-Military", LC("{{PD-USGov-Military-Army}}")[0] == "pd_us_gov")
check("PD-old-auto-expired is US-expired", LC("{{PD-old-auto-expired|deathyear=1930}}")[0] == "pd_us")
check("PD-Art wrapper reads its parameter", LC("{{PD-Art|PD-old-auto-expired}}")[0] == "pd_us")
check("PD-old-70 alone is not US evidence", LC("{{PD-old-70}}")[0] == "pd_source_only")
check("cc-zero", LC("{{cc-zero}}")[0] == "cc0")
c, t, ob = LC("{{self|cc-by-sa-4.0|GFDL}}")
check("self wrapper: CC BY-SA with its obligations", c == "cc_by_sa" and ob == "attribution, share-alike")
c, t, ob = LC("{{cc-by-2.0}}")
check("CC BY with attribution", c == "cc_by" and ob == "attribution")
check("GFDL only is not counted usable", LC("{{GFDL}}")[0] == "gfdl_only")
check("PD-self", LC("{{PD-self}}")[0] == "pd_release")
check("a deletion request voids the licence", LC("{{Delete|reason=x}}\n{{PD-US-no notice}}")[0] == "contested")
check("no permission", LC("{{No permission since|month=May}}{{cc-by-4.0}}")[0] == "contested")
check("Flickr no known restrictions", LC("{{Flickr-no known copyright restrictions}}")[0] == "no_known_restrictions")
check("self with a nested author template", LC("{{self|author={{user at project|R|wikipedia|en}}|Cc-by-sa-3.0}}")[0] == "cc_by_sa")
check("a wrapper's numbered parameter", LC("{{PD-scan|1=PD-US-no notice |country=US}}")[0] == "pd_us")
check("PD-old-auto-1978 redirects to no notice", LC("{{PD-old-auto-1978}}")[0] == "pd_us")
check("PD-Pre1964 redirects to not renewed", LC("{{PD-Pre1964}}")[0] == "pd_us")
check("another country's PD is not US evidence", LC("{{PD-Canada}}")[0] == "pd_source_only")
check("LOC no-known-restrictions is not a status", LC("{{PD-Van Vechten}}")[0] == "no_known_restrictions")
check("Gottlieb's own dedication", LC("{{PD-Gottlieb}}")[0] == "pd_release")
check("LOC Bain is not a status", LC("{{PD-Bain}}")[0] == "no_known_restrictions")
check("LA Times UCLA is CC BY", LC("{{LATimes UCLA}}")[:3:2] == ("cc_by", "attribution"))
check("unknown", LC("{{Information|description=x}}")[0] == "unknown")
check("unread page", LC(None)[0] == "unread")
check("usable set", {"pd_us", "pd_us_gov", "cc0", "pd_release", "free_use", "cc_by", "cc_by_sa"} == P.USABLE
      and not ({"gfdl_only", "pd_source_only", "contested", "unknown", "no_known_restrictions"} & P.USABLE))

ff = P.file_facts("{{Information\n|description=x\n|date=1947\n|source=[https://www.ebay.com/itm/1 eBay]\n"
                  "|author=[[User:Abc|NBC Radio]]\n}}")
check("author markup stripped", ff["author"] == "NBC Radio")
check("source link kept", ff["source_links"] == ["https://www.ebay.com/itm/1"])
check("creator template", P.file_facts("{{Information\n|author={{Creator:Maurice Seymour}}\n}}")["author"] == "Maurice Seymour")
page, thumb = P.commons_urls("Orson Welles 1937.jpg")
check("thumb is a Commons FilePath URL, not a download",
      page.endswith("File:Orson_Welles_1937.jpg") and "Special:FilePath/Orson_Welles_1937.jpg?width=" in thumb)

# ------------------------------------------------------------ the DB step
tmp = tempfile.mkdtemp()
try:
    db = os.path.join(tmp, "radio-catalog.sqlite")
    con = sqlite3.connect(db)
    con.executescript("""
      CREATE TABLE people (id TEXT PRIMARY KEY, name TEXT, names TEXT, otrr_id TEXT, goldin_name TEXT,
        birth TEXT, death TEXT, birth_name TEXT, birth_place TEXT, sources TEXT);
      CREATE TABLE episode_credits (episode_id TEXT, person_id TEXT, name TEXT, role TEXT, character TEXT,
        source TEXT, source_ref TEXT, method TEXT);
      CREATE TABLE episodes (id TEXT PRIMARY KEY, series_key TEXT, air_date TEXT);
      CREATE TABLE art (x TEXT); INSERT INTO art VALUES ('other track');
      INSERT INTO people VALUES ('otrr:1','Orson Welles','["Orson Welles"]','1',NULL,'1915-05-06','1985-10-10',NULL,NULL,'[]');
      INSERT INTO people VALUES ('otrr:2','Nobody Known','[]','2',NULL,NULL,NULL,NULL,NULL,'[]');
      INSERT INTO episodes VALUES ('mercury|1938-10-30','mercury','1938-10-30');
      INSERT INTO episodes VALUES ('mercury|1938-11-06','mercury','1938-11-06');
      INSERT INTO episode_credits VALUES ('mercury|1938-10-30','otrr:1','Orson Welles','cast',NULL,'otrr',NULL,'file');
      INSERT INTO episode_credits VALUES ('mercury|1938-11-06','otrr:1','Orson Welles','director',NULL,'otrr',NULL,'file');
      INSERT INTO episode_credits VALUES ('mercury|1938-10-30','otrr:2','Nobody Known','cast',NULL,'otrr',NULL,'file');
    """)
    con.commit()
    con.close()
    cdir = os.path.join(tmp, "cache", "people_wd")
    os.makedirs(cdir)
    import gzip
    for fn, obj in (("names.json.gz", {"Orson Welles": ["Q24829"], "Nobody Known": []}),
                    ("entities.json.gz", {"Q24829": ent("Orson Welles", 1915, 1985, "1915-05-06", "1985-10-10",
                                                        images=["Welles 1937.jpg", "Welles cc.jpg"])}),
                    ("files.json.gz", {"Welles 1937.jpg": {"class": "pd_us", "template": "PD-US-not renewed",
                                                           "author": "WPA", "source_links": []},
                                       "Welles cc.jpg": {"class": "gfdl_only", "template": "GFDL"}})):
        with gzip.open(os.path.join(cdir, fn), "wt") as f:
            json.dump(obj, f)
    P.DB, P.DIR, P.OUT, P.CACHE = db, cdir, tmp, os.path.join(tmp, "cache")
    import io
    import contextlib
    for run in (1, 2):
        with contextlib.redirect_stdout(io.StringIO()):
            P.main()
    con = sqlite3.connect(db)
    rows = con.execute("SELECT person_id, qid, basis, credited_episodes, rank FROM people_wikidata ORDER BY rank").fetchall()
    check("db: matched row", rows[0] == ("otrr:1", "Q24829", "name+birth_day+death_day", 2, 1))
    check("db: unmatched row kept with its basis", rows[1][1] is None and rows[1][2] == "no_candidate")
    art = con.execute("SELECT file, license_class, usable, evidence_url FROM people_art ORDER BY file").fetchall()
    check("db: usable PD portrait", art[0][:3] == ("Welles 1937.jpg", "pd_us", 1)
          and art[0][3].startswith("https://commons.wikimedia.org/wiki/File:"))
    check("db: GFDL-only portrait recorded, not usable", art[1][1:3] == ("gfdl_only", 0))
    check("db: rerun does not duplicate", con.execute("SELECT COUNT(*) FROM people_art").fetchone()[0] == 2)
    check("db: another track's table untouched", con.execute("SELECT x FROM art").fetchone()[0] == "other track")
    rep = json.load(open(os.path.join(tmp, "enrich_people_art_report.json")))
    check("report counts", rep["all"]["matched"] == 1 and rep["all"]["with_usable_image"] == 1
          and rep["all"]["usable_by_best_class"] == {"pd_us": 1})
    con.close()
finally:
    shutil.rmtree(tmp)

print(f"{len(PASS)}/{len(PASS) + len(FAIL)} passed")
sys.exit(1 if FAIL else 0)
