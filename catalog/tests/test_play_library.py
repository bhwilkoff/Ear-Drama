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
import shutil
import sys
import tarfile
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import build_castable_scripts as B
import build_play_library as L
import check_play_library as C
import play_library_archive as A
import play_phonemes as PH
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


def speeches(prefix, speakers, n=40):
    return "\n\n".join(f"{s}. {prefix} line {i} of {s}, said plainly and at some length." for i in range(n) for s in speakers)


def volume_text(titles=("THE FIRST PLAY", "THE SECOND PLAY"), names=(("SHERIFF", "HALE"), ("COOK", "BAKER"))):
    out = ["*** START OF THE PROJECT GUTENBERG EBOOK VOLUME ***", "THE COLLECTED PLAYS"]
    for title, who in zip(titles, names):
        out += [title, "CHARACTERS", "\n".join(f"{w}, a person." for w in who), "ACT I",
                speeches(title.split()[1].lower(), who), "THE END"]
    return "\n\n".join(out) + "\n"


check_library = C.check_library


@case
def only_clean_and_castable_plays_are_built():
    entries, report = fixture_build()
    assert [e["id"] for e in entries] == ["gut-1"], [e["id"] for e in entries]
    assert report["parsed"] == 3 and report["clean"] == 1 and report["rights_cleared_uncached"] == 1, report
    assert report["failures"] == {"stub_too_short": 1, "monologue": 1}, report["failures"]


@case
def a_play_is_the_bundles_entry_byte_for_byte():
    entries, _ = fixture_build()
    parsed = P.parse(TEXTS["1"], "stage")
    direct = B.script_entry(L.R.from_gutenberg(PLAYS[0]), L.R.judge(L.R.from_gutenberg(PLAYS[0]), CTX), parsed)
    plain = {**entries[0], "roles": [{k: v for k, v in r.items() if k != "register"} for r in entries[0]["roles"]]}
    assert plain == direct and entries[0]["revision"] == direct["revision"], "the same entry but each role's register"


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
def each_role_carries_its_stand_in_register_and_the_index_says_it_in_cast_order():
    # catalog DECISIONS 049: "MRS PETERS" is a woman by her title; nothing says what the SHERIFF is (no list, no direction)
    entries, report = fixture_build()
    roles = {r["name"]: r.get("register") for r in entries[0]["roles"]}
    assert roles == {"SHERIFF": None, "MRS PETERS": "high"}, roles
    row = L.index_row(entries[0])
    order = sorted(entries[0]["roles"], key=lambda r: -r["lines"])
    assert row["registers"] == "".join("h" if r.get("register") == "high" else "-" for r in order), row["registers"]
    with tempfile.TemporaryDirectory() as d:
        L.write(entries, report, d)
        check_library(d)
        idx = json.load(open(os.path.join(d, "index.json")))
        idx["plays"][0]["registers"] = idx["plays"][0]["registers"][::-1]
        json.dump(idx, open(os.path.join(d, "index.json"), "w"))
        try:
            check_library(d)
        except AssertionError:
            return
        raise AssertionError("an index whose registers disagree with its script passed the check")


@case
def an_index_row_carries_its_opening_speeches_in_their_own_words():
    entries, _ = fixture_build()
    e = entries[0]
    row = L.index_row(e)
    speeches = [l for l in e["lines"] if l["kind"] == "speech"]
    assert len(row["opening"]) == min(L.OPENING_SPEECHES, len(speeches)), row["opening"]
    for o, l in zip(row["opening"], speeches):
        assert o["role"] == l["role"], (o, l)
        said = " ".join(p["say"] for p in l["parts"] if "say" in p).replace("_", "")
        words = o["text"].rstrip("\u2026").split()
        assert " ".join(said.split()).startswith(" ".join(words)), (o["text"], said)
        assert len(o["text"]) <= L.OPENING_CHARS + 1, o["text"]
    long = {"lines": [{"kind": "direction", "source": "_Night._"},
                      {"kind": "speech", "role": "A", "parts": [{"direction": "low"}, {"say": "word " * 40}]},
                      {"kind": "speech", "role": "B", "parts": [{"say": ". Who   _is_ it? "}]},
                      {"kind": "speech", "role": "A", "parts": [{"say": "Me--now."}]}]}
    got = L.opening_of(long)
    assert got[0]["role"] == "A" and got[0]["text"].endswith("\u2026") and len(got[0]["text"]) <= L.OPENING_CHARS + 1, got
    assert "word wor" not in got[0]["text"].replace("word word", ""), "a word is cut inside itself"
    assert got[1] == {"role": "B", "text": "Who is it?"} and len(got) == 2, got
    assert L.opening_of({"lines": long["lines"][3:]})[0]["text"] == "Me\u2014now.", "a double hyphen reads as a dash"


