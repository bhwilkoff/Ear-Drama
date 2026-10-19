"""Post-build: add external facts, art and date witnesses to out/radio-catalog.sqlite.

    python3 tools/enrich_external.py [--db out/radio-catalog.sqlite]

Run after build_db.py. It only ADDS tables (dropping and re-creating its own, so
a rerun is idempotent) and never changes a row build_db.py wrote:

  series_wikidata       one row per series matched to a Wikidata item, with the
                        evidence for the match and the item's facts
  episode_witnesses     one row per external dated mention of an episode
                        (Haendiges log line, Wikipedia episode-table row,
                        Wikidata episode item), joined to our episode when the
                        (series, date) exists
  episode_external      per-episode witness counts and title agreement
  external_disagreements  title disagreements on the same date, and the same
                        title on a different date in the same series
  art                   Commons files with the licence template that frees them,
                        tied to a series or a person where the file says so
  external_meta         counts written by this step

Inputs are the harvest_ext_*.py caches; a missing cache is reported, never read
as "no witnesses" (the meta row says which sources were absent).
Series names are keyed with tools/otr_parse.py norm_series, as build_db.py does.
"""
import argparse
import datetime
import gzip
import json
import os
import re
import sqlite3
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import otr_parse as P  # noqa: E402
from ia_lib import CACHE, EDITORIAL, OUT  # noqa: E402

PD_CLASSES = {"PD-US-no notice", "PD-US-not renewed", "PD-US-expired",
              "PD-US-no notice advertisement", "PD-US-defective notice", "PD-US-1978-89"}
RADIO_DRAMA = "Q2635894"      # mostly single plays; a weaker series signal
YEAR_SLACK = 2


def load(path, default=None):
    if not os.path.exists(path):
        return default
    op = gzip.open if path.endswith(".gz") else open
    with op(path, "rt", encoding="utf-8") as f:
        return json.load(f)


# ---------------------------------------------------------------- names

def strip_qualifier(name):
    return re.sub(r"\s*\((?:[^)]*\b(?:radio|program|programme|series|show|drama|serial)\b[^)]*)\)\s*$",
                  "", name or "", flags=re.I).strip()


def variants(name):
    """Normalized keys a name may appear under. Conservative: & / and, and a
    trailing radio qualifier; nothing that drops a content word."""
    if not name:
        return set()
    out = set()
    for n in {name, strip_qualifier(name)}:
        out.add(P.norm_series(n))
        out.add(P.norm_series(re.sub(r"\s*&\s*", " and ", n)))
        out.add(P.norm_series(re.sub(r"\s+and\s+", " & ", n, flags=re.I)))
    return {v for v in out if len(v) >= 3}


class SeriesIndex:
    def __init__(self, db):
        self.name = {}
        self.years = {}
        self.known = set()
        self.by = defaultdict(set)
        for key, name, first, last, eps, spine in db.execute(
                "SELECT key, name, first_date, last_date, episodes, in_spine FROM series"):
            self.name[key] = name
            self.years[key] = (_year(first), _year(last))
            if spine or (eps or 0) >= 5:
                self.known.add(key)
            for v in variants(name) | {key}:
                self.by[v].add(key)
        self.otrr = set()
        # OTRR alternate titles: every title of a program reaches its key
        pt = load(os.path.join(CACHE, "otrr", "pTitles.json"), [])
        groups = defaultdict(list)
        for r in pt:
            groups[r["idp"]].append(r["title"])
        ol = {r["idp"]: r for r in load(os.path.join(CACHE, "otrr", "otterlog.json"), [])}
        for idp, titles in groups.items():
            keys = set()
            for t in titles:
                keys |= {k for v in variants(t) for k in self.by.get(v, ())}
            if not keys:
                continue
            if idp in ol:
                self.otrr |= keys
                self.known |= keys
                lo, hi = _year(ol[idp].get("min")), _year(ol[idp].get("max"))
                for k in keys:
                    a, b = self.years.get(k, (None, None))
                    self.years[k] = (a or lo, b or hi)
            for t in titles:
                for v in variants(t):
                    self.by[v] |= keys
        for alias, target in (load(os.path.join(EDITORIAL, "series_aliases.json"), {}) or {}).items():
            if alias.startswith("_"):
                continue
            tk = {k for v in variants(target) for k in self.by.get(v, ())}
            self.by[P.norm_series(alias)] |= tk

    def lookup(self, name, known_only=True):
        keys = {k for v in variants(name) for k in self.by.get(v, ())}
        return {k for k in keys if k in self.known} if known_only else keys


