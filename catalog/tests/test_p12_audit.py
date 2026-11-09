"""P-12 (catalog DECISIONS 033): the classes P-11 left open, each decided by a rule we already had, guarded over a real
build. Owner, 2026-11-09: "These are incredibly easy questions to answer using our own rules for how we build." and
"I'm really not sure what you are saying is 'passing' when we are attempting to find issues in the database."

    python3 tests/test_p12_audit.py
    PROJECTION=out/publish/ear-drama.sqlite SOURCE=out/radio-catalog.sqlite python3 tests/test_p12_audit.py

Fixtures prove each rule and its refusal. The guards over a real build never pin a row; each asks whether the build
serves something a rule withholds:
  - an episode in another language (archive.org's language, else the title's script or words) that is not a speech;
  - an episode or series carrying a production label ("- AU", "(Aus)", "Aus 62", "(South Africa)");
  - an undated episode whose own name carries a year after 1972 ("Oct 2019", "(2015)", "Upstate Radio Theatre 2004");
  - a series that names a game broadcast or V-Discs;
  - an upload-named series that is one registry program under its initials or another spelling, by three shared titles;
  - a piece of one broadcast filed as a single (same day, one title's letters inside a registry episode's title);
  - a series under an upload-shaped name ("Babe Ruth Collection") where a program source names its show (DECISIONS 034).
Seen failing on the 2026-11-09 dry-run artifacts of the unchanged tools (counts in DECISIONS 033).
"""
import gzip
import json
import os
import sqlite3
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import audit_audio_rights as A
import display_text as DT
import enrich_scope as S
import reattribute as RA

ran = failed = 0


def check(name, got, want):
    global ran, failed
    ran += 1
    if got != want:
        failed += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


# ---- fixtures: modern dates that are not full dates (006) ----
check("month and year", A.modern_date("The Undead Radio Play - DJCAD Oct 2019", partial=True), "Oct 2019")
check("a year on its own", A.modern_date("Upstate Radio Theatre 2004.mp3", partial=True), "2004")
check("a bracket holding only a year", A.modern_date("02 Double Indemnity [2013].mp3", partial=True), "2013")
check("day, month and year", A.modern_date("Keith McGowan Brekkie - 3DB - 14.03.1988", partial=True), "14.03.1988")
check("control: a bracketed rebroadcast note beside the copy's own date",
      A.modern_date("Navy Lark - s08e07 1966-10-16 - The Army Lark [2019-05-29]", partial=True), None)
check("control: a bracket with words is a note", A.modern_date("Red Macaw (Recreation 4-22-2016)", partial=True), None)
check("control: a note naming a repeat", A.modern_date("Money [Rpt BBC7 3 Oct 2003]", partial=True), None)
check("control: a year the series' own name carries", A.modern_date("2000 Plus 05", partial=True, name="2000 Plus"), None)
check("control: a title that is only a year", A.modern_date("1984.mp3", partial=True), None)
check("control: a month-like word is not a month", A.modern_date("Dartmouth Travel Rex Marshall 1970", partial=True), None)
check("control: without partial, only a full date", A.modern_date("Upstate Radio Theatre 2004", partial=False), None)
check("a dated episode reads a bracketed year only", A.modern_date("Special (2013) (120m)", partial=True, bare=False), "2013")
check("control: a dated episode's bare year is a title's", A.modern_date("The Year 2000", partial=True, bare=False), None)
check("series name year", A.series_name_year("WKBW 1973 Halloween Show"), "1973")
check("control: series name decade", A.series_name_year("Vintage Japanese (1953-1955)"), None)

# ---- fixtures: production labels and languages (006, 027) ----
for name in ("Lux Radio Theater - AU", "The Fat Man (Australia)", "Aus 62 Rocky Starr Lost in Space", "Out of the Night (Au)",
             "It's a Crime, Mr Collins - Aus", "High Adventure (South Africa)", "Gunsmoke(Aus) xx-xx-xx Al Galeco"):
    check(f"label: {name}", bool(A.country_label(name)), True)
