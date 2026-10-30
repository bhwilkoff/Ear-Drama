"""Which portraits the projection serves, and how each is credited (contract §3.3).

One predicate, imported by build_projection.py (and through it the web
projection), so no builder decides for itself. An image is served only when
its own record carries the evidence (DECISIONS 055), and only when the PERSON
match carries it too:

  * the file's license class is one enrich_people_art.py counts usable
    (a US public-domain template, a government work, CC0, the holder's own
    release, CC BY, CC BY-SA);
  * the person was matched on a DATE (OTRRpedia's birth or death agreeing with
    Wikidata's). The undated rule (one namesake of the right trade and era) is
    not served: it is the only rule that fails on its own logic, and about 1 in
    30 of its matches is someone else (catalog/reports/E-people-portraits.md;
    RESEARCH.md §12 V1 asks the owner whether to open it);
  * the file is the person's own Wikidata image (P18). A file found because its
    Structured Data depicts the person can be a group photograph, which a
    portrait slot would crop to the wrong face;
  * a license that requires attribution has an author to attribute.

Library of Congress "no known restrictions" photographs and Smithsonian CC0
portraits (Track F) are not here: RESEARCH.md §12 V2 and V4 are the owner's.
"""
import math
import re
import urllib.parse

SERVED_CLASSES = ("pd_us", "pd_us_gov", "cc0", "pd_release", "free_use", "cc_by", "cc_by_sa")
PREFER = {c: i for i, c in enumerate(SERVED_CLASSES)}
NEEDS_CREDIT = {"cc_by", "cc_by_sa"}
UNDATED_BASIS = "name+occupation+unique"
SERVED_VIA = "wikidata:P18"
FILEPATH = "https://commons.wikimedia.org/wiki/Special:FilePath/"
FILE_PAGE = "https://commons.wikimedia.org/wiki/File:"
NO_AUTHOR = re.compile(r"^\s*(unknown|anonymous|not credited|n/?a|none|\?)?\s*$", re.I)


def dated_match(basis):
    """A match made on a date of ours agreeing with Wikidata's ('name+birth_day', ...)."""
    return bool(basis) and basis.startswith("name+") and basis != UNDATED_BASIS


def license_name(cls, template):
    """The license as a reader writes it, for a class that must be credited: 'CC BY-SA 3.0'."""
    if cls not in NEEDS_CREDIT:
        return None
    base = "CC BY-SA" if cls == "cc_by_sa" else "CC BY"
    m = re.search(r"(\d\.\d)", template or "")
    if (template or "").lower().replace(" ", "") == "latimesucla":
        return "CC BY 4.0"   # the UCLA LA Times archive's own license, enrich_people_art ALIASES
    return f"{base} {m.group(1)}" if m else base


def credit(cls, template, author):
    """The line a credited image carries: 'Author, CC BY-SA 3.0'; None when none is owed."""
    name = license_name(cls, template)
    return f"{author.strip()}, {name}" if name else None


def year_of(text):
    """The year a date as Wikidata or Commons writes it begins with ('1971-08-03'), or None."""
    m = re.match(r"\s*(\d{4})", text or "")
    return int(m.group(1)) if m else None


def implausible_own_work(own_work, date_field, died):
    """True when a picture its page calls the uploader's own work (a {{self}} license, {{own}}
    as its source) is dated after the death of the person it is of: Richard Kollmar died in 1971
    and File:Kollmar.jpg is "a photograph I took of Richard Kollmar", dated 2019. An uploader's
    word is not evidence (evidence-gated-catalog-curation), and here the word contradicts itself.
    date_field is the file page's own date; died is the year or date of the person's death."""
    fy, dy = file_year(date_field), year_of(str(died)) if died else None
    return bool(own_work and fy and dy and fy > dy)


def earliest_death(rows):
    """{series key: the earliest death year} of the people the program's record marks.
    rows: (series key, death as Wikidata writes it) pairs."""
    out = {}
    for key, death in rows:
        y = year_of(death)
        if y:
            out[key] = min(y, out.get(key, y))
    return out