def _year(s):
    if not s:
        return None
    m = re.match(r"(\d{4})", str(s))
    y = int(m.group(1)) if m else None
    return y if y and 1900 <= y <= 2030 else None


def nt(s):
    s = (s or "").lower()
    s = re.sub(r"\(.*?\)", " ", s)
    s = re.sub(r"^\s*(the|a|an)\s+", "", s)
    return re.sub(r"[^a-z0-9]", "", s)


def titles_agree(a, b):
    x, y = nt(a), nt(b)
    if not x or not y:
        return None
    if x == y or (min(len(x), len(y)) >= 5 and (x in y or y in x)):
        return 1
    ta = set(re.findall(r"[a-z0-9]+", (a or "").lower())) - {"the", "a", "an", "of", "and"}
    tb = set(re.findall(r"[a-z0-9]+", (b or "").lower())) - {"the", "a", "an", "of", "and"}
    if ta and tb and len(ta & tb) / len(ta | tb) >= 0.5:
        return 1
    return 0


# ---------------------------------------------------------------- Wikidata

def wd_years(it):
    ys = [_year(v) for k in ("start", "end", "inception", "dissolved", "published")
          for v in it["props"].get(k, [])]
    ys = [y for y in ys if y]
    return (min(ys), max(ys)) if ys else (None, None)


def radio_program_category(cat):
    """An enwiki category that holds radio PROGRAMS. The crawl also walks into
    franchise categories (Category:Lone Ranger -> Lone Ranger films, The Shadow
    magazine covers), whose members are not radio and must not vouch."""
    return bool(re.search(r"\bradio\b", cat, re.I)) and bool(re.search(
        r"programs|dramas|series|shows|serials|soap operas|comed|sitcoms", cat, re.I)) and not re.search(
        r"\b(television|films?|people|personalit|presenters|hosts|actors|actresses|stations|"
        r"networks?\b(?! (radio )?programs)|episodes|seasons|characters|novels|comics|magazines?)", cat, re.I)


def match_wikidata(idx, items, enwiki_radio):
    """Return ({key: (qid, evidence)}, rejected Counter, ambiguous list)."""
    american = {}
    for v in enwiki_radio.values():
        cats = [c for c in v.get("cats", []) if radio_program_category(c)]
        if v.get("qid") and cats:
            american.setdefault(v["qid"], []).extend(cats)
    cands = defaultdict(list)
    rejected = Counter()
    for q, it in items.items():
        rc = it.get("radio_class") or []
        strong = any(c != RADIO_DRAMA for c in rc)
        in_cat = q in american
        if not rc and not in_cat:
            rejected["not_radio"] += 1
            continue
        names = [("label", it.get("label"))] + [("alias", a) for a in it.get("aliases", [])]
        if it.get("enwiki"):
            names.append(("enwiki", it["enwiki"]))
        wy = wd_years(it)
        country = it["props"].get("country", [])
        for kind, nm in names:
            for key in idx.lookup(nm):
                oy = idx.years.get(key, (None, None))
                ev = {"qid": q, "name": nm, "name_kind": kind, "wd_years": list(wy), "our_years": list(oy),
                      "radio_class": rc, "enwiki_category": american.get(q, [])[:3],
                      "country": country}
                score = {"label": 2, "enwiki": 2, "alias": 1}[kind]
                score += 2 if strong else (1 if in_cat else 0)
                if wy[0] and oy[0]:
                    lo, hi = oy[0], oy[1] or oy[0]
                    if wy[0] <= hi + YEAR_SLACK and wy[1] >= lo - YEAR_SLACK:
                        ev["years"] = "overlap"
                        score += 3
                    else:
                        ev["years"] = "disagree"
                        rejected["years_disagree"] += 1
                        continue
                else:
                    ev["years"] = "unknown"
                    if not strong and not in_cat:
                        rejected["radio_drama_no_years"] += 1
                        continue
                    if kind == "alias" or not (in_cat or "Q30" in country):
                        rejected["weak_no_years"] += 1
                        continue
                if country and "Q30" not in country:
                    score -= 2
                elif "Q30" in country:
                    score += 1
                ev["score"] = score
                cands[key].append(ev)
    matched, ambiguous = {}, []
    for key, evs in cands.items():
        best = {}
        for e in evs:
            if e["qid"] not in best or e["score"] > best[e["qid"]]["score"]:
                best[e["qid"]] = e
        ranked = sorted(best.values(), key=lambda e: -e["score"])
        if len(ranked) > 1 and ranked[0]["score"] == ranked[1]["score"]:
            ambiguous.append({"key": key, "qids": [e["qid"] for e in ranked[:4]], "score": ranked[0]["score"]})
            continue
        matched[key] = ranked[0]
    return matched, rejected, ambiguous


