"""Post-build enrichment: people, credits, runs, networks and sponsors.

    python3 tools/enrich_db.py            # out/radio-catalog.sqlite, in place (atomic)
    python3 tools/enrich_db.py --db PATH

Runs AFTER build_db.py. It opens the built database and ADDS tables and
columns; it never rewrites build_db's rows (a re-run drops and rebuilds only
what this tool added). Inputs, all cached by their harvesters:

  .cache/goldin/records.json.gz        RadioGOLDINdex, every record (harvest_goldin.py)
  .cache/otrr/programs/*.json.gz       OTRR episode logs with people (harvest_otrr.py)
  .cache/otrrpedia/progPedia.json.gz   OTRRpedia programs: genres, histories, sponsors
  .cache/otrrpedia/peoplePedia.json.gz OTRRpedia people (id, name)
  .cache/otrrpedia/programs/*.json.gz  programData: DATED sponsors, histories
  .cache/otrrpedia/people/*.json.gz    personData: birth/death, Goldin artist link
  editorial/series_aliases.json        read-only, the same aliases build_db applies

Tables added: people, episode_credits, program_runs, sponsors, goldin_records,
series_map. Columns added: series.{otrr_idp, networks, first_broadcast,
last_broadcast, broadcast_span_source, genres_otrr, sponsors_otrr},
episodes.{network, network_source, goldin_cat, otrr_eid}.

Goldin's plot text and OTRR contributors' notes are PROSE: they are stored with
their provenance and `display_allowed = 0`; the owner must obtain permission
before a client shows them. Everything else here is fact (Feist).

Linking is on (series, date): a program name maps to one of our series keys by
name (otr_parse.norm_series, the editorial aliases, "X, The" reordered), or,
when the name alone does not, by DATE CORROBORATION — at least 3 of the
program's dated records fall on dates our series has an episode, they are at
least 30% of its dated records, and the two names share a significant word.
Undated episodes link on (series, normalized title) only when the title is
unique on both sides. Every link carries the method that made it.
"""
import argparse
import collections
import datetime
import glob
import gzip
import json
import os
import re
import shutil
import sqlite3
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
import ia_lib as ia
import otr_parse as P

GOLDIN_URL = "https://radiogoldin.library.umkc.edu/ProgramMoreinfo/{}"
OTRR_PROGRAM_URL = "https://www.otrr.org/OTRRPedia/?p={}"
GOLDIN_PROVENANCE = "RadioGOLDINdex (J. David Goldin), radiogoldin.library.umkc.edu, record {}"

MONTHS = {m: i for i, m in enumerate(
    ["january", "february", "march", "april", "may", "june", "july", "august", "september",
     "october", "november", "december"], 1)}
NAME_SUFFIX = re.compile(r"^(jr\.?|sr\.?|ii|iii|iv|m\.?d\.?|ph\.?d\.?|esq\.?)$", re.I)
STATION = re.compile(r"^[KWC][A-Z]{2,3}(-(?:AM|FM))?$")
STOP = {"the", "and", "of", "a", "an", "show", "program", "programme", "hour", "theater", "theatre",
        "radio", "presents", "with", "in", "on", "for", "to", "time", "new", "family"}


# ---------------------------------------------------------------- parsing

def goldin_date(s):
    """'March 01, 1945' -> '1945-03-01'; a bare year or anything else -> None."""
    m = re.match(r"^\s*([A-Za-z]+)\s+(\d{1,2}),\s*(\d{4})\s*$", s or "")
    if not m or m.group(1).lower() not in MONTHS:
        return None
    y, mo, d = int(m.group(3)), MONTHS[m.group(1).lower()], int(m.group(2))
    try:
        return datetime.date(y, mo, d).isoformat()
    except ValueError:
        return None


def goldin_duration(s):
    """(exact seconds, nominal minutes). '29:42' is a timing; '*30 minutes' and
    '*1/2 hour' are Goldin's starred nominal lengths, kept apart."""
    s = (s or "").strip()
    m = re.match(r"^(?:(\d+):)?(\d{1,3}):(\d{2})$", s)
    if m:
        h, mi, se = int(m.group(1) or 0), int(m.group(2)), int(m.group(3))
        return h * 3600 + mi * 60 + se, None
    m = re.match(r"^\*?\s*(\d+)\s*minutes?$", s, re.I)
    if m:
        return None, int(m.group(1))
    m = re.match(r"^\*?\s*(\d+)/(\d+)\s*hours?$", s, re.I)
    if m:
        return None, round(60 * int(m.group(1)) / int(m.group(2)))
    m = re.match(r"^\*?\s*(\d+(?:\.\d+)?)\s*hours?$", s, re.I)
    if m:
        return None, round(60 * float(m.group(1)))
    return None, None


def split_top(s, sep=","):
    """Split on `sep` outside parentheses and double quotes. A string whose parentheses do not
    close ("Max Terr (music (music), Tony La Frano (announcer)") is split again with a
    parenthesis that never nests, so one typo does not make the whole cast list one name."""
    out = _split_top(s, sep, True)
    return _split_top(s, sep, False) if _open_parens(s) else out


