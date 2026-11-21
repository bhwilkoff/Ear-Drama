"""Which portraits the projection serves, and how each is credited (contract §3.3).

One predicate, imported by build_projection.py (and through it the web
projection), so no builder decides for itself. An image is served unless its
own record marks a restriction (DECISIONS 040, owner 2026-11-21), and only when
the PERSON match carries identity:

  * the file's license class is one enrich_people_art.py counts usable: a
    free class (a US public-domain template, a government work, CC0, the
    holder's own release, CC BY, CC BY-SA), or a class that states no
    restriction (PD in the source country only, "no known restrictions", a page
    with no rights sentence). A copyright notice, "all rights reserved", a
    non-free or fair-use license, a no-reuse license, or "permission required"
    is `restricted` and never served;
  * the person was matched on a DATE (OTRRpedia's birth or death agreeing with
    Wikidata's), or on the undated rule (one namesake, a radio, stage or screen
    occupation of their own, an era that fits) when no other person of that
    name in our credits competes (`undated_served`); about 1 in 30 undated
    matches is someone else (catalog/reports/E-people-portraits.md), and the
    take-down path answers that;
  * the file is the person's own Wikidata image (P18). A file found because its
    Structured Data depicts the person can be a group photograph, which a
    portrait slot would crop to the wrong face;
  * a license that requires attribution has an author to attribute.

Library of Congress "no known restrictions" photographs and Smithsonian CC0
portraits (Track F) are not here: RESEARCH.md §12 V2 and V4 are the owner's.
"""
import json
import math
import os
import re
import urllib.parse

import networks as NW
import polish as PL

# The first seven are free licenses; the last three say nothing against reuse (040): the file is public domain
# where it was made (PD-old with no US template), the holder's own "no known restrictions", or its record has no
# rights sentence. They rank after every free class.
SERVED_CLASSES = ("pd_us", "pd_us_gov", "cc0", "pd_release", "free_use", "cc_by", "cc_by_sa",
                  "pd_source_only", "no_known_restrictions", "unmarked")
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


def clean_author(author):
    """The author as a person reads a credit: wiki markup and bare links dropped, nothing added. "{{Fortepan |id= 1 ...}}"
    is credited to "Fortepan"; "*File.jpg: Geoff Leonard. () *derivative work: X (talk)" to "Geoff Leonard; derivative
    work: X"; "Greg Hernandez at https://www.flickr.com/..." to "Greg Hernandez"."""
    a = PL.unescape((author or "").strip())
    m = re.match(r"\{\{\s*([^|{}]+?)\s*(?:\||\}\})", a)
    if m:
        return m.group(1)
    a = re.sub(r"^\*[^:*]*\.(?:jpe?g|png|gif|tiff?|webp)\s*:\s*", "", a, flags=re.I)
    a = re.sub(r"\(\s*\)|\(talk\)", "", a)
    a = re.sub(r"\s*\*\s*", "; ", a)
    a = re.sub(r"\s+at\s+https?://\S+", "", a)
    a = re.sub(r"https?://\S+", "", a)
    a = re.sub(r"[\s.]+;", ";", a)
    a = re.sub(r"\s{2,}", " ", a)
    return a.strip(" ;.") or (author or "").strip()


def credit(cls, template, author):
    """The line a credited image carries: 'Author, CC BY-SA 3.0'; None when none is owed."""
    name = license_name(cls, template)
    return f"{clean_author(author)}, {name}" if name else None


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


# --------------------------------------------------------------- 040: an explicit restriction is the only refusal
# A restriction is what the file's own page or record says against reuse. Template names are compared with
# everything but letters and digits dropped. A sentence is read only when the page names no free class, because a
# no-notice or not-renewed page quotes the original notice ("(c) 1941 NBC. All rights reserved") as the reason it
# is free.
RESTRICTED_TEMPLATES = ("nonfree", "fairuse", "allrightsreserved", "ccbync", "ccbynd", "ccnc", "ccnd", "noncommercial",
                        "permissionrequired", "restricted", "noreuse", "copyrightrestricted", "copyvio")
RESTRICTED_EXACT = ("copyrighted",)
RESTRICTION_TEXT = re.compile(
    r"all rights reserved|non-?free|fair[- ]use|rights?[ -]restricted|restricted (?:rights|use|access)|"
    r"permission (?:is |are )?(?:required|needed)|no[- ]reuse|not for reuse|"
    r"may not be (?:reproduced|reused|used)|reproduction (?:is )?prohibited|publication may be restricted|"
    r"used by permission only|creative commons[^.]{0,30}non-?commercial|\bby-n[cd]\b", re.I)


def restricted_template(name):
    """True when a template's own name is a restriction ('Non-free poster', 'Fair use', 'Cc-by-nc-3.0')."""
    k = re.sub(r"[^a-z0-9]", "", (name or "").lower())
    return k in RESTRICTED_EXACT or any(k.startswith(t) for t in RESTRICTED_TEMPLATES)


def restriction_in(text):
    """The sentence on a page or record that restricts reuse, or None. Used for a page that names no free class."""
    m = RESTRICTION_TEXT.search(text or "")
    return m.group(0) if m else None


ENWIKI_LOCAL = re.compile(r"upload\.wikimedia\.org/wikipedia/en/", re.I)


def enwiki_local(url):
    """A file under /wikipedia/en/ is hosted on English Wikipedia itself: its non-free (fair-use) files live there."""
    return bool(ENWIKI_LOCAL.search(url or ""))


# R3b V1, owner 2026-11-21: an undated person match is served when the person's own record names a radio, stage or
# screen occupation and no other person of that name in our credits competes for the face.
STAGE_SCREEN_RADIO_OCC = re.compile(
    r"\b(act(or|ress)|voice|radio|announcer|broadcast\w*|disc jockey|presenter|host|comedian|entertainer|performer|"
    r"vaudevillian|ventriloquist|singer|musician|bandleader|organist|pianist|violinist|screenwriter|playwright|"
    r"dramatist|scriptwriter|(?:film|radio|television|theat(?:re|er)|stage|motion picture)\s+(?:director|producer)|"
    r"newscaster|news anchor|commentator|narrator|impressionist|humorist|dancer|magician)\b", re.I)

