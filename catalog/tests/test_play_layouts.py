"""The second reader of stage plays (catalog/tools/play_layouts.py, BACKLOG-LOOP B16): one fixture a layout family, each
one the first reader (script_parse.parse) does not read clean, and the tests that hold a play.

    python3 tests/test_play_layouts.py

Every fixture is also a negative control: `second` asserts the first reader fails it. The words are made for the test.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import build_play_library as L
import play_layouts as PL
import script_parse as P

CASES = []


def case(fn):
    CASES.append(fn)
    return fn


LONG = "the harbor is cold tonight and nobody has lit the lamp on the pier"


def body(label, names=("Anna", "Peter", "Old Man"), n=24, between="\n\n", head="PERSONS OF THE PLAY\n\nAnna, a sailor.\nPeter, her brother.\nOld Man, a pilot.\n\n", scene="SCENE: A pier."):
    """n speeches a name, each set by label(name, words)."""
    out = [head + scene] if scene else [head]
    for i in range(n):
        for k, name in enumerate(names):
            out.append(label(name, f"Line {i} of mine, and {LONG}, {'is it not?' if k else 'you know.'}"))
    return "*** START OF THE PROJECT GUTENBERG EBOOK X ***\n\nTHE PIER\n\n" + between.join(out) + "\n\nCURTAIN\n"


def said(line):
    return " ".join(p["say"] for p in line["parts"] if "say" in p)


def speeches(r):
    return [l for l in r["lines"] if l["kind"] == "speech"]


def second(raw, title="The Pier", first_fails=True):
    """The second reader's clean result. `first_fails`: the first reader does not read this text clean."""
    if first_fails:
        assert not P.parse(raw, "stage", title).get("clean"), "the first reader reads this already: not a control"
    r = PL.parse(raw, title)
    assert r and r.get("clean"), (r and (r.get("issues"), r.get("leaks")[:3], r.get("unclassified", [])[:3]))
    return r


def roles(r):
    return {x["name"]: x["lines"] for x in r["roles"]}


@case
def mixed_case_names_alone_on_a_line():
    r = second(body(lambda n, w: f"{n}\n{w}"))
    assert r["layout"] == "mixed_own" and roles(r) == {"ANNA": 24, "PETER": 24, "OLD MAN": 24}, (r["layout"], roles(r))
    assert said(speeches(r)[1]).startswith("Line 0 of mine")


@case
def italic_names_alone_over_a_blank_line():
    r = second(body(lambda n, w: f"_{n}_.\n\n  {w}"))
    assert roles(r) == {"ANNA": 24, "PETER": 24, "OLD MAN": 24}, roles(r)


@case
def names_between_marks():
    for o, c in (("=", "="), ("+", "+"), ("{", "}")):
        r = second(body(lambda n, w: f"{o}{n}.{c} {w}"))
        assert roles(r) == {"ANNA": 24, "PETER": 24, "OLD MAN": 24}, (o, roles(r))
    r = second(body(lambda n, w: f"{{{n}}} (_Angrily._) {w}"))
    assert speeches(r)[0]["parts"][0] == {"direction": "Angrily."}, speeches(r)[0]["parts"]


@case
def a_dash_after_the_name():
    for dash in ("--", "—"):
        r = second(body(lambda n, w: f"{n.upper()}{dash}[_To Peter._] {w}"))
        assert roles(r) == {"ANNA": 24, "PETER": 24, "OLD MAN": 24}, roles(r)
        assert speeches(r)[3]["parts"][0] == {"direction": "To Peter."}, speeches(r)[3]


@case
def a_dash_after_an_italic_name():
    r = second(body(lambda n, w: f"_{n}_—{w}"))
    assert roles(r) == {"ANNA": 24, "PETER": 24, "OLD MAN": 24}, roles(r)


@case
def a_listed_name_and_a_space():
    r = second(body(lambda n, w: f"{n} {w}", names=("Anna", "Peter")))
    assert r["layout"] == "mixed_space" and roles(r) == {"ANNA": 24, "PETER": 24}, (r["layout"], roles(r))


@case
def a_label_direction_printed_over_two_lines():
    r = second(body(lambda n, w: f"{n.upper()}--[_Looking at the lamp for a long while, then at the\nwater under the pier._] {w}"))
    assert all(len(l["parts"]) == 2 for l in speeches(r)), speeches(r)[0]["parts"]


