"""The play-phoneme rules, the correction file and the published phoneme file (Decision 078).

    python3 tests/test_play_phonemes.py                       # stdlib cases (run_all.sh, CI)
    .venv-phonemes/bin/python tests/test_play_phonemes.py     # also the misaki cases

Every lexicon here is a fixture: the rules are tested against words the fixture knows, never against
which plays or words the real library holds. The misaki cases run only where misaki is installed
(catalog/.venv-phonemes); elsewhere they print SKIP.
"""
import importlib.util
import json
import os
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import play_phonemes as PH

CASES = []


def case(fn):
    CASES.append(fn)
    return fn


LEX = {"strained": "stɹˈAnd", "love": "lˈʌv", "over": "ˈOvəɹ", "on": "ˌɔn", "it": "ɪt", "have": "hæv",
       "upon": "əpˈɑn", "believe": "bəlˈiv", "know": "nˈO", "see": "sˈi", "should": "ʃˌʊd", "deny": "dənˈI",
       "aye": "ˈI", "cafe": "kæfˈA", "good": "ɡˈʊd", "natured": "nˈAʧəɹd", "would": "wˈʊd", "lived": "lˈɪvd",
       "go": "ɡˈO", "curse": "kˈɜɹs", "jacob": "ʤˈAkəb", "self": "sˈɛlf", "nothing": "nˈʌθɪŋ", "prithee": "pɹˈɪði",
       "joined": "ʤˈYnd", "young": "jˈʌŋ", "will": "wˈɪl", "royal": "ɹˈYəl", "gave": "ɡˈAv", "thou": "ðˈW",
       "stop": "stˈɑp", "wait": "wˈAt", "every": "ˈɛvɹi", "coming": "kˈʌmɪŋ", "round": "ɹˈWnd", "willful": "wˈɪlfəl",
       "shown": "ʃˈOn", "ain't": "ˈAnt", "you'll": "jul", "overcome": "ˌOvəɹkˈʌm", "to": "tə", "say": "sˈA",
       "recompense": "ɹˈɛkəmpˌɛns", "gypsy": "ʤˈɪpsi", "fallen": "fˈɔlən"}


def known(w):
    return LEX.get(w) or LEX.get(w.lower()) if w else None


def derived(word):
    r = PH.derive(word, known)
    return r and r[0]


@case
def a_line_is_keyed_as_the_clients_key_it():
    # js/plays-core.js spokenText joins the said parts with a space; kokoro-voice.js keyOf drops "_" and folds space
    line = {"kind": "speech", "parts": [{"say": "Come _here_,\n  now."}, {"direction": "aside"}, {"say": "Quickly!"}]}
    assert PH.line_text(line) == "Come here, now. Quickly!", PH.line_text(line)
    assert PH.line_text({"kind": "speech", "parts": [{"direction": "exit"}]}) == ""


@case
def normalizing_spaces_dashes_and_says_regnal_numbers():
    assert PH.normalize("Yes--no—maybe") == "Yes — no — maybe"
    assert PH.normalize("the ſame Æsop’s “tale”") == "the same Aesop's \"tale\""
    assert PH.normalize("King Henry IV and St. John") == "King Henry the Fourth and Saint John"
    assert PH.normalize("Henry I said Act V") == "Henry I said Act V", "a lone I and an act number stay"


@case
def elisions_resolve_to_known_words():
    assert derived("strain'd") == "stɹˈAnd"
    assert derived("lov'd") == "lˈʌvd", derived("lov'd")
    assert derived("stopp'd") is None or derived("stopp'd").endswith("t")
    assert derived("wait'd") == "wˈAtɪd", "a past after t is -ɪd"
    assert derived("o'er") == "ˈOvəɹ"
    assert derived("on't") == "ˌɔn ɪt"
    assert derived("wou'd") == "wˈʊd"
    assert derived("liu'd") == "lˈɪvd", "an elision with an early-modern u for v"
    assert derived("nothin'") == "nˈʌθɪŋ"
    assert derived("Pr'ythee") == "pɹˈɪði"
    assert derived("gav'st") == "ɡˈAvst"
    assert derived("'tis") == "tˈɪz" and PH.derive("'twere", known, "gb")[0] == "twˈɜː"
    assert derived("ev'ry") == "ˈɛvɹi" and derived("fall'n") == "fˈɔlən", "a dropped e"
    assert derived("comin") == "kˈʌmɪŋ" and derived("comin'") == "kˈʌmɪŋ", "a dropped g"
    assert derived("roun'") == "ɹˈWnd" and derived("o'ercome") == "ˌOvəɹkˈʌm" and derived("t'say") == "tə sˈA"
    assert derived("aint") == "ˈAnt" and derived("youll") == "jul", "a contraction printed without its apostrophe"