def served(basis, cls, usable, found_via, author, own_work=False, date_field=None, died=None):
    """True when this (person match, file) may leave the pipeline."""
    if not usable or cls not in PREFER or found_via != SERVED_VIA or not dated_match(basis):
        return False
    if cls in NEEDS_CREDIT and NO_AUTHOR.match(author or ""):
        return False
    return not implausible_own_work(own_work, date_field, died)


def image_url(file):
    """The file's Commons address with no width; each client's one helper appends ?width=."""
    return FILEPATH + urllib.parse.quote(file.replace(" ", "_"))


def evidence_url(file):
    return FILE_PAGE + urllib.parse.quote(file.replace(" ", "_"))


# A file whose Structured Data depicts the person may stand in for their own image when it fills
# a larger window: the detector read exactly one confident face on it, so it is not the group a
# depicts file often is (Jack Benny's own image is 174 x 333; NBC's 1938 photograph of him alone,
# a depicts file, is 1139 x 1479). Only for a person who has a served own image: it changes which
# picture of them is shown, never who has one.
ALTERNATE_VIA = "commons:depicts"
FACE_CONFIDENCE = 0.5   # harvest_people_wikidata.MIN_FACE_CONFIDENCE


def face_count(facts):
    """How many confident faces the detector read on a file ({"faces": [[x, y, w, h, conf]]}),
    or None when it was not read."""
    faces = (facts or {}).get("faces")
    if faces is None:
        return None
    return sum(1 for f in faces if (list(f) + [1.0])[4] >= FACE_CONFIDENCE)


def alternate(basis, cls, usable, found_via, author, own_work=False, date_field=None, died=None, faces=None):
    """True when a depicts file may stand in for this person's own image: every check `served`
    makes, on a file showing one face."""
    return (found_via == ALTERNATE_VIA and faces == 1
            and served(basis, cls, usable, SERVED_VIA, author, own_work, date_field, died))


def pick(rows):
    """The one portrait per person: the most permissive class of their own image, then the file
    name; unless it is under the size floor (it fills less than LARGEST_SLOT) and a file showing
    one face fills more, when the one of those that fills most (up to LARGEST_SLOT) is taken, then
    an own image before a stand-in, the class, the name. A group never replaces a portrait: David
    Rose's other own image is him among three soldiers.
    rows: (file, cls, template, author[, own image, fill_px, faces]) already passing `served` or
    `alternate`; a row without the last three is an own image of unknown size and faces."""
    if not rows:
        return None
    full = [tuple(r) + (True, 0, None)[len(r) - 4:] for r in rows]
    own = [r for r in full if r[4]]
    base = min(own or full, key=lambda r: (PREFER[r[1]], r[0]))
    fill = lambda r: min(r[5] or 0, LARGEST_SLOT)
    better = [r for r in full if r[6] == 1 and fill(r) > fill(base)]
    best = min(better, key=lambda r: (-fill(r), not r[4], PREFER[r[1]], r[0])) if better else base
    return rows[full.index(best)]


# ---------------------------------------------------------------- whose face a show wears

# Credits heard on the air; a writer or a director has no face in the broadcast.
ON_AIR = {None, "", "cast", "host", "hostess", "performer", "narrator", "guest", "emcee", "m. c.", "doubles",
          "vocal", "star"}
STAR_MIN_EPISODES = 3
STAR_SHARE = 1 / 3


def series_star(credited, portrait_people):
    """The series' face: the person with a served portrait heard on the most of its
    credited episodes, when that is at least STAR_MIN_EPISODES and STAR_SHARE of
    them (an anthology's guest of one week is not its face). Ties by person id.
    credited: {episode_id: [(person_id, role), ...]} for one series."""
    counts = {}
    for creds in credited.values():
        for pid in {p for p, role in creds if role in ON_AIR and p in portrait_people}:
            counts[pid] = counts.get(pid, 0) + 1
    if not counts:
        return None
    pid, n = min(counts.items(), key=lambda kv: (-kv[1], kv[0]))
    return pid if n >= STAR_MIN_EPISODES and n >= STAR_SHARE * len(credited) else None


