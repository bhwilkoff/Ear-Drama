"""What text a listener is shown, and what is withheld (owner ruling 2026-10-31, catalog DECISIONS 025).

Raw uploader text (a file name, an identifier, a folder date, a rip string) never reaches a display field; it
stays in the `raw_` columns for provenance and search. For each episode, in order:

  1. the source's title, cleaned (titles.py), when it reads as a title;
  2. a title composed from the episode's own data: "Suspense, April 26, 1952" (series name + air date) or
     "Gunsmoke, episode 112" (series name + number); the fields used are recorded, nothing is invented;
  3. otherwise the episode is withheld from the apps, with a reason code. It stays in the research database.

A series whose shown name is still an upload habit (a date, a run-together identifier, a lowercase
identifier, an uploader's grab bag with no program behind it) is withheld with all its episodes.
"""
import re

import field_defects as FD
import text_defects as TD

MONTHS = ("January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
          "November", "December")
FULL_DATE = re.compile(r"^(19\d\d|20\d\d)-(\d\d)-(\d\d)$")

GRAB_BAG = re.compile(r"^(?:otrr\s+)?(?:singles\s*(?:&|and)\s*doubles(?:\s+collection)?|misc(?:ellaneous)?|various|assorted|"
                      r"afrs\s+collection|old[- ]?time[- ]?radio(?:\s+(?:collection|shows?))?|odds\s*(?:&|and)\s*ends)$", re.I)
FILE_NAMED = re.compile(r"\d{6,}|[A-Za-z]\d{3,}[A-Za-z]|\b(?:x{3,}|afrs\d+)\b|[^\W\d_]{16,}", re.I)
COUNTED_BAG = re.compile(r"^\d[\d,]*\+?\s+(?:[A-Za-z']+\s+){0,3}(?:shows?|episodes?|programs?|programmes?|broadcasts?|recordings?)$", re.I)
GENRE_YEAR = re.compile(r"^[^\W\d_]+(?:\s+[^\W\d_]+){0,3}\s+(?:19|20)\d\d$")
V_DISC = re.compile(r"\bV[- ]?Discs?\b", re.I)
IDENTIFIER_TITLE = re.compile(r"^[^\W\d_]+\d+$")
HARD_TITLE = {"IDENT", "GLUED", "RIPTAG", "COUNT", "UPLOADER", "MOJIBAKE", "CODE", "FILE", "DOUBLED"}
INTRO_TRACK = re.compile(r"^(?:old[- ]time radio researchers(?: group)? (?:introduction|information)|otrr (?:introduction|information)|"
                         r"kbps(?:\[\d+\])?|old[- ]time radio(?: \d+)?)$", re.I)
HARD_NAME = {"IDENT", "GLUED", "RIPTAG", "COUNT", "UPLOADER", "MOJIBAKE", "CODE", "FILE", "DOUBLED"}
LONG_NAME = 60
GENERIC_TITLE = re.compile(r"^(?:(?:xx\s+)*no\s+title|(?:episode|ep|deel|program|file|track|nr|no|side|disc|show|production|tape|reel|recording)\.?\s*[\d.\-]*)$", re.I)
AIRED_FRAGMENT = re.compile(r"\b(?:aired|air\s?date)\s+[\d/ ,-]*$", re.I)

SCOPE_REASONS = {"concert": "out_of_scope_concert", "lecture": "out_of_scope_lecture", "music": "out_of_scope_music_set"}
SERIES_REASONS = {"S_DATED": "series_name_is_a_date", "S_RUNTOGETHER": "series_name_is_an_identifier",
                  "S_LOWER": "series_name_is_an_identifier", "S_COLLECTION": "series_is_an_uploaders_grab_bag"}


def series_withheld(shown_name, key, own_key):
    """The reason a series is not shown, or None. `own_key`: the series exists only because an upload named it
    (no spine, OTRR or editorial source knows it); a grab bag is judged only then."""
    if not shown_name:
        return "series_name_has_no_words"
    if not re.search(r"[^\W\d_]", shown_name):
        return "series_name_is_a_date" if "S_DATED" in TD.series_defects(shown_name, key) else "series_name_has_no_words"
    if not (key or "").startswith("librivox") and (len(shown_name) > LONG_NAME or FILE_NAMED.search(shown_name) or TD._runtogether(shown_name)):
        return "series_name_is_a_file_name"
    if own_key and (COUNTED_BAG.match(shown_name.strip()) or GENRE_YEAR.match(shown_name.strip())):
        return "series_is_an_uploaders_grab_bag"
    for c in TD.series_defects(shown_name, key):
        if c == "S_COLLECTION" and not (own_key or GRAB_BAG.match(shown_name.strip())):
            continue
        return SERIES_REASONS[c]
    if AIRED_FRAGMENT.search(shown_name) or set(FD.text_defects(shown_name, "name")) & HARD_NAME:
        return "series_name_is_a_file_name"
    return None


