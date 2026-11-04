"""The text a listener reads (tools/display_text.py, tools/text_defects.py; DECISIONS 025, owner 2026-10-31).

    python3 tests/test_display_text.py
    PROJECTION=out/publish/ear-drama.sqlite python3 tests/test_display_text.py

Fixtures prove each rule and its refusal. With PROJECTION (or out/publish/ear-drama.sqlite) set, the guard
also runs over every row of the real artifact: no series named for a date, an identifier or a grab bag, no
episode title that is empty, run together or unreadable. The guard counts classes; it never pins a row.
Seen failing on the live projection of 2026-10-30 (297 series named for a date, 3,840 empty titles).
"""
import os
import sqlite3
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import display_text as DT
import text_defects as TD

ran = failed = 0


def check(name, got, want):
    global ran, failed
    ran += 1
    if got != want:
        failed += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


# Classifier: each class and its control.
check("dated name", TD.series_defects("1959 10"), ["S_DATED"])
check("long digits then a word", TD.series_defects("19411207 part"), ["S_DATED", "S_LOWER"])
check("control: a real title that starts with a number", TD.series_defects("20000 Leagues Under the Sea"), [])
check("control: a numbered show", TD.series_defects("77 Sunset Strip"), [])
check("lowercase identifier", TD.series_defects("jbintro"), ["S_LOWER"])
check("run together", TD.series_defects("CaseClosed3"), ["S_RUNTOGETHER"])
check("hyphen-joined", TD.series_defects("Remote-HarryJames"), ["S_RUNTOGETHER"])
check("control: Mc names", TD.series_defects("McGee and Molly"), [])
check("grab bag word", TD.series_defects("Singles & Doubles Collection"), ["S_COLLECTION"])
check("control: LibriVox keeps its reader's title", TD.series_defects("Shakespeare Monologues Collection vol. 4", "librivox1396"), [])
check("empty title", TD.title_defects("xx xx xx"), ["T_EMPTY"])
check("rip tag", TD.title_defects("Hillybilly Feud (OTR)"), ["T_RIPTAG"])
check("code", TD.title_defects("Show [b007jvn8]"), ["T_CODE"])
check("doubled", TD.title_defects("To Rent -- Danger"), ["T_DOUBLED"])
check("control: an ellipsis", TD.title_defects("Gone... Again"), [])
check("control: a clean title", TD.title_defects("Sorry, Wrong Number"), [])

# Series withheld.
check("a date name is withheld", DT.series_withheld("1959 10", "195910", True), "series_name_is_a_date")
check("an identifier is withheld", DT.series_withheld("rrthriller2", "rrthriller2", True), "series_name_is_an_identifier")
check("a file name is withheld", DT.series_withheld("Barbara Jean Coles Birthday Party Telegraph Binghamcanyonutah Trip Pics", "x", True),
      "series_name_is_a_file_name")
check("an uploader's grab bag is withheld", DT.series_withheld("Singles & Doubles Collection", "k", False), "series_is_an_uploaders_grab_bag")
check("control: a collection named for a person stays", DT.series_withheld("Boris Karloff Collection", "k", False), None)
check("control: a real program stays", DT.series_withheld("Suspense", "suspense", False), None)
check("control: a long LibriVox title stays", DT.series_withheld("A Very Long Title That A Reader Gave To A Play That Runs On And On Part 2", "librivox1", True), None)

check("an upload code in the name is withheld", DT.series_withheld("UIUC Archives 1306005", "uiuc", True), "series_name_is_a_file_name")
check("control: a year in a name is not a code", DT.series_withheld("Radio News 1944", "radionews1944", False), None)

# Episodes: source, composed, withheld.
check("control: Chapter 19 is the source's own word", DT.decide_episode("Chapter 19", "Woyzeck", None, 19)[1], "source")
check("a readable title is the source's", DT.decide_episode("The Burning Court", "Suspense", "1942-06-17", None),
      ("The Burning Court", "source", ["episodes.title"], None))
