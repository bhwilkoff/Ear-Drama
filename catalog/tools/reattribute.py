"""Which program an upload's file belongs to, and what its series is called (P-6, 2026-10-31).

Imported by `build_db.py`; pure functions over what the build already holds, so a test can feed
fixtures. Three rules, each only on evidence a reader can open, each recorded in the episode's
`identity` (never a guess; an episode that fits no rule stays where the upload put it):

  stem_program        a file whose name BEGINS with a known program's name moves to that program
                      when the rest of the name is a title that program is known to have, or the
                      file's own date falls in that program's run ("Dragnet - Big Flight",
                      "1946-01-12 0006 - Continental Celebrity Club - Guest - ...").
  name_from_metadata  an unregistered series takes its name from the archive.org item's own title
                      when that title spells the same letters (item "Stand by for Mars" for the file
                      prefix "standbyformars"), or from the ID3 album the uploader wrote on nearly
                      every file ("Case Closed" for the item "CaseClosed3").
  prefer_tag_title    a file's own ID3 title beats a title that only restates the file name
                      ("CC211: Sherlock Holmes and The Lineup" over "CaseClosed211").
"""
import re

import audit_audio_rights as A
import otr_parse as P
import text_defects as TD

PART = re.compile(r"\s+-+\s*|\s*-+\s+")
LEAD_SHELF = re.compile(r"^\[[^\]]*\]\s*")
LEAD_NUMBER = re.compile(r"^\d{1,4}[\s._)-]+(?=\S)")
LEAD_DATE = re.compile(r"^(?:(?:19\d\d|\d\d)[-./]\d{1,2}[-./]\d{1,2}|19\d{6}|\d{6})(?:\s+\d{2,4}[a-z]?)?\s*[-:]?\s*(?=\S)")
LEAD_AFRS = re.compile(r"^(?:afrs|afrts)\s*#?\s*\d+\s*-+\s*", re.I)
CODE_PART = re.compile(r"^(?:[\dx\s.\-/]+|[a-z]?\d+[a-z]?)$", re.I)
TRAIL_NOISE = re.compile(r"\s*[(\[](?:afrs|afrts|otr|[^)\]]*\d{2,4}[^)\]]*)[)\]]\s*$", re.I)
GENERIC_ALBUM = {"podcast", "unknown", "album", "audio", "various", "untitled", "otr", "radio", "old time radio",
                 "general", "recording", "recordings", "music", "speech", "other", "none", "radio show", "radio shows"}
MIN_TITLE_KEY = 6
MIN_RUN_DATES = 3


def _segments(stem):
    s = re.sub(r"_+", " ", stem or "").strip()
    for _ in range(3):
        for rx in (LEAD_SHELF, LEAD_AFRS, LEAD_DATE, LEAD_NUMBER):
            s2 = rx.sub("", s, count=1)
            if s2 != s and s2.strip():
                s = s2.strip()
    return [p.strip() for p in PART.split(s) if p.strip()]


def _program_keys(text):
    return [k for k in [P.norm_series(text)] + P.series_variants_simple(text) if k]


def _title_matches(rest, titles):
    nr = A.norm_title(TRAIL_NOISE.sub("", rest or ""))
    if len(nr) < MIN_TITLE_KEY:
        return False
    return nr in titles or any(len(t) >= 8 and (nr.startswith(t) or nr.endswith(t)) for t in titles)


def stem_program(stem, k2c, titles_of, date, run_of):
    """(program key, how, gate) when `stem` begins with a known program's name and a gate holds, else None.
    k2c: alias key -> program key; titles_of(key) -> set of A.norm_title strings the program is known to
    have; date: the file's own date or None; run_of(key) -> (first year, last year, dated count) or None."""
    segs = _segments(stem)
    for i, seg in enumerate(segs[:3]):
        if CODE_PART.match(seg):
            continue
        words = seg.split()
        tries = [(seg, " - ".join(segs[i + 1:]), "exact")]
        for n in range(len(words) - 1, 0, -1):
            head = " ".join(words[:n])
            if len(P.norm_series(head)) >= 8 and n >= 2:
                tries.append((head, " ".join(words[n:]) + (" - " + " - ".join(segs[i + 1:]) if segs[i + 1:] else ""), "prefix"))
        for head, rest, how in tries:
            found = {k2c[k] for k in _program_keys(head) if k in k2c}
            if len(found) != 1:
                continue
            c = next(iter(found))
            if _title_matches(rest, titles_of(c)):
                return c, how, "title"
            run = run_of(c)
            if i == 0 and date and run and run[2] >= MIN_RUN_DATES and run[0] - 1 <= int(date[:4]) <= run[1] + 1:
                return c, how, "date"
        return None   # the first usable part is the only place a program name is read
    return None


def _clean_name(s):
    return re.sub(r"\s+", " ", (s or "").replace("_", " ")).strip()


def name_from_metadata(key, files):
    """A better display name for an unregistered series, or None. files: [{"item_title", "album"}] of
    the series' files. Returns (name, new key or None, why). A new key is returned only for the album
    rule, where one name is written on the files of several uploads."""
    n = len(files)
    if not n:
        return None
    titles = {}
    for f in files:
        t = _clean_name(f.get("item_title"))
        if t:
            titles[t] = titles.get(t, 0) + 1
    for t, c in sorted(titles.items(), key=lambda x: (-x[1], x[0])):
        if c * 2 >= n and P.norm_series(t) == key and t != key and re.search(r"[A-Z]", t) and not TD.series_defects(t):
            return t, None, "item title"
        break
    albums = {}
    for f in files:
        a = _clean_name(f.get("album"))
        if a:
            albums[a] = albums.get(a, 0) + 1
    for a, c in sorted(albums.items(), key=lambda x: (-x[1], x[0])):
        if (n >= 3 and c * 5 >= n * 4 and re.search(r"[A-Z]", a) and re.search(r"[A-Za-z]{3}", a)
                and a.casefold() not in GENERIC_ALBUM and P.norm_series(a) not in ("", key)):
            return a, P.norm_series(a), "album tag"
        break
    return None


def prefer_tag_title(file_title, tag_title, stem):
    """The title to keep: the file's own ID3 title when the title the file name gave only restates the name."""
    if not isinstance(tag_title, str) or not P.is_titleish(tag_title) or P.parse(tag_title)["date"]:
        return file_title
    if file_title is None:
        return tag_title
    fold = lambda x: re.sub(r"[^a-z0-9]", "", (x or "").lower())
    restated = " " not in file_title.strip() and (fold(file_title) == fold(stem) or fold(file_title) in fold(tag_title)
                                                   or fold(tag_title).endswith(fold(file_title)))
    if restated and " " in tag_title.strip():
        return tag_title
    return file_title
