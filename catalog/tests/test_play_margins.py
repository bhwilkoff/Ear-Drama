"""play_margins: the verse's line numbers read as words (catalog DECISIONS 048, BACKLOG-LOOP B28).

    python3 tests/test_play_margins.py

Mutation controls: tests/mutate_play_emphasis.py removes each guard in turn.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import play_corrections as PC
import play_margins as PM

CASES = []


def case(fn):
    CASES.append(fn)
    return fn


def speech(n, *parts, em=()):
    return {"id": f"L{n:04d}", "kind": "speech", "role": "ARN", "parts": [{"say": p} if isinstance(p, str) else p for p in parts], **({"em": list(em)} if em else {})}


def play(*lines):
    return {"id": "gut-1", "revision": PC._revision(lines), "lines": list(lines), "roles": PC._roles(lines)}


def numbered(*more, first=10):
    """gut-23475-108's print: a number after a row's end, then the next row."""
    return play(*[speech(n, f"How art thou fallen          {first + 10 * n} Son of the Morning!") for n in range(6)], *more)


def says(entry, n):
    return [p.get("say") for p in entry["lines"][n]["parts"]]


@case
def the_numbers_go():
    out = PM.mend(numbered())
    assert [says(out, n) for n in range(6)] == [["How art thou fallen Son of the Morning!"]] * 6
    assert out["revision"] == PC._revision(out["lines"]) and out["roles"] == [{"name": "ARN", "lines": 6, "words": 48}]


@case
def a_row_keeps_its_break():
    e = numbered(speech(7, "Or a monarch who     70\nHas heard the truth.", em=()))
    assert says(PM.mend(e), 6) == ["Or a monarch who\nHas heard the truth."]
    assert says(PM.mend(numbered(speech(7, "No, she is calm.      70"))), 6) == ["No, she is calm."]


@case
def one_printed_without_the_spaces_goes_only_in_its_place():
    assert says(PM.mend(numbered(speech(7, "Call no pilgrim queer 70 And see."))), 6) == ["Call no pilgrim queer And see."]
    assert says(PM.mend(numbered(speech(7, "Call no pilgrim queer 70"))), 6) == ["Call no pilgrim queer"]
    for text in ("I had 70 pounds.", "I had 75 Crowns, and 300 Crowns.", "He was born in 1580 In May."):
        e = numbered(speech(7, text))
        if "75" not in text:
            assert says(PM.mend(e), 6) == [text], text
    assert says(PM.mend(numbered(speech(7, "There were 20 Crowns."))), 6) == ["There were 20 Crowns."], "before the number before it"
    e = numbered(speech(7, "There were 90 Crowns."), speech(8, "Row          80 Row."))
    assert says(PM.mend(e), 6) == ["There were 90 Crowns."], "past the number after it"


@case
def only_multiples_of_five():
    assert says(PM.mend(numbered(speech(7, "The row ends       72 So."))), 6) == ["The row ends       72 So."]
    assert says(PM.mend(numbered(speech(7, "The row ends       0 So."))), 6) == ["The row ends       0 So."]


@case
def a_play_that_is_not_numbered_is_the_same():
    e = play(*[speech(n, f"It cost          {n * 5} pounds.") for n in range(1, 5)])
    assert PM.mend(e) is e, "four numbers are too few"
    e = play(*[speech(n, f"It cost          {c} pounds.") for n, c in enumerate((50, 20, 40, 30, 60, 10, 5))])
    assert PM.mend(e) is e, "they do not rise"
    e = play(*[speech(n, f"It cost {n * 5} Pounds.") for n in range(1, 9)])
    assert PM.mend(e) is e, "not set apart"


@case
def a_part_that_was_a_number_alone_goes_and_emphasis_keeps_its_place():
    e = numbered(speech(7, {"direction": "Aside"}, "70", "so", "much", em=[2]))
    line = PM.mend(e)["lines"][6]
    assert line["parts"] == [{"direction": "Aside"}, {"say": "so"}, {"say": "much"}] and line["em"] == [1]
    line = PM.mend(numbered(speech(7, {"direction": "Andrew."}, "70")))["lines"][6]
    assert line == {"id": "L0007", "kind": "direction", "source": "Andrew."}


@case
def nothing_else_moves():
    e = numbered(speech(7, "Words alone."), {"id": "L0008", "kind": "direction", "source": "Row      70 Row."})
    out = PM.mend(e)
    assert out["lines"][6] is e["lines"][6] and out["lines"][7] is e["lines"][7]
    assert [l["id"] for l in out["lines"]] == [l["id"] for l in e["lines"]]
    assert PM.mend(out) is out
    assert says(e, 0) == ["How art thou fallen          10 Son of the Morning!"], "the entry given is not changed"


if __name__ == "__main__":
    bad = 0
    for fn in CASES:
        try:
            fn()
            print("ok  ", fn.__name__)
        except Exception as err:  # a mutant may break what a case reads
            bad += 1
            print("FAIL", fn.__name__, repr(err))
    print(f"{len(CASES) - bad}/{len(CASES)} passed")
    sys.exit(1 if bad else 0)
