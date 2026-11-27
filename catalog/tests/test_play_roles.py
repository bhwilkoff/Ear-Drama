"""play_roles: what was read as a speaker and is not one (catalog DECISIONS 044, BACKLOG-LOOP B16c).

    python3 tests/test_play_roles.py

Every case reads a fixture twice: as the readers had it, where the fault must show (the fixture fails without the rule),
and refined, where it must not. Line ids never move in any of them (`reads` checks it every time).
Mutation controls, 2026-11-24: each rule's step removed from play_roles.refine fails its cases (tests/mutate_play_roles.py).
"""
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import build_castable_scripts as B
import play_roles as PR
import script_parse as P

CASES = []


def case(fn):
    CASES.append(fn)
    return fn


def play(middle, top="", end="", a="SHERIFF", b="HALE", sep=". ", n=30, title="The Fixture"):
    """A play of two speakers with `middle` between two runs of their talk."""
    talk = lambda k: "\n\n".join(f"{who}{sep}I tell you plainly, line {k + i} is said by me, and you know it well." for i in range(n) for who in (a, b))
    return f"Title: {title}\n\n*** START OF THE PROJECT GUTENBERG EBOOK X ***\n\n{top}ACT I\n\n{talk(0)}\n\n{middle}\n\n{talk(100)}\n\n{end}"


def reads(raw, title="The Fixture"):
    """(lines as read, lines refined), with every id checked."""
    was, now = P.parse(raw, "stage", title), P.parse(raw, "stage", title, refine=True)
    assert was.get("status") == "parsed", was
    a, b = [l["id"] for l in was["lines"]], [l["id"] for l in now["lines"]]
    assert len(set(b)) == len(b), "an id twice"
    assert [i for i in a if i in set(b)] == [i for i in b if i in set(a)], "an id moved"
    return was["lines"], now["lines"]


def said(line):
    return " ".join(p["say"] for p in line["parts"] if "say" in p) if line["kind"] == "speech" else ""


def roles(lines):
    return {l["role"] for l in lines if l["kind"] == "speech"}


def find(lines, words):
    return next((l for l in lines if words in (said(l) or l.get("source", ""))), None)


def role_gone(name, raw, words, kind="direction", title="The Fixture"):
    """`name` was a speaker and is not; the words it stood over are kept on a line of `kind` (None: set aside)."""
    was, now = reads(raw, title)
    assert name in roles(was), (name, sorted(roles(was)))
    assert name not in roles(now), name
    line = find(now, words)
    assert (line is None) if kind is None else (line and line["kind"] == kind), (words, line)
    return was, now


@case
def a_place_over_an_entrance_is_a_direction():
    role_gone("LEPOCHE'S HOUSE", play("LEPOCHE'S HOUSE. _Enter HALE, strutting._"), "LEPOCHE'S HOUSE")
    role_gone("A STREET", play("A STREET. IT IS NIGHT."), "A STREET")
    role_gone("WARKWORTH", play("Warkworth. Before the Castle\n\n".replace("Warkworth", "WARKWORTH") + "Enter RUMOUR"), "WARKWORTH")


@case
def a_crowd_called_the_house_still_speaks():
    _, now = reads(play("THE HOUSE. Oh! Oh!"))
    assert "THE HOUSE" in roles(now)


@case
def a_numeral_over_a_setting_is_a_direction_and_a_stanza_is_not():
    role_gone("II", play("II\n[_A pavilion, with a view of the sea._]"), "A pavilion")
    was, now = reads(play("II\nI go to the land where my father is gone;\nHis ghost shall rejoice in the fame of his son:\nDeath comes like a friend to relieve me from pain,\nAnd thy son, O Alknomook, has scorned to complain."))
    assert "II" in roles(was) and find(now, "I go to the land")["kind"] == "speech", "a stanza's words stay spoken"


@case
def a_time_and_a_curtain_are_directions():
    role_gone("THE NEXT MORNING", play("THE NEXT MORNING. [_The scene is the same as in the Second Act,\nthe drawing-room at Basil's house._]"), "The scene is the same")
    role_gone("VERY SLOW CURTAIN", play("VERY SLOW CURTAIN. (_Two nights and a day--from Wednesday to Friday--\npass between the Acts._)"), "Two nights")
    role_gone("DISCOVERED", play("DISCOVERED. HALE, _on a low stone post, looking left._"), "on a low stone post")


@case
def justice_silence_is_a_part():
    _, now = reads(play("\n\n".join("SILENCE. Good morrow, good cousin Shallow, I say." for _ in range(6))))
    assert "SILENCE" in roles(now)


