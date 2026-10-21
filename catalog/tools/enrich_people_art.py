"""Credited radio people -> Wikidata humans, and the portraits that are free to use.

    python3 tools/harvest_people_wikidata.py   # first: fills .cache/people_wd/
    python3 tools/enrich_people_art.py         # POST-BUILD: adds people_wikidata, people_art

A POST-BUILD step like enrich_external.py: it drops and rebuilds ONLY its own
tables (people_wikidata, people_art, people_art_meta) and writes
out/enrich_people_art_report.json. It reads the caches only (no network).

The matching rules and the licence classes live here as pure functions, so the
harvester (which must know who matched before it reads their Commons pages) and
the tests use the same code.

MATCHING (conservative; every row records its basis):
  * candidates are Wikidata items typed human (P31 Q5) whose English or "mul"
    label or alias equals one of the person's name variants (`name_variants`:
    the name, every spelling in `names`, the birth name, the name without a
    quoted nickname, the nickname + surname, the name without middle initials,
    "Jr." forms);
  * when we hold a birth or death year, a candidate must AGREE on one of them
    (exact year) and contradict neither (both sides known and more than one year
    apart). One agreeing candidate is a match; several are left ambiguous unless
    exactly one agrees on both years;
  * when we hold no year at all, the person must have exactly ONE human
    candidate, it must carry an occupation of the radio trades (actor, writer,
    announcer, broadcaster, musician ...: `RELEVANT_OCC`), and its own dates must
    fit the era of our credits (born at least 12 years before the first credit,
    not dead before it). A candidate with no Wikidata year at all is refused,
    since its era cannot be checked;
  * a dated person whose candidates carry no year is NOT accepted on the
    undated rule: our date is evidence, and an item that cannot be checked
    against it is not a match.

LICENCES (`license_class`, read from the Commons file page's wikitext; Track D's
`template_class` decides the PD-US templates):
  usable  pd_us       PD-US-no notice / not renewed / expired / 1978-89 /
                      defective notice / PD-US / PD-1996 / *-expired (PD-old-auto-expired)
          pd_us_gov   PD-USGov* (a federal employee's work)
          cc0         CC0 / cc-zero
          pd_release  PD-self / PD-author / PD-user (the author's own release)
          cc_by       CC BY (attribution required)
          cc_by_sa    CC BY-SA (attribution + share-alike)
  not     gfdl_only   GFDL with no CC alternative (the licence text must travel)
          pd_source_only  PD-old-* with no US template (no US evidence)
          no_known_restrictions  Flickr "no known copyright restrictions"
          contested   a deletion request, copyvio, no-permission/no-source/no-licence tag
          unknown     nothing recognized
A file page is recorded with its template as written and its author/source; a
person still opens the page before a portrait ships (Track D: many no-notice tags
rest on no visible evidence).
"""
import gzip
import hashlib
import json
import os
import re
import sqlite3
import sys
import time
import unicodedata
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ia_lib import CACHE, OUT, write_json  # noqa: E402
from harvest_ext_commons import template_class  # noqa: E402

DIR = os.path.join(CACHE, "people_wd")
DB = os.path.join(OUT, "radio-catalog.sqlite")

RELEVANT_OCC = re.compile(
    r"\b(act(or|ress)|voice|radio|announcer|broadcast|disc jockey|presenter|host|"
    r"writer|screenwriter|playwright|dramatist|author|novelist|poet|scriptwriter|lyricist|"
    r"director|producer|composer|conductor|musician|singer|bandleader|organist|pianist|"
    r"violinist|arranger|comedian|entertainer|performer|vaudevillian|ventriloquist|"
    r"journalist|newscaster|news anchor|commentator|narrator|impressionist|humorist|"
    r"sound designer|showrunner|dancer|magician)\b", re.I)
USABLE = {"pd_us", "pd_us_gov", "cc0", "pd_release", "cc_by", "cc_by_sa"}
PREFER = {c: i for i, c in enumerate(("pd_us", "pd_us_gov", "cc0", "pd_release", "cc_by", "cc_by_sa"))}
OBLIGATIONS = {"cc_by": "attribution", "cc_by_sa": "attribution, share-alike"}
CONTESTED = re.compile(r"^(delete|deletionrequest|copyvio|nopermissionsince|nosourcesince|"
                       r"nolicensesince|nolicense|speedydelete|speedy|dr|copyrightviolation)$")