def episode_star(creds, portrait_people, star):
    """The episode's face: the series' star when heard in it, else its first on-air
    credit with a served portrait, else None. creds: [(person_id, role), ...] in order."""
    on_air = [p for p, role in creds if role in ON_AIR and p in portrait_people]
    if star in on_air:
        return star
    return on_air[0] if on_air else None


def face_text(box):
    """A face box ([x, y, w, h], normalized, top-left origin) as the projection's `art.face`
    ("x,y,w,h", contract section 3.3a), or None when there is none or it does not lie inside
    the image: a crop is never centered on a point off the picture."""
    if not box or len(box) != 4:
        return None
    x, y, w, h = (float(v) for v in box)
    if not (w > 0 and h > 0 and x >= 0 and y >= 0 and x + w <= 1.0001 and y + h <= 1.0001):
        return None
    return ",".join(f"{v:.4f}".rstrip("0").rstrip(".") for v in (x, y, w, h))


def face_list(text):
    """`art.face` as the web's [x, y, w, h], or None."""
    return [float(v) for v in text.split(",")] if text else None


# ---------------------------------------------------------------- the size floor

# The largest square window a client fills with a person's or a show's picture: tvOS's show
# tile (apple/Shared/Grammar.swift SeriesTile.defaultWidth 312, less its 12 of padding). The
# web's tile is 200, Android TV's 200 dp less its padding, a head board at most 176.
LARGEST_SLOT = 300
WIDE_ASPECT = 1.15


def crop_rect(width, height, face):
    """The crop square every client draws (contract section 3.3a `cropRect`, golden cases in
    js/api.test.js), as (x, y, w, h) normalized to the image, or None: an unknown size, or a
    wide picture with no face (drawn whole)."""
    if not (width and height and width > 0 and height > 0):
        return None
    a = width / height
    f = face if face and len(face) == 4 else None
    if not f and a > WIDE_ASPECT:
        return None
    full = min(a, 1.0)
    clamp = lambda v, lo, hi: min(hi, max(lo, v))
    s, left, top = full, 0.5 * (a - full), 0.2 * (1 - full)
    if f:
        s = clamp(2 * max(f[2] * a, f[3]), full / 4, full)
        left = clamp((f[0] + f[2] / 2) * a - s / 2, 0, a - s)
        top = clamp(f[1] + f[3] / 2 - s / 2, 0, 1 - s)
    return (left / a, top, s / a, s)


def fill_px(width, height, face):
    """The pixels a window gets from the picture, the number every client's `windowFill`
    compares with its slot (uniform-imagery-design section 4): the crop's height in pixels, or
    for a wide picture drawn whole twice its short side; 0 for an unknown size."""
    if not (width and height and width > 0 and height > 0):
        return 0
    r = crop_rect(width, height, face)
    return 2 * min(width, height) if r is None else r[3] * height


def fills(width, height, face, slot=LARGEST_SLOT):
    """True when the picture fills a window of `slot` points instead of the title block."""
    return fill_px(width, height, face) >= slot


# ---------------------------------------------------------------- the picture that leads a show

# A series' picture (contract section 3.3a), in order: the show's own image ("show"), then its
# star by recognizability ("star"), then the person heard most ("person"); else the board.
# Owner, 2026-10-29: "images/graphics that show the full 'show' are better than individual
# contributors. Images that show the star(s) are better than those that show folks that are
# less recognizable."
KINDS = ("show", "star", "person")
# Where a show image may come from, best first: the item's own chosen image, logo, poster,
# collage, related image; then a Commons file whose Structured Data depicts the item (P180);
# then a file the item's own Commons category (P373) holds, named on the file's own page.
SHOW_SOURCES = ("wikidata:P18", "wikidata:P154", "wikidata:P3383", "wikidata:P2716", "wikidata:P6802",
                "commons:P180", "commons:category")
