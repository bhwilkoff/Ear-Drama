"""The script parser on small fixtures: roles and lines, directions kept apart, no
word rewritten, and the stub check.

    python3 tests/test_script_parse.py
Broken controls, 2026-10-22, against mutated copies of script_parse.py:
    labels need not recur 6/7, no stub check 6/7, cast block runs on 5/7,
    parentheses read as speech 6/7. "Labels need not recur" first PASSED 7/7: its
    prose word ("Then") was on the never-a-label list, so the fixture now uses "Truly".
Broken controls, 2026-10-23 (where the play begins and ends): no play bounds 11/17 (the
    cached-text shape check among them), no back matter 15/17, no full-name expansion 15/17,
    no cast sub-lists 16/17, no honorific labels 16/17. The cached-text check first PASSED
    with no bounds: it took a "* * *" separator for the play's first heading. Plays counted
    only inside the play window 16/17 (two plays refused); no set-aside gate 16/17.
Broken controls, 2026-10-23 (radio shapes), each failing its own case: no direction on a bare
    label, no multi-paragraph speech, radio italics as directions, no front/back, no note
    kind, no separator heading, no cast-entry rule, no unglue, no bare cues, mixed labels need
    not recur, no quoted or numbered labels: 24-26/27. An unmerged bare label continuing a
    speech failed only the cached-text check. No Gutenberg strip for radio first PASSED
    27/27 (the license after the play was set aside as back matter); the fixture now carries
    a Gutenberg header ("Author: ...") and fails 25/27.
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


COMMERCIALS = RADIO.replace("SOUND: DOOR OPENS", """MIDDLE COMMERCIAL

ANNCR: Johnson's Glo-Coat gives your floors a shine.

HARLOW: That's right, folks.

MUSIC: BRIDGE

ANNCR: And now, back to Wistful Vista.

(SECOND COMMERCIAL)

ANNCR: Get Glo-Coat today.

END OF SECOND COMMERCIAL

SOUND: DOOR OPENS""")


@case
def radio_commercials_are_their_own_parts():
    r = P.parse(COMMERCIALS, "radio")
    roles = [l["role"] for l in r["lines"] if l["kind"] == "speech"]
    assert roles[0] == "ANNCR", roles[:3]
    assert "ANNCR (COMMERCIAL 1)" in roles and "HARLOW (COMMERCIAL 1)" in roles, roles[:12]
    assert "ANNCR (COMMERCIAL 2)" in roles, roles[:12]
    assert roles[roles.index("HARLOW (COMMERCIAL 1)") + 1] == "ANNCR", roles[:12]
    assert roles[roles.index("ANNCR (COMMERCIAL 2)") + 1] == "DOC", roles[:14]
    assert not any("COMMERCIAL" in a for a in r["aliases"]), r["aliases"]


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


def _small_play(a, b, n=40):
    return "ACT I.\n\n" + "\n\n".join(f"{a}. A line of the scene, said plainly, {i}.\n\n{b}. And an answer said back, {i}."
                                      for i in range(n)) + "\n\nTHE END."


@case
def two_plays_in_one_text_are_refused():
    # one cast list, so only the whole-text count of first acts finds the second play
    two = ("*** START OF THE PROJECT GUTENBERG EBOOK WORKS ***\n\nTHE FIRST PLAY\n\nCHARACTERS\n\nALDO\nBORIS\n\n"
           + _small_play("ALDO", "BORIS") + "\n\nTHE SECOND PLAY\n\n" + _small_play("CYRIL", "DORA")
           + "\n\n*** END OF THE PROJECT GUTENBERG EBOOK WORKS ***\n")
    r = P.parse(two, "stage")
    assert r["status"] == "parsed" and not r["clean"] and "several_plays_in_one_text" in r["issues"], r.get("issues")
    one = ("*** START OF THE PROJECT GUTENBERG EBOOK ONE ***\n\nTHE FIRST PLAY\n\nCHARACTERS\n\nALDO\nBORIS\n\n"
           + _small_play("ALDO", "BORIS") + "\n\n*** END OF THE PROJECT GUTENBERG EBOOK ONE ***\n")
    r = P.parse(one, "stage")
    assert r["clean"], r["issues"]


@case
def a_text_that_is_mostly_set_aside_is_refused():
    essay = "\n\n".join("An essay on the drama and its history, which is not a play at all, part %d." % i
                        for i in range(120))
    r = P.parse("*** START OF THE PROJECT GUTENBERG EBOOK ESSAY ***\n\n" + essay + "\n\nCHARACTERS\n\nALDO\nBORIS\n\n"
                + _small_play("ALDO", "BORIS") + "\n", "stage")
    assert r["set_aside_share"] > P.CLEAN_SET_ASIDE and not r["clean"], (r["set_aside_share"], r["issues"])
    assert "mostly_set_aside" in r["issues"], r["issues"]


# ---- radio shapes (measured 2026-10-23 over every cached radio text: 1,028 GRW + 4 Gutenberg) ----

BOOK_RADIO = """The Project Gutenberg EBook of Pilots