@case
def a_direction_that_names_who_sings_is_that_speaker():
    was, now = reads(play("HALE SINGS. O, that joy so soon should waste,\nOr so sweet a bliss as a kiss."))
    assert "HALE SINGS" in roles(was) and "HALE SINGS" not in roles(now)
    line = find(now, "O, that joy")
    assert line["role"] == "HALE" and line["parts"][0] == {"direction": "sings"}, line


@case
def an_air_named_for_its_singer_is_his():
    was, now = reads(play("AIR V.--HALE. _A master I have, and I am his man,_\n_Galloping, dreary, dun._\n\n_I saddled his steed so fine and so gay,_\n_Galloping, dreary, dun._"))
    assert "AIR V.--HALE" in roles(was)
    line = find(now, "A master I have")
    assert line["role"] == "HALE" and line["parts"][0] == {"direction": "Air V"}, line
    assert find(now, "I saddled his steed")["role"] == "HALE", "the second stanza, printed in italics"


@case
def choral_hymn_is_the_chorus():
    chorus = "\n\n".join(f"CHORUS. I say to you, strophe {i}, O king." for i in range(6))
    was, now = reads(play(chorus + "\n\nCHORAL HYMN. King of all kings, high-blest above\nEach blest celestial nature."))
    assert "CHORAL HYMN" in roles(was) and find(now, "King of all kings")["role"] == "CHORUS"


OWN = "\n\n".join(f"{w}\n\nI tell you plainly that line {i} is mine, and you know it." for i in range(30) for w in ("REUMANN", "JULIAN"))


@case
def a_sentences_first_word_goes_back_to_the_label_over_it():
    """gut-29745-1: "REUMANN / Certainly. Indeed, I have no other reason." was CERTAINLY speaking, and REUMANN's label was lost."""
    three = "\n\n".join(f"{w}\n\nCertainly. {t}" for w, t in (("REUMANN", "Indeed, I have no other reason."), ("JULIAN", "Ask her to come in."), ("JULIAN", "I have to get home.")))
    raw = "*** START OF THE PROJECT GUTENBERG EBOOK X ***\n\nACT I\n\n" + OWN + "\n\n" + three + "\n\n" + OWN
    was, now = reads(raw)
    assert "CERTAINLY" in roles(was) and "CERTAINLY" not in roles(now)
    assert find(now, "no other reason")["role"] == "REUMANN" and said(find(now, "no other reason")).startswith("Certainly. Indeed")
    assert find(now, "Ask her to come in")["role"] == "JULIAN"


@case
def a_line_of_a_speech_that_opens_on_such_a_word_is_the_speech_going_on():
    lines = [f"{w}. What is he doing to defeat them, I ask you?\nNothing. For these {k} days he has been hidden." for k, w in enumerate(("SHERIFF", "HALE", "SHERIFF"))]
    was, now = reads(play("\n\n".join(lines)))
    assert "NOTHING" in roles(was) and "NOTHING" not in roles(now)
    assert [l["role"] for l in now if "Nothing. For these" in said(l)] == ["SHERIFF", "HALE", "SHERIFF"]


@case
def a_label_that_is_an_english_word_is_the_one_name_it_shortens():
    cast = "CHARACTERS\n\nANDREW, his servant.\n\nSHERIFF.\n\nHALE.\n\n"
    was, now = reads(play("\n\n".join(f"AND. More than ten carts send over, I say {i}." for i in range(6)), top=cast))
    assert "AND" in roles(was) and "AND" not in roles(now) and "ANDREW" in roles(now)


@case
def such_a_label_with_two_names_is_left():
    cast = "CHARACTERS\n\nANDREW, his servant.\n\nANDREA, his friend.\n\nSHERIFF.\n\nHALE.\n\n"
    _, now = reads(play("\n\n".join(f"AND. More than ten carts send over, I say {i}." for i in range(6)), top=cast))
    assert "AND" in roles(now)


@case
def a_label_cut_at_a_title_takes_the_name_after_it():
    mrs = "\n\n".join(f"MRS. BANGER. I say it again, {i}, General." for i in range(6))
    was, now = reads(play(mrs + "\n\nLADY CORINTHIA AND MRS. BANGER (rising). Thank you."))
    line = find(now, "Thank you.")
    assert line["role"] == "LADY CORINTHIA AND MRS. BANGER", line