@case
def early_modern_spellings_resolve_only_to_known_words():
    assert derived("haue") == "hæv"
    assert derived("vpon") == "əpˈɑn"
    assert derived("beleeue") == "bəlˈiv"
    assert derived("Iacob") == "ʤˈAkəb"
    assert derived("selfe") == "sˈɛlf"
    assert derived("ioyned") == "ʤˈYnd"
    assert derived("yong") == "jˈʌŋ"
    assert derived("wil") == "wˈɪl"
    assert derived("Royall") == "ɹˈYəl"
    assert derived("wilful") == "wˈɪlfəl" and derived("shewn") == "ʃˈOn" and derived("gipsy") == "ʤˈɪpsi"
    assert derived("recompence") == "ɹˈɛkəmpˌɛns"
    assert derived("Gaveston") is None, "a name no rule reaches is left for the dictionary or the guesser"


@case
def archaic_endings_and_ied_are_built_from_the_stem():
    assert derived("knowest") == "nˈOɪst"
    assert derived("seest") == "sˈiɪst", "see-est, two syllables"
    assert derived("shouldst") == "ʃˌʊdst"
    assert derived("goeth") == "ɡˈOɪθ"
    assert derived("loveth") == "lˈʌvɪθ"
    assert derived("denied") == "dənˈId"
    assert derived("denies") == "dənˈIz"
    assert derived("cursèd") == "kˈɜɹsɪd", "a marked -èd is a said syllable"


@case
def capitals_accents_punctuation_and_compounds():
    assert derived("Ay") == "ˈI"
    assert derived("café") == "kæfˈA"
    assert derived("Ay!") == "ˈI", "a token carrying its punctuation"
    assert derived("goodnatured") == "ɡˈʊdnˈAʧəɹd"
    assert derived("Goodnatured") == "ɡˈʊdnˈAʧəɹd" or derived("Goodnatured") is None
    assert derived("xyzzy") is None


@case
def endings_follow_the_last_sound():
    assert PH.past_ending("wˈAt") == "ɪd" and PH.past_ending("stˈɑp") == "t" and PH.past_ending("lˈʌv") == "d"
    assert PH.possessive("Paramore's") == ("Paramore", "'s") and PH.possessive("Jones'") == ("Jone", "s'")
    assert PH.possessive("it") is None
    assert PH.possessive_ending("ʤˈOnz") == "ɪz" and PH.possessive_ending("bˈɑb") == "z"
    assert PH.possessive_ending("dʒˈæk") == "s" and PH.possessive_ending("x", plural=True) == ""


@case
def arpabet_converts_to_misaki_and_an_approximate_british_form():
    assert PH.arpa_to_misaki("L EH1 N ER0 D".split()) == "lˈɛnəɹd"
    assert PH.arpa_to_misaki("S IH1 L V IY0 AH0".split()) == "sˈɪlviə"
    assert PH.us_to_gb("lˈɛnəɹd") == "lˈɛnəd"
    assert PH.us_to_gb("pˈɛɹəmˌɔɹ") == "pˈɛɹəmˌɔː", "an r before a vowel stays"
    assert PH.us_to_gb("ɡˈO kˈæt") == "ɡˈQ kˈat"
    assert set(PH.us_to_gb("ʧˈɑɹtəɹɪs ɡˈOɪŋ ɹˈɪTᵻn")) <= PH.VOCAB["gb"] | PH.PUNCT


@case
def cmudict_reads_first_pronunciations_and_drops_comments():
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "c.dict")
        open(p, "w").write("leonard L EH1 N ER0 D\nleonard(2) L IY1 AH0 N ER0 D\naalen AE1 L AH0 N # place, german\n")
        assert PH.load_cmudict(p) == {"leonard": ["L", "EH1", "N", "ER0", "D"], "aalen": ["AE1", "L", "AH0", "N"]}


def corrections(doc):
    d = tempfile.mkdtemp()
    p = os.path.join(d, "c.json")
    json.dump(doc, open(p, "w"), ensure_ascii=False)
    return PH.load_corrections(p)


@case
def the_correction_file_loads_and_a_plays_entry_wins():
    c = corrections({"format": 1, "words": {"Gaveston": {"ps": "ɡˈævəstən"}, "Mistris": {"like": "mistress"},
                                            "Monsieur": {"us": "məsjˈɜɹ", "gb": "məsjˈɜː"}},
                     "plays": {"gut-1": {"gaveston": {"ps": "ɡəvˈɛstən"}}}})
    assert PH.correction_for(c, "gut-2", "GAVESTON", "us") == ("ps", "ɡˈævəstən")
    assert PH.correction_for(c, "gut-1", "Gaveston", "us") == ("ps", "ɡəvˈɛstən")
    assert PH.correction_for(c, "gut-2", "mistris", "gb") == ("like", "mistress")
    assert PH.correction_for(c, "gut-2", "Monsieur", "gb") == ("ps", "məsjˈɜː")
    assert PH.correction_for(c, "gut-2", "Hamlet", "us") is None


@case
def a_bad_correction_is_refused():
    for bad in ({"format": 1, "words": {"x": {"ps": "x@y"}}}, {"format": 1, "words": {"x": {"say": "y"}}},
                {"format": 1, "words": {"x": {"like": " "}}}, {"format": 2, "words": {}},
                {"format": 1, "words": {"x": {"ps": ""}}}):
        try:
            corrections(bad)
        except ValueError:
            continue
        raise AssertionError(f"accepted {bad}")