@case
def the_same_speaker_goes_on_after_a_direction():
    def label(n, w):
        return f"{n.upper()}.\n\n{w}" + ("\n\n[_She lifts the lamp._]\n\nAnd I tell you I will wait here for him." if n == "Anna" else "")
    r = second(body(label))
    assert roles(r)["ANNA"] == 48, roles(r)
    assert [said(l) for l in speeches(r) if l["role"] == "ANNA"][1] == "And I tell you I will wait here for him."
    assert r["lines"][2]["kind"] == "direction", r["lines"][2]


@case
def a_direction_that_gives_the_voice_to_another_is_not_a_continuation():
    raw = body(lambda n, w: f"{n.upper()}.\n\n{w}")
    raw = raw.replace("PETER.\n\nLine 3", "[_Old Man is heard singing off stage._]\n\nOh, the ships come in with me and you.\n\nPETER.\n\nLine 3", 1)
    r = PL.parse(raw, "The Pier")
    assert "Oh, the ships come in with me and you." in r["unclassified"], r["unclassified"]


@case
def a_plain_direction_is_never_spoken():
    raw = body(lambda n, w: f"_{n}_.\n\n  {w}" + ("\n\nAnna stands still again and looks at the water." if n == "Peter" else ""))
    r = second(raw)
    assert not any("stands still again" in said(l) for l in speeches(r))
    assert sum("stands still again" in l["source"] for l in r["lines"] if l["kind"] == "direction") == 24


@case
def a_wife_is_not_her_husband():
    """"MERCADET" and "MME. MERCADET" were one role in a first try; only MR / THE forms are one speaker."""
    r = second(body(lambda n, w: f"_{n}_.\n\n  {w}", names=("Denham", "Mrs. Denham", "The Maid"), head="PERSONS\n\nDenham, a painter.\nMrs. Denham.\nThe Maid.\n\n"))
    assert set(roles(r)) == {"DENHAM", "MRS. DENHAM", "THE MAID"}, roles(r)


@case
def a_name_in_italics_is_spoken_not_a_direction():
    r = second(body(lambda n, w: f"_{n}_.\n\n  I love thee well. _Peter_! come and say as you know. {w}"))
    assert said(speeches(r)[0]).startswith("I love thee well. Peter ! come") and speeches(r)[0].get("em") == [1], speeches(r)[0]


@case
def an_unclosed_direction_is_not_spoken():
    r = second(body(lambda n, w: f"_{n}_.\n\n  {w}   [_Exit_ PETER, _through window_, R."))
    assert all(p.get("say", "").find("PETER") < 0 for l in speeches(r) for p in l["parts"]), speeches(r)[0]["parts"]
    assert speeches(r)[0]["parts"][-1]["direction"].startswith("Exit"), speeches(r)[0]["parts"]


@case
def every_part_is_a_slice_of_its_source():
    r = second(body(lambda n, w: f"_{n}_.\n\n  {w} [12] So I say, {{4}} and _never_ shall I go. [_Exit._"))
    flat = lambda s: " ".join(s.split())
    for l in speeches(r):
        src, at = flat(l["source"]), 0
        for p in l["parts"]:
            k = src.find(flat(next(iter(p.values()))), at)
            assert k >= 0, (p, src)
            at = k
        assert "So I say, and" in said(l) and not any("12" in x or "4" in x for x in [p.get("direction", "") for p in l["parts"]]), l["parts"]


@case
def a_shared_verse_line_prints_its_second_speaker_on_the_line():
    def label(n, w):
        return f"{n.upper()}.\n\n  {w}" if n != "Peter" else "PETER.             There is no wise man\n  And I will tell you that there is none here."
    raw = body(label)
    first = P.parse(raw, "stage", "The Pier")
    r = second(raw, first_fails=False)
    assert roles(r) == {"ANNA": 24, "PETER": 24, "OLD MAN": 24}, (roles(r), roles(first))


@case
def no_printed_word_of_a_speech_is_lost():
    """A label printed on the line in a play whose labels mostly stand alone lost its first line's words in a first try
    (gut-1192: "Business! And so must time, my friend, be close pursued" went missing)."""
    def label(n, w):
        return f"{n.upper()}. Pursued, my friend, and {w}\nand more of it on the second line here." if n == "Peter" else f"{n.upper()}.\n\n  {w}"
    r = second(body(label, names=("Anna", "Peter", "Old Man", "Mate", "Cook", "Pilot")), first_fails=False)
    assert r["layout"] == "caps_own", r["layout"]
    assert all(said(l).startswith("Pursued, my friend") and said(l).endswith("second line here.") for l in speeches(r) if l["role"] == "PETER"), [said(l) for l in speeches(r)][:3]
    assert not any(PL._lost_words(l) for l in speeches(r))