@case
def a_speech_that_is_one_word_on_its_label_is_a_line_of_its_own():
    was, now = reads(play("SHERIFF. I--\n\nHALE (cutting him short). No, you've done it now."))
    assert any(r.startswith("SHERIFF. I--") for r in roles(was)), sorted(roles(was))
    k = next(i for i, l in enumerate(now) if "you've done it now" in said(l))
    assert now[k]["role"] == "HALE" and now[k - 1]["role"] == "SHERIFF" and said(now[k - 1]).strip("-") == "I"


@case
def a_label_ended_after_a_stop_is_two_speakers():
    """gut-6731: DON. LOUISA and DON. CLARA were one part, DON, who spoke "Louisa." """
    talk = "\n\n".join(f"_Don. {w}_. I shall never forgive you for it, {i}, never in this world." for i in range(14) for w in ("Louisa", "Clara"))
    raw = "*** START OF THE PROJECT GUTENBERG EBOOK X ***\n\nACT I\n\n" + talk + "\n\n" + "\n\n".join(f"_Isaac_. I say so too, {i}, my dear, and I say it again." for i in range(20)) + "\n\n" + talk
    was, now = reads(raw)
    assert "DON" in roles(was), sorted(roles(was))
    assert {"DON. LOUISA", "DON. CLARA"} <= roles(now) and "DON" not in roles(now), sorted(roles(now))
    assert not any(said(l).startswith(("Louisa", "Clara")) for l in now)


@case
def a_misprint_is_the_part_it_misprints():
    was, now = reads(play("SHREIFF. I tell you the same.\n\nHALE. Who said so?"))
    assert "SHREIFF" in roles(was) and "SHREIFF" not in roles(now)


@case
def a_title_of_another_sex_is_not_a_misprint():
    mrs = "\n\n".join(f"MRS. LOVEDAY. I say it again, {i}, sir." for i in range(6))
    _, now = reads(play(mrs + "\n\nMR. LOVEDAY. I say it too, madam."))
    assert "MR. LOVEDAY" in roles(now)


ITALIC = "\n\n".join(f"_{w}._ I tell you plainly, line {i} is mine, and you know it." for i in range(20) for w in ("Hale", "Sheriff"))


@case
def a_minor_part_printed_like_the_others_is_not_a_direction():
    raw = "*** START OF THE PROJECT GUTENBERG EBOOK X ***\n\nACT I\n\n" + ITALIC + "\n\n_2 Merch._ Sir, we saw 'em not.\n\n_Hale_ (_rising_). Nora! Nora!\n\n" + ITALIC
    was, now = reads(raw)
    assert find(was, "we saw 'em not")["kind"] == "direction", "the fault"
    assert find(now, "we saw 'em not")["role"] == "2 MERCH"
    line = find(now, "Nora! Nora!")
    assert line["role"] == "HALE" and line["parts"][0] == {"direction": "rising"}, line


@case
def business_printed_in_italics_stays_a_direction():
    raw = "*** START OF THE PROJECT GUTENBERG EBOOK X ***\n\nACT I\n\n" + ITALIC + "\n\n_There is a pause._ PETER _stops short._\n\n_Cornets._ _Enter_ GONZAGO.\n\n" + ITALIC
    _, now = reads(raw)
    assert find(now, "stops short")["kind"] == "direction" and find(now, "GONZAGO")["kind"] == "direction"


@case
def numbered_speakers_folded_into_a_speech_are_lines_of_their_own():
    was, now = reads(play("HALE. Has there been such resort, say you?\n\n1 NEI. Daily, sir.\n\n2 NEI. And nightly, too."))
    assert "1 NEI" not in roles(was) and "Daily" in said(find(was, "such resort"))
    assert said(find(now, "such resort")) == "Has there been such resort, say you?"
    assert find(now, "Daily, sir.")["role"] == "1 NEI" and find(now, "And nightly")["role"] == "2 NEI"
    base = find(now, "such resort")["id"]
    assert [find(now, "Daily, sir.")["id"], find(now, "And nightly")["id"]] == [base + "a", base + "b"]


@case
def one_numbered_part_under_two_abbreviations_is_one_role():
    was, now = reads(play("HALE. Who is there?\n\n1 GEN. My coach, an't please you.\n\n1 GENT. The honour, madam."))
    assert find(now, "My coach")["role"] == find(now, "The honour")["role"] == "1 GENT"


