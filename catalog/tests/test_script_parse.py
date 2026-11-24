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


HONORIFIC_LINES = [
    ("MRS. AUSTIN.", "[She is young and beautiful.] Why do you do this, line {i}?"),
    ("DR. RANK.", "I am the most wretched of all my patients, line {i}."),
    ("M. PERRICHON.", "Madame, you will permit me, line {i}."),
    ("CAPT. HOLT.", "Steady now, all hands, line {i}."),
    ("MME. CHENU.", "Mais non, line {i}."),
]


@case
def an_honorific_abbreviation_is_part_of_the_speaker_name():
    # real shapes: "MRS. AUSTIN. [She ...]" (The Second-Story Man), "MRS. MARWOOD." (The Way of the World)
    body = "\n\n".join(f"{n} {t.format(i=i)}\n\nSMITH. And an answer said back, {i}."
                       for i in range(12) for n, t in HONORIFIC_LINES)
    r = P.parse("*** START OF THE PROJECT GUTENBERG EBOOK X ***\n\nTHE PLAY\n\nACT I.\n\n" + body
                + "\n\nTHE END\n\n*** END OF THE PROJECT GUTENBERG EBOOK X ***\n", "stage")
    names = {x["name"] for x in r["roles"]}
    assert {"MRS. AUSTIN", "DR. RANK", "M. PERRICHON", "CAPT. HOLT", "MME. CHENU", "SMITH"} <= names, names
    assert not names & {"MRS", "DR", "M", "CAPT", "MME"}, names
    scene = P.parse("*** START OF THE PROJECT GUTENBERG EBOOK X ***\n\nTHE PLAY\n\nACT I.\n\n" + body.replace("SMITH. And", "MRS. FAINALL, FOIBLE.\n\nSMITH. And")
                    + "\n\nTHE END\n\n*** END OF THE PROJECT GUTENBERG EBOOK X ***\n", "stage")
    assert "MRS" not in {x["name"] for x in scene["roles"]}, scene["roles"]
    assert next(x for x in r["roles"] if x["name"] == "MRS. AUSTIN")["lines"] == 12


@case
def an_abbreviation_outside_the_honorific_list_still_ends_at_the_period():
    body = "\n\n".join(f"SMITH. A line of the scene, said plainly and at some length, {i}, {FILLER[:60]}.\n\nZED. And an answer said back, {i}."
                       for i in range(20))
    r = P.parse("*** START OF THE PROJECT GUTENBERG EBOOK X ***\n\nTHE PLAY\n\nACT I.\n\n" + body
                + "\n\nTHE END\n\n*** END OF THE PROJECT GUTENBERG EBOOK X ***\n", "stage")
    assert {x["name"] for x in r["roles"]} == {"SMITH", "ZED"}, r["roles"]


@case
def the_title_over_a_cast_list_is_not_a_speaker():
    # real shape: Julius Caesar (gut-1522), a cast list opening with the title in capitals and no
    # CHARACTERS heading; Macbeth-style eponymous parts that really speak stay roles
    body = "\n\n".join(f"BRUTUS. A line of the scene, said plainly and at some length, {i}, {FILLER[:60]}.\n\n"
                       f"CAESAR. And an answer said back, {i}.\n\nJULIUS CAESAR. I speak too, {i}." for i in range(20))
    head = ("*** START OF THE PROJECT GUTENBERG EBOOK JULIUS CAESAR ***\n\nTitle: Julius Caesar\n\n"
            "JULIUS CAESAR\nOCTAVIUS CAESAR, Triumvir after his death.\nMARCUS BRUTUS, Conspirator.\n\nACT I.\n\n")
    r = P.parse("Title: Julius Caesar\n" + head + body + "\n\nTHE END\n\n*** END OF THE PROJECT GUTENBERG EBOOK X ***\n", "stage")
    jc = [x for x in r["roles"] if x["name"] == "JULIUS CAESAR"]
    assert jc and jc[0]["lines"] >= 20, r["roles"]
    r = P.parse("Title: Julius Caesar\n" + head + body.replace("JULIUS CAESAR. I speak too", "BRUTUS. I speak too")
                + "\n\nTHE END\n\n*** END OF THE PROJECT GUTENBERG EBOOK X ***\n", "stage")
    assert "JULIUS CAESAR" not in {x["name"] for x in r["roles"]}, r["roles"]


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
    """Shape only, over every cached text: a castable role (5+ lines) with all its lines
    before the play's first cast list or act/scene heading makes the parse unclean (the
    full 1,721-text cache has 78 such texts, 2026-11-14)."""
    import glob
    files = sorted(glob.glob(os.path.join(GUTENBERG_TEXTS, "*.txt")))
    if not files:
        print("SKIP cached_texts_no_castable_role_lives_only_before_the_play: no cache")
        return
    bad = []
    for f in files:
        raw = open(f, encoding="utf-8", errors="replace").read()
        items, _ = P._stage_items(P.gutenberg_body(raw))
        P._one_speaker_one_role(items)  # as parse() does: "SL" beside "SLEN" (gut-1116) is Slender
        if P.roles_only_before_play(items) and P.parse(raw, "stage").get("clean"):
            bad.append(os.path.basename(f))
    assert not bad, bad