check("guard: a repeated air date is dropped from a title", DT.decide_episode("Red Goes To The Fights - 1941-11-11", "Red", "1941-11-11", None)[0], "Red Goes To The Fights")
check("guard: a bracketed air date is dropped", DT.decide_episode("Cops And Robbers [1964-03-19]", "S", "1964-03-19", None)[0], "Cops And Robbers")
check("guard: another date is spelled out", DT.decide_episode("Frankenstein (Repeat of 1931-08-03)", "W", "1932-03-07", None)[0], "Frankenstein (Repeat of August 3, 1931)")
check("guard: a trailing air date is dropped", DT.decide_episode("Criscos Radio Newspaper 1944-03-14", "C", "1944-03-14", None)[0], "Criscos Radio Newspaper")
check("guard: an asterisk-wrapped uploader note leaves a series name", DT.clean_series_name("The Shadow Recreations **Updated 1 27 **", "k")[0], "The Shadow Recreations")
check("guard: an asterisk-wrapped uploader note leaves an episode title", DT.decide_episode("Chapter One **Updated 1 27 **", "S", None, None)[0], "Chapter One")
check("control: a lone asterisk is not an uploader note", DT.strip_uploader_note("MacArthur*s Dismissal"), "MacArthur*s Dismissal")
check("guard: a trailing reel code leaves an episode title", DT.decide_episode("Poison Gas (BB REEL 0552)", "S", None, None)[0], "Poison Gas")
check("guard: a reel code with a track leaves a title", DT.decide_episode("The Raincoat (JD REEL 0206 TRACK 2)", "S", None, None)[0], "The Raincoat")
check("guard: a disc code leaves a title", DT.decide_episode("Night Beat [Disc 123456]", "S", None, None)[0], "Night Beat")
check("control: a parenthesis that is not a code stays", DT.strip_archive_code("Sound (Last Show of the Series)"), "Sound (Last Show of the Series)")
check("date composes", DT.decide_episode("xxx", "Suspense", "1952-04-26", None),
      ("Suspense, April 26, 1952", "composed", ["series.name", "episodes.air_date"], None))
check("number composes", DT.decide_episode("Episode 112", "Gunsmoke", None, 112),
      ("Gunsmoke, episode 112", "composed", ["series.name", "episodes.num"], None))
check("none title composes too", DT.decide_episode(None, "Gunsmoke", "1955-09-10", 3)[1], "composed")
check("control: a date wins over a number", DT.decide_episode("deel 04", "Dams", "1950-01-02", 4)[0], "Dams, January 2, 1950")
check("nothing to compose from: withheld", DT.decide_episode("jbintro", "Radio", None, None),
      (None, None, [], "no_readable_title_and_no_date_or_number"))
check("control: a bad date is not composed", DT.decide_episode("xxx", "Radio", "1950-13-40", None)[3],
      "no_readable_title_and_no_date_or_number")

# Recovering a despaced name from evidence.
KN = {"annsothern": "Ann Sothern", "mynameisnero": "My Name Is Nero"}
check("a person's name", DT.recover_name("annsothern", KN), "Ann Sothern")
check("control: nothing matches, stays withheld", DT.recover_name("jbintro", KN), None)
check("control: the same spelling is no recovery", DT.recover_name("Ann Sothern", {"annsothern": "Ann Sothern"}), None)

# P-7 job A: a title that is one word and a number is a file name.
check("a series token and a number is composed from the number", DT.decide_episode("TopSecret15", "Top Secret", None, 15),
      ("Top Secret, episode 15", "composed", ["series.name", "episodes.num"], None))
check("a token and a number, a date composes", DT.decide_episode("Hunting300", "Abbott And Costello Show", "1946-02-07", 300)[0],
      "Abbott And Costello Show, February 7, 1946")
check("a token and a number, nothing to compose from: withheld", DT.decide_episode("CheerUp1930", "Belle Baker", None, None)[3],
      "no_readable_title_and_no_date_or_number")
check("control: words and a number are a title", DT.readable_title("Apollo 13"), True)
check("control: a number then words", DT.readable_title("3 Skeleton Key"), True)
check("control: one word, no number", DT.readable_title("Marathon"), True)

# P-7 job C: a grab bag named by a count or a genre and a year (only when an upload named it).
check("a counted bag", DT.series_withheld("500 Christmas Shows", "500christmasshows", True), "series_is_an_uploaders_grab_bag")
check("a genre and a year", DT.series_withheld("Science Fiction 1968", "sciencefiction1968", True), "series_is_an_uploaders_grab_bag")
check("control: a registry program with a count", DT.series_withheld("77 Sunset Strip", "77sunsetstrip", False), None)
check("control: a registry program with a year", DT.series_withheld("Science Fiction 1968", "sciencefiction1968", False), None)
check("control: a numbered show an upload named", DT.series_withheld("77 Sunset Strip", "77sunsetstrip", True), None)

