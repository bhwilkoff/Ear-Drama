"""The Listen shelves: rules over data, published once for every client (docs/CATALOG-CONTRACT.md §5).

Imported by both builders, never copied. A shelf is a rule and what the rule
selects from served rows; nothing here writes a title, a blurb, or a pick (R13).
`listen_shelves` is the published list: `onThisDay` first (a query by rule,
since it depends on the person's date), then `mostDownloaded` (archive.org's
own download counts, Decision 067), then one `genreFirsts` per genre in
GENRES order, each with its episode ids precomputed.

Episode rows are (id, series_key, air_date, num, no_recommend[, title]); series
is key -> (genre, served episode count).
"""
import re

from genres import GENRES

RULES = ("onThisDay", "mostDownloaded", "genreFirsts")
# The only keys a published shelf may carry: no free text, so no copy can ride along.
KEYS = {"onThisDay": {"rule"}, "mostDownloaded": {"rule", "episodes"}, "genreFirsts": {"rule", "genre", "episodes"}}
SHELF_LIMIT = 20
# A genre gets a shelf when this many served series each have a recommendable
# episode. MEASURED 2026-10-23 on the 2026-10-22 projection: every genre has 39
# or more natively (western is the least), and the clean-only web set has drama
# 608, comedy 2, the rest 0, so any floor from 3 to 39 publishes the same
# shelves; 5 is one ten-foot row, fewer reads as a heading over nothing.
MIN_SERIES = 5
FULL_DATE = re.compile(r"\d{4}-\d{2}-\d{2}")
# A book's front matter is not a place to start listening: a LibriVox dramatic
# reading's first section is often its cast list or preface (measured 2026-10-23:
# 108 "Dramatis Personae" sections, 74 numbered 0 and 33 numbered 1, so the number
# cannot tell). A prologue is performed, so it stays.
FRONT_MATTER = re.compile(
    # At the title's start (after a section number), or a collection's closing
    # "... Introduction". A word met mid-title is a program ("Cartoon Characters",
    # "First Show-Introduction Of Bergen And McCarthy"), never front matter.
    r"^\W*(?:\d+\s*[-–.:]?\s*)?(?:dramatis person\w*|cast of characters|cast list|characters\b|"
    r"preface|foreword|introduction|introductory|costumes|vorrede|widmung|avertissement|"
    r"personen|dedication)\b|\bintroduction\s*$", re.I)


def recommendable(e):
    """recommendAnd: `no_recommend IS NULL`."""
    return e[4] is None


# A section that also carries the play ("Personen - 1. Aufzug", "Preface and Act
# 1") is where the performance starts, so it is never skipped.
PERFORMED = re.compile(r"\b(act|acts|akt|aufzug|auftritt|scene|szene|chapter|kapitel|prolog\w*)\b", re.I)


def front_matter(e):
    """A section that only introduces the work (cast list, preface), by its title."""
    title = e[5] if len(e) > 5 else None
    return bool(title) and bool(FRONT_MATTER.search(title)) and not PERFORMED.search(title)


def oldest_first(e):
    return (e[2] is None, e[2] or "", e[3] is None, e[3] if e[3] is not None else 0, e[0])


def on_this_day(episodes, month, day, limit=SHELF_LIMIT):
    """Episodes first broadcast on this calendar month and day in any year: a
    full YYYY-MM-DD date only (a month or year alone never matches),
    recommendAnd, oldest year first, ties by id."""
    md = f"-{month:02d}-{day:02d}"
    hits = [e for e in episodes if recommendable(e) and e[2] and FULL_DATE.fullmatch(e[2]) and e[2].endswith(md)]
    return [e[0] for e in sorted(hits, key=lambda e: (e[2], e[0]))[:limit]]


def firsts(episodes, keep):
    """Series key -> its earliest surviving recommendable episode, front matter
    skipped (oldest first: dated before undated, then number, then id), for the
    series `keep(key)` admits."""
    first = {}
    for e in episodes:
        if keep(e[1]) and recommendable(e) and not front_matter(e):
            if e[1] not in first or oldest_first(e) < oldest_first(first[e[1]]):
                first[e[1]] = e
    return first


def genre_firsts(episodes, series, genre, limit=SHELF_LIMIT):
    """The earliest surviving recommendable episode of each series in the genre,
    series with the most served episodes first, ties by key."""
    first = firsts(episodes, lambda k: bool(series.get(k)) and series[k][0] == genre)
    keys = sorted(first, key=lambda k: (-series[k][1], k))
    return [first[k][0] for k in keys[:limit]]


def series_downloads(default_copies, downloads):
    """Series key -> archive.org's own download count summed over the distinct items
    that hold its served episodes' default copies. `default_copies` is (series key,
    archive id) per served episode; `downloads` is archive id -> count, and an item
    never read adds nothing (it is not counted as zero downloads, it is unknown)."""
    seen, out = set(), {}
    for sk, aid in default_copies:
        if (sk, aid) in seen:
            continue
        seen.add((sk, aid))
        n = downloads.get(aid)
        if isinstance(n, int) and n > 0:
            out[sk] = out.get(sk, 0) + n
    return out


def most_downloaded(episodes, by_series, limit=SHELF_LIMIT):
    """Decision 067: popularity from data. The series archive.org's listeners have
    downloaded most (`series_downloads`), each by its earliest surviving
    recommendable episode, most downloads first, ties by key."""
    first = firsts(episodes, lambda k: by_series.get(k, 0) > 0)
    keys = sorted(first, key=lambda k: (-by_series[k], k))
    return [first[k][0] for k in keys[:limit]]


def listen_shelves(episodes, series, min_series=MIN_SERIES, downloads=None):
    """`downloads` is series key -> `series_downloads`; without it there is no
    popularity shelf (an older registry that never read the counts)."""
    episodes = list(episodes)
    with_rec = {}
    for e in episodes:
        g = series.get(e[1])
        if g and g[0] and recommendable(e):
            with_rec.setdefault(g[0], set()).add(e[1])
    out = [{"rule": "onThisDay"}]
    popular = most_downloaded(episodes, downloads or {})
    if len(popular) >= min_series:
        out.append({"rule": "mostDownloaded", "episodes": popular})
    for g in GENRES:
        if len(with_rec.get(g, ())) >= min_series:
            out.append({"rule": "genreFirsts", "genre": g, "episodes": genre_firsts(episodes, series, g)})
    return out


def violations(shelves, served, recommended):
    """The guarantees over a published list: name -> offending items. `served`
    and `recommended` are the output's own episode id sets."""
    bad = {}
    add = lambda k, v: bad.setdefault(k, []).append(v)
    if not isinstance(shelves, list) or not shelves:
        return {"listenShelves is a non-empty list": [shelves]}
    for s in shelves:
        rule = s.get("rule") if isinstance(s, dict) else None
        if rule not in RULES:
            add("every rule is from the known set", rule)
            continue
        if set(s) != KEYS[rule]:
            add("a shelf carries only its rule's keys (no text)", sorted(set(s) ^ KEYS[rule]))
        if rule == "genreFirsts" and s.get("genre") not in GENRES:
            add("a genre shelf names one of the eight genres", s.get("genre"))
        if rule in ("genreFirsts", "mostDownloaded"):
            for i in s.get("episodes") or []:
                if i not in served:
                    add("every published episode is served", i)
                elif i not in recommended:
                    add("every published episode is recommendable", i)
            if not s.get("episodes"):
                add("an episode shelf is never empty", s.get("genre") or rule)
    return bad
