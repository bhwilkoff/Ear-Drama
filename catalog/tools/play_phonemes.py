"""The play-phoneme rules and file shapes (Decision 078), stdlib only, so the catalog tests and the
site's shape check run them without the phoneme environment. The build that uses them,
`build_play_phonemes.py`, runs misaki in catalog/.venv-phonemes.

Every rule here derives a pronunciation from words the lexicon already knows, and is accepted only
when the lexicon knows the result: early-modern spellings (`haue`, `vpon`, `beleeue`), elisions
(`strain'd`, `o'er`, `on't`), archaic endings (`knowest`, `goeth`, `shouldst`), `-ied` and `-ies`,
capitals, accents, and compounds of two known words. A word no rule reaches is guessed by a neural
network and listed in the report for an editor; `catalog/plays/phoneme-corrections.json` overrides
everything. No device ever runs any of this (R2-kokoro-feasibility §2.5).
"""
import json
import re
import unicodedata

FORMAT = 1
DIALECTS = ("us", "gb")
# A play whose guessed share of words is above this gets no phoneme file until an editor looks:
# its Kokoro parts are read by the system voice (R2-kokoro-feasibility §2.5).
HOLD_GUESSED_SHARE = 0.05

# Kokoro-82M's tokenizer vocabulary (onnx-community/Kokoro-82M-v1.0-ONNX tokenizer.json at 1939ad2a8e41),
# space included. A published phoneme string uses only these; a client drops anything else.
KOKORO_VOCAB = frozenset(
    " $;:,.!?—…\"()“” ̃ʣʥʦʨᵝꭧAIOQSTWYᵊabcdefhijklmnopqrstuvwxyzɑɐɒæβɔɕçɖðʤəɚɛɜɟɡɥɨɪʝɯɰŋɳɲɴøɸθœɹɾɻʁɽʂʃʈʧʊʋʌɣɤχʎʒʔˈˌːʰʲ↓→↗↘ᵻ")
# misaki's own per-dialect symbol sets (misaki/en.py US_VOCAB, GB_VOCAB); a correction must fit its dialect.
VOCAB = {"us": frozenset("AIOWYbdfhijklmnpstuvwzæðŋɑɔəɛɜɡɪɹɾʃʊʌʒʤʧˈˌθᵊᵻʔT"),
         "gb": frozenset("AIQWYabdfhijklmnpstuvwzðŋɑɒɔəɛɜɡɪɹʃʊʌʒʤʧˈˌːθᵊ")}
PUNCT = frozenset(" ;:,.!?—…\"()“”")


def line_text(line):
    """The words of a speech exactly as a client keys them (js/plays-core.js spokenText + kokoro-voice.js keyOf):
    the said parts joined by a space, printed italic marks dropped, whitespace folded."""
    t = " ".join(p["say"] for p in line.get("parts", []) if "say" in p and p["say"])
    return re.sub(r"\s+", " ", t.replace("_", "")).strip()


ROMAN = re.compile(r"\b(?!(?:Act|Scene|Part|Book|Chapter|Volume|Canto)\b)([A-Z][a-z]+) (X?(?:IX|IV|V?I{1,3}|V)|X|XX)\b")
ORDINALS = {"II": "the Second", "III": "the Third", "IV": "the Fourth", "V": "the Fifth", "VI": "the Sixth",
            "VII": "the Seventh", "VIII": "the Eighth", "IX": "the Ninth", "X": "the Tenth", "XI": "the Eleventh",
            "XII": "the Twelfth", "XIII": "the Thirteenth", "XIV": "the Fourteenth", "XV": "the Fifteenth",
            "XVI": "the Sixteenth", "XVII": "the Seventeenth", "XVIII": "the Eighteenth", "XIX": "the Nineteenth",
            "XX": "the Twentieth"}