# The doors 040 opens (an undated match, a class that only states no restriction) admit a face and nothing else: the
# file shows exactly one confident face and is no trailer frame, title card, poster, logo, grave or signature. The
# older doors keep their old checks.
OPENED_CLASSES = ("pd_source_only", "no_known_restrictions", "unmarked")
NOT_A_PORTRAIT = re.compile(r"(?<![a-z])(trailers?|screenshots?|screen\s?captures?|title cards?|posters?|logos?|covers?|"
                            r"stamps?|signatures?|autographs?|graves?|tombs?|statues?|monuments?|plaques?|ads?|"
                            r"advertisements?)(?![a-z])", re.I)


def norm_name(name):
    t = re.sub(r"[^a-z0-9]+", " ", PL.unescape(name or "").casefold().replace("’", "'").replace("'", ""))
    return t.strip()


def name_competes(name, counts):
    """True when another person of this name is among our credits. counts: {normalized name: distinct people}."""
    return counts.get(norm_name(name), 0) > 1


def undated_served(basis, occupations, competes):
    """The undated portrait rule: the match was made on name, occupation and a single candidate; the person's own
    Wikidata occupations include a radio, stage or screen one; and no other person of that name competes."""
    return (basis == UNDATED_BASIS and not competes
            and any(STAGE_SCREEN_RADIO_OCC.search(o or "") for o in occupations or ()))


def served(basis, cls, usable, found_via, author, own_work=False, date_field=None, died=None, undated_ok=False,
           faces=None, file=None):
    """True when this (person match, file) may leave the pipeline. `undated_ok` is `undated_served` for the person;
    `faces` and `file` are judged for the doors 040 opens (OPENED_CLASSES, the undated rule)."""
    if not usable or cls not in PREFER or found_via != SERVED_VIA or not (dated_match(basis) or (
            basis == UNDATED_BASIS and undated_ok)):
        return False
    if (cls in OPENED_CLASSES or basis == UNDATED_BASIS) and (faces != 1 or NOT_A_PORTRAIT.search(file or "")):
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


def alternate(basis, cls, usable, found_via, author, own_work=False, date_field=None, died=None, faces=None,
              undated_ok=False, file=None):
    """True when a depicts file may stand in for this person's own image: every check `served`
    makes, on a file showing one face."""
    return (found_via == ALTERNATE_VIA and faces == 1
            and served(basis, cls, usable, SERVED_VIA, author, own_work, date_field, died, undated_ok, faces,
                       file))


# ---------------------------------------------------------------- H5: archive photographs through people
# R3b section 5.1 H5 (owner V2/V4, ROUND3-LOOP.md): a Library of Congress "No known restrictions on publication" or
# Smithsonian CC0 photograph is a person's portrait when the record's own title is that person (and nothing else: a
# record that names two people, or "Herbert Hoover, Jr., and radio set", is not a portrait of the one), the person
# was alive and grown in the photograph's year, and the match is one the person rule serves (a dated Wikidata
# match, or our own birth and death years both known). Only for a person with no Commons portrait of their own:
# it changes who has a face, never which face a person who has one wears.
ARCHIVE_CLASS = {"no_known_restrictions": "no_known_restrictions", "government": "pd_us_gov", "cc0": "cc0",
                 "unmarked": "unmarked"}
ARCHIVE_VIA = {"loc": "loc:record-title", "smithsonian": "smithsonian:sitter"}
PORTRAIT_FILLER = frozenset(
    "portrait photograph photo head shoulders half three quarter length full bust standing seated sitting facing slightly "
    "left right front view at the microphone mike radio broadcasting broadcast studio a an in mr mrs miss dr".split())
ADULT_AGE = 10
SMITHSONIAN_STEP = "https://ids.si.edu/ids/deliveryService?id={id}&max=960&w="


def _name_tokens(text):
    t = re.sub(r"[^a-z0-9]+", " ", PL.unescape(text or "").casefold().replace("’", "'").replace("'", ""))
    return t.split()


def portrait_title(title, name):
    """True when a record's title is the person and only portrait words: "Graham McNamee", "[Herbert Hoover,
    three-quarter length portrait, seated, facing slightly left]", "Graham McNamee at the microphone". Any other
    word (a second person, "Jr.", a place, an event) means the record is about something else."""
    t, n = _name_tokens(title), _name_tokens(name)
    if len(n) < 2 or len(t) < len(n):
        return False
    for i in range(len(t) - len(n) + 1):
        if t[i:i + len(n)] == n:
            rest = t[:i] + t[i + len(n):]
            return all(w in PORTRAIT_FILLER or re.fullmatch(r"\d{4}|\d{1,2}", w) for w in rest)
    return False


PHOTOGRAPH = re.compile(r"^photograph", re.I)


def archive_portrait_served(source, rights_class, usable, title, name, photo_year, birth, death, basis, link_basis="",
                            object_type="Photograph"):
    """True when this archive record may be the portrait of this person (the policy above). `basis` is the person's
    Wikidata match (people_wikidata.basis, or None), `link_basis` photo_match's own reason for the tie: a
    Smithsonian sitter line whose printed lifespan agreed with ours. `object_type` is the holder's own kind of
    object: a photograph only (NPG's caricatures, drawings, busts, posters and prints are the sitter's likeness,
    never a photograph of them: R3b section 5.1 H5 is photographs)."""
    if source not in ARCHIVE_VIA or rights_class not in ARCHIVE_CLASS or not usable or not photo_year:
        return False
    if not PHOTOGRAPH.match(object_type or ""):
        return False
    if not (portrait_title(title, name) or str(link_basis).startswith("portrait:")):
        return False
    b, d = year_of(str(birth)) if birth else None, year_of(str(death)) if death else None
    if b is None and d is None:
        return False   # nothing of the person's own to set the photograph's year against
    if (b is not None and photo_year < b + ADULT_AGE) or (d is not None and photo_year > d):
        return False
    return bool(dated_match(basis) or (b is not None and d is not None))


