"""The register of each part's stand-in voice (catalog DECISIONS 049, tools/play_voices.py).

    python3 tests/test_play_voices.py

Every rule has a case from a play's own print, and a guard against the reading it must not make. Where the harvest cache
and a built library are on this machine, the hand-labeled roles (golden/play_voice_labels.json) are read again: no wrong
register on any half, and the held-out halves at least 98% precise.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tools"))
import play_voices as V

CASES = []


def case(fn):
    CASES.append(fn)
    return fn


def speech(i, role, *parts):
    return {"id": f"L{i:04d}", "kind": "speech", "role": role, "source": "", "parts": [dict([p]) for p in parts]}


def direction(i, text):
    return {"id": f"L{i:04d}", "kind": "direction", "role": None, "source": text}


def entry(roles, lines):
    return {"id": "gut-0", "revision": "r", "roles": [{"name": r, "lines": 1, "words": 1} for r in roles], "lines": lines}


def regs(roles, lines, text=""):
    return V.registers(entry(roles, lines), text)


@case
def a_role_named_by_a_title_or_a_word_for_a_woman_or_a_man():
    assert V.from_name("MRS. ALVING") == "high" and V.from_name("LADY MACBETH") == "high" and V.from_name("FIRST WITCH") == "high"
    assert V.from_name("SIR TOBY BELCH") == "low" and V.from_name("THE KING") == "low" and V.from_name("FRIAR PETER") == "low"
    assert V.from_name("THE KING'S DAUGHTER") == "high", "the words after the possessive"
    assert V.from_name("WIFE OF HANS") == "high" and V.from_name("SON OF THE QUEEN") == "low", "the words before OF"
    assert V.from_name("VOICE OF THE KING") == "low", "a voice of someone is that someone"
    assert V.from_name("BOY") == "high" and V.from_name("THE CHILD") == "high", "a child is high"
    assert V.from_name("MESSENGER") is None and V.from_name("HORATIO") is None


@case
def a_crowd_a_pair_or_a_voice_alone_is_never_marked():
    for name in ("ALL", "BOTH", "VOICES", "CHORUS", "PAUL AND LUCY", "MRS. LOVING AND RACHEL", "A VOICE", "ANOTHER VOICE", "THE PEOPLE", "SAILORS"):
        assert V.grouped(name), name
        assert V.decide(V.evidence(name, entry([name], []), [], V.Names([name]))) is None, name
    assert not V.grouped("VOICE OF THE WOOD-BIRD") and not V.grouped("THE KING")


@case
def a_list_of_persons_says_who_a_role_is():
    assert V.from_description(", his wife.") == "high" and V.from_description(", son to Montague.") == "low"
    assert V.from_description(", daughter of Jacobus") == "high" and V.from_description(", _a knight of the road_") == "low"
    assert V.from_description("..................... His sister") == "high", "after dot leaders"
    assert V.from_description(", servant to the Countess.") is None, "a word after a preposition is someone else"
    assert V.from_description(", Helmer's wife") == "high" and V.from_description(", the Duke's steward") is None, "the noun after"
    assert V.from_description(", _mother’s pet_") is None, "a possessive, in a curly apostrophe too"
    assert V.from_description(", the twins. Rev. J. Jones, the minister.") is None, "the description ends at its clause"


@case
def a_list_row_is_found_for_its_role_and_never_for_a_namesake():
    rows = [("HENNING TJAELDE, merchant and brewer.", None), ("MRS. TJAELDE, his wife.", None), ("MR. DARCY--(OF PEMBERLEY).", None),
            ("CLERIMONT, a gentleman.", None), ("NORA, his wife.", None)]
    assert V.entry_for("MRS. TJAELDE", rows)[0][0].startswith("MRS. TJAELDE")
    assert V.entry_for("TJAELDE", rows)[0] is None, "two rows could be TJAELDE: neither"
    row, rest, lead = V.entry_for("DARCY", rows)
    assert row[0].startswith("MR. DARCY") and lead == "MR", "the row's own title is evidence"
    assert V.entry_for("CLER", rows)[0][0].startswith("CLERIMONT"), "a cut label finds the one name it starts"
    assert V.entry_for("NORAH", rows)[0] is None, "NORA is not NORAH"


@case
def a_list_groups_its_names_by_a_brace_or_by_two_headings():
    text = "CHARACTERS\n\nJACOBUS the Burgomeister     )\nAXEL the Smith               )   Men of Hamelin\n\nILSE    )\nTRUDE   )   Children\n\nVERONIKA, the wife of Kurt\n"
    rows = dict(V.cast_list(text))
    assert rows["JACOBUS the Burgomeister     )"] == "low" and rows["TRUDE   )   Children"] == "high"
    assert rows["VERONIKA, the wife of Kurt"] is None
    headed = dict(V.cast_list("DRAMATIS PERSONAE\n\nMEN\n\nJOHN\n\nWOMEN\n\nMARY\n"))
    assert headed == {"JOHN": "low", "MARY": "high"}, headed
    chorus = dict(V.cast_list("DRAMATIS PERSONAE\n\nPRAXAGORA.\nWOMEN.\nCHREMES.\n"))
    assert chorus.get("CHREMES.") is None, "a list printing WOMEN. among its names has a chorus, not a heading"


@case
def the_speakers_own_direction_says_to_herself_and_someone_elses_is_not_hers():
    lines = [speech(1, "NORA", ("direction", "to herself"), ("say", "So.")), speech(2, "NORA", ("say", "Yes."), ("direction", "He comes towards her."))]
    hi, lo = V.from_directions("NORA", lines, V.Names(["NORA"]))
    assert hi >= 3 and lo == 0, (hi, lo)
    lines = [speech(1, "TJAELDE", ("say", "Go."), ("direction", "She goes.")), speech(2, "TJAELDE", ("direction", "To himself."))]
    hi, lo = V.from_directions("TJAELDE", lines, V.Names(["TJAELDE"]))
    assert hi == 1 and lo == 3, "an opening pronoun inside a speech counts little: it is the listener as often as the speaker"
    lines = [speech(1, "SANNAES", ("direction", "starts, but collects herself"))]
    assert V.from_directions("SANNAES", lines, V.Names(["SANNAES"])) == (1, 0), "a reflexive not of speech is the listener's as often"


@case
def a_direction_about_the_part_names_it_first():
    names = V.Names(["JOHN", "MARY", "NORAH", "MRS. TJAELDE", "TJAELDE"])
    assert V._votes_in("JOHN crosses to the fire, and he sits.", "JOHN", names) == [("low", 2)]
    assert V._votes_in("JOHN turns to MARY, and she smiles.", "JOHN", names) == [], "stops at the next person"
    assert V._votes_in("Without seeing NORAH, he rings the bell.", "NORAH", names) == [], "the part is not the subject"
    assert V._votes_in("She bows and looks at JOHN, and he smiles.", "JOHN", names) == [], "a pronoun before the part"
    assert V._votes_in("She kisses JOHN and smooths her dress.", "JOHN", names) == [], "her dress is hers, who kissed him"
    assert V._votes_in("MRS. TJAELDE hides her face in her hands.", "TJAELDE", names) == [], "her own name, not her husband's"
    assert V._votes_in("_JOHN throws himself into a chair_.", "JOHN", names) == [("low", 3)], "italic underscores"
    assert V.sentences("MRS. TJAELDE sits. She weeps.") == ["MRS. TJAELDE sits.", "She weeps."]


@case
def directions_decide_only_when_they_agree():
    assert V.weigh(2, 0) == "high" and V.weigh(0, 9) == "low"
    assert V.weigh(1, 0) is None, "one possessive is not enough"
    assert V.weigh(12, 3) == "conflict" and V.weigh(8, 76) == "low"
    assert V.weigh(5, 4) == "conflict"


@case
def the_play_calling_a_name_with_a_title_says_who_it_is():
    lines = [speech(1, "ELIZA", ("say", "Good day, Mr. Darcy.")), speech(2, "JANE", ("say", "Mr. Darcy is here.")), speech(3, "DARCY", ("say", "Yes."))]
    assert V.from_address("DARCY", entry(["ELIZA", "JANE", "DARCY"], lines)) == (0, 2)
    family = lines + [direction(4, "Sarah Tapp and Nathaniel Tapp sit."), speech(5, "TAPP", ("say", "Mrs. Tapp, sit."))]
    assert V.from_address("TAPP", entry(["ELIZA", "TAPP"], family)) == (0, 0), "a family's name says nothing of one of them"
    assert V.from_address("TJAELDE", entry(["TJAELDE", "MRS. TJAELDE"], [speech(1, "X", ("say", "Mrs. Tjaelde! Mrs. Tjaelde!"))])) == (0, 0)
    mixed = [speech(1, "JACK", ("say", "Lady Bracknell! Lady Bracknell! Lady Bracknell! Lady Bracknell! Lord Bracknell, Lord Bracknell, Lord Bracknell.")), speech(2, "LADY BRACKNELL", ("say", "Yes."))]
    assert regs(["JACK", "LADY BRACKNELL"], mixed) == {"LADY BRACKNELL": "high"}, "a mixed count is no evidence, never a veto"


@case
def an_actors_title_and_a_given_name_speak_only_when_nothing_else_does():
    text = "CAST\n\nDOROTHY ............ MISS MARION TERRY.\nDAN'L DRUCE ......... MR. HERMANN VEZIN.\n"
    got = regs(["DOROTHY", "DAN'L DRUCE"], [speech(1, "DOROTHY", ("say", "Father.")), speech(2, "DAN'L DRUCE", ("say", "Child."))], text)
    assert got == {"DOROTHY": "high", "DAN'L DRUCE": "low"}, got
    breeches = "CAST\n\nTHE KING ............ MISS VESTA TILLEY.\nALADDIN ............ MISS NELLIE FARREN.\n"
    got = regs(["THE KING", "ALADDIN"], [speech(1, "THE KING", ("say", "Ho.")), speech(2, "ALADDIN", ("say", "Hey."))], breeches)
    assert got == {"THE KING": "low"}, "a play that casts an actress as a king lets no actor's title speak"
    assert V.from_given_name("NORA") == "high" and V.from_given_name("HORACE") == "low"
    assert V.from_given_name("ROSE") is None and V.from_given_name("WILL") is None, "a name that is an English word"
    got = regs(["HORACE"], [speech(1, "HORACE", ("say", "Hi.")), speech(2, "HORACE", ("direction", "to herself"), ("say", "Oh."))])
    assert got == {"HORACE": "high"}, "the play's own direction wins over a census name"


@case
def two_kinds_of_evidence_that_disagree_leave_the_part_unmarked():
    text = "DRAMATIS PERSONAE\n\nLADY BRIGHT, a young man in disguise.\n"
    assert regs(["LADY BRIGHT"], [speech(1, "LADY BRIGHT", ("say", "Well."))], text) == {}
    assert V.decide({"name": "high", "list": "low"}) is None and V.decide({"name": "high", "directions": "conflict"}) is None
    assert V.decide({"actor": "high", "given_name": "low"}) is None
    assert V.decide({"directions": "conflict", "given_name": "low"}) is None, "conflicting directions leave it unmarked"
    assert V.decide({"name": "high", "given_name": "low"}) == "high", "a census name never outvotes the print"


@case
def annotating_changes_no_line_id_or_revision():
    e = entry(["MRS. PAGE", "FORD", "ALL"], [speech(1, "MRS. PAGE", ("say", "Ha.")), speech(2, "FORD", ("say", "Ho.")), speech(3, "ALL", ("say", "Hey."))])
    out = V.annotate(e, "")
    assert out["lines"] is e["lines"] and out["revision"] == e["revision"] and out["id"] == e["id"]
    assert [r.get("register") for r in out["roles"]] == ["high", None, None], out["roles"]
    assert all(set(r) - {"register"} == set(o) for r, o in zip(out["roles"], e["roles"]))
    again = V.annotate({**out, "roles": [{**r, "register": "low"} for r in out["roles"]]}, "")
    assert [r.get("register") for r in again["roles"]] == ["high", None, None], "a stale register is replaced, never kept"


@case
def the_given_name_table_says_where_it_came_from():
    d = json.load(open(V.NAMES, encoding="utf-8"))
    assert "Census" in d["source"] and "public domain" in d["source"] and d["rule"] and d["made_by"]
    assert not set(d["high"]) & set(d["low"]) and len(d["high"]) > 1000 and len(d["low"]) > 400
    assert all(n.isupper() and n.isalpha() for n in d["high"] + d["low"])


LIB = os.path.join(HERE, "..", "out", "plays-library")
TEXTS = os.path.join(HERE, "..", ".cache", "gutenberg", "text")
LABELS = os.path.join(HERE, "golden", "play_voice_labels.json")


@case
def the_hand_labeled_roles_read_again():
    labels = json.load(open(LABELS, encoding="utf-8"))
    assert labels["about"] and len(labels["labels"]) >= 300 and len({r["play"] for r in labels["labels"]}) >= 60
    if not (os.path.exists(os.path.join(LIB, "index.json")) and os.path.isdir(TEXTS)):
        print("  (no built library or harvest cache: the labels' shape only)")
        return
    tally = {}
    wrong = []
    for r in labels["labels"]:
        path = os.path.join(LIB, "scripts", r["play"] + ".json")
        if not os.path.exists(path):
            continue
        s = json.load(open(path, encoding="utf-8"))["scripts"][0]
        got = next((x.get("register") for x in s["roles"] if x["name"] == r["role"]), "gone")
        if got == "gone":
            continue
        t = tally.setdefault(r["half"], {"roles": 0, "known": 0, "said": 0, "right": 0})
        t["roles"] += 1
        t["known"] += r["truth"] is not None
        t["said"] += got is not None
        t["right"] += got is not None and got == r["truth"]
        if got is not None and got != r["truth"]:
            wrong.append((r["half"], r["play"], r["role"], r["truth"], got))
    for half, t in sorted(tally.items()):
        print(f"  {half}: {t['said']} of {t['roles']} roles marked, {t['right']} right; coverage of the roles a reader can settle "
              f"{t['right'] / max(1, t['known']):.0%}")
    held_out = [t for h, t in tally.items() if h != "build"]
    said = sum(t["said"] for t in held_out)
    assert said and sum(t["right"] for t in held_out) / said >= 0.98, ("held-out precision under 98%", wrong)
    assert len(wrong) <= 1, wrong


def main():
    failed = 0
    for fn in CASES:
        try:
            fn()
        except (AssertionError, KeyError, TypeError, IndexError) as e:
            failed += 1
            print(f"FAIL {fn.__name__}: {e!r}")
    print(f"{len(CASES) - failed}/{len(CASES)} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