SHOW_RANK = {s: i for i, s in enumerate(SHOW_SOURCES)}
# How the series was matched to its Wikidata item. A title alone is never an identity
# (evidence-gated-catalog-curation section 7); a title with the years or the network is.
IDENTITY_SERVED = ("title+years", "title+network")
# The largest show tile is 160 points (uniform-imagery-design: a show tile is 96 to 160 pt, and a
# slot takes a picture only with at least the slot's pixels): a smaller show image would be
# refused by every tile, so it does not displace a star who can fill one.
SHOW_MIN_SIDE = 160
# A still of the program's television run is a different broadcast (Life of Riley's TV cast).
TELEVISION = re.compile(r"\b(television|TV)\b", re.I)
NETWORK_NAMES = {"columbiabroadcastingsystem": "cbs", "cbsradio": "cbs", "cbsradionetwork": "cbs",
                 "nationalbroadcastingcompany": "nbc", "nbcred": "nbc", "nbcradio": "nbc", "nbcblue": "blue",
                 "bluenetwork": "blue", "mutualbroadcastingsystem": "mutual", "mbs": "mutual",
                 "americanbroadcastingcompany": "abc", "abcradio": "abc"}


def network_key(name):
    k = re.sub(r"[^a-z0-9]", "", (name or "").lower())
    return NETWORK_NAMES.get(k, k)


YEAR_SLACK = 2


def description_years(text):
    """The years an item's own description names ('radio Western drama series (1952-1961)',
    'from the mid-1980s'), as (first, last), or None."""
    ys = []
    for m in re.finditer(r"\b(19\d\d|20[0-2]\d)(s)?\b", text or ""):
        y = int(m.group(1))
        ys += [y, y + 9] if m.group(2) else [y]
    return (min(ys), max(ys)) if ys else None


def series_identity(evidence, our_networks, broadcasters, description=None):
    """'title+years' when the Wikidata item's years (its own dates, its article's decade
    category, or the years its own description names) overlap ours within YEAR_SLACK,
    'title+network' when one of its broadcasters is one of our networks, else 'title' (refused).
    evidence: series_wikidata.match_evidence as a dict."""
    evidence = evidence or {}
    if TELEVISION.search(description or "") and not re.search(r"\bradio\b", description or "", re.I):
        return "television"   # its own description says it is the TV program (The Goldbergs, 1949-1956)
    if evidence.get("years") == "overlap":
        return "title+years"
    ours = [y for y in (evidence.get("our_years") or []) if y]
    dy = description_years(description)
    if ours and dy and dy[0] <= max(ours) + YEAR_SLACK and dy[1] >= min(ours) - YEAR_SLACK:
        return "title+years"
    ours = {network_key(n) for n in our_networks or []}
    if ours & {network_key(b) for b in broadcasters or []}:
        return "title+network"
    return "title"


def file_year(date_field):
    """The year a Commons file page's own date field names, or None."""
    m = re.search(r"\b(1[89]\d\d|20\d\d)\b", date_field or "")
    return int(m.group(1)) if m else None


def run_dates(con):
    """{series key: (first, last)}: the earliest broadcast witnessed (the logs' first_broadcast or
    our first episode, whichever is earlier) and our last episode's date, from the series table."""
    cols = {r[1] for r in con.execute("PRAGMA table_info(series)")}
    fb = "first_broadcast" if "first_broadcast" in cols else "NULL"
    out = {}
    for key, first, broadcast, last in con.execute(f"SELECT key, first_date, {fb}, last_date FROM series"):
        starts = [d for d in (first, broadcast) if d]
        out[key] = (min(starts) if starts else None, last)
    return out