def _open_parens(s):
    depth, q = 0, False
    for ch in s:
        if ch == '"':
            q = not q
        elif ch == "(" and not q:
            depth += 1
        elif ch == ")" and not q and depth:
            depth -= 1
    return depth > 0


def _split_top(s, sep, nest):
    out, buf, depth, q = [], [], 0, False
    for ch in s:
        if ch == '"':
            q = not q
        elif ch == "(" and not q:
            depth = depth + 1 if nest else 1
        elif ch == ")" and not q and depth:
            depth -= 1
        if ch == sep and depth == 0 and not q:
            out.append("".join(buf))
            buf = []
        else:
            buf.append(ch)
    out.append("".join(buf))
    return [x.strip() for x in out if x.strip()]


def parse_artists(s):
    """Goldin's Artists string -> [{name, role, character, note}].

    'William Spier (producer, editor, director)' gives three rows; a quoted
    parenthesis ('Joseph Kearns ("The Man In Black")') is a character; a long
    parenthesis that is not a list of short roles is kept as a note, not a role.
    'Sammy Davis, Jr.' stays one name. A string with 2+ non-empty ';' segments
    is a cast list Goldin typed with semicolons: each segment is parsed on its
    own, so no whole cast list becomes one person."""
    s = (s or "").strip().rstrip(";").strip()
    segs = [x for x in split_top(s, ";") if x.strip(" ,")]
    if len(segs) >= 2:
        return [a for seg in segs for a in parse_artists(seg)]
    parts = split_top(s or "")
    merged = []
    for p in parts:
        if merged and NAME_SUFFIX.match(p.split("(")[0].strip()):
            merged[-1] = merged[-1] + ", " + p
        else:
            merged.append(p)
    out = []
    for p in merged:
        m = re.match(r"^(.*?)\s*\((.*)\)\s*$", p, re.S)
        name, inner = (m.group(1), m.group(2)) if m else (p, "")
        name = re.sub(r"\s+", " ", name).strip(" ;,")
        if not name or name in ("*", "?"):
            continue
        roles, character, note = [], None, None
        if "(" in inner:
            inner = re.sub(r"\b(\w+)(?:\s+\1\b)+", r"\1", inner.replace("(", " "))
        if inner:
            if inner.strip().startswith('"') and inner.strip().endswith('"') and inner.count('"') == 2:
                character = inner.strip().strip('"')
            else:
                pieces = [x.strip() for x in re.split(r",|\band\b|&", inner) if x.strip()]
                if pieces and all(x.lower() in ("possibly", "probably", "maybe", "?") for x in pieces):
                    note = inner.strip()
                elif pieces and all(len(x.split()) <= 4 and '"' not in x for x in pieces):
                    roles = [x.lower() for x in pieces]
                else:
                    note = inner.strip()
        for r in [norm_role(x) for x in roles] or ["cast"]:
            out.append({"name": name, "role": r, "character": character, "note": note})
    return out


def collapse_character_roles(crow):
    """Rows are (episode, person, name, role, character, ...). OTRR files an actor's character
    as a role ("the man in black"); when Goldin credits the same person as cast in that
    character, the cast row says it and the role-as-character row is dropped."""
    played = {(r[0], r[1], r[4].lower()) for r in crow if r[3] == "cast" and r[4]}
    return [r for r in crow if not (r[3] != "cast" and (r[0], r[1], r[3].lower()) in played)]


def parse_source(s):
    """Goldin's Source -> (network, distribution, is_tv).

    'CBS net, KQW, San Jose aircheck' -> ('CBS', 'network', False);
    'CBS-TV net' -> (None, 'television', True); 'ZIV Syndication' ->
    (None, 'syndicated', False); 'AFRS origination' -> ('AFRS', 'afrs', False)."""
    s = (s or "").strip()
    if not s or s == "*":
        return None, None, False
    first = (split_top(s) or [s])[0]
    if re.search(r"-TV\b|\baudio \+ video\b|\btelevision\b", s, re.I):
        return None, "television", True
    m = re.match(r"^(.*?)\s+(?:net|network)\b", first, re.I)
    if m:
        net = m.group(1).strip()
        net = {"Red": "NBC Red", "Blue": "Blue", "NBC Blue": "Blue"}.get(net, net)
        return net, "network", False
    if re.match(r"^AFRT?S\b", first):
        return first.split()[0], "afrs", False
    if re.search(r"syndicat", first, re.I):
        return None, "syndicated", False
    if STATION.match(first.split()[0]):
        return None, "local:" + first.split()[0], False
    return None, None, False


ROLE_SAME = {"cast member": "cast", "adapter": "adaptor", "m.c.": "emcee", "mc": "emcee",
             "commercial spokeswoman": "commercial spokesperson", "commercial spokesman": "commercial spokesperson"}


def norm_role(r):
    r = re.sub(r"\s+", " ", (r or "cast").strip().lower()) or "cast"
    return ROLE_SAME.get(r, r)


def norm_title(t):
    t = re.sub(r"[\"\u201c\u201d]", "", (t or "").lower()).strip()
    t = re.sub(r"^(the|a|an)\s+", "", t)
    t = re.sub(r",\s*(the|a|an)$", "", t)
    return re.sub(r"[^a-z0-9]", "", t)


