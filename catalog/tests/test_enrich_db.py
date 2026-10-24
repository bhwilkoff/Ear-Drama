"""enrich_db.py: parsers, series mapping and the post-build join, on a small
database built from tools/schema.sql with hand-made Goldin/OTRR inputs.

Controls, each seen to FAIL (2026-10-19) by breaking the rule it guards:
  - same_name replaced by "shares one significant word, or one key contains
    the other": 7 of 51 checks fail (Star and the Story -> Pacific Story,
    Jim's Christmas Stocking -> Christmas, CBS News of the World -> Radio
    News, ...).
  - the two-thirds bound removed from same_name's word subset: 1 fails
    (Guest Star -> Jack Benny As A Guest Star 2).
  - the TV check removed from Goldin linking: 1 fails (a CBS-TV record links).
  - the both-sides-unique rule removed from title linking: 1 fails.
  - the run-date bound removed from the OTRR-history network: 1 fails.
  - the NAME_SUFFIX merge removed from parse_artists: 2 fail (Jr. split off).
  - the DROPs removed from SCHEMA: the re-run raises (table exists).
"""
import json
import os
import sqlite3
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tools"))
import enrich_db as E

failed = 0
checks = 0


def check(cond, msg):
    global failed, checks
    checks += 1
    if not cond:
        failed += 1
        print("FAIL", msg)


def parsers():
    a = E.parse_artists('William Spier (producer, editor, director), Joseph Kearns ("The Man In Black"), '
                        'Sammy Davis, Jr. (singer), Crazy Bull (billed as "Chief Crazy Bull, grandson of '
                        'Sitting Bull" did the war chant), Truman Bradley (commercial spokesman)')
    spier = [x["role"] for x in a if x["name"] == "William Spier"]
    check(spier == ["producer", "editor", "director"], f"Spier roles {spier}")
    kearns = [x for x in a if x["name"] == "Joseph Kearns"]
    check(kearns and kearns[0]["character"] == "The Man In Black" and kearns[0]["role"] == "cast", f"Kearns {kearns}")
    check(any(x["name"] == "Sammy Davis, Jr." and x["role"] == "singer" for x in a), "control: Jr. stays with the name")
    check(not any(x["name"].startswith("Jr") for x in a), "control: no person named Jr.")
    bull = [x for x in a if x["name"] == "Crazy Bull"]
    check(bull and bull[0]["role"] == "cast" and bull[0]["note"], f"long parenthesis is a note, not roles {bull}")
    check(any(x["role"] == "commercial spokesperson" for x in a), "role normalized")

    c = E.parse_artists('Joseph Kearns ("The Man In Black"); William Spier (producer, director);  Ann Fixture ; '
                        'Sammy Davis, Jr. (singer)')
    check([x["name"] for x in c] == ["Joseph Kearns", "William Spier", "William Spier", "Ann Fixture",
                                      "Sammy Davis, Jr."], f"semicolon cast list splits per person {c}")
    check(c[0]["character"] == "The Man In Black" and c[0]["role"] == "cast", f"character kept on split {c[0]}")
    check([x["role"] for x in c if x["name"] == "William Spier"] == ["producer", "director"], "roles kept on split")
    check(not any(";" in x["name"] for x in c), "control: no name carries a semicolon")
    one = E.parse_artists("Edward G. Robinson (cast; guest)")
    check(len(one) == 1 and one[0]["name"] == "Edward G. Robinson", f"control: ';' inside parens is not a separator {one}")
    check(len(E.parse_artists("Edward G. Robinson;")) == 1, "control: one segment is not a list")

    check(E.parse_source("CBS net, KQW, San Jose aircheck") == ("CBS", "network", False), "CBS net")
    check(E.parse_source("Blue Network") == ("Blue", "network", False), "Blue Network")
    check(E.parse_source("Mutual-Don Lee net origination") == ("Mutual-Don Lee", "network", False), "Don Lee")
    check(E.parse_source("CBS-TV net, audio + video")[2] is True, "control: TV source is TV")
    check(E.parse_source("ZIV Syndication") == (None, "syndicated", False), "syndication")
    check(E.parse_source("AFRS origination") == ("AFRS", "afrs", False), "AFRS")
    check(E.parse_source("WOR") == (None, "local:WOR", False), "station")
    check(E.parse_source("*") == (None, None, False), "control: '*' is unknown, not a network")

    check(E.goldin_date("March 01, 1945") == "1945-03-01", "date")
    check(E.goldin_date("February 30, 1945") is None, "control: impossible date")
    check(E.goldin_date("1947") is None, "control: bare year is not a date")
    check(E.goldin_duration("29:42") == (1782, None), "duration")
    check(E.goldin_duration("1:02:03") == (3723, None), "long duration")
    check(E.goldin_duration("*30 minutes") == (None, 30), "nominal minutes")
    check(E.goldin_duration("*1/2 hour") == (None, 30), "nominal half hour")