def normalize(text):
    """What the phonemizer reads: one printed form per symbol. Long s, ligatures and curly quotes folded,
    dashes spaced (misaki reads "word--word" as one unknown word), brackets dropped, "St." before a name is
    Saint, and a regnal number after a name is said ("Henry IV" is Henry the Fourth, never "I V")."""
    t = text.replace("ſ", "s").replace("æ", "ae").replace("Æ", "Ae").replace("œ", "oe").replace("Œ", "Oe")
    t = t.replace("‘", "'").replace("’", "'").replace("“", '"').replace("”", '"')
    t = re.sub(r"\s*(—|–|--+)\s*", " — ", t)
    t = re.sub(r"[\[\]{}*]", " ", t)
    t = re.sub(r"\bSt\.(?= [A-Z])", "Saint", t)
    t = ROMAN.sub(lambda m: f"{m.group(1)} {ORDINALS[m.group(2)]}" if m.group(2) in ORDINALS else m.group(0), t)
    return re.sub(r"\s+", " ", t).strip()


# ---- elisions: a spelling, or a phoneme string (marked /.../) when no spelling says it ----
ELISIONS = {
    "o'er": "over", "e'er": "ever", "ne'er": "never", "ne're": "never", "e'en": "even", "th'": "the", "i'": "in",
    "'gainst": "against", "gainst": "against", "heav'n": "heaven", "i'le": "I'll", "ile": "I'll", "wee'l": "we'll",
    "weel": "we'll", "thou'rt": "thou art", "y'are": "you are", "d'you": "do you", "pr'ythee": "prithee",
    "prythee": "prithee", "prethee": "prithee", "pray'thee": "prithee", "h'm": "hmm", "dont": "don't",
    "doesnt": "doesn't", "didnt": "didn't", "isnt": "isn't", "wasnt": "wasn't", "couldnt": "couldn't",
    "wouldnt": "wouldn't", "shouldnt": "shouldn't", "havent": "haven't", "ay": "aye", "an't": "and it",
    "'tis": "/tˈɪz/", "tis": "/tˈɪz/", "'twas": "/twˈʌz/", "'twere": "/twˈɜɹ/", "twere": "/twˈɜɹ/",
    "'twill": "/twˈɪl/", "twill": "/twˈɪl/", "'twould": "/twˈʊd/", "twould": "/twˈʊd/", "ta'en": "/tˈAn/",
    "d'ye": "/ʤə/", "i'th'": "/ɪðə/", "o'th'": "/əðə/", "i'faith": "/ɪfˈAθ/", "ifaith": "/ɪfˈAθ/",
    "twixt": "/twˈɪkst/", "'twixt": "/twˈɪkst/", "thro": "through", "thro'": "through", "tho": "though",
    "tho'": "though", "ive": "I've", "o'th": "/əðə/", "i'th": "/ɪðə/", "th'art": "thou art", "p'raps": "perhaps",
    "more'n": "more than", "yes'm": "yes ma'am", "mas'r": "master", "'neath": "beneath", "neath": "beneath",
    "'ud": "would", "'ull": "will", "an'": "and", "o'": "of", "wi'": "with", "ne'r": "never",
}
# The /.../ strings above are US; the GB lexicon's own symbols where they differ.
ELISIONS_GB = {"'twere": "/twˈɜː/", "twere": "/twˈɜː/"}