@case
def a_new_line_never_takes_a_letter_already_published():
    """The run-in fix (2026-11-14) gave this speech `a`; the speech found before it now takes `b`."""
    was, now = reads(play("HALE. Has there been such resort?\n\n1 NEI. Daily, sir.\n\nSHERIFF (reflecting). Never, I say."))
    base = find(was, "such resort")["id"]
    assert find(was, "Never, I say")["id"] == base + "a", find(was, "Never, I say")
    assert find(now, "Never, I say")["id"] == base + "a" and find(now, "Daily, sir.")["id"] == base + "b"


@case
def a_mixed_case_label_with_its_direction_is_not_folded():
    talk = "\n\n".join(f"{w}. I tell you plainly, line {i} is mine, and you know it." for i in range(20) for w in ("Hovstad", "Mrs. Stockmann"))
    raw = "*** START OF THE PROJECT GUTENBERG EBOOK X ***\n\nACT I\n\n" + talk + "\n\nHovstad. Good evening to you.\n\nMrs. Stockmann (coming forward). Ah, good evening, is it you?\n\n" + talk
    was, now = reads(raw)
    assert "is it you" in said(find(was, "Good evening to you")), "the fault"
    line = find(now, "is it you")
    assert line["role"] == "MRS. STOCKMANN" and line["parts"][0] == {"direction": "coming forward"} and line["id"].endswith("a")


@case
def a_label_in_capitals_inside_a_speech_is_the_next_speaker():
    """gut-14322 L0330: ORESTES spoke ELECTRA's half of the verse and her name."""
    was, now = reads(play("HALE. No more to see thee! SHERIFF. Nor thy breath be near my face! HALE. Ah, so it ends.\n\nSHERIFF. Good day, my dear Mr. HALE. I am going."))
    assert "SHERIFF. Nor thy" in said(find(was, "No more to see")), "the fault"
    assert said(find(now, "No more to see")) == "No more to see thee!"
    assert find(now, "Nor thy breath")["role"] == "SHERIFF" and find(now, "Ah, so it ends")["role"] == "HALE"
    assert find(now, "I am going")["role"] == "SHERIFF", "a name after Mr. is not a label"


@case
def a_label_of_a_part_who_speaks_seldom_is_still_the_next_speaker():
    """gut-1775 L0061: GURNEY speaks twice in King John, so his label inside the Bastard's speech was not read."""
    was, now = reads(play("GURNEY. I thank you, my lord.\n\nSHERIFF. James Gurney, wilt thou give us leave awhile? GURNEY. Good leave, good Philip.\n\nHALE. Be it so."))
    assert "GURNEY. Good leave" in said(find(was, "wilt thou give us leave")), "the fault"
    assert said(find(now, "wilt thou give us leave")) == "James Gurney, wilt thou give us leave awhile?"
    assert find(now, "Good leave, good Philip")["role"] == "GURNEY"


@case
def a_capital_name_nobody_speaks_as_is_not_a_label():
    was, now = reads(play("SHERIFF. Tell the king. KIMBERLEY. Is a place I know well.\n\nHALE. Be it so."))
    assert "KIMBERLEY" not in roles(now) and "KIMBERLEY. Is a place" in said(find(now, "Tell the king"))


@case
def a_verse_line_two_speakers_share_is_two_speeches():
    shared = "\n\n".join(f"_Bor._ To serve your vast expenses {i}. _Are._ Am I then\nBrought in the balance?" for i in range(6))
    talk = "\n\n".join(f"_{w}._ I tell you plainly, line {i} is mine, and you know it." for i in range(15) for w in ("Are", "Bor"))
    was, now = reads("*** START OF THE PROJECT GUTENBERG EBOOK X ***\n\nACT I\n\n" + talk + "\n\n" + shared + "\n\n" + talk)
    assert not any(l.get("role") == "ARE" and "Am I then" in said(l) for l in was)
    assert sum(l.get("role") == "ARE" and said(l).startswith("Am I then") for l in now) == 6


@case
def a_publishers_list_after_the_play_is_not_spoken():
    ads = "\n\n".join(f"{t}. By W. D. Howells. 12mo, Cloth, $1 00." for t in ("CRITICISM AND FICTION", "MODERN ITALIAN POETS", "ANNIE KILBURN"))
    was, now = reads(play("HALE. I have done.", end="PRICE 25 CENTS. A DAY AND A NIGHT. A comedy in 2 acts, by A. Ruggeri.\n\n" + ads))
    if "PRICE 25 CENTS" in roles(was) or "ANNIE KILBURN" in roles(was):
        assert not roles(now) & {"PRICE 25 CENTS", "CRITICISM AND FICTION", "MODERN ITALIAN POETS", "ANNIE KILBURN"}, sorted(roles(now))
    else:
        raise AssertionError("the fixture no longer shows the fault")