def norm_person(n):
    n = (n or "").lower()
    n = re.sub(r"[\"'.]", "", n)
    return re.sub(r"[^a-z0-9]+", " ", n).strip()


def reorder(name):
    m = re.match(r"^(.*), (The|A|An)$", (name or "").strip())
    return f"{m.group(2)} {m.group(1)}" if m else name


def words(name):
    return {w for w in re.findall(r"[a-z0-9]+", (name or "").lower()) if len(w) >= 4 and w not in STOP}


LEAD = {"the", "a", "an", "bbc", "cbc", "afrs", "nbc", "cbs", "remote"}
TRAIL = {"show", "program", "programme", "hour", "theater", "theatre", "series", "eps", "the"}


def tokens(name):
    """Name -> word sequence for same_name: 'X, The' reordered, CamelCase
    split (not after 'Mc'), network/`The` prefixes, 'Adventures of', and
    trailing 'Show', '03 Eps', '(49-52)' style residue dropped."""
    n = reorder(name or "")
    n = re.sub(r"(?<=[a-z])(?<!Mc)(?=[A-Z])", " ", n)
    t = re.findall(r"[a-z0-9]+", n.lower().replace("'", ""))
    while t and t[0] in LEAD:
        t = t[1:]
    if t[:2] in (["adventures", "of"], ["new", "adventures"]):
        t = t[2:] if t[1] == "of" else t[2:]
        if t[:1] == ["of"]:
            t = t[1:]
    while t and (t[-1] in TRAIL or t[-1].isdigit()):
        t = t[:-1]
    return t


def contiguous(small, big):
    return any(big[i:i + len(small)] == small for i in range(len(big) - len(small) + 1))


def same_name(prog, series_name, series_key=None):
    """Is a program name the same name as a series? Not 'shares a word':
    either one name's significant words all appear in the other's (the
    smaller side carrying at least two, and two thirds of the larger), or one name's word sequence occurs
    whole inside the other's and is at least half its letters. MEASURED
    2026-10-19: 'shares a word' mapped CBS News of the World to Radio News
    and Cavalcade of Music to The Cavalcade of America; letter containment
    mapped BBC Radio Newsreel to Radio News; a bare subset mapped Guest Star
    (a Treasury series) to Jack Benny As A Guest Star."""
    a = words(prog) | words(reorder(prog))
    b = words(series_name)
    small, big = (a, b) if len(a) <= len(b) else (b, a)
    if len(small) >= 2 and small <= big and 3 * len(small) >= 2 * len(big):
        return True
    x, y = tokens(prog), tokens(series_name)
    if not x or not y:
        return False
    s, l = (x, y) if len(x) <= len(y) else (y, x)
    ls, ll = len("".join(s)), len("".join(l))
    return ls >= 6 and ls >= 0.5 * ll and contiguous(s, l)


class SeriesMap:
    """Maps a source's program name to one of the database's series keys."""

    def __init__(self, known, aliases, by_date):
        self.known = known            # key -> display name
        self.aliases = {k: v for k, v in aliases.items() if not k.startswith("_")}
        self.by_date = by_date        # date -> set(series_key)

    def by_name(self, names):
        """Every series key a name spells, raw or reordered: our catalog can
        hold 'The Lone Ranger' as both loneranger and lonerangerthe."""
        out = []
        for nm in names:
            for v in (nm, reorder(nm)):
                k = P.norm_series(v)
                if k in self.aliases:
                    k = P.norm_series(self.aliases[k])
                if k and k in self.known and k not in out:
                    out.append(k)
        return out

    def by_dates(self, names, dates, min_hits=3, min_share=0.3):
        """Keys whose episodes fall on the program's dates AND whose name is
        the same name (see same_name). Several keys can qualify when our
        series is split (Jungle Jim 01..05); together they must cover
        min_share of the program's dated records, each with min_hits."""
        dates = set(dates)
        if len(dates) < min_hits:
            return None, None, None
        hits = collections.Counter()
        for d in dates:
            for k in self.by_date.get(d, ()):
                hits[k] += 1
        keys = [k for k, n in hits.most_common() if n >= min_hits
                and any(same_name(nm, self.known.get(k) or k) for nm in names)]
        covered = sum(hits[k] for k in keys)
        if keys and covered >= min_share * len(dates):
            return keys, "date_corroborated", {"hits": {k: hits[k] for k in keys}, "dated": len(dates)}
        return None, None, None

    def resolve(self, names, dates):
        """-> (keys, {key: method}, evidence). Name matches first; keys the
        dates corroborate (same name, a split series) are added to them."""
        how = {k: "name" for k in self.by_name(names)}
        keys, _m, ev = self.by_dates(names, dates)
        for k in keys or ():
            how.setdefault(k, "date_corroborated")
        if not how:
            return None, None, None
        return list(how), how, ev


# ---------------------------------------------------------------- loaders

def gz(path, default=None):
    if not os.path.exists(path):
        return default
    with gzip.open(path, "rt") as f:
        return json.load(f)


