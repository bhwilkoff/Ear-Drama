"""Decision 040 (owner 2026-11-21): an image is used unless its own record marks a restriction. Fixtures for each
restriction class and for each newly allowed class, each with a negative control that must fail the way the rule says.

    python3 tests/test_image_rule_040.py

Seen to FAIL (2026-11-21): every `control` below was run against a copy of the predicate with its rule removed
(the restriction template list, the sentence pattern, the enwiki-local host, the competing-name check, the occupation
check, the design-drawing refusal, the FTP owner check, the exact-title check, the page's own notice, the issue-year
status, the run window) and went red. Nothing here pins catalog contents.
"""
import os
import sqlite3
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools"))
import art_policy as AP
import build_projection as BP
import photo_match as M

ran = failed = 0


def check(name, got, want):
    global ran, failed
    ran += 1
    if got != want:
        failed += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


# --- a restriction is what the record says against reuse ---------------------------------------
for tpl in ("Non-free poster", "Nonfree album cover", "Fair use", "Cc-by-nc-3.0", "cc-by-nd-4.0", "Copyrighted",
            "All rights reserved", "Permission required", "Restricted"):
    check(f"restricted template: {tpl}", AP.restricted_template(tpl), True)
for tpl in ("PD-US-no notice", "Cc-by-sa-4.0", "Copyrighted free use", "Information", "PD-old-70", "Cc-zero"):
    check(f"control: not a restriction: {tpl}", AP.restricted_template(tpl), False)
for sentence in ("All rights reserved.", "This is a non-free image.", "Used under fair use.", "Permission is required.",
                 "Rights restricted by the holder", "Publication may be restricted.", "Not for reuse"):
    check(f"restriction sentence: {sentence}", bool(AP.restriction_in(sentence)), True)
for sentence in ("A photograph of the cast at the microphone, 1947.", "Rights status not evaluated.",
                 "No known restrictions on publication.", ""):
    check(f"control: no restriction in: {sentence!r}", AP.restriction_in(sentence), None)
check("a file hosted on English Wikipedia is non-free",
      AP.enwiki_local("https://upload.wikimedia.org/wikipedia/en/a/ab/Poster.jpg"), True)
check("control: a Commons-hosted file is not enwiki-local",
      AP.enwiki_local("https://upload.wikimedia.org/wikipedia/commons/a/ab/Poster.jpg"), False)
check("lead image: free, on Commons, not enwiki-local", AP.lead_image_served("Poster.jpg", "ok"), True)
check("control: a lead image hosted on enwiki is refused even when flagged",
      AP.lead_image_served("Poster.jpg", "ok", "https://upload.wikimedia.org/wikipedia/en/a/ab/Poster.jpg"), False)
check("control: a lead image Wikipedia does not call free is refused", AP.lead_image_served(None, "ok"), False)

# --- the classes 040 newly serves, and the ones it does not ------------------------------------
for cls in ("pd_source_only", "no_known_restrictions", "unmarked"):
    check(f"newly served class: {cls}", cls in AP.SERVED_CLASSES, True)
    check(f"ranks after every free class: {cls}", AP.PREFER[cls] > AP.PREFER["cc_by_sa"], True)
for cls in ("restricted", "contested", "unread", "gfdl_only"):
    check(f"control: never served: {cls}", cls in AP.SERVED_CLASSES, False)

# --- V1: the undated person rule ---------------------------------------------------------------
UND = AP.UNDATED_BASIS
check("undated: a radio occupation and no competitor is served", AP.undated_served(UND, ["actor", "radio actor"], False), True)
check("undated: a stage occupation", AP.undated_served(UND, ["playwright"], False), True)
check("undated: 'record producer' is a music trade, not a radio, stage or screen one",
      AP.undated_served(UND, ["politician", "record producer", "journalist"], False), False)
check("undated: a film producer is", AP.undated_served(UND, ["film producer"], False), True)
check("control: a competing person of the name refuses it", AP.undated_served(UND, ["actor"], True), False)
check("control: an occupation outside radio, stage and screen refuses it",
      AP.undated_served(UND, ["politician", "footballer"], False), False)