# ---------------------------------------------------------------- tables

DDL = """
DROP TABLE IF EXISTS series_wikidata;
CREATE TABLE series_wikidata (
  series_key TEXT PRIMARY KEY, qid TEXT, label TEXT, enwiki TEXT,
  confidence INTEGER,            -- match score (title kind + radio class + years + country)
  match_evidence TEXT,           -- JSON: name matched, its kind, both year ranges, radio class, country
  broadcaster TEXT, production_company TEXT, genre TEXT,   -- JSON [{qid,label}]
  episodes_count INTEGER, start TEXT, end TEXT,
  cast TEXT, creators TEXT,      -- JSON [{qid,label,role}]
  external_ids TEXT,             -- JSON {property: [values]}
  musicbrainz_series TEXT, imdb TEXT, ia_ids TEXT,
  image TEXT, logo TEXT, commons_category TEXT,
  url TEXT                       -- https://www.wikidata.org/wiki/<qid>
);
DROP TABLE IF EXISTS episode_witnesses;
CREATE TABLE episode_witnesses (
  series_key TEXT, air_date TEXT, episode_id TEXT,   -- episode_id NULL when we hold no such (series, date)
  title TEXT, num TEXT, source TEXT, url TEXT,
  title_agrees INTEGER                               -- vs our title; NULL when either is missing
);
CREATE INDEX ew_ep ON episode_witnesses(episode_id);
CREATE INDEX ew_sd ON episode_witnesses(series_key, air_date);
DROP TABLE IF EXISTS episode_external;
CREATE TABLE episode_external (
  episode_id TEXT PRIMARY KEY, witnesses INTEGER, sources TEXT,
  title_agree INTEGER, title_disagree INTEGER
);
DROP TABLE IF EXISTS external_disagreements;
CREATE TABLE external_disagreements (
  kind TEXT,                     -- title (same series+date, different title) | date (same title, other date)
  series_key TEXT, episode_id TEXT, our_date TEXT, our_title TEXT,
  witness_date TEXT, witness_title TEXT, source TEXT, url TEXT
);
DROP TABLE IF EXISTS art;
CREATE TABLE art (
  file TEXT, series_key TEXT, person_qid TEXT, person TEXT,
  url TEXT, page TEXT, width INTEGER, height INTEGER, mime TEXT,
  license_template TEXT,         -- the PD template on the file page, or 'other:<licence>'
  usable INTEGER,                -- 1 when license_template is a PD-US class
  evidence_url TEXT,             -- the file page (template + description), plus credit links in found_via
  match_basis TEXT, found_via TEXT
);
CREATE INDEX art_series ON art(series_key);
DROP TABLE IF EXISTS external_meta;
CREATE TABLE external_meta (k TEXT PRIMARY KEY, v TEXT);
"""


def lab(labels, q):
    return {"qid": q, "label": labels.get(q)} if q and q[:1] == "Q" else {"value": q}