# Read from Commons 2026-10-21 (index.php?action=raw on the template pages):
# PD-old-auto-1978 is "#REDIRECT [[Template:PD-US-no notice]]", PD-Pre1964 redirects
# to PD-US-not renewed; NoC-US is rightsstatements.org's "No Copyright - United
# States", the holding institution's own determination. PD-Van Vechten wraps the
# Library of Congress "no known copyright restrictions" statement, which is not a
# determination of status, so it is not counted usable.
ALIASES = {"pdoldauto1978": "pd_us", "pdpre1964": "pd_us", "nocus": "pd_us",
           "pdvanvechten": "no_known_restrictions"}
WRAP_PARAMS = {"self", "pdart", "pdscan", "licensedpdart", "pdarttwo", "licensedpdarttwo",
               "multilicensereplacing", "selfie"}


# ---------------------------------------------------------------- names

def norm(s):
    s = unicodedata.normalize("NFKD", s or "")
    s = "".join(ch for ch in s if not unicodedata.combining(ch)).lower()
    s = re.sub(r"[\"'‘’“”.]", "", s)
    s = re.sub(r"[^a-z0-9]+", " ", s)
    return re.sub(r"\s+", " ", s).strip()


PARTICLES = {"von", "van", "de", "del", "della", "di", "du", "la", "le", "der", "den", "da", "dos"}
GROUP = re.compile(r"\b(orchestra|trio|quartet|quintet|sextet|singers|chorus|choir|ensemble|band|"
                   r"brothers|sisters|boys|girls|players|men|dreamers)\b|^the\s|\band his\b|\band her\b", re.I)


def _forms(n):
    n = re.sub(r"\s+", " ", (n or "").strip())
    if not n or len(n) < 4 or " " not in n or GROUP.search(n):
        return set()
    if re.match(r"^(.*?),\s*(the)$", n, re.I):
        return set()  # a group ("Honey Dreamers, The"), never a human
    out = {n}
    m = re.search(r"\s*[,]?\s*\b(jr|sr|ii|iii)\.?$", n, re.I)
    if m:
        base = n[:m.start()].strip(" ,")
        suf = m.group(1).capitalize() if m.group(1).lower() in ("jr", "sr") else m.group(1).upper()
        dot = "." if suf in ("Jr", "Sr") else ""
        out |= {base, f"{base} {suf}{dot}", f"{base}, {suf}{dot}"}
    for x in list(out):
        q = re.search(r"\s+(?:['\"\u2018\u201c]([^'\"\u2019\u201d]+)['\"\u2019\u201d]|\(([^)]+)\))\s+", x)
        if q:
            nick = (q.group(1) or q.group(2)).strip()
            without = re.sub(r"\s+", " ", (x[:q.start()] + " " + x[q.end():]).strip())
            out.add(without)
            parts = without.split()
            if len(parts) >= 2:
                out.add(nick + " " + parts[-1])
    for x in list(out):
        parts = x.split()
        if len(parts) >= 3 and not re.fullmatch(r"[A-Z]\.?", parts[0]):
            kept = [p for i, p in enumerate(parts) if not (0 < i < len(parts) - 1 and re.fullmatch(r"[A-Z]\.?", p))]
            if len(kept) >= 2:
                out.add(" ".join(kept))
    for x in list(out):
        parts = x.split()
        flip = [p.lower() if p in {w.capitalize() for w in PARTICLES} else
                (p.capitalize() if p in PARTICLES else p) for p in parts]
        if flip != parts:
            out.add(" ".join(flip))
    return {re.sub(r"\s+", " ", x).strip() for x in out if len(x.split()) >= 2}


def name_variants(name, names=None, birth_name=None, cap=8):
    seen = []
    for n in [name] + list(names or []) + ([birth_name] if birth_name else []):
        for f in sorted(_forms(n), key=lambda s: (s != n, len(s))):
            if f not in seen:
                seen.append(f)
    return seen[:cap]


def year(s):
    m = re.match(r"^(\d{4})", s or "")
    if not m:
        return None
    y = int(m.group(1))
    return y if 1700 <= y <= 2030 else None


# ---------------------------------------------------------------- matching