def names():
    for a, b in [("Kitty Keene, Inc.", "Kitty Keene"), ("The Adventures Of Jungle Jim", "Jungle Jim 02"),
                 ("One Night Stand", "AFRS One Night Stand"), ("Fibber McGee and Company", "FibberMcGee"),
                 ("Tales of the Bizarre", "BBC Ray Bradbury-TalesOfTheBizarre"),
                 ("Good News Of 1938", "Good News")]:
        check(E.same_name(a, b), f"same name: {a} / {b}")
    for a, b in [("CBS News Of The World", "Radio News"), ("Cavalcade of Music, The", "The Cavalcade Of America"),
                 ("BBC Radio Newsreel", "Radio News"), ("Star and the Story, The", "Pacific Story, The"),
                 ("Jim's Christmas Stocking", "Christmas"), ("Guest Star", "Jack Benny As A Guest Star 2")]:
        check(not E.same_name(a, b), f"control, different names: {a} / {b}")


def build():
    db = sqlite3.connect(":memory:")
    db.executescript(open(os.path.join(HERE, "..", "tools", "schema.sql")).read())
    ser = [("suspense", "Suspense"), ("kittykeene", "Kitty Keene"), ("radionews", "Radio News"),
           ("whistler", "The Whistler")]
    for k, n in ser:
        db.execute("INSERT INTO series (key, name) VALUES (?,?)", (k, n))
    eps = [("suspense|1945-03-01", "suspense", "1945-03-01", "My Wife, Geraldine"),
           ("suspense|1945-03-08", "suspense", "1945-03-08", "The Bet"),
           ("suspense|1945-03-02", "suspense", "1945-03-02", "The List"),
           ("suspense|1965-01-01", "suspense", "1965-01-01", "Out of Run"),
           ("x:a/1.mp3", "suspense", None, "The Burning Court"),
           ("x:a/2.mp3", "whistler", None, "Retribution"),
           ("x:a/3.mp3", "whistler", None, "Retribution")]
    for d in ("1938-01-03", "1938-01-04", "1938-01-05", "1938-01-06"):
        eps.append((f"kittykeene|{d}", "kittykeene", d, None))
        eps.append((f"radionews|{d}", "radionews", d, None))
    for e in eps:
        db.execute("INSERT INTO episodes (id, series_key, air_date, title) VALUES (?,?,?,?)", e)
    db.execute("INSERT INTO credits VALUES (?,?,?,?,?)", ("suspense|1945-03-01", "900", "William Spier", "director", "otrr.org"))
    db.commit()
    return db


def goldin_row(cat, prog, date, title=None, artist="", source="CBS net", plot="A plot."):
    return {"CATALOGNUM": cat, "PROGNAME": prog, "SDATE": date, "TITLE": title, "PLOT": plot, "ARTIST": artist,
            "SOURCE": source, "DURATION": "29:42", "QUALITY": "Excellent|Green", "COMPLETE": "Complete",
            "PROGNUMB": None, "SPONSOR": None}


def inputs():
    goldin = [
        goldin_row(24104, "Suspense", "March 01, 1945", '"My Wife, Geraldine"',
                   "Edward G. Robinson, William Spier (director)"),
        goldin_row(24105, "Suspense", "March 01, 1945", None, "Somebody Else", source="CBS-TV net, audio + video"),
        goldin_row(24106, "Suspense", "", '"The Burning Court"', "Charles Ruggles"),
        goldin_row(24107, "Suspense", "March 02, 1945", None,
                   "William Spier (producer); Ann Fixture (host); Joseph Kearns (cast)"),
        goldin_row(30001, "The Whistler", "", '"Retribution"', "Bill Forman"),
    ] + [goldin_row(40000 + i, "CBS News Of The World", f"January 0{d}, 1938", source="CBS net")
         for i, d in enumerate((3, 4, 5, 6))]
    logs = [{"eid": "1", "idp": "8654", "program": "Suspense", "date": "1945-03-08", "epnum": "1", "title": "The Bet",
             "exists": True, "files": [], "people": [{"id": "901", "name": "Joseph Kearns", "role": "cast"}]}]
    logs += [{"eid": f"k{d}", "idp": "500", "program": "Kitty Keene, Inc.", "date": d, "epnum": None, "title": None,
              "exists": True, "files": [], "people": []} for d in ("1938-01-03", "1938-01-04", "1938-01-05")]
    progs = {"8654": {"idp": "8654", "titles": [{"title": "Suspense"}], "genres": [{"genre": "Mystery"}],
                      "histories": [{"begin": "1942-06-17", "end": "1962-09-30", "network": "CBS", "country": "USA",
                                     "dow": "Th", "time": "8:00 PM", "length": "30"}],
                      "sponsors": [{"sponsor": "Roma Wines"}]},
             "500": {"idp": "500", "titles": [{"title": "Kitty Keene, Inc."}], "genres": [], "histories": [],
                     "sponsors": []}}
    full = {"8654": {**progs["8654"], "sponsors": [{"sponsor": "Roma Wines", "begin": "1943-12-02",
                                                    "end": "1947-11-20"}]}}
    people = [{"idp": "900", "first": "William", "last": "Spier"}, {"idp": "901", "first": "Joseph", "last": "Kearns"},
              {"idp": "902", "first": "Edward G.", "last": "Robinson"}]
    pdata = {"902": {"dtbirth": "1893-12-12", "dtdeath": "1973-01-26", "birthName": "Emanuel Goldenberg",
                     "birthPlace": "Bucharest", "links": [{"url": "Robinson, Edward G.&ArtistNumber=1", "idtype": "102"}]}}
    return goldin, logs, progs, full, people, pdata


