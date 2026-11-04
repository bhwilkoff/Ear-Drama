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
GENERIC_TITLE = re.compile(r"^(?:(?:xx\s+)*no\s+title|(?:episode|ep|deel|program|file|track|nr|no|side|disc|show)\.?\s*[\d.\-]*)$", re.I)
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


def decide_episode(shown, series_name, air_date, num):
    """(title to show, source, fields, withheld reason): source is 'source' (the cleaned title) or 'composed'."""
    if readable_title(shown):
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
    orig = (name or "").strip()
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
        reg = registry.get(nm, set()) - set(keys)
        frag = [k for k in keys if series[k]["cleaned"]]
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