def readable_title(t):
    t = (t or "").strip()
    if not t or GENERIC_TITLE.match(t) or not re.search(r"[^\W\d_]{3}", re.sub(r"[\[{][^\]}]*[\]}]", " ", t)):
        return False
    bad = set(TD.title_defects(t)) & {"T_EMPTY", "T_RUNTOGETHER"}
    if bad:
        return False
    if " " not in t and t == t.lower() and not re.search(r"\d", t):
        return False   # one lowercase token: an identifier
    if IDENTIFIER_TITLE.match(t):
        return False   # one word and a number ("TopSecret15", "Hunting300"): a file name, not a title
    if set(FD.text_defects(t, "title")) & HARD_TITLE:
        return False   # a habit polish.py could not undo: composed from data or withheld
    return True


def episode_out_of_scope(title):
    """The reason an episode is not shown for being music, from its own title ("048 V-Disc A Chorus and Organ"), or None."""
    if INTRO_TRACK.match((title or "").strip()):
        return "out_of_scope_not_a_program"
    return "out_of_scope_music_record" if V_DISC.search(title or "") else None


def repair_apostrophe(shown, aliases):
    """A name the source spelled without its apostrophe, set back from a name a registry spells with it
    ("The Witchs Tale" from the alias "The Witch's Tale"): the same letters, one such spelling, no guess."""
    if not shown or re.search(r"['\u2019]", shown):
        return shown
    flat = lambda x: re.sub(r"['\u2019]", "", x).casefold()
    good = {a.strip() for a in aliases or () if re.search(r"\w['\u2019](?:s|t|re|ll|d|ve|m)\b|s['\u2019](?!\w)", a)
            and flat(a) == shown.casefold() and a != a.upper() and a != a.lower() and not TD.series_defects(a)}
    return good.pop() if len(good) == 1 else shown


def compose_title(series_name, air_date, num):
    """(title, fields used) from the episode's own data, or None."""
    m = FULL_DATE.match(air_date or "")
    if m and 1 <= int(m.group(2)) <= 12:
        return f"{series_name}, {MONTHS[int(m.group(2)) - 1]} {int(m.group(3))}, {m.group(1)}", ["series.name", "episodes.air_date"]
    if num:
        return f"{series_name}, episode {num}", ["series.name", "episodes.num"]
    return None


ISO_IN_TITLE = re.compile(r"(?<![\d])((?:19|20)\d\d)[-.](\d\d)[-.](\d\d)(?!\d)")


UPLOADER_NOTE = re.compile(r"\s*\*{2,}[^*]*\*{2,}")


def strip_uploader_note(text):
    """An uploader's asterisk-wrapped note ("The Shadow Recreations **Updated 1 27 **") is raw upload residue: removed."""
    return re.sub(r"\s{2,}", " ", UPLOADER_NOTE.sub("", text or "")).strip()


ARCHIVE_CODE = re.compile(r"\s*[(\[]\s*(?:[A-Z]{1,4}\s+)?(?:REEL|TAPE|DISC)\s*#?\d[\w.\-]*(?:\s+TRACK\s*\d+)?\s*[)\]]\s*$", re.I)


def strip_archive_code(title):
    """A trailing reel, tape or disc code an uploader added ("Poison Gas (BB REEL 0552)") is residue: removed."""
    return ARCHIVE_CODE.sub("", title or "").strip()


def drop_impossible_date(title):
    """A date no calendar holds ("1946-05-38", "1949-09-00") is a file name's code, not a date: it goes with
    the short code before it, or an "aka" tail, and the words of the title stay."""
    for m in ISO_IN_TITLE.finditer(title or ""):
        if 1 <= int(m.group(2)) <= 12 and 1 <= int(m.group(3)) <= 31:
            continue
        head, tail = title[:m.start()], title[m.end():].strip()
        if tail and len(head.split()) <= 2:
            return re.sub(r"^#\d+\s*", "", tail)
        if not tail:
            return re.sub(r"(?:\s*aka)?\s*\b[A-Za-z]{0,3}$", "", head)
    return title


def spell_iso_dates(title, air_date):
    """No ISO date on screen (owner 2026-11-04): a date the title repeats from the record's own air date is
    dropped with its brackets and separators (the date line already shows it); any other is spelled out."""
    def one(m):
        y, mo, d = m.group(1), int(m.group(2)), int(m.group(3))
        if not 1 <= mo <= 12 or not 1 <= d <= 31:
            return m.group(0)
        if f"{y}-{mo:02d}-{d:02d}" == (air_date or ""):
            return "\0"
        return f"{MONTHS[mo - 1]} {d}, {y}"
    t = ISO_IN_TITLE.sub(one, drop_impossible_date(title) or "")
    if "\0" in t:
        t = re.sub(r"\s*[\[(]\s*\0\s*[\])]|\s*[-\u2013\u2014:,]\s*\0|\0\s*[-\u2013\u2014:]\s*|\s*\0", "", t)
        t = re.sub(r"\(\s*\)|\[\s*\]", "", t)
    return re.sub(r"\s{2,}", " ", t).strip(" -\u2013\u2014:,")