def load_otrr_logs():
    rows = []
    for p in sorted(glob.glob(os.path.join(ia.CACHE, "otrr", "programs", "*.json.gz"))):
        d = gz(p)
        for r in d["episodes"]:
            r["idp"] = r.get("idp") or d["idp"]
            rows.append(r)
    return rows


def load_pedia():
    progs = {p["idp"]: p for p in gz(os.path.join(ia.CACHE, "otrrpedia", "progPedia.json.gz"), []) or
             gz(os.path.join(ia.CACHE, "otrr", "progPedia.json.gz"), [])}
    full = {}
    for p in glob.glob(os.path.join(ia.CACHE, "otrrpedia", "programs", "*.json.gz")):
        full[os.path.basename(p).split(".")[0]] = gz(p)
    people = gz(os.path.join(ia.CACHE, "otrrpedia", "peoplePedia.json.gz"), []) or []
    pdata = {}
    for p in glob.glob(os.path.join(ia.CACHE, "otrrpedia", "people", "*.json.gz")):
        pdata[os.path.basename(p).split(".")[0]] = gz(p)
    return progs, full, people, pdata


# ---------------------------------------------------------------- enrichment

SCHEMA = """
DROP TABLE IF EXISTS people;
DROP TABLE IF EXISTS episode_credits;
DROP TABLE IF EXISTS program_runs;
DROP TABLE IF EXISTS sponsors;
DROP TABLE IF EXISTS goldin_records;
DROP TABLE IF EXISTS series_map;
CREATE TABLE people (
  id TEXT PRIMARY KEY,           -- otrr:<OTRRpedia id> | goldin:<normalized name>
  name TEXT, names TEXT,         -- names: JSON, every spelling seen
  otrr_id TEXT, goldin_name TEXT,
  birth TEXT, death TEXT, birth_name TEXT, birth_place TEXT,
  sources TEXT                   -- JSON list: otrr | goldin
);
CREATE TABLE episode_credits (
  episode_id TEXT, person_id TEXT, name TEXT, role TEXT, character TEXT,
  source TEXT,                   -- otrr | goldin
  source_ref TEXT,               -- OTRR eid | Goldin CATALOGNUM
  method TEXT                    -- file | series_date | series_title
);
CREATE TABLE program_runs (
  series_key TEXT, otrr_idp TEXT, network TEXT, country TEXT, start TEXT, end TEXT,
  day TEXT, time TEXT, length_min INTEGER, sponsor TEXT, source TEXT
);
CREATE TABLE sponsors (series_key TEXT, otrr_idp TEXT, sponsor TEXT, start TEXT, end TEXT, source TEXT);
CREATE TABLE goldin_records (
  catalognum INTEGER PRIMARY KEY, url TEXT,
  program TEXT, series_key TEXT, series_method TEXT,
  air_date TEXT, date_text TEXT, title TEXT, prognumb TEXT,
  artists TEXT, source_text TEXT, network TEXT, distribution TEXT, is_tv INTEGER,
  duration_s INTEGER, duration_nominal_min INTEGER, duration_text TEXT,
  quality TEXT, complete TEXT, sponsor TEXT,
  plot TEXT, plot_display_allowed INTEGER, plot_provenance TEXT,
  episode_id TEXT, episode_method TEXT
);
CREATE TABLE series_map (
  source TEXT, program TEXT, program_id TEXT, series_key TEXT, method TEXT, evidence TEXT
);
"""
INDEXES = """
CREATE INDEX ec_ep ON episode_credits(episode_id);
CREATE INDEX ec_person ON episode_credits(person_id);
CREATE INDEX gr_ep ON goldin_records(episode_id);
CREATE INDEX gr_series ON goldin_records(series_key, air_date);
CREATE INDEX pr_series ON program_runs(series_key);
CREATE INDEX sp_series ON sponsors(series_key);
CREATE INDEX sm_series ON series_map(series_key);
"""
SERIES_COLS = ["otrr_idp TEXT", "networks TEXT", "first_broadcast TEXT", "last_broadcast TEXT",
               "broadcast_span_source TEXT", "genres_otrr TEXT", "sponsors_otrr TEXT"]
EPISODE_COLS = ["network TEXT", "network_source TEXT", "goldin_cat INTEGER", "otrr_eid TEXT"]


def add_columns(db, table, cols):
    have = {r[1] for r in db.execute(f"PRAGMA table_info({table})")}
    for c in cols:
        name = c.split()[0]
        if name not in have:
            db.execute(f"ALTER TABLE {table} ADD COLUMN {c}")
        else:
            db.execute(f"UPDATE {table} SET {name} = NULL")


