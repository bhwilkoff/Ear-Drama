"""Rights classes and conservative matching for photographs and graphics from
archives other than Wikimedia Commons (reports/F-photo-archives.md).

Rights are classed from the archive's OWN statement on the record, quoted
verbatim beside the class; nothing is inferred from a photo's look or age
alone. Owner rule (2026-10): no human review queue — an image is used when
its own record carries public-domain or free-licence evidence a reader can
open, and removed on request.

    no_known_restrictions  the record says "No known restrictions" (LoC), or
                           is marked public domain / CC0 by the holder
    government             a US federal work (OWI, FSA, WPA Federal Theatre
                           Project, a federal agency named as creator), AND
                           the record does not say publication is restricted
    restricted             the record says publication may be / is restricted,
                           copyright, or permission required
    cc0                    the holder marks the image file itself CC0
                           (Smithsonian Open Access per-media usage)
    unknown                anything else ("Rights status not evaluated", no
                           statement, served by appointment only)

`usable` = class is no_known_restrictions or government AND an image file is
online. A restriction on the record always beats a government creator: a
World-Telegram print of an OWI photo that says "Publication may be restricted"
is restricted (LoC applies it because the print may come from a wire service).
"""
import re
import unicodedata

USABLE = ("no_known_restrictions", "government", "cc0")

_RESTRICT = re.compile(
    r"publication (?:may be|is) restricted|restricted|copyright(?:ed)?\b(?! (?:status )?(?:not|undetermined|unknown))|"
    r"permission (?:is )?required|in copyright|all rights reserved", re.I)
_NKR = re.compile(r"\bno known (?:copyright )?restrictions\b|\bno known copyright\b|\bpublic domain\b|\bcc0\b|"
                  r"\bno copyright\b", re.I)
_UNEVAL = re.compile(r"rights status not evaluated|not evaluated|undetermined|unknown", re.I)
# Federal creators. Matched against contributor / collection / call number text.
_GOV = re.compile(
    r"office of war information|farm security administration|\bowi\b|\bfsa\b|federal theatre project|"
    r"work projects administration|works progress administration|united states\.\s*(?:army|navy|office|department|"
    r"war|federal|signal|coast guard|marine|bureau|national|information)|\bu\.s\. (?:army|navy|signal corps|"
    r"office of war information)|national archives|signal corps|department of (?:agriculture|the interior|war|"
    r"state|commerce)", re.I)


def rights_class(statement, creator_text=""):
    """(class, why). `statement` is the record's rights text verbatim; `creator_text`
    joins contributor, collection and call-number strings."""
    s = (statement or "").strip()
    if s and _RESTRICT.search(s) and not re.search(r"\bno known restrictions\b", s, re.I):
        return "restricted", "record states a restriction"
    if s and re.search(r"\bno known restrictions\b", s, re.I) and re.search(r"publication may be restricted", s, re.I):
        return "restricted", "record states a restriction"
    if _GOV.search(creator_text or "") and (not s or _NKR.search(s) or not _UNEVAL.search(s)):
        if s and not _NKR.search(s) and s.lower().startswith("served by appointment"):
            return "unknown", "government creator but the record is not served online"
        return "government", "federal creator named on the record"
    if s and _NKR.search(s):
        return "no_known_restrictions", "record states no known restrictions / public domain"
    return "unknown", "no free statement on the record" if s else "no rights statement on the record"


def fold(s):
    s = unicodedata.normalize("NFKD", s or "")
    s = "".join(ch for ch in s if not unicodedata.combining(ch)).lower()
    s = s.replace("&", " and ").replace("'n'", " and ").replace("’", "'")
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9' ]", " ", s)).strip()


# Words that put a record in broadcasting. "studio", "program" and "show" are
# deliberately absent: a photographer's studio and a theater program are not radio.
RADIO_WORDS = re.compile(
    r"\b(radio|broadcast\w*|microphones?|announcer|nbc|cbs|mutual broadcasting|blue network|wjz|weaf|wabc|"
    r"wgn|wmaq|kdka|on the air|sound effects?|transcriptions?)\b")