TRACK_TAIL = re.compile(r"\.t\d{1,3}$", re.I)
XX_DATE = re.compile(r"^((?:19|20)\d\d)-xx-xx\b\s*[-–:]?\s*(?=\S)", re.I)
TAIL_TAG = re.compile(r"\s*\(([A-Z]{1,4})\)$")
BROADCASTERS = re.compile(r"^(?:[KW][A-Z]{2,3}|NBC|CBS|ABC|MBS|BBC|CBC|AFRS|AFRTS|AFN|RRG|DRF|TV|US|USA|UK|NYC)$")


XX_LEAD = re.compile(r"^(?:xx\s+)+(?=[A-Za-z]{2})")


def series_possessive(title, series_name):
    """"Tarzans First Birthday" in Tarzan is "Tarzan's First Birthday": a word that is the series' own one-word name
    and an s, before a capitalized word, is that name's possessive; the series' name is the witness to the spelling."""
    t = name_tokens(series_name or "")
    words = re.findall(r"[A-Za-z]+", series_name or "")
    if len(t) != 1 or len(t[0]) < 4:
        return title
    name = next((w for w in words if w.casefold() == t[0]), None)
    if not name or not name[0].isupper():
        return title
    return re.sub(rf"\b{name}s(?= [A-Z])", f"{name}'s", title)


def recurring_tags(titles):
    """The trailing "(DM)", "(JR)" codes a series' titles carry three times or more: a source's or uploader's shelf
    mark, not the program's words. A broadcaster's call letters or a network ("(NBC)", "(WOR)") is a fact, and stays."""
    seen = {}
    for t in titles:
        m = TAIL_TAG.search(t or "")
        if m and not BROADCASTERS.match(m.group(1)):
            seen[m.group(1)] = seen.get(m.group(1), 0) + 1
    return {c for c, n in seen.items() if n >= 3}


# Initials, then what an upload put after them: a date (the record's air date shows it), a six-digit date code, a
# "#" or zero-padded episode number, an SxxEyy code. A bare number stays ("MLM 100 Shares of Stock").
SERIES_CODE = re.compile(r"^([A-Z]{2,5})\b\s*(?:(?:19|20)?\d\d[-./]\d{1,2}[-./]\d{1,2}\b\s*)?(?:\d{6}\b\s*)?"
                         r"(?:(?:#\d{1,4}|0\d{1,3})[a-z]?\b\s*)?(?:[-\u2013:]\s*)?(?:S\d{1,2}E\d{1,3}\b\s*(?:[-\u2013:]\s*)?)?")


def strip_series_code(title, series_name):
    """A title led by its series' initials and a number ("OMB #001 1st Show" in Our Miss Brooks, "CGS #055 ..." in
    the Charlotte Greenwood Show, "STSA - S01E04 - ...") is the title after them: the initials restate the series."""
    t, whole = name_tokens(series_name or ""), tuple(_tokens(series_name or ""))
    inits = {i.upper() for i in _initials(t) | _initials(whole) if len(i) >= 2} if len(t) >= 2 else set()
    m = SERIES_CODE.match(title or "")
    if m and m.group(1) in inits and not BROADCASTERS.match(m.group(1)) and m.end() < len(title):
        return title[m.end():].strip()
    return title


def episode_text(shown, series_name, tags=()):
    """The P-10 classes undone on one title (owner 2026-11-09): a reel track tail ("Six Shooter.Gunsmoke Reel.t01"
    is the reel's name, so no title is left), a date an upload wrote as "1942-xx-xx" (its year kept at the end),
    the series' initials and number in front, a recurring trailing shelf code. Removes; never adds a word."""
    t = (shown or "").strip()
    if TRACK_TAIL.search(t):
        t = TRACK_TAIL.sub("", t).strip()
        if REEL_WORD.search(t) or _norm(t) == _norm(series_name):
            # "Suspense-The Pit and the Pendulum Reel.t01": the reel names its series, then one title.
            parts = [p for p in re.split(r"\s*(?:\.|\s-\s|-)\s*", REEL_WORD.sub("", t).strip(" -.")) if p.strip()]
            rest = [p for p in parts if name_tokens(p) != name_tokens(series_name or "")]
            return rest[0].strip() if len(parts) == 2 and len(rest) == 1 and len(rest[0].split()) >= 2 else ""
    m = XX_DATE.match(t)
    if m:
        t = f"{t[m.end():].strip()} ({m.group(1)})"
    t = XX_LEAD.sub("", t)
    t = strip_series_code(t, series_name)
    t = series_possessive(t, series_name)
    m = TAIL_TAG.search(t)
    if m and m.group(1) in tags and m.start() > 0:
        t = t[:m.start()].strip()
    return t


def decide_episode(shown, series_name, air_date, num, tags=()):
    """(title to show, source, fields, withheld reason): source is 'source' (the cleaned title) or 'composed'.
    A title that only repeats its series' name ("Louella Parsons" in Louella Parsons) is composed from the date or
    number when the record has one; with neither, the name is the work's own title and stays."""
    shown = spell_iso_dates(strip_archive_code(strip_uploader_note(episode_text(shown, series_name, tags))), air_date)
    restates = bool(shown) and bool(series_name) and _norm(shown) == _norm(series_name)
    if readable_title(shown) and not (restates and compose_title(series_name, air_date, num)):
        return shown, "source", ["episodes.title"], None
    got = compose_title(series_name, air_date, num)
    if got:
        return got[0], "composed", got[1], None
    return None, None, [], "no_readable_title_and_no_date_or_number"