def elision_candidates(word):
    """Spellings an elided word stands for, most likely first (each is checked against the lexicon)."""
    lw = word.lower()
    out = []
    if lw in ELISIONS:
        out.append(ELISIONS[lw])
    m = re.fullmatch(r"([a-z]+)ou'd", lw)  # wou'd, shou'd, cou'd
    if m:
        out.append(m.group(1) + "ould")
    m = re.fullmatch(r"([a-z]+)'d", lw)  # strain'd, lov'd, liu'd
    if m:
        out += [m.group(1) + "ed", m.group(1) + "d"]
    m = re.fullmatch(r"([a-z]+)'st", lw)  # dar'st, lov'st
    if m:
        out += [m.group(1) + "est", m.group(1) + "st"]
    m = re.fullmatch(r"([a-z]+)'t", lw)  # on't, is't, do't
    if m:
        out.append(m.group(1) + " it")
    m = re.fullmatch(r"([a-z]{2,})in'?", lw)  # nothin', comin, lookin
    if m:
        out.append(m.group(1) + "ing")
    m = re.fullmatch(r"([a-z]+n)'", lw)  # roun', fin'
    if m:
        out.append(m.group(1) + "d")
    m = re.fullmatch(r"o'er([a-z]+)", lw)  # o'ercome, o'erthrown
    if m:
        out.append("over" + m.group(1))
    m = re.fullmatch(r"t'([a-z]+)", lw)  # t'say
    if m:
        out.append("to " + m.group(1))
    if "'" in lw.strip("'"):
        out.append(lw.replace("'", ""))
        out.append(lw.strip("'").replace("'", "e"))  # ev'ry, fall'n, pow'r, wand'ring
    if lw.isalpha() and len(lw) > 3:  # aint, youll, youve, hadnt: the apostrophe left out
        for k in ("n't", "'ll", "'ve", "'re", "'d", "'m"):
            bare = k.replace("'", "")
            if lw.endswith(bare) and len(lw) > len(bare) + 1:
                out.append(lw[:-len(bare)] + k)
    return out


# ---- early-modern spelling: substitutions tried alone and in pairs, kept only when the result is known ----
def spelling_variants(word):
    """Modern spellings an early-modern one may stand for, fewest changes first: u/v and i/j, a final -e,
    doubled letters, ie/y, ee/ie, oy/oi, o/ou. Deterministic order."""
    w = word.lower()
    if not w.isalpha():
        return []

    def one(x):
        c = []
        for i, ch in enumerate(x):
            nxt = x[i + 1] if i + 1 < len(x) else ""
            prv = x[i - 1] if i else ""
            if ch == "u" and nxt in "aeiouy" and nxt and prv:
                c.append(x[:i] + "v" + x[i + 1:])
            if ch == "v" and (i == 0 or prv in "aeiou") and nxt and nxt not in "aeiouy":
                c.append(x[:i] + "u" + x[i + 1:])
            if ch == "i" and nxt and nxt in "aeiou" and (i == 0 or prv in "-"):
                c.append(x[:i] + "j" + x[i + 1:])
            if ch == "y" and prv and prv not in "aeiou" and i:
                c.append(x[:i] + "i" + x[i + 1:])
        if x.endswith("e") and len(x) > 3:
            c.append(x[:-1])
        if x.endswith("ie") and len(x) > 3:
            c.append(x[:-2] + "y")
        if re.search(r"([bdglmnprst])\1e?$", x):
            c.append(re.sub(r"([bdglmnprst])\1e?$", r"\1", x))
        if re.search(r"[aeiou][lt]$", x):
            c.append(x + x[-1])
        for a, b in (("ee", "e"), ("ee", "ie"), ("ee", "ea"), ("oo", "o"), ("oy", "oi"), ("ei", "ie"), ("ck", "c"),
                     ("ou", "o"), ("ay", "ai"), ("ie", "y"), ("ew", "ow"), ("j", "g"), ("i", "y")):
            if a in x:
                c.append(x.replace(a, b))
        if re.search(r"(?<!l)l(?!l)", x):  # wilful, skilful, fulness: the US doubles the l
            c.append(re.sub(r"(?<![l])l(?=[fn])", "ll", x))
        if x.endswith("ce"):
            c.append(x[:-2] + "se")  # recompence
        if re.search(r"o(?=ng$)", x):
            c.append(re.sub(r"o(?=ng$)", "ou", x))
        return [y for y in dict.fromkeys(c) if y != x]

    first = one(w)
    second = [y for x in first for y in one(x)]
    return [y for y in dict.fromkeys(first + second) if y != w]


# ---- archaic and regular endings the lexicon's own stemmer misses ----
SUFFIXES = (("eth", "ɪθ"), ("est", "ɪst"), ("st", "st"), ("ied", "d"), ("ies", "z"), ("èd", "ɪd"))


