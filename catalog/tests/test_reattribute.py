"""Re-attribution, names from an item's own metadata, and ID3 titles (tools/reattribute.py, P-6 2026-10-31).

    python3 tests/test_reattribute.py

Fixtures only; tests never pin catalog contents. Each case was seen failing before its rule was written
(the module did not exist), and each control is a refusal: an episode moves only on evidence.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import reattribute as R

ran = failed = 0


def check(name, got, want):
    global ran, failed
    ran += 1
    if got != want:
        failed += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


K2C = {"dragnet": "dragnet", "continentalcelebrityclub": "continentalcelebrityclub", "ourmissbrooks": "ourmissbrooks",
       "camelcaravan": "camelcaravan", "adolfhitler": "adolfhitler", "thebattleoftheages": "battleoftheages"}
TITLES = {"dragnet": {"bigflight", "bigbrink"}}
titles_of = lambda c: TITLES.get(c, set())
RUNS = {"continentalcelebrityclub": (1944, 1948, 12), "camelcaravan": (1933, 1936, 9), "ourmissbrooks": (1948, 1957, 2), "adolfhitler": (1920, 1945, 40)}
run_of = lambda c: RUNS.get(c)


def sp(stem, date=None):
    return R.stem_program(stem, K2C, titles_of, date, run_of)


# stem_program: the file name begins with a program, and the rest is a title the program has.
check("title gate", sp("Dragnet - Big Flight"), ("dragnet", "exact", "title"))
check("title gate, underscores and a trailing tag", sp("Dragnet_-_The_Big_Brink_(AFRS)"), ("dragnet", "exact", "title"))
check("track number and AFRS number are not the program", sp("01 AFRS 12 - Dragnet - Big Flight"), ("dragnet", "exact", "title"))
check("date gate", sp("1946-01-12 0006 - Continental Celebrity Club - Guest - Anne Baxter", "1946-01-12"),
      ("continentalcelebrityclub", "exact", "date"))
check("a noisy name, date gate", sp("Camel Caravan Radio Show - CBS - Chicago", "1935-02-01"),
      ("camelcaravan", "exact", "date"))
check("prefix of two words, date gate", sp("Camel Caravan Zebra Quartz - CBS - Chicago", "1935-02-01"),
      ("camelcaravan", "prefix", "date"))
# Controls: refusals.
check("control: a title the program does not have, no date", sp("Dragnet - Something Else Entirely"), None)
check("control: a date outside the run", sp("1962-01-12 - Continental Celebrity Club - Guest", "1962-01-12"), None)
check("control: a run of two dates is no run", sp("1950-02-01 - Our Miss Brooks - Guest", "1950-02-01"), None)
check("control: a program named in a later part is a title, not the program", sp("Friday the 13th - Our Miss Brooks"), None)
check("control: a name with no title gate and no date", sp("Adolf Hitler #5 (JR)"), None)
check("control: one word prefix of a longer title", sp("Dragnet Big Flight Revisited Again"), None)
check("control: nothing known", sp("Dave Garroway xx-xx-xx 346"), None)
check("control: a stem of codes only", sp("32-22 - 14m42s"), None)

# name_from_metadata
F = lambda t=None, a=None: {"item_title": t, "album": a}
check("item title spells the key", R.name_from_metadata("standbyformars", [F("Stand by for Mars")] * 5),
      ("Stand by for Mars", None, "item title"))
check("item title with punctuation", R.name_from_metadata("dedraakbbendeonderwereld", [F("De Draak, B.B. en de onderwereld ")] * 3),
      ("De Draak, B.B. en de onderwereld", None, "item title"))
check("control: an item title of other words", R.name_from_metadata("powerrecords", [F("Post Apocalyptic Audio Dramas")] * 8), None)
check("control: an item title with no capital is no better", R.name_from_metadata("willradiomatterial", [F("will radio matterial")] * 4), None)
check("album tag on nearly every file", R.name_from_metadata("caseclosed3", [F("CaseClosed3", "Case Closed")] * 9),
      ("Case Closed", "caseclosed", "album tag"))
check("control: too few files", R.name_from_metadata("caseclosed3", [F("CaseClosed3", "Case Closed")] * 2), None)
check("control: a generic album", R.name_from_metadata("rrshow2", [F("RRShow2", "Podcast")] * 9), None)
check("control: an album on half the files", R.name_from_metadata("rrshow2", [F("RRShow2", "Radio Rewind")] * 5 + [F("RRShow2")] * 5), None)
check("control: the album is the key's own spelling", R.name_from_metadata("caseclosed", [F(None, "Case Closed")] * 9), None)

# prefer_tag_title
check("tag restating", R.prefer_tag_title("CaseClosed211", "CC211: Sherlock Holmes and The Lineup", "CaseClosed211"),
      "CC211: Sherlock Holmes and The Lineup")
check("tag when the name gave none", R.prefer_tag_title(None, "The Veldt by X Minus One", "SciFi146"), "The Veldt by X Minus One")
check("control: a real file title stays", R.prefer_tag_title("The Veldt", "SF146: The Veldt by X Minus One", "SciFi146"), "The Veldt")
check("control: a one-word tag", R.prefer_tag_title("Thriller181", "Thriller181", "Thriller181"), "Thriller181")
check("control: a junk tag", R.prefer_tag_title("CaseClosed211", "Track 3", "CaseClosed211"), "CaseClosed211")
check("control: a dated tag is left to the date rules", R.prefer_tag_title("CaseClosed211", "Case Closed 1946-01-12 Show", "CaseClosed211"),
      "CaseClosed211")

# P-7: stem_program on a disc of many programs (loose), hyphenated stems, service words, shelf codes.
check("loose: a program named at the start, no title or date gate",
      R.stem_program("AFRS-Proudly-We-Hail-311-This-Mans-Army", {"proudlywehail": "proudlywehail"}, lambda c: set(), None, lambda c: None, loose=True),
      ("proudlywehail", "prefix", "named"))
check("loose: a dated hyphenated stem keeps its date apart",
      R.stem_program("1954-09-19-AFRS-Proudly-We-Hail-311-This-Mans-Army", {"proudlywehail": "proudlywehail"}, lambda c: set(), "1954-09-19", lambda c: None, loose=True),
      ("proudlywehail", "prefix", "named"))
check("control: the same stem, not loose, no gate",
      R.stem_program("AFRS-Proudly-We-Hail-311-This-Mans-Army", {"proudlywehail": "proudlywehail"}, lambda c: set(), None, lambda c: None), None)
check("loose: a shelf code and a service word are not the program",
      R.stem_program("317137B-Melody Ranch Radio Shows Gene Autry GA-58", {"melodyranch": "melodyranch"}, lambda c: set(), None, lambda c: None, loose=True),
      ("melodyranch", "prefix", "named"))
check("control: loose never names an unknown program",
      R.stem_program("USAF Wolfman Jack s13 Sep72", {"proudlywehail": "proudlywehail"}, lambda c: set(), None, lambda c: None, loose=True), None)

# P-7: a garbled series name that carries on past the item's title into its parenthetical
check("item title with a trailing parenthetical",
      R.name_from_metadata("raybradburybradburyreadsbradburylistening",
                           [F("Ray Bradbury: Bradbury Reads Bradbury (Listening Library, 1975)")] * 14),
      ("Ray Bradbury: Bradbury Reads Bradbury", None, R.PAREN_RULE))
check("control: a parenthetical the key does not carry",
      R.name_from_metadata("raybradbury", [F("Ray Bradbury: Bradbury Reads Bradbury (Listening Library, 1975)")] * 14), None)


# P-7: near_program
def prog(key, name, n, run=None, titles=()):
    return {"key": key, "name": name, "n": n, "run": run, "titles": set(titles)}


def src(key, name, n, years=(), titles=()):
    return {"key": key, "name": name, "n": n, "years": list(years), "titles": set(titles)}


TS = prog("topsecret", "Top Secret", 31, (1950, 1951, 20), ["confession"])
check("near: a misspelling whose dates sit in the run", R.near_program(src("topsercet", "Top Sercet", 15, [1950, 1951]), [TS]), ("topsecret", "date"))
check("near: a title the program has", R.near_program(src("topsercet", "Top Sercet", 2, [], ["confession"]), [TS]), ("topsecret", "title"))
check("near: a joining word dropped", R.near_program(src("murdermidnight", "Murder Midnight", 2, [1946]),
                                                     [prog("murderatmidnight", "Murder At Midnight", 102, (1946, 1950, 60))]),
      ("murderatmidnight", "date"))
check("control: a date outside the run", R.near_program(src("topsercet", "Top Sercet", 15, [1962]), [TS]), None)
check("control: no dates and no titles", R.near_program(src("topsercet", "Top Sercet", 15), [TS]), None)
check("control: two programs this near", R.near_program(src("topsercet", "Top Sercet", 15, [1950]),
                                                       [TS, prog("topsercot", "Top Sercot", 40, (1950, 1951, 20))]), None)
check("control: another production (extra words)", R.near_program(src("luxradiotheaterau", "Lux Radio Theater - AU", 47, [1970]),
                                                                [prog("luxradiotheater", "Lux Radio Theater", 742, (1935, 1972, 500))]), None)
check("control: a bigger series is never folded into a smaller one", R.near_program(src("topsecret", "Top Secret", 31, [1950]),
                                                                                   [prog("topsercet", "Top Sercet", 5, (1950, 1951, 5))]), None)
check("control: different numbers", R.near_program(src("americanarmedforcesradiono16", "American Armed Forces Radio No 16", 20, [1950]),
                                                  [prog("americanarmedforcesradiono15", "American Armed Forces Radio No 15", 396, (1940, 1960, 90))]), None)
check("control: a key under nine letters", R.near_program(src("thehood", "The Hood", 1, [1950]), [prog("thefood", "The Food", 9, (1950, 1951, 5))]), None)

# P-7: disc_groups
NAMES = {"cbsmysterytheaterfantasyselection1": "CBS Mystery Theater Fantasy Selection 1",
         "cbsmysterytheaterfantasyselection2": "CBS Mystery Theater Fantasy Selection 2",
         "americanarmedforcesradiono62": "American Armed Forces Radio No 62",
         "americanarmedforcesradiono63": "American Armed Forces Radio No 63",
         "classiccrimewiththebritsno6": "Classic Crime With The Brits No 6",
         "librivox1": "Shakespeare Monologues Collection vol. 1", "librivox2": "Shakespeare Monologues Collection vol. 2",
         "alcappradioshowqandareel1": "Al Capp Radio Show - Q and A Reel 1",
         "alcappradioshowqanda": "Al Capp Radio Show - Q and A"}
G = R.disc_groups(NAMES, skip={"librivox1", "librivox2"})
check("disc: volumes of one program", G["cbsmysterytheaterfantasy"],
      ("CBS Mystery Theater Fantasy", ["cbsmysterytheaterfantasyselection1", "cbsmysterytheaterfantasyselection2"], False))
check("disc: a distribution service is flagged", G["americanarmedforcesradio"][2], True)
check("disc: a sibling joins the series named for the base", G["alcappradioshowqanda"][1], ["alcappradioshowqanda", "alcappradioshowqandareel1"])
check("control: one volume alone is no group", "classiccrimewiththebrits" in G, False)
check("control: LibriVox projects are works of their own", any("shakespeare" in v[0].lower() for v in G.values()), False)
check("disc_base reads Vol., Volume, Disc, Selection", [R.disc_base(n) for n in ("Foo, Volume 001", "Foo vol. 3", "Foo Disc 4", "Foo")],
      [("Foo", 1), ("Foo", 3), ("Foo", 4), None])

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