def _event(ours, wd_years, wd_date):
    """How one event (birth or death) compares: day (same full date), year (same
    year, or one apart), monthday (same month and day, years 2-10 apart: the
    shaved or misread birth year of a performer, seen 2026-10-21 on Joseph
    Kearns, Hans Conried, Alice Faye; Gracie Allen by seven), near (one year apart: not a conflict, and
    agreement only beside a monthday), unknown (a side has no year), conflict."""
    y = year(ours)
    wy = set(wd_years or [])
    if y is None or not wy:
        return "unknown"
    full = re.fullmatch(r"\d{4}-(\d\d)-(\d\d)", ours or "")
    wfull = re.fullmatch(r"\d{4}-(\d\d)-(\d\d)", wd_date or "")
    same_md = bool(full and wfull and full.groups() == wfull.groups() and full.group(1) != "00")
    if y in wy:
        return "day" if same_md and ours == wd_date else "year"
    if any(abs(y - w) <= 1 for w in wy):
        return "near"
    if same_md and any(abs(y - w) <= 10 for w in wy):
        return "monthday"
    return "conflict"


def decide(person, cands):
    """person: {birth, death, first_year}; cands: {qid: entity} for every human
    candidate found under any variant. Returns (qid|None, basis, detail)."""
    by, dy = year(person.get("birth")), year(person.get("death"))
    if not cands:
        return None, "no_candidate", None
    if by or dy:
        agree = []
        for q, e in cands.items():
            sb = _event(person.get("birth"), e.get("birth_years"), e.get("birth"))
            sd = _event(person.get("death"), e.get("death_years"), e.get("death"))
            if "conflict" in (sb, sd):
                continue
            if not ({sb, sd} & {"day", "year"}) and {sb, sd} != {"monthday", "near"}:
                continue
            agree.append((q, sb, sd))
        if len(agree) == 1:
            q, sb, sd = agree[0]
            return q, "name+" + "+".join(f"{k}_{v}" for k, v in (("birth", sb), ("death", sd))
                                         if v != "unknown"), None
        if len(agree) > 1:
            both = [a for a in agree if a[1] in ("day", "year") and a[2] in ("day", "year")]
            if len(both) == 1:
                q, sb, sd = both[0]
                return q, f"name+birth_{sb}+death_{sd}", f"{len(agree)} agreed on one event"
            return None, "ambiguous_dated", ",".join(sorted(a[0] for a in agree))
        return None, "dates_disagree", ",".join(sorted(cands))
    if len(cands) != 1:
        return None, "ambiguous_undated", ",".join(sorted(cands))
    q, e = next(iter(cands.items()))
    occ = [o for o in e.get("occupations") or [] if RELEVANT_OCC.search(o)]
    if not occ:
        return None, "undated_occupation_unrelated", q
    cb, cd = e.get("birth_years") or [], e.get("death_years") or []
    fy = person.get("first_year")
    if not cb and not cd:
        return None, "undated_no_wikidata_year", q
    if fy:
        if cb and min(cb) > fy - 12:
            return None, "undated_era_mismatch", q
        if cd and max(cd) < fy:
            return None, "undated_era_mismatch", q
    return q, "name+occupation+unique", ";".join(occ[:3])


# ---------------------------------------------------------------- licences

def _templates(text):
    """(name, [positional params]) of every innermost template on a page."""
    out = []
    for m in re.finditer(r"\{\{\s*([^|{}]+?)\s*(\|[^{}]*)?\}\}", text or ""):
        params = [p.strip() for p in (m.group(2) or "")[1:].split("|")] if m.group(2) else []
        out.append((m.group(1).strip(), [p for p in params if p and "=" not in p]))
    return out


def _k(s):
    return re.sub(r"[^a-z0-9]", "", (s or "").lower())