# ---- the typography defects (R2-play-typography §4, 2026-11-14); every fixture is a real shape ----

def _stage_play(paras, filler=("GRACE", "CHARTERIS", "HODSON", "ROY", "BERTHA", "JACK", "MADHAV"), n=8):
    """A play: `n` plain speeches by each filler role (so each is a known role), then `paras`."""
    plain = [f"{s}. A plain line {i} of the scene, said at some length by {s.title()}." for i in range(n) for s in filler]
    return ("*** START OF THE PROJECT GUTENBERG EBOOK X ***\n\nTHE PLAY\n\nACT I.\n\n" + "\n\n".join(plain + list(paras))
            + "\n\nTHE END\n\n*** END OF THE PROJECT GUTENBERG EBOOK X ***\n")


def _speech(r, start):
    return next(l for l in r["lines"] if l["kind"] == "speech" and l["source"].startswith(start))


RUN_IN = [
    "CHARTERIS. Of course. Why not?",
    "GRACE (reflecting). Never mind why. Now tell me, is this your first\nlove affair?",
    "CHARTERIS (amazed at the simplicity of the question). No, bless my\nsoul. No--nor my second, nor my third.",
    "GRACE. But I mean your first serious one.",
    "HODSON [hesitant]. Is it a dangerous part you're going to, sir?",
    "ROY (_rising_). Hallo! Little Pitcher’s ears are wide open.",
    "BERTHA.--What time is it now?",
    "COL. Tell your master, Mr. Newcomb, that I will see him this evening.",
    "JACK.[Sullenly.]  No.",
    "MADHAV Poor child, it is very hard to keep him indoors all day.",
    "SEELCHEN sits gazing through the window at the peaks.",
    "GRACE. The end of it.",
]


@case
def a_speaker_with_a_direction_before_the_period_opens_a_speech():
    # real shapes: Shaw (gut-5071 "GRACE (reflecting). Never"), gut-3612 "HODSON [hesitant].", gut-48538
    # "ROY (_rising_).", gut-8500-1 "BERTHA.--What", gut-49295 "COL. Tell", gut-2906 "JACK.[Sullenly.]",
    # gut-6523 "MADHAV Poor child"; each was folded into the speech before it
    r = P.parse(_stage_play(RUN_IN).replace("MADHAV. A plain line 0", "COL. A plain line 0"), "stage")
    assert r["status"] == "parsed", r
    got = [(l["role"], l["parts"][0]) for l in r["lines"][-11:]]
    want = [("CHARTERIS", {"say": "Of course. Why not?"}),
            ("GRACE", {"direction": "reflecting"}),
            ("CHARTERIS", {"direction": "amazed at the simplicity of the question"}),
            ("GRACE", {"say": "But I mean your first serious one."}),
            ("HODSON", {"direction": "hesitant"}),
            ("ROY", {"direction": "rising"}),
            ("BERTHA", {"say": "What time is it now?"}),
            ("COL", {"say": "Tell your master, Mr. Newcomb, that I will see him this evening."}),
            ("JACK", {"direction": "Sullenly."}),
            ("MADHAV", {"say": "Poor child, it is very hard to keep him indoors all day.\n"
                                "SEELCHEN sits gazing through the window at the peaks."}),
            ("GRACE", {"say": "The end of it."})]
    assert got == want, got
    grace = _speech(r, "GRACE (reflecting)")
    assert grace["parts"][1] == {"say": "Never mind why. Now tell me, is this your first love affair?"}, grace["parts"]
    madhav = _speech(r, "MADHAV Poor")
    assert "SEELCHEN" in madhav["source"], "a capitals name before a lowercase verb is not a speaker"
    assert "SEELCHEN" not in {x["name"] for x in r["roles"]}


