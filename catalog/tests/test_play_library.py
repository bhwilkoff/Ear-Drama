"""The play library published beside the catalog (Decision 075, docs/CATALOG-CONTRACT.md
"Play library"): every rights-cleared Gutenberg play that parses clean, as an index plus
one script file per play.

    python3 tests/test_play_library.py

The shape check (`check_library`) runs over a fixture build always, and over the real
artifact in catalog/out/plays-library/ whenever it has been built. It reads shape and
cross-file consistency, never which plays exist.
"""
import json
import os
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import build_castable_scripts as B
import build_play_library as L
import script_parse as P

CASES = []


def case(fn):
    CASES.append(fn)
    return fn


def stage(name, speakers=("SHERIFF", "MRS PETERS"), n=60):
    return f"*** START OF THE PROJECT GUTENBERG EBOOK {name} ***\n\n{name}\n\nSCENE: The kitchen.\n\n" + "\n\n".join(
        f"{s}. Line {i}, said plainly and at some length.\n\n" if k else f"{s}. Answer {i}, said back with a few more words.\n\n"
        for i in range(n) for k, s in enumerate(speakers)) + "\n"


def play(pid, title, rights="Public domain in the USA.", subjects=("Drama",)):
    return {"id": f"gut-{pid}", "title": title, "authors": [{"name": "Glaspell, Susan", "born": 1876, "died": 1948,
            "role": "author"}], "translators": [], "year": None, "year_basis": None,
            "source_url": f"https://www.gutenberg.org/ebooks/{pid}",
            "rights": {"text": rights, "src": f"https://www.gutenberg.org/ebooks/{pid}.rdf"},
            "subjects": list(subjects), "shelves": [], "librivox": [],
            "evidence": [{"claim": rights, "src": f"https://www.gutenberg.org/ebooks/{pid}.rdf"}]}


TEXTS = {"1": stage("TRIFLES"), "2": stage("ONE VOICE", speakers=("SHERIFF",)),
         "3": "*** START OF THE PROJECT GUTENBERG EBOOK TINY ***\n\nA short note.\n", "4": stage("RENEWED")}
PLAYS = [play(1, "Trifles"), play(2, "One Voice"), play(3, "Tiny"), play(4, "Hidden", rights="Copyrighted. Read the copyright notice inside this book for details."),
         play(5, "Never Fetched")]
CTX = {"renewals": {}, "takedowns": {}, "today": __import__("datetime").date(2026, 11, 14)}


def fixture_build():
    return L.build(PLAYS, CTX, TEXTS.get)


def check_library(root):
    """Shape and consistency of a built library; returns the index."""
    idx = json.load(open(os.path.join(root, "index.json")))
    assert idx["format"] == L.FORMAT and isinstance(idx["plays"], list)
    assert idx["count"] == len(idx["plays"]) > 0
    names = sorted(os.listdir(os.path.join(root, "scripts")))
    assert names == sorted(f"{p['id']}.json" for p in idx["plays"]), "scripts/ and the index name different plays"
    ids = [p["id"] for p in idx["plays"]]
    assert len(ids) == len(set(ids)), "duplicate id"
    keys = [(p["sort_name"], p["id"]) for p in idx["plays"]]
    assert keys == sorted(keys), "index is not in sort order"
    for p in idx["plays"]:
        assert p["id"].startswith("gut-") and p["id"][4:].isdigit(), p["id"]
        assert p["kind"] in ("stage", "radio"), p
        for k in ("title", "revision", "path"):
            assert isinstance(p[k], str) and p[k], (p["id"], k)
        assert p["path"] == f"scripts/{p['id']}.json"
        assert isinstance(p["authors"], list) and all(isinstance(a, str) for a in p["authors"])
        assert isinstance(p["voices"], int) and p["voices"] >= 2, p
        assert p["roles"] >= p["voices"] and p["words"] > 0 and p["minutes"] >= 1 and p["lines"] > 0
        assert "year" not in p or isinstance(p["year"], int)
        assert p["rights"]["bucket"] and p["rights"]["evidence"], (p["id"], "no rights evidence")
        for ev in p["rights"]["evidence"]:
            assert ev["claim"] and ev["src"].startswith("http"), p["id"]
        assert p["source"]["url"].startswith("http")
        doc = json.load(open(os.path.join(root, p["path"])))
        assert doc["format"] == L.FORMAT and len(doc["scripts"]) == 1
        s = doc["scripts"][0]
        assert s["id"] == p["id"] and s["revision"] == p["revision"] and s["title"] == p["title"]
        assert len(s["roles"]) == p["roles"] and s["rights"] == p["rights"]
        speech = [l for l in s["lines"] if l["kind"] == "speech"]
        assert len(speech) == p["lines"]
        assert all(l["role"] and l["parts"] for l in speech)
    return idx


@case
def only_clean_and_castable_plays_are_built():
    entries, report = fixture_build()
    assert [e["id"] for e in entries] == ["gut-1"], [e["id"] for e in entries]
    assert report["parsed"] == 3 and report["clean"] == 1 and report["rights_cleared_uncached"] == 1, report
    assert report["failures"] == {"stub_too_short": 1, "unclean_fewer_than_two_castable_roles": 1}, report["failures"]