def license_class(text):
    """(class, template as written, obligations) for one Commons file page."""
    if text is None:
        return "unread", None, None
    toks = [name for name, _ in _templates(text)]
    flat = text
    for _ in range(4):  # flatten nested templates so a wrapper's own parameters can be read
        flat2 = re.sub(r"\{\{(?:[^{}|]*\|)*?[^{}]*\{\{[^{}]*\}\}", lambda m: m.group(0)[:m.group(0).rfind("{{")], flat)
        if flat2 == flat:
            break
        flat = flat2
    for m in re.finditer(r"\{\{\s*([^|{}]+?)\s*\|([^{}]*)\}\}", flat):
        if _k(m.group(1)) in WRAP_PARAMS:
            toks += [x.strip() for x in m.group(2).split("|") if x.strip() and "=" not in x]
    found = {}
    for t in toks:
        k = _k(t)
        low = t.lower().strip()
        if k in ALIASES:
            found.setdefault(ALIASES[k], t)
        elif CONTESTED.match(k):
            found.setdefault("contested", t)
        elif k.startswith("pdusgov"):
            found.setdefault("pd_us_gov", t)
        elif k.startswith("pdus") or k in ("pd1996", "pdoldauto1996") or (k.startswith("pd") and k.endswith("expired")):
            found.setdefault("pd_us", t)
        elif k in ("cczero", "cc0", "cc010") or low.startswith("cc-zero") or low.startswith("cc0"):
            found.setdefault("cc0", t)
        elif k in ("pdself", "pdauthor", "pduser", "pdreleased", "pduserw") or k.startswith("pduser"):
            found.setdefault("pd_release", t)
        elif low.startswith("cc-by-sa"):
            found.setdefault("cc_by_sa", t)
        elif low.startswith("cc-by") and "-nc" not in low and "-nd" not in low:
            found.setdefault("cc_by", t)
        elif k.startswith("gfdl"):
            found.setdefault("gfdl_only", t)
        elif k.startswith("pdold") or (k.startswith("pd") and k not in WRAP_PARAMS and len(k) > 2):
            found.setdefault("pd_source_only", t)
        elif "noknowncopyrightrestrictions" in k:
            found.setdefault("no_known_restrictions", t)
    tc, tw = template_class(text)
    if tc and "pd_us" not in found:
        found["pd_us"] = tw
    if "contested" in found:
        return "contested", found["contested"], None
    for c in ("pd_us", "pd_us_gov", "cc0", "pd_release", "cc_by", "cc_by_sa", "gfdl_only",
              "pd_source_only", "no_known_restrictions"):
        if c in found:
            return c, found[c], OBLIGATIONS.get(c)
    return "unknown", None, None


def _strip_markup(s):
    s = re.sub(r"<[^>]+>", "", s or "")
    s = re.sub(r"\{\{\s*(?:creator|c)\s*:\s*([^|}]+)[^}]*\}\}", r"\1", s, flags=re.I)
    s = re.sub(r"\{\{\s*(?:unknown|anonymous)[^}]*\}\}", "unknown", s, flags=re.I)
    s = re.sub(r"\{\{[^{}]*\}\}", "", s)
    s = re.sub(r"\[\[(?:[^|\]]*\|)?([^\]]+)\]\]", r"\1", s)
    s = re.sub(r"\[https?://\S+\s+([^\]]+)\]", r"\1", s)
    s = re.sub(r"\[(https?://\S+)\]", r"\1", s)
    s = re.sub(r"'''?", "", s)
    return re.sub(r"\s+", " ", s).strip(" ,;")[:200] or None


def file_facts(text):
    """Author, date and source links of a Commons file page."""
    def field(*names):
        for n in names:
            m = re.search(r"\|\s*" + n + r"\s*=(.*?)(?=\n\s*\||\n\}\}|\}\}\s*$)", text or "", re.S | re.I)
            if m and m.group(1).strip():
                return m.group(1).strip()
        return None
    src = field("source", "Source")
    return {"author": _strip_markup(field("author", "Author", "photographer", "Photographer", "artist")),
            "date_field": _strip_markup(field("date", "Date")),
            "source_links": re.findall(r"https?://[^\s\]|}<]+", src)[:5] if src else [],
            "source_text": _strip_markup(src)}


def commons_urls(filename):
    name = filename.replace(" ", "_")
    q = urllib.parse.quote(name)
    return ("https://commons.wikimedia.org/wiki/File:" + q,
            "https://commons.wikimedia.org/wiki/Special:FilePath/" + q + "?width=330")


# ---------------------------------------------------------------- DB step

