"""play_corrections: audited per-play corrections (catalog DECISIONS 046, BACKLOG-LOOP B22).

    python3 tests/test_play_corrections.py

A correction only moves the source's own words (reassign, cut, set aside), names the revision it was read against,
and quotes its evidence from the play. Mutation controls: tests/mutate_play_corrections.py removes each guard in turn.
"""
import copy
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import play_corrections as PC

CASES = []


def case(fn):
    CASES.append(fn)
    return fn


def sp(lid, role, *parts):
    return {"id": lid, "kind": "speech", "role": role, "parts": [p if isinstance(p, dict) else {"say": p} for p in parts]}


def entry(lines=None, sections=None):
    lines = lines or [
        sp("L0001", "SHERIFF", "Good day to you."),
        sp("L0002", "HALE", "Hector is slain. ALL. Hector! The gods forbid!"),
        {"id": "L0002a", "kind": "direction", "source": "Enter the crowd."},
        sp("L0003", "HALE", {"say": "Take this. [ Exit HALE."}),
        sp("L0004", "COOK", "A very distinguished woman."),
        {"id": "L0005", "kind": "direction", "source": "Gower speaks.\n\nGood Helicane, that stay'd at home."},
    ]
    e = {"id": "gut-1", "revision": PC._revision(lines), "lines": lines, "roles": PC._roles(lines)}
    if sections:
        e["sections"] = sections
    return e


def corr(e, line, op, **kw):
    return {"play": e["id"], "revision": e["revision"], "line": line, "op": op, "evidence": kw.pop("evidence", "Good day to you."),
            "why": "because", **kw}


def run(e, *cs):
    return PC.apply(e, {e["id"]: list(cs)})


def refused(e, *cs):
    try:
        run(e, *cs)
    except PC.Refused as err:
        return str(err)
    raise AssertionError("the correction was accepted")


def lines_of(out):
    return {l["id"]: l for l in out["lines"]}


@case
def an_entry_without_corrections_is_the_same_entry():
    e = entry()
    assert PC.apply(e, {}) is e and PC.apply(e, {"gut-2": [corr(e, "L0001", "drop")]}) is e


@case
def a_role_is_reassigned_and_the_roles_follow():
    e = entry()
    out = run(e, corr(e, "L0004", "role", role="SHERIFF"))
    assert lines_of(out)["L0004"]["role"] == "SHERIFF" and lines_of(out)["L0004"]["parts"] == e["lines"][4]["parts"]
    assert {r["name"]: r["lines"] for r in out["roles"]} == {"SHERIFF": 2, "HALE": 2} and out["revision"] != e["revision"]


@case
def a_speech_becomes_a_direction_with_its_words():
    e = entry()
    out = run(e, corr(e, "L0004", "direction", evidence="A very distinguished woman."))
    assert lines_of(out)["L0004"] == {"id": "L0004", "kind": "direction", "source": "A very distinguished woman."}
    assert "COOK" not in {r["name"] for r in out["roles"]}


@case
def a_direction_becomes_a_speech_with_its_words():
    e = entry()
    out = run(e, corr(e, "L0005", "speech", role="GOWER", evidence="Good Helicane, that stay'd at home."))
    assert lines_of(out)["L0005"]["parts"] == [{"say": "Gower speaks.\n\nGood Helicane, that stay'd at home."}] and lines_of(out)["L0005"]["role"] == "GOWER"


@case
def a_line_set_aside_keeps_its_id_used():
    e = entry()
    out = run(e, corr(e, "L0004", "drop", evidence="A very distinguished woman."))
    assert "L0004" not in lines_of(out) and [l["id"] for l in out["lines"]] == ["L0001", "L0002", "L0002a", "L0003", "L0005"]


@case
def a_split_cuts_a_label_and_gives_the_new_line_the_next_free_letter():
    e = entry()
    out = run(e, corr(e, "L0002", "split", evidence="Hector is slain. ALL. Hector!",
                      pieces=[{"as": "speech", "role": "HALE"}, {"as": "speech", "role": "ALL", "from": "ALL. Hector", "cut": "ALL."}]))
    got = lines_of(out)
    assert got["L0002"]["parts"] == [{"say": "Hector is slain."}] and got["L0002b"]["parts"] == [{"say": "Hector! The gods forbid!"}] and got["L0002b"]["role"] == "ALL"
    assert [l["id"] for l in out["lines"]][:5] == ["L0001", "L0002", "L0002b", "L0002a", "L0003"], "the letter L0002a was used already"