@case
def a_speech_split_out_keeps_the_ids_of_the_lines_around_it():
    # marks and takes anchor to line ids: a speech the parser used to fold into the one before it takes that
    # line's id plus a letter, so every line it found before keeps its id
    r = P.parse(_stage_play(RUN_IN).replace("MADHAV. A plain line 0", "COL. A plain line 0"), "stage")
    ids = [l["id"] for l in r["lines"]][-11:]
    k = int(ids[0][1:])
    assert ids == [f"L{k:04d}", f"L{k:04d}a", f"L{k:04d}b", f"L{k + 1:04d}"] + [f"L{k + 1:04d}{c}" for c in "abcdef"] \
        + [f"L{k + 2:04d}"], ids


@case
def a_paragraph_of_names_and_italic_business_is_a_direction():
    # real shape: gut-44233-3 "LINDGREN _appears in the doorway_." and "AXEL _is startled ... of_ LINDGREN.",
    # folded into the speech above as said words
    r = P.parse(_stage_play(["ROY. Well, Axel, we'll see you later then.", "GRACE _appears in the doorway_.",
                             "JACK _is startled for a moment at the sight of_ GRACE.", "GRACE. Hello."]), "stage")
    tail = [(l["id"][-1].isalpha(), l["kind"], l["source"][:10]) for l in r["lines"][-4:]]
    assert tail == [(False, "speech", "ROY. Well,"), (True, "direction", "GRACE _app"), (True, "direction", "JACK _is s"),
                    (False, "speech", "GRACE. Hel")], tail


@case
def an_italic_word_inside_a_sentence_is_said_with_emphasis():
    # real shapes: gut-5071 L0010 "in which _I_ have been", gut-844 L0013 "I believe it _is_ a very", gut-5071 L0020
    r = P.parse(_stage_play([
        "CHARTERIS (with a certain hesitation). Yes. (There is a pause. She is\nnot convinced.) It is the first in which _I_ have been serious.",
        "GRACE. I believe it _is_ a very pleasant state.",
        "JACK. Oh, yes: _I_ broke it off, you know.",
        "ROY. Come here, Bess. _Aside._ She is a fool.",
        "BERTHA. I will go _aside_ now and think.",
        "MADHAV. I tell you _he_ said so, and _he turns_ away.",
    ]), "stage")
    ch = _speech(r, "CHARTERIS (with a certain")
    assert ch["parts"] == [{"direction": "with a certain hesitation"}, {"say": "Yes."},
                           {"direction": "There is a pause. She is not convinced."}, {"say": "It is the first in which"},
                           {"say": "I"}, {"say": "have been serious."}], ch["parts"]
    assert ch["em"] == [4], ch.get("em")
    g = _speech(r, "GRACE. I believe")
    assert g["parts"] == [{"say": "I believe it"}, {"say": "is"}, {"say": "a very pleasant state."}] and g["em"] == [1], g
    assert _speech(r, "JACK. Oh, yes")["em"] == [1]
    roy, bertha = _speech(r, "ROY. Come here"), _speech(r, "BERTHA. I will go")
    assert {"direction": "Aside."} in roy["parts"] and "em" not in roy, roy
    assert {"direction": "aside"} in bertha["parts"] and "em" not in bertha, bertha
    madhav = _speech(r, "MADHAV. I tell you")
    assert madhav["em"] == [1] and {"direction": "he turns"} in madhav["parts"], madhav