class People:
    def __init__(self, pedia_people, pdata):
        self.rows = {}
        self.by_norm = collections.defaultdict(set)
        self.goldin_link = {}
        for p in pedia_people:
            name = " ".join(x for x in (p.get("first"), p.get("last")) if x).strip()
            pid = "otrr:" + p["idp"]
            self.rows[pid] = {"id": pid, "name": name, "names": {name}, "otrr_id": p["idp"], "goldin_name": None,
                              "birth": None, "death": None, "birth_name": None, "birth_place": None,
                              "sources": {"otrr"}}
            self.by_norm[norm_person(name)].add(pid)
        for idp, d in pdata.items():
            row = self.rows.get("otrr:" + idp)
            if not row or not d:
                continue
            for k, src in (("birth", "dtbirth"), ("death", "dtdeath")):
                v = d.get(src) or ""
                row[k] = v if re.match(r"^\d{4}-\d{2}-\d{2}$", v) and not v.startswith("0000") else None
            row["birth_name"] = d.get("birthName") or None
            row["birth_place"] = d.get("birthPlace") or None
            for l in d.get("links") or []:
                if str(l.get("idtype")) == "102" and "ArtistNumber=" in (l.get("url") or ""):
                    gname = l["url"].split("&ArtistNumber=")[0]
                    last, _, first = gname.partition(",")
                    full = f"{first.strip()} {last.strip()}".strip()
                    row["goldin_name"] = full
                    self.goldin_link.setdefault(norm_person(full), "otrr:" + idp)

    def otrr(self, pid, name):
        key = "otrr:" + pid
        if key not in self.rows:
            self.rows[key] = {"id": key, "name": name, "names": {name}, "otrr_id": pid, "goldin_name": None,
                              "birth": None, "death": None, "birth_name": None, "birth_place": None,
                              "sources": {"otrr"}}
        return key

    def goldin(self, name):
        n = norm_person(name)
        pid = self.goldin_link.get(n)
        if not pid and len(self.by_norm.get(n, ())) == 1:
            pid = next(iter(self.by_norm[n]))
        if not pid:
            pid = "goldin:" + n
            if pid not in self.rows:
                self.rows[pid] = {"id": pid, "name": name, "names": set(), "otrr_id": None, "goldin_name": name,
                                  "birth": None, "death": None, "birth_name": None, "birth_place": None,
                                  "sources": set()}
        row = self.rows[pid]
        row["names"].add(name)
        row["sources"].add("goldin")
        return pid


