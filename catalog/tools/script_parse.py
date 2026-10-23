"""Turn a radio script or a stage play into roles and lines, never rewriting a word.

Built from the research prototypes (catalog/prototypes/scripts/radio_parse.py and
stage_parse.py, research 08b §2). A parse PROPOSES attributions for a person to
accept: it never fills a gap, modernizes a line, or writes a cast description
(08b §4; no AI-written copy). Every part of a line is an exact slice of the
source block (whitespace aside), so the words of the parts, in order, are the
words of the source less its brackets and the speaker's label.

A line is
    {"id": "L0007", "kind": "speech"|"sound"|"music"|"direction",
     "role": "FIBBER" | None, "source": "<the block as printed>",
     "parts": [{"say": ...}, {"direction": ...}, {"mic": ...}, {"sound": ...}]}
Stage directions are kept apart from speech (their own parts or lines) so the
people casting a stage play can decide how to read them for radio (Decision 059).

A stage text's play is found before it is parsed (measured 2026-10-23 over every cached
Gutenberg text): it begins at the earliest cast list, act or scene heading, or first
entrance shortly before the first sustained run of speech, and ends at the last speech by
a recurring speaker (through its closing directions and END/CURTAIN). Title pages,
publishers, catalogs, prefaces, and notes outside it are `front`/`back` items: kept with
their words, never lines, never a role. A full name that expands a frequent label
("Barnardo." beside "Barn.", "_Clapboard._" beside "_Clap._") is that label's role when the
text prints the name as a name.

A radio text is read the same way (measured 2026-10-23 over every cached radio text: 1,028
GRW and the 4 Gutenberg radio plays): a cast list runs from its heading over its entries
("RICK, private detective", "CLERK (2 lines)") until the play's first label; a label may
stand on its own line with a direction ("CARVER [_off_]"); a speech may run over several
paragraphs; notes and credits ("NOTE:", "Transcribed by", a Gutenberg transcriber's note)
and everything before the first cast list, speech, or cue are set aside, never lines. A
mixed-case label ("Announcer:") is a role when it recurs or is one or two words, so a
sentence ending in a semicolon is not. Only bracketed spans are radio directions: an
italic ship's name is spoken.

A text is a STUB, and not a script, when it is under 500 words or is a page of
links with no dialogue (measured 2026-10-22 on all 1,028 cached GRW texts: 39 too
short, such as "Information Coming Soon...", and 25 link pages, such as "PDF
files on Old Time Radio Researchers Group website"). A long text in which no
dialogue is found is a parse FAILURE (format_unrecognized), not a stub: one is the
Campbell Playhouse "Rebecca" with its line breaks lost. Neither is ever cast.

    python3 tools/script_parse.py measure     # the 50 GRW + 20 Gutenberg sample
"""
import collections
import glob
import html
import json
import os
import random
import re
import statistics
import sys

MIN_WORDS = 500
MIN_SPEECHES = 20
CASTABLE_LINES = 5
CLEAN_UNCLASSIFIED = 0.05
# Measured 2026-10-23 over the 24 cached Gutenberg texts: a play set aside at most 28% of
# its words (a farce with publishers' catalogs at both ends, a translation whose notes
# follow it); a text that sets aside more holds something besides one play.
CLEAN_SET_ASIDE = 0.40

# ---- radio conventions (08b §2.1) ----------------------------------------------------------------
CUE_TAGS = {
    "music": r"MUSIC|THEME|ORCH(?:ESTRA)?|ORGAN|BAND|QUARTET|SONG|BRIDGE|STING",
    "sound": r"SOUND(?:\s*(?:EFFECTS?|FX))?|SFX|F/?X|EFFECTS?|SOUND\s*EFFECT|SOUND\s*PATTERN|BIZ|BUSINESS|APPLAUSE|NOISE",
}
CUE = re.compile(r"^\(?\s*(%s)\s*(?:[:;.\-]|(?=\())\s*(.*)$" % "|".join(f"(?P<{k}>{v})" for k, v in CUE_TAGS.items()), re.I)
R_ROLE = re.compile(r"^[\[\"]?(?P<role>(?:\d+(?:ST|ND|RD|TH|st|nd|rd|th)\.?\s+)?[A-ZÀ-Þ][A-Za-zÀ-ÿ0-9.'&/#\- ]{0,38}?)[\]\"]?"
                    r"\s*(?:\((?P<paren>[^)]{0,60})\))?\s*[:;]\s*(?P<text>.*)$")
R_ROLE_SPACED = re.compile(r"^(?P<role>[A-ZÀ-Þ][A-ZÀ-Þ0-9.'&\- ]{1,30}?)(?:\s*\((?P<paren>[^)]{0,60})\))?\s{3,}(?P<text>\S.*)$")
NOTROLE = re.compile(r"^(DATE|CAST|NOTE|PRODUCTION|SCENE|ACT|PAGE|PROGRAM|WRITER|DIRECTOR|SPONSOR|TITLE|SERIES|"
                     r"SOURCE|TRANSCRIBED|THANKS|https?)(?:\s+\d+)?$", re.I)