def archive_image_url(source, url):
    """The address a client appends ?width= to. LoC's tile address is a plain file that ignores the query; a
    Smithsonian download is the master (thousands of pixels), so the delivery service gives 960 px, with a last
    parameter the client's ?width= falls into."""
    if source == "smithsonian":
        m = re.search(r"[?&]id=([^&]+?)(?:\.jpe?g)?$", url or "")
        return SMITHSONIAN_STEP.format(id=m.group(1)) if m else None
    return url


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
# The voices ranked in "Most heard voices" (contract section 3.3): a credit heard on the air, an
# announcer or a commercial spokesperson included; a writer, a director or a conductor is not a voice.
VOICE_ROLES = ON_AIR | {"announcer", "commercial spokesperson"}
VOICES_LIMIT = 300
STAR_MIN_EPISODES = 3
STAR_SHARE = 1 / 3


def rank_voices(credit_rows, names, limit=VOICES_LIMIT):
    """[(person id, served episodes heard on)], most first, ties by name then id, at most `limit`.
    credit_rows: (episode id, person id, role). An episode counts once for a person however many
    credits they hold in it; a role-only credit counts the same as a lead."""
    heard = {}
    for eid, pid, role in credit_rows:
        if role in VOICE_ROLES:
            heard.setdefault(pid, set()).add(eid)
    ranked = sorted(((pid, len(eps)) for pid, eps in heard.items()),
                    key=lambda t: (-t[1], (names.get(t[0]) or "").lower(), t[0]))
    return ranked[:limit]


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


# The grade (uniform-imagery-design section 2): one linear map, out = k * in + o, on sRGB-encoded
# luminance inside the crop a slot shows. lo and hi, the 1st and 99th percentile, go to 0.04 and
# 0.96; k stays between 1.0 and 1.6 (at 1.0 or below the grade is the identity), and at the cap the
# stretch is centered instead of pinning one end.
GRADE_LO, GRADE_HI, GRADE_KMIN, GRADE_KMAX = 0.04, 0.96, 1.0, 1.6


def grade_levels(lo, hi):
    """(k, o) for a measured luminance range, or (1.0, 0.0) when it already spans the range."""
    k = (GRADE_HI - GRADE_LO) / max(hi - lo, 1e-3)
    if k <= GRADE_KMIN:
        return 1.0, 0.0
    if k >= GRADE_KMAX:
        return GRADE_KMAX, 0.5 - GRADE_KMAX * (lo + hi) / 2
    return k, GRADE_LO - lo * k


def grade_text(lo, hi):
    """`art.grade` ("k,o", contract section 3.3a) for a measured range, or None for the identity."""
    k, o = grade_levels(lo, hi)
    if k == 1.0:
        return None
    return f"{k:.3f},{o:.3f}"


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
                "commons:P180", "commons:category", "commons:enwiki", "commons:name")
SHOW_RANK = {s: i for i, s in enumerate(SHOW_SOURCES)}
# How the series was matched to its Wikidata item. A title alone is never an identity
# (evidence-gated-catalog-curation section 7); a title with the years or the network is.
IDENTITY_SERVED = ("title+years", "title+network")
# A Commons search hit (H4, source `commons:name`) is tied to the show by its own file, not by a
# Wikidata item: the name in the file's own title or categories, and a date inside the run (rule 6).
NAME_SOURCE = "commons:name"
NAME_IDENTITY = "name+date"
# The largest show tile is 160 points (uniform-imagery-design: a show tile is 96 to 160 pt, and a
# slot takes a picture only with at least the slot's pixels): a smaller show image would be
# refused by every tile, so it does not displace a star who can fill one.
SHOW_MIN_SIDE = 160
# R3b section 5.2 rule 2: television, film and adaptations are refused, on the item and on the file.
# A still of the program's television run is a different broadcast (Life of Riley's TV cast), and a
# film trailer's frame is the film (Ann Sothern in "A Letter to Three Wives", served as Maisie's P18).
TELEVISION = re.compile(r"\b(television|TV)\b", re.I)
SCREEN = re.compile(r"\b(television|TV|films?|movies?|motion pictures?|trailers?|sitcoms?|telenovelas?)\b", re.I)
RADIO = re.compile(r"\bradio\b", re.I)


def screen_item(description=None, shortdesc=None, classes=(), radio_class=()):
    """Rule 2 on the item: True when the Wikidata item is a television or film work, not the radio
    program. An item with a radio-program class is never one (Cavalcade of America's single item is
    both runs: it matches, and series_identity and the file's own words keep its TV stills off the
    show). Otherwise its own description or its article's short description names the screen and
    not radio, or its classes (P31 labels) are all screen classes with no radio-program class among them, unless
    its own article's short description names radio with years and no screen (`radio_shortdesc`):
    a class is a Wikidata editor's guess, the article is about the program (H1).
    "Radio and television series" is still the radio one; "1949-1956 CBS television program" is not."""
    if radio_class:
        return False   # (also) the radio program; its images still face series_identity and rule 2 on the file
    for text in (description, shortdesc):
        if text and SCREEN.search(text) and not RADIO.search(text):
            return True
    if radio_shortdesc(shortdesc):
        return False
    labels = [c for c in classes or () if c]
    return bool(labels) and not radio_class and all(SCREEN.search(c) for c in labels)


def radio_shortdesc(text):
    """H1 (R3b section 5.1): an English Wikipedia article whose own short description names radio and
    years ('American radio drama (1942-1962)', '1940s American radio program') vouches for its
    Wikidata item as a radio program, whatever the item's class. One that also names the screen
    ('American radio and television series') does not: rule 2."""
    t = text or ""
    return bool(RADIO.search(t)) and description_years(t) is not None and not SCREEN.search(t)