# A series name that is an ordinary word or phrase is never matched by name
# alone in an archive's free text ("Suspense", "The Shadow", "Escape").
GENERIC = set("""suspense escape shadow whistler mystery theater theatre the program show hour news music
quiz family hollywood broadway america american adventure adventures stories story tales drama comedy western
first nighter radio theater playhouse workshop hour half time series""".split())


def series_name_ok(name):
    """A series name long or particular enough to look for in free text."""
    f = fold(name)
    f = re.sub(r"^the ", "", f)
    toks = f.split()
    if not toks:
        return False
    if len(toks) == 1:
        return len(toks[0]) >= 7 and toks[0] not in GENERIC
    content = [t for t in toks if t not in GENERIC and t not in ("of", "and", "a", "an", "in", "on")]
    return len(content) >= 1 and len(f) >= 9


def phrase_in(phrase, text):
    p = fold(phrase)
    p = re.sub(r"^the ", "", p)
    if not p:
        return False
    return re.search(r"(?<![a-z0-9])" + re.escape(p) + r"(?![a-z0-9])", text) is not None


def year_of(s):
    m = re.search(r"(1[89]\d\d|20\d\d)", s or "")
    return int(m.group(1)) if m else None


_SER_INDEX = {}


def _series_index(series_rows):
    """folded name (leading 'the' dropped) -> [(key, name, fy, ly)], built once per list."""
    k = id(series_rows)
    if k not in _SER_INDEX:
        idx = {}
        for row in series_rows:
            if series_name_ok(row[1]):
                f = re.sub(r"^the ", "", fold(row[1]))
                idx.setdefault(f, []).append(row)
        _SER_INDEX.clear()
        _SER_INDEX[k] = (idx, max((len(f.split()) for f in idx), default=1))
    return _SER_INDEX[k]


def match_series(rec_text, rec_year, series_rows, radio_required=True):
    """series_rows: [(key, name, first_year, last_year)]. Returns list of
    (key, basis). A match needs the series' own name as a phrase, a radio word in
    the same record, and (when both are known) the record's year inside the
    series' run +/- 2. A record naming two series is kept for both."""
    text = fold(rec_text)
    if radio_required and not RADIO_WORDS.search(text):
        return []
    idx, longest = _series_index(series_rows)
    toks = text.split()
    seen, out = set(), []
    for n in range(1, min(longest, 12) + 1):
        for i in range(len(toks) - n + 1):
            for key, name, fy, ly in idx.get(" ".join(toks[i:i + n]), ()):
                if key in seen:
                    continue
                if rec_year and fy and ly and not (fy - 2 <= rec_year <= ly + 2):
                    continue
                seen.add(key)
                basis = f"series name '{name}' in record text"
                basis += f"; record year {rec_year} within run {fy}-{ly}" if rec_year and fy else "; no year to compare"
                out.append((key, basis))
    return out


_LIFESPAN = re.compile(r"^([^,]+),\s*([^,]+?)(?:,\s*(\d{4})\??-(\d{4})?)?\s*$")


def subject_names(subjects):
    """LoC name headings 'Benny, Jack, 1894-1974' -> [('jack benny', 1894, 1974)]."""
    out = []
    for s in subjects or []:
        s = re.split(r"--", s)[0].strip()
        m = _LIFESPAN.match(s)
        if not m or not m.group(3):
            continue
        last, first = m.group(1).strip(), re.sub(r"\(.*?\)", "", m.group(2)).strip()
        out.append((fold(f"{first} {last}"), int(m.group(3)), int(m.group(4)) if m.group(4) else None))
    return out


def name_ok(name):
    toks = fold(name).split()
    return len(toks) >= 2 and len("".join(toks)) >= 7