def enrich(db, goldin_rows, otrr_logs, progs, full, pedia_people, pdata, aliases):
    stats = collections.Counter()
    db.executescript(SCHEMA)
    add_columns(db, "series", SERIES_COLS)
    add_columns(db, "episodes", EPISODE_COLS)

    known = dict(db.execute("SELECT key, COALESCE(name, key) FROM series"))
    eps = db.execute("SELECT id, series_key, air_date, title FROM episodes").fetchall()
    by_sd = collections.defaultdict(list)
    by_st = collections.defaultdict(list)
    by_date = collections.defaultdict(set)
    for eid, sk, d, t in eps:
        if d:
            by_sd[(sk, d)].append(eid)
            by_date[d].add(sk)
        else:
            nt = norm_title(t)
            if len(nt) >= 4:
                by_st[(sk, nt)].append(eid)
    smap = SeriesMap(known, aliases, by_date)

    # --- OTRR programs -> series keys (names: every OTRRpedia title + the log's own)
    log_by_idp = collections.defaultdict(list)
    for r in otrr_logs:
        log_by_idp[r["idp"]].append(r)
    otrr_key = {}
    all_idps = set(progs) | set(log_by_idp)
    for idp in all_idps:
        names = [t["title"] for t in (progs.get(idp) or {}).get("titles") or [] if t.get("title")]
        names += sorted({r["program"] for r in log_by_idp.get(idp, []) if r.get("program")})
        dates = [r["date"] for r in log_by_idp.get(idp, []) if r.get("date")]
        keys, how, ev = smap.resolve(names, dates)
        if keys:
            otrr_key[idp] = keys
            for k in keys:
                db.execute("INSERT INTO series_map VALUES (?,?,?,?,?,?)",
                           ("otrr", names[0] if names else None, idp, k, how[k], json.dumps(ev) if ev else None))
                stats["otrr_program_keys_" + how[k]] += 1
            stats["otrr_programs_mapped"] += 1
        elif names:
            stats["otrr_programs_unmapped"] += 1

    people = People(pedia_people, pdata)

    # --- credits: what build_db already linked by file, then OTRR logs by series+date / title
    credited = collections.defaultdict(set)   # episode -> {(person, role)}
    otrr_linked = set()
    crow = []
    for ep, pid, name, role, _src in db.execute("SELECT episode_id, person_id, name, role, source FROM credits"):
        key = people.otrr(pid, name) if pid else people.goldin(name)
        role = norm_role(role)
        if (key, role) in credited[ep]:
            continue
        credited[ep].add((key, role))
        otrr_linked.add(ep)
        crow.append((ep, key, name, role, None, "otrr", None, "file"))
    stats["credits_from_build_db"] = len(crow)

    ep_otrr = {}
    title_rows = collections.defaultdict(list)
    for r in otrr_logs:
        for k in otrr_key.get(r["idp"], ()):
            if r.get("date"):
                for ep in by_sd.get((k, r["date"]), []):
                    ep_otrr.setdefault(ep, (r["eid"], "series_date"))
            else:
                title_rows[(k, norm_title(r.get("title")))].append(r)
    for (k, nt), rs in title_rows.items():
        targets = by_st.get((k, nt), [])
        if len(nt) >= 4 and len(rs) == 1 and len(targets) == 1:
            ep_otrr.setdefault(targets[0], (rs[0]["eid"], "series_title"))
    eid_row = {r["eid"]: r for r in otrr_logs}
    for ep, (oeid, how) in ep_otrr.items():
        db.execute("UPDATE episodes SET otrr_eid = ? WHERE id = ?", (oeid, ep))
        stats["episodes_otrr_" + how] += 1
        if ep in otrr_linked:
            continue
        for pp in eid_row[oeid].get("people") or []:
            key = people.otrr(pp["id"], pp["name"])
            role = norm_role(pp["role"])
            if (key, role) in credited[ep]:
                continue
            credited[ep].add((key, role))
            crow.append((ep, key, pp["name"], role, None, "otrr", oeid, how))
            stats["credits_otrr_" + how] += 1

    # --- Goldin
    g_by_prog = collections.defaultdict(list)
    for r in goldin_rows:
        g_by_prog[(r.get("PROGNAME") or "").strip()].append(r)
    g_key = {}
    for prog, rs in g_by_prog.items():
        if not prog:
            continue
        radio = [r for r in rs if not parse_source(r.get("SOURCE"))[2]]
        dates = [d for d in (goldin_date(r.get("SDATE")) for r in radio) if d]
        keys, how, ev = smap.resolve([prog], dates)
        if keys:
            g_key[prog] = (keys, how)
            for k in keys:
                db.execute("INSERT INTO series_map VALUES (?,?,?,?,?,?)",
                           ("goldin", prog, None, k, how[k], json.dumps({**(ev or {}), "records": len(rs)})))
                stats["goldin_program_keys_" + how[k]] += 1
            stats["goldin_programs_mapped"] += 1
            stats["goldin_records_in_mapped_programs"] += len(rs)
        else:
            stats["goldin_programs_unmapped"] += 1

    g_title = collections.defaultdict(list)
    g_parsed = []
    for r in goldin_rows:
        prog = (r.get("PROGNAME") or "").strip()
        keys, how = g_key.get(prog, ((), None))
        net, dist, tv = parse_source(r.get("SOURCE"))
        date = goldin_date(r.get("SDATE"))
        dur, nominal = goldin_duration(r.get("DURATION"))
        rec = {"cat": r["CATALOGNUM"], "prog": prog, "k": keys[0] if keys else None, "how": None, "date": date,
               "net": net, "dist": dist, "tv": tv, "dur": dur, "nominal": nominal, "r": r, "ep": None, "ep_how": None}
        for k in keys if not tv else ():
            if date:
                t = by_sd.get((k, date), [])
                if t and not rec["ep"]:
                    rec["k"], rec["ep"], rec["ep_how"] = k, t[0], "series_date"
            else:
                g_title[(k, norm_title(r.get("TITLE")))].append(rec)
        if rec["k"]:
            rec["how"] = how[rec["k"]]
        g_parsed.append(rec)
    for (k, nt), rs in g_title.items():
        t = by_st.get((k, nt), [])
        if len(nt) >= 4 and len(rs) == 1 and len(t) == 1 and not rs[0]["ep"]:
            rs[0]["k"], rs[0]["ep"], rs[0]["ep_how"] = k, t[0], "series_title"
            rs[0]["how"] = g_key[rs[0]["prog"]][1][k]

    ep_network = {}
    ep_goldin = {}
    for rec in g_parsed:
        r = rec["r"]
        plot = (r.get("PLOT") or "").strip() or None
        title = (r.get("TITLE") or "").strip().strip('"') or None
        db.execute("INSERT INTO goldin_records VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", (
            rec["cat"], GOLDIN_URL.format(rec["cat"]), rec["prog"], rec["k"], rec["how"],
            rec["date"], r.get("SDATE") or None, title, r.get("PROGNUMB"),
            r.get("ARTIST") or None, (r.get("SOURCE") or "").strip() or None, rec["net"], rec["dist"], int(rec["tv"]),
            rec["dur"], rec["nominal"], r.get("DURATION") or None,
            (r.get("QUALITY") or "").split("|")[0] or None, r.get("COMPLETE") or None, r.get("SPONSOR") or None,
            plot, 0, GOLDIN_PROVENANCE.format(rec["cat"]) if plot else None,
            rec["ep"], rec["ep_how"]))
        stats["goldin_records"] += 1
        stats["goldin_tv_records"] += rec["tv"]
        if not rec["ep"]:
            continue
        ep = rec["ep"]
        stats["goldin_records_linked_" + rec["ep_how"]] += 1
        ep_goldin.setdefault(ep, rec["cat"])
        if rec["net"] and ep not in ep_network:
            ep_network[ep] = (rec["net"], "goldin:%d" % rec["cat"])
        for a in parse_artists(r.get("ARTIST")):
            key = people.goldin(a["name"])
            if (key, a["role"]) in credited[ep]:
                stats["goldin_credit_dupe_of_otrr"] += 1
                continue
            credited[ep].add((key, a["role"]))
            crow.append((ep, key, a["name"], a["role"], a["character"], "goldin", str(rec["cat"]), rec["ep_how"]))
            stats["credits_goldin"] += 1
            if ";" in a["name"]:
                stats["goldin_compound_names_unparsed"] += 1
    for ep, cat in ep_goldin.items():
        db.execute("UPDATE episodes SET goldin_cat = ? WHERE id = ?", (cat, ep))

    crow = collapse_character_roles(crow)
    db.executemany("INSERT INTO episode_credits VALUES (?,?,?,?,?,?,?,?)", crow)
    used = {c[1] for c in crow}
    for p in people.rows.values():
        if p["id"] not in used and not p["id"].startswith("otrr:"):
            continue
        db.execute("INSERT INTO people VALUES (?,?,?,?,?,?,?,?,?,?)", (
            p["id"], p["name"], json.dumps(sorted(x for x in p["names"] if x)), p["otrr_id"], p["goldin_name"],
            p["birth"], p["death"], p["birth_name"], p["birth_place"], json.dumps(sorted(p["sources"]))))
    stats["people"] = len(people.rows)

    # --- runs and sponsors (OTRRpedia), per series
    runs_by_key = collections.defaultdict(list)
    for idp, k in ((i, k) for i, ks in otrr_key.items() for k in ks):
        d = full.get(idp) or progs.get(idp) or {}
        src = "otrrpedia:programData" if idp in full else "otrrpedia:progPedia"
        spons = [s for s in d.get("sponsors") or [] if s.get("sponsor")]
        for s in spons:
            db.execute("INSERT INTO sponsors VALUES (?,?,?,?,?,?)", (
                k, idp, s["sponsor"], clean_date(s.get("begin")), clean_date(s.get("end")), src))
        for h in d.get("histories") or []:
            start, end = clean_date(h.get("begin")), clean_date(h.get("end"))
            over = sorted({s["sponsor"] for s in spons if clean_date(s.get("begin")) and start
                           and clean_date(s.get("begin")) <= (end or "9999") and (clean_date(s.get("end")) or "9999") >= start})
            length = int(h["length"]) if str(h.get("length") or "").isdigit() else None
            row = (k, idp, h.get("network") or None, h.get("country") or None, start, end,
                   h.get("dow") or None, h.get("time") or None, length, "; ".join(over) or None, src)
            db.execute("INSERT INTO program_runs VALUES (?,?,?,?,?,?,?,?,?,?,?)", row)
            runs_by_key[k].append(row)
            stats["program_runs"] += 1

    # --- episode network: Goldin's source first, else the OTRR run covering the date
    for eid, sk, d, _t in eps:
        if eid in ep_network or not d:
            continue
        for row in runs_by_key.get(sk, ()):
            if row[2] and row[4] and row[4] <= d <= (row[5] or row[4]):
                ep_network[eid] = (row[2], "otrr_history")
                break
    for ep, (net, src) in ep_network.items():
        db.execute("UPDATE episodes SET network = ?, network_source = ? WHERE id = ?", (net, src, ep))

    # --- per-series columns
    log_dates = collections.defaultdict(list)
    for r in otrr_logs:
        for k in otrr_key.get(r["idp"], ()) if r.get("date") else ():
            log_dates[k].append(r["date"])
    g_dates = collections.defaultdict(list)
    g_nets = collections.defaultdict(collections.Counter)
    for rec in g_parsed:
        if rec["k"] and not rec["tv"]:
            if rec["date"]:
                g_dates[rec["k"]].append(rec["date"])
            if rec["net"]:
                g_nets[rec["k"]][rec["net"]] += 1
    idps_by_key = collections.defaultdict(list)
    for idp, ks in otrr_key.items():
        for k in ks:
            idps_by_key[k].append(idp)
    for k in known:
        nets = collections.Counter()
        for row in runs_by_key.get(k, ()):
            if row[2]:
                nets[row[2]] += 1
        nets.update(g_nets.get(k, {}))
        if log_dates.get(k):
            span, how = (min(log_dates[k]), max(log_dates[k])), "otrr_log"
        elif g_dates.get(k):
            span, how = (min(g_dates[k]), max(g_dates[k])), "goldin"
        else:
            span, how = (None, None), None
        genres, spons = [], []
        for idp in sorted(idps_by_key.get(k, ()), key=int):
            p = progs.get(idp) or full.get(idp) or {}
            genres += [g["genre"] for g in p.get("genres") or [] if g.get("genre") and g["genre"] not in genres]
            spons += [s["sponsor"] for s in p.get("sponsors") or [] if s.get("sponsor") and s["sponsor"] not in spons]
        if not (nets or how or genres or idps_by_key.get(k)):
            continue
        db.execute("UPDATE series SET otrr_idp=?, networks=?, first_broadcast=?, last_broadcast=?, "
                   "broadcast_span_source=?, genres_otrr=?, sponsors_otrr=? WHERE key=?", (
                       ",".join(sorted(idps_by_key.get(k, ()), key=int)) or None,
                       json.dumps([n for n, _ in nets.most_common()]) if nets else None,
                       span[0], span[1], how, json.dumps(genres) if genres else None,
                       json.dumps(spons) if spons else None, k))
    db.executescript(INDEXES)
    return stats