def recover_name(shown, known, words=None):
    """A name spelled with its spaces lost ("annsothern"), set back from evidence: `known` maps the letters of a
    name a source spells properly (a person, another series, a registry program) to that spelling; else a split
    the catalog's own titles spell out (titles.Words.split). None when nothing matches, so the series stays withheld."""
    letters = re.sub(r"[^a-z0-9]", "", (shown or "").casefold())
    got = known.get(letters)
    if got and got != shown and not TD.series_defects(got):
        return got
    if words is not None and " " not in (shown or "") and len(letters) >= 10 and letters.isalpha():
        parts = words.split(letters)
        if parts:
            name = " ".join(p[:1].upper() + p[1:] for p in parts)
            if not TD.series_defects(name):
                return name
    return None


# ---- P-9: names an upload cut, numbered or strung together (owner ruling 2026-10-31; catalog DECISIONS 026) ----
# A class is undone only by removing words the uploader added (a cut-off tail, a page or episode code, a reel
# word, a track number, an uploader's initials), never by adding any: the residue is what the source spelled.
# A residue with no program behind it is withheld, with a reason, and counted.
UPLOADER_TAIL = re.compile(r"\s+D\.?\s?D\.?\s?Teoli\s+Jr\.?\s+A\.?\s?C\.?$", re.I)
CODE_TAIL = re.compile(r"\s*[-–]?\s*(?:s\d{1,2}\s?e\d{1,3}|ep\.?\s?\d{1,4}|deel\s?\d{1,3})$", re.I)
MONTH_TAIL = re.compile(r"\s+(?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\d{1,4}$", re.I)
GLUED_TAIL = re.compile(r"(?<=[a-z]{4})\d{2,3}$")
PAGE_TAIL = re.compile(r"\s+page\s?\d{1,3}$", re.I)
CUT_WORD = re.compile(r"(?:\s*[-–,]\s*|\s+)(part|side|vol|volume|disc|reel|episode|ep|chapter)\.?$", re.I)
# "On the Sunny Side" is whole: the word before Side is an adjective or a direction.
SIDE_OWNERS = {"sunny", "other", "dark", "bright", "wild", "west", "east", "north", "south", "flip", "seamy", "right",
               "wrong", "far", "near", "b", "a", "lighter", "brighter", "upper", "lower", "left", "blind"}
REEL_WORD = re.compile(r"\breels?\b", re.I)
DOT_JOIN = re.compile(r"(?<=[A-Za-z]{3})\.(?=[A-Za-z0-9])")
LOOSE_JOIN = re.compile(r"(?<=[A-Za-z])\.\s?(?=[A-Z0-9])")
ABBREVIATIONS = {"capt", "prof", "gen", "col", "sgt", "lieut", "dept", "gov", "rev", "mrs", "assn", "bros", "corp", "ltd", "inc"}
FRAGMENT_ONLY = re.compile(r"^(?:side|page|part|disc|reel|track|tape|cd)\s?[\d.\-]*[a-d]?$", re.I)
NUMBERED_STUB = re.compile(r"^(?:\w+\s+){0,2}no\.?\s?\d+$", re.I)
TRACK_NUMBER = re.compile(r"^(\d{1,3})([. ])\s*(?=\S)")
QUANTITY_WORDS = {"years", "year", "best", "minutes", "ways", "things", "reasons", "thousand", "hundred", "days", "men",
                  "women", "great", "greatest", "top", "most", "steps", "nights", "hours", "stories", "tales", "questions"}
P9_REASONS = {"fragment": "series_name_is_a_fragment", "reel": "series_is_a_reel_compilation",
              "programs": "series_name_joins_programs", "context": "series_name_has_no_context"}


def _letters(s):
    return len(re.sub(r"[^A-Za-z]", "", s))


def cut_residue(name):
    """The name with an upload's cut-off tail taken off (an unclosed bracket, a bare Part or Side), or the name."""
    n = (name or "").strip()
    if n.count("(") > n.count(")"):
        n = n[:n.rindex("(")]
    elif n.count("[") > n.count("]"):
        n = n[:n.rindex("[")]
    n = n.rstrip(" -–,;:").strip()
    m = CUT_WORD.search(n)
    if m and len(n[:m.start()].split()) >= 2:
        before = n[:m.start()].split()[-1].casefold().strip("'")
        if not (m.group(1).casefold() == "side" and before in SIDE_OWNERS):
            n = n[:m.start()].rstrip(" -–,;:").strip()
    return n


def cut_title(t):
    """An episode title an upload cut mid-bracket, with the unclosed bracket and what follows it taken off."""
    t = (t or "").strip()
    while t and (t.count("(") > t.count(")") or t.count("[") > t.count("]")):
        nxt = cut_residue(t)
        if nxt == t:
            break
        t = nxt
    return t