check("control: no occupation refuses it", AP.undated_served(UND, [], False), False)
check("control: a dated basis is not this rule", AP.undated_served("name+birth_year", ["actor"], False), False)
check("name_competes: two people carry the name", AP.name_competes("John Smith", {AP.norm_name("John Smith"): 2}), True)
check("control: one person carries the name", AP.name_competes("John Smith", {AP.norm_name("John Smith"): 1}), False)

con = sqlite3.connect(":memory:")
con.executescript("""
CREATE TABLE people (id TEXT, name TEXT, names TEXT);
INSERT INTO people VALUES ('a1', 'John Smith', '[]');
INSERT INTO people VALUES ('a2', 'John Smith', '[]');
INSERT INTO people VALUES ('b1', 'Mary Jones', '["Mary J. Jones"]');
INSERT INTO people VALUES ('b2', 'Mary Jones Jr', '["Mary Jones"]');
INSERT INTO people VALUES ('c1', 'Orson Welles', '[]');
INSERT INTO people VALUES ('c2', 'Orson Welles', '[]');
""")
check("competing: two people of one name, and an alias that is another's name",
      BP.undated_people(con)["competing"], {"a1", "a2", "b1", "b2", "c1", "c2"})
check("control: two ids merged as one person do not compete",
      BP.undated_people(con, {"a2": "a1", "c2": "c1"})["competing"], {"b1", "b2"})
con.close()

# --- V3: Federal Theatre Project pictures for plays --------------------------------------------
FTP = ["federal theatre project (new york, n.y.)"]
POSTER = dict(title='WPA Federal Theatre Project 891 presents "Horse eats hat" Maxine Elliott\'s Theatre.',
              summary=None, description=None)
PHOTO = dict(title="The Trojan Incident: Strapless gold gown with green jewelry.", summary=None, description=None)


def ftp(rec, play, cls="government", usable=True, contributors=FTP, partof=(), width=None, height=None):
    return AP.ftp_play_served(cls, usable, contributors, partof, rec["title"], rec["summary"], rec["description"], play,
                              width, height)


check("FTP: a poster's quoted title is the play", ftp(POSTER, "Horse Eats Hat"), True)
check("FTP: a production photograph's head is the play", ftp(PHOTO, "The Trojan Incident"), True)
check("FTP: an article is dropped on either side", ftp(PHOTO, "Trojan Incident"), True)
check("FTP: a record with no rights sentence is used (unmarked)", ftp(POSTER, "Horse Eats Hat", cls="unmarked"), True)
check("control: a title that only contains the play's is another work", ftp(PHOTO, "Incident"), False)
check("control: a longer play's title is not a shorter one's picture",
      ftp(dict(title="Doctor Faustus Lights the Lights: scene", summary=None, description=None), "Doctor Faustus"), False)
check("control: a record that is not the Federal Theatre Project's",
      ftp(PHOTO, "The Trojan Incident", contributors=["bain news service"], partof=["bain collection"]), False)
check("control: a costume design is a drawing, not a production picture",
      ftp(PHOTO, "The Trojan Incident", partof=["federal theatre project: production records: costume designs file"]),
      False)
check("control: a restricted record is refused", ftp(POSTER, "Horse Eats Hat", cls="restricted"), False)
check("control: a record whose image is not online is refused", ftp(POSTER, "Horse Eats Hat", usable=False), False)
check("control: smaller than a tile is refused", ftp(POSTER, "Horse Eats Hat", width=100, height=120), False)
check("control: a title too short to be a name", ftp(dict(title='Presents "It"', summary=None, description=None), "It"), False)
BROTHERS = dict(title='Federal Theatre Project presents "Brothers" by Herbert Ashton Jr.', summary=None, description=None)
check("FTP: a poster naming the author is the play when the author is ours",
      AP.ftp_play_served("government", True, FTP, (), BROTHERS["title"], None, None, "Brothers", None, None, ["Herbert Ashton"]),
      True)