@case
def the_real_artifact_has_the_documented_shape():
    if not os.path.exists(os.path.join(L.OUT, "index.json")):
        print("  (no built library in out/plays-library; fixture shape only)")
        return
    built = json.load(open(os.path.join(L.OUT, "index.json")))
    # a library built with its phonemes (the publishable kind) must carry them for the shipped share
    idx = check_library(L.OUT, 1, C.MIN_PHONEME_SHARE if "phonemes" in built else 0.0)
    bundle = json.load(open(L.BUNDLE))["scripts"]
    have = {p["id"]: p for p in idx["plays"]}
    for s in bundle:
        assert s["id"] in have, f"bundled {s['id']} is missing from the library"
        assert have[s["id"]]["revision"] == s["revision"], f"{s['id']}: the library's text differs from the bundle's"
    assert idx["report"]["bundled_missing_from_library"] == []


@case
def a_volume_is_split_at_its_plays_with_stable_numbers():
    parts = P.split_volume(volume_text())
    assert [(n, t) for n, t, _ in parts] == [(1, "THE FIRST PLAY"), (2, "THE SECOND PLAY")], [(n, t) for n, t, _ in parts]
    assert "SHERIFF" in parts[0][2] and "COOK" not in parts[0][2] and "COOK" in parts[1][2]


@case
def a_volume_builds_to_numbered_plays_carrying_its_rights():
    plays = [dict(play(7, "The Collected Plays"), authors=[{"name": "Glaspell, Susan", "born": 1876, "died": 1948, "role": "author"}])]
    entries, report = L.build(plays, CTX, {"7": volume_text()}.get)
    assert [e["id"] for e in entries] == ["gut-7-1", "gut-7-2"], [e["id"] for e in entries]
    assert [e["title"] for e in entries] == ["The First Play", "The Second Play"]
    assert all(e["collection"] == "The Collected Plays" and e["rights"]["evidence"] for e in entries)
    assert report["volumes"] == 1 and report["split_clean"] == 2, report
    with tempfile.TemporaryDirectory() as d:
        L.write(entries, report, d)
        check_library(d)


@case
def a_volume_with_two_authors_is_held_not_split():
    two = dict(play(7, "The Collected Plays"))
    two["authors"] = two["authors"] + [{"name": "Cook, George Cram", "born": 1873, "died": 1924, "role": "author"}]
    entries, report = L.build([two], CTX, {"7": volume_text()}.get)
    assert entries == [] and report["volumes_held_not_one_author"] == 1, report


@case
def a_title_that_names_no_play_is_not_used():
    rec = {"authors": [{"name": "Dunsany, Lord"}], "translators": []}
    for bad in (None, "THE", "BY", "DISPOSITION OF CHARACTERS", "II.--THE FAN", "OR THE DOUBLE LIFE", "LORD DUNSANY"):
        assert L.volume_play_title(bad, rec) is None, bad
    assert L.volume_play_title("THE GODS OF THE MOUNTAIN", rec) == "The Gods of the Mountain"