def write_wikidata(db, matched, items, labels):
    rows = []
    roles = [("creator", "creator"), ("author", "author"), ("screenwriter", "screenwriter"),
             ("director", "director"), ("producer", "producer"), ("composer", "composer"),
             ("presenter", "presenter")]
    for key, ev in matched.items():
        it = items[ev["qid"]]
        p = it["props"]
        x = it["external_ids"]
        creators = [{**lab(labels, q), "role": r} for prop, r in roles for q in p.get(prop, [])]
        cast = [lab(labels, q) for q in p.get("cast", []) + p.get("voice_actor", [])]
        eps = p.get("episodes", [])
        rows.append((
            key, ev["qid"], it.get("label"), it.get("enwiki"), ev["score"], json.dumps(ev),
            json.dumps([lab(labels, q) for q in p.get("broadcaster", [])]),
            json.dumps([lab(labels, q) for q in p.get("production_company", [])]),
            json.dumps([lab(labels, q) for q in p.get("genre", [])]),
            int(float(eps[0])) if eps else None,
            (p.get("start") or p.get("inception") or [None])[0], (p.get("end") or p.get("dissolved") or [None])[0],
            json.dumps(cast), json.dumps(creators), json.dumps(x),
            (x.get("P1407") or [None])[0], (x.get("P345") or [None])[0], json.dumps(x.get("P724", [])),
            (p.get("image") or [None])[0], (p.get("logo") or [None])[0], (p.get("commons_category") or [None])[0],
            f"https://www.wikidata.org/wiki/{ev['qid']}"))
    db.executemany("INSERT INTO series_wikidata VALUES (" + ",".join("?" * 22) + ")", rows)
    return len(rows)


def collect_witnesses(idx, matched):
    """Rows (key, date, title, num, source, url) from every external date source."""
    by_qid = defaultdict(set)
    for k, ev in matched.items():
        by_qid[ev["qid"]].add(k)
    out, absent, unmatched = [], [], Counter()
    hw = load(os.path.join(CACHE, "haendiges", "witnesses.json.gz"))
    if hw is None:
        absent.append("haendiges")
    else:
        cache = {}
        for r in hw:
            s = r["series"]
            if s not in cache:
                cache[s] = idx.lookup(s)
            if not cache[s]:
                unmatched["haendiges"] += 1
            for k in cache[s]:
                out.append((k, r["date"], r["title"], r.get("ep"), "haendiges", r["url"]))
    ww = load(os.path.join(CACHE, "wikipedia", "witnesses.json.gz"))
    if ww is None:
        absent.append("wikipedia")
    else:
        for r in ww:
            keys = set(by_qid.get(r.get("page_qid"), ())) or idx.lookup(r["series"])
            if not keys:
                unmatched["wikipedia"] += 1
            for k in keys:
                out.append((k, r["date"], r["title"], r.get("num"), "wikipedia", r["url"]))
    we = load(os.path.join(CACHE, "wikidata", "episodes.json.gz"))
    if we is None:
        absent.append("wikidata_episode")
    else:
        for q, it in we.items():
            dates = [d for d in it["props"].get("published", []) if re.fullmatch(r"\d{4}-\d{2}-\d{2}", d)]
            keys = {k for s in it["props"].get("series", []) for k in by_qid.get(s, ())}
            if not dates or not keys:
                unmatched["wikidata_episode"] += 1
                continue
            for k in keys:
                out.append((k, dates[0], it.get("label"), (it["props"].get("ordinal") or [None])[0],
                            "wikidata_episode", f"https://www.wikidata.org/wiki/{q}"))
    return out, absent, unmatched


