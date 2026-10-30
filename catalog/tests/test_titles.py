"""Display titles (tools/titles.py), with the titles that must not change as controls.

    python3 tests/test_titles.py

The vocabulary is a fixture, never the catalog (tests never pin catalog contents).
Mutation controls, each seen to fail this suite on 2026-10-30: `Words.split` taking the
first of two fewest-piece splits; `Words.piece` accepting a two-letter piece outside SHORT;
CODE_PART matching a lone number in any part; `series_titles` ignoring the order.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
from titles import Words, display_name, display_title, series_titles

ran = failed = 0


def check(raw, want, series=None, words=None):
    global ran, failed
    ran += 1
    got = display_title(raw, series, words)
    if got != want:
        failed += 1
        print(f"FAIL {raw!r}: got {got!r}, want {want!r}")


def same(name, got, want):
    global ran, failed
    ran += 1
    if got != want:
        failed += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


# The 2026-10-22 rules.
check("Carolyn_Day_Detective_-_Audition_1", "Carolyn Day Detective - Audition 1")
check("01CbsNews-LinkletterHouseParty", "Cbs News-Linkletter House Party")
check("EdnaWolfeWantsToGetNancyFowler", "Edna Wolfe Wants To Get Nancy Fowler")
check("SHELL CHATEAU_092135.MP3", "SHELL CHATEAU 092135")
check("FibberMcGeeAndMollyTheHallCloset", "Fibber McGee And Molly The Hall Closet")
check("NBC-Story-Behind-The-Headlines---Appeasement-Marches-On", "NBC Story Behind The Headlines - Appeasement Marches On")
check("Dragnet-The-Big-Cast", "Dragnet The Big Cast")
# Controls: hyphenated real words stay.
check("Twenty-Two", "Twenty-Two")
check("Jean-Luc Picard", "Jean-Luc Picard")
check("1945-03-22", "1945-03-22")
check("Episode-12", "Episode-12")
check("Rock-n-Roll Hour", "Rock-n-Roll Hour")
# Controls: already words, so unchanged.
check("Sorry, Wrong Number", "Sorry, Wrong Number")
check("77 Sunset Strip", "77 Sunset Strip")
check("The McGee Closet", "The McGee Closet")
check("NYA Orchestra-- L.F. Demming, Director, April 10", "NYA Orchestra-- L.F. Demming, Director, April 10")
check("UFO RADIO SCARY SEPTEMBER", "UFO RADIO SCARY SEPTEMBER")
check("iPhone", "iPhone")
check("Chapter 01", "Chapter 01")
check("", "")

# Numbering, codes and durations (D3, 2026-10-30).
check("001 Frankenstein 1931.mp3", "Frankenstein 1931")
check("01 The Hobbit", "The Hobbit")
check("Ep 221 Regroup", "Regroup")
check("#257 An Automobile Accident", "An Automobile Accident")
check("e0054 Streetcar Motorman McGee", "Streetcar Motorman McGee")
check("8 01 02 13 The Jack Benny Program Jack's 40th Birthday Again", "The Jack Benny Program Jack's 40th Birthday Again")
check("8 01 02 13 The Jack Benny Program - Jack's 40th Birthday Again", "Jack's 40th Birthday Again",
      series="Jack Benny Program")
check("0005 -The Babe Ruth Collection -Harry The Hat -32-22 -14m42s", "Harry The Hat", series="The Babe Ruth Collection")
check("4115 - Backstage Wife - Episode 4115 - 32-22 - 10m38s", "Episode 4115", series="Backstage Wife")
check("15m08s Harold Suspects Jimmy", "Harold Suspects Jimmy")
check("Open Warfare - X Minus One", "Open Warfare", series="X Minus One")
check("10.01. Return To Memory Lane", "Return To Memory Lane")
check("09 29 The Hobbit 1 8 An Unexpected Party", "The Hobbit 1 8 An Unexpected Party")
check("01 20,000 Leagues Under The Sea Part 1", "20,000 Leagues Under The Sea Part 1")
# Controls: nothing is stripped that leaves no words, and a later number is a chapter.
check("Friar Tuck - 33", "Friar Tuck - 33", series="Ivanhoe")
check("01 2010-09", "01 2010-09")
check("2001 A Space Odyssey", "2001 A Space Odyssey")
check("4. Aufzug", "4. Aufzug")
check("Black Magic Radio 1969", "Black Magic Radio 1969", series="Black Magic")
check("The Fred Allen Show-murder In The Penthouse", "The Fred Allen Show-murder In The Penthouse",
      series="The Fred Allen Show")
check("Frankenstein - The Monster", "Frankenstein - The Monster", series="Frankenstein")
check("Dragnet", "Dragnet", series="Dragnet")

# Case and splitting, from a fixture vocabulary.
W = Words(["Tarzan Meets The Apes", "His First Birthday", "A Birthday Party", "First Things First", "First Love",
           "Birthday Blues", "Love with Honor", "Apes Again",
           "Tarzans Last Stand", "Tarzans Return", "Tarzans Revenge", "Battle with the Apes", "Battle Cry",
           "The Battle Lines", "Apes in the Night", "with Love", "Over the Rainbow", "Over the Hill", "Hill Over",
           "Over Time", "Hill Street", "Rainbow Hill", "the Hill", "OTR Classics (OTR)", "More (OTR) Shows",
           "The OTR Hour", "Summer Nights", "Summer Fun", "Summer Days", "we go", "we are", "we can",
           "en route", "en masse", "en garde", "Inferno XXXI", "Purgatorio XXXI", "Paradiso XXXI",
           "Perry's Office", "At Perry's", "Perry's Case"])
check("EP001 TARZANSFIRSTBIRTHDAY", "Tarzans First Birthday", words=W)
check("BATTLEWITHTHEAPES", "Battle with the Apes", words=W)
check("HALVERSON AT PERRY'S OFFICE (OTR)", "Halverson at Perry's Office (OTR)", words=W)
check("INFERNO XXXI", "Inferno XXXI", words=W)
# Controls: the refusals.
check("SUMMERWEEN NIGHTS", "Summerween Nights", words=W)             # "summer we en": "en" is no SHORT word
check("OVERTHEHILLRAINBOW", "Overthehillrainbow", words=W)           # no split into known words alone
check("TARZANSFIRSTBIRTHDAY", "TARZANSFIRSTBIRTHDAY")                 # no vocabulary, no change
check("Tarzans First Birthday", "Tarzans First Birthday", words=W)    # mixed case is never recased
check("THEBATTLE", "Thebattle", words=W)                              # under ten letters: left whole
P = Words([f"{w} {n}" for w in ("Post", "to", "as", "Ties", "Cream", "of", "Wheat") for n in ("One", "Two", "Three")])
same("control: two short words in a row are no proof", P.split("posttoasties"), None)
same("split: one short word between two is", P.split("creamofwheat"), ["cream", "of", "wheat"])
V = Words([f"{w} {n}" for w in ("Man", "Slaughter", "Mans", "Laughter") for n in ("One", "Two", "Three")])
same("split: two fewest-piece splits are refused", V.split("manslaughter"), None)
same("control: one fewest-piece split is taken", V.split("laughterman"), ["laughter", "man"])
same("display_name: a series has no series to drop", display_name("01 The Hobbit"), "The Hobbit")

# The order a client lists a series' episodes in.
reading = [("r1", None, None, "01 - Mrs. Hudson"), ("r2", None, None, "02 - Baker Street"),
           ("r3", None, None, "03 - Athelney Jones")]
same("order: a reading ordered by its numbers keeps them", series_titles(reading, "A Reading", W),
     {"r1": "01 - Mrs. Hudson", "r2": "02 - Baker Street", "r3": "03 - Athelney Jones"})
dated = [("d1", "1940-01-01", None, "03 - Athelney Jones"), ("d2", "1940-01-08", None, "01 - Mrs. Hudson")]
same("control: a dated series loses the numbers", series_titles(dated, "A Reading", W),
     {"d1": "Athelney Jones", "d2": "Mrs. Hudson"})
alpha = [("v1", None, None, "Vanishing Point - Zebra"), ("v2", None, None, "Vanishing Point - Yak"),
         ("v3", None, None, "Apple")]
same("control: an order that was only alphabetical carries nothing", series_titles(alpha, "Vanishing Point", W),
     {"v1": "Zebra", "v2": "Yak", "v3": "Apple"})

# P-3 (2026-10-30). Each seen failing before its fix; the controls are what must not change.
H = Words([f"{w} {n}" for w in ("barbershop", "Quartet", "Mayfield", "Cigarettes", "May", "Field", "Mac", "Arthur",
                                "MacArthur") for n in ("One", "Two", "Three") if (w, n) != ("Mayfield", "Two")
                                and not (w == "Mayfield" and n == "Three")] + ["Gen MacArthur Speaks"])
check("Ouvenir barbershopQuartet", "Ouvenir barbershop Quartet", words=H)      # both halves proved
check("ArbershopQuartet barbershopQuartet", "ArbershopQuartet barbershop Quartet", words=H)  # "Arbershop" is no word: left whole
check("Souvenir ZzzzzQuartet", "Souvenir ZzzzzQuartet", words=H)                # an unproved half: left whole
check("General MacArthur", "General MacArthur", words=H)                       # the catalog spells the whole
check("iPhone Quartet", "iPhone Quartet", words=H)
check("MAYFIELDCIGARETTES", "Mayfield Cigarettes", words=H)                    # "may field" stays "Mayfield": a title spells it whole
same("residue: a name the catalog spells whole is not split", H.split("mayfield"), None)
M = [("m1", None, None, "The Magic Flute - Mozart")]
same("residue: a series name said once is part of the title", series_titles(M, "Magic Flute", W),
     {"m1": "The Magic Flute - Mozart"})
M2 = M + [("m2", None, None, "The Magic Flute - Part Two")]
same("control: a name repeated on two episodes is a prefix", series_titles(M2, "Magic Flute", W),
     {"m1": "Mozart", "m2": "Part Two"})

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