# R3b section 5.2 rule 7: an organization matches by its QID, never by its name. "Blue" and "Mutual"
# are words before they are networks, and MBS Radio is Japan's Mainichi Broadcasting System.
def _network_qids():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "editorial", "network_qids.json")
    with open(path, encoding="utf-8") as f:
        table = json.load(f)
    return {k: {r["qid"] for r in rows} for k, rows in table.items() if not k.startswith("_")}


NETWORK_QIDS = _network_qids()


def network_qids(our_networks):
    """The Wikidata items that are any of our networks, by networks.py's spelling and by its fold."""
    out = set()
    for n in our_networks or ():
        for k in {NW.canonical_network(n), NW.fold_network(n)}:
            out |= NETWORK_QIDS.get(k, set())
    return out


YEAR_SLACK = 2


def description_years(text):
    """The years an item's own description names ('radio Western drama series (1952-1961)',
    'from the mid-1980s', "1920's", an abbreviated end as in '(1933-55)'), as (first, last), or None."""
    ys = []
    for m in re.finditer(r"\b(19\d\d|20[0-2]\d)('?s)?(?:\s*[-\u2013]\s*(\d\d)\b(?!\d))?", text or ""):
        y = int(m.group(1))
        ys += [y, y + 9] if m.group(2) else [y]
        if m.group(3):
            end = y // 100 * 100 + int(m.group(3))
            ys.append(end if end >= y else end + 100)
    return (min(ys), max(ys)) if ys else None


def series_identity(evidence, our_networks, broadcasters, description=None):
    """Rule 1 (R3b section 5.2, DECISIONS 017): a title is never enough. 'title+years' when the
    Wikidata item's years (its own dates, its article's short description or decade category, or the
    years its own description names) overlap ours within YEAR_SLACK; 'title+network' when one of its
    broadcasters, by QID (rule 7), is one of our networks; 'television' when its own description says
    it is the screen work (rule 2); else 'title' (refused).
    evidence: series_wikidata.match_evidence as a dict; broadcasters: the item's P449 QIDs."""
    evidence = evidence or {}
    if TELEVISION.search(description or "") and not RADIO.search(description or ""):
        return "television"   # its own description says it is the TV program (The Goldbergs, 1949-1956)
    if evidence.get("years") == "overlap":
        return "title+years"
    ours = [y for y in (evidence.get("our_years") or []) if y]
    dy = description_years(description)
    if ours and dy and dy[0] <= max(ours) + YEAR_SLACK and dy[1] >= min(ours) - YEAR_SLACK:
        return "title+years"
    if network_qids(our_networks) & set(broadcasters or ()):
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


def file_in_run(date_field, file, first_date=None, last_date=None):
    """Rule 3 (R3b section 5.2): the file's own date (its page's date field, else a year in its name)
    lies inside the run, YEAR_SLACK either side; an undated file is not refused here. Bob Barker's
    1958 headshot is the TV Truth or Consequences, and a 1914 photograph of the Hill Top House hotel
    predates the soap opera's first broadcast (1939)."""
    fy, last, first = file_year(date_field) or file_year(file), file_year(last_date), file_year(first_date)
    if fy and last and fy > last + YEAR_SLACK:
        return False
    return not (fy and first and fy < first - YEAR_SLACK)


def show_people(con, min_episodes=3):
    """{series key: [names]}: the people a program's records mark (series_marks; the cast and
    presenters of its matched Wikidata item) or credit on at least `min_episodes` of its episodes
    (episode_credits), the names rule 4 accepts in a file."""
    tables = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
    out = {}
    if {"series_marks", "people"} <= tables:
        for k, n in con.execute("SELECT m.series_key, p.name FROM series_marks m JOIN people p ON p.id = m.person_id"):
            out.setdefault(k, []).append(n)
    if "series_wikidata" in tables:   # the program's own Wikidata record: its cast and presenters
        for k, cast, creators in con.execute("SELECT series_key, cast_members, creators FROM series_wikidata"):
            for r in json.loads(cast or "[]") + [c for c in json.loads(creators or "[]") if c.get("role") == "presenter"]:
                if r.get("label"):
                    out.setdefault(k, []).append(r["label"])
    if "episode_credits" in tables:
        for k, n in con.execute(
                "SELECT e.series_key, c.name FROM episode_credits c JOIN episodes e ON e.id = c.episode_id "
                "WHERE c.name IS NOT NULL GROUP BY e.series_key, c.name "
                "HAVING COUNT(DISTINCT c.episode_id) >= ?", (min_episodes,)):
            out.setdefault(k, []).append(n)
    return out


def show_served(identity, source, cls, author, width, height, file, categories=(), date_field=None,
                last_date=None, first_date=None, own_work=False, died=None):
    """True when this (series match, file) may lead the show: the match is more than a title (rule
    1), the file came from one of the show's own records, its license class is one portraits are
    served under (credited when required), it is big enough for a show tile, its own name and
    categories do not say it is from television or film (rule 2), it is not an own work dated after
    its star's death, and its own date lies inside the run (rule 3). Whether the file names the show
    at all is rule 4, `names_the_show`, which each builder applies beside this."""
    if source not in SHOW_RANK or cls not in PREFER or not is_picture(file):
        return False
    if identity != NAME_IDENTITY if source == NAME_SOURCE else identity not in IDENTITY_SERVED:
        return False   # a name hit needs the file's own tie (name_hit_served); every other source needs the item's
    if cls in NEEDS_CREDIT and NO_AUTHOR.match(author or ""):
        return False
    if not width or not height or min(width, height) < SHOW_MIN_SIDE:
        return False
    if implausible_own_work(own_work, date_field, died):
        return False   # died: the earliest death among the people the program's record marks
    if not file_in_run(date_field, file, first_date, last_date):
        return False
    words = " ".join([file or ""] + list(categories or []))
    if TELEVISION.search(words):
        return False
    # A film's name in a radio publicity photo's categories is the picture the broadcast adapted
    # (Lux Radio Theatre's Bogart and Bacall, "To Have and Have Not (film)"): it is refused only
    # when nothing on the file says radio (a trailer frame, a lobby card).
    return not (SCREEN.search(words) and not RADIO.search(words))


