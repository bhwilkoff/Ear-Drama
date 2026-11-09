"""A show's "about" text: the lead of its English Wikipedia article (catalog DECISIONS 030).

Owner, 2026-11-09: "Most people will have no idea what the shows are about and
they will need an entry point to know whether or not they should listen."

The text is human-written (CC BY-SA 4.0) and travels with its source, its URL and
its license; nothing here writes a word. A series gets one only when all hold, so
a wrong match is never published (a wrong "about" is worse than none):

    1. enrich_external.match_wikidata matched the series to a Wikidata item (a radio
       class or radio-program category, overlapping years, its own name);
    2. that item's English article is the page read, by its own Wikidata id (the
       page's `wikibase_item` is the matched qid, after redirects);
    3. the article is about a radio program: its short description says radio and
       names no person, character, franchise, station or network; or, with a short
       description of a program in no other medium or none at all, its first
       sentence names a radio program; the lead never opens on a person;
    4. the article's years agree with the series' (`years_ok`), and no editor refused
       the match (editorial/series_about_rejects.json, each row with its reason);
    5. the lead survives cleaning: whole paragraphs up to MAX_CHARS, else whole
       sentences of the first, never cut mid-sentence, at least MIN_CHARS.

The harvest (harvest_ext_wikipedia_about.py) stores what Wikipedia returned;
enrich_external.py applies this policy into `series_about`; the projection copies it.
"""
import re

SOURCE = "Wikipedia"
LICENSE = "CC BY-SA 4.0"
MAX_CHARS = 900
MIN_CHARS = 60

PROGRAM = re.compile(r"\b(program|programme|series|drama|dramas|show|serial|anthology|sitcom|soap opera|comedy|"
                     r"situation comedy|quiz|western|mystery|thriller|broadcast)\b", re.I)
# A short description naming one of these is about a person, a character or a franchise, not the show.
NOT_SHOW = re.compile(r"\b(actor|actress|singer|comedian|comedienne|ventriloquist|presenter|personality|"
                      r"announcer|writer|author|novelist|journalist|composer|musician|bandleader|"
                      r"broadcaster|executive|politician|businessman|"
                      r"character|characters|franchise|video game|album|episode)\b", re.I)
# ... or about a station or a network: the description ends on it ("American radio network").
NOT_SHOW_END = re.compile(r"\b(station|stations|network|networks|company|newspaper|magazine)\s*(\([^)]*\))?$", re.I)
# Without "radio" in it, a description naming another medium is that medium's article.
NOT_RADIO_FORM = re.compile(r"\b(film|films|television|tv|novel|comic|comics|video game|stage|album)\b", re.I)
PERSON_LEAD = re.compile(r"^[^.]{0,120}?\b(?:was|is) an? (?:[A-Z][a-z]+(?:-[A-Z][a-z]+)? )*(?:radio )?"
                         r"(?:actor|actress|singer|comedian|comedienne|ventriloquist|writer|author|announcer|"
                         r"personality|host|presenter|bandleader|musician|journalist|broadcaster|producer|director)\b")
ABBREV = re.compile(r"(?:\b(?:Mr|Mrs|Ms|Dr|St|Jr|Sr|Inc|Co|Corp|Ltd|Bros|vs|Vol|No|Mt|Ft|Gen|Col|Capt|Lt|Sgt|Rev|Prof|"
                    r"Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec|U\.S|U\.K|D\.C|a\.m|p\.m|e\.g|i\.e|a\.k\.a|"
                    r"etc|ca|c)|(?:^|[\s(])[A-Za-z])\.$")
# A hatnote the plain-text intro keeps ("For the 1946 film, see Breakfast in Hollywood (film).").
HATNOTE = re.compile(r"^(?:for (?:the|other|a|an)\b.*,? see\b|this article is about\b|not to be confused with\b|"
                     r"see also\b|.{0,80}\bredirects here\b)", re.I)
END = re.compile(r"[.!?][\"”’')\]]*$")


def clean(text):
    """Wikipedia's plain-text lead with the residue its stripped templates leave:
    hatnotes, empty or punctuation-only parentheses (a removed pronunciation or date),
    IPA in slashes, citation marks; paragraphs kept, spaces collapsed."""
    if not text:
        return []
    out = []
    for p in text.split("\n"):
        p = re.sub(r"\[(?:\d+|[a-z]|citation needed|note \d+)\]", "", p)
        p = re.sub(r"/[^/\s][^/]{0,40}/", lambda m: "" if re.search(r"[ˈˌəɪʊæɔʃʒθðŋː]", m.group(0)) else m.group(0), p)
        for _ in range(3):
            p = re.sub(r"\(\s*(?:listen|pronounced|;|,|\s)*\)", "", p)
            p = re.sub(r"\(\s*[;,]\s*", "(", p)
            p = re.sub(r"\s*[;,]\s*\)", ")", p)
        p = re.sub(r"\s+([,.;:!?])", r"\1", p)
        p = re.sub(r"\s{2,}", " ", p).strip()
        if p and not (not out and HATNOTE.match(p)):
            out.append(p)
    return out


def sentences(paragraph):
    """Whole sentences: split after . ! ? (and a closing quote or bracket) before a
    capital or an opening quote, never after an abbreviation or a lone initial."""
    parts, start = [], 0
    for m in re.finditer(r"[.!?][\"”’')\]]*(?=\s+[\"“'(]?[A-Z0-9])", paragraph):
        if m.group(0)[0] == "." and ABBREV.search(paragraph[max(0, m.start() - 8):m.start() + 1]):
            continue
        parts.append(paragraph[start:m.end()].strip())
        start = m.end()
    tail = paragraph[start:].strip()
    if tail:
        parts.append(tail)
    return parts