# P-7 job D: an apostrophe only from a registry's spelling.
check("apostrophe from an alias", DT.repair_apostrophe("The Witchs Tale", ["The Witch's Tale", "Witch's Tale", "the witchs tale"]), "The Witch's Tale")
check("apostrophe, curly", DT.repair_apostrophe("Bachelors Children", ["Bachelor’s Children"]), "Bachelor’s Children")
check("control: no alias spells it", DT.repair_apostrophe("Heres To Veterans", ["Here to Veterans"]), "Heres To Veterans")
check("control: two spellings, no guess", DT.repair_apostrophe("Witches Tale", ["Witches' Tale", "Witche's Tale"]), "Witches Tale")
check("control: a stray apostrophe is no possessive", DT.repair_apostrophe("Molle Mystery Theater", ["Molle' Mystery Theater"]), "Molle Mystery Theater")
check("control: a name that has its apostrophe", DT.repair_apostrophe("Duffy's Tavern", ["Duffys Tavern"]), "Duffy's Tavern")
check("control: nothing to compare", DT.repair_apostrophe("Dads Army", None), "Dads Army")

# P-7 job E: scope reasons and music records.
check("a V-Disc is a music record", DT.episode_out_of_scope("048 V-Disc A Chorus and Organ - Joy To The World"), "out_of_scope_music_record")
check("control: a radio show", DT.episode_out_of_scope("Suspense, April 26, 1952"), None)
check("scope kinds map to reason codes", sorted(DT.SCOPE_REASONS.values()),
      ["out_of_scope_concert", "out_of_scope_lecture", "out_of_scope_music_set"])

# P-9: names an upload cut, numbered or strung together. Each class, then the real titles that must survive.
cs = DT.clean_series_name
check("page suffix is dropped", cs("Superman page01"), ("Superman", None))
check("a bare side has no program", cs("Side 2"), (None, "series_name_is_a_fragment"))
check("an unclosed bracket is cut", cs("Banter (s01"), ("Banter", None))
check("a dangling Side is cut", cs("The Best of Fibber McGee & Molly Side"), ("The Best of Fibber McGee & Molly", None))
check("a dangling Part after a dash", cs("The Freedland Files - Part"), ("The Freedland Files", None))
check("control: Sunny Side is a whole title", cs("On the Sunny Side"), ("On the Sunny Side", None))
check("control: Part 1 is the source's own", cs("Henry VI, Part 1"), ("Henry VI, Part 1", None))
check("reels of several programs are withheld", cs("Mystery Reel.Suspense.X Minus One.Black Museum"), (None, "series_is_a_reel_compilation"))
check("a one-letter program in a reel still splits", cs("Mystery Reel.Theatre V.Dimension X.Weird Circle"), (None, "series_is_a_reel_compilation"))
check("a mystery reel of one group", cs("Frank Sinatra and Others Mystery Reel"), ("Frank Sinatra and Others", None))
check("a lone reel word has no program", cs("Christmas Reel"), (None, "series_is_a_reel_compilation"))
check("the reel word goes, the program stays", cs("FDR Speaks.Reel Series"), ("FDR Speaks", None))
check("one program on a reel", cs("Bergen and McCarthy.Bits and Pieces Reel"), ("Bergen and McCarthy", None))
check("programs joined by dots are withheld", cs("Tales of the Texas Rangers.Cisco Kid"), (None, "series_name_joins_programs"))
check("control: a sentence is not a join (speeches stay)", cs("First War Address. WGN."), ("First War Address. WGN.", None))
check("control: a dot inside brackets is not a join", cs('"How Good Is American Air Power" (prog.1, part2) American Legion')[1], None)
check("control: initials are not a join", cs("T.S. Eliot Reading His Poetry"), ("T.S. Eliot Reading His Poetry", None))
check("control: an abbreviation is not a join", cs("Capt.Midnight"), ("Capt.Midnight", None))
check("control: an ellipsis is not a join", cs("This...Our Land Get on Board"), ("This...Our Land Get on Board", None))
check("uploader initials are dropped", cs("APM Stan Kenton Story D.D.Teoli Jr. A.C"), ("APM Stan Kenton Story", None))
check("uploader initials leave no program", cs("101 Vintage No 2 D D Teoli Jr A C"), (None, "series_name_has_no_context"))
check("a glued count is dropped", cs("Jills All Time Jukebox31"), ("Jills All Time Jukebox", None))
check("an episode code is dropped", cs("Sexton Blake - s01e01"), ("Sexton Blake", None))
check("an upload's episode number leaves no program", cs("GG Ep119"), (None, "series_name_has_no_context"))
check("a month and day leave no program", cs("SS Dec18"), (None, "series_name_has_no_context"))
check("control: real titles are untouched", [cs(n)[0] for n in ("33 Half Moon Street", "2000 Plus", "1938 Radio News", "Ford V8 Revue", "Radio 4 Extra")],
      ["33 Half Moon Street", "2000 Plus", "1938 Radio News", "Ford V8 Revue", "Radio 4 Extra"])