@case
def a_publishers_colophon_and_a_transcribers_list_are_not_spoken():
    raw = body(lambda n, w: f"+{n}.+ {w}")
    raw += "\n+Printed by+\nBALLANTYNE & COMPANY LTD\nLondon\n\nTranscriber's Note: changes made.\n\n+Anna.+ Page 9, \"treadding\" changed to \"treading\".\n"
    r = second(raw)
    assert not any("BALLANTYNE" in said(l) or "treadding" in said(l) for l in speeches(r))


@case
def unread_labels_hold_the_play():
    """A label that is not accepted hands its words to the speaker before it: a play with too many is held."""
    base = body(lambda n, w: f"_{n}_: {w}", n=40)
    assert PL.parse(base, "The Pier")["clean"]
    for k in range(6):
        base = base.replace(f"_Anna_: Line {k + 2} ", f"_{'Zeb Trew Marl Voss Hale Wick'.split()[k]} o' the mill_: Line {k + 2} ", 1)
    lines = PL.parse(base, "The Pier")
    assert not lines["clean"] and "unread_labels" in lines["issues"] or set(roles(lines)) >= {"ZEB O' THE MILL"}, (lines["issues"], lines["leaks"])
    spoken_over = body(lambda n, w: f"{n.upper()}.\n\n  {w[:8].strip()} she comes here to me\n  And I will wait for her.", n=40)
    for k in range(6):
        spoken_over = spoken_over.replace(f"ANNA.\n\n  Line {k + 12} ", f"ANNA.\n\n  She is here.\n  Peter. Not yet, I say, nor ever.\n  Line {k + 12} ", 1)
    held = PL.parse(spoken_over, "The Pier")
    assert "unread_labels" in held["issues"] and not held["clean"], held["issues"]


@case
def a_recurring_label_nobody_reads_holds_the_play():
    """"NO." six times at the head of a paragraph: Nora, or the word. Neither is guessed."""
    raw = body(lambda n, w: f"{n.upper()}. {w}")
    for k in range(6):
        raw = raw.replace(f"PETER. Line {k + 3} ", f"NO. Line {k + 3} ", 1)
    r = PL.parse(raw, "The Pier")
    assert not r["clean"] and "recurring_label_unread" in r["issues"], r["issues"]


@case
def a_cast_list_is_not_the_first_speech():
    raw = body(lambda n, w: f"_{n}_.\n\n  {w}", head="")
    raw = raw.replace("SCENE: A pier.", "_Anna_\n\nHerr Ebeling, a lawyer.\nFrau von Yburg.\nMargot, her daughter.\nThe Servant.", 1)
    r = second(raw)
    assert said(speeches(r)[0]).startswith("Line 0"), said(speeches(r)[0])


@case
def two_plays_in_one_text_are_held():
    one = body(lambda n, w: f"_{n}_.\n\n  {w}")
    two = body(lambda n, w: f"_{n}_.\n\n  {w}", names=("Rosa", "Hugh", "Miller"), head="PERSONS OF THE PLAY\n\nRosa.\nHugh.\nMiller.\n\n")
    r = PL.parse(one + "\n\n" + two, "Two")
    assert r and not r["clean"] and set(r["issues"]) & {"several_plays_in_one_text", "two_casts"}, r and r["issues"]


@case
def two_casts_one_after_the_other_are_two_plays():
    """No cast list or act heading divides them; hardly anyone who speaks before the middle speaks after it."""
    one = body(lambda n, w: f"_{n}_.\n\n  {w}", head="", scene="SCENE: A pier.")
    two = body(lambda n, w: f"_{n}_.\n\n  {w}", names=("Rosa", "Hugh", "Miller"), head="", scene="SCENE: A mill.").split("THE PIER\n\n", 1)[1]
    r = PL.parse(one.replace("CURTAIN", "") + two, "Two")
    assert not r["clean"] and "two_casts" in r["issues"], r["issues"]