for name in ("Augustus", "The Australia Story", "Poirot US", "Captain Midnight", "Paul"):
    check(f"control: no label in {name}", A.country_label(name), None)
check("item language", A.foreign_language({"title": "Billetericidio", "recordings": [{"archive_id": "t", "file": "x.mp3"}]},
                                          {"t": "spa"}), {"source": "archive.org item language", "language": "spa"})
check("control: a speech in another language is kept (027)",
      A.foreign_language({"title": "Adolf Hitler - Rede an die deutsche Jugend", "recordings": [{"archive_id": "h", "file": "x.mp3"}]},
                         {"h": "ger"}), None)
check("control: a speech the item's subjects name is kept",
      A.foreign_language({"title": "Auszug 1", "recordings": [{"archive_id": "h", "file": "x.mp3"}]}, {"h": "ger"},
                         {"h": "Kundgebung in Stuttgart"}), None)
check("control: a US government service abroad is kept",
      A.foreign_language({"title": "Nachrichten", "recordings": [{"archive_id": "v", "file": "x.mp3", "producer_text": "Voice of America"}]},
                         {"v": "ger"}), None)
check("control: English", A.foreign_language({"title": "x", "recordings": [{"archive_id": "e", "file": "x.mp3"}]}, {"e": "english"}), None)
check("control: LibriVox reads a public-domain text", A.foreign_language(
    {"title": "Zueignung", "librivox": True, "recordings": [{"archive_id": "f", "file": "x.mp3"}]}, {"f": "ger"}), None)
check("title script", A.title_language("ヴィンテージ 演歌"), "script")
check("title words", A.title_language("De Cock en het duel in de nacht"), "words")
check("control: a French name in an English title", A.title_language("Cyrano de Bergerac"), None)
check("control: one foreign word", A.title_language("Le Petit Prince"), None)

# ---- fixtures: scope (026) ----
for name in ("Baseball Games", "World Series", "CBOTR Classic Baseball on the Radio", "Kentucky Derby Broadcasts", "Boxing",
             "State High School Basketball Championship Game", "Rose Bowl Game - Stanford vs. Illinois"):
    check(f"sports: {name}", S.sports(name), "name_names_a_game_broadcast")
for name in ("Our Western World Series", "The Bill Stern Sports Newsreel", "Red Grange Football Show", "King Lear on Boxing Day",
             "All star football banquet", "KFBK interviews baseball players Joe Marty", "The Baseball Story Hour"):
    check(f"control: not a game: {name}", S.sports(name), None)
check("music show: no story label, music subjects", S.music_show(False, 20, 15), True)
check("control: a story label keeps it", S.music_show(True, 20, 20), False)
check("control: few music subjects", S.music_show(False, 20, 10), False)

# ---- fixtures: one show under initials or another spelling (026, 031) ----
check("initials", RA.spells_by_initials("W B Hickok", "Wild Bill Hickok"), True)
check("control: initials only", RA.spells_by_initials("GG Season 05", "The Great Gildersleeve"), False)
check("control: other words", RA.spells_by_initials("W B Hitchcock", "Wild Bill Hickok"), False)
check("spelling", RA.spelled_alike("Big Jon And Sparky", "Big Jon and Sparkie"), True)
check("spelling, one extra word", RA.spelled_alike("Big John and Little Sparky", "Big Jon and Sparkie"), True)
check("control: a production label", RA.spelled_alike("Lux Radio Theater - AU", "Lux Radio Theater"), False)
check("control: another first letter", RA.spelled_alike("The Fat Man", "The Thin Man"), False)
cand = {"key": "wildbillhickok", "name": "Wild Bill Hickok", "n": 300, "run": (1951, 1956, 200),
        "titles": {"firstbroadcast", "missourikid", "caseoftheunluckyseven"}}
src = {"key": "wbhickok", "name": "W B Hickok", "n": 214, "years": [],
       "titles": ["First Broadcast (OTR)", "The Missouri Kid (OTR)", "The Case of the Unlucky Seven (OTR)"]}