@case
def a_role_read_out_of_a_cast_list_is_an_artifact():
    ent = lambda *names: {"title": "Hedda Gabler", "roles": [{"name": n, "lines": 9, "words": 9} for n in names]}
    assert L.role_artifact(ent("HEDDA", "MRS")) == "MRS"
    once = {"title": "Hedda Gabler", "roles": [{"name": "HEDDA GABLER", "lines": 1, "words": 40}]}
    assert L.role_artifact(once) == "HEDDA GABLER"
    eponymous = {"title": "Macbeth", "roles": [{"name": "MACBETH", "lines": 146, "words": 3000}]}
    assert L.role_artifact(eponymous) is None
    assert L.role_artifact(ent("HEDDA", "STROPHE I")) and L.role_artifact(ent("HEDDA", "MRS. ELVSTED")) is None
    # the Doctor printed "DR." (gut-70635-5, 23 speeches) speaks; a "DR" of a line or two is still an artifact
    assert L.role_artifact(ent("HEDDA", "DR")) is None
    assert L.role_artifact({"title": "Hedda Gabler", "roles": [{"name": "DR", "lines": 1, "words": 4}]}) == "DR"
    assert L.role_artifact(ent("HEDDA", "FOURTH SCENE")) == "FOURTH SCENE"


def dup_entry(eid, lines, volume=False, voices=2):
    words = [f"w{i}" for i in range(lines)]
    ent = {"id": eid, "title": "Same Play", "authors": [{"name": "Author, A"}],
           "roles": [{"name": f"R{k}", "lines": 9, "words": 9} for k in range(voices)],
           "lines": [{"kind": "speech", "role": "R0", "parts": [{"say": " ".join(words)}]}]}
    if volume:
        ent["collection"] = "A Volume"
    return ent


@case
def one_work_under_several_ids_is_kept_once_and_every_drop_is_listed():
    entries = [dup_entry("gut-9-3", 400, volume=True, voices=9), dup_entry("gut-5", 400), dup_entry("gut-2", 400)]
    kept, rows, _ = L.dedupe(entries)
    assert [e["id"] for e in kept] == ["gut-2"], "the single-play text with the lower id wins over a fuller volume play"
    assert sorted(r["dropped"] for r in rows) == ["gut-5", "gut-9-3"] and all(r["kept"] == "gut-2" for r in rows)
    kept, rows, _ = L.dedupe(entries, protect={"gut-5"})
    assert [e["id"] for e in kept] == ["gut-5"], "a bundled play is never the one dropped"


@case
def the_edition_with_full_speaker_names_and_verse_lines_is_kept():
    # real shapes: gut-2265 (Folio Hamlet: "BAR"/"HAM" beside "Enter Barnardo", "Hamlet", prose-run lines) and
    # gut-1524 (modern: "BARNARDO", "HAMLET", verse lines kept); the Folio has the fuller cast and the lower number
    folio = dup_entry("gut-2", 400, voices=9)
    folio["roles"][:2] = [{"name": "HAM", "lines": 9, "words": 9}, {"name": "BAR", "lines": 9, "words": 9}]
    folio["lines"] = [{"kind": "direction", "source": "Enter Barnardo and Hamlet."},
                      {"kind": "speech", "role": "HAM", "parts": folio["lines"][0]["parts"]}]
    modern = dup_entry("gut-5", 400, voices=3)
    modern["roles"][:2] = [{"name": "HAMLET", "lines": 9, "words": 9}, {"name": "BARNARDO", "lines": 9, "words": 9}]
    words = modern["lines"][0]["parts"][0]["say"].split()
    modern["lines"] = [{"kind": "direction", "source": "Enter Barnardo and Hamlet."},
                       {"kind": "speech", "role": "HAMLET", "parts": [{"say": " ".join(words[:200]) + "\n" + " ".join(words[200:])}]}]
    kept, rows, _ = L.dedupe([folio, modern])
    assert [e["id"] for e in kept] == ["gut-5"], [e["id"] for e in kept]
    assert rows[0]["dropped"] == "gut-2" and "edition" in rows[0]["reason"], rows
    kept, _, _ = L.dedupe([folio, modern], protect={"gut-2"})
    assert [e["id"] for e in kept] == ["gut-2"], "a bundled play is still never the one dropped"