@case
def a_split_makes_a_direction_of_the_tail_and_keeps_part_kinds():
    lines = [sp("L0001", "A", "Go on.", "Yes.", {"direction": "he waves"}, {"say": "[ Exit A"})]
    e = entry(lines)
    out = run(e, corr(e, "L0001", "split", evidence="Go on.", pieces=[{"as": "speech", "role": "A"}, {"as": "direction", "from": "[ Exit"}]))
    assert lines_of(out)["L0001"]["parts"] == [{"say": "Go on."}, {"say": "Yes."}, {"direction": "he waves"}]
    assert lines_of(out)["L0001a"] == {"id": "L0001a", "kind": "direction", "source": "[ Exit A"}


@case
def a_single_piece_cut_removes_a_caption_and_a_dropped_piece_a_warning():
    lines = [sp("L0001", "SONG", "Music illustration: 1. The ship sails.")]
    e = entry(lines)
    out = run(e, corr(e, "L0001", "split", evidence="Music illustration: 1. The ship", pieces=[{"as": "speech", "role": "SONG", "cut": "Music illustration:"}]))
    assert lines_of(out)["L0001"]["parts"] == [{"say": "1. The ship sails."}]
    lines = [sp("L0001", "WARNING", "Could not break paragraph: MRS. S: Counting. One.")]
    e = entry(lines)
    out = run(e, corr(e, "L0001", "split", evidence="Could not break paragraph:", pieces=[
        {"as": "drop"}, {"as": "speech", "role": "MRS. S", "from": "MRS. S: Counting", "cut": "MRS. S:"}]))
    assert [l["id"] for l in out["lines"]] == ["L0001"] and lines_of(out)["L0001"]["role"] == "MRS. S" and lines_of(out)["L0001"]["parts"] == [{"say": "Counting. One."}]


@case
def a_start_the_line_prints_twice_is_named_by_its_place():
    lines = [sp("L0001", "MILLER", "Yes.\nFIRST CLERK", {"direction": "bowing"}, {"say": ". Just so.\nSECOND CLERK. Even so.\nFIRST CLERK. Just so again."})]
    e = entry(lines)
    pieces = [{"as": "speech", "role": "MILLER"}, {"as": "speech", "role": "FIRST CLERK", "from": "FIRST CLERK", "nth": 1, "cut": "FIRST CLERK"},
              {"as": "speech", "role": "SECOND CLERK", "from": "SECOND CLERK.", "cut": "SECOND CLERK."},
              {"as": "speech", "role": "FIRST CLERK", "from": "FIRST CLERK", "nth": 2, "cut": "FIRST CLERK"}]
    out = run(e, corr(e, "L0001", "split", evidence="Yes. FIRST CLERK bowing", pieces=pieces))
    assert [(l["role"], l["parts"]) for l in out["lines"]][-1] == ("FIRST CLERK", [{"say": ". Just so again."}])
    assert "not 3 times" in refused(e, corr(e, "L0001", "split", evidence="Yes.", pieces=[pieces[0], {**pieces[1], "nth": 3}]))
    assert "2 times, not once" in refused(e, corr(e, "L0001", "split", evidence="Yes.", pieces=[pieces[0], {k: v for k, v in pieces[3].items() if k != "nth"}]))


@case
def a_split_never_adds_a_word():
    """Every letter of the pieces is a letter of the line, less the quoted cut and the dropped piece."""
    e = entry()
    out = run(e, corr(e, "L0002", "split", evidence="Hector is slain.", pieces=[{"as": "speech", "role": "HALE"}, {"as": "speech", "role": "ALL", "from": "ALL. Hector", "cut": "ALL."}]))
    original = "".join(e["lines"][1]["parts"][0]["say"].split())
    first, second = ("".join("".join(p["say"].split()) for p in lines_of(out)[k]["parts"]) for k in ("L0002", "L0002b"))
    assert first + "ALL." + second == original


@case
def a_correction_for_a_changed_play_is_refused_loudly():
    e = entry()
    c = corr(e, "L0004", "role", role="SHERIFF")
    c["revision"] = "000000000000"
    assert "read it again" in refused(e, c)


@case
def a_label_misprinted_is_evidence_too():
    e = entry()
    out = run(e, corr(e, "L0004", "role", role="SHERIFF", evidence="COOK. A very distinguished"))
    assert lines_of(out)["L0004"]["role"] == "SHERIFF"


@case
def a_split_that_would_add_a_word_is_refused():
    e = entry()
    real = PC._speech
    PC._speech = lambda lid, role, segs, em=None: real(lid, role, segs + [("say", "extra")], em)
    try:
        assert "lost or added" in refused(e, corr(e, "L0002", "split", evidence="Hector is slain.",
                                                  pieces=[{"as": "speech", "role": "A"}, {"as": "speech", "role": "B", "from": "ALL. Hector", "cut": "ALL."}]))
    finally:
        PC._speech = real


@case
def evidence_that_is_not_in_the_play_is_refused():
    e = entry()
    assert "evidence" in refused(e, corr(e, "L0004", "role", role="SHERIFF", evidence="Not a word of this is printed"))