PERSON_MIN = 6        # a person's name, letters only, long enough not to sit inside an ordinary word
PUBLICITY = re.compile(r"\bpublicity\b", re.I)


def names_the_show(file, categories, series_name, people=(), own_category=None, networks=()):
    """Rule 4 (R3b section 5.2): a topic is not a show. A show image needs, in the file's own name or
    its categories, the program's name, the name of a person the program's records mark or credit
    (`people`), the program's own Commons category (its item's P373), or a publicity category of one
    of the program's networks ("CBS Radio publicity photos"). Ceiling Unlimited's P18 is a B-17 in
    flight and Hello Americans' is a map of the Americas: each depicts the subject, not the program."""
    cats = list(categories or ())
    fold = lambda t: _nt(t).replace("theatre", "theater")   # Lux Radio Theatre is Lux Radio Theater
    hay = [fold(h) for h in [file or ""] + cats]
    name = fold(series_name) if series_name else ""
    if len(name) >= TITLE_MIN and any(name in h for h in hay):
        return True
    if own_category and any(c.split(":", 1)[-1] == own_category for c in cats):
        return True
    for p in people or ():
        n = _nt(p)
        if len(n) >= PERSON_MIN and any(n in h for h in hay):
            return True
    nets = {_nt(n) for n in networks or () if n}
    return any(PUBLICITY.search(c) and any(n and n in _nt(c) for n in nets) for c in cats)


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


# ---------------------------------------------------------------- Round 3 V2: more real images
# R3b sections 5.1-5.5. Every rule below is a predicate with a fixture test and a broken control in
# tests/test_art_v2.py; the builders import them, none decides for itself.

# A file that is not a picture (the audio file a search matched beside a photograph's name).
NOT_A_PICTURE = re.compile(r"\.(ogg|oga|ogv|opus|ogx|webm|mp3|mp4|mpe?g|flac|wav|mid|pdf|djvu|stl|xcf)$", re.I)


def is_picture(file):
    return not NOT_A_PICTURE.search(file or "")


def _words(text):
    return re.findall(r"[a-z0-9]+", (text or "").lower().replace("theatre", "theater"))


def _title_words(name):
    """A program's name as the words a file's title must carry: no leading article, no parenthesis."""
    w = _words(re.sub(r"\(.*?\)", " ", name or ""))
    return w[1:] if len(w) > 1 and w[0] in ("the", "a", "an") else w


def _holds(haystack_words, needle):
    n = len(needle)
    return n > 0 and any(haystack_words[i:i + n] == needle for i in range(len(haystack_words) - n + 1))


def name_in_file(file, categories, series_name):
    """True when the file's own title or categories are about the program (rule 6), as whole words:
    its title (extension dropped) opens with the program's name, or one of its categories IS the program
    (its parenthesis dropped: 'Suspense (radio series)'), or, for a name of three words or more, the name
    stands anywhere in the title or a category ('Cast of Stories of Mercy General'). Never a caption the
    search engine matched, never 'Saints' for 'The Saint', and never a longer program's name that
    contains ours: the series 'Radio Theater' is not 'Lux Radio Theatre', and 'Music' is the title
    of no photograph, only a word in 'Great Moments in Music'."""
    need = _title_words(series_name)
    if sum(len(w) for w in need) < TITLE_MIN:
        return False
    stem = _title_words(re.sub(r"\.[A-Za-z0-9]{2,5}$", "", file or ""))
    if stem[:len(need)] == need:
        return True
    cats = [c.split(":", 1)[-1] for c in categories or ()]
    if any(_title_words(c) == need for c in cats):
        return True
    return len(need) >= 3 and any(_holds(_words(h), need) for h in [re.sub(r"\.[A-Za-z0-9]{2,5}$", "", file or "")] + cats)


def name_hit_served(file, categories, date_field, series_name, first_date, last_date):
    """H4 (R3b section 5.1), rules 6, 3 and 2: a Commons search hit may lead a show when (a) the file is
    about the program (`name_in_file`), (b) the file has a date of its own (its page's date field, else a
    year in its name) and it lies inside the run, YEAR_SLACK either side (a hit with no date says nothing
    about which broadcast it shows: The Saint's hit was a 2004 photograph of an Italian journalist), and
    (c) radio is in the file's own title or one of its categories. (c) is the twin rule: Gunsmoke,
    Father Knows Best, The Twilight Zone, Burns and Allen and You Bet Your Life each have a television
    run beside the radio one, whose stills carry the same name, the same stars and the network's plain
    'publicity photos' category, and a date inside the run; only a file that says radio is the radio
    program. Television and film in the words are refused by `show_served`."""
    if not is_picture(file) or not name_in_file(file, categories, series_name):
        return False
    if not (first_date and last_date) or not (file_year(date_field) or file_year(file)):
        return False
    if not file_in_run(date_field, file, first_date, last_date):
        return False
    return any(RADIO.search(h) for h in [file or ""] + [c for c in categories or ()])


def lead_image_served(page_image_free, commons_status, url=None):
    """H3 (R3b section 4.1): an English Wikipedia article's lead image leads a show only when
    Wikipedia itself calls it free (`pageprops.page_image_free`) AND it is on Commons (its Commons file
    page reads, with a license the policy serves): 40 of 70 lead images measured were enwiki-local
    fair-use files, which are never served (a file hosted on English Wikipedia itself is non-free: `enwiki_local`).
    `show_served` still demands the item's identity (rule 1)."""
    return bool(page_image_free) and commons_status == "ok" and not enwiki_local(url)


# A screen capture or a screen producer's credit: "episode screenshot (NBC)", "NBC Productions", "Universal Pictures".
SCREEN_CREDIT = re.compile(r"\b(screen\s?shots?|screen\s?captures?|still from|frame from|productions?|studios?|pictures|"
                           r"television|tv|films?)\b", re.I)


