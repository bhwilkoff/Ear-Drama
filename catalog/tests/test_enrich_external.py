"""External witnesses: Haendiges log lines, Wikipedia episode tables, Wikidata
series matching, witness joins and Commons licence classes.

    python3 tests/test_enrich_external.py

Every case is checked against a synthetic database built here, never the live
one, so it runs without the caches. Broken controls, 2026-10-19, each run
against a mutated copy of the tool (the count is what that copy scored):

    Wikidata year check removed (disagree accepted)    34/35
    a non-radio item accepted                          33/35
    an item typed TV vouched for by its category       33/35
    tie broken by order instead of refused             34/35
    Wikidata-duplicate rule removed                    34/35
    year context ignored (X Minus One "April 22")      33/35
    an invented year when no heading gives one         34/35
    a notes column readable as a title                 34/35
    'Title Unknown' kept as a title                    34/35
    unterminated title not joined                      34/35
    no fuzzy title agreement (Truck/Trunk)             34/35
    every licence marked usable                        34/35
    a PD redirect name not recognized                  34/35
    same-title date check removed                      34/35

Two controls first PASSED (27/27, an earlier count) against their mutation and were rewritten:
the non-radio item lost on score to a radio one rather than being refused (a
TV-only Gunsmoke item is now the only candidate), and the licence test had no
non-PD file to mark usable (a CC file is now written beside the PD one).
"""
import os
import sqlite3
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import enrich_external as E  # noqa: E402
import harvest_ext_haendiges as H  # noqa: E402
import harvest_ext_wikipedia as W  # noqa: E402
import harvest_ext_commons as C  # noqa: E402

HLOG = b'''<PRE>
 </FONT><FONT SIZE=5><B>Series: "SUSPENSE"</B></FONT>
======================================================================================================
84847B   "THE BURNING COURT"               1  06-17-42  :30:20  Charles Ruggles, Julie Hayden
*na*     "WITNESS ON THE WESTBOUND         6  07-22-42  :30:00
         LIMITED"
*na*     ?? Title Unknown ??             138  03-26-42  :30:00
*na*     "BAD DATE"                        9  13-45-42  :30:00
                                                                Show of 8-26-42 pre-empted
</PRE>'''

XMO = '''==1955==
{| class="wikitable"
|-
! Title
! Air Date
! Author
|-
| 1. "[[The Martian Chronicles#x|And The Moon Be Still As Bright]]"
| April 22
| [[Ray Bradbury]]
|-
| 2. "No Contact"
| April 24
| George Lefferts
|}
'''
NOYEAR = XMO.replace("==1955==", "==First season==")
ESCAPE = '''{| class="wikitable"
! No. !! Title !! Author !! Star !! Air date
|-
! 1
| "[[The Man Who Would Be King]]"
| Kipling
| Jack Webb
|07-07-47
|}
'''
EPLIST = '''{{Episode list
 |EpisodeNumber=3
 |Title=The Parade
 |OriginalAirDate={{Start date|1955|5|1}}
 |ShortSummary=Prose that must not be kept.
}}'''


def mkdb():
    db = sqlite3.connect(":memory:")
    db.executescript("""
      CREATE TABLE series (key TEXT PRIMARY KEY, name TEXT, genre TEXT, first_date TEXT, last_date TEXT,
        episodes INTEGER, is_librivox INTEGER, foreign_evidence TEXT, claim TEXT, in_spine INTEGER);
      CREATE TABLE episodes (id TEXT PRIMARY KEY, series_key TEXT, air_date TEXT, title TEXT);""")
    db.executemany("INSERT INTO series (key,name,first_date,last_date,episodes,in_spine) VALUES (?,?,?,?,?,?)", [
        ("suspense", "Suspense", "1942-06-17", "1962-09-30", 900, 1),
        ("escape", "Escape", "1947-07-07", "1954-09-25", 200, 1),
        ("fibbermcgeeandmolly", "Fibber McGee and Molly", "1935-04-16", "1959-01-01", 700, 1),
        ("theshadow", "The Shadow", "1937-09-26", "1954-12-26", 200, 1),
        ("dragnet", "Dragnet", "1949-06-03", "1957-02-26", 300, 1),
        ("gunsmoke", "Gunsmoke", "1952-04-26", "1961-06-18", 400, 1),
    ])
    db.executemany("INSERT INTO episodes VALUES (?,?,?,?)", [
        ("suspense|1942-06-17", "suspense", "1942-06-17", "The Burning Court"),
        ("suspense|1942-07-22", "suspense", "1942-07-22", "Philomel Cottage"),
        ("suspense|1942-07-30", "suspense", "1942-07-30", "Wet Saturday"),
    ])
    return db