def show_served(identity, source, cls, author, width, height, file, categories=(), date_field=None,
                last_date=None, first_date=None, own_work=False, died=None):
    """True when this (series match, file) may lead the show: the match is more than a title,
    the file came from one of the show's own records, its license class is one portraits are
    served under (credited when required), it is big enough for a show tile, its own page does
    not say it is from television, is not an own work dated after its star's death (served), and its own date (its page's date field, else a year in its
    name) lies inside the run (YEAR_SLACK either side): Bob Barker's 1958 headshot is the TV
    Truth or Consequences, and a 1914 photograph of the Hill Top House hotel, reached through a
    Commons depicts statement, predates the soap opera's first broadcast (1939)."""
    if identity not in IDENTITY_SERVED or source not in SHOW_RANK or cls not in PREFER:
        return False
    if cls in NEEDS_CREDIT and NO_AUTHOR.match(author or ""):
        return False
    if not width or not height or min(width, height) < SHOW_MIN_SIDE:
        return False
    if implausible_own_work(own_work, date_field, died):
        return False   # died: the earliest death among the people the program's record marks
    fy, last, first = file_year(date_field) or file_year(file), file_year(last_date), file_year(first_date)
    if fy and last and fy > last + YEAR_SLACK:
        return False
    if fy and first and fy < first - YEAR_SLACK:
        return False
    return not TELEVISION.search(" ".join([file or ""] + list(categories or [])))


def pick_show(rows, series_name=None):
    """The one show image: the best source, then a file whose own name names the show ("Ralph
    Edwards Truth or Consequences 1942" before "Buff Cobb 1949" in the same category), then the
    most permissive class, then the file name. rows: (file, source, cls, ...) passing `show_served`."""
    name = _nt(series_name) if series_name else ""
    named = lambda f: bool(name) and len(name) >= TITLE_MIN and name in _nt(f)
    return min(rows, key=lambda r: (SHOW_RANK[r[1]], not named(r[0]), PREFER[r[2]], r[0])) if rows else None


# The program's own record (OTRRpedia's "Noted Role") marks a star when the character is the
# title role or the role is the star's or the host's own.
MARK_ROLES = re.compile(r"^(star|host|hostess|himself|herself|emcee|m\.? ?c\.?)$", re.I)
TITLE_MIN = 4
# A marked star heard on at least a tenth of the credited episodes: Richard Kollmar's Boston
# Blackie (184 of 190) or Steve Dunne's half season of Sam Spade, never Robert Montgomery's
# season as host of Suspense's twenty years (15 of about 900 credited).
MARK_SHARE = 0.1


def _nt(s):
    s = re.sub(r"\(.*?\)", " ", (s or "").lower())
    s = re.sub(r"^\s*(the|a|an)\s+", "", s)
    return re.sub(r"[^a-z0-9]", "", s)


def marks_star(character, series_name):
    """True when a program's noted role names its star: 'Star', 'Host', 'Himself', or the
    title role (the character is in the series' name: 'Boston Blackie(beginning in 1945)')."""
    ch = re.sub(r"\(.*$", "", character or "").strip()
    if MARK_ROLES.match(ch):
        return True
    c, s = _nt(ch), _nt(series_name)
    return len(c) >= TITLE_MIN and c in s


def recognizability(sitelinks):
    """1 + ln(1 + the number of Wikipedias with an article about the person): a person no
    Wikipedia covers weighs 1, one on 1 weighs 1.7, on 10 weighs 3.4, on 50 weighs 4.9. The log
    because the counts are heavy-tailed (a film star on 60, a radio regular on 1 or 2): ten times
    the coverage is one step more, never ten times the claim on the show."""
    return 1 + math.log1p(max(0, sitelinks or 0))