SOUNDROLE = re.compile(r"\b(DOOR|KNOCK|PHONE|TELEPHONE|CROWD|APPLAUSE|LAUGH\w*|SCENE \d+|COMMERCIAL|BACKGROUND|"
                       r"VIBRAPHONE|GONG|BELL|SIREN|GUN\w*|SHOTS?|WIND|RAIN|THUNDER|FOOTSTEPS|CREDITS|AD LIBS?|"
                       r"SIGNOFF|ECHO|FILTER|CLOCK|CAR|TRAIN|PLANE|ENGINE|HORN|WHISTLE)\b")
MIC = re.compile(r"^\s*_?(in|off|on mike|off mike|coming in|going off|fading(?: in| out| off)?|fade(?: in| out)?|"
                 r"filter|close|distant|backing off|offstage|off stage)\b", re.I)
SOUNDWORD = re.compile(r"\b(knock\w*|sound|door|crowd|noise|bell|shot|thunder|wind|music|bugle|drum|cheer\w*|"
                       r"footsteps|horse|hoof\w*|crash|ring\w*|whistle|applause|laughter)\b", re.I)

# ---- stage conventions (08b §2.4) ----------------------------------------------------------------
CAP = r"[A-ZÀ-Þ][A-ZÀ-Þ0-9.'’\- ]{0,40}?"
S_ROLE_OWN = re.compile(r"^_?(?P<role>%s)_?\.?\s*(?P<d>\[[^\]]*\]|\(_[^)]*_\)|\([^)]*\))?\s*$" % CAP)
S_ROLE_COLON = re.compile(r"^_?(?P<role>%s)_?\s*:\s*(?P<text>.+)$" % CAP, re.S)
S_ROLE_INLINE = re.compile(r"^_?(?P<role>%s)_?\.\s+(?P<text>\S.+)$" % CAP, re.S)
CASTHEAD = re.compile(r"^_?(CAST|CAST OF CHARACTERS|PERSONS|CHARACTERS|DRAMATIS PERSON(?:AE|Æ)|THE PERSONS OF THE PLAY|"
                      r"PERSONS IN THE PLAY|PERSONS REPRESENTED(?: IN THE PLAY)?|CHARACTERS IN THE PLAY)_?\.?:?\s*$", re.I)
# A play's first act, counted over the whole text: two of them are two plays.
FIRST_ACT = re.compile(r"^_?\[?(?:ACT\.?\s+(?:I|1|ONE|FIRST)\b(?![IVX])|ACTUS\s+PRIMUS|(?:THE\s+)?FIRST\s+ACT)", re.I)
HEADING = re.compile(r"^_?(ACT|SCENE|CURTAIN|END|THE END|PERSONS|CHARACTERS|DRAMATIS|(?:THE )?FIRST ACT|"
                     r"(?:THE )?SECOND ACT|(?:THE )?THIRD ACT|(?:THE )?FOURTH ACT|(?:THE )?FIFTH ACT|PROLOGUE|EPILOGUE|"
                     r"PLAYS|CONTENTS|PREFACE|INTRODUCTION|NOTE|FOOTNOTES?|"
                     r"TRANSCRIBER|ILLUSTRATIONS?|CHAPTER|BOOK|PART|APPENDIX|INDEX|FINIS)\b", re.I)
# Lists that belong to the cast list without starting another one ("COSTUMES.").
CASTSUB = re.compile(r"^_?(COSTUMES?|PROPERTIES|SCENERY|TIME OF (?:PLAYING|PERFORMANCE|REPRESENTATION))_?\.?:?\s*$",
                     re.I)
CAST_ENTRY = re.compile(r"^\s*_?(?:MRS?\.\s+|MISS\s+|DR\.\s+)?[A-ZÀ-Þ][A-ZÀ-Þ'’\-]+(?:\s+[A-ZÀ-Þ][A-ZÀ-Þ'’\-]+){0,3}_?[,.]")
# Where the play itself begins: a cast list, an act or scene heading, a first entrance.
PLAY_MARK = re.compile(r"^_?\[?(?:(?:ACT|ACTUS|SCENE|SCENA|SCOENA|SC[ÆE]NA|PROLOGUE|INDUCTION|"
                       r"(?:THE\s+)?(?:FIRST|SECOND|THIRD|FOURTH|FIFTH)\s+ACT)\b|[IVX]+\.\s+_?[A-Z])", re.I)
ENTER_LINE = re.compile(r"^\s*[\[(]?_?(?:Enter|Re-?enter)(?:_|\b)")
END_HEAD = re.compile(r"^_?(THE END|END|FINIS|CURTAIN)\b[^a-z]*$")
SEPARATOR = re.compile(r"^[\s*.\-=_~]{3,}$")
BACK_START = re.compile(r"Transcriber|Project Gutenberg|Typographical errors|Produced by|Etext", re.I)
ROMAN = re.compile(r"^[IVXL]+$")
LATIN_HEAD = re.compile(r"^_?(Actus|Scena|Scoena|Sc[æe]na)\b[\w .]{0,40}\.?_?$")
# Mixed-case labels ("Ham.", "_Clap._", "Roberts:", "Mrs. Roberts:", "L. Kin."), accepted only
# when the same label opens 3 or more lines of the text, so a prose sentence starting
# "Then." is not a role.
HONORIFIC = r"(?:(?:Mrs?|Ms|Miss|Dr|St|Sir|Lady|Lord|Mme|Mlle|Col|Capt|Gen|Prof|Rev|[B-HJ-NP-Z])\.?\s+)"
LABEL_MIXED = re.compile(r"^\s*_?(?P<role>%s?[A-ZÀ-Þ][A-Za-zÀ-ÿ'’\-]{0,20}(?:\s+[A-ZÀ-Þ][A-Za-zÀ-ÿ'’\-]{0,20}){0,2})_?"
                         r"\s*[.:;]_?\s+(?P<text>\S.*)$" % HONORIFIC, re.S)