@case
def notes_after_the_play_are_not_spoken():
    notes = "\n\n".join(f"P. {i}, l. {10 + i}, Beguiling.]--The editor says so." for i in range(3, 10))
    was, now = reads(play("HALE. I have done.", end=notes))
    assert "P" in roles(was) and "P" not in roles(now)


@case
def a_heading_of_notes_ends_the_play():
    was, now = reads(play("HALE. I have done.", end="[NOTES:]\n\n[a] [From the first part]\n\nSHERIFF. The Fixture. Who, from a shepherd by his rare and wonderful conquests."))
    if not find(was, "rare and wonderful"):
        raise AssertionError("the fixture no longer shows the fault")
    assert not find(now, "rare and wonderful") and find(now, "I have done.")


@case
def a_footnote_printed_as_a_direction_is_set_aside():
    was, now = reads(play("[Footnote 3: censures: i.e. judgments.]"))
    assert find(was, "judgments") and not find(now, "judgments")


@case
def a_bracketed_number_of_business_is_not_a_note():
    _, now = reads(play("[1] _He goes out._"))
    assert find(now, "He goes out")


@case
def the_license_inside_an_old_etext_is_not_spoken():
    role_gone("WITH PERMISSION", play("WITH PERMISSION. ELECTRONIC AND MACHINE READABLE COPIES MAY BE DISTRIBUTED SO LONG AS SUCH COPIES ARE FOR YOUR PERSONAL USE."), "MACHINE READABLE", None)


@case
def a_cast_list_read_as_the_first_speeches_is_set_aside():
    top = "SHERIFF. Long white hair and beard, gray shirt, dark pants, boots and belt.\n\nHALE. Iron-gray wig and beard, gray shirt, overalls and boots.\n\n"
    raw = "*** START OF THE PROJECT GUTENBERG EBOOK X ***\n\n" + top + play("HALE. I have done.").split("***\n\n", 1)[1].replace("ACT I\n\n", "")
    was, now = reads(raw)
    assert find(was, "Long white hair"), "the fault"
    assert not find(now, "Long white hair") and not find(now, "Iron-gray wig")


@case
def a_play_whose_lines_look_like_a_cast_list_is_not_emptied():
    raw = play("HALE. and so it goes on.").replace("I tell you plainly, line", "the friend of line").replace("is said by me, and you know it well", "is here")
    _, now = reads(raw)
    assert len(now) > 50


@case
def a_prologue_spoken_by_an_actor_is_the_prologue():
    raw = play("HALE. I have done.", top="PROLOGUE.\n\nSPOKEN BY MR. MARTIN\n\nA native Bard, a native scene displays,\nAnd claims your candour for his daring lays, my friends.\n\nSHERIFF. I am here.\n\nHALE. So am I.\n\n")
    was, now = reads(raw)
    assert "SPOKEN BY MR. MARTIN" in roles(was), sorted(roles(was))
    assert find(now, "A native Bard")["role"] == "PROLOGUE"


@case
def a_song_the_print_sets_in_italics_is_sung():
    """gut-2421: the words of every air in The Beggar's Opera were read as directions."""
    was, now = reads(play("HALE. _I, like a ship in storms, was tost;_\n_Yet afraid to put in to land:_\n_For seized in the port the vessel's lost,_\n_Whose treasure is contraband._"))
    assert not said(find(was, "I, like a ship")), "the fault"
    assert "Whose treasure is contraband." in said(find(now, "I, like a ship"))


@case
def what_another_person_is_like_is_a_direction():
    """gut-25565: THOMAS, a servant with forty lines, "said" the stage's picture of MISS HENEAGE."""
    words = "MISS HENEAGE _is a solidly built, narrow-minded woman in her sixties. She makes no effort to look younger._"
    was, now = reads(play("HALE. " + words))
    assert find(was, "MISS HENEAGE")["kind"] == "speech", "the fault"
    assert find(now, "MISS HENEAGE")["kind"] == "direction"


@case
def a_mute_action_in_italics_stays_a_direction():
    _, now = reads(play("HALE. _crosses to the window, and looks out on the street._"))
    assert not said(find(now, "crosses to the window"))


@case
def what_a_part_wears_is_the_cast_list():
    raw = play("HALE. I have done.", top="FEAR. Wearing black cloak, carries banner with the word Fear printed on it.\n\nRAIN. Raincoat and cap, may carry umbrella.\n\nScene. A garden.\n\n")
    was, now = reads(raw)
    assert "FEAR" in roles(was) and "FEAR" not in roles(now)