@case
def a_contents_page_and_a_cast_listed_by_act_are_one_play():
    raw = body(lambda n, w: f"{n.upper()}. {w}", head="CONTENTS\n\nACT I\n\nACT II\n\nPERSONS\n\nANNA.\n\nPETER.\n\n", scene="ACT I\n\nA pier.")
    raw = raw.replace("ANNA. Line 12", "ACT II\n\nPERSONS IN THE PLAY\n\nANNA.\n\nPETER.\n\nOLD MAN.\n\nThe same.\n\nANNA. Line 12", 1)
    r = second(raw, first_fails=True)
    assert "several_plays_in_one_text" not in r["issues"]


@case
def a_preface_under_its_heading_is_not_another_play():
    pre = "PREFACE\n\n" + "\n\n".join("This preface says a good deal about the theatre and the people in it, at length. " * 8 for _ in range(30))
    raw = body(lambda n, w: f"_{n}_.\n\n  {w}").replace("THE PIER\n\n", "THE PIER\n\n" + pre + "\n\n", 1)
    r = second(raw)
    assert "mostly_set_aside" not in r["issues"]


@case
def another_language_is_held():
    raw = body(lambda n, w: f"_{n}_.\n\n  El hombre de la casa no es el que yo creo, pero por las calles se ve que los niños van con una flor.")
    r = PL.parse(raw, "Pier")
    assert not r["clean"] and "not_english" in r["issues"], r["issues"]


@case
def a_volume_is_divided_by_its_contents_list():
    def play(title, by, names):
        return f"{title}\n\n_By {by}_\n\n" + body(lambda n, w: f"{n.upper()}. {w}", names=names, head="CHARACTERS\n\n" + "\n\n".join(x.upper() for x in names) + "\n\n").split("THE PIER\n\n", 1)[1]
    raw = ("*** START OF THE PROJECT GUTENBERG EBOOK X ***\n\nPLAYS OF THE SEA\n\nCONTENTS\n\n"
           "THE LAMP ............ 1\nTHE ROPE ............ 20\nNOTES ............ 40\n\n"
           + play("THE LAMP", "Alice Brown", ("Anna", "Peter", "Mate")) + "\n\n" + play("THE ROPE", "JOHN GREY", ("Rosa", "Hugh", "Cook")))
    got = PL.split_by_contents(raw)
    assert [(n, t, w) for n, t, w, _ in got] == [(1, "THE LAMP", "Alice Brown"), (2, "THE ROPE", "John Grey")], [x[:3] for x in got]


def record(pid, title, authors=(), translators=(), subjects=("Drama",)):
    return {"id": f"gut-{pid}", "title": title, "authors": [{"name": a, "born": None, "died": None, "role": "author"} for a in authors],
            "translators": list(translators), "year": None, "year_basis": None, "source_url": f"https://www.gutenberg.org/ebooks/{pid}",
            "rights": {"text": "Public domain in the USA.", "src": f"https://www.gutenberg.org/ebooks/{pid}.rdf"}, "subjects": list(subjects),
            "shelves": [], "librivox": [], "evidence": [{"claim": "Public domain in the USA.", "src": f"https://www.gutenberg.org/ebooks/{pid}.rdf"}]}


CTX = {"renewals": {}, "takedowns": {}, "today": __import__("datetime").date(2026, 11, 24)}


def volume_text():
    def play(title, by, names):
        return f"{title}\n\n_By {by}_\n\n" + body(lambda n, w: f"{n.upper()}. {w}" + " " + " ".join(names) + ".", names=names, head="CHARACTERS\n\n" + "\n\n".join(x.upper() for x in names) + "\n\n").split("THE PIER\n\n", 1)[1]
    return ("*** START OF THE PROJECT GUTENBERG EBOOK X ***\n\nPLAYS OF THE SEA\n\nCONTENTS\n\nTHE LAMP ............ 1\nTHE ROPE ............ 20\n\n"
            + play("THE LAMP", "Alice Brown", ("Anna", "Peter", "Mate")) + "\n\n" + play("THE ROPE", "JOHN GREY", ("Rosa", "Hugh", "Cook")))


@case
def a_volume_by_several_authors_credits_each_play_to_the_author_it_prints():
    entries, report = L.build([record(7, "Plays of the Sea", ())], CTX, {"7": volume_text()}.get)
    assert {(e["id"], e["title"], e["authors"][0]["display"]) for e in entries} == {
        ("gut-7-101", "The Lamp", "Alice Brown"), ("gut-7-102", "The Rope", "John Grey")}, [(e["id"], e["title"], e["authors"]) for e in entries]
    silent = volume_text().replace("_By Alice Brown_\n\n", "").replace("_By JOHN GREY_\n\n", "")
    entries, report = L.build([record(7, "Plays of the Sea", ())], CTX, {"7": silent}.get)
    assert not entries and report["failures"].get("volume_author_not_printed") == 2, report["failures"]