Title: Pilots

Author: A. Writer

Release Date: May 1, 2009

*** START OF THE PROJECT GUTENBERG EBOOK PILOTS ***

_HOW TO READ THIS PLAY_

The play in this book has been produced on the radio. The word [_off_] means
the speaker stands away from the microphone.

_CAST_

ALDER
BRISK
NARRATOR

NARRATOR

It was a long winter in the valley, and the river froze early.

That is where our story begins, aboard the _Swallow_.

""" + "\n\n".join(f"ALDER\n\nA line of the scene, said plainly, {i}.\n\nBRISK [_off_]\n\nAn answer from afar, {i}."
                  for i in range(40)) + """

BRISK

The last word,
wrapped over two lines.

       *       *       *       *       *

Transcriber's Note:

Page 9: Corrected a typo.

End of Project Gutenberg's Pilots

*** END OF THE PROJECT GUTENBERG EBOOK PILOTS ***
"""


@case
def radio_label_on_its_own_line_with_a_direction():
    r = P.parse(BOOK_RADIO, "radio")
    assert r["status"] == "parsed" and r["clean"], (r.get("status"), r.get("issues"), r.get("unclassified"))
    assert {x["name"] for x in r["roles"]} == {"NARRATOR", "ALDER", "BRISK"}, r["roles"]
    brisk = next(l for l in r["lines"] if l["role"] == "BRISK")
    assert brisk["parts"][0] == {"mic": "off"} and brisk["parts"][1]["say"].startswith("An answer"), brisk["parts"]


@case
def radio_speech_over_several_paragraphs_is_one_line():
    r = P.parse(BOOK_RADIO, "radio")
    nar = [l for l in r["lines"] if l["role"] == "NARRATOR"]
    assert len(nar) == 1 and "where our story begins" in nar[0]["parts"][-1]["say"], nar
    # a radio script brackets its directions: an italic name is spoken
    assert "_Swallow_" in nar[0]["parts"][-1]["say"], nar[0]["parts"]


@case
def radio_preface_notes_and_separators_are_never_lines():
    r = P.parse(BOOK_RADIO, "radio")
    src = " ".join(l["source"] for l in r["lines"])
    for w in ("HOW TO READ", "microphone", "Transcriber", "Corrected", "End of Project", "*", "A. Writer"):
        assert w not in src, w
    assert not {"PAGE 9", "AUTHOR"} & {x["name"] for x in r["roles"]}, r["roles"]
    assert r["lines"][-1]["source"].endswith("wrapped over two lines."), r["lines"][-1]


CAST_RADIO = """Some Series

An Episode

Date: May 18 1951

CAST:

1ST ANNOUNCER

RICK, private detective
HELEN, Rick's girlfriend

CLERK (2 lines)

NBC ANNCR (1 line)1ST ANNCR: The makers present the program.

NOTE:

This is the text of a published version, bookended with the broadcast's announcements.

MUSIC: THEME

Applause