class FakeIdx(E.SeriesIndex):
    def __init__(self, db):  # no caches: names and years from the db only
        from collections import defaultdict
        self.name, self.years, self.known, self.in_db = {}, {}, set(), set()
        self.by, self.otrr, self.radioechoes = defaultdict(dict), set(), set()
        for key, name, first, last in db.execute("SELECT key, name, first_date, last_date FROM series"):
            self.name[key] = name
            self.years[key] = (E._year(first), E._year(last))
            self.known.add(key)
            self.in_db.add(key)
            self._add(name, key, "direct")
            self._add(key, key, "direct")


def item(q, label, rc=("Q3511312",), start=None, end=None, country=("Q30",), aliases=(), enwiki=None,
         typed=True):
    p = {"country": list(country), "instance_of": list(rc) or (["Q5398426"] if typed else [])}
    if start:
        p["start"] = [start]
    if end:
        p["end"] = [end]
    return {"qid": q, "label": label, "aliases": list(aliases), "enwiki": enwiki, "props": p,
            "external_ids": {}, "radio_class": list(rc)}


def main():
    checks = []

    def ok(name, cond):
        checks.append(name)
        if not cond:
            print(f"FAIL {name}")
            return 1
        return 0

    f = 0
    # --- Haendiges
    rows = H.parse_log(HLOG, "Suspense", "logs1003.htm")
    f += ok("haendiges: three dated lines, a bad date dropped", len(rows) == 3)
    f += ok("haendiges: quoted title + ep + date", rows[0]["title"] == "THE BURNING COURT"
            and rows[0]["ep"] == "1" and rows[0]["date"] == "1942-06-17")
    f += ok("haendiges: wrapped title joined", rows[1]["title"] == "WITNESS ON THE WESTBOUND LIMITED"
            and rows[1]["ep"] == "6")
    f += ok("haendiges: 'Title Unknown' witnesses the date, not a title",
            rows[2]["title"] is None and rows[2]["date"] == "1942-03-26")
    f += ok("haendiges: series from the header", rows[0]["series"] == "SUSPENSE")
    f += ok("haendiges: a date inside the comments column is not a line",
            all(r["date"] != "1942-08-26" for r in rows))
    # --- Wikipedia
    x = W.table_rows(XMO)
    f += ok("wikipedia: heading year completes 'April 22'", [r["date"] for r in x] == ["1955-04-22", "1955-04-24"])
    f += ok("wikipedia: link text and leading number stripped", x and x[0]["title"] == "And The Moon Be Still As Bright")
    f += ok("wikipedia (control): no year is invented", W.table_rows(NOYEAR) == [])
    e = W.table_rows(ESCAPE)
    f += ok("wikipedia: mm-dd-yy cell and row-header number", e and e[0]["date"] == "1947-07-07"
            and e[0]["title"] == "The Man Who Would Be King")
    notes = '{| class="wikitable"\n! Date !! Program notes\n|-\n| August 25, 1946 || Fifth and last program on the case.\n|-\n| September 1, 1946 || x\n|}\n'
    f += ok("wikipedia (control): a notes column is never read as a title", W.table_rows(notes) == [])
    ep = W.episode_list_rows(EPLIST)
    f += ok("wikipedia: {{Episode list}} with {{Start date}}", ep == [
        {"date": "1955-05-01", "title": "The Parade", "num": "3", "shape": "episode_list"}])
    f += ok("wikipedia: summary prose not kept", "ShortSummary" not in str(ep) and "Prose" not in str(ep))
    f += ok("wikipedia: 'List of X episodes' names X", W.page_series("List of X Minus One episodes") == "X Minus One")
    # --- Wikidata matching
    db = mkdb()
    idx = FakeIdx(db)
    items = {
        "Q1548940": item("Q1548940", "Suspense", start="1942-06-17", end="1962-09-30"),
        "Q999": item("Q999", "Suspense", rc=(), start="1949-01-01", end="1964-01-01"),        # TV: not radio
        "Q100": item("Q100", "Escape", start="1985-01-01", end="1990-01-01"),               # wrong era
        "Q200": item("Q200", "Fibber McGee & Molly", start="1935-04-16"),                    # & vs and
        "Q301": item("Q301", "The Shadow", start="1937-01-01", end="1954-01-01"),
        "Q302": item("Q302", "The Shadow", start="1938-01-01", end="1953-01-01"),            # tie, other years
        "Q801": item("Q801", "Gunsmoke", start="1952-04-26", end="1961-06-18"),              # Wikidata duplicates:
        "Q802": item("Q802", "Gunsmoke", rc=("Q3956369",), start="1952-04-26", end="1961-06-18"),  # same dates
        "Q400": item("Q400", "Dragnet", rc=("Q2635894",), country=()),                       # a single play, no years
        "Q500": item("Q500", "Gunsmoke", rc=(), start="1955-09-10", end="1975-03-31"),       # the TV series only
    }
    items["Q600"] = item("Q600", "Escape", rc=(), typed=False, start="1947-07-07")      # untyped, in a radio category
    items["Q700"] = item("Q700", "Dragnet", rc=(), start="1949-06-03")                  # typed TV, in a radio category
    enw = {"Escape (radio program)": {"qid": "Q600", "cats": ["Category:American radio dramas"]},
           "Dragnet (franchise)": {"qid": "Q700", "cats": ["Category:American radio dramas"]}}
    m, rej, amb = E.match_wikidata(idx, items, enw)
    f += ok("wikidata: title + radio class + years", m.get("suspense", {}).get("qid") == "Q1548940")
    f += ok("wikidata (control): non-radio item never matches", all(v["qid"] not in ("Q999", "Q500")
                                                                     for v in m.values()))
    f += ok("wikidata (control): years that do not overlap refuse the match",
            m.get("escape", {}).get("qid") != "Q100" and rej["years_disagree"] >= 1)
    f += ok("wikidata: an untyped item in a radio-program category matches", m.get("escape", {}).get("qid") == "Q600")
    f += ok("wikidata (control): an item typed as TV never matches on its category",
            m.get("dragnet", {}).get("qid") != "Q700")
    f += ok("wikidata: & and 'and' are one name", m.get("fibbermcgeeandmolly", {}).get("qid") == "Q200")
    f += ok("wikidata (control): a tie is ambiguous, not a match", "theshadow" not in m
            and any(a["key"] == "theshadow" for a in amb))
    f += ok("wikidata (control): a radio-drama play with no years is refused", "dragnet" not in m)
    f += ok("wikidata: two radio items with the same dates are duplicates, one is taken and the other named",
            m.get("gunsmoke", {}).get("qid") == "Q801" and m["gunsmoke"].get("wikidata_duplicates") == ["Q802"])
    f += ok("titles: one letter apart agree", E.titles_agree("The Thirteenth Truck", "The Thirteenth Trunk") == 1)
    f += ok("titles (control): different stories disagree",
            E.titles_agree("MessageFromTheHills", "Revenge on the Shadow") == 0)
    # --- witnesses
    db.executescript(E.DDL)
    rows = [("suspense", "1942-06-17", "THE BURNING COURT", "1", "haendiges", "u1"),
            ("suspense", "1942-07-22", "Witness on the Westbound Limited", "6", "haendiges", "u1"),
            ("suspense", "1942-07-29", "Wet Saturday", None, "wikipedia", "u2"),
            ("suspense", "1942-08-05", "Finishing School", None, "wikipedia", "u2")]
    n, nd = E.write_witnesses(db, rows)
    got = dict(((r[0], r[1]), r[2]) for r in db.execute(
        "SELECT episode_id, source, title_agrees FROM episode_witnesses WHERE episode_id IS NOT NULL"))
    f += ok("witness: same date, same title agrees", got.get(("suspense|1942-06-17", "haendiges")) == 1)
    f += ok("witness: same date, other title is a title disagreement",
            got.get(("suspense|1942-07-22", "haendiges")) == 0 and db.execute(
                "SELECT COUNT(*) FROM external_disagreements WHERE kind='title'").fetchone()[0] == 1)
    f += ok("witness: our title on a date a day off is a date disagreement", db.execute(
        "SELECT our_date, witness_date FROM external_disagreements WHERE kind='date'").fetchall()
        == [("1942-07-30", "1942-07-29")])
    f += ok("witness: a date we lack is kept with no episode", db.execute(
        "SELECT COUNT(*) FROM episode_witnesses WHERE episode_id IS NULL").fetchone()[0] == 2)
    # --- art
    f += ok("art: PD-US-not renewed is a usable class",
            E.license_template({"pd_class": "PD-US-not renewed"}) == "PD-US-not renewed")
    f += ok("art (control): a CC licence is not a PD class", E.license_template(
        {"pd_class": None, "license_short": "cc-by-sa-4.0"}) not in E.PD_CLASSES)
    files = {"File:Suspense cast 1950.jpg": {
        "pageid": 1, "url": "https://upload/x.jpg", "page": "https://commons/File:x", "width": 800,
        "height": 600, "categories": ["Category:Suspense (radio series)"],
        "pd_class": "PD-US-not renewed", "found_via": []},
        "File:Modern Suspense fan art.png": {
        "pageid": 2, "url": "https://upload/y.png", "page": "https://commons/File:y", "width": 800,
        "height": 600, "categories": ["Category:Suspense (radio series)"], "pd_class": None,
        "license_short": "CC BY-SA 4.0", "found_via": []}}
    E.write_art(db, idx, m, items, files, {})
    f += ok("art: a '(radio series)' category ties the file to the series", db.execute(
        "SELECT series_key, usable FROM art WHERE file LIKE '%1950%'").fetchall() == [("suspense", 1)])
    f += ok("art (control): a CC file is recorded but not usable", db.execute(
        "SELECT license_template, usable FROM art WHERE file LIKE '%fan art%'").fetchall()
        == [("other:CC BY-SA 4.0", 0)])
    f += ok("commons: a PD template on the page, through a redirect name", C.template_class(
        "{{Information|source=x}}\n{{PD-Pre1978}}") == ("PD-US-no notice", "PD-Pre1978"))
    f += ok("commons: a wrapper's first parameter names the licence", C.template_class(
        "== {{int:license-header}} ==\n{{PD-Art|PD-US-not renewed}}") == ("PD-US-not renewed", "PD-Art|PD-US-not renewed"))
    f += ok("commons (control): a bare PD-Art (a museum-scan rule, no US class) is not PD-US",
            C.template_class("{{PD-Art}}") == (None, None))
    f += ok("commons (control): a CC page has no PD class",
            C.template_class("{{Information}}\n{{cc-by-sa-4.0}}") == (None, None))
    total = len(checks)
    print(f"{total - f}/{total} passed")
    sys.exit(1 if f else 0)


if __name__ == "__main__":
    main()