check("renamed: initials, undated, titles agree", RA.renamed_program(src, [cand]), ("wildbillhickok", "initials", "title"))
check("control: titles that do not agree", RA.renamed_program(dict(src, titles=["A", "Other Story", "Third One"]), [cand]), None)
check("control: two stations' call signs are no spelling", RA.spelled_alike("KEAR San Francisco", "KYA San Francisco"), False)
freedom = {"key": "freedomforum", "name": "Freedom Forum", "n": 40, "run": (1940, 1960, 30), "titles": {"x"}}
check("control: one date inside a long run is a coincidence",
      RA.renamed_program({"key": "ff", "name": "Freedom Forge", "n": 1, "years": [1950], "titles": ["Steel"]}, [freedom]), None)
check("three dates inside the run agree",
      RA.renamed_program({"key": "ff", "name": "Freedom Forge", "n": 3, "years": [1950, 1951, 1952], "titles": []}, [freedom]),
      ("freedomforum", "spelling", "date"))
check("control: a smaller program never takes it", RA.renamed_program(src, [dict(cand, n=10)]), None)

# ---- fixtures: a piece of one broadcast filed as a single (031) ----
series = {"mercury": {"own": False, "eps": 50, "name": "Mercury Theater on the Air"},
          "welles": {"own": True, "eps": 1, "name": "Orson Welles War of the Worlds 10 30"},
          "lux": {"own": False, "eps": 900, "name": "Lux Radio Theater"},
          "hrt": {"own": False, "eps": 90, "name": "Hollywood Radio Theater"}}
eps = {"m": ("mercury", "1938-10-30", "War of the Worlds", False, {"a"}),
       "w": ("welles", "1938-10-30", "Orson Welles - War of the Worlds", False, {"b"})}
check("contained title on the same day", DT.contained_broadcasts(eps, series), {"w": "m"})
check("control: another day", DT.contained_broadcasts(dict(eps, w=("welles", "1938-10-31", "Orson Welles - War of the Worlds", False, {"b"})), series), {})
eps2 = dict(eps, l=("lux", "1938-10-30", "War of the Worlds", False, {"c"}))
check("control: two registry programs hold it that day", DT.contained_broadcasts(eps2, series), {})
check("control: two registry programs are never folded by it",
      DT.contained_broadcasts({"l": ("lux", "1955-02-08", "War of the Worlds", False, set()),
                               "h": ("hrt", "1955-02-08", "The War of the Worlds", False, set())}, series), {})

# ---- fixtures: one star's show under a sponsor- or title-era name (026; coordinator 2026-11-09) ----
nights = ["1947-11-%02d" % d for d in (2, 9, 16, 23, 30)]
shows = {"bergen": {"own": False, "librivox": False, "eps": 400, "idps": ["3250"], "dates": nights + ["1947-12-07"],
                    "run": ("1937-05-09", "1956-07-01")},
         "chase": {"own": False, "librivox": False, "eps": 40, "idps": ["2178", "3250"], "dates": nights[:4],
                   "run": ("1947-11-02", "1947-11-23")},
         "fred": {"own": False, "librivox": False, "eps": 300, "idps": ["3823"], "dates": ["1935-01-02", "1949-06-26"],
                  "run": ("1932-10-23", "1949-06-26")},
         "town": {"own": False, "librivox": False, "eps": 60, "idps": ["3823"], "dates": ["1936-01-01"],
                  "run": ("1936-01-01", "1936-01-01")}}
check("same nights and a shared OTRR program; one registry program under two names",
      DT.same_show(shows), {"chase": ("bergen", "same_nights"), "town": ("fred", "registry_alias")})
check("control: other nights", DT.same_show(dict(shows, chase=dict(shows["chase"], dates=["1931-12-13", "1932-01-03", "1933-02-05"]))),
      {"town": ("fred", "registry_alias")})
check("control: no shared program", DT.same_show(dict(shows, chase=dict(shows["chase"], idps=["2178"]))),
      {"town": ("fred", "registry_alias")})
check("control: outside the run", DT.same_show(dict(shows, town=dict(shows["town"], dates=["1960-01-01"]))),
      {"chase": ("bergen", "same_nights")})