def clean_date(v):
    v = (v or "").strip()
    if not re.match(r"^\d{4}-\d{2}-\d{2}$", v) or v.startswith("0000"):
        return None
    return v.replace("-00", "-01") if "-00" in v else v


def coverage(db):
    q = lambda s: db.execute(s).fetchone()[0]
    n = q("SELECT COUNT(*) FROM episodes")
    dated = q("SELECT COUNT(*) FROM episodes WHERE air_date IS NOT NULL")
    out = {
        "episodes": n, "episodes_dated": dated,
        "with_credits_before (build_db credits)": q("SELECT COUNT(DISTINCT episode_id) FROM credits"),
        "with_credits": q("SELECT COUNT(DISTINCT episode_id) FROM episode_credits"),
        "with_credits_otrr": q("SELECT COUNT(DISTINCT episode_id) FROM episode_credits WHERE source='otrr'"),
        "with_credits_goldin": q("SELECT COUNT(DISTINCT episode_id) FROM episode_credits WHERE source='goldin'"),
        "with_goldin_match": q("SELECT COUNT(*) FROM episodes WHERE goldin_cat IS NOT NULL"),
        "with_otrr_log_match": q("SELECT COUNT(*) FROM episodes WHERE otrr_eid IS NOT NULL"),
        "with_network": q("SELECT COUNT(*) FROM episodes WHERE network IS NOT NULL"),
        "with_plot_stored_not_displayable": q(
            "SELECT COUNT(DISTINCT episode_id) FROM goldin_records WHERE episode_id IS NOT NULL AND plot IS NOT NULL"),
        "playable_keep_episodes": q("SELECT COUNT(*) FROM episodes WHERE state LIKE 'keep%'"),
        "playable_keep_with_credits": q(
            "SELECT COUNT(*) FROM episodes WHERE state LIKE 'keep%' AND id IN (SELECT episode_id FROM episode_credits)"),
        "playable_keep_dated": q("SELECT COUNT(*) FROM episodes WHERE state LIKE 'keep%' AND air_date IS NOT NULL"),
        "playable_keep_dated_with_goldin": q(
            "SELECT COUNT(*) FROM episodes WHERE state LIKE 'keep%' AND air_date IS NOT NULL AND goldin_cat IS NOT NULL"),
        "series_with_network": q("SELECT COUNT(*) FROM series WHERE networks IS NOT NULL"),
        "series_with_genres_otrr": q("SELECT COUNT(*) FROM series WHERE genres_otrr IS NOT NULL"),
        "series_with_broadcast_span": q("SELECT COUNT(*) FROM series WHERE first_broadcast IS NOT NULL"),
        "people": q("SELECT COUNT(*) FROM people"),
        "people_with_birth": q("SELECT COUNT(*) FROM people WHERE birth IS NOT NULL"),
        "people_goldin_only": q("SELECT COUNT(*) FROM people WHERE id LIKE 'goldin:%'"),
        "episode_credits": q("SELECT COUNT(*) FROM episode_credits"),
        "goldin_records": q("SELECT COUNT(*) FROM goldin_records"),
        "goldin_records_linked": q("SELECT COUNT(*) FROM goldin_records WHERE episode_id IS NOT NULL"),
        "program_runs": q("SELECT COUNT(*) FROM program_runs"),
        "sponsors": q("SELECT COUNT(*) FROM sponsors"),
        "sponsors_dated": q("SELECT COUNT(*) FROM sponsors WHERE start IS NOT NULL"),
    }
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=os.path.join(ia.OUT, "radio-catalog.sqlite"))
    a = ap.parse_args()
    t0 = time.time()
    goldin = gz(os.path.join(ia.CACHE, "goldin", "records.json.gz"), [])
    logs = load_otrr_logs()
    progs, full, pedia_people, pdata = load_pedia()
    aliases = json.load(open(os.path.join(ia.EDITORIAL, "series_aliases.json")))
    if not goldin and not logs:
        raise SystemExit("no Goldin records and no OTRR logs cached: nothing to enrich with")
    tmp = a.db + ".enrich.tmp"
    mtime = os.path.getmtime(a.db)
    shutil.copyfile(a.db, tmp)
    db = sqlite3.connect(tmp)
    stats = enrich(db, goldin, logs, progs, full, pedia_people, pdata, aliases)
    cov = coverage(db)
    rep = {"inputs": {"goldin_records": len(goldin), "otrr_log_rows": len(logs), "progPedia": len(progs),
                      "programData": len(full), "peoplePedia": len(pedia_people), "personData": len(pdata)},
           "stats": dict(sorted(stats.items())), "coverage": cov,
           "built": datetime.datetime.now(datetime.timezone.utc).isoformat(), "seconds": round(time.time() - t0)}
    db.execute("INSERT OR REPLACE INTO meta VALUES (?,?)", ("enrich_report", json.dumps(rep)))
    db.commit()
    db.close()
    if os.path.getmtime(a.db) != mtime:
        os.remove(tmp)
        raise SystemExit("the database was rebuilt while enriching; run enrich_db.py again")
    os.replace(tmp, a.db)
    ia.write_json(os.path.join(ia.OUT, "enrich_report.json"), rep)
    print(json.dumps(rep, indent=1))
    if not cov["episode_credits"]:
        sys.exit(1)


if __name__ == "__main__":
    main()
