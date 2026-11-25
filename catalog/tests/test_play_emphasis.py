"""play_emphasis: italic words inside a speech that are spoken (catalog DECISIONS 048, BACKLOG-LOOP B28).

    python3 tests/test_play_emphasis.py

Every sentence is a play's own, its file named. Mutation controls: tests/mutate_play_emphasis.py removes each guard in turn.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import play_corrections as PC
import play_emphasis as PE
import play_punctuation as PN
import script_parse as P

CASES = []


def case(fn):
    CASES.append(fn)
    return fn


def speech(text, role="ANNA", lid="L0001"):
    parts = P.split_parts(text)
    em = [k for k, p in enumerate(parts) if p.pop("_em", False)]
    return {"id": lid, "kind": "speech", "role": role, "parts": parts, **({"em": em} if em else {})}


def play(*lines, brackets=True, roles=("KNOX", "ORLANDO")):
    """A play that brackets its directions (or one that prints them in bare italics), holding the lines given."""
    more = [speech("(rising) Well, I _am_ then, if _you_ will." if brackets else "_rising._ Well, then.", roles[n % len(roles)], f"L{n:04d}") for n in range(100, 112)]
    lines = [l if isinstance(l, dict) else speech(l, lid=f"L{n:04d}") for n, l in enumerate(lines, 1)] + more
    return {"id": "gut-1", "revision": PC._revision(lines), "lines": lines, "roles": PC._roles(lines), "sections": [{"line": "L0001", "source": "ACT I"}]}


def said(text, **kw):
    """The first line of the play once mended: its spoken words, and its directions."""
    line = PE.mend(play(text, **kw))["lines"][0]
    return " ".join(p["say"] for p in line["parts"] if "say" in p), [p["direction"] for p in line["parts"] if "direction" in p]


def spoken(text, words, **kw):
    got = said(text, **kw)
    assert got == (words, []), got


def kept(text, direction, **kw):
    got = said(text, **kw)
    assert direction in got[1], got


BARE = {"brackets": False}


@case
def a_closed_word_inside_a_sentence_is_spoken_in_any_play():
    for kw in ({}, BARE):
        spoken("The way to hurt him is to hurt _you_.", "The way to hurt him is to hurt you .", **kw)        # gut-3820's shape
        spoken("Because you do not wholly _will_.", "Because you do not wholly will .", **kw)                # gut-66240-1
        spoken("You two _are_ Dodo birds!", "You two are Dodo birds!")                                       # gut-16635
        spoken("This must be for _him!_", "This must be for him!", **kw)                                     # gut-47560
        spoken("I'm a confirmed bachelor, ever since I met _you._", "I'm a confirmed bachelor, ever since I met you.", **kw)  # gut-41647-2
        spoken("You see _you_ love him.", "You see you love him.", **kw)


@case
def a_closed_word_opens_a_sentence_that_goes_on():
    spoken("I ain't been. _Why_ ain't you been?", "I ain't been. Why ain't you been?", **BARE)               # gut-70780
    spoken("_Somebody's_ sent me a ring.", "Somebody's sent me a ring.", **BARE)                             # gut-21849
    spoken("Like it? _You_, sir?", "Like it? You , sir?", **BARE)
    spoken("Ah! _that's_ all right.", "Ah! that's all right.", **BARE)                                       # gut-15744-2
    spoken("_Me?_ No, sir!", "Me? No, sir!", **BARE)                                                         # gut-58546-10


@case
def a_word_the_words_before_it_need_is_spoken_in_any_play():
    spoken("You mean a hundred _dollars_.", "You mean a hundred dollars .")
    spoken("His education at the court of _Savoy_ has refined him.", "His education at the court of Savoy has refined him.", **BARE)   # gut-38931
    spoken("Well, Mr. _Neverout_, you'll never be mad.", "Well, Mr. Neverout , you'll never be mad.", **BARE)  # gut-60186
    spoken("Cousin, I so love your _Palante_.", "Cousin, I so love your Palante .", **BARE)                  # gut-36234
    spoken("Well said, Mr. _Neverout_; go.", "Well said, Mr. Neverout ; go.", **BARE)
    spoken("'Tis the story of _The Survival of Thersites_, as told.", "'Tis the story of The Survival of Thersites , as told.", **BARE)  # gut-887


@case
def a_name_called_or_named():
    spoken("_Alexis_, speak or move.", "Alexis , speak or move.", **BARE)                                    # gut-12222
    spoken("The villain that kill'd Pompey, dear _Lucy_. Be pacified.", "The villain that kill'd Pompey, dear Lucy . Be pacified.", **BARE)
    kept("_Aside_, to him.", "Aside", **BARE)


@case
def words_in_quotation_marks():
    spoken("He said it: “_Always saving you money_.”", "He said it: “ Always saving you money .”", **BARE)   # gut-57598
    spoken("I no longer wish \"_Death!_\"", "I no longer wish \" Death! \"", **BARE)
    kept("He said: “_laughing_” and so on.", "laughing", **BARE)


@case
def only_a_play_that_brackets_its_directions_gives_a_bare_word():
    for text, words in [("For certain 'tis Frou Frou, _little_, I know.", "For certain 'tis Frou Frou, little , I know."),
                        ("Conscience now. _Suppose_ he came?", "Conscience now. Suppose he came?"),
                        ("Where is he? _Veto!_ Sit down.", "Where is he? Veto! Sit down."),
                        ("My _dear_ Judge!", "My dear Judge!"),
                        ("I know not where _is_ Charlie now.", "I know not where is Charlie now."),
                        ("_Au revoir_, Mr. Arbuthnot.", "Au revoir , Mr. Arbuthnot."),
                        ("I'm sick of _arguing_ with you.", "I'm sick of arguing with you.")]:
        spoken(text, words)
    for text, d in [("Conscience now. _Suppose_ he came?", "Suppose"), ("Where is he? _Veto!_ Sit down.", "Veto!"), ("My _dear_ Judge!", "dear"), ("I know not where _is_ Charlie now.", "is"),
                    ("_Au revoir_, Mr. Arbuthnot.", "Au revoir"), ("I'm sick of _arguing_ with you.", "arguing")]:
        kept(text, d, **BARE)


@case
def a_play_of_bare_business_or_of_no_brackets_is_not_one():
    business = [speech("_rising_ Well, then.", lid=f"L{n:04d}") for n in range(2, 12)]
    line = speech("My _dear_ Judge!")
    assert PE.mend(play(line, *business))["lines"][0] is line
    plain = [speech("Well, I _am_ here, if _you_ will.", lid=f"L{n:04d}") for n in range(2, 12)]
    few = {**play(line, *plain)}
    few["lines"] = [l for l in few["lines"] if not any("direction" in p for p in l["parts"])] + [line]
    assert PE.mend(few)["lines"][-1] is line


@case
def stage_business_stays_a_direction():
    for d in ("aside", "rising", "to John", "angrily", "more cordial than ever", "Exit", "Re-enter", "within", "kneels", "a pause", "They go"):
        kept(f"I will not. _{d}_ Come here.", d)
        kept(f"I will not. _{d}_ come here.", d, **BARE)
    kept("What I mean is, _rising_ that you must go.", "rising")
    kept("Hum, now _enters_ is the word.", "enters")


@case
def a_label_or_a_note_stays_a_direction():
    kept("Above what? _Ld. H._ Above all.", "Ld. H.")                                                        # gut-55922-102
    kept("Why so? _Colman 1768_ I know not.", "Colman 1768")                                                 # gut-22695-2
    kept("I give it to _Arm._, sir.", "Arm.")                                                                # gut-38931
    kept("Come, sit. _Knox_ I thank you.", "Knox")                                                           # gut-9077's shape
    kept("Come in. _Knox_ is here.", "Knox")
    kept("A] no more smell. l. 35. A _omits_ Is it so.", "omits")                                            # gut-10850
    kept("Read as in ed. 2 the _Folio_.", "Folio")                                                           # gut-45209-2
    spoken("_Orl_, speak.", "Orl , speak.")                                                                  # a part called by name


@case
def names_in_capitals_are_stage_business():
    kept("Away! UMANSKI _his_ Wife stand.", "his")
    kept("I know how _me_ LADIES go.", "me")
    kept("I know CHARLES RAY, a _professor of philosophy_. Go.", "professor of philosophy")                  # gut-68072
    spoken("I know _I_ am.", "I know I am.")
    spoken("They say _you_ I'll have.", "They say you I'll have.")


@case
def business_that_is_still_going_on():
    kept("Be it so. _Enter_ Rasni, with his Kings and _his_ Lords.", "his")                                  # gut-55769-102
    got = said("_Enter Guard._ Good. I love _him_. Go.")
    assert got == ("Good. I love him . Go.", ["Enter Guard."]), got


@case
def a_bracket_is_never_opened():
    line = {"id": "L0001", "kind": "speech", "role": "ANNA", "parts": [{"say": "Well [and"}, {"direction": P.Italic("you")}, {"say": "go on"}]}
    assert PE.mend(play(line))["lines"][0] is line
    line = {"id": "L0001", "kind": "speech", "role": "ANNA", "parts": [{"say": "Well and"}, {"direction": P.Italic("[you")}, {"say": "go on"}]}
    assert PE.mend(play(line))["lines"][0] is line
    line = {"id": "L0001", "kind": "speech", "role": "ANNA", "parts": [{"say": "Well and"}, {"direction": "you"}, {"say": "go on"}]}
    assert PE.mend(play(line))["lines"][0] is line, "a bracketed direction is never spoken"


@case
def a_mostly_italic_line_is_left():
    line = speech("Jump, _and fling about the pulpit in a fit of the spirit, and so_ desperately _you_ know.")
    assert PE.mend(play(line))["lines"][0] is line
    kept("_Smiling down at the great lady of the house_, and _you_ Sir.", "you")
    kept("_She is showily dressed_ , _my_ Lady.", "my")                                                      # gut-2195


@case
def a_long_span_or_a_lone_one_is_left():
    kept("He told me the same, _that is the thing I said to you before_.", "that is the thing I said to you before")
    kept("I read it in the story of _The Long Survival of Thersites Again_.", "The Long Survival of Thersites Again")
    line = speech("_You_")
    assert PE.mend(play(line))["lines"][0] is line
    kept("The receipt, please!” _She_ waves it.", "She", **BARE)                                             # gut-3403


@case
def the_words_are_carried_as_the_parsers_own_emphasis():
    line = PE.mend(play("I said _I_ know, and _you_, (rising) _you_ too."))["lines"][0]
    assert line["parts"] == [{"say": "I said"}, {"say": "I"}, {"say": "know, and"}, {"say": "you"}, {"say": ","}, {"direction": "rising"},
                             {"say": "you"}, {"say": "too."}] or line["em"], line
    for k in line["em"]:
        assert line["parts"][k]["say"].lower() in ("i", "you")
    # the offsets of the line's printed words do not move
    src = speech("Be _yourself_. I know.")
    text = lambda l: " ".join(next(iter(p.values())) for p in l["parts"])
    out = PE.mend(play(src))["lines"][0]
    assert text(out) == text(src) == "Be yourself . I know." and out["em"] == [1]
    assert type(out["parts"][1]["say"]) is str


@case
def a_word_the_print_joins_is_one_part_with_its_marks():
    out = PE.mend(play("_I_'ll come. _You_ know."))["lines"][0]
    assert out["parts"] == [{"say": "_I_'ll come."}, {"say": "You"}, {"say": "know."}] and out["em"] == [1], out    # gut-35305-3
    out = PE.mend(play("He is self-_made_. Sir."))["lines"][0]
    assert out["parts"] == [{"say": "He is self-_made_"}, {"say": ". Sir."}] and "em" not in out, out
    out = PE.mend(play("It was--_him_. But _me_."))["lines"][0]
    assert {"say": "him"} in out["parts"] and {"say": "me"} in out["parts"], "a dash is no letter"


@case
def emphasis_already_there_keeps_its_place():
    line = speech("You know _why_ I came. _You_ know _how_ it was.")
    assert line["em"]
    out = PE.mend(play(line))["lines"][0]
    assert [out["parts"][k]["say"] for k in out["em"]] == ["why", "You", "how"], out


@case
def the_sentences_own_stop_is_the_speakers():
    out = PN.mend(PE.mend(play("Come! Be _yourself_. I know.")))["lines"][0]
    assert " ".join(p["say"] for p in out["parts"]) == "Come! Be yourself . I know."


@case
def ids_roles_and_order_stay_and_a_play_with_none_is_the_same():
    e = play("Hello.", "(aside) Yes.")
    assert PE.mend(e) is e
    e = play("_rising_ Hello.")
    assert PE.mend(e) is e, "a direction alone is nothing to mend"
    e = play("Be _yourself_.", "Hello.")
    out = PE.mend(e)
    assert [l["id"] for l in out["lines"]] == [l["id"] for l in e["lines"]] and out["lines"][1] is e["lines"][1]
    assert [l["role"] for l in out["lines"]] == [l["role"] for l in e["lines"]] and out["sections"] == e["sections"]
    assert out["revision"] == PC._revision(out["lines"]) != e["revision"] and out["roles"] == PC._roles(out["lines"]) != e["roles"]
    assert PE.mend(out) is out, "mending twice changes nothing"


@case
def an_italic_direction_is_its_words():
    parts = P.split_parts("Go. _rising_ Come (aside) now.")
    assert parts == [{"say": "Go."}, {"direction": "rising"}, {"say": "Come"}, {"direction": "aside"}, {"say": "now."}]
    assert isinstance(parts[1]["direction"], P.Italic) and not isinstance(parts[3]["direction"], P.Italic)
    assert not isinstance(P.split_parts("Go. _(rising)_ Come")[1]["direction"], P.Italic) or PE.BRACKET.search(P.split_parts("Go. _(rising)_ Come")[1]["direction"])
    assert not isinstance(P.split_parts("Go. _ rising _ Come")[1]["direction"], P.Italic), "marks that pair badly say nothing"


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
