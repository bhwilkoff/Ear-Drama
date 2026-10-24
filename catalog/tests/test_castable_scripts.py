"""The castable-scripts file the apps bundle (PLAYS-DESIGN §3, §8 rule 1): a script
is written only when its rights are castable AND its parse is clean, and every line
keeps the parser's exact slices.

    python3 tests/test_castable_scripts.py
Broken controls, 2026-10-22, each run against a mutated copy of build_castable_scripts.py:
    offered() ignores the parse   3/4     offered() ignores the rights   3/4
    speech keeps no parts         3/4
2026-10-23: display_title ignores the volume 5/6; printed_title returns None 5/6;
    any printed title replaces the record's 5/6
"""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import build_castable_scripts as B
import script_parse as P

CASES = []


def case(fn):
    CASES.append(fn)
    return fn


STAGE = """*** START OF THE PROJECT GUTENBERG EBOOK TRIFLES ***

TRIFLES

SCENE: The kitchen.

""" + "\n\n".join(f"SHERIFF. [Rubbing his hands.] Line {i}, said plainly and at some length.\n\n"
                  f"MRS PETERS. Answer {i}, said back to him with a few more words." for i in range(60)) + "\n"

CASTABLE = {"castable": True, "bucket": "script_source_cleared", "evidence": [{"claim": "Public domain in the USA.",
                                                                                "src": "https://example.org/1.rdf"}]}
HIDDEN = {"castable": False, "bucket": "script_renewed", "evidence": []}
RECORD = {"id": "gut-1", "kind": "stage", "title": "Trifles", "authors": [{"name": "Glaspell, Susan", "died": 1948}],
          "source": {"name": "Project Gutenberg", "url": "https://example.org/1"}}


@case
def clean_and_castable_is_offered():
    parsed = P.parse(STAGE, "stage")
    assert parsed["clean"], parsed["issues"]
    assert B.offered(CASTABLE, parsed)


@case
def a_hidden_script_is_never_offered():
    assert not B.offered(HIDDEN, P.parse(STAGE, "stage"))


@case
def an_unclean_parse_is_never_offered():
    parsed = dict(P.parse(STAGE, "stage"), clean=False)
    assert not B.offered(CASTABLE, parsed)
    assert not B.offered(CASTABLE, {"status": "stub"})


@case
def the_entry_carries_its_sort_name():
    entry = B.script_entry(dict(RECORD, title='"The Fixture Play"'), CASTABLE, P.parse(STAGE, "stage"))
    assert entry["sort_name"] == 'fixture play"', entry["sort_name"]


@case
def lines_keep_the_exact_slices_and_the_evidence():
    parsed = P.parse(STAGE, "stage")
    entry = B.script_entry(RECORD, CASTABLE, parsed)
    assert entry["rights"]["evidence"] == CASTABLE["evidence"]
    speech = [l for l in entry["lines"] if l["kind"] == "speech"]
    src = {l["id"]: l for l in parsed["lines"]}
    for l in speech:
        assert l["parts"] == src[l["id"]]["parts"], l
        assert "source" not in l
    assert speech[0]["parts"][0] == {"direction": "Rubbing his hands."}, speech[0]
    again = B.script_entry(RECORD, CASTABLE, parsed)
    assert again["revision"] == entry["revision"], "the revision is a hash of the lines"
    json.dumps(entry)


@case
def a_collected_volume_shows_the_play_it_prints():
    parsed = P.parse(STAGE, "stage")
    assert parsed["printed_title"] == "TRIFLES", parsed["printed_title"]
    volume = dict(RECORD, title="The Works of Susan Glaspell, Vol. 2")
    entry = B.script_entry(volume, CASTABLE, parsed)
    assert entry["title"] == "Trifles" and entry["collection"] == volume["title"], entry["title"]


@case
def a_play_record_keeps_its_own_title():
    entry = B.script_entry(dict(RECORD, title="Trifles: A Play"), CASTABLE, P.parse(STAGE, "stage"))
    assert entry["title"] == "Trifles: A Play" and "collection" not in entry, entry["title"]


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