@case
def different_plays_and_a_bundle_are_not_taken_for_duplicates():
    a, b = dup_entry("gut-1", 400), dup_entry("gut-2", 400)
    b["lines"][0]["parts"][0]["say"] = " ".join(f"z{i}" for i in range(400))
    bundle = dup_entry("gut-3", 4000)
    bundle["lines"][0]["parts"][0]["say"] += " " + a["lines"][0]["parts"][0]["say"]
    kept, rows, shared = L.dedupe([a, b, bundle])
    assert len(kept) == 3 and rows == [], rows
    assert shared == [["gut-1", "gut-2", "gut-3"]], "same title and author, different text: reported, kept"


def add_phonemes(d, skip=()):
    """Fixture phoneme files (Decision 078) for every play in the library at d, as build_play_phonemes writes
    them: one row per speech line with words, the index row pointing at its file, the report beside it."""
    idx = json.load(open(os.path.join(d, "index.json")))
    os.makedirs(os.path.join(d, "phonemes"), exist_ok=True)
    held = 0
    for p in idx["plays"]:
        if p["id"] in skip:
            held += 1
            continue
        s = json.load(open(os.path.join(d, p["path"])))["scripts"][0]
        rows = [{"id": l["id"], "t": PH.line_text(l), "us": "lˈIn"} for l in s["lines"]
                if l["kind"] == "speech" and PH.line_text(l)]
        json.dump(PH.phoneme_file(s, rows, "fixture"), open(os.path.join(d, "phonemes", f"{p['id']}.json"), "w"),
                  ensure_ascii=False)
        p["phonemes"] = f"phonemes/{p['id']}.json"
    idx["phonemes"] = {"format": 1, "g2p": "fixture", "dialects": ["us", "gb"], "report": "phonemes-report.json",
                       "plays": len(idx["plays"]) - held, "held_for_review": held}
    json.dump({"format": 1}, open(os.path.join(d, "phonemes-report.json"), "w"))
    json.dump(idx, open(os.path.join(d, "index.json"), "w"), ensure_ascii=False)


def sized_library(d, n, phonemes=True):
    """A library of n copies of the fixture play under distinct ids, for the archive tests."""
    entries, report = fixture_build()
    many = []
    for k in range(n):
        e = json.loads(json.dumps(entries[0]))
        e["id"] = f"gut-{1000 + k}"
        e["sort_name"] = f"play {k:04d}"
        many.append(e)
    L.write(many, report, d)
    if phonemes:
        add_phonemes(d)


@case
def the_archive_round_trips_a_library_byte_for_byte():
    with tempfile.TemporaryDirectory() as d:
        src, a, b, out = (os.path.join(d, x) for x in ("src", "a.tar.xz", "b.tar.xz", "out"))
        sized_library(src, C.MIN_PLAYS)
        A.pack(src, a)
        A.pack(src, b)
        assert open(a, "rb").read() == open(b, "rb").read(), "packing is not deterministic"
        assert A.unpack(a, out)["count"] == C.MIN_PLAYS
        assert open(os.path.join(out, "index.json"), "rb").read() == open(os.path.join(src, "index.json"), "rb").read()


@case
def a_library_below_the_floor_is_not_packed_or_unpacked():
    with tempfile.TemporaryDirectory() as d:
        src, a = os.path.join(d, "src"), os.path.join(d, "a.tar.xz")
        sized_library(src, 3)
        for fn in (lambda: A.pack(src, a),):
            try:
                fn()
            except AssertionError:
                break
            raise AssertionError("a 3-play library was packed")
        with tarfile.open(a, "w:xz") as tar:
            for name in ("index.json", "phonemes-report.json") + tuple(
                    f"{f}/{n}" for f in ("scripts", "phonemes") for n in sorted(os.listdir(os.path.join(src, f)))):
                tar.add(os.path.join(src, name), arcname="plays-library/" + name)
        try:
            A.unpack(a, os.path.join(d, "out"))
        except AssertionError:
            return
        raise AssertionError("a 3-play archive was unpacked")