def gallery_is_radio(file, categories, template=None, author=None, people=(), networks=()):
    """A gallery or hero file is radio (R3b section 5.2 rule 4, owner 2026-11-19): it has "radio" in its own name or
    categories, or it names a person the program's records mark and is no screen capture, or it sits in a network's
    radio publicity category. Television and film words refuse (`show_served`), and so does a screen capture or a
    screen producer's credit when radio is not in the words: The Great Gildersleeve's 1955 television stills sit in
    the program's own category and name Willard Waterman, so the category and the name alone do not make them radio."""
    cats = list(categories or ())
    hay = [file or ""] + cats
    own = hay + [x for x in (template, author) if x]   # the file page's credit is its own words too ("CBS Radio")
    if TELEVISION.search(" ".join(own)):
        return False
    if any(RADIO.search(h) for h in own):
        return True
    if SCREEN_CREDIT.search(" ".join(x for x in (template, author) if x)):
        return False
    folded = [_nt(h) for h in hay]
    return any(len(_nt(p)) >= PERSON_MIN and any(_nt(p) in h for h in folded) for p in people or ())


HERO_MIN_WIDTH = 600   # a hero fills a page header or Home's lead; narrower is soft at that size
GALLERY_MAX = 6


def landscape(width, height):
    """The box takes the image's shape (artwork-presentation-design): wide is past WIDE_ASPECT."""
    return bool(width and height) and width / height > WIDE_ASPECT


def _show_key(r):
    """Best first: the source, the license class, an original before a crop of it, then the name."""
    return (SHOW_RANK[r[1]], PREFER[r[2]], bool(re.search(r"\b(cropped|crop|edited|retouched)\b", r[0], re.I)), r[0])


def pick_hero(rows):
    """series.hero (R3b section 5.5): the best landscape show image, at least HERO_MIN_WIDTH wide, never
    a portrait stretched. rows: (file, source, cls, template, author, width, height, face), all passing
    `show_served`; None when no landscape one passes (the client draws the label, never a crop)."""
    wide = [r for r in rows if landscape(r[5], r[6]) and r[5] >= HERO_MIN_WIDTH]
    return min(wide, key=_show_key) if wide else None


def pick_gallery(rows, taken=()):
    """series.gallery: up to GALLERY_MAX further show images in order, each file once, never one
    already leading (`taken`: the picture's and hero's files)."""
    seen, out = {_same_picture(f) for f in taken}, []
    for r in sorted(rows, key=_show_key):
        if _same_picture(r[0]) not in seen:
            seen.add(_same_picture(r[0]))
            out.append(r)
    return out[:GALLERY_MAX]


def _same_picture(file):
    """A file's name with the words of a derivative dropped ('(cropped)', 'edited'): a crop of a photograph
    already in the gallery is the same picture twice."""
    stem = re.sub(r"\.[A-Za-z0-9]{2,5}$", "", file or "").lower()
    return re.sub(r"[^a-z0-9]", "", re.sub(r"\(\s*(?:cropped|crop|edited|edit|retouched)\s*\)|\b(?:cropped|edited)\b", "", stem))


# H9: a served image is hot-linked from Commons, so it can be deleted or moved under us. A HEAD on a
# TTL records 'ok' (the file answers), 'gone' (404 or 410), or nothing at all for a transient error;
# only 'gone' removes a candidate, and the next one leads (never a broken box, never a blip as dead).
LIVENESS_TTL_DAYS = 14
GONE = (404, 410)


def liveness_verdict(status):
    """'ok' | 'gone' | None (unknown: a 429, a 5xx, a timeout)."""
    if status in GONE:
        return "gone"
    return "ok" if isinstance(status, int) and 200 <= status < 400 else None


def alive(live, file):
    """False only for a file a liveness check found gone; one never checked is presumed alive."""
    return (live or {}).get(file, {}).get("verdict") != "gone"


def liveness_stale(rec, today_ordinal):
    """True when a file's last check is older than the TTL (or it has none)."""
    return not rec or today_ordinal - rec.get("day", 0) > LIVENESS_TTL_DAYS


# ---- plays (H7)

EDITION_LAST_YEAR = 1930   # published 1930 or earlier is public domain in the US by age
# Rule 8: a collection is not a first edition ("The Best Known Works of Ibsen", 1940).
COLLECTION_WORDS = frozenset(
    "works collected complete plays dramas dramatic best selected select volume volumes vol anthology library "
    "masterpieces series repertory repertoire three four five six seven eight nine ten twelve other".split())
# A book about a play is not an edition of it ("Ninon, Moliere et Tartuffe").
ABOUT_WORDS = frozenset("study studies criticism critical essay essays life biography notes commentary analysis "
                        "history guide introduction lectures".split())


def _fold(text):
    import unicodedata
    return "".join(c for c in unicodedata.normalize("NFKD", text or "") if not unicodedata.combining(c))


def surname_of(display):
    """The family name of an author as the record spells it ('Shaw, Bernard' or 'George Bernard Shaw')."""
    d = re.sub(r"\(.*?\)", " ", display or "").strip()
    d = d.split(",")[0] if "," in d else (d.split() or [""])[-1]
    return (_words(_fold(d)) or [""])[-1]


def holds_surname(creator, surnames):
    """True when an item's creator field carries one of our authors' family names as a whole word."""
    cw = _words(_fold(" ".join(creator) if isinstance(creator, (list, tuple)) else creator))
    return any(len(s) >= 3 and s in cw for s in surnames or ())


def edition_served(play_title, surnames, item):
    """H7 (R3b sections 5.1, 5.2 rule 8): a scanned edition of this play whose own record is the
    evidence: a text published in 1930 or earlier, its creator field holding the author's family name
    (a title alone is a common noun more often than not), its title opening with the play's own title,
    and no collection or study word in it that the play's title lacks. item: archive.org's own
    {title, creator, year, mediatype}."""
    try:
        year = int(str(item.get("year"))[:4])
    except (TypeError, ValueError):
        return False
    if item.get("mediatype") not in (None, "texts") or not (1400 <= year <= EDITION_LAST_YEAR):
        return False
    if not holds_surname(item.get("creator"), surnames):
        return False
    need = _title_words(_fold(play_title))
    got = _words(_fold(re.sub(r"^(the|a|an)\s+", "", item.get("title") or "", flags=re.I)))
    if sum(len(w) for w in need) < TITLE_MIN or got[:len(need)] != need:
        return False
    return not ((set(got) & (COLLECTION_WORDS | ABOUT_WORDS)) - set(need))