NOT_LABEL = {"Enter", "Exit", "Exeunt", "Re-enter", "Manet", "Flourish", "Sennet", "Alarum", "Alarums", "March",
             "Mr", "Mrs", "Dr", "St", "Mme", "Mlle", "Scene", "Act", "Note", "The", "A", "I", "O", "Oh", "Yes", "No",
             "Well", "Then"}
# Capitals labels that are stage business, never a role ("AT RISE:", "ENTER MRS.").
NOT_STAGE_ROLE = re.compile(r"^(AT RISE|TIME|PLACE|SCENE|SYNOPSIS|ENTER|RE-?ENTER|EXIT|EXEUNT|ALARUMS?|FLOURISH|"
                            r"SENNET|S O N G|CURTAIN)\b|^(?:THE|A|AN|OR|BY)$|^(?:[RLC]\.?\s*)+$")
ENTRANCE = re.compile(r"^\s*_?(Enter|Re-?enter|Exit|Exeunt|Manet|Flourish|Sennet|Alarums?|A march|Sound|Trumpets|"
                      r"Thunder|Curtain|Scene|Act)\b", re.I)
DIR_SPAN = re.compile(r"\[[^\]]*\]|\([^)]*\)|(?<![A-Za-z0-9])_[^_\n]+_(?![A-Za-z0-9])")
DIR_SPAN_BRACKETS = re.compile(r"\[[^\]]*\]|\([^)]*\)")


def clean_html(raw):
    t = raw.replace("\r", "")
    if re.search(r"<(p|br|div|b)\b", t, re.I):
        t = re.sub(r"<br\s*/?>", "\n", t, flags=re.I)
        t = re.sub(r"</p>", "\n\n", t, flags=re.I)
        t = re.sub(r"<[^>]+>", "", t)
    return html.unescape(t)


GUT_START = re.compile(r"\*\*\* ?START OF TH(?:E|IS) PROJECT GUTENBERG")


def gutenberg_body(raw):
    t = raw.replace("\r", "")
    a = re.search(r"\*\*\* ?START OF TH(?:E|IS) PROJECT GUTENBERG[^\n]*\n", t)
    b = re.search(r"\*\*\* ?END OF TH(?:E|IS) PROJECT GUTENBERG", t)
    return t[a.end() if a else 0: b.start() if b else len(t)]


def split_parts(text, italic=True):
    """Speech text -> parts, each an exact slice of `text`. Bracketed or italic spans are
    directions (mic words become `mic`, effect words `sound`); everything else is `say`.
    A radio script brackets its directions, so there an italic word ("the _Mayflower_")
    is spoken (italic=False)."""
    parts, pos = [], 0
    for m in (DIR_SPAN if italic else DIR_SPAN_BRACKETS).finditer(text):
        say = text[pos:m.start()].strip()
        if say:
            parts.append({"say": say})
        inner = m.group(0)[1:-1].strip(" _")
        if inner:
            kind = "mic" if MIC.match(inner) else "sound" if (SOUNDWORD.search(inner) and m.group(0)[0] == "[") \
                else "direction"
            parts.append({kind: inner})
        pos = m.end()
    tail = text[pos:].strip()
    if tail:
        parts.append({"say": tail})
    return parts


def _role(r):
    return re.sub(r"\s+", " ", r.replace("’", "'").strip(" ._[]\"")).upper()


# ---- radio ---------------------------------------------------------------------------------------

# A label glued to the line before it by a lost line break ("(1 line)WILCOX: The ...",
# "Generic Radio WorkshopANNCR: ..."); split only for a label that opens 3+ other lines.
R_LINE_LABEL = re.compile(r"^\s*([A-ZÀ-Þ0-9][A-ZÀ-Þ0-9.'#\- ]{1,30}):", re.M)
# A cue printed as a bare word or two, in any case ("Applause", "Theme music", "G O N G").
R_BARE_CUE = re.compile(r"^(?:(?P<music>(?:theme\s+)?(?:music|theme|orchestra|organ|fanfare)(?:\s+(?:up|in|out|under))?)|"
                        r"(?P<sound>applause|laughter|laughs?|gong|chimes|cheers?|knock(?:ing|s)?|(?:tele)?phone\s+rings?))"
                        r"[\s.!]*$", re.I)


def _unglue(text):
    labels = {k for k, n in collections.Counter(m.group(1).strip() for m in R_LINE_LABEL.finditer(text)).items()
              if n >= 3 and len(k) >= 3}
    if not labels:
        return text
    alt = "|".join(re.escape(x) for x in sorted(labels, key=len, reverse=True))
    return re.sub(r"(?<=[a-z)\]])(?=(?:%s):\s)" % alt, "\n", text)