def ranked_people(con):
    """Every credited person, most-credited first, with roles, series and era."""
    rows = con.execute("""
        SELECT p.id, p.name, p.names, p.birth_name, p.birth, p.death,
               COUNT(DISTINCT ec.episode_id) AS eps,
               COUNT(DISTINCT e.series_key) AS ser,
               MIN(substr(e.air_date,1,4)) AS fy, MAX(substr(e.air_date,1,4)) AS ly
        FROM people p JOIN episode_credits ec ON ec.person_id = p.id
        LEFT JOIN episodes e ON e.id = ec.episode_id
        GROUP BY p.id ORDER BY eps DESC, p.id""").fetchall()
    roles = {}
    for pid, role, n in con.execute(
            "SELECT person_id, role, COUNT(DISTINCT episode_id) FROM episode_credits GROUP BY person_id, role"):
        roles.setdefault(pid, {})[role] = n
    out = []
    for rank, r in enumerate(rows, 1):
        try:
            names = json.loads(r[2]) if r[2] else []
        except json.JSONDecodeError:
            names = []
        out.append({"id": r[0], "name": r[1], "names": names, "birth_name": r[3], "birth": r[4],
                    "death": r[5], "episodes": r[6], "series": r[7],
                    "first_year": int(r[8]) if r[8] and r[8].isdigit() else None,
                    "last_year": int(r[9]) if r[9] and r[9].isdigit() else None,
                    "rank": rank, "roles": roles.get(r[0], {})})
    return out


def load_cache():
    def rj(p, default):
        p = os.path.join(DIR, p)
        if not os.path.exists(p):
            return default
        op = gzip.open if p.endswith(".gz") else open
        with op(p, "rt", encoding="utf-8") as f:
            return json.load(f)
    return rj("names.json.gz", {}), rj("entities.json.gz", {}), rj("files.json.gz", {})


def match_all(people, names_idx, ents):
    res = {}
    for p in people:
        vs = name_variants(p["name"], p["names"], p["birth_name"])
        if not vs:
            res[p["id"]] = (None, "not_a_personal_name", None, vs)
            continue
        if not all(v in names_idx for v in vs):
            res[p["id"]] = (None, "not_queried", None, vs)
            continue
        qs = {q for v in vs for q in names_idx[v]}
        cands = {q: ents[q] for q in qs if q in ents}
        if len(cands) < len(qs):
            res[p["id"]] = (None, "entities_missing", None, vs)
            continue
        q, basis, detail = decide(p, cands)
        res[p["id"]] = (q, basis, detail, vs)
    return res


def depicts_index():
    """Track D's Commons files whose Structured Data depicts a human: qid -> [title]."""
    p = os.path.join(CACHE, "commons", "files.json.gz")
    if not os.path.exists(p):
        return {}
    files = json.load(gzip.open(p, "rt"))
    idx = {}
    for t, v in files.items():
        for q in v.get("depicts") or []:
            idx.setdefault(q, []).append(t)
    return idx


def page_text(filename):
    """A Commons file page's wikitext from this track's cache or Track D's, else None."""
    title = "File:" + filename.replace("_", " ")
    key = hashlib.sha1(("commons.wikimedia.org|" + title).encode()).hexdigest() + ".json.gz"
    for d in (os.path.join(DIR, "commons_raw"), os.path.join(CACHE, "commons", "raw")):
        p = os.path.join(d, key)
        if os.path.exists(p):
            with gzip.open(p, "rt", encoding="utf-8") as f:
                return json.load(f).get("text")
    return None


SCHEMA = """
DROP TABLE IF EXISTS people_wikidata;
DROP TABLE IF EXISTS people_art;
DROP TABLE IF EXISTS people_art_meta;
CREATE TABLE people_wikidata (
  person_id TEXT PRIMARY KEY, qid TEXT, basis TEXT, detail TEXT,
  label TEXT, description TEXT, birth TEXT, death TEXT, occupations TEXT,
  imdb TEXT, enwiki TEXT, commons_category TEXT, credited_episodes INTEGER, rank INTEGER,
  evidence_url TEXT
);
CREATE TABLE people_art (
  person_id TEXT, qid TEXT, file TEXT, found_via TEXT,
  license_class TEXT, usable INTEGER, template TEXT, obligations TEXT,
  author TEXT, date_field TEXT, source_links TEXT,
  evidence_url TEXT, thumb_url TEXT,
  PRIMARY KEY (person_id, file)
);
CREATE TABLE people_art_meta (k TEXT PRIMARY KEY, v TEXT);
"""


