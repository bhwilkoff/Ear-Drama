"""play_punctuation: the stop a split-off direction leaves at the head of the words (catalog DECISIONS 046, BACKLOG-LOOP B27).

    python3 tests/test_play_punctuation.py

Mutation controls: tests/mutate_play_punctuation.py removes each guard in turn.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import play_corrections as PC
import play_punctuation as PN

CASES = []


def case(fn):
    CASES.append(fn)
    return fn


def d(x):
    return {"direction": x}


def s(x):
    return {"say": x}


def fixed(*parts, em=()):
    out, e = PN.mend_parts(list(parts), list(em))
    return out


@case
def a_stop_closing_the_opening_direction_goes():
    assert fixed(d("yawning impatiently"), s(".\nCome! I am weary...")) == [d("yawning impatiently"), s("Come! I am weary...")]
    assert fixed(d("Strato"), s(", thou hast some skill")) == [d("Strato"), s("thou hast some skill")]
    assert fixed(d("Solamen"), s(": but I alone.")) == [d("Solamen"), s("but I alone.")]
    assert fixed(d("ironically"), s(".             Oh,")) == [d("ironically"), s("Oh,")]


@case
def a_run_of_stops_goes():
    assert fixed(d("aside"), s(". , Well.")) == [d("aside"), s("Well.")]
    assert fixed(d("aside"), s(";: Well.")) == [d("aside"), s("Well.")]


@case
def after_another_direction_too():
    assert fixed(d("rising"), d("to the door"), s(". Well.")) == [d("rising"), d("to the door"), s("Well.")]


@case
def an_ellipsis_stays():
    for t in ("...and so on", "... and so on", "…and so on", ".. odd"):
        assert fixed(d("trailing off"), s(t)) == [d("trailing off"), s(t)], t
    assert fixed(d("aside"), s(". ...and so on")) == [d("aside"), s("...and so on")]


@case
def a_dash_a_quote_a_bracket_a_letter_stays():
    for t in ("—and so", "--and so", '"Come!" he said', "“Come!”", "(aside) Come", "] Come", "Come", "!Come", "?"):
        assert fixed(d("aside"), s(t)) == [d("aside"), s(t)], t
    assert fixed(d("aside"), s(".—and so")) == [d("aside"), s("—and so")]


@case
def a_say_with_no_direction_before_it_stays():
    assert fixed(s(". Come!")) == [s(". Come!")]
    assert fixed(s("Well."), s(". Come!")) == [s("Well."), s(". Come!")]
    assert fixed(d("aside"), d("rising"), s("Well"), s(". Come!")) == [d("aside"), d("rising"), s("Well"), s(". Come!")]


@case
def a_say_left_empty_goes():
    assert fixed(d("They go out"), s(".")) == [d("They go out")]
    assert fixed(s("We are gone."), d("They go out"), s(".")) == [s("We are gone."), d("They go out")]
    assert fixed(d("a"), s(" . "), d("b"), s("Yes.")) == [d("a"), d("b"), s("Yes.")]


@case
def in_the_middle_the_second_stop_goes():
    assert fixed(s("Hector is slain."), d("sits down"), s(". What now?")) == [s("Hector is slain."), d("sits down"), s("What now?")]
    assert fixed(s("Why!"), d("sits"), s(".")) == [s("Why!"), d("sits")]
    assert fixed(s("Why?"), d("sits"), s(".\nNo.")) == [s("Why?"), d("sits"), s("No.")]
    assert fixed(s("Well."), d("a"), d("b"), s(". Yes.")) == [s("Well."), d("a"), d("b"), s("Yes.")]


@case
def in_the_middle_the_sentences_own_stop_stays():
    # the direction was an emphasised word inside the sentence: the stop is the sentence's
    assert fixed(s("We shall (indeed"), d("do"), s(". This stormy air")) == [s("We shall (indeed"), d("do"), s(". This stormy air")]
    assert fixed(s("Nor any thing,"), d("Arnoldo"), s(".")) == [s("Nor any thing,"), d("Arnoldo"), s(".")]
    assert fixed(s("Well -"), d("he stammers"), s(".")) == [s("Well -"), d("he stammers"), s(".")]
    assert fixed(s("Well."), d("a"), s(", and so")) == [s("Well."), d("a"), s(", and so")]
    assert fixed(s("Well."), d("a"), s(": and so")) == [s("Well."), d("a"), s(": and so")]
    assert fixed(s("Well."), d("a"), s("... and so")) == [s("Well."), d("a"), s("... and so")]
    assert fixed(s("Well."), d("a"), s(".. and so")) == [s("Well."), d("a"), s(".. and so")]
    assert fixed(s("Well."), d("a"), s(".and so")) == [s("Well."), d("a"), s(".and so")]


@case
def italic_marks_follow_their_parts():
    parts = [d("a"), s(". Oh"), s("so"), s("much")]
    out, em = PN.mend_parts(parts, [2])
    assert out == [d("a"), s("Oh"), s("so"), s("much")] and em == [2]
    parts = [d("a"), s("."), s("so"), s("much")]
    out, em = PN.mend_parts(parts, [2])
    assert out == [d("a"), s("so"), s("much")] and em == [1]


def sp(lid, role, *parts, em=()):
    line = {"id": lid, "kind": "speech", "role": role, "parts": list(parts)}
    if em:
        line["em"] = list(em)
    return line


def entry(lines):
    return {"id": "gut-1", "revision": PC._revision(lines), "lines": lines, "roles": PC._roles(lines),
            "sections": [{"line": "L0001", "source": "ACT I"}]}


@case
def a_line_nothing_is_mended_in_is_the_same_object():
    lines = [sp("L0001", "A", s("Hello.")), sp("L0002", "B", d("aside"), s("Yes."))]
    e = entry(lines)
    assert PN.mend(e) is e
    mended = PN.mend(entry([lines[0], sp("L0002", "B", d("aside"), s(". Yes."))]))
    assert mended["lines"][0] is lines[0]


@case
def a_speech_left_with_no_words_is_a_direction():
    e = entry([sp("L0001", "A", s("Well.")), sp("L0002", "A", d("They go out"), s(".")), sp("L0003", "B", s("Yes."))])
    out = PN.mend(e)
    assert out["lines"][1] == {"id": "L0002", "kind": "direction", "source": "They go out"}
    assert [l["id"] for l in out["lines"]] == ["L0001", "L0002", "L0003"]
    assert out["roles"] == [{"name": "A", "lines": 1, "words": 1}, {"name": "B", "lines": 1, "words": 1}]
    assert out["revision"] != e["revision"] and out["sections"] == e["sections"]


@case
def the_roles_and_revision_follow_and_ids_stay():
    e = entry([sp("L0001", "A", d("aside"), s(". Come now."), s("sir"), em=[2]), sp("L0001a", "B", s("Yes."))])
    out = PN.mend(e)
    assert out["lines"][0] == {"id": "L0001", "kind": "speech", "role": "A", "parts": [d("aside"), s("Come now."), s("sir")], "em": [2]}
    assert out["revision"] == PC._revision(out["lines"]) and out["roles"] == PC._roles(out["lines"])
    assert [l["id"] for l in out["lines"]] == ["L0001", "L0001a"]
    assert e["lines"][0]["parts"][1] == s(". Come now."), "the entry given is not changed"


@case
def mending_twice_changes_nothing():
    e = entry([sp("L0001", "A", d("aside"), s(". Come now.")), sp("L0002", "B", s("Well."), d("sits"), s(". Yes."))])
    once = PN.mend(e)
    assert PN.mend(once) is once


if __name__ == "__main__":
    bad = 0
    for fn in CASES:
        try:
            fn()
            print("ok  ", fn.__name__)
        except AssertionError as err:
            bad += 1
            print("FAIL", fn.__name__, err)
    print(f"{len(CASES) - bad}/{len(CASES)} passed")
    sys.exit(1 if bad else 0)