def _radio_blocks(text):
    text = _unglue(text)
    out = []
    for para in re.split(r"\n\s*\n", text):
        cur = None
        for l in (x.strip() for x in para.split("\n")):
            if not l:
                continue
            if cur is not None and not (R_ROLE.match(l) or R_ROLE_SPACED.match(l) or CUE.match(l)):
                cur += " " + l
            else:
                if cur is not None:
                    out.append(cur)
                cur = l
        if cur is not None:
            out.append(cur)
    return out


RADIO_CASTHEAD = re.compile(r"^_?(?:THE\s+)?(CAST|CAST OF CHARACTERS|CHARACTERS|DRAMATIS PERSONAE)_?(?:\s*\([^)]{0,40}\))?"
                            r"\s*:?\s*$", re.I)
# A label printed on its own line, with an optional direction after it ("CARVER [_off_]").
R_BARE = re.compile(r"^(?P<name>[A-ZÀ-Þ][A-ZÀ-Þ.'\- ]{1,24}?)\s*(?P<d>\[[^\]\n]{0,60}\]|\([^)\n]{0,60}\))?$")
# Notes about the text, never a line: "NOTE: ...", "Transcribed by ...", "Script courtesy ...".
R_NOTE = re.compile(r"^(?:\**\s*(?:TRANSCRIBER'?S?\s+|EDITOR'?S?\s+|PRODUCTION\s+)?NOTES?\s*:|\*+\s*NOTE\b|"
                    r"(?:This\s+(?:script|transcript)\s+(?:has\s+been|was)\s+)?(?:transcribed|transcription)\s+(?:by|from)\b|"
                    r"Script\s+(?:courtesy|provided|transcribed)\b|Transcription\s+by\b|End\s+of\s+(?:the\s+)?Project\s+Gutenberg)",
                    re.I)


def _bare(b):
    m = R_BARE.match(b)
    if not m or len(m.group("name").split()) > 3 or SOUNDROLE.search(m.group("name")) \
            or NOTROLE.match(m.group("name").strip()):
        return None
    return m


def _speaks(b):
    m = R_ROLE.match(b)
    return bool(m and m.group("text").strip() and not NOTROLE.match(m.group("role").strip()))


def _caps_label(b):
    m = R_ROLE.match(b)
    return bool(m and not re.search(r"[a-z]", m.group("role")))


def _cast_entry(b, nxt):
    """A block of a cast list: short, or names only; not a cue or a labeled speech, and
    not a label whose next block is prose (that label opens the play)."""
    if CUE.match(b) or _speaks(b) or R_NOTE.match(b):
        return False
    if not (len(b) <= 80 or not re.search(r"[a-z]", b)):
        return False
    return not (_bare(b) and nxt is not None and re.search(r"[a-z]", nxt)
                and (len(nxt) > 80 or re.search(r"[.!?…\-—]['\"”’]?$", nxt)))