def suffix_candidates(word):
    """(stem, phonemes added) pairs: knowest = know + ɪst, goeth = go + ɪθ, shouldst = should + st,
    denied = deny + d, cursèd = curse + ɪd (the accent marks a said syllable)."""
    lw = word.lower()
    out = []
    for suf, ps in SUFFIXES:
        if not lw.endswith(suf) or len(lw) - len(suf) < 2:
            continue
        stem = lw[:-len(suf)]
        if suf in ("ied", "ies"):
            out.append((stem + "y", ps))
            continue
        out += [(stem, ps), (stem + "e", ps)]
        if suf == "est":
            out.append((lw[:-2], "st"))  # seest = see + st
        if re.search(r"([bdglmnprt])\1$", stem):
            out.append((stem[:-1], ps))  # forgettest
    return out


def past_ending(ps):
    """The past ending said after a stem's last sound: -ɪd after t or d, -t after a voiceless sound, else -d."""
    last = next((c for c in reversed(ps) if c.isalpha() or c in "ʃʧθ"), "")
    return "ɪd" if last in "td" else "t" if last in "pkfsθʃʧ" else "d"


def ascii_fold(word):
    return unicodedata.normalize("NFKD", word).encode("ascii", "ignore").decode()


def spell_phrase(phrase, known):
    parts = phrase.split(" ")
    ps = [known(p) for p in parts]
    return " ".join(ps) if all(ps) else None


def derive(word, known, dialect="us", _depth=0):
    """A pronunciation built from words the lexicon knows, or None. Returns (phonemes, rule).
    `known(w)` is the lexicon lookup (phonemes or None). Nothing here guesses."""
    if not word or _depth > 2:
        return None
    core = word.strip(".,;:!?\"()-—–'*") if not re.fullmatch(r"'?[A-Za-z]+'?", word) else word
    if core and core != word:
        r = derive(core, known, dialect, _depth + 1)
        if r:
            return r
    lw = word.lower()
    for cand in elision_candidates(word):
        if cand.startswith("/"):
            if dialect == "gb" and lw in ELISIONS_GB:
                cand = ELISIONS_GB[lw]
            return cand.strip("/"), "elision"
        ps = spell_phrase(cand, known)
        if ps:
            return ps, "elision"
        if " " not in cand and cand.isalpha():
            for v in spelling_variants(cand):
                ps = known(v)
                if ps:
                    return ps, "elision+spelling"
    m = re.fullmatch(r"([a-z]+)'(d|st|lt)", lw)
    if m:
        stem, end = m.groups()
        for s in [stem, stem + "e"] + spelling_variants(stem)[:40] + spelling_variants(stem + "e")[:40]:
            ps = known(s)
            if ps:
                return ps + (past_ending(ps) if end == "d" else end), "elision+ending"
    if word.isalpha():
        if word != lw:
            ps = known(lw)
            if ps:
                return ps, "case"
        for v in spelling_variants(word):
            ps = known(v)
            if ps:
                return ps, "spelling"
        for stem, add in suffix_candidates(word):
            ps = known(stem)
            if not ps:
                for v in spelling_variants(stem)[:40]:
                    ps = known(v)
                    if ps:
                        break
            if ps:
                return ps + add, "ending"
        if lw == word and len(word) >= 7:
            for i in range(3, len(word) - 2):
                a, b = known(word[:i]), known(word[i:])
                if a and b and len(word[:i]) >= 3 and len(word[i:]) >= 3:
                    return a + b, "compound"
    folded = ascii_fold(word)
    if folded != word and folded.isalpha():
        ps = known(folded) or known(folded.lower())
        if ps:
            return ps, "accent"
        r = derive(folded, known, dialect, _depth + 1)
        if r:
            return r[0], "accent+" + r[1]
    return None