@case
def a_play_is_the_bundles_entry_byte_for_byte():
    entries, _ = fixture_build()
    parsed = P.parse(TEXTS["1"], "stage")
    direct = B.script_entry(L.R.from_gutenberg(PLAYS[0]), L.R.judge(L.R.from_gutenberg(PLAYS[0]), CTX), parsed)
    assert entries[0] == direct and entries[0]["revision"] == direct["revision"]


@case
def a_title_cut_off_by_punctuation_is_held():
    assert L.title_unusable({"title": "The Collected Works of"}) and L.title_unusable({"title": "The"})
    assert not L.title_unusable({"title": "Faust"}) and not L.title_unusable({"title": "Lady Windermere's Fan"})


@case
def the_index_and_the_files_agree():
    entries, report = fixture_build()
    with tempfile.TemporaryDirectory() as d:
        L.write(entries, report, d)
        check_library(d)


@case
def writing_again_removes_a_play_that_left():
    entries, report = fixture_build()
    with tempfile.TemporaryDirectory() as d:
        L.write(entries, report, d)
        open(os.path.join(d, "scripts", "gut-99.json"), "w").write("{}")
        L.write(entries, report, d)
        assert sorted(os.listdir(os.path.join(d, "scripts"))) == ["gut-1.json"]


@case
def the_check_fails_on_a_missing_script_file():
    entries, report = fixture_build()
    with tempfile.TemporaryDirectory() as d:
        L.write(entries, report, d)
        os.remove(os.path.join(d, "scripts", "gut-1.json"))
        try:
            check_library(d)
        except (AssertionError, FileNotFoundError):
            return
        raise AssertionError("a library with an index row and no file passed the check")


@case
def the_check_fails_without_rights_evidence():
    entries, report = fixture_build()
    with tempfile.TemporaryDirectory() as d:
        L.write(entries, report, d)
        p = os.path.join(d, "index.json")
        idx = json.load(open(p))
        idx["plays"][0]["rights"]["evidence"] = []
        json.dump(idx, open(p, "w"))
        try:
            check_library(d)
        except AssertionError:
            return
        raise AssertionError("a play with no rights evidence passed the check")


GOLDEN_SECTIONS = os.path.join(os.path.dirname(__file__), "golden", "script_sections.json")


@case
def section_headings_agree_with_the_golden_cases():
    for c in json.load(open(GOLDEN_SECTIONS))["cases"]:
        assert P.section_level(c["text"]) == c["level"], (c["text"], P.section_level(c["text"]), c["level"])


@case
def a_printed_act_heading_the_parser_sets_aside_is_a_section():
    text = stage("ACTS").replace("SCENE: The kitchen.", "ACT I.\n\nSCENE: The kitchen.")
    half = text.index("SHERIFF. Answer 30,")
    text = text[:half] + "ACT II.\n\n" + text[half:]
    parsed = P.parse(text, "stage")
    secs = parsed["sections"]
    assert [s["source"] for s in secs] == ["ACT I.", "ACT II."], secs
    ids = [l["id"] for l in parsed["lines"]]
    assert secs[0]["line"] == ids[0], (secs[0], ids[:2])
    second = next(l for l in parsed["lines"] if "Answer 30," in (l.get("source") or ""))
    assert secs[1]["line"] == second["id"], (secs[1], second["id"])
    entry = B.script_entry(L.R.from_gutenberg(PLAYS[0]), L.R.judge(L.R.from_gutenberg(PLAYS[0]), CTX), parsed)
    assert entry["sections"] == secs
    plain = B.script_entry(L.R.from_gutenberg(PLAYS[0]), L.R.judge(L.R.from_gutenberg(PLAYS[0]), CTX), P.parse(TEXTS["1"], "stage"))
    assert "sections" not in plain, "a play with no printed heading carries no sections key"


@case
def an_index_row_carries_its_cast_largest_first():
    entries, _ = fixture_build()
    row = L.index_row(entries[0])
    assert row["cast"] == sorted((r["lines"] for r in entries[0]["roles"]), reverse=True) and len(row["cast"]) == row["roles"]


@case
def the_real_artifact_has_the_documented_shape():
    if not os.path.exists(os.path.join(L.OUT, "index.json")):
        print("  (no built library in out/plays-library; fixture shape only)")
        return
    idx = check_library(L.OUT)
    bundle = json.load(open(L.BUNDLE))["scripts"]
    have = {p["id"]: p for p in idx["plays"]}
    for s in bundle:
        assert s["id"] in have, f"bundled {s['id']} is missing from the library"
        assert have[s["id"]]["revision"] == s["revision"], f"{s['id']}: the library's text differs from the bundle's"
    assert idx["report"]["bundled_missing_from_library"] == []


def main():
    failed = 0
    for fn in CASES:
        try:
            fn()
        except (AssertionError, KeyError, StopIteration, FileNotFoundError) as e:
            failed += 1
            print(f"FAIL {fn.__name__}: {e!r}")
    print(f"{len(CASES) - failed}/{len(CASES)} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
