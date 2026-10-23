"""The script parser on small fixtures: roles and lines, directions kept apart, no
word rewritten, and the stub check.

    python3 tests/test_script_parse.py
Broken controls, 2026-10-22, against mutated copies of script_parse.py:
    labels need not recur 6/7, no stub check 6/7, cast block runs on 5/7,
    parentheses read as speech 6/7. "Labels need not recur" first PASSED 7/7: its
    prose word ("Then") was on the never-a-label list, so the fixture now uses "Truly".
Broken controls, 2026-10-23 (where the play begins and ends): no play bounds 10/15 (the
    cached-text shape check among them), no back matter 13/15, no full-name expansion 13/15,
    no cast sub-lists 14/15, no honorific labels 14/15. The cached-text check first PASSED
    with no bounds: it took a "* * *" separator for the play's first heading.
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


# ---- where the play begins and ends (measured 2026-10-23 over every cached Gutenberg text) ----

FARCE = """*** START OF THE PROJECT GUTENBERG EBOOK FARCE ***

THE
GLOBE STAGE

BOSTON:
WALTER PUBLISHER & CO.

1. =Lost Things.= A Drama in Three Acts. By J. M.
Morton. 3 Male, 3 Female characters.

2. =Old Honesty.= A Comic Drama in Two Acts. By J. M.
Morton. 5 Male, 2 Female characters.

3. =A Fix.= A Farce in One Act. By W. E.
Morton. 2 Male characters.

4. =Two Heads.= A Farce in One Act. By T. J.
Morton. 4 Male characters.

A KIND ATTACHMENT.
A Farce.

CHARACTERS.

MR. CLAPBOARD, a landlord.
EBENEZER CROTCHET, a father.

COSTUMES.

CLAPBOARD, gray wig, brown coat, dark pants, and a very long scarf to the knee.

EBENEZER, gray wig, blue coat with brass buttons, dark pants, hat, and a long cane.

SCENE.--_A room._

_Enter MR. CLAPBOARD, followed by EBENEZER._

_Clapboard._ This is the room, sir.

_Ebenezer._ O, it is! The abode of my son.

""" + "\n\n".join(f"_Clap._ Come, come, sir, line {i}.\n\n_Eben._ Pooh, pooh, answer {i}." for i in range(30)) \
    + """

_Disposition at the fall of the Curtain._

GLOBE STAGE.

5. =Brother Ben.= A Farce in One Act. By J. M.
Morton. 3 Male characters.

6. =Mary Moo.= A Farce in One Act. By J. M.
Morton. 2 Male characters.

7. =Blue.= A Comedy in One Act. By J. M.
Morton. 2 Male characters.

*** END OF THE PROJECT GUTENBERG EBOOK FARCE ***
"""

FOLIO_NOTE = """*** START OF THE PROJECT GUTENBERG EBOOK HAMLET ***

Director's Notes:

Here are the first few lines, as they are presented herein:

  Barnardo. Who's there?
  Fran. Nay answer me: Stand & vnfold
your selfe

   Bar. Long liue the King

       *       *       *       *       *

As I understand it, the printers often ran out of certain letters.

The Tragedie of Hamlet

Actus Primus. Scoena Prima.

Enter Barnardo and Francisco two Centinels.

  Barnardo. Who's there?
  Fran. Nay answer me: Stand & vnfold
your selfe

""" + "\n\n".join(f"   Bar. Long liue the King, {i}\n\n   Fran. You come most carefully, {i}\n\n"
                  f"   Barn. Haue you had quiet Guard, {i}" for i in range(40)) + """

Exeunt.

FINIS.