def match_people(rec_text, subjects, rec_year, name_index, people_years):
    """name_index: folded full name -> set(person ids). people_years: id -> (birth_year, death_year).
    A match needs a two-token name that resolves to ONE person; if the record's
    subject heading gives a lifespan it must agree with ours (+/- 1); if the
    record has a year, the person must have been alive (and over 10) then.
    Returns (matches [(pid, basis)], refused [(name, reason)])."""
    text = fold(rec_text)
    heads = subject_names(subjects)
    found, refused = [], []
    cands = [(n, "subject heading", b, d) for n, b, d in heads]
    seen = {c[0] for c in cands}
    toks = text.split()
    for k in (2, 3, 4, 5):
        for i in range(len(toks) - k + 1):
            n = " ".join(toks[i:i + k])
            if n in name_index and n not in seen:
                seen.add(n)
                cands.append((n, "record text", None, None))
    for n, how, hb, hd in cands:
        ids = name_index.get(n)
        if not ids or not name_ok(n):
            continue
        if len(ids) > 1:
            refused.append((n, f"name resolves to {len(ids)} people"))
            continue
        if how == "record text" and not RADIO_WORDS.search(text):
            refused.append((n, "name in free text with no radio word on the record"))
            continue
        pid = next(iter(ids))
        by, dy = people_years.get(pid, (None, None))
        if hb and by and abs(hb - by) > 1:
            refused.append((n, f"lifespan on record {hb} vs ours {by}"))
            continue
        if hd and dy and abs(hd - dy) > 1:
            refused.append((n, f"death year on record {hd} vs ours {dy}"))
            continue
        if rec_year and by and rec_year < by + 10:
            refused.append((n, f"record year {rec_year} before person aged 10 (born {by})"))
            continue
        if rec_year and dy and rec_year > dy + 1:
            refused.append((n, f"record year {rec_year} after death {dy}"))
            continue
        basis = f"name '{n}' in {how}"
        if hb and by:
            basis += f"; lifespan agrees ({hb})"
        found.append((pid, basis))
    return found, refused


_SITTER = re.compile(r"^(.+?),\s*(?:c\.\s*)?(?:\d{1,2}\s+\w{3}\s+)?(\d{4}|\?)\s*-\s*(?:c\.\s*)?(?:\d{1,2}\s+\w{3}\s+)?(\d{4})?\s*$")


def sitters(names):
    """NPG name lines 'Orson Welles, 6 May 1915 - 10 Oct 1985' -> [('orson welles', 1915, 1985)]."""
    out = []
    for s in names or []:
        m = _SITTER.match(s.strip())
        if m:
            b = int(m.group(2)) if m.group(2) and m.group(2) != "?" else None
            d = int(m.group(3)) if m.group(3) else None
            out.append((fold(m.group(1)), b, d))
    return out


def match_portrait(title, sitter_list, name_index, people_years):
    """A portrait: the record's own title is the sitter's name, that name resolves
    to ONE of our people, and the sitter's printed lifespan agrees with ours
    (birth or death year within 1). With no year on either side to compare, the
    name alone is refused — a portrait gallery holds many people of one name."""
    t = fold(title)
    found, refused = [], []
    for n, b, d in sitter_list:
        if n != t or not name_ok(n):
            continue
        ids = name_index.get(n)
        if not ids:
            continue
        if len(ids) > 1:
            refused.append((n, f"name resolves to {len(ids)} people"))
            continue
        pid = next(iter(ids))
        by, dy = people_years.get(pid, (None, None))
        agree = [x for x in ((b, by), (d, dy)) if x[0] and x[1]]
        if not agree:
            refused.append((n, "portrait with no lifespan to compare"))
            continue
        if any(abs(x - y) > 1 for x, y in agree):
            refused.append((n, f"sitter lifespan {b}-{d} vs ours {by}-{dy}"))
            continue
        found.append((pid, f"portrait: record title is the sitter '{n}'; lifespan {b}-{d} agrees"))
    return found, refused