def _radio_items(text):
    bs = _radio_blocks(text)
    start = 0
    for i, b in enumerate(bs[:6]):
        if b.startswith("Date:"):
            start = i + 1
            m = re.match(r"Date:\s*(?:[A-Z][a-z]{2} \d{1,2} \d{4}|Date Unknown|circa \d{4}s|\d{4})(.+)$", b)
            if m:
                bs.insert(i + 1, m.group(1).strip())
    head = bs[:start]
    seq, k = bs[start:], 0
    # a cast list runs from its heading over short blocks until the play starts
    cast = set()
    while k < len(seq):
        if RADIO_CASTHEAD.match(seq[k]):
            cast.add(k)
            k += 1
            while k < len(seq) and _cast_entry(seq[k], seq[k + 1] if k + 1 < len(seq) else None):
                cast.add(k)
                k += 1
            continue
        k += 1
    # a label printed on its own line is a role when it recurs (3+ times) or follows a speech
    names = collections.Counter(m.group("name") for m in map(_bare, seq) if m)
    # a mixed-case label ("Fibber:") is a role only when it recurs, so "I know not; ..." is not
    mixed = collections.Counter(m.group("role") for m in map(R_ROLE.match, seq) if m and re.search(r"[a-z]", m.group("role")))
    merged, k = [], 0
    while k < len(seq):
        b, m = seq[k], _bare(seq[k])
        if (m and k not in cast and k + 1 < len(seq) and k + 1 not in cast and not _caps_label(seq[k + 1])
                and not CUE.match(seq[k + 1]) and not _bare(seq[k + 1])
                and (names[m.group("name")] >= 3 or any(R_ROLE.match(x) for x in seq[max(0, k - 6):k])
                     or any(x[0] for x in merged[-6:]) or k - 1 in cast)):
            merged.append((m, b, seq[k + 1]))
            k += 2
            continue
        merged.append((None, b, k in cast))
        k += 1
    items = [{"kind": "front", "source": b} for b in head]
    note = False
    for label, b, extra in merged:
        if label:
            d = label.group("d")
            lead = [{"direction": d[1:-1].strip(" _")}] if d and d[1:-1].strip(" _") else []
            if lead and MIC.match(lead[0]["direction"]):
                lead = [{"mic": lead[0]["direction"]}]
            items.append({"kind": "speech", "role": _role(label.group("name")), "source": b + "\n" + extra,
                          "text": extra, "lead": lead})
            note = False
            continue
        if extra:
            items.append({"kind": "cast", "source": b})
            continue
        if R_NOTE.match(b):
            items.append({"kind": "note", "source": b})
            note = True
            continue
        m = CUE.match(b)
        if m:
            items.append({"kind": next(k for k in CUE_TAGS if m.group(k)), "source": b})
            note = False
            continue
        m = R_ROLE.match(b) or R_ROLE_SPACED.match(b)
        if m and re.search(r"[a-z]", m.group("role")) and mixed[m.group("role")] < 3 and (
                note or len(m.group("role").split()) > 2 or m.group("role").split()[0] in NOT_LABEL):
            m = None
        if m and not NOTROLE.match(m.group("role").strip()) and len(m.group("role").split()) <= 5:
            note = False
            role = _role(m.group("role"))
            if SOUNDROLE.search(role):
                items.append({"kind": "sound", "source": b})
                continue
            text = b[m.start("text"):]
            lead = [{"direction": m.group("paren").strip()}] if m.group("paren") else []
            if lead and MIC.match(lead[0]["direction"]):
                lead = [{"mic": lead[0]["direction"]}]
            items.append({"kind": "speech", "role": role, "source": b, "text": text, "lead": lead})
            continue
        if note:
            items.append({"kind": "note", "source": b})
            continue
        if R_BARE_CUE.match(re.sub(r"(?<=\b\w) (?=\w\b)", "", b)):
            items.append({"kind": "music" if R_BARE_CUE.match(re.sub(r"(?<=\b\w) (?=\w\b)", "", b)).group("music")
                          else "sound", "source": b})
            continue
        if SEPARATOR.match(b):
            items.append({"kind": "heading", "source": b})
            continue
        if re.match(r"^\(.*\)$", b, re.S) or _bare(b):
            items.append({"kind": "direction", "source": b})
            continue
        if re.search(r"[A-Z]{2}", b) and not re.search(r"[a-z]", b):
            # a capitals line that is not a role: an unlabeled cue or a scene heading
            items.append({"kind": "sound" if SOUNDROLE.search(b) or SOUNDWORD.search(b) else "direction",
                          "source": b})
            continue
        if items and items[-1]["kind"] == "speech":
            # a speech printed over several paragraphs
            items[-1]["source"] += "\n\n" + b
            items[-1]["text"] += "\n" + b
            items[-1]["continued"] = items[-1].get("continued", 0) + 1
            continue
        items.append({"kind": "other", "source": b})
    # before the play's first cast list, speech, or cue, and after its last speech or cue:
    # title pages, prefaces, and closing notes, kept with their words, never lines
    play = [i for i, it in enumerate(items) if it["kind"] in ("cast", "speech", "music", "sound")]
    if play:
        for i, it in enumerate(items):
            if (i < play[0] and it["kind"] not in ("cast", "note")) or (i > play[-1] and it["kind"] == "other"):
                it["kind"] = "front" if i < play[0] else "back"
    return items


# ---- stage ---------------------------------------------------------------------------------------

def _not_label(role):
    return role in NOT_LABEL or role.split()[0] in NOT_LABEL or bool(HEADING.match(role)) \
        or bool(ENTRANCE.match(role)) or bool(NOT_STAGE_ROLE.match(role.upper()))


def frequent_labels(text):
    counts = collections.Counter()
    for line in text.split("\n"):
        m = LABEL_MIXED.match(line)
        if m and not _not_label(m.group("role")):
            counts[m.group("role")] += 1
    return {k for k, n in counts.items() if n >= 3}


def known_names(text):
    """Names the text prints as names: words in capitals, and the capitalized words of an
    entrance line ("Enter Barnardo and Francisco"); with each one's leading 4+ letters, so
    a fuller form of a label ("_Arnol_." beside "Arn." and "Enter Arnoldo") is known too."""
    names = {w.upper() for w in re.findall(r"\b[A-ZÀ-Þ][A-ZÀ-Þ'’]{2,}\b", text)}
    for line in text.split("\n"):
        if re.search(r"\b(Enter|Re-?enter|Exit|Exeunt)\b", line):
            names.update(w.upper() for w in re.findall(r"\b[A-ZÀ-Þ][a-zà-ÿ'’]{2,}\b", line))
    return {n[:k] for n in names for k in range(4, len(n) + 1)} | names


def _label(name, labels, names=None):
    """The label a line opens with, or None. A full name that expands a frequent abbreviated
    label ("Barnardo." for "Bar."/"Barn.", "_Clapboard._" for "_Clap._") is that label's role
    when the text also prints the name as a name (capitals, or an entrance)."""
    if name in labels:
        return name
    if not names or " " in name or _not_label(name) or name.upper() not in names:
        return None
    grown = [f for f in labels if 2 <= len(f) < len(name) and name.startswith(f)]
    return max(grown, key=len) if grown else None