*** END OF THE PROJECT GUTENBERG EBOOK HAMLET ***
"""


def _words(raw):
    return " ".join(raw.split())


@case
def front_matter_never_becomes_a_role():
    r = P.parse(FARCE, "stage")
    assert r["status"] == "parsed" and r["clean"], (r.get("status"), r.get("issues"), r.get("unclassified"))
    names = {x["name"] for x in r["roles"]}
    assert names == {"CLAP", "EBEN"}, names
    assert r["set_aside"]["front"] > 0, r["set_aside"]
    for l in r["lines"]:
        assert "Morton" not in l["source"] and "GLOBE" not in l["source"] and "BOSTON" not in l["source"], l


@case
def a_full_name_that_expands_a_label_is_that_role():
    r = P.parse(FARCE, "stage")
    sp = [l for l in r["lines"] if l["kind"] == "speech"]
    assert (sp[0]["role"], sp[0]["parts"]) == ("CLAP", [{"say": "This is the room, sir."}]), sp[0]
    assert sp[1]["role"] == "EBEN" and sp[1]["source"].startswith("_Ebenezer._"), sp[1]
    r = P.parse(FOLIO_NOTE, "stage")
    sp = [l for l in r["lines"] if l["kind"] == "speech"]
    assert sp[0]["source"] == "Barnardo. Who's there?" and sp[0]["role"] in ("BAR", "BARN"), sp[0]
    assert not [u for u in r["unclassified"] if "Barnardo" in u], r["unclassified"]


@case
def a_note_that_quotes_the_play_stays_out_of_its_lines():
    r = P.parse(FOLIO_NOTE, "stage")
    assert r["status"] == "parsed" and r["clean"], (r.get("status"), r.get("issues"))
    src = [l["source"] for l in r["lines"]]
    assert sum("Who's there?" in s for s in src) == 1, [s for s in src if "Who's there?" in s]
    assert not [s for s in src if "printers" in s or "Director" in s], src[:5]


@case
def the_costume_list_belongs_to_the_cast_list():
    r = P.parse(FARCE, "stage")
    assert not [u for u in r["unclassified"] if "wig" in u], r["unclassified"]
    assert not [l for l in r["lines"] if "wig" in l["source"]]


@case
def back_matter_after_the_play_is_set_aside():
    r = P.parse(FARCE, "stage")
    assert r["set_aside"]["back"] >= 3, r["set_aside"]
    assert "Brother Ben" not in " ".join(l["source"] for l in r["lines"])
    r = P.parse(FOLIO_NOTE, "stage")
    assert r["lines"][-1]["source"] == "Exeunt.", r["lines"][-1]


@case
def a_label_may_carry_an_honorific():
    body = "\n\n".join(f"Mrs. Roberts: “Line {i} of the scene, said plainly.”\n\nRoberts: “Answer {i}, said back to her.”" for i in range(40))
    r = P.parse("*** START OF THE PROJECT GUTENBERG EBOOK X ***\n\n_Enter Mrs._ Roberts.\n\n" + body
                + "\n\n_Enter Mrs._ Roberts.\n\n_Enter Mrs._ Roberts.\n\nTHE END\n", "stage")
    assert {x["name"] for x in r["roles"]} == {"MRS. ROBERTS", "ROBERTS"}, r["roles"]


@case
def every_word_set_aside_is_still_accounted_for():
    for raw in (FARCE, FOLIO_NOTE):
        items, _ = P._stage_items(P.gutenberg_body(raw))
        assert _words("\n\n".join(i["source"] for i in items)) == _words(P.gutenberg_body(raw)), "a word was lost"


GUTENBERG_TEXTS = os.path.join(os.path.dirname(__file__), "..", ".cache", "gutenberg", "text")


@case
def cached_texts_no_castable_role_lives_only_before_the_play():
    """Shape only, over every cached text: a castable role (5+ lines) never has all its
    lines before the play's first cast list or act/scene heading."""
    import glob
    files = sorted(glob.glob(os.path.join(GUTENBERG_TEXTS, "*.txt")))
    if not files:
        print("SKIP cached_texts_no_castable_role_lives_only_before_the_play: no cache")
        return
    bad = []
    for f in files:
        items, _ = P._stage_items(P.gutenberg_body(open(f, encoding="utf-8", errors="replace").read()))
        mark = next((k for k, it in enumerate(items) if it["kind"] == "cast" or (it["kind"] == "heading" and (
            P.PLAY_MARK.match(it["source"]) or P.LATIN_HEAD.match(it["source"])))), None)
        if mark is None:
            continue
        at = {}
        for k, it in enumerate(items):
            if it["kind"] == "speech":
                at.setdefault(it["role"], []).append(k)
        bad += [(os.path.basename(f), role) for role, ks in at.items() if len(ks) >= P.CASTABLE_LINES
                and max(ks) < mark]
    assert not bad, bad


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
