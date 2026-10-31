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
LONG_NAME = 60
GENERIC_TITLE = re.compile(r"^(?:episode|ep|deel|program|file|track|nr|no|side|disc|show)\.?\s*[\d.\-]*$", re.I)

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
    return True


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