check("control: LibriVox keeps its reader's name", cs("Part 2 (Dramatic Reading", "librivox9"), ("Part 2 (Dramatic Reading", None))

check("a title cut mid-bracket loses the bracket", DT.cut_title("Jack Armstrong 41-05-07 (FROM (DON MARRIS)"), "Jack Armstrong 41-05-07")
check("control: a closed bracket stays", DT.cut_title("Gone Again (Part 2)"), "Gone Again (Part 2)")
check("control: a date in a name is not a glued month", cs("15 post prayer speeches by Mahatma Gandhi August 24"),
      ("15 post prayer speeches by Mahatma Gandhi August 24", None))
run = {"a%d" % i: "%d Maigret Case %d" % (10 + i, i) for i in range(4)}
check("a numbered run of upload-named series is track numbers", sorted(DT.track_numbered(run, set(run))), sorted(run))
check("control: a registry program is really numbered", DT.track_numbered(run, set()), set())
check("control: a lone number is part of the title", DT.track_numbered({"k": "33 Half Moon Street", "j": "40 Other Show"}, {"k", "j"}), set())
check("control: a quantity is part of the title", DT.track_numbered({"a": "100 Years of Motion Pictures", "b": "101 Dalmatians",
      "c": "99 Best Shows"}, {"a", "b", "c"}), set())
check("an impossible date is a file code", DT.spell_iso_dates("TJed 1946-05-38 #192 Stagecoach Pushed Off Cliff", None), "Stagecoach Pushed Off Cliff")
check("an impossible date with no day", DT.spell_iso_dates("Arch an 1949-09-00 Dinner in a Restaurant", None), "Dinner in a Restaurant")
check("an impossible date as an aka tail", DT.spell_iso_dates("The Mystery of the Magic Mesaaka Tm1949-12-00", None), "The Mystery of the Magic Mesa")
check("a real date is still spelled out", DT.spell_iso_dates("Report of 1944-03-14", None), "Report of March 14, 1944")
check("a track number is removed", DT.strip_track_number("10 Maigret's Boyhood Friend"), "Maigret's Boyhood Friend")
check("dotted track number", DT.strip_track_number("34.Habakkuk"), "Habakkuk")


def S(name, key, own=True, eps=1, first=None, last=None, cleaned=False, lv=False, aliases=()):
    return {"name": name, "cleaned": cleaned, "librivox": lv, "own": own, "eps": eps, "first": first, "last": last, "aliases": list(aliases)}


check("quotes only: one show", DT.merge_into({"armyhour": S("The Army Hour", "x", False, 7), "thearmyhour": S('"The Army Hour"', "x")}),
      {"thearmyhour": "armyhour"})
check("& and 'and': one show", DT.merge_into({"b1": S("Bergen & McCarthy", "x", eps=2), "b2": S("Bergen and McCarthy", "x")}), {"b2": "b1"})
check("a track number on the key: one show", DT.merge_into({"02tarzan": S("Tarzan", "x"), "tarzan": S("Tarzan", "x", False, 152)}), {"02tarzan": "tarzan"})
check("fragments of one upload join", DT.merge_into({"p1": S("Superman", "x", cleaned=True, eps=2), "p2": S("Superman", "x", cleaned=True, eps=9)}),
      {"p1": "p2"})
check("fragments join the registry program that names them", DT.merge_into({"p1": S("Superman", "x", cleaned=True),
      "adv": S("The Adventures Of Superman", "x", False, 1391, aliases=["Superman"])}), {"p1": "adv"})