def _stage_paras(text, labels, names=None):
    """Blank-line paragraphs, split again where a line opens with a known label or an
    entrance. An entrance inside a speech stands alone, and the verse after it is marked
    as that speech continuing (Folio-style texts print them so)."""
    out = []
    for p in re.split(r"\n\s*\n", text):
        cur, cont = [], False
        for line in p.split("\n"):
            m = LABEL_MIXED.match(line)
            if cur and m and _label(m.group("role"), labels, names):
                out.append(("\n".join(cur), cont))
                cur, cont = [], False
            elif cur and ENTRANCE.match(line):
                out.append(("\n".join(cur), cont))
                out.append((line, False))
                cur, cont = [], True
                continue
            cur.append(line)
        out.append(("\n".join(cur), cont))
    return [(x.strip(), c) for x, c in out if x.strip()]


def _caps_role(role):
    r = role.strip(" ._")
    return len(role.split()) <= 4 and not HEADING.match(role) and r.upper() == r and bool(re.search(r"[A-ZÀ-Þ]{2}", r)) \
        and not NOT_STAGE_ROLE.match(r) and not ROMAN.match(r)


def _speaker(line, labels, names):
    m = LABEL_MIXED.match(line)
    if m and _label(m.group("role"), labels, names):
        return _role(_label(m.group("role"), labels, names))
    for rx in (S_ROLE_OWN, S_ROLE_COLON, S_ROLE_INLINE):
        m = rx.match(line)
        if m and _caps_role(m.group("role")):
            return _role(m.group("role"))
    return None


RUN_WINDOW, RUN_SPEECHES, START_REACH = 8, 4, 60


def play_bounds(paras, labels, names):
    """[start, end) of the play among blank-line paragraphs. The play is where speech is
    sustained: a window of 8 paragraphs with 4+ speeches by 2+ speakers who each speak
    twice (a publisher's catalog or a title page names each title once). It begins at the
    earliest cast list, act or scene heading, or first entrance within 60 paragraphs before
    that first run, and ends at the last speech by a recurring speaker, carried through the
    directions and verse after it up to an END/CURTAIN heading or a non-play break."""
    firsts = [p.split("\n")[0].strip() for p in paras]
    sp = [_speaker(f, labels, names) for f in firsts]

    def run_at(i):
        if not sp[i]:
            return False
        w = [s for s in sp[i:i + RUN_WINDOW] if s]
        c = collections.Counter(w)
        return len(w) >= RUN_SPEECHES and sum(1 for v in c.values() if v >= 2) >= 2

    first = next((i for i in range(len(paras)) if run_at(i)), None)
    if first is None:
        return 0, len(paras)

    def marks(i):
        f, n = firsts[i], len(paras[i].split("\n"))
        if CASTHEAD.match(f) or ENTER_LINE.match(f):
            return True
        if re.match(r"^_?SCENE\s*(?:[:.]|[.—–-]{1,2})", f):
            return True
        return bool(PLAY_MARK.match(f)) and n <= 3 and (f.upper() == f or re.match(
            r"^_?(Act|Actus|Scene|Scena|Scoena|Prologue|Induction)\b[ .]+\w", f))

    start = next((i for i in range(max(0, first - START_REACH), first) if marks(i)), first)
    counts = collections.Counter(s for s in sp[start:] if s)
    last = max((i for i in range(start, len(paras)) if sp[i] and counts[sp[i]] >= 3), default=first)
    end = last + 1
    while end < len(paras):
        f = firsts[end]
        if END_HEAD.match(f):
            end += 1
            break
        if SEPARATOR.match(f) or BACK_START.search(f) or (f.upper() == f and re.search(r"[A-ZÀ-Þ]{2}", f)):
            break
        end += 1
    return start, end