check("same night in one show is one broadcast", DT.same_day_in_series(
    {"b": ("bergen", "1947-11-09", "Bergen and Horses", False, "bergen"),
     "c": ("bergen", "1947-11-09", "Guests Maurice Evans", False, "chase")}, {"c"}, {"chase"}), {"c": "b"})
check("control: without the same-show fold the titles decide", DT.same_day_in_series(
    {"b": ("bergen", "1947-11-09", "Bergen and Horses", False, "bergen"),
     "c": ("bergen", "1947-11-09", "Guests Maurice Evans", False, "chase")}, {"c"}), {})

# ---- fixtures: names and titles an upload left raw (025, 028, 031) ----
import otr_parse as P
import polish as PL
import titles as TI
check("collection note on a name", DT.clean_series_name("Tarzan (all runs)"), ("Tarzan", None))
check("collection note: combines all dates", DT.clean_series_name("Bobby Benson (Combines all dates)"), ("Bobby Benson", None))
check("control: a year in brackets is no collection note", DT.clean_series_name("Tarzan (1951)"), ("Tarzan (1951)", None))
check("sort letter", DT.clean_series_name("zSherlock Holmes"), ("Sherlock Holmes", None))
check("control: a lowercase prefix that is a name's", DT.clean_series_name("eBay Radio"), ("eBay Radio", None))
check("date code tail", DT.clean_series_name("Big City Nights 30 10 13"), ("Big City Nights", None))
check("control: a number that is no date", DT.clean_series_name("Tonight at 8 30"), ("Tonight at 8 30", None))
check("lead code: no context", DT.clean_series_name("Rc Superman"), (None, "series_name_has_no_context"))
check("control: a two-letter word", DT.clean_series_name("Dr Christian"), ("Dr Christian", None))
check("catalog code", DT.decide_episode("67073A-Billy Williams; Jim Ambross", "Billy Williams", None, None)[0], "Billy Williams; Jim Ambross")
check("date code and number", DT.decide_episode("460507 249.5 A Day at Camp", "Archie Andrews", None, None)[0], "A Day at Camp")
check("series name and code", DT.decide_episode("Crime Does Not Pay-500529-34-Imported Headaches", "Crime Does Not Pay", None, None)[0],
      "Imported Headaches")
check("control: a quantity", DT.decide_episode("20000 Leagues Under the Sea", "X", None, None)[0], "20000 Leagues Under the Sea")
check("collector credit: nothing left", DT.decide_episode("Tom C. Miller Collection", "No School Today", None, None)[3],
      "no_readable_title_and_no_date_or_number")
check("collector credit composed when dated", DT.decide_episode("Tom C. Miller Collection", "No School Today", "1954-04-13", None)[0],
      "No School Today, April 13, 1954")
check("cut off on a small word: withheld", DT.decide_episode("Surprise Awaits the Mayor a", "Big Jon", None, None)[3],
      "no_readable_title_and_no_date_or_number")
check("control: ends on a word", DT.decide_episode("A Matter of Life and Death", "X", None, None)[0], "A Matter of Life and Death")
check("restore a cut title from a witness", DT.restore_cut("The Silver Clippe", ["Menace to the Silver Clipper", "The Silver Clipper"]),
      "The Silver Clipper")
check("control: a witness with more words is no cut", DT.restore_cut("The Hunted", ["The Hunted Man"]), None)
check("markup", PL.polish_title("<strong>13: David Part 1</strong>"), "13: David Part 1")
w = TI.Words(["Meta Tells all", "Ted is here", "the Leg broke", "Bob Hastings sings", "Bob says to Hastings", "Leg To leg",
              "Tells a tale", "Ted and Tells", "to and fro", "Bob to Ted", "Hastings Leg To", "to bed", "Meta Ted Bob"] * 3)
check("humps split into known words", TI.GLUED_TOKEN.sub(w.humps, "Meta TellsTed Off, No LegTo Stand On, BobHastings"),
      "Meta Tells Ted Off, No Leg To Stand On, Bob Hastings")