TITLE_PAGE_SCAN = 40       # a title page is among the first leaves of a book
TITLE_PAGE_MAX_CHARS = 1500


def title_page_ocr(pages, play_title, surnames):
    """H7: the index (in the OCR's own page list) of the first of an edition's first leaves whose own text is a
    title page of this play: short, holding the play's title words in order and one of the author's family
    names as whole words. A running head or a table of contents is long and a half-title holds no author.
    pages: the OCR text of each page, in order; None when no leaf qualifies."""
    need = _title_words(_fold(play_title))
    if sum(len(w) for w in need) < TITLE_MIN:
        return None
    for i, text in enumerate(pages[:TITLE_PAGE_SCAN]):
        w = _words(_fold(text))
        if 3 <= len(w) and len(text) <= TITLE_PAGE_MAX_CHARS and _holds(w, need) and \
                any(len(x) >= 3 and x in w for x in surnames or ()):
            return i
    return None


def title_page_agrees(scan_index, ocr_index):
    """The leaf archive.org's own scan data types as the title page (`scan_index`, its place among the leaves
    that are in the page list) and the leaf whose own OCR is a title page (`ocr_index`) are the same page. The
    OCR list may lack the first leaf (a Google scan's 'digitized by' cover), so it may sit one place earlier. MEASURED
    2026-11-19: the scan data's type alone named a copyright page, a contents page or a text page in 8 of 12
    leaves read by eye; the OCR alone cannot say which index the page image has."""
    return scan_index is not None and ocr_index is not None and scan_index in (ocr_index, ocr_index + 1)


def work_served(play_title, surnames, work):
    """H7: a Wikidata work item stands for the play when its label is the play's title and its P50
    author's name, or its description, carries one of our authors' family names (rule 8): 'In Honour
    Bound' is a 1925 radio play, not Grundy's 1885 stage play, and the author says which.
    work: {label, authors: [names], description}."""
    if _title_words(_fold(work.get("label"))) != _title_words(_fold(play_title)):
        return False
    pool = [surname_of(a) for a in work.get("authors") or ()] + _words(_fold(work.get("description")))
    return any(len(s) >= 3 and s in pool for s in surnames or ())


def play_title(t):
    """A Gutenberg title as the play is named: one line, cut at a subtitle ('; Or, ...', ': A Comedy') or a
    'From the Quarto of 1604' note."""
    t = re.sub(r"\s+", " ", t or "")
    t = re.sub(r"\s*[:;(\[].*$", "", t).strip()
    return re.sub(r"\s+(?:from|by|with|edited|translated)\b.*$", "", t, flags=re.I)


def work_image_is_of_the_work(file, title, surnames):
    """H7: a work item's own image stands for the play unless it is a portrait of its author: a file whose
    name holds the author's family name and not the play's title ('G Bernard Shaw.jpg' is Misalliance's P18)
    is the playwright, who has his own slot (`play.authorArt`). A name with neither (a scene's title) stands."""
    words = _words(_fold(re.sub(r"\.[A-Za-z0-9]{2,5}$", "", file or "")))
    named = any(len(s) >= 3 and s in words for s in surnames or ())
    return not named or _holds(words, _title_words(_fold(title)))


def play_image_served(cls, author, width, height, own_work=False, date_field=None, died=None):
    """H7: a file that stands for a play or its author is served under the license classes portraits
    are (credited when owed), big enough for a tile, and is not an own work dated after the death of
    the person it shows (the portrait rule, `implausible_own_work`)."""
    if cls not in PREFER or (cls in NEEDS_CREDIT and NO_AUTHOR.match(author or "")):
        return False
    if not width or not height or min(width, height) < SHOW_MIN_SIDE:
        return False
    return not implausible_own_work(own_work, date_field, died)


PLAY_KINDS = ("work", "production", "titlePage", "author")   # what leads a play: the work's image, a Federal Theatre
# Project production picture (040), a title page, the author


def pick_play(rows):
    """play.picture: work image, then title page, then the author's portrait (R3b section 5.5), else
    None (the script-page label). rows: (kind, ...) in any order."""
    order = {k: i for i, k in enumerate(PLAY_KINDS)}
    return min(rows, key=lambda r: order[r[0]]) if rows else None


# --------------------------------------------------------------- 040 V3: Federal Theatre Project pictures for plays
# A photograph or poster of the Federal Theatre Project (a federal agency's work, records with no rights sentence)
# is the picture of a play it staged when the record's own title or quoted title is that play. A costume or scene
# design, a script, a clipping or a program is a drawing or a document, not a picture of the production.
FTP = re.compile(r"federal theat(?:re|er) project", re.I)
FTP_DESIGN = re.compile(r"costume designs?|set designs?|scene designs?|scenic designs?|prop(?:erty)? designs?|"
                        r"lighting|clippings?|scripts?|budget|playbill", re.I)
QUOTED = re.compile(r"[\"“]([^\"”]{3,80})[\"”]")
FTP_CLASSES = ("government", "no_known_restrictions", "unmarked", "cc0")


def ftp_titles(title, summary=None, description=None):
    """The production names an FTP record gives: its quoted titles ('presents "Horse eats hat"') and, for a
    production photograph, the words before the first colon ('The Trojan Incident: Strapless gold gown')."""
    out = [m.group(1) for t in (title, summary, description) for m in QUOTED.finditer(t or "")]
    head = re.sub(r"^\[|\]$", "", (title or "").strip()).split(":", 1)
    if len(head) == 2 and head[0].strip():
        out.append(head[0].strip())
    return out


BY_AUTHOR = re.compile(r"\bby\s+((?:[A-Z][\w.'\-]*\.?\s*){1,5})")