check("control: the same poster is another play when the author is not ours (Terence's The Brothers)",
      AP.ftp_play_served("government", True, FTP, (), BROTHERS["title"], None, None, "The Brothers", None, None, ["Terence"]),
      False)
check("FTP: a poster that names no author stands on its title",
      AP.ftp_play_served("government", True, FTP, (), POSTER["title"], None, None, "Horse Eats Hat", None, None, ["Anyone"]), True)
check("FTP quoted titles read the description too",
      AP.ftp_titles("Poster", None, 'Poster for Federal Theatre Project presentation of "Federal Varieties" at the Civic'),
      ["Federal Varieties"])

# --- V5: pages of unrenewed radio magazine issues ----------------------------------------------
PAGE = "Inside the broadcast of Lux Radio Theatre as Cecil B DeMille directs the cast of the weekly hour of Lux Radio Theatre"
FIRST, LAST = "1934-06-01", "1955-06-01"


def mag(status="not_renewed", nwords=40, text=PAGE, year=1939, name="Lux Radio Theatre", people=(), first=FIRST, last=LAST):
    return AP.magazine_page_served(status, nwords, text, year, name, people, first, last)


check("magazine: a page naming the program in an unrenewed year", mag(), "name")
check("magazine: public domain by age", mag(status="pd_by_age", year=1928, first="1920-01-01"), "name")
check("magazine: a page naming a marked person", mag(text="Peter Lorre leaps from the microphone and Peter Lorre screams", name="Mystery Playhouse",
                                                     people=["Peter Lorre"]), "marked person")
check("control: a renewed issue year is refused", mag(status="renewed"), False)
check("control: an in-copyright issue is refused", mag(status="in_copyright"), False)
check("control: a page of close print is not a picture", mag(nwords=900), False)
check("control: a page whose text does not name the program or a marked person",
      mag(text="A recipe for angel food cake and a column on gardening and thrift"), False)
check("control: the issue's year outside the run (another program of the name)", mag(year=1925, first="1934-06-01"), False)
check("control: a program name too common to be a name (generic)", mag(name="Suspense", text="Suspense builds in the studio"),
      False)
check("control: a marked person's first name alone is not them", mag(text="Peter went home", name="Mystery Playhouse",
                                                                    people=["Peter Lorre"]), False)
LATE = "A long column about the week in radio and the thrift of the home. " * 4 + "Lux Radio Theatre was heard Monday."
check("control: a program named once in passing, late on the page, is not what the page is about", mag(text=LATE, nwords=60), False)
check("control: the name three times but never in the headline is not what the page is about",
      mag(text=LATE + " Lux Radio Theatre again. Lux Radio Theatre.", nwords=70), False)
check("control: a sponsor's advertisement naming the program is not about it",
      mag(text=PAGE + " Try Lux Soap for 10 days. Send 10 cents."), False)
check("control: a trade paper's directory is not a picture",
      AP.magazine_page_served("not_renewed", 40, PAGE, 1939, "Lux Radio Theatre", (), FIRST, LAST, magazine="Variety"), False)
check("page: a magazine for listeners",
      AP.magazine_page_served("not_renewed", 40, PAGE, 1939, "Lux Radio Theatre", (), FIRST, LAST, magazine="Radio Mirror"),
      "name")
check("control: a one-word-ish name is too thin to mean the program",
      mag(name="Darkness", text="Darkness at the studio tonight. Darkness again. Darkness once more."), False)
check("page notice: another holder's copyright on the page", bool(AP.page_notice(PAGE + " Copyright 1938 General Foods Corp.")),
      True)
check("page notice: a photograph credit with the symbol", bool(AP.page_notice(PAGE + " © 1938 NBC")), True)
check("control: the magazine's own publisher notice is the lapsed one",
      AP.page_notice(PAGE + " Copyright 1938, Macfadden Publications, Inc."), None)
check("control: a page with another holder's notice is refused", mag(text=PAGE + " Copyright 1938 General Foods Corp."),
      False)