def series_face(credited, portrait_people, marked=(), sitelinks=None):
    """(person id, kind, source) for the series' face, or None.
    1. "star", "otrrpedia:noted-role": a person the program's record marks (title role, star,
       host) with a served portrait, heard on at least STAR_MIN_EPISODES and MARK_SHARE of the
       credited episodes (any, when none is credited);
    2. "star", "wikipedia:sitelinks": else a regular (series_star's eligibility) whom at least
       one Wikipedia covers;
    3. "person", "credits:heard-most": else series_star, the heard-most rule.
    Within 1 and 2 the score is the share of credited episodes x recognizability; ties by id.
    credited: {episode_id: [(person_id, role), ...]}; marked: person ids; sitelinks: {pid: n}."""
    sitelinks = sitelinks or {}
    total = len(credited)
    counts = {}
    for creds in credited.values():
        for pid in {p for p, role in creds if role in ON_AIR and p in portrait_people}:
            counts[pid] = counts.get(pid, 0) + 1

    def best(pids):
        scored = [((counts.get(p, 0) / total if total else 1.0) * recognizability(sitelinks.get(p)), p)
                  for p in pids]
        return min(scored, key=lambda t: (-t[0], t[1]))[1] if scored else None

    tagged = sorted({p for p in marked if p in portrait_people and (not total or (
        counts.get(p, 0) >= STAR_MIN_EPISODES and counts.get(p, 0) >= MARK_SHARE * total))})
    if tagged:
        return best(tagged), "star", "otrrpedia:noted-role"
    regulars = [p for p, n in counts.items() if n >= STAR_MIN_EPISODES and n >= STAR_SHARE * total]
    known = [p for p in regulars if (sitelinks.get(p) or 0) >= 1]
    if known:
        return best(known), "star", "wikipedia:sitelinks"
    pid = series_star(credited, portrait_people)
    return (pid, "person", "credits:heard-most") if pid else None


def _heard(credited, pid):
    """How many of a show's credited episodes the person is heard on."""
    return sum(1 for creds in credited.values() if any(p == pid and role in ON_AIR for p, role in creds))


def _claim(shows, pid, key, biggest, named):
    """How strongly a person is identified with one show, best first: a show named for them
    (its title holds their full name: the Jack Benny Program), then a marked role in a show
    holding at least MARK_FLOOR of the episodes of their biggest show (Jack Webb's seven
    episodes of Pete Kelly's Blues, where Pete Kelly is the title role, do not outweigh his 474
    of Dragnet), then the most episodes, then the highest share, then the series key."""
    credited, marked = shows[key]
    n = _heard(credited, pid)
    return (key not in named, not (pid in marked and n >= MARK_FLOOR * biggest), -n,
            -(n / len(credited) if credited else 1.0), key)


MARK_FLOOR = 0.5


def names_person(person_name, series_name):
    """True when the series' title holds the person's full name (two words at least)."""
    p = _nt(person_name)
    return len(re.findall(r"[A-Za-z0-9]+", re.sub(r"\(.*?\)", " ", person_name or ""))) >= 2 and len(p) >= 6 \
        and p in _nt(series_name)


def assign_faces(shows, portrait_people, sitelinks=None, names=None, titles=None):
    """{series key: series_face result or None} with each person the face of at most one show
    (owner, 2026-10-29: "Yes" to one face per star). Of the shows a person would lead, they keep
    the one they are most identified with (`_claim`, ties by series key); every other show is
    decided again without them, so it falls to its next candidate or to no face.
    shows: {series key: (credited, marked)}, the arguments series_face takes;
    names: {person id: name}, titles: {series key: name}, for the show named for its star."""
    names, titles = names or {}, titles or {}
    out, barred = {}, {k: set() for k in shows}
    while True:
        out = {k: series_face(c, portrait_people - barred[k], m, sitelinks) for k, (c, m) in shows.items()}
        leads = {}
        for k, f in out.items():
            if f:
                leads.setdefault(f[0], []).append(k)
        moved = False
        for pid, keys in leads.items():
            if len(keys) > 1:
                biggest = max(_heard(shows[k][0], pid) for k in keys)
                named = {k for k in keys if names_person(names.get(pid), titles.get(k))}
                keep = min(keys, key=lambda k: _claim(shows, pid, k, biggest, named))
                for k in keys:
                    if k != keep:
                        barred[k].add(pid)
                        moved = True
        if not moved:
            return out