def main():
    con = sqlite3.connect(DB)
    people = ranked_people(con)
    names_idx, ents, files = load_cache()
    if not names_idx:
        print("no harvest cache: run tools/harvest_people_wikidata.py first", file=sys.stderr)
        sys.exit(1)
    res = match_all(people, names_idx, ents)
    dep = depicts_index()
    con.executescript(SCHEMA)
    wd_rows, art_rows = [], []
    for p in people:
        q, basis, detail, _ = res[p["id"]]
        e = ents.get(q) if q else None
        wd_rows.append((p["id"], q, basis, detail, e and e.get("label"), e and e.get("description"),
                        e and e.get("birth"), e and e.get("death"),
                        json.dumps(e.get("occupations")) if e else None,
                        e and (e.get("imdb") or [None])[0], e and e.get("enwiki"),
                        e and (e.get("commons_category") or [None])[0],
                        p["episodes"], p["rank"], f"https://www.wikidata.org/wiki/{q}" if q else None))
        if not e:
            continue
        titles = [("wikidata:P18", f) for f in e.get("images") or []]
        titles += [("commons:depicts", t.split(":", 1)[1]) for t in dep.get(q, [])]
        seen = set()
        for via, fn in titles:
            if fn in seen:
                continue
            seen.add(fn)
            fv = dict(files.get(fn) or {})
            text = page_text(fn)
            if text is not None:  # classed again from the page, so a rule change needs no re-harvest
                fv["class"], fv["template"], _ = license_class(text)
                fv.update(file_facts(text))
            cls = fv.get("class", "unread")
            page, thumb = commons_urls(fn)
            art_rows.append((p["id"], q, fn, via, cls, int(cls in USABLE), fv.get("template"),
                             OBLIGATIONS.get(cls), fv.get("author"), fv.get("date_field"),
                             json.dumps(fv.get("source_links") or []), page, thumb))
    con.executemany("INSERT INTO people_wikidata VALUES (" + ",".join("?" * 15) + ")", wd_rows)
    con.executemany("INSERT OR IGNORE INTO people_art VALUES (" + ",".join("?" * 13) + ")", art_rows)
    rep = report(people, res, ents, art_rows)
    con.executemany("INSERT INTO people_art_meta VALUES (?,?)",
                    [("built", time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())),
                     ("report", json.dumps(rep))])
    con.commit()
    write_json(os.path.join(OUT, "enrich_people_art_report.json"), rep)
    print(json.dumps(rep, indent=1)[:4000])


def report(people, res, ents, art_rows):
    by_person = {}
    for r in art_rows:
        by_person.setdefault(r[0], []).append(r)
    rep = {}
    for label, n in (("top500", 500), ("top2000", 2000), ("all", len(people))):
        sub = people[:n]
        matched = [p for p in sub if res[p["id"]][0]]
        with_img = [p for p in matched if by_person.get(p["id"])]
        usable = [p for p in matched if any(r[5] for r in by_person.get(p["id"], []))]
        classes = {}
        for p in usable:
            best = sorted((r for r in by_person[p["id"]] if r[5]),
                          key=lambda r: PREFER.get(r[4], 99))[0]
            classes[best[4]] = classes.get(best[4], 0) + 1
        bases = {}
        for p in sub:
            b = res[p["id"]][1]
            bases[b] = bases.get(b, 0) + 1
        rep[label] = {"people": len(sub), "matched": len(matched), "with_image": len(with_img),
                      "with_usable_image": len(usable), "usable_by_best_class": classes,
                      "basis": dict(sorted(bases.items(), key=lambda kv: -kv[1])),
                      "with_imdb": sum(1 for p in matched if ents[res[p["id"]][0]].get("imdb")),
                      "with_enwiki": sum(1 for p in matched if ents[res[p["id"]][0]].get("enwiki"))}
    files = {}
    for r in art_rows:
        files[r[2]] = r[4]
    fc = {}
    for c in files.values():
        fc[c] = fc.get(c, 0) + 1
    rep["files_by_class"] = dict(sorted(fc.items(), key=lambda kv: -kv[1]))
    shared = {}
    for pid, (q, *_rest) in res.items():
        if q:
            shared.setdefault(q, []).append(pid)
    rep["qids_shared_by_several_person_ids"] = sum(1 for v in shared.values() if len(v) > 1)
    return rep


if __name__ == "__main__":
    main()