def join():
    db = build()
    before = db.execute("SELECT COUNT(*) FROM credits").fetchone()[0]
    args = inputs()
    for run in (1, 2):
        stats = E.enrich(db, *args, {})
    q = lambda s, *a: db.execute(s, a).fetchall()
    check(q("SELECT COUNT(*) FROM credits")[0][0] == before, "build_db's credits untouched")
    g = dict(q("SELECT catalognum, episode_id FROM goldin_records"))
    check(g[24104] == "suspense|1945-03-01", f"Goldin links on series+date {g[24104]}")
    check(g[24105] is None, "control: a CBS-TV record does not link")
    check(g[24106] == "x:a/1.mp3", f"undated Goldin links on a unique title {g[24106]}")
    check(g[30001] is None, "control: a title two of our episodes share does not link")
    check(all(g[40000 + i] is None for i in range(4)), "control: CBS News of the World not mapped to Radio News")
    sm = q("SELECT source, program, series_key, method FROM series_map WHERE program LIKE 'Kitty%'")
    check(sm == [("otrr", "Kitty Keene, Inc.", "kittykeene", "date_corroborated")], f"Kitty Keene {sm}")
    plot = q("SELECT plot, plot_display_allowed, plot_provenance FROM goldin_records WHERE catalognum=24104")[0]
    check(plot[0] == "A plot." and plot[1] == 0 and "RadioGOLDINdex" in plot[2], f"plot stored, not displayable {plot}")
    cr = q("SELECT person_id, role, source, method FROM episode_credits WHERE episode_id='suspense|1945-03-01' ORDER BY 1")
    check(("otrr:900", "director", "otrr", "file") in cr, f"build_db credit carried {cr}")
    check(sum(1 for c in cr if c[0] == "otrr:900") == 1, f"control: Goldin's Spier/director deduped {cr}")
    check(("otrr:902", "cast", "goldin", "series_date") in cr, f"Goldin name resolved via OTRR link {cr}")
    cr2 = q("SELECT person_id, source, method FROM episode_credits WHERE episode_id='suspense|1945-03-08'")
    check(cr2 == [("otrr:901", "otrr", "series_date")], f"OTRR log credit on series+date {cr2}")
    net = dict(q("SELECT id, network FROM episodes"))
    check(net["suspense|1945-03-01"] == "CBS", "network from Goldin's source")
    check(net["suspense|1945-03-08"] == "CBS", "network from the OTRR run covering the date")
    check(net["suspense|1965-01-01"] is None, "control: no network outside every run")
    s = q("SELECT networks, first_broadcast, last_broadcast, broadcast_span_source, genres_otrr FROM series "
          "WHERE key='suspense'")[0]
    check(json.loads(s[0]) == ["CBS"] and s[1] == "1945-03-08" and s[3] == "otrr_log"
          and json.loads(s[4]) == ["Mystery"], f"series columns {s}")
    run = q("SELECT network, start, end, sponsor, source FROM program_runs WHERE series_key='suspense'")
    check(run == [("CBS", "1942-06-17", "1962-09-30", "Roma Wines", "otrrpedia:programData")], f"runs {run}")
    p = q("SELECT birth, birth_name FROM people WHERE id='otrr:902'")
    check(p == [("1893-12-12", "Emanuel Goldenberg")], f"person facts {p}")
    sp = q("SELECT person_id, name, role FROM episode_credits WHERE episode_id='suspense|1945-03-02' ORDER BY 1, 3")
    check(sp == [("goldin:ann fixture", "Ann Fixture", "host"), ("otrr:900", "William Spier", "producer"),
                 ("otrr:901", "Joseph Kearns", "cast")], f"cast list split, deduped onto existing people {sp}")
    check(q("SELECT COUNT(*) FROM people WHERE name LIKE '%;%'")[0][0] == 0, "control: no compound person row")
    n1 = q("SELECT COUNT(*) FROM episode_credits")[0][0]
    E.enrich(db, *args, {})
    check(q("SELECT COUNT(*) FROM episode_credits")[0][0] == n1, "control: a re-run adds no duplicates")


def main():
    parsers()
    names()
    try:
        join()
    except Exception as e:  # a crash is a failure, reported as one
        global failed
        failed += 1
        print("FAIL join raised", repr(e))
    print(f"{checks - failed}/{checks} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