def _joined_parts(n):
    """The programs an upload joined with dots ("Boston Blackie.Shadow.Mystery Reel"), or [n]."""
    join = LOOSE_JOIN if REEL_WORD.search(n) else DOT_JOIN
    if "..." in n or not join.search(n):
        return [n]
    parts, last = [], 0
    for m in join.finditer(n):
        left = re.findall(r"[A-Za-z]+$", n[:m.start()])
        if (left and left[0].casefold() in ABBREVIATIONS) or n[:m.start()].count("(") > n[:m.start()].count(")"):
            continue
        parts.append(n[last:m.start()].strip())
        last = m.end()
    parts.append(n[last:].strip())
    return [p for p in parts if p]


def clean_series_name(name, key=None):
    """(shown name, reason): the name with this pass's classes undone, or (None, reason) when what is left has
    no program behind it. Classes: page or side fragment, cut-off tail, episode code, uploader's initials,
    a glued count or month, a reel compilation. A name no class touches comes back unchanged."""
    orig = strip_uploader_note(name)
    if not orig or (key or "").startswith("librivox"):
        return orig, None
    if FRAGMENT_ONLY.match(orig):
        return None, P9_REASONS["fragment"]
    n = UPLOADER_TAIL.sub("", orig)
    parts = _joined_parts(n)
    reel = [p for p in parts if REEL_WORD.search(p)]
    solid = [p for p in parts if not REEL_WORD.search(p)]
    if reel:
        if len(parts) == 1:
            n = re.sub(r"\s*\bmystery\s*$", "", REEL_WORD.sub("", n).strip(" -–,"), flags=re.I).strip()
            if len(n.split()) < 2:
                return None, P9_REASONS["reel"]
        elif len(solid) == 1:
            n = solid[0]
        else:
            return None, P9_REASONS["reel"]
    elif len(parts) > 1:
        return None, P9_REASONS["programs"]
    n = cut_residue(PAGE_TAIL.sub("", n))
    if " " in n:
        n = MONTH_TAIL.sub("", CODE_TAIL.sub("", n)).strip()
        n = GLUED_TAIL.sub("", n)
    n = n.rstrip(" -–,;:").strip()
    if n == orig:
        return n, None
    if not n or FRAGMENT_ONLY.match(n) or _letters(n) < 4 or NUMBERED_STUB.match(n):
        return None, P9_REASONS["context"]
    return n, None


def track_numbered(names, own_keys):
    """Keys whose leading number is a track number: an upload-named series (never a registry program, which may
    really be numbered) whose number sits in a run of three upload-named names within two of it that write the
    number the same way ("12 Title" or "12.Title"), and whose next word is not a quantity ("100 Years")."""
    fam = {}
    for k in sorted(names):
        m = TRACK_NUMBER.match(names[k] or "")
        if k in own_keys and m:
            fam.setdefault((m.group(2), len(m.group(1))), {}).setdefault(int(m.group(1)), []).append(k)
    out = set()
    for nums in fam.values():
        for v, ks in nums.items():
            if sum(1 for u in nums if abs(u - v) <= 2) >= 3:
                out.update(ks)
    keep = set()
    for k in out:
        rest = names[k][TRACK_NUMBER.match(names[k]).end():]
        if rest[:1].isupper() and rest.split()[0].casefold() not in QUANTITY_WORDS:
            keep.add(k)
    return keep


def strip_track_number(name):
    m = TRACK_NUMBER.match(name or "")
    return name[m.end():].strip() if m else name


def _norm(n):
    n = re.sub(r"[\"“”'’]", "", (n or "").casefold()).replace("&", "and")
    n = re.sub(r"\s+", " ", re.sub(r"[^a-z0-9 ]", " ", n)).strip()
    return re.sub(r"^(?:the|a|an) ", "", n)


def _key_stem(k):
    return re.sub(r"^\d+(?=[a-z])", "", k)


def merge_into(series):
    """{old key: surviving key} for series that are one show. `series`: key -> dict(name, cleaned, librivox, own,
    eps, first, last, aliases). Merged only on evidence in the data, never on a guess:
      - an upload's fragments (page, side, episode code) whose cleaned name is another fragment's, or a registry
        program's name or alias: one show cut into pieces by an upload;
      - names that differ only in quotes or "&" for "and", whose keys differ only by a leading track number,
        or that carry the same single air date: one show written several ways.
    A LibriVox reading and a broadcast are distinct productions and are never merged; a pair that differs in
    dates or key stems (The Hobbit, Henry V) is left for a person."""
    by_norm, registry = {}, {}
    for k in sorted(series):
        v = series[k]
        if v["librivox"]:
            continue
        by_norm.setdefault(_norm(v["name"]), []).append(k)
        if not v["own"]:
            for a in [v["name"]] + list(v.get("aliases") or ()):
                registry.setdefault(_norm(a), set()).add(k)

    def pick(keys):
        return sorted(keys, key=lambda k: (series[k]["own"], -series[k]["eps"], k))[0]
    out = {}
    for nm, keys in sorted(by_norm.items()):
        frag = [k for k in keys if series[k]["cleaned"]]
        # The registry program may share the cleaned name ("The Whistler reel" beside "The Whistler").
        reg = registry.get(nm, set()) - set(frag)
        if frag and len(reg) == 1:
            out.update({k: next(iter(reg)) for k in frag})
            keys = [k for k in keys if k not in frag]
        elif len(frag) > 1 and len(frag) == len(keys):
            tgt = pick(frag)
            out.update({k: tgt for k in frag})
            continue
        if len(keys) < 2:
            continue
        tgt = pick(keys)
        for k in keys:
            a, b = series[k], series[tgt]
            quoted = lambda x: x["name"] != re.sub(r"[\"“”]", "", x["name"])
            amp = ("&" in a["name"]) != ("&" in b["name"])
            same_text = _norm(a["name"]) == _norm(b["name"]) and (quoted(a) or quoted(b) or amp)
            track = _key_stem(k) == _key_stem(tgt) and k != tgt and (k != _key_stem(k) or tgt != _key_stem(tgt))
            same_day = bool(a["first"]) and a["first"] == a["last"] == b["first"] == b["last"]
            if k != tgt and (same_text or track or same_day):
                out[k] = tgt
    return {k: v for k, v in out.items() if k != v}