check("same single air date: one show", DT.merge_into({"n1": S("Naughty Navy", "x", first="1965-12-25", last="1965-12-25"),
      "n2": S("Naughty Navy", "x", first="1965-12-25", last="1965-12-25")}), {"n2": "n1"})
check("a merged series shows the whole run", DT.merged_span({"b": "a"}, {"a": ("1940-01-01", "1941-01-01", '["NBC"]'),
      "b": ("1938-05-01", "1950-02-02", '["CBS", "NBC"]')}), {"a": ("1938-05-01", "1950-02-02", '["NBC", "CBS"]')})
check("control: an undated fragment leaves the dates", DT.merged_span({"b": "a"}, {"a": ("1940-01-01", "1941-01-01", None),
      "b": (None, None, None)}), {"a": ("1940-01-01", "1941-01-01", None)})
check("control: a LibriVox reading and a broadcast are two productions", DT.merge_into({"henryv": S("Henry V", "x", first="1942-10-25", last="1942-10-25"),
      "librivox4773": S("Henry V", "x", False, 5, lv=True)}), {})
check("control: same name, different stems and dates stay apart", DT.merge_into({"01thehobbit": S("The Hobbit", "x", eps=19),
      "hobbit": S("The Hobbit", "x", False, 8, "1968-09-29", "1968-11-17")}), {})
check("control: two interviews with one title stay apart", DT.merge_into({"a": S("In Conversation With", "x", first="2002-01-01", last="2002-01-01"),
      "b": S("In Conversation With", "x", first="2004-01-01", last="2004-01-01")}), {})

# The guard over a real projection.
real = os.environ.get("PROJECTION") or os.path.join(os.path.dirname(__file__), "..", "out", "publish", "ear-drama.sqlite")
if os.path.exists(real):
    d = sqlite3.connect(f"file:{real}?mode=ro", uri=True)
    bad_series = [(k, n) for k, n in d.execute("SELECT key, name FROM series") if DT.series_withheld(n, k, False)]
    check("guard: no series is named for an upload habit", bad_series[:5], [])
    n = d.execute("SELECT COUNT(*) FROM episodes").fetchone()[0]
    empty = [(i, t) for i, t in d.execute("SELECT id, title FROM episodes") if TD.title_defects(t) == ["T_EMPTY"]]
    p9 = [(k, n) for k, n in d.execute("SELECT key, name FROM series") if DT.clean_series_name(n, k) != (n, None)]
    check("guard P-9: no series name is a fragment, reel, code or uploader string", p9[:5], [])
    names = {k: n for k, n in d.execute("SELECT key, name FROM series")}
    check("guard P-9: no run of track-numbered names", sorted(DT.track_numbered(names, set(names)))[:5], [])
    dupes = DT.merge_into({k: {"name": n, "cleaned": False, "librivox": k.startswith("librivox"), "own": True, "eps": c,
                               "first": f, "last": la, "aliases": []}
                           for k, n, c, f, la in d.execute("SELECT key, name, episodes, first_date, last_date FROM series")})
    check("guard P-9: no show is split by quotes, '&' or a track number", sorted(dupes.items())[:5], [])
    cut = [(i, t) for i, t in d.execute("SELECT id, title FROM episodes") if DT.cut_title(t) != (t or "").strip()]
    check("guard P-9: no episode title is cut off mid-bracket", cut[:5], [])
    check("guard: no title is empty or a placeholder", empty[:5], [])
    unreadable = [(i, t) for i, t in d.execute("SELECT id, title FROM episodes") if not DT.readable_title(t)]
    check("guard: every title is readable", unreadable[:5], [])
    iso = [(i, t) for i, t in d.execute("SELECT id, title FROM episodes") if DT.ISO_IN_TITLE.search(t or "")]
    check("guard: no shown title carries an ISO date", iso[:5], [])
    rip = sum(1 for (t,) in d.execute("SELECT title FROM episodes") if "T_RIPTAG" in TD.title_defects(t))
    check("guard: rip tags are rare (under 0.2%)", rip <= n * 0.002, True)
elif os.environ.get("PROJECTION"):
    check("the projection named by PROJECTION exists", False, True)
else:
    print("  SKIP  guard: no projection at out/publish/ear-drama.sqlite (name one with PROJECTION)")

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
