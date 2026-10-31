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
LONG_NAME = 60
GENERIC_TITLE = re.compile(r"^(?:episode|ep|deel|program|file|track|nr|no|side|disc|show)\.?\s*[\d.\-]*$", re.I)

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
    return True


def episode_out_of_scope(title):
    """The reason an episode is not shown for being music, from its own title ("048 V-Disc A Chorus and Organ"), or None."""
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