""" + "\n\n".join(f"RICK: A line of the scene, said plainly, {i}.\n\nHELEN: And an answer said back, {i}.\n\n"
                  f"1ST ANNCR: A word from the sponsor, {i}." for i in range(20)) + """

I know not; this sentence is prose, and not a role at all.

"I": (NARRATES) I dreamt I went to the house again.

MAN #1: Up in the sky!

G O N G

Transcribed by A. Volunteer
"""


@case
def radio_cast_list_entries_with_qualifiers_stay_in_the_cast():
    r = P.parse(CAST_RADIO, "radio")
    assert r["status"] == "parsed" and r["clean"], (r.get("status"), r.get("issues"), r.get("unclassified"))
    for l in r["lines"]:
        assert "private detective" not in l["source"] and "(2 lines)" not in l["source"], l
    assert not any("," in x["name"] for x in r["roles"]), r["roles"]


@case
def radio_glued_label_is_split():
    r = P.parse(CAST_RADIO, "radio")
    first = next(l for l in r["lines"] if l["kind"] == "speech")
    assert first["role"] == "1ST ANNCR" and first["parts"] == [{"say": "The makers present the program."}], first


@case
def radio_notes_and_credits_are_set_aside():
    r = P.parse(CAST_RADIO, "radio")
    src = " ".join(l["source"] for l in r["lines"]) + " ".join(r["unclassified"])
    assert "bookended" not in src and "Volunteer" not in src, src[-300:]


@case
def radio_bare_cues_in_any_case():
    r = P.parse(CAST_RADIO, "radio")
    cues = {l["source"]: l["kind"] for l in r["lines"] if l["kind"] in ("sound", "music")}
    assert cues.get("Applause") == "sound" and cues.get("G O N G") == "sound", cues


@case
def radio_label_shapes_quoted_numbered_and_not_prose():
    r = P.parse(CAST_RADIO, "radio")
    names = {x["name"] for x in r["roles"]}
    assert {"I", "MAN #1"} <= names, names
    assert not [n for n in names if n.startswith("I KNOW")], names


@case
def radio_every_word_is_accounted_for():
    for raw in (BOOK_RADIO, CAST_RADIO, RADIO):
        text = P.clean_html(P.gutenberg_body(raw) if P.GUT_START.search(raw) else raw)
        items = P._radio_items(text)
        # whitespace aside: a glued label is split by a line break, and nothing else changes
        assert "".join("".join(i["source"] for i in items).split()) == "".join(text.split()), "a word was lost"


GRW_TEXTS = os.path.join(os.path.dirname(__file__), "..", ".cache", "grw", "text")


@case
def cached_radio_texts_never_fold_a_label_or_note_into_a_speech():
    """Shape only, over every cached radio text: no speech carries another speaker's label
    on a line of its own, no role is a cast-list entry ("RICK, detective") or a note."""
    import glob
    import json
    files = sorted(glob.glob(os.path.join(GRW_TEXTS, "*.txt")))
    plays = os.path.join(GUTENBERG_TEXTS, "..", "plays.json")
    if os.path.exists(plays):
        files += [os.path.join(GUTENBERG_TEXTS, p["id"][4:] + ".txt") for p in json.load(open(plays))["plays"]
                  if any("Radio plays" in s for s in p.get("subjects") or [])]
    files = [f for f in files if os.path.exists(f)]
    if not files:
        print("SKIP cached_radio_texts_never_fold_a_label_or_note_into_a_speech: no cache")
        return
    bad = []
    for f in files:
        raw = open(f, encoding="utf-8", errors="replace").read()
        text = P.clean_html(P.gutenberg_body(raw) if P.GUT_START.search(raw) else raw)
        if P.stub_check(text):
            continue
        for it in P._radio_items(text):
            if it["kind"] != "speech":
                continue
            if "," in it["role"] or P.R_NOTE.match(it["role"]):
                bad.append((os.path.basename(f), it["role"]))
            for para in it["source"].split("\n\n")[1:]:
                if P._bare(para.strip()):
                    bad.append((os.path.basename(f), para[:40]))
    assert not bad, bad[:10]


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