check("control: a name's hump", TI.GLUED_TOKEN.sub(w.humps, "Fibber McGee and DeMille"), "Fibber McGee and DeMille")
check("control: a piece the catalog never spells", TI.GLUED_TOKEN.sub(w.humps, "JrsSecret"), "JrsSecret")
check("a note where a title should be", DT.decide_episode("(Radio Comedy)", "Anything Legal", None, 3)[0], "Anything Legal, episode 3")
check("a network where a title should be", DT.decide_episode("NBC", "Lora Lawton", "1947-03-04", None)[0], "Lora Lawton, March 4, 1947")
check("a station and city", DT.decide_episode("WOR, NY", "Last Trip", "1938-12-04", None)[0], "Last Trip, December 4, 1938")
check("control: a title with a network in it", DT.decide_episode("NBC Short Story Thing", "X", None, None)[0], "NBC Short Story Thing")
check("an uploader's signature", DT.decide_episode("Silver Eagle Trouble Trail D.D.Teoli Jr. A.C", "The Silver Eagle", None, None)[0],
      "Silver Eagle Trouble Trail")
check("label: a collection's dash", bool(A.country_label("Aus - The O' Brien Girl")), True)
check("control: a German word", A.country_label("Aus der Welt"), None)
check("xx in any case", DT.decide_episode("Xx Xx Xx-Audition", "Train Time", None, None)[0], "Audition")
check("a radio play the item names in another language", A.foreign_language(
    {"title": "Moord in de ridderzaal", "recordings": [{"archive_id": "d", "file": "x.mp3"}]}, {}, {"d": "hoorspel KRO"}),
    {"source": "the item's own record names a radio play or audiobook in another language", "language": "not English"})
check("control: an English radio play", A.foreign_language(
    {"title": "Murder in the Hall", "recordings": [{"archive_id": "e", "file": "x.mp3"}]}, {}, {"e": "radio play"}), None)
check("two-digit year read in this century", P.modern_two_digit("1920-02-08", "2020-03-01 10:00:00"), "2020-02-08")
check("control: an old upload", P.modern_two_digit("1920-02-08", "2009-03-01"), None)
check("control: a date after the upload", P.modern_two_digit("1921-05-08", "2021-03-01"), None)
check("control: a year with broadcasting", P.modern_two_digit("1935-02-08", "2035-03-01"), None)

# ---- fixtures: a fold keeps the program's own title, and the key follows it (DECISIONS 034) ----
fold = {"casebook": {"name": "The Newly Discovered Casebook Of Sherlock Holmes", "eps": 475, "own": False},
        "newadv": {"name": "The New Adventures Of Sherlock Holmes", "eps": 48, "own": False},
        "baberuthcollection": {"name": "Babe Ruth Collection", "eps": 23, "own": False},
        "adventuresofbaberuth": {"name": "Adventures of Babe Ruth", "eps": 9, "own": False},
        "fredallen": {"name": "The Fred Allen Show", "eps": 579, "own": False},
        "townhall": {"name": "Town Hall Tonight", "eps": 73, "own": False},
        "cs": {"name": "Chase And Sanborn Program", "eps": 57, "own": False},
        "bergen": {"name": "Edgar Bergen And Charlie McCarthy", "eps": 288, "own": False},
        "big": {"name": "Suspense Reel", "eps": 30, "own": True}, "small": {"name": "Suspense Theater", "eps": 3, "own": True},
        "bag": {"name": "Escape", "eps": 90, "own": True, "bag": True}, "esc": {"name": "Escape Singles", "eps": 2, "own": True}}