def merged_span(merged, rows):
    """{surviving key: (first, last, networks)} widened across every series folded into it. `rows`: key ->
    (first, last, networks as a JSON list or None). Only keys that absorbed another appear."""
    import json
    out = {}
    for old, new in sorted(merged.items()):
        for k in (new, old):
            f, l, n = rows.get(k, (None, None, None))
            cf, cl, cn = out.get(new, (None, None, []))
            fs = [x for x in (cf, f) if x]
            ls = [x for x in (cl, l) if x]
            try:
                nets = json.loads(n) if n else []
            except ValueError:
                nets = []
            out[new] = (min(fs) if fs else None, max(ls) if ls else None,
                        cn + [x for x in nets if x not in cn])
    return {k: (f, l, json.dumps(n) if n else None) for k, (f, l, n) in out.items()}


# ---- P-10: one broadcast in one place, one show under one name (owner 2026-11-09; catalog DECISIONS 030) ----
# "I see a lot of things that seem disconnected from their shows": the same broadcast filed under a real show and
# under a series named for a sponsor, a collection, a season or a reel. Every fold below is read from the data
# (an air date and a title the two records share, an archive.org item title, a registry alias, a run), never
# from a likeness of names alone, and each one is listed in display_text.json for review.
GENERIC_WORDS = {"the", "a", "an", "show", "program", "programme", "radio", "series", "hour"}
COLLECTION_WORDS = {"single", "singles", "episode", "episodes", "show", "shows", "program", "programs", "season",
                    "seasons", "series", "vol", "volume", "volumes", "disc", "discs", "reel", "reels", "set", "part",
                    "parts", "final", "collection", "complete", "otr", "old", "time", "radio", "summer", "winter",
                    "spring", "fall", "and", "to", "of", "the", "lost", "all", "available", "eps", "ep", "a", "b"}
RANGE_TOKEN = re.compile(r"^(?:\d[\d\-/.]*[a-z]?|[ivx]+)$")
SMALL_INITIAL = {"and", "of", "the", "a", "an", "to", "in", "on", "for"}
MIN_SHARED = 3           # a pair of series that repeat each other's broadcasts this often is one source copying another
DISSOLVE_SHARE = 1 / 2   # an upload-named series more than half of whose dated broadcasts are one show's is that show


def _tokens(s):
    s = (s or "").casefold().replace("&", " and ").replace("theatre", "theater")
    s = re.sub(r"['’\"“”]", "", s)
    return re.findall(r"[a-z]+|\d[\d\-/.]*[a-z]?", s)


def name_tokens(n):
    t = _tokens(n)
    while t and t[0] in ("the", "a", "an"):
        t = t[1:]
    while t and t[-1] == "the":   # "Springbok Library of the Air - The"
        t = t[:-1]
    return tuple(t)


def _core(n):
    return tuple(w for w in name_tokens(n) if w not in GENERIC_WORDS)


def _collection_only(tokens):
    return all(w in COLLECTION_WORDS or RANGE_TOKEN.match(w) for w in tokens)


def _strong_name(t):
    return len(t) >= 2 or (len(t) == 1 and len(t[0]) >= 6 and t[0].isalpha())


def _framed(text, name):
    """True when `text` (tokens) is `name` (tokens) with only collection words and numbers around it:
    "Jack Benny - Single Episodes - 1932-1934", "The Shadow Season 11 (9-7-47 to 5-30-48)"."""
    n = len(name)
    for i in range(len(text) - n + 1):
        if tuple(text[i:i + n]) == name and _collection_only(list(text[:i]) + list(text[i + n:])):
            return True
    return False


def _initials(t):
    return {"".join(w[0] for w in t if w.isalpha()), "".join(w[0] for w in t if w.isalpha() and w not in SMALL_INITIAL)}


def _in_run(dates, run, years=1):
    lo, hi = run
    if not lo or not hi:
        return False
    lo, hi = f"{int(lo[:4]) - years}{lo[4:]}", f"{int(hi[:4]) + years}{hi[4:]}"
    return all(lo <= d <= hi for d in dates)


