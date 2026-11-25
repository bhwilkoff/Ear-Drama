"""One spelling of a text for both sides of the search (R4-9 section 2.1).

Words only: lowercase, no accents, no apostrophes, brackets and speaker labels dropped. No table of old
spellings: modernized copies were found 12 of 12 without one.
"""
import collections
import html
import re
import unicodedata

WORD = re.compile(r"[a-z0-9']+")
SPAN = re.compile(r"\[[^\[\]]{0,240}\]|\([^()]{0,240}\)")
LABEL = re.compile(r"^[ \t_*]*([A-Z][A-Za-z.'’\- ]{0,30}?)[ _*]*(?:[.:;][_*]*|(?=\n|$))(?=\s|$)")
SENTENCE = re.compile(r"(?<=[.!?])\s+|\n+")


def words(text):
    t = text
    if not t.isascii():
        t = unicodedata.normalize("NFKD", t.replace("’", "'").replace("‘", "'"))
        t = "".join(c for c in t if not unicodedata.combining(c))
    return [x.replace("'", "") for x in WORD.findall(t.replace("_", "").lower())]


def strip_labels(text):
    """Speaker labels that open three paragraphs or more, and bracketed spans, are not words of the play."""
    text = SPAN.sub(" ", text)
    paras = re.split(r"\n\s*\n|\n(?=[A-Z][A-Z .'’]{1,24}[.:])", text)
    n, hit = collections.Counter(), []
    for p in paras:
        m = LABEL.match(p)
        lab = m.group(1).strip().lower() if m else None
        hit.append((p, m, lab))
        if lab and len(lab.split()) <= 4:
            n[lab] += 1
    return "\n".join(p[m.end():] if m and n[lab] >= 3 else p for p, m, lab in hit)


def sentences(text):
    return [s for s in SENTENCE.split(text) if s and s.strip()]


def gut_body(raw):
    t = raw.replace("\r", "")
    a = re.search(r"\*\*\* ?START OF TH(?:E|IS) PROJECT GUTENBERG[^\n]*\n", t)
    b = re.search(r"\*\*\* ?END OF TH(?:E|IS) PROJECT GUTENBERG", t)
    return t[a.end() if a else 0: b.start() if b else len(t)]


def grw_body(raw):
    t = raw.replace("\r", "")
    t = re.sub(r"<br\s*/?>", "\n", t, flags=re.I)
    t = re.sub(r"</p>", "\n\n", t, flags=re.I)
    return html.unescape(re.sub(r"<[^>]+>", "", t))


def norm_title(t):
    t = re.sub(r"^(the|a|an)\s+", "", (t or "").lower().strip())
    return re.sub(r"[^a-z0-9]", "", t)


def title_keys(t):
    """The whole title and the part before a colon or '; or,'."""
    head = re.split(r"[\n\r:;]", t or "")[0]
    return [k for k in dict.fromkeys([norm_title(t), norm_title(head)]) if k]