@case
def a_stage_play_has_no_mic_positions_and_a_spoken_parenthesis_is_said():
    # real shapes: "which he (in breefe) obeyes" (gut-1122), Macbeth's Captain (gut-1533 L0019), a stage
    # "(In a low voice)" read as a mic cue (gut-44233-4)
    r = P.parse(_stage_play([
        "CHARTERIS. On Fortinbras, which he (in breefe) obeyes, and so it ends.",
        "GRACE. Come. (In a low voice) Here.",
        "SOLDIER.\nDoubtful it stood;\nAs two spent swimmers that do cling together\nAnd choke their art. The merciless Macdonwald\n"
        "(Worthy to be a rebel, for to that\nThe multiplying villainies of nature\nDo swarm upon him) from the Western Isles\n"
        "Of kerns and gallowglasses is supplied;",
        "ROY. I tell you (rising) that it is so.",
        "JACK. I tell you (to him) that it is so.",
        "BERTHA. Don't forget us, and (_mock courtesy_) send us a box.",
    ]), "stage")
    assert not [p for l in r["lines"] for p in l.get("parts") or [] if "mic" in p], "a mic cue in a stage play"
    ch = _speech(r, "CHARTERIS. On Fortinbras")
    assert all("say" in p for p in ch["parts"]) and "in breefe" in " ".join(p["say"] for p in ch["parts"]), ch["parts"]
    assert {"direction": "In a low voice"} in _speech(r, "GRACE. Come.")["parts"]
    sol = _speech(r, "SOLDIER.")
    assert all("say" in p for p in sol["parts"]) and "Worthy to be a rebel" in " ".join(p["say"] for p in sol["parts"]), sol
    assert {"direction": "rising"} in _speech(r, "ROY. I tell you")["parts"]
    assert {"direction": "to him"} in _speech(r, "JACK. I tell you")["parts"]
    assert {"direction": "mock courtesy"} in _speech(r, "BERTHA. Don't forget")["parts"], "an italic parenthesis is business"


@case
def a_radio_sound_cue_in_parentheses_is_a_sound():
    # real shape: gut-28051 L0006 "(sound of gavel)", a direction beside the same cue in brackets as a sound
    raw = RADIO.replace("FIBBER: Doc! Come in, come in.", "FIBBER: (sound of gavel) Doc! Come in, come in. (going to the door)")
    r = P.parse(raw, "radio")
    fib = next(l for l in r["lines"] if l["role"] == "FIBBER" and "Doc!" in l["source"])
    assert fib["parts"][0] == {"sound": "sound of gavel"}, fib["parts"]
    assert fib["parts"][-1] == {"direction": "going to the door"}, fib["parts"]
    assert next(l for l in r["lines"] if l["role"] == "DOC")["parts"][0] == {"mic": "OFF"}


@case
def a_direction_keeps_its_italic_marks_balanced():
    # real shape: gut-49295 "(_Exeunt_, R., POLLY _and_ BIJAH.)" stored as "Exeunt_, R., ..."
    r = P.parse(_stage_play(["ROY. Come with me. (_Exeunt_, R., POLLY _and_ BIJAH.)", "JACK (_rising_). Go."]), "stage")
    assert _speech(r, "ROY. Come with")["parts"][-1] == {"direction": "_Exeunt_, R., POLLY _and_ BIJAH."}
    assert _speech(r, "JACK (_rising_)")["parts"][0] == {"direction": "rising"}