def same_program(series, shared=None):
    """{old key: (surviving key, rule)} for upload- and sponsor-named series that are one program. `series`: key ->
    dict(name, own, librivox, eps, aliases, dates (served air dates), run (first, last), items {item title: episodes},
    titles [display titles]); `shared`: {(a, b): broadcasts the two series both carry}, either order. Rules, each
    needing every dated episode inside the program's run (a year either side) and the program to be the larger:
      alias     the name spells the letters of exactly one registry program's name or alias ("FM&M", alias "FMM");
      variant   the names differ only by the, show, program, radio or hour ("Red Skelton", "The Red Skelton Show");
      item      half its episodes come from archive.org items titled with one registry program's name and collection
                words only ("Jack Benny - Single Episodes - 1932-1934" for "Grape Nuts Program"), items that feed no
                third series; three dated episodes or more; its own name not that program's name plus a qualifier
                ("High Adventure (South Africa)"); and its name is a season or volume, or the two share a broadcast;
      initials  the name is a program's initials and collection words ("GG Season 05"), and the two share a broadcast;
      prefix    the name is a program's name and more ("Escape the Birds"), dated, and the rest is a number or an
                episode's own title, or the two share a broadcast.
    A LibriVox project is never folded either way; a series named by a registry is folded only by `item`."""
    shared = shared or {}
    pair = lambda a, b: shared.get((a, b), 0) + shared.get((b, a), 0)
    names, letters, inits, cores = {}, {}, {}, {}
    for k in sorted(series):
        v = series[k]
        if v["librivox"] or not v["eps"]:
            continue
        for n in [v["name"]] + ([] if v["own"] else list(v.get("aliases") or ())):
            t = name_tokens(n)
            if _strong_name(t) and not re.search(r"\d", " ".join(t)):
                names.setdefault(t, set()).add(k)
            if not v["own"]:
                lt = re.sub(r"[^a-z0-9]", "", n.casefold())
                if len(lt) >= 3:
                    letters.setdefault(lt, set()).add(k)
        t = name_tokens(v["name"])
        if len(t) >= 2:
            for i in _initials(t):
                if len(i) >= 2:
                    inits.setdefault(i, set()).add(k)
        if _core(v["name"]):
            cores.setdefault(_core(v["name"]), set()).add(k)

    out = {}
    for k in sorted(series):
        v = series[k]
        if v["librivox"] or not v["eps"]:
            continue
        dates = v.get("dates") or []

        def ok(r):
            w = series[r]
            return (r != k and not w["librivox"] and w["eps"] > v["eps"] and _in_run(dates, w["run"])
                    if dates else r != k and not w["librivox"] and w["eps"] > v["eps"])

        def one(cands):
            c = {r for r in cands if ok(r)}
            return next(iter(c)) if len(c) == 1 else None
        tok = name_tokens(v["name"])
        got = None
        if v["own"]:
            lt = re.sub(r"[^a-z0-9]", "", v["name"].replace("&", "").casefold())
            if len(lt) >= 3 and (r := one(letters.get(lt, ()))):
                got = (r, "alias")
            elif len(_core(v["name"])) and len("".join(_core(v["name"]))) >= 5 and (r := one(cores.get(_core(v["name"]), ()))):
                got = (r, "variant")
        if not got and len(dates) >= MIN_SHARED:
            held = {}
            for title, n in sorted((v.get("items") or {}).items()):
                tt = _tokens(title)
                found = {(r, name_tokens(series[r]["name"]) == t) for t, rs in names.items() for r in rs
                         if not series[r]["own"] and _framed(tt, t) and ok(r)}
                hits = {r for r, _p in found}
                if len(hits) > 1:   # one program's own name beats another's alias ("The Shadow")
                    hits = {r for r, primary in found if primary} or hits
                if len(hits) == 1:
                    r = next(iter(hits))
                    if (v.get("feeds") or {}).get(title, {k}) <= {k, r}:   # an item feeding other series is a compilation
                        held[r] = held.get(r, 0) + n
            best = [r for r, n in held.items() if 2 * n >= v["eps"]]
            if len(best) == 1:
                r = best[0]
                rt = name_tokens(series[r]["name"])
                qualified = len(tok) > len(rt) and any(tuple(tok[i:i + len(rt)]) == rt for i in range(len(tok)))
                if not qualified and (_collection_only(tok) or pair(k, r) >= 1):
                    got = (r, "item")
        if not got and v["own"]:
            head = [w for w in tok]
            while head and (head[-1] in COLLECTION_WORDS or RANGE_TOKEN.match(head[-1])):
                head.pop()
            hl = "".join(w for w in head if w != "and")
            if head and len(hl) >= 2 and head != list(tok) and len(head) <= 2 and hl.isalpha():
                r = one(x for x in inits.get(hl, ()) if pair(k, x) >= 1)
                if r:
                    got = (r, "initials")
        if not got and v["own"] and dates:
            for t in sorted(names, key=len, reverse=True):
                if len(t) < len(tok) and tok[:len(t)] == t:
                    rest = tok[len(t):]
                    for r in sorted(names[t]):
                        if not ok(r):
                            continue
                        titled = any(name_tokens(x) and set(name_tokens(x)) <= set(rest) for x in v.get("titles") or ())
                        if _collection_only(rest) or titled or pair(k, r) >= 1:
                            got = (r, "prefix")
                            break
                    if got:
                        break
        if got:
            out[k] = got
    return out