@case
def a_part_printed_with_an_article_and_without_is_one_part():
    """gut-3012: The Acharnians listed "A MEGARIAN" and "MEGARIAN", "AN INFORMER" and "INFORMER", so it claimed 34 voices."""
    middle = ("A MEGARIAN. Greeting, market of Athens, beloved of Megarians.\n\nMEGARIAN. Come up, my little daughters, find some bread.\n\n"
              "AN INFORMER. Who are you, and whence come you, my man?\n\nINFORMER. I denounce this sack and all it holds.\n\n"
              "FIRST WOMAN. I tell you the gate is shut against us.\n\nSECOND WOMAN. Then we must wait here until the morning.\n\n"
              "AN OLD SLAVE. I carried the lamp the whole way here.\n\nSLAVE. And I carried the bread, which is heavier.\n\n"
              "MEGARIAN. Here are my pigs, as fine as any.\n\nINFORMER. And here is my denunciation, as fine as any.")
    was, now = reads(play(middle))
    assert {"A MEGARIAN", "AN INFORMER"} <= roles(was), sorted(roles(was))
    assert not {"A MEGARIAN", "AN INFORMER"} & roles(now), sorted(roles(now))
    assert find(now, "Greeting, market of Athens")["role"] == "MEGARIAN" and find(now, "Who are you, and whence")["role"] == "INFORMER"
    assert {"FIRST WOMAN", "SECOND WOMAN", "AN OLD SLAVE", "SLAVE"} <= roles(now), "control: different parts stay apart"
    parsed = P.parse(play(middle), "stage", "The Fixture", refine=True)
    assert [r["name"] for r in parsed["roles"]].count("MEGARIAN") == 1 and not any(r["name"] == "A MEGARIAN" for r in parsed["roles"])
    assert next(r for r in parsed["roles"] if r["name"] == "MEGARIAN")["lines"] == 3, "the part has all its lines"


@case
def a_play_with_no_fault_is_the_same_entry():
    raw = play("HALE. I have done.")
    record = {"id": "gut-1", "kind": "stage", "title": "The Fixture", "authors": [], "source": {"name": "Project Gutenberg", "url": "https://example.org/1"}}
    entry = B.script_entry(record, {"bucket": "x", "evidence": []}, P.parse(raw, "stage", "The Fixture"))
    assert B.refined_entry(entry, P.parse(raw, "stage", "The Fixture", refine=True)) is entry


@case
def a_reading_that_moves_an_id_is_refused():
    raw = play("HALE. I have done.")
    record = {"id": "gut-1", "kind": "stage", "title": "The Fixture", "authors": [], "source": {"name": "Project Gutenberg", "url": "https://example.org/1"}}
    entry = B.script_entry(record, {"bucket": "x", "evidence": []}, P.parse(raw, "stage", "The Fixture"))
    moved = P.parse(raw, "stage", "The Fixture", refine=True)
    moved["lines"][3]["id"], moved["lines"][4]["id"] = moved["lines"][4]["id"], moved["lines"][3]["id"]
    try:
        B.refined_entry(entry, moved)
    except ValueError:
        return
    raise AssertionError("a moved id was accepted")


@case
def the_second_reader_is_mended_too():
    import play_layouts as PL
    raw = ("*** START OF THE PROJECT GUTENBERG EBOOK X ***\n\nACT I\n\n" + "\n\n".join(f"_{w}_. I tell you plainly, line {i} is mine, and you know it." for i in range(40) for w in ("Archidamus", "Leosthenes"))
           + "\n\n_A Prison_. MARULLO _discovered in chains_.\n\n" + "\n\n".join(f"_{w}_. I tell you plainly again, line {i} is mine, and you know it." for i in range(40) for w in ("Archidamus", "Leosthenes")))
    was, now = PL.parse(raw, "The Bondman"), PL.parse(raw, "The Bondman", refine=True)
    assert "A PRISON" in roles(was["lines"]) and "A PRISON" not in roles(now["lines"]) and find(now["lines"], "discovered in chains")


def main():
    failed = 0
    for fn in CASES:
        try:
            fn()
        except (AssertionError, KeyError, StopIteration, TypeError) as e:
            failed += 1
            print(f"FAIL {fn.__name__}: {type(e).__name__} {str(e)[:300]}")
    print(f"{len(CASES) - failed}/{len(CASES)} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