wit = {"newadv": {"otrr": {DT.witness_tokens("New Adventures of Sherlock Holmes")},
                  "goldin": {DT.witness_tokens("The New Adventures Of Sherlock Holmes")},
                  "wiki": {DT.witness_tokens("The New Adventures of Sherlock Holmes (radio series)")}},
       "casebook": {"otrr": {DT.witness_tokens("Sherlock Holmes")},
                    "goldin": {DT.witness_tokens("The Newly Discovered Casebook Of Sherlock Holmes")}},
       "baberuthcollection": {"otrr": {DT.witness_tokens("Babe Ruth")}},
       "adventuresofbaberuth": {"otrr": {DT.witness_tokens("Adventures of Babe Ruth")}},
       "fredallen": {"otrr": {DT.witness_tokens("Fred Allen Show, The")}, "goldin": {DT.witness_tokens("The Fred Allen Show")}},
       "townhall": {"goldin": {DT.witness_tokens("Town Hall Tonight")}}}
got, named = DT.name_survivors({"newadv": "casebook", "adventuresofbaberuth": "baberuthcollection", "townhall": "fredallen",
                                "cs": "bergen", "small": "big", "esc": "bag"}, fold, wit, {"cs": {"Chase and Sanborn Coffee"}})
check("the name more program sources write survives, and the key follows it", got.get("casebook"), "newadv")
check("a witnessed program name beats a collection's", got.get("baberuthcollection"), "adventuresofbaberuth")
check("named folds report why", (named.get("casebook"), named.get("baberuthcollection")),
      (("newadv", "witness"), ("adventuresofbaberuth", "witness")))
check("control: a show's best-witnessed name stays when a title-era name folds in", got.get("townhall"), "fredallen")
check("control: a sponsor's name never takes over a program's", got.get("cs"), "bergen")
check("unwitnessed: the name that is not upload-shaped survives", got.get("big"), "small")
got2, named2 = DT.name_survivors({"tarzanallruns": "tarzan"}, {"tarzan": {"name": "Tarzan", "eps": 40, "own": True},
                                  "tarzanallruns": {"name": "Tarzan", "eps": 360, "own": True}}, {})
check("control: the same name either way keeps the survivor's key", (got2, named2), ({"tarzanallruns": "tarzan"}, {}))
check("an upload-shaped show takes the one program name its sources write",
      DT.witness_name(["boriskarloffcollection"], "Boris Karloff Collection",
                      {"boriskarloffcollection": {("boris", "karloff", "show"): "Boris Karloff Show"}}), "Boris Karloff Show")
check("control: two program names, no choice", DT.witness_name(["x"], "Sherlock Holmes Collection",
      {"x": {("sherlock", "holmes"): "Sherlock Holmes", ("new", "adventures"): "New Adventures"}}), None)
check("control: a name that is not upload-shaped stands", DT.witness_name(["x"], "Town Hall Tonight",
      {"x": {("fred", "allen", "show"): "The Fred Allen Show"}}), None)
check("a grab bag never survives", "bag" in set(got.values()), False)
check("witness names read inverted articles and encyclopedia qualifiers",
      (DT.witness_tokens("Fred Allen Show, The"), DT.witness_tokens("The Fred Allen Show (radio program)")),
      (("fred", "allen", "show"), ("fred", "allen", "show")))
for n in ("Babe Ruth Collection", "Jack Benny Singles", "Ron Bowser John Dunning Project", "The Whistler Reel", "GG Season 05",
          "Adventures of Babe Ruth 08 Eps", "Lux Vol 2"):
    check(f"upload-shaped: {n}", DT.upload_shaped(n), True)
for n in ("The Shadow", "The Single Girl", "Project Mercury", "Screen Guild Theater", "Season of Fear", "The Collector"):
    check(f"control: a program's name: {n}", DT.upload_shaped(n), False)

