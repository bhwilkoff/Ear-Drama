"""Display titles (tools/titles.py), with the titles that must not change as controls.

    python3 tests/test_titles.py
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
from titles import display_title

ran = failed = 0


def check(raw, want):
    global ran, failed
    ran += 1
    got = display_title(raw)
    if got != want:
        failed += 1
        print(f"FAIL {raw!r}: got {got!r}, want {want!r}")


check("001 Frankenstein 1931.mp3", "001 Frankenstein 1931")
check("Carolyn_Day_Detective_-_Audition_1", "Carolyn Day Detective - Audition 1")
check("01CbsNews-LinkletterHouseParty", "Cbs News-Linkletter House Party")
check("EdnaWolfeWantsToGetNancyFowler", "Edna Wolfe Wants To Get Nancy Fowler")
check("SHELL CHATEAU_092135.MP3", "SHELL CHATEAU 092135")
check("FibberMcGeeAndMollyTheHallCloset", "Fibber McGee And Molly The Hall Closet")
# Controls: already words, so unchanged.
check("Sorry, Wrong Number", "Sorry, Wrong Number")
check("77 Sunset Strip", "77 Sunset Strip")
check("The McGee Closet", "The McGee Closet")
check("NYA Orchestra-- L.F. Demming, Director, April 10", "NYA Orchestra-- L.F. Demming, Director, April 10")
check("UFO RADIO SCARY SEPTEMBER", "UFO RADIO SCARY SEPTEMBER")
check("iPhone", "iPhone")
check("Chapter 01", "Chapter 01")
check("", "")

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