def _stage_items(text):
    raw = [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]
    names = known_names(text)
    start, end = play_bounds(raw, frequent_labels(text), names)
    body = "\n\n".join(raw[start:end])
    labels = frequent_labels(body)
    paras = _stage_paras(body, labels, names)
    items = [{"kind": "front", "source": p} for p in raw[:start]]
    pending, pending_src, incast, casts, last_role = None, None, False, 0, None
    for p, cont in paras:
        if items and items[-1]["kind"] in ("speech", "heading", "cast"):
            last_role = items[-1].get("role")
        lines = p.split("\n")
        first = lines[0].strip()
        if CASTHEAD.match(first):
            incast, casts, pending = True, casts + 1, None
            items.append({"kind": "cast", "source": p})
            continue
        if incast:
            lab = LABEL_MIXED.match(first)
            speaks = (lab and _label(lab.group("role"), labels, names)) or S_ROLE_COLON.match(first) \
                or ENTRANCE.match(first) or re.match(r"^_?SCENE\b", first, re.I)
            if not speaks and (CASTSUB.match(first) or CAST_ENTRY.match(first)
                               or all(len(l.strip()) < 70 for l in lines)):
                items.append({"kind": "cast", "source": p})
                continue
            incast = False
        if SEPARATOR.match(p) or (HEADING.match(first) and len(lines) <= 3 and first.upper() == first) \
                or (LATIN_HEAD.match(first) and len(lines) <= 2):
            items.append({"kind": "heading", "source": p})
            pending = None
            continue
        m = S_ROLE_OWN.match(first)
        if m and len(m.group("role").split()) <= 4 and not HEADING.match(m.group("role")) \
                and not NOT_STAGE_ROLE.match(m.group("role").strip(" ._")):
            rest = "\n".join(l.strip() for l in lines[1:]).strip()
            lead = [{"direction": m.group("d").strip("[]() _")}] if m.group("d") else []
            if rest:
                items.append({"kind": "speech", "role": _role(m.group("role")), "source": p, "text": rest, "lead": lead})
                pending = None
            else:
                pending, pending_src = (_role(m.group("role")), lead), p
            continue
        joined = " ".join(l.strip() for l in lines)
        m = LABEL_MIXED.match(joined)
        if m and _label(m.group("role"), labels, names):
            items.append({"kind": "speech", "role": _role(_label(m.group("role"), labels, names)), "source": p,
                          "text": m.group("text")})
            pending = None
            continue
        m = S_ROLE_COLON.match(joined) or S_ROLE_INLINE.match(joined)
        if m and ROMAN.match(m.group("role").strip(" ._")):
            items.append({"kind": "heading", "source": p})
            pending = None
            continue
        if m and _caps_role(m.group("role")):
            items.append({"kind": "speech", "role": _role(m.group("role")), "source": p, "text": m.group("text")})
            pending = None
            continue
        if pending and re.match(r"^_?(SCENE|PLACE|TIME)\b", joined):
            pending = None
        if pending:
            items.append({"kind": "speech", "role": pending[0], "source": pending_src + "\n" + p, "text": joined,
                          "lead": pending[1]})
            pending = None
            continue
        if re.match(r"^[\[(_]", joined) or ENTRANCE.match(joined) or (m and NOT_STAGE_ROLE.match(m.group("role"))):
            items.append({"kind": "direction", "source": p})
            continue
        if cont and last_role:
            items.append({"kind": "speech", "role": last_role, "source": p, "text": joined, "continues": True})
            continue
        if items and items[-1]["kind"] == "speech":
            items[-1]["source"] += "\n\n" + p
            items[-1]["text"] += "\n" + joined
            items[-1]["continued"] = items[-1].get("continued", 0) + 1
            continue
        items.append({"kind": "other", "source": p})
    items += [{"kind": "back", "source": p} for p in raw[end:]]
    # plays are counted over the WHOLE text, so a play window never hides the others
    whole = [(p.split("\n")[0].strip(), len(p.split("\n"))) for p in raw]
    plays = max(sum(1 for f, _ in whole if CASTHEAD.match(f)),
                sum(1 for f, n in whole if n <= 3 and FIRST_ACT.match(f) and len(f.split()) <= 6
                    and not re.search(r"[—:–]", f)))
    return items, max(casts, plays)


# ---- the shared model ----------------------------------------------------------------------------

def stub_check(text, items=None):
    words = len(text.split())
    links = len(re.findall(r"https?://", text))
    if words < MIN_WORDS:
        return "link_page" if links else "too_short"
    if items is not None:
        speeches = sum(1 for i in items if i["kind"] == "speech")
        if speeches < MIN_SPEECHES:
            return "link_page" if links and words < 2000 else "format_unrecognized"
    return None


def parse(raw, kind):
    """kind: "radio" (a broadcast script) or "stage" (a Gutenberg play text)."""
    text = gutenberg_body(raw) if kind == "stage" or GUT_START.search(raw) else raw
    if kind == "radio":
        text = clean_html(text)
    stub = stub_check(text)
    casts = 0
    if stub:
        return {"status": "stub", "stub_kind": stub, "words": len(text.split())}
    if kind == "radio":
        items = _radio_items(text)
    else:
        items, casts = _stage_items(text)
    stub = stub_check(text, items)
    if stub == "format_unrecognized":
        return {"status": "failed", "issues": [stub], "words": len(text.split())}
    if stub:
        return {"status": "stub", "stub_kind": stub, "words": len(text.split())}
    lines, roles, unclassified = [], collections.OrderedDict(), []
    for it in items:
        if it["kind"] in ("cast", "heading", "note", "front", "back"):
            continue
        if it["kind"] == "other":
            unclassified.append(it["source"])
            continue
        lid = f"L{len(lines) + 1:04d}"
        if it["kind"] == "speech":
            parts = (it.get("lead") or []) + split_parts(it["text"], italic=kind == "stage")
            r = roles.setdefault(it["role"], {"name": it["role"], "lines": 0, "words": 0})
            r["lines"] += 1
            r["words"] += sum(len(p["say"].split()) for p in parts if "say" in p)
            lines.append({"id": lid, "kind": "speech", "role": it["role"], "source": it["source"], "parts": parts})
        else:
            lines.append({"id": lid, "kind": it["kind"], "role": None, "source": it["source"]})
    blocks = len(lines) + len(unclassified)
    castable = [r for r in roles.values() if r["lines"] >= CASTABLE_LINES]
    big = [r["name"] for r in castable]
    aliases = [r["name"] for r in roles.values() if r["lines"] <= 2 and any(
        r["name"] != b and (b.startswith(r["name"]) or r["name"].startswith(b)) for b in big)]
    issues = []
    share = len(unclassified) / max(1, blocks)
    if share > CLEAN_UNCLASSIFIED:
        issues.append("unclassified_over_5pct")
    if len(castable) < 2:
        issues.append("fewer_than_two_castable_roles")
    if casts > 1:
        issues.append("several_plays_in_one_text")
    aside = sum(len(i["source"].split()) for i in items if i["kind"] in ("front", "back"))
    aside_share = aside / max(1, sum(len(i["source"].split()) for i in items))
    if aside_share > CLEAN_SET_ASIDE:
        issues.append("mostly_set_aside")
    if aliases:
        issues.append("possible_aliases")
    clean = not any(i in issues for i in ("unclassified_over_5pct", "fewer_than_two_castable_roles",
                                          "several_plays_in_one_text", "mostly_set_aside"))
    return {"status": "parsed", "clean": clean, "issues": issues, "roles": list(roles.values()),
            "castable_roles": len(castable), "lines": lines, "unclassified": unclassified,
            "unclassified_share": round(share, 3), "aliases": aliases, "words": len(text.split()),
            "set_aside": {k: sum(1 for i in items if i["kind"] == k) for k in ("front", "back")},
            "set_aside_share": round(aside_share, 3), "printed_title": printed_title(text, lines)}


