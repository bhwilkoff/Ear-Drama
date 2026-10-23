"""The script parser on small fixtures: roles and lines, directions kept apart, no
word rewritten, and the stub check.

    python3 tests/test_script_parse.py
Broken controls, 2026-10-22, against mutated copies of script_parse.py:
    labels need not recur 6/7, no stub check 6/7, cast block runs on 5/7,
    parentheses read as speech 6/7. "Labels need not recur" first PASSED 7/7: its
    prose word ("Then") was on the never-a-label list, so the fixture now uses "Truly".
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import script_parse as P

FILLER = " ".join(["word"] * 520)

RADIO = """Fibber McGee and Molly

Good Grammar

Date: May 06 1947

CAST:

FIBBER

MOLLY

DOC GAMBLE

MUSIC: THEME UP AND UNDER

ANNCR: The Johnson's Wax program, with Fibber McGee and Molly!

FIBBER: (CHUCKLING) Well, Molly, I've got it all figured out.

MOLLY: You have, dearie?

SOUND: DOOR OPENS

DOC: (OFF) Anybody home?

FIBBER: Doc! Come in, come in.

""" + "\n\n".join(f"MOLLY: Line {i} of the scene, said plainly.\n\nFIBBER: Answer {i}, said back." for i in range(40)) \
    + "\n\nGONG\n\nDOC: Good night, all.\n"

STAGE = """*** START OF THE PROJECT GUTENBERG EBOOK TRIFLES ***

TRIFLES

CHARACTERS

GEORGE HENDERSON, County Attorney
HENRY PETERS, Sheriff
MRS PETERS

SCENE: The kitchen in the now abandoned farmhouse.

""" + "\n\n".join(f"SHERIFF. [Rubbing his hands.] This feels good, line {i}.\n\nMRS PETERS. And it is cold, {i}." for i in range(40)) \
    + "\n\n*** END OF THE PROJECT GUTENBERG EBOOK TRIFLES ***\n"

FOLIO = "*** START OF THE PROJECT GUTENBERG EBOOK X ***\n\n" + "\n\n".join(
    f"  Ham. A little more then kin, {i}\n\n   King. How is it that the Clouds, {i}" for i in range(40)) \
    + "\n\nTruly. This is a prose sentence and not a role.\n\n*** END OF THE PROJECT GUTENBERG EBOOK X ***\n"

CASES = []


def case(fn):
    CASES.append(fn)
    return fn


@case
def radio_roles_lines_and_cues():
    r = P.parse(RADIO, "radio")
    assert r["status"] == "parsed", r.get("status")
    names = {x["name"] for x in r["roles"]}
    assert {"FIBBER", "MOLLY", "DOC", "ANNCR"} <= names, names
    kinds = [l["kind"] for l in r["lines"]]
    assert kinds[0] == "music" and "sound" in kinds, kinds
    assert not any(l["role"] == "CAST" for l in r["lines"])
    assert not [u for u in r["unclassified"] if u in ("FIBBER", "MOLLY", "DOC GAMBLE")], r["unclassified"][:5]


@case
def radio_directions_and_mic_are_parts_not_words():
    r = P.parse(RADIO, "radio")
    fib = next(l for l in r["lines"] if l["role"] == "FIBBER")
    assert fib["parts"][0] == {"direction": "CHUCKLING"}, fib["parts"]
    doc = next(l for l in r["lines"] if l["role"] == "DOC")
    assert doc["parts"][0] == {"mic": "OFF"}, doc["parts"]


@case
def no_word_is_rewritten():
    for raw, kind in ((RADIO, "radio"), (STAGE, "stage"), (FOLIO, "stage")):
        r = P.parse(raw, kind)
        for l in r["lines"]:
            for p in l.get("parts") or []:
                (k, v), = p.items()
                assert " ".join(v.split()) in " ".join(l["source"].split()), (k, v, l["source"])


@case
def stage_role_with_bracketed_direction():
    r = P.parse(STAGE, "stage")
    assert r["status"] == "parsed" and r["clean"], (r.get("status"), r.get("issues"))
    sh = next(l for l in r["lines"] if l["role"] == "SHERIFF")
    assert sh["parts"][0] == {"direction": "Rubbing his hands."}, sh["parts"]
    assert sh["parts"][1]["say"].startswith("This feels good")
    assert {x["name"] for x in r["roles"]} == {"SHERIFF", "MRS PETERS"}, r["roles"]


@case
def mixed_case_labels_need_to_recur():
    r = P.parse(FOLIO, "stage")
    names = {x["name"] for x in r["roles"]}
    assert names == {"HAM", "KING"}, names
    king = [l for l in r["lines"] if l["role"] == "KING"][-1]
    assert "prose sentence" in king["source"], king


@case
def link_page_is_a_stub():
    page = "Richard Diamond, Private Detective\n\nPDF files on Old Time Radio Researchers Group website\n\n" \
           "Date: Date Unknownhttp://www.otrr.org/FILES/Scripts_pdf/Richard_Diamond/"
    r = P.parse(page, "radio")
    assert (r["status"], r["stub_kind"]) == ("stub", "link_page"), r
    assert P.parse("The Whistler\n\nDate: Date UnknownInformation Coming Soon...", "radio")["stub_kind"] == "too_short"
    assert P.parse(RADIO, "radio")["status"] == "parsed"


@case
def long_text_without_dialogue_is_a_failure_not_a_stub():
    r = P.parse("Some Series\n\nTitle\n\nDate: Dec 09 1938\n\n" + FILLER, "radio")
    assert (r["status"], r["issues"]) == ("failed", ["format_unrecognized"]), r


def main():
    failed = 0
    for fn in CASES:
        try:
            fn()
        except (AssertionError, KeyError, StopIteration) as e:
            failed += 1
            print(f"FAIL {fn.__name__}: {e}")
    print(f"{len(CASES) - failed}/{len(CASES)} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