# ---- CMUdict (BSD-style, pinned): real pronunciations for words misaki lacks, mostly names ----
CMUDICT_URL = "https://raw.githubusercontent.com/cmusphinx/cmudict/74790861f652b15e4ac49015a90074ad62a27690/cmudict.dict"
CMUDICT_SHA256 = "81917843c7f44ce2b094ac63873c2c7a4cf802040792c455ba3ca406891c3d22"
CMUDICT_NOTICE = "Copyright (C) 1993-2015 Carnegie Mellon University. All rights reserved. (cmusphinx/cmudict, BSD-style license)"
ARPA = {"AA": "ɑ", "AE": "æ", "AH": "ʌ", "AO": "ɔ", "AW": "W", "AY": "I", "EH": "ɛ", "ER": "ɜɹ", "EY": "A",
        "IH": "ɪ", "IY": "i", "OW": "O", "OY": "Y", "UH": "ʊ", "UW": "u", "B": "b", "CH": "ʧ", "D": "d",
        "DH": "ð", "F": "f", "G": "ɡ", "HH": "h", "JH": "ʤ", "K": "k", "L": "l", "M": "m", "N": "n",
        "NG": "ŋ", "P": "p", "R": "ɹ", "S": "s", "SH": "ʃ", "T": "t", "TH": "θ", "V": "v", "W": "w",
        "Y": "j", "Z": "z", "ZH": "ʒ"}
_VOWELS = "AIOWYaeiouæɑɒɔəɛɜɪʊʌᵊᵻQ"


def arpa_to_misaki(phones):
    """ARPAbet (CMUdict, g2p_en) to misaki's US symbols, stress marks before the vowel."""
    out = []
    for p in phones:
        m = re.fullmatch(r"([A-Z]+)([012]?)", p)
        if not m or m.group(1) not in ARPA:
            continue
        base, st = m.groups()
        v = "ə" if (base == "AH" and st == "0") else "əɹ" if (base == "ER" and st == "0") else ARPA[base]
        out.append(("ˈ" if st == "1" else "ˌ" if st == "2" else "") + v)
    return "".join(out)


def us_to_gb(ps):
    """An approximate British form of a US string (for a dictionary entry or a guess, never misaki's own GB):
    non-rhotic r after a vowel, the GOAT vowel Q, TRAP a, and only symbols the GB lexicon uses."""
    t = ps.replace("O", "Q").replace("æ", "a").replace("ᵻ", "ɪ").replace("ɾ", "t").replace("T", "t").replace("ʔ", "t")
    for a, b in (("ɜɹ", "ɜː"), ("əɹ", "ə"), ("ɑɹ", "ɑː"), ("ɔɹ", "ɔː"), ("ɛɹ", "ɛː"), ("ɪɹ", "ɪə"), ("ʊɹ", "ʊə"),
                 ("Iɹ", "Iə"), ("Wɹ", "Wə")):
        t = re.sub(re.escape(a) + r"(?![ˈˌ]?[" + _VOWELS + r"])", b, t)
    return t


def load_cmudict(path):
    """{word: first pronunciation as ARPAbet phones}. Comments and alternates (word(2)) dropped."""
    out = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.split("#", 1)[0].strip()
            if not line:
                continue
            word, *phones = line.split()
            if "(" in word or word in out:
                continue
            out[word] = phones
    return out


def possessive(word):
    """("Paramore", "z") for "Paramore's": the stem and the ending said after it, or None."""
    m = re.fullmatch(r"(.+?)('s|s')", word, re.I)
    if not m or not any(c.isalpha() for c in m.group(1)):
        return None
    return m.group(1), m.group(2).lower()


def possessive_ending(ps, plural=False):
    """-ɪz after a sibilant, -s after another voiceless sound, else -z (nothing added for a plural's s')."""
    if plural:
        return ""
    last = next((c for c in reversed(ps) if c.isalpha() or c in "ʃʒʧʤθ"), "")
    return "ɪz" if last in "szʃʒʧʤ" else "s" if last in "ptkfθ" else "z"


def is_word(token_text):
    return any(c.isalpha() for c in token_text)


# ---- the editorial correction file ----