@case
def evidence_is_at_most_twelve_words_and_the_file_says_why():
    import tempfile
    e = entry()
    for bad in (dict(evidence=" ".join(["word"] * 13)), dict(why="")):
        doc = {"format": 1, "corrections": [{**corr(e, "L0004", "drop"), **bad}]}
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump(doc, f)
        try:
            PC.load(f.name)
        except PC.Refused:
            continue
        finally:
            os.unlink(f.name)
        raise AssertionError("a malformed correction was loaded")


@case
def a_missing_line_a_second_correction_and_a_bad_split_are_refused():
    e = entry()
    assert "no such line" in refused(e, corr(e, "L0099", "drop"))
    assert "twice" in refused(e, corr(e, "L0004", "drop", evidence="A very distinguished woman."), corr(e, "L0004", "role", role="X", evidence="A very distinguished woman."))
    assert "once" in refused(e, corr(e, "L0002", "split", evidence="Hector is slain.", pieces=[{"as": "speech", "role": "A"}, {"as": "speech", "role": "B", "from": "no such words"}]))
    assert "begin with the cut" in refused(e, corr(e, "L0002", "split", evidence="Hector is slain.", pieces=[{"as": "speech", "role": "A"}, {"as": "speech", "role": "B", "from": "ALL. Hector", "cut": "ZZZ."}]))
    assert refused(e, corr(e, "L0002", "split", evidence="Hector is slain.", pieces=[{"as": "speech", "role": "A"}]))


@case
def two_labels_for_one_part_become_one_and_the_roles_follow():
    lines = [sp("L0001", "JOE'S MOTHER", "Let us hope."), sp("L0002", "JOE", "Yes."), sp("L0003", "JOE'S M", "So laudable his wish."),
             {"id": "L0004", "kind": "direction", "source": "Exit."}, sp("L0005", "JOE'S M", "Away.")]
    e = entry(lines)
    out = run(e, corr(e, "L0003", "merge", role="JOE'S MOTHER", **{"from": "JOE'S M"}, evidence="So laudable his wish."))
    assert [l.get("role") for l in out["lines"]] == ["JOE'S MOTHER", "JOE", "JOE'S MOTHER", None, "JOE'S MOTHER"]
    assert {r["name"]: r["lines"] for r in out["roles"]} == {"JOE'S MOTHER": 3, "JOE": 1} and out["revision"] != e["revision"]
    assert [l["parts"] for l in out["lines"] if l["kind"] == "speech"] == [l["parts"] for l in lines if l["kind"] == "speech"], "no word moves"
    assert [l["id"] for l in out["lines"]] == [l["id"] for l in lines], "no id moves"


@case
def a_merge_keeps_a_label_the_play_prints_and_starts_at_the_label_it_takes_away():
    lines = [sp("L0001", "JOE'S MOTHER", "Let us hope."), sp("L0002", "JOE'S M", "So laudable his wish.")]
    e = entry(lines)
    merge = lambda line, keep, gone: corr(e, line, "merge", role=keep, evidence="So laudable his wish.", **{"from": gone})
    assert "keeps a label the play prints" in refused(e, merge("L0002", "JOE'S MA", "JOE'S M"))
    assert "keeps a label the play prints" in refused(e, merge("L0001", "JOE'S M", "JOE'S M"))
    assert "keeps a label the play prints" in refused(e, merge("L0001", "JOE'S MOTHER", "JOE'S M"))
    assert "names the label" in refused_load({"play": "gut-1", "revision": "r", "line": "L0002", "op": "merge", "evidence": "x", "why": "y", "role": "A"})


def refused_load(c):
    import tempfile
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump({"format": PC.FORMAT, "corrections": [c]}, f)
    try:
        PC.load(f.name)
    except PC.Refused as err:
        return str(err)
    finally:
        os.unlink(f.name)
    raise AssertionError("a malformed correction was loaded")


@case
def a_correction_that_takes_away_a_line_a_section_opens_at_is_refused():
    e = entry(sections=[{"line": "L0004", "source": "ACT II"}])
    assert "section" in refused(e, corr(e, "L0004", "drop", evidence="A very distinguished woman."))


@case
def the_file_in_the_repo_is_well_formed_and_every_correction_names_its_play():
    table = PC.load()
    assert table and all(c["play"] == k for k, cs in table.items() for c in cs)
    assert len({(c["play"], c["line"]) for cs in table.values() for c in cs}) == sum(len(cs) for cs in table.values()), "a line corrected twice"


def main():
    failed = 0
    for fn in CASES:
        try:
            fn()
        except (AssertionError, KeyError, StopIteration, TypeError, ValueError, PC.Refused) as e:
            failed += 1
            print(f"FAIL {fn.__name__}: {type(e).__name__} {str(e)[:300]}")
    print(f"{len(CASES) - failed}/{len(CASES)} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
