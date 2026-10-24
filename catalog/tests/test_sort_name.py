"""sort_name (tools/sort_name.py): the golden cases every client's A-to-Z relies on.

    python3 tests/test_sort_name.py
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
from sort_name import sort_name

ran = failed = 0


def check(name, want):
    global ran, failed
    ran += 1
    got = sort_name(name)
    if got != want:
        failed += 1
        print(f"FAIL {name!r}: got {got!r}, want {want!r}")


check('"Fixture Quoted"', "fixture quoted\"")
check(": FIXTURE COLON", "fixture colon")
check("? Fixture Question!", "fixture question!")
check("'Fixture Apostrophe'", "fixture apostrophe'")
check("The Fixture Hour", "fixture hour")
check("A Fixture Date", "fixture date")
check("An Fixture Evening", "fixture evening")
check('"The Fixture Quoted Article"', "fixture quoted article\"")
check("Ánother Fixtüre", "another fixture")
check("21st Fixture Century", "21st fixture century")
# Controls: words that merely begin with an article's letters, and a lone article.
check("Theatre Fixture", "theatre fixture")
check("Another Fixture", "another fixture")
check("Anthology Fixture", "anthology fixture")
check("The", "the")
check("A", "a")
check("???", "???")
check("", "")

order = sorted(["The Fixture Zed", '"Fixture Alpha"', "3 Fixture Digits", ": Fixture Mid", "Fixture Beta"], key=sort_name)
ran += 1
if order != ["3 Fixture Digits", '"Fixture Alpha"', "Fixture Beta", ": Fixture Mid", "The Fixture Zed"]:
    failed += 1
    print(f"FAIL order {order}")

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