@case
def the_shipped_correction_file_loads():
    c = PH.load_corrections(os.path.join(os.path.dirname(__file__), "..", "plays", "phoneme-corrections.json"))
    assert isinstance(c["words"], dict) and isinstance(c["plays"], dict)


SCRIPT = {"id": "gut-1", "revision": "abc", "lines": [
    {"id": "L0001", "kind": "speech", "role": "A", "parts": [{"say": "Come in."}]},
    {"id": "L0002", "kind": "direction", "source": "He enters."},
    {"id": "L0002a", "kind": "speech", "role": "B", "parts": [{"direction": "aside"}, {"say": "Not _now_."}]},
    {"id": "L0003", "kind": "speech", "role": "A", "parts": [{"say": "—"}]}]}


def good_file():
    return PH.phoneme_file(SCRIPT, [{"id": "L0001", "t": "Come in.", "us": "kˌʌm ˈɪn."},
                                    {"id": "L0002a", "t": "Not now.", "us": "nˌɑt nˈW.", "gb": "nˌɒt nˈW."}], "test")


@case
def a_phoneme_file_agrees_with_its_script():
    PH.check_phoneme_file(good_file(), SCRIPT)


@case
def a_broken_phoneme_file_is_refused():
    def broken(fn):
        d = json.loads(json.dumps(good_file()))
        fn(d)
        return d
    controls = {
        "text differs": broken(lambda d: d["lines"][0].update(t="Come out.")),
        "a symbol Kokoro cannot read": broken(lambda d: d["lines"][0].update(us="k@m")),
        "a line missing": broken(lambda d: d["lines"].pop(0)),
        "gb repeats us": broken(lambda d: d["lines"][1].update(gb=d["lines"][1]["us"])),
        "an old revision": broken(lambda d: d.update(revision="old")),
        "a direction line": broken(lambda d: d["lines"].append({"id": "L0002", "t": "He enters.", "us": "hi"})),
        "an empty string": broken(lambda d: d["lines"][0].update(us=" ")),
    }
    for name, doc in controls.items():
        try:
            PH.check_phoneme_file(doc, SCRIPT)
        except AssertionError:
            continue
        raise AssertionError(f"accepted a phoneme file with {name}")


# ---- misaki (only in catalog/.venv-phonemes) ----

def misaki_phonemizer(dialect="us", corr=None, cmu=None):
    import build_play_phonemes as BP
    ph = BP.Phonemizer(dialect, corr or {"words": {}, "plays": {}}, BP.Neural(), cmu or {})
    BP.override_known(ph, corr or {"words": {}, "plays": {}})
    ph.begin("gut-1", set())
    return ph


def have_misaki():
    if importlib.util.find_spec("misaki") is None:
        print("SKIP misaki cases: misaki is not installed here (catalog/.venv-phonemes runs them)")
        return False
    return True


@case
def misaki_reads_a_line_without_dropping_or_spelling_a_word():
    if not have_misaki():
        return
    ph = misaki_phonemizer()
    ps, words = ph.line("The quality of mercy is not strain'd, CHESTERTON said; vpon my word, Zxqvort.")
    assert words == 13, words
    assert "❓" not in ps and set(ps) <= PH.KOKORO_VOCAB, ps
    assert "ˌiˌ" not in ps, "capitals are a word, never spelled letter by letter"
    assert ph.stats["rule"] >= 2 and set(ph.guessed) == {"Zxqvort", "CHESTERTON"}, (ph.stats, ph.guessed)


@case
def misaki_takes_an_editors_correction_over_its_own_lexicon():
    if not have_misaki():
        return
    corr = {"words": {"tis": {"ps": "tˈɪz"}, "zxqvort": {"like": "sport"}}, "plays": {}}
    ph = misaki_phonemizer(corr=corr)
    ps, _ = ph.line("Tis Zxqvort.")
    assert ps.startswith("tˈɪz") and ph.stats["guessed"] == 0, (ps, ph.stats)
    assert ps.rstrip(".").endswith(ph.line("sport")[0].rstrip(".")), ps


@case
def misaki_uses_the_dictionary_before_guessing_and_a_possessive_keeps_its_stem():
    if not have_misaki():
        return
    ph = misaki_phonemizer(cmu={"zxqvort": ["Z", "EH1", "K", "S"]})
    ps, _ = ph.line("Zxqvort's hat.")
    assert ps.startswith("zˈɛksɪz") and ph.stats["dictionary"] == 1 and ph.stats["guessed"] == 0, (ps, ph.stats)
    gb = misaki_phonemizer("gb", cmu={"zxqvort": ["Z", "ER1"]})
    ps, _ = gb.line("Zxqvort.")
    assert ps.startswith("zˈɜː"), ps


def main():
    failed = 0
    for fn in CASES:
        try:
            fn()
        except (AssertionError, KeyError, ValueError, TypeError) as e:
            failed += 1
            print(f"FAIL {fn.__name__}: {e!r}")
    print(f"{len(CASES) - failed}/{len(CASES)} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