def load_corrections(path):
    """catalog/plays/phoneme-corrections.json: {format: 1, words: {word: entry}, plays: {id: {word: entry}}}.
    An entry is {"ps": phonemes} (both dialects), {"us": ..., "gb": ...}, or {"like": a respelling the
    lexicon reads}; "note" is free text. Words match without regard to case. Raises ValueError on a bad entry."""
    doc = json.load(open(path, encoding="utf-8"))
    if doc.get("format") != FORMAT:
        raise ValueError("phoneme corrections: format must be 1")

    def entries(d, where):
        out = {}
        for w, e in sorted((d or {}).items()):
            if not isinstance(e, dict) or not w.strip():
                raise ValueError(f"{where}: {w!r} is not a correction")
            keys = set(e) - {"note"}
            if keys not in ({"ps"}, {"us", "gb"}, {"like"}, {"us"}, {"gb"}):
                raise ValueError(f"{where}: {w!r} needs ps, us+gb or like, got {sorted(keys)}")
            for k in keys & {"ps", "us", "gb"}:
                bad = set(e[k]) - KOKORO_VOCAB
                if not e[k] or bad:
                    raise ValueError(f"{where}: {w!r} {k} has symbols Kokoro cannot read: {sorted(bad)}")
            if "like" in e and not (isinstance(e["like"], str) and e["like"].strip()):
                raise ValueError(f"{where}: {w!r} like is empty")
            out[w.lower()] = e
        return out

    return {"words": entries(doc.get("words"), "words"),
            "plays": {pid: entries(d, pid) for pid, d in sorted((doc.get("plays") or {}).items())}}


def correction_for(corrections, play_id, word, dialect):
    """The corrections entry for a word in a play (the play's own first), resolved to ("ps", s) or ("like", s), or None."""
    lw = word.lower()
    for table in ((corrections or {}).get("plays", {}).get(play_id, {}), (corrections or {}).get("words", {})):
        e = table.get(lw)
        if e:
            if dialect in e:
                return "ps", e[dialect]
            if "ps" in e:
                return "ps", e["ps"]
            if "like" in e:
                return "like", e["like"]
            return "ps", e.get("us") or e.get("gb")
    return None


# ---- the published file ----

def phoneme_file(script, rows, g2p_id):
    """phonemes/<id>.json: {format, id, revision, g2p, lines: [{id, t, us, gb?}]}. `t` is the line's words as a
    client keys them (line_text); `gb` is present only where it differs from `us`."""
    return {"format": FORMAT, "id": script["id"], "revision": script["revision"], "g2p": g2p_id, "lines": rows}


def check_phoneme_file(doc, script):
    """Shape and consistency of one play's phoneme file against its script. Raises AssertionError."""
    assert doc["format"] == FORMAT, doc.get("format")
    assert doc["id"] == script["id"] and doc["revision"] == script["revision"], (doc["id"], "phonemes out of date")
    assert isinstance(doc["g2p"], str) and doc["g2p"]
    speech = {l["id"]: line_text(l) for l in script["lines"] if l["kind"] == "speech"}
    seen = set()
    for r in doc["lines"]:
        assert set(r) <= {"id", "t", "us", "gb"} and {"id", "t", "us"} <= set(r), (doc["id"], r.get("id"), sorted(r))
        assert r["id"] in speech, (doc["id"], r["id"], "not a speech line")
        assert r["id"] not in seen, (doc["id"], r["id"], "twice")
        seen.add(r["id"])
        assert r["t"] == speech[r["id"]], (doc["id"], r["id"], "text differs from the script")
        for k in ("us", "gb"):
            if k in r:
                assert isinstance(r[k], str) and r[k].strip(), (doc["id"], r["id"], k, "empty")
                bad = set(r[k]) - KOKORO_VOCAB
                assert not bad, (doc["id"], r["id"], k, sorted(bad))
        assert r.get("gb") != r["us"], (doc["id"], r["id"], "gb repeats us")
    missing = [i for i, t in speech.items() if t and i not in seen and any(c.isalpha() for c in t)]
    assert not missing, (doc["id"], "speech lines without phonemes", missing[:5])