def write_witnesses(db, rows):
    ours = {}
    by_series = defaultdict(list)
    for eid, key, date, title in db.execute(
            "SELECT id, series_key, air_date, title FROM episodes WHERE air_date IS NOT NULL"):
        ours[(key, date)] = (eid, title)
        by_series[key].append((date, title, eid))
    wrows, dis = [], []
    seen = set()
    for key, date, title, num, src, url in rows:
        k = (key, date, nt(title), src)
        if k in seen:
            continue
        seen.add(k)
        hit = ours.get((key, date))
        eid, ag = None, None
        if hit:
            eid = hit[0]
            ag = titles_agree(hit[1], title)
            if ag == 0:
                dis.append(("title", key, eid, date, hit[1], date, title, src, url))
        else:
            # the same title on another date in this series, within ~13 months
            wd = datetime.date.fromisoformat(date)
            for d2, t2, e2 in by_series.get(key, ()):
                if t2 and nt(t2) and nt(t2) == nt(title):
                    try:
                        gap = abs((datetime.date.fromisoformat(d2) - wd).days)
                    except ValueError:
                        continue
                    if 0 < gap <= 400:
                        dis.append(("date", key, e2, d2, t2, date, title, src, url))
                        break
        wrows.append((key, date, eid, title, num, src, url, ag))
    db.executemany("INSERT INTO episode_witnesses VALUES (?,?,?,?,?,?,?,?)", wrows)
    db.executemany("INSERT INTO external_disagreements VALUES (?,?,?,?,?,?,?,?,?)", dis)
    db.execute("""INSERT INTO episode_external
        SELECT episode_id, COUNT(*), GROUP_CONCAT(DISTINCT source),
               SUM(title_agrees = 1), SUM(title_agrees = 0)
        FROM episode_witnesses WHERE episode_id IS NOT NULL GROUP BY episode_id""")
    return len(wrows), len(dis)


def license_template(f):
    for t in f.get("templates", []):
        n = t.split(":", 1)[-1]
        if n in PD_CLASSES:
            return n
    return "other:" + (f.get("license_short") or "unknown")


