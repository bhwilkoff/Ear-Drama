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

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