def ftp_play_served(rights_class, usable, contributors, partof, title, summary, description, play, width=None,
                    height=None, authors=None):
    """True when this Library of Congress record is a picture of this play's Federal Theatre Project production:
    the record is the Federal Theatre Project's (its contributors or collections), its rights class is usable
    (no restriction on the record), it is no design drawing or document, it is big enough for a tile when its
    size is known, and one of the production names it gives IS the play's title, word for word (an article
    dropped). A title that only contains the play's is another work."""
    if not usable or rights_class not in FTP_CLASSES:
        return False
    owners = " ".join(str(x) for x in list(contributors or []) + list(partof or []))
    if not FTP.search(owners + " " + (title or "")):
        return False
    if FTP_DESIGN.search(" ".join([title or "", owners])):
        return False
    if width and height and min(width, height) < SHOW_MIN_SIDE:
        return False
    need = _title_words(play_title(play))
    if sum(len(w) for w in need) < TITLE_MIN:
        return False
    if not any(_title_words(t) == need for t in ftp_titles(title, summary, description)):
        return False
    # A poster that says who wrote the play it announces is that play only when the author is ours: the Federal
    # Theatre's "Brothers" by Herbert Ashton Jr. is not Terence's "The Brothers" (spot check, 2026-11-21).
    said = [m.group(1) for t in (title, summary, description) for m in BY_AUTHOR.finditer(t or "")]
    if said and authors:
        words = set(_words(" ".join(said)))
        return any(sn in words for sn in (surname_of(a).lower() for a in authors) if len(sn) >= 3)
    return True


# --------------------------------------------------------------- 040 V5: pages of unrenewed radio magazine issues
# An issue is free when its year was not renewed (or is public domain by age): the issue-year row of
# `magazine_rights`. The issue's own notice is what lapsed. A notice on the PAGE that is somebody else's (a photograph
# credited "(c) NBC", an advertisement's "Copyright 1938 General Foods") is that holder's own claim, and the page is
# refused. The page is tied to a program only when its own text names the program, or a person the program's record
# marks, and its year lies inside the run.
MAGAZINE_STATUS = ("not_renewed", "pd_by_age")
MAGAZINE_SOURCE = "archive.org:magazine"
# Owner ruling 2026-11-21: measured, magazine pages were the right subject about one time in two, and 040 kept every
# accuracy rule, so no magazine page reaches the projection. The harvest, the enrichment and their caches stay.
SERVE_MAGAZINE_PAGES = False
PUBLISHERS = ("macfadden", "triangle publications", "triangle pub", "annenberg", "fawcett", "radio stars",
              "radio mirror", "radio guide", "movie and radio guide", "tower magazines", "dell publishing")
NOTICE = re.compile(r"(?:©|\(c\)|\bcopyright\b|\bcopr\.?)\s*(?:19|20)?\d{0,2}\d{0,2}[^.\n]{0,70}", re.I)
MAGAZINE_MIN_WORDS, MAGAZINE_MAX_WORDS = 25, 450


def page_notice(text):
    """The first copyright notice on a page that is not the magazine publisher's own, or None."""
    for m in NOTICE.finditer(text or ""):
        held = m.group(0).lower()
        if not any(p in held for p in PUBLISHERS):
            return m.group(0).strip()
    return None


# The page is about the program, not a listing or an advertisement that mentions it: a magazine for listeners (not
# a trade paper's directory), the name at least twice on the page or in its first words (a headline), and a name
# particular enough to mean the program (two content words, or ten letters). A spot check of the first version, which
# accepted any mention, found most pages were directory entries, advertisements and articles that named the program
# in passing (2026-11-21).
LISTENER_MAGAZINES = ("Radio Mirror", "Radio Guide", "Radio Stars", "Radio Digest", "Tune In", "Screen and Radio Weekly",
                      "Radio Varieties", "Radio Album", "Radioland", "Radio Life")
HEADLINE_CHARS = 80


def _about(phrase, folded):
    import photo_match as M
    p = re.sub(r"^the ", "", M.fold(phrase))
    if not p:
        return False
    hits = re.findall(r"(?<![a-z0-9])" + re.escape(p) + r"(?![a-z0-9])", folded)
    return len(hits) >= 2 and p in folded[:HEADLINE_CHARS]


# A sponsor's advertisement names programs and stars as its testimonial or its hour; it is not about them.
ADVERTISEMENT = re.compile(r"\b(cigarettes?|tobacco|luckies|soap|toothpaste|powder|cream|lotion|laxative|coupon|"
                           r"send (?:\d+ )?cents?|for \d+ days|per cent|ovaltine|pepsodent|chesterfield|camels?|"
                           r"cosmetics?|complexion|dentists?|trial offer|money back)\b", re.I)


def magazine_page_served(status, nwords, text, year, series_name, people=(), first_date=None, last_date=None,
                         folded=None, magazine=None):
    """The tie when this page of this issue is about this program ("name" when the page is about the program,
    "marked person" when it is about a person the program's record marks), else False.
    status: the issue-year row's status; nwords/text: the short page as harvested; year: the issue's."""
    import photo_match as M
    if status not in MAGAZINE_STATUS or not (MAGAZINE_MIN_WORDS <= (nwords or 0) <= MAGAZINE_MAX_WORDS):
        return False
    if magazine is not None and magazine not in LISTENER_MAGAZINES:
        return False
    if page_notice(text) or ADVERTISEMENT.search(text or ""):
        return False
    if first_date and last_date and year:
        if not (year_of(first_date) - YEAR_SLACK <= year <= year_of(last_date) + YEAR_SLACK):
            return False
    folded = folded or M.fold(text)
    content = [w for w in M.fold(re.sub(r"^the ", "", M.fold(series_name or ""))).split() if w not in M.GENERIC]
    if M.series_name_ok(series_name) and (len(content) >= 2 or len(M.fold(series_name).replace(" ", "")) >= 10) \
            and _about(series_name, folded):
        return "name"
    for p in people or ():
        n = M.fold(p)
        if len(n.replace(" ", "")) >= PERSON_MIN and len(n.split()) >= 2 and _about(n, folded):
            return "marked person"
    return False
