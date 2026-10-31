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

# The guard over a real projection.
real = os.environ.get("PROJECTION") or os.path.join(os.path.dirname(__file__), "..", "out", "publish", "ear-drama.sqlite")
if os.path.exists(real):
    d = sqlite3.connect(f"file:{real}?mode=ro", uri=True)
    bad_series = [(k, n) for k, n in d.execute("SELECT key, name FROM series") if DT.series_withheld(n, k, False)]
    check("guard: no series is named for an upload habit", bad_series[:5], [])
    n = d.execute("SELECT COUNT(*) FROM episodes").fetchone()[0]
    empty = [(i, t) for i, t in d.execute("SELECT id, title FROM episodes") if TD.title_defects(t) == ["T_EMPTY"]]
    check("guard: no title is empty or a placeholder", empty[:5], [])
    unreadable = [(i, t) for i, t in d.execute("SELECT id, title FROM episodes") if not DT.readable_title(t)]
    check("guard: every title is readable", unreadable[:5], [])
    rip = sum(1 for (t,) in d.execute("SELECT title FROM episodes") if "T_RIPTAG" in TD.title_defects(t))
    check("guard: rip tags are rare (under 0.2%)", rip <= n * 0.002, True)
elif os.environ.get("PROJECTION"):
    check("the projection named by PROJECTION exists", False, True)
else:
    print("  SKIP  guard: no projection at out/publish/ear-drama.sqlite (name one with PROJECTION)")

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