def _title_key(title):
    t = name_tokens(title)
    return " ".join(t) if len("".join(w for w in t if w.isalpha())) >= 6 else None


def _rights_allow(keep, gone):
    """A copy the rights audit served as unclaimed never joins an episode served as clean: the clean-only (public web)
    projection would carry it under the clean line. Element 5 of an episode row is True for keep_clean (absent: clean)."""
    clean = lambda row: row[5] if len(row) > 5 else True
    return not clean(keep) or clean(gone)


def same_broadcasts(eps, series):
    """Episodes of different series that are one broadcast: ({old id: surviving id}, {(a, b): shared count}).
    `eps`: id -> (series key, air date, display title, composed?, items {archive.org item}[, clean?]). Two episodes are one
    broadcast when they carry the same full air date and the same title (six letters or more, not the series'
    own name, not a title composed from the date) and either a series is upload-named, they share an archive.org
    item, or their two series repeat each other at least MIN_SHARED times (one source copying another; a single
    coincidence such as two "A Christmas Carol" on December 24 is two productions). Within one series after a
    fold, the same date and a title one contains is one broadcast (the catalog's identity for a dated episode).
    The survivor is the episode of the series with fewer partner series (a compilation repeats many shows),
    then a registry program, then the larger series."""
    groups = {}
    for eid in sorted(eps):
        sk, air, title, composed = eps[eid][:4]
        if not air or len(air) != 10 or composed:
            continue
        key = _title_key(title)
        if not key or key == " ".join(name_tokens(series[sk]["name"])):
            continue
        groups.setdefault((air, key), []).append(eid)
    shared, partners = {}, {}
    for ids in groups.values():
        sks = sorted({eps[e][0] for e in ids})
        for i, a in enumerate(sks):
            for b in sks[i + 1:]:
                shared[(a, b)] = shared.get((a, b), 0) + 1
                partners.setdefault(a, set()).add(b)
                partners.setdefault(b, set()).add(a)
    rank = lambda sk: (len(partners.get(sk, ())), series[sk]["own"], -series[sk]["eps"], sk)
    out = {}
    for (air, key), ids in sorted(groups.items()):
        if len({eps[e][0] for e in ids}) < 2:
            continue
        ids = sorted(ids, key=lambda e: (rank(eps[e][0]), e))
        keep = ids[0]
        ka = eps[keep][0]
        for e in ids[1:]:
            b = eps[e][0]
            if b == ka:
                continue
            n = shared.get((min(ka, b), max(ka, b)), 0)
            if not _rights_allow(eps[keep], eps[e]):
                continue
            if series[ka]["own"] or series[b]["own"] or n >= MIN_SHARED or eps[keep][4] & eps[e][4]:
                out[e] = keep
    return out, shared


def same_day_in_series(eps, moved):
    """{old id: surviving id} for episodes a series fold brought onto a date their new series already holds, when
    one title contains the other's words or one was composed from the date. `eps`: id -> (series key, air date,
    display title, composed?, original series key[, clean?]); `moved`: ids whose series changed. Never an unclaimed
    copy into a clean episode (_rights_allow)."""
    by = {}
    for eid in sorted(eps):
        sk, air = eps[eid][:2]
        if air and len(air) == 10:
            by.setdefault((sk, air), []).append(eid)
    out = {}
    for ids in by.values():
        stay = [e for e in ids if e not in moved] or ids[:1]
        keep = stay[0]
        for e in ids:
            if e == keep or e not in moved:
                continue
            a, b = set(name_tokens(eps[keep][2])), set(name_tokens(eps[e][2]))
            if not _rights_allow(eps[keep], eps[e]):
                continue
            if eps[keep][3] or eps[e][3] or (a and b and (a <= b or b <= a)):
                out[e] = keep
    return out


def dissolve(series, shared):
    """{old key: surviving key} for an upload-named series more than DISSOLVE_SHARE of whose dated broadcasts (and at
    least MIN_SHARED) are one larger series' broadcasts, with every dated episode inside that series' run."""
    out = {}
    for k in sorted(series):
        v = series[k]
        if not v["own"] or v["librivox"] or not v.get("dates"):
            continue
        best = {}
        for (a, b), n in shared.items():
            if k in (a, b):
                best[b if a == k else a] = n
        cands = sorted(((n, r) for r, n in best.items()
                        if n >= MIN_SHARED and n > DISSOLVE_SHARE * len(v["dates"]) and series[r]["eps"] > v["eps"]
                        and not series[r]["librivox"] and _in_run(v["dates"], series[r]["run"])), reverse=True)
        if cands and (len(cands) == 1 or cands[0][0] > cands[1][0]):
            out[k] = cands[0][1]
    return out


def resolve_chains(m):
    out = {}
    for k in sorted(m):
        seen, t = {k}, m[k]
        while t in m and t not in seen:
            seen.add(t)
            t = m[t]
        if t != k:
            out[k] = t
    return out
