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


def served(basis, cls, usable, found_via, author):
    """True when this (person match, file) may leave the pipeline."""
    if not usable or cls not in PREFER or found_via != SERVED_VIA or not dated_match(basis):
        return False
    if cls in NEEDS_CREDIT and NO_AUTHOR.match(author or ""):
        return False
    return True


def image_url(file):
    """The file's Commons address with no width; each client's one helper appends ?width=."""
    return FILEPATH + urllib.parse.quote(file.replace(" ", "_"))


def evidence_url(file):
    return FILE_PAGE + urllib.parse.quote(file.replace(" ", "_"))


def pick(rows):
    """The one portrait per person: the most permissive class, then the file name.
    rows: (file, cls, template, author) already passing `served`."""
    return min(rows, key=lambda r: (PREFER[r[1]], r[0])) if rows else None


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