def write_art(db, idx, matched, items, files, dlabels):
    qid_keys = defaultdict(set)
    p373 = defaultdict(set)
    for k, ev in matched.items():
        qid_keys[ev["qid"]].add(k)
        for c in items[ev["qid"]]["props"].get("commons_category", []):
            p373["Category:" + c].add(k)
    rows = []
    for title, f in files.items():
        if not f.get("url"):
            continue
        lt = license_template(f)
        links = []   # (series_key, person_qid, person, basis)
        for via in f.get("found_via", []):
            if via.startswith("wikidata:"):
                for k in qid_keys.get(via.split(":", 1)[1], ()):
                    links.append((k, None, None, "wikidata P18/P154"))
        for c in f.get("categories", []):
            for k in p373.get(c, ()):
                links.append((k, None, None, "Commons category is the series' P373"))
            nm = c.split(":", 1)[-1]
            if re.search(r"\((?:[^)]*\b)?radio\b[^)]*\)\s*$", nm, re.I):
                for k in idx.lookup(nm):
                    links.append((k, None, None, f"category {nm}"))
        for q in f.get("depicts", []):
            for k in qid_keys.get(q, ()):
                links.append((k, None, None, "depicts (P180) the series"))
            d = dlabels.get(q)
            if d and d.get("human"):
                links.append((None, q, d.get("label"), "depicts (P180) a person"))
        if not links:
            links = [(None, None, None, "none")]
        uniq = {}
        for k, pq, pn, basis in links:
            uniq.setdefault((k, pq), (pn, basis))
        evidence = f.get("page") or ("https://commons.wikimedia.org/wiki/" + title.replace(" ", "_"))
        for (k, pq), (pn, basis) in uniq.items():
            rows.append((title, k, pq, pn, f["url"], f.get("page"), f.get("width"), f.get("height"),
                         f.get("mime"), lt, int(lt in PD_CLASSES), evidence, basis,
                         json.dumps({"via": f.get("found_via", []), "credit_links": f.get("credit_links", [])})))
    db.executemany("INSERT INTO art VALUES (" + ",".join("?" * 14) + ")", rows)
    return len(rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=os.path.join(OUT, "radio-catalog.sqlite"))
    ap.add_argument("--report", default=os.path.join(OUT, "enrich_external_report.json"))
    a = ap.parse_args()
    db = sqlite3.connect(a.db)
    db.executescript(DDL)
    idx = SeriesIndex(db)
    wd = os.path.join(CACHE, "wikidata")
    items = load(os.path.join(wd, "items.json.gz"))
    absent = []
    if items is None:
        absent.append("wikidata")
        items = {}
    enw = load(os.path.join(wd, "enwiki_radio.json"), {})
    labels = load(os.path.join(wd, "labels.json.gz"), {})
    matched, rejected, ambiguous = match_wikidata(idx, items, enw)
    n_wd = write_wikidata(db, matched, items, labels)
    rows, ab2, unmatched = collect_witnesses(idx, matched)
    absent += ab2
    n_w, n_dis = write_witnesses(db, rows)
    files = load(os.path.join(CACHE, "commons", "files.json.gz"))
    if files is None:
        absent.append("commons")
        files = {}
    dl = load(os.path.join(CACHE, "commons", "depicts_labels.json"), {})
    n_art = write_art(db, idx, matched, items, files, dl)
    q = lambda s: db.execute(s).fetchone()[0]  # noqa: E731
    rep = {
        "date": datetime.date.today().isoformat(),
        "sources_absent": absent,
        "series_known": len(idx.known), "series_otrr_logged": len(idx.otrr),
        "series_with_qid": n_wd,
        "series_with_qid_otrr": len(set(matched) & idx.otrr),
        "series_with_qid_spine": q("SELECT COUNT(*) FROM series_wikidata w JOIN series s ON s.key=w.series_key WHERE s.in_spine=1"),
        "wikidata_items_considered": len(items), "wikidata_rejected": dict(rejected),
        "wikidata_ambiguous": len(ambiguous), "ambiguous_sample": ambiguous[:20],
        "witness_rows": n_w,
        "witness_rows_by_source": dict(db.execute("SELECT source, COUNT(*) FROM episode_witnesses GROUP BY 1").fetchall()),
        "witness_rows_joined": dict(db.execute("SELECT source, COUNT(*) FROM episode_witnesses WHERE episode_id IS NOT NULL GROUP BY 1").fetchall()),
        "witness_rows_unmatched_series": dict(unmatched),
        "episodes_with_witness": q("SELECT COUNT(*) FROM episode_external"),
        "episodes_dated": q("SELECT COUNT(*) FROM episodes WHERE air_date IS NOT NULL"),
        "episodes_with_2plus_sources": q("SELECT COUNT(*) FROM episode_external WHERE sources LIKE '%,%'"),
        "disagreements": dict(db.execute("SELECT kind, COUNT(*) FROM external_disagreements GROUP BY 1").fetchall()),
        "title_agree_rows": q("SELECT COUNT(*) FROM episode_witnesses WHERE title_agrees=1"),
        "title_disagree_rows": q("SELECT COUNT(*) FROM episode_witnesses WHERE title_agrees=0"),
        "witnessed_dates_we_lack": q("SELECT COUNT(*) FROM (SELECT DISTINCT series_key, air_date FROM episode_witnesses WHERE episode_id IS NULL)"),
        "art_rows": n_art,
        "art_files_by_license": dict(db.execute("SELECT license_template, COUNT(DISTINCT file) FROM art GROUP BY 1 ORDER BY 2 DESC").fetchall()),
        "art_usable_with_series": q("SELECT COUNT(DISTINCT file) FROM art WHERE usable=1 AND series_key IS NOT NULL"),
        "art_usable_series": q("SELECT COUNT(DISTINCT series_key) FROM art WHERE usable=1 AND series_key IS NOT NULL"),
        "art_usable_with_person": q("SELECT COUNT(DISTINCT file) FROM art WHERE usable=1 AND person_qid IS NOT NULL"),
    }
    db.executemany("INSERT INTO external_meta VALUES (?,?)", [(k, json.dumps(v)) for k, v in rep.items()])
    db.commit()
    with open(a.report, "w") as f:
        json.dump(rep, f, indent=1)
    print(json.dumps({k: v for k, v in rep.items() if k != "ambiguous_sample"}, indent=1))
    if absent and len(absent) >= 4:
        sys.exit(1)


if __name__ == "__main__":
    main()