@case
def the_second_reader_never_displaces_the_first():
    """A first-reader play keeps its id and revision whatever the second reader finds in the same works."""
    one = body(lambda n, w: f"{n.upper()}. {w}", head="", scene="SCENE: A pier.")
    alone, _ = L.build([record(1, "The Pier", ("Brown, A.",))], CTX, {"1": one}.get)
    again = body(lambda n, w: f"_{n}_.\n\n  {w}", n=60)
    both, report = L.build([record(1, "The Pier", ("Brown, A.",)), record(2, "The Pier", ("Brown, A.",))], CTX, {"1": one, "2": again}.get)
    assert len(alone) == 1 and [(e["id"], e["revision"]) for e in both] == [(e["id"], e["revision"]) for e in alone], [(e["id"]) for e in both]


@case
def what_is_not_a_play_is_held_with_its_evidence():
    prose = "*** START OF THE PROJECT GUTENBERG EBOOK X ***\n\n" + "\n\n".join(f"Chapter talk {i}: " + LONG + " and so on." for i in range(200))
    rows = [record(3, "Punch, or the London Charivari, Volume 1"), record(4, "Essays on the Stage", subjects=("Drama -- History and criticism", "PN")),
            record(5, "The Novel of the Pier", subjects=("Drama",))]
    entries, report = L.build(rows, CTX, {"3": prose, "4": prose, "5": prose}.get)
    held = {r["id"]: r for r in report["_held"]["held"]}
    assert not entries and report["failures"] == {"not_a_play": 3}, report["failures"]
    assert "periodical" in held["gut-3"]["evidence"] and "History and criticism" in held["gut-4"]["evidence"] and "0%" in held["gut-5"]["evidence"], held


@case
def a_mark_that_names_no_play_is_never_a_title():
    r = record(9, "Works", ("Brown, A.",))
    for bad in ("COMEDY", "PERSONAE", "ACTVS I", "APPENDICES", "CAST OF CHARACTERS", "FIRST INTERLUDE", "AN OUTLINE OF THE PLOT", "EVERYMAN'S LIBRARY"):
        assert L.second_title(bad, r) is None, bad
    assert L.second_title("THE TRAGEDY OF RICHARD II", r) == "The Tragedy of Richard II"
    assert L.second_title("MCDONOUGH'S WIFE", r) == "McDonough's Wife"
    assert L.second_title("“WHICH, O LORD, IS WISEST?”", r) == "“Which, O Lord, Is Wisest?”"


@case
def a_latin_1_file_keeps_its_letters():
    import tempfile
    with tempfile.NamedTemporaryFile(suffix=".txt") as f:
        f.write("THÉRÈSE. Voilà.".encode("latin-1"))
        f.flush()
        assert P.read_text(f.name) == "THÉRÈSE. Voilà."


@case
def a_published_play_with_lost_letters_is_mended_only_when_its_lines_stay():
    good = body(lambda n, w: f"{n.upper()}. Thérèse, {w}", head="", scene="SCENE: A pier.")
    lost = good.replace("é", "�").replace("è", "�")
    rec = [record(1, "The Pier", ("Brown, A.",))]
    was, _ = L.build(rec, CTX, {"1": lost}.get)
    now, _ = L.build(rec, CTX, {"1": good}.get, read_as_published={"1": lost}.get)
    assert [l["id"] for l in now[0]["lines"]] == [l["id"] for l in was[0]["lines"]] and "Thérèse" in said(speeches(now[0])[0])
    moved_good = good.replace("PETER. ", "PÉTER. ")
    moved_lost = moved_good.replace("é", "�").replace("è", "�").replace("É", "�")
    was, _ = L.build(rec, CTX, {"1": moved_lost}.get)
    now, _ = L.build(rec, CTX, {"1": moved_good}.get, read_as_published={"1": moved_lost}.get)
    assert now[0]["revision"] == was[0]["revision"], "a play whose lines would move is not rewritten"


def main():
    failed = 0
    for fn in CASES:
        try:
            fn()
        except (AssertionError, KeyError, StopIteration, IndexError, TypeError, ValueError) as e:
            failed += 1
            print(f"FAIL {fn.__name__}: {e!r}"[:600])
    print(f"{len(CASES) - failed}/{len(CASES)} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