# ---- the guards over a real build ----
real = os.environ.get("PROJECTION") or os.path.join(os.path.dirname(__file__), "..", "out", "publish", "ear-drama.sqlite")
src_db = os.environ.get("SOURCE") or os.path.join(os.path.dirname(__file__), "..", "out", "radio-catalog.sqlite")
if os.path.exists(real) and os.path.exists(src_db):
    d = sqlite3.connect(f"file:{real}?mode=ro", uri=True)
    s = sqlite3.connect(f"file:{src_db}?mode=ro", uri=True)
    names = dict(d.execute("SELECT key, name FROM series"))
    served = {e: (sk, a, t) for e, sk, a, t in d.execute("SELECT id, series_key, air_date, title FROM episodes")}
    registry = {k for (k,) in s.execute("SELECT key FROM series WHERE in_spine = 1 OR otrr_programs IS NOT NULL OR is_librivox = 1")}
    librivox = {k for (k,) in s.execute("SELECT key FROM series WHERE is_librivox = 1")}
    first = {}
    for eid, aid, f in d.execute("SELECT episode_id, archive_id, url FROM recordings WHERE rank = 0"):
        first[eid] = (aid, f.rsplit("/", 1)[-1])
    raw = {eid: (t, f) for eid, t, f in s.execute(
        "SELECT e.id, e.title, r.file FROM episodes e JOIN recordings r ON r.episode_id = e.id AND r.rank = 0")}
    cols = {r[1] for r in s.execute("PRAGMA table_info(items)")}
    itext = {i: (t or "") for i, t in s.execute("SELECT id, title FROM items")}
    lang = {}
    if "language" in cols:
        lang = {i: l for i, l in s.execute("SELECT id, language FROM items WHERE language IS NOT NULL")}
    meta = os.path.join(os.path.dirname(os.path.abspath(src_db)), "..", ".cache", "meta")
    for aid in sorted({v[0] for v in first.values()}):   # archive.org's own record: the words the build read
        p = os.path.join(meta, aid + ".json.gz")
        if os.path.exists(p):
            it = json.load(gzip.open(p)).get("item") or {}
            if "language" not in cols:
                lang[aid] = A.language_of(it.get("language"))
            itext[aid] = " ".join(str(it.get(k) or "") for k in ("title", "description", "subject", "creator", "publisher",
                                                              "contributor", "source", "notes"))
    us = set()   # OTRRpedia names a US run: an American production whatever an item's language field says
    pedia = os.path.join(os.path.dirname(os.path.abspath(src_db)), "..", ".cache", "otrrpedia", "progPedia.json.gz")
    if os.path.exists(pedia) and "otrr_idp" in {r[1] for r in s.execute("PRAGMA table_info(series)")}:
        keys_of = {}
        for k, idps in s.execute("SELECT key, otrr_idp FROM series WHERE otrr_idp IS NOT NULL"):
            for i in idps.split(","):
                keys_of.setdefault(i, []).append(k)
        us = A.us_series_keys(json.load(gzip.open(pedia)), lambda p: keys_of.get(p.get("idp"), []))
    other = []
    for eid, (sk, a, t) in sorted(served.items()):
        if eid not in first or sk in librivox or sk in us:
            continue
        aid, f = first[eid]
        rt, rf = raw.get(eid, (t, f))
        ep = {"title": rt or t, "series_name": names.get(sk), "recordings": [{"archive_id": aid, "file": rf or f}]}
        if A.foreign_language(ep, lang, itext):
            other.append((names.get(sk), t))
    check("guard: no served episode is in another language (speeches kept)", (len(other), other[:6]), (0, []))
    labels = sorted({(names[k],) for k in names if k not in librivox and A.country_label(names[k])})
    labels += sorted((names.get(sk), t) for eid, (sk, a, t) in served.items() if sk not in librivox and (
        A.country_label(t) or A.country_label(raw.get(eid, ("", ""))[1].rsplit(".", 1)[0])))
    check("guard: no served episode or series carries a production label", (len(labels), labels[:6]), (0, []))
    modern = sorted((str(names.get(sk)), str(raw[eid])) for eid, (sk, a, t) in served.items() if not a and eid in raw
                    and A.modern_date(*raw[eid], partial=True, name=names.get(sk)))
    check("guard: no served undated episode carries a year after 1972", (len(modern), modern[:6]), (0, []))
    games = sorted(n for k, n in names.items() if k not in librivox and (S.sports(n) or S.V_DISC.search(n or "")))
    check("guard: no served series names a game broadcast or V-Discs", (len(games), games[:6]), (0, []))
    by_series = {}
    for eid, (sk, a, t) in served.items():
        by_series.setdefault(sk, []).append((sk, a, t))
    renamed = []
    index = {}
    for r in sorted(registry & set(names)):
        for w in RA._name_words(names[r]):
            if len(w) >= 3 and w not in RA.STOP_WORDS:
                index.setdefault(w, set()).add(r)
    for k in sorted(names):
        if k in registry:
            continue
        near = set()
        for w in RA._name_words(names[k]):
            near |= index.get(w, set())
        for test in (RA.spells_by_initials, RA.spelled_alike):   # exactly one program that near (026)
            hits = [r for r in sorted(near) if test(names[k], names[r])]
            if len(hits) != 1:
                continue
            r = hits[0]
            mine = [t for (sk, a, t) in by_series.get(k, ()) if t]
            theirs = {A.norm_title(t) for (sk, a, t) in by_series.get(r, ()) if t}
            if RA._agree({"titles": mine, "years": []}, {"titles": theirs, "run": None}):
                renamed.append((names[k], names[r]))
            break
    check("guard: no served upload-named series is a program under its initials or another spelling",
          (len(renamed), renamed[:6]), (0, []))
    idps = dict(s.execute("SELECT key, otrr_idp FROM series WHERE otrr_idp IS NOT NULL")) \
        if "otrr_idp" in {r[1] for r in s.execute("PRAGMA table_info(series)")} else {}
    shows = {}
    for eid, (sk, a, t) in served.items():
        v = shows.setdefault(sk, {"own": sk not in registry, "librivox": sk in librivox, "eps": 0, "dates": [],
                                  "idps": sorted((idps.get(sk) or "").split(",")) if idps.get(sk) else []})
        v["eps"] += 1
        if a and len(a) == 10:
            v["dates"].append(a)
    for v in shows.values():
        v["dates"].sort()
        v["run"] = (v["dates"][0], v["dates"][-1]) if v["dates"] else (None, None)
    one = sorted((names[k], names[r], rule) for k, (r, rule) in DT.same_show(shows).items())
    check("guard: no two served registry series are one show under two names", (len(one), one[:6]), (0, []))
    info = {k: {"own": k not in registry, "librivox": k in librivox, "eps": 0, "name": names[k]} for k in names}
    def composed(sk, a, t):   # a title composed from the series' name and the date (display_text.compose_title)
        got = DT.compose_title(names.get(sk), a, None)
        return bool(got) and PL.small_words(got[0]) == t
    clean = {e for (e,) in s.execute("SELECT id FROM episodes WHERE state = 'keep_clean'")}
    rows = {eid: (sk, a, t or "", composed(sk, a, t), set(), eid in clean) for eid, (sk, a, t) in served.items()}
    pieces = DT.contained_broadcasts(rows, info)
    show = sorted((names[served[e][0]], served[e][2], names[served[v][0]], served[v][2]) for e, v in pieces.items())
    check("guard: no piece of one broadcast is served as a single", (len(show), show[:6]), (0, []))
    # DECISIONS 034: a served series' name is never upload-shaped when a program source names the show it is. The
    # show is the served key and every key the build folded into it (display_text.json beside the projection).
    witnesses = DT.program_witnesses(s)
    try:
        merged = json.load(open(os.path.join(os.path.dirname(os.path.abspath(real)), "display_text.json"))).get("merged") or {}
    except (OSError, ValueError):
        merged = {}
    group = {k: {k} for k in names}
    for old, new in merged.items():
        if new in group:
            group[new].add(old)
    titled = []
    for k in sorted(names):
        if k in librivox or not DT.upload_shaped(names[k]):
            continue
        said = sorted({" ".join(t) for m in group[k] for ns in (witnesses.get(m) or {}).values() for t in ns
                       if not DT.upload_shaped(" ".join(t))})
        if said:
            titled.append((names[k], said[:3]))
    check("guard: no served series is upload-named where a program source names its show", (len(titled), titled[:8]), (0, []))
elif os.environ.get("PROJECTION"):
    check("the build named by PROJECTION and SOURCE exists", False, True)
else:
    print("  SKIP  guards: no build at out/publish/ear-drama.sqlite and out/radio-catalog.sqlite (name them)")

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