# --- the magazine harvest and its enrichment, on fixtures ---------------------------------------
import gzip
import json
import tempfile
import harvest_magazine_pages as HM
import enrich_magazine_pages as EM

check("a volume spanning two years is judged on both", HM.years_in("Radio mirror (Nov 1938-Apr 1939)", 1938), [1938, 1939])
check("a title with no year takes the item's", HM.years_in("Radio digest", 1922), [1922])

text = "ignored header\nPage one text\nLux Radio Theatre cast photograph\n"
raw = text.encode()
a, b = raw.index(b"Page"), raw.index(b"Lux")
index = [[0, a, 0, 0], [a, b, 0, 0], [b, len(raw), 0, 0]]
answers = {"x_hocr_searchtext.txt.gz": gzip.compress(raw), "x_hocr_pageindex.json.gz": gzip.compress(json.dumps(index).encode())}
HM.fetch = lambda url, pace: answers.get(url.rsplit("/", 1)[-1].replace("x_", "x_"))
got = HM.pages_from_hocr("x", 0)
check("the page index slices the search text into leaves", [p.strip() for p in got], ["ignored header", "Page one text", "Lux Radio Theatre cast photograph"])
check("control: an issue with no search text is not read as empty", (HM.fetch.__call__("u/other", 0), HM.pages_from_hocr("y", 0)), (None, None))

tmp = tempfile.mkdtemp()
EM.DIR = tmp


def issue(sid, years, magazine, pages):
    json.dump({"id": sid, "title": sid, "magazine": magazine, "years": years, "leaves": 9, "read": "hocr", "pages": pages},
              gzip.open(os.path.join(tmp, sid + ".json.gz"), "wt"))


issue("rm1939", [1939], "Radio Mirror", [[3, 30, "Lux Radio Theatre cast at the microphone of Lux Radio Theatre"],
                                         [4, 30, "Lux Radio Theatre Copyright 1939 General Foods Corp."],
                                         [5, 30, "A recipe for angel food cake and a column on thrift"]])
issue("rm1950", [1950], "Radio Mirror", [[3, 30, "Lux Radio Theatre cast at the microphone of Lux Radio Theatre"]])
issue("rm1925", [1925], "Radio Digest", [[3, 30, "Lux Radio Theatre cast at the microphone of Lux Radio Theatre"]])
db = sqlite3.connect(":memory:")
db.executescript("""
CREATE TABLE series (key TEXT, name TEXT, first_date TEXT, last_date TEXT, networks TEXT);
INSERT INTO series VALUES ('lux', 'Lux Radio Theatre', '1934-06-01', '1955-06-07', NULL);
CREATE TABLE episodes (id TEXT, series_key TEXT, air_date TEXT);
INSERT INTO episodes VALUES ('lux|1934-06-01', 'lux', '1934-06-01');
INSERT INTO episodes VALUES ('lux|1955-06-07', 'lux', '1955-06-07');
CREATE TABLE people (id TEXT, name TEXT);
CREATE TABLE series_marks (series_key TEXT, person_id TEXT);
CREATE TABLE magazine_rights (title TEXT, year INTEGER, status TEXT, usable INTEGER);
INSERT INTO magazine_rights VALUES ('Radio Mirror', 1939, 'not_renewed', 1);
INSERT INTO magazine_rights VALUES ('Radio Mirror', 1950, 'renewed', 0);
INSERT INTO magazine_rights VALUES ('Radio Digest', 1925, 'pd_by_age', 1);
""")
pages = EM.rows(db)
check("magazine pages: the unrenewed issue's page that names the program",
      sorted((r[1], r[2], r[6]) for r in pages), [("rm1939", 3, "name")])
check("control: a renewed issue year, a page with another holder's notice, a page that does not name it, and a year "
      "before the run give none", len(pages), 1)
check("the page image is the issue's own page at 800 px", pages[0][11], "https://archive.org/download/rm1939/page/n3_w800.jpg")

print(f"{ran} checks, {failed} failed")
sys.exit(1 if failed else 0)