def trim(paragraphs, limit=MAX_CHARS):
    """Whole paragraphs while they fit and each ends a sentence (one ending on a colon
    introduces a quotation the intro does not carry); else whole sentences of the first.
    None when even the first sentence is over the limit or nothing ends a sentence."""
    kept = []
    for p in paragraphs:
        size = sum(len(k) for k in kept) + 2 * len(kept) + len(p)
        if size > limit or not END.search(p):
            break
        kept.append(p)
    if not kept and paragraphs:
        got = ""
        for s in sentences(paragraphs[0]):
            nxt = (got + " " + s).strip()
            if len(nxt) > limit or not END.search(s):
                break
            got = nxt
        kept = [got] if got else []
    text = "\n\n".join(kept)
    return text if text and END.search(text) else None


def gate(page, qid):
    """(ok, reason) for one harvested page against the series' matched qid."""
    if not page or page.get("missing"):
        return False, "missing"
    if page.get("disambiguation"):
        return False, "disambiguation"
    if (page.get("title") or "").startswith("List of"):
        return False, "list_page"
    if page.get("qid") != qid:
        return False, "qid_mismatch"
    paras = clean(page.get("extract"))
    if not paras:
        return False, "no_lead"
    first = sentences(paras[0])[0]
    lead2 = " ".join(sentences(paras[0])[:2])
    sd = (page.get("shortdesc") or "").strip()
    radio = lambda t: bool(re.search(r"\bradio\b", t, re.I))  # noqa: E731
    if PERSON_LEAD.search(first):
        return False, "lead_is_a_person"
    if sd and (NOT_SHOW.search(sd) or (NOT_SHOW_END.search(sd) and not PROGRAM.search(sd))):
        return False, "shortdesc_not_the_show"
    if sd and radio(sd):
        return True, None
    if sd and (not PROGRAM.search(sd) or NOT_RADIO_FORM.search(sd)):
        return False, "shortdesc_not_radio"
    if not (radio(first) and PROGRAM.search(first)):
        return False, "lead_not_a_radio_program"
    if not radio(lead2):
        return False, "lead_not_radio"
    return True, None


def _years(text):
    return [int(y) for y in re.findall(r"\b(1[89]\d\d|20\d\d)\b", text or "")]


def years_ok(page, years):
    """(ok, reason): the article's own years against the series' (first, last) years.
    A title qualified by a year ("(1968 radio drama)", "(1954–1956)") is one version
    of several, so the series must begin within two years of it, and a series with no
    dated episode cannot be told which version it is. A range in the short description
    ("(1940–1946)", "1933–55") must overlap the series' run by two years; a single year
    ("1941 radio show") is when it began, so the series must not end before it."""
    first, last = years or (None, None)
    last = last or first
    q = re.search(r"\(([^)]*)\)\s*$", page.get("title") or "")
    qy = _years(q.group(1)) if q else []
    if qy:
        if first is None:
            return False, "version_years_unknown"
        if not (min(qy) - 2 <= first <= max(qy) + 2):
            return False, "version_years_disagree"
    sd = page.get("shortdesc") or ""
    if first is None:
        return True, None
    r = re.search(r"\b(1[89]\d\d|20\d\d)\s*(?:–|-|to)\s*(\d{4}|\d{2})\b", sd)
    if r:
        lo, hi = int(r.group(1)), r.group(2)
        hi = int(hi) if len(hi) == 4 else lo // 100 * 100 + int(hi)
        if hi < lo:
            hi += 100
        if last < lo - 2 or first > hi + 2:
            return False, "years_disagree"
    elif len(set(_years(sd))) == 1 and last < _years(sd)[0] - 2:
        return False, "years_disagree"
    return True, None


def about_of(page, qid, years=None, rejected=None):
    """({"text", "source", "url", "license", "fetched"}, None) or (None, reason).
    `years` is the series' (first, last) broadcast years; `rejected` the reason an
    editor recorded for refusing this article to this series (editorial/series_about_rejects.json)."""
    ok, why = gate(page, qid)
    if not ok:
        return None, why
    ok, why = years_ok(page, years)
    if not ok:
        return None, why
    if rejected:
        return None, "editorial_reject"
    text = trim(clean(page.get("extract")))
    if not text:
        return None, "untrimmable"
    if len(text) < MIN_CHARS:
        return None, "too_short"
    url = page.get("url") or ""
    if not url.startswith("https://en.wikipedia.org/wiki/"):
        return None, "no_url"
    return {"text": text, "source": SOURCE, "url": url, "license": LICENSE, "fetched": page.get("fetched")}, None


def load_rejects(path=None):
    """{series key: {"article", "reason", "checked"}}: a match an editor read and refused.
    A row names the article it refuses, so a later, different match is judged afresh."""
    import json
    import os
    path = path or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "editorial", "series_about_rejects.json")
    try:
        d = json.load(open(path, encoding="utf-8"))
    except FileNotFoundError:
        return {}
    return {k: v for k, v in d.items() if not k.startswith("_")}


def rejected_for(rejects, key, page):
    r = rejects.get(key)
    return r if r and page and r.get("article") == page.get("title") else None