@case
def an_archive_with_a_stray_or_climbing_member_is_refused():
    with tempfile.TemporaryDirectory() as d:
        src = os.path.join(d, "src")
        sized_library(src, C.MIN_PLAYS)
        for bad in ("plays-library/notes.txt", "../escape.json", "/abs/index.json"):
            a = os.path.join(d, "bad.tar.xz")
            with tarfile.open(a, "w:xz") as tar:
                tar.add(os.path.join(src, "index.json"), arcname="plays-library/index.json")
                tar.add(os.path.join(src, "index.json"), arcname=bad)
            try:
                A.unpack(a, os.path.join(d, "out"))
            except ValueError:
                continue
            raise AssertionError(f"an archive holding {bad} was unpacked")


@case
def phoneme_files_agree_with_the_index_and_their_scripts():
    entries, report = fixture_build()
    with tempfile.TemporaryDirectory() as d:
        L.write(entries, report, d)
        add_phonemes(d)
        idx = check_library(d, 1, 1.0)
        assert idx["plays"][0]["phonemes"] == "phonemes/gut-1.json"


@case
def a_broken_phoneme_set_fails_the_check():
    entries, report = fixture_build()

    def broken(fn):
        with tempfile.TemporaryDirectory() as d:
            L.write(entries, report, d)
            add_phonemes(d)
            fn(d)
            try:
                check_library(d)
            except (AssertionError, FileNotFoundError):
                return True
        return False

    def edit_file(d, f):
        path = os.path.join(d, "phonemes", "gut-1.json")
        doc = json.load(open(path))
        f(doc)
        json.dump(doc, open(path, "w"), ensure_ascii=False)

    def edit_index(d, f):
        path = os.path.join(d, "index.json")
        idx = json.load(open(path))
        f(idx)
        json.dump(idx, open(path, "w"), ensure_ascii=False)

    controls = {
        "a file the index does not name": lambda d: edit_index(d, lambda i: i["plays"][0].pop("phonemes")),
        "an index row whose file is gone": lambda d: os.remove(os.path.join(d, "phonemes", "gut-1.json")),
        "a line whose words differ from the script": lambda d: edit_file(d, lambda doc: doc["lines"][0].update(t="Other.")),
        "an out-of-date revision": lambda d: edit_file(d, lambda doc: doc.update(revision="0")),
        "a count that disagrees": lambda d: edit_index(d, lambda i: i["phonemes"].update(plays=5)),
        "no report": lambda d: os.remove(os.path.join(d, "phonemes-report.json")),
    }
    for name, fn in controls.items():
        assert broken(fn), f"the check passed a library with {name}"


@case
def writing_the_library_again_drops_its_stale_phonemes():
    entries, report = fixture_build()
    with tempfile.TemporaryDirectory() as d:
        L.write(entries, report, d)
        add_phonemes(d)
        L.write(entries, report, d)
        assert not os.path.exists(os.path.join(d, "phonemes")) and not os.path.exists(os.path.join(d, "phonemes-report.json"))
        check_library(d)


@case
def a_library_without_enough_phonemes_is_not_packed():
    with tempfile.TemporaryDirectory() as d:
        src = os.path.join(d, "src")
        sized_library(src, C.MIN_PLAYS, phonemes=False)
        try:
            A.pack(src, os.path.join(d, "a.tar.xz"))
        except AssertionError:
            pass
        else:
            raise AssertionError("a library without phonemes was packed")
        shutil.rmtree(src)
        sized_library(src, C.MIN_PLAYS, phonemes=False)
        add_phonemes(src, skip={f"gut-{1000 + k}" for k in range(C.MIN_PLAYS // 2)})
        try:
            A.pack(src, os.path.join(d, "a.tar.xz"))
        except AssertionError:
            return
        raise AssertionError("a library with phonemes for half its plays was packed")


def main():
    failed = 0
    for fn in CASES:
        try:
            fn()
        except (AssertionError, KeyError, StopIteration, FileNotFoundError, ValueError) as e:
            failed += 1
            print(f"FAIL {fn.__name__}: {e!r}")
    print(f"{len(CASES) - failed}/{len(CASES)} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