def printed_title(text, lines):
    """The play's own title as its text prints it: the first short capitals paragraph
    before the first speech. A collected-works record names the volume, not the play."""
    first = next((l["source"] for l in lines if l["kind"] == "speech"), None)
    for p in re.split(r"\n\s*\n", text):
        p = p.strip()
        if not p:
            continue
        if first is not None and first.startswith(p[:40]):
            break
        head = p.split("\n")[0].strip(" _.")
        if head and len(head.split()) <= 10 and re.search(r"[A-Z]", head) and head.upper() == head \
                and not HEADING.match(head) and not CASTHEAD.match(head):
            return head
    return None


# ---- the measurement -----------------------------------------------------------------------------

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "..", ".cache")


def _summary(results):
    parsed = [r for r in results if r["status"] == "parsed"]
    fail = collections.Counter()
    for r in results:
        if r["status"] == "stub":
            fail["stub:" + r["stub_kind"]] += 1
        elif r["status"] == "failed":
            fail.update(r["issues"])
        else:
            fail.update(i for i in r["issues"])
    med = lambda xs: statistics.median(xs) if xs else None
    return {"sample": len(results), "stubs": sum(r["status"] == "stub" for r in results),
            "failed": sum(r["status"] == "failed" for r in results), "parsed": len(parsed),
            "clean": sum(r["clean"] for r in parsed),
            "roles_median": med([len(r["roles"]) for r in parsed]),
            "castable_roles_median": med([r["castable_roles"] for r in parsed]),
            "castable_roles_range": [min((r["castable_roles"] for r in parsed), default=None),
                                     max((r["castable_roles"] for r in parsed), default=None)],
            "speeches_median": med([sum(1 for l in r["lines"] if l["kind"] == "speech") for r in parsed]),
            "unclassified_share_median": med([r["unclassified_share"] for r in parsed]),
            "failure_kinds": dict(fail)}


def measure():
    grw = sorted(glob.glob(os.path.join(CACHE, "grw", "text", "*.txt")))
    sample = random.Random(20261022).sample(grw, 50)
    rows = []
    for f in sample:
        r = parse(open(f, encoding="utf-8", errors="replace").read(), "radio")
        rows.append({"id": os.path.basename(f)[:-4], **{k: r.get(k) for k in ("status", "stub_kind", "clean", "issues",
                                                                               "castable_roles", "unclassified_share",
                                                                               "words")},
                     "roles": len(r.get("roles") or [])})
        r["_id"] = rows[-1]["id"]
        rows[-1]["_r"] = r
    plays = sorted(glob.glob(os.path.join(CACHE, "gutenberg", "text", "*.txt")))
    prow = []
    for f in plays:
        r = parse(open(f, encoding="utf-8", errors="replace").read(), "stage")
        prow.append({"id": "gut-" + os.path.basename(f)[:-4], "_r": r})
    out = {"grw": _summary([x["_r"] for x in rows]), "gutenberg": _summary([x["_r"] for x in prow]),
           "grw_rows": [{k: v for k, v in x.items() if k != "_r"} for x in rows],
           "gutenberg_rows": [{"id": x["id"], "status": x["_r"]["status"], "stub_kind": x["_r"].get("stub_kind"),
                               "clean": x["_r"].get("clean"), "issues": x["_r"].get("issues"),
                               "roles": len(x["_r"].get("roles") or []), "castable_roles": x["_r"].get("castable_roles"),
                               "unclassified_share": x["_r"].get("unclassified_share"), "words": x["_r"].get("words")}
                              for x in prow]}
    json.dump(out, sys.stdout, indent=1)
    print()


if __name__ == "__main__":
    if sys.argv[1:] == ["measure"]:
        measure()
    elif len(sys.argv) == 3:
        r = parse(open(sys.argv[2], encoding="utf-8", errors="replace").read(), sys.argv[1])
        json.dump(r, sys.stdout, indent=1, ensure_ascii=False)
        print()
    else:
        raise SystemExit("usage: script_parse.py measure | script_parse.py radio|stage FILE")