@case
def a_gutenberg_illustration_marker_is_never_a_line_and_takes_no_ids_from_the_lines_after():
    # real shape: gut-20989-5 opened with a direction line "[Illustration]", which the reader showed as
    # "Illustration"; it marks where the book printed a picture, and is not a word of the play
    marks = ["[Illustration]", "_[Illustration: THE KING ENTERS]_", "ROY. Come with me. [Illustration] Now.",
             "JACK (_rising_). Go.", "[ILLUSTRATION: A ROOM.]\n\n[Illustration]", "GRACE. The end.",
             "[Illustration: THE POWER OF DARKNESS. ACT I.", "GRACE. Again.", "[illustration omitted]", "ROY. Last."]
    stand_in = [m.replace("[Illustration]", "[He sits.]").replace("[Illustration: THE KING ENTERS]", "[Exit.]")
                .replace("[ILLUSTRATION: A ROOM.]", "[A room.]").replace("[Illustration: THE POWER OF DARKNESS. ACT I.", "[A curtain.").replace("[illustration omitted]", "[Dark.]")
                for m in marks]
    r, before = P.parse(_stage_play(marks), "stage"), P.parse(_stage_play(stand_in), "stage")
    for l in r["lines"]:
        assert "llustration" not in l["source"].lower() or l["kind"] == "speech", l
        for p in l.get("parts") or []:
            assert "llustration" not in next(iter(p.values())).lower(), l
    assert _speech(r, "ROY. Come with")["parts"] == [{"say": "Come with me."}, {"say": "Now."}], \
        _speech(r, "ROY. Come with")["parts"]
    kept = {l["source"]: l["id"] for l in r["lines"]}
    for l in before["lines"]:
        if l["source"] in kept:
            assert kept[l["source"]] == l["id"], (l["source"], kept[l["source"]], l["id"])
    assert len(before["lines"]) - len(r["lines"]) == 6, (len(before["lines"]), len(r["lines"]))


@case
def a_heading_with_more_on_its_line_is_a_direction_not_a_speaker():
    # real shapes: gut-35242 "FOURTH SCENE. A haymow. ...", gut-35342 "TABLEAU II. A Saloon ...", gut-63198 "TABLEAU."
    r = P.parse(_stage_play(["FOURTH SCENE. A haymow. Melchior lies on his back in the fresh hay.", "GRACE. Hello.",
                             "TABLEAU II. A Saloon with bay windows opening on a Terrace.", "ROY. Hello.",
                             "TABLEAU. Eugene in chair. Lizzie bending over him, R.", "JACK. Hello."]), "stage")
    names = {x["name"] for x in r["roles"]}
    assert not names & {"FOURTH SCENE", "TABLEAU II", "TABLEAU"}, names
    kinds = {l["source"][:12]: l["kind"] for l in r["lines"]}
    assert kinds["FOURTH SCENE"] == kinds["TABLEAU II. "] == kinds["TABLEAU. Eug"] == "direction", kinds


@case
def abbreviated_labels_of_one_speaker_are_one_role():
    # real shape: gut-2265 (Folio Hamlet) "Bar."/"Barn." for Barnardo, "Hor."/"Hora." for Horatio
    r = P.parse(FOLIO_NOTE, "stage")
    names = {x["name"] for x in r["roles"]}
    assert len(names & {"BAR", "BARN"}) == 1 and "FRAN" in names, names
    # two speakers whose names share a start, each printed as a name, stay two
    two = _stage_play(["Enter JOHN and JOHNSON."] + [f"JOHN. I am John, {i}.\n\nJOHNSON. I am Johnson, {i}." for i in range(6)])
    names = {x["name"] for x in P.parse(two, "stage")["roles"]}
    assert {"JOHN", "JOHNSON"} <= names, names


@case
def a_one_letter_misprint_of_a_speaker_is_that_speaker():
    # real shape: gut-5071 "GRAVEN. Don't rub it in, Julia" once, beside CRAVEN's 68 speeches
    raw = _stage_play(["GRAVEN. Don't rub it in, Julia: it's not kind."], filler=("CRAVEN", "JULIA", "JOHN"), n=16)
    r = P.parse(raw.replace("ACT I.", "CHARACTERS\n\nCRAVEN\nJULIA\nJOHN\nJOAN\n\nACT I.").replace(
        "THE END", "JOAN. I am Joan.\n\nTHE END"), "stage")
    names = {x["name"]: x["lines"] for x in r["roles"]}
    assert "GRAVEN" not in names and names["CRAVEN"] == 17, names
    assert names.get("JOAN") == 1, "a one-off speaker the cast list names stays"


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
