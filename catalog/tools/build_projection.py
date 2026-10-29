"""The served projection: the database every Ear Drama app reads (docs/CATALOG-CONTRACT.md §3).

    python3 tools/build_projection.py                 # out/radio-catalog.sqlite -> out/publish/
    python3 tools/build_projection.py --clean-only    # the public-web gate: keep_clean rows only
    python3 tools/build_projection.py --db PATH --out DIR
    python3 tools/build_projection.py --loudness .cache/loudness.json.gz   # fill loudness_i, loudness_tp
    python3 tools/build_projection.py --transcripts .cache/transcripts.json.gz   # FTS text, has_transcript
    python3 tools/build_projection.py --previous live/ear-drama.sqlite.zz   # forward the ids that left (§3.5)
    python3 tools/build_projection.py --clean-only --forwarding-from out/publish/ear-drama.sqlite

Reads the full research database (build_db.py, then enrich_db.py) and writes
`ear-drama.sqlite`, its raw-DEFLATE `ear-drama.sqlite.zz`, and `manifest.json`.
Only `keep_*` rows leave: a hidden row is never in a file a client can read.
Nothing here judges rights, ranks copies, or matches identity; it copies what
the pipeline decided (the contract's one rule).
"""
import argparse
import datetime
import hashlib
import json
import os
import sqlite3
import sys
import urllib.parse
import zlib

sys.path.insert(0, os.path.dirname(__file__))
import ia_lib as ia
from genres import genre_of
import shelves as SH
import sponsors as SP
from sort_name import sort_name
from titles import display_title
from measure_loudness import load as load_loudness, usable as loudness_usable
import fetch_transcripts as T
import transcript_gate as TG
import art_policy as AP
import episode_scripts as ES
from audit_audio_rights import pd_published_year
import arcs as ARCS
import forwarding as FW

SCHEMA_VERSION = 1
SERVED = ("keep_clean", "keep_unclaimed")
# The rights line every client shows (contract §5.5), published so no client types it.
def rights_lines(today=None):
    """The published lines; the published-age year moves every January with the
    rule that frees it (audit_audio_rights.pd_published_year)."""
    return {
        "unclaimed": "No rights claim known. Removed on request.",
        "rec_gov_work": "Government recording",
        "rec_librivox": "LibriVox recording",
        "rec_pd_published_age": f"Published before {pd_published_year(today) + 1}",
        "rec_cc_corroborated": "Creative Commons recording",
    }


RIGHTS_LINES = rights_lines()
# A refused projection is better than a shrunken one (Archive Watch Decision 020).
MIN_EPISODES = 10_000

SCHEMA = """
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
CREATE TABLE series (key TEXT PRIMARY KEY, name TEXT NOT NULL, genre TEXT, genre_source TEXT, first_date TEXT, last_date TEXT,
    networks TEXT, episodes INTEGER NOT NULL, star TEXT, sort_name TEXT NOT NULL, downloads INTEGER);
CREATE TABLE episodes (id TEXT PRIMARY KEY, series_key TEXT NOT NULL, air_date TEXT, date_source TEXT,
    season TEXT, num INTEGER, title TEXT, aka TEXT, length_s REAL, rights TEXT NOT NULL, rights_basis TEXT,
    no_recommend TEXT, network TEXT, network_source TEXT, has_transcript INTEGER NOT NULL DEFAULT 0,
    gain_db REAL, detail_json TEXT, loudness_i REAL, loudness_tp REAL, transcript_url TEXT, star TEXT,
    script TEXT, sponsor TEXT);
CREATE TABLE recordings (episode_id TEXT NOT NULL, rank INTEGER NOT NULL, archive_id TEXT NOT NULL,
    url TEXT NOT NULL, format TEXT, kbps INTEGER, length_s REAL, variant TEXT,
    partial INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (episode_id, rank));
CREATE TABLE people (id TEXT PRIMARY KEY, name TEXT NOT NULL, birth TEXT, death TEXT, portrait INTEGER);
-- Served images and their evidence (art_policy.py): url is Commons' Special:FilePath with no
-- width (a client appends ?width=); credit is the line a CC BY / BY-SA image must carry;
-- face ("x,y,w,h", normalized, top-left origin) is where a small crop centers (contract §3.3a).
CREATE TABLE art (id INTEGER PRIMARY KEY, url TEXT NOT NULL, width INTEGER, height INTEGER,
    license TEXT NOT NULL, author TEXT, credit TEXT, evidence_url TEXT NOT NULL, face TEXT);
CREATE TABLE credits (episode_id TEXT NOT NULL, person_id TEXT NOT NULL, role TEXT, character TEXT);
-- Forwarding ids (forwarding.py, contract §3.5): an id that left forwards to the served episode
-- now holding its default copy, or is tombstoned when none does; cumulative across publishes.
CREATE TABLE episode_aliases (old_id TEXT PRIMARY KEY, new_id TEXT NOT NULL);
CREATE TABLE episode_tombstones (id TEXT PRIMARY KEY);
-- Story arcs (arcs.py, contract §3.3): a serial plays to its arc's end and stops (Decision 067).
-- next_arc is the series' following arc whose first part is recommendable, offered, never started.
CREATE TABLE arcs (id TEXT PRIMARY KEY, series_key TEXT NOT NULL, title TEXT, parts INTEGER NOT NULL,
    method TEXT NOT NULL, next_arc TEXT);
CREATE TABLE arc_parts (episode_id TEXT PRIMARY KEY, arc_id TEXT NOT NULL, part INTEGER NOT NULL);
-- archive.org's own download count for each item a served recording comes from (contract §3.3);
-- an item whose count was never read is absent.
CREATE TABLE items (archive_id TEXT PRIMARY KEY, downloads INTEGER NOT NULL);
-- Contentless: a match's rowid is the episode's rowid (join episodes ON rowid). Only the index
-- is stored, so the transcript column costs its postings, never its text; only a transcript
-- past the gate is indexed (transcript_gate.py). detail=column keeps
-- word-prefix terms and column filters (every client query) and drops token positions, which
-- only phrase and NEAR queries use: measured 2026-10-22 on 233 transcripts, 2.1 KB compressed
-- each this way, 8.6 KB with positions (about 78 MB over the catalog), contract §3.4.
CREATE VIRTUAL TABLE episodes_fts USING fts5(title, series, people, transcript, content='', tokenize='unicode61',
    detail=column);
"""
INDEXES = """
CREATE INDEX episodes_series ON episodes (series_key, air_date);
CREATE INDEX episodes_date ON episodes (air_date);
CREATE INDEX credits_person ON credits (person_id);
CREATE INDEX credits_episode ON credits (episode_id);
CREATE INDEX arc_parts_arc ON arc_parts (arc_id, part);
"""


def season(air_date):
    """The broadcast season, '1949-50': a network season ran from the fall to the
    next summer, so September onward opens a season and January to August closes
    the one before. Summer replacements are told apart by their run, not here."""
    if not air_date:
        return None
    y, m = int(air_date[:4]), int(air_date[5:7])
    start = y if m >= 9 else y - 1
    return f"{start}-{(start + 1) % 100:02d}"


def download_url(archive_id, file):
    return "https://archive.org/download/{}/{}".format(urllib.parse.quote(archive_id, safe=""),
                                                       urllib.parse.quote(file, safe="/"))


def build(src, dst, clean_only=False, loudness=None, transcripts=None, scripts=None, previous=None,
          forwarding_from=None):
    """`loudness` is the measurement cache (measure_loudness.py), id -> result; only
    a usable measurement of the episode's default copy URL is published.
    `transcripts` is the transcript cache (fetch_transcripts.py), id -> entry: a text
    of the default copy's own transcript is indexed for search, and `has_transcript` and
    `transcript_url` set, only where the gate passes: what Search finds, Detail can show.
    `scripts` is the castable bundle (episode_scripts.load_bundle), id -> entry; None reads
    plays/castable-scripts.json. An episode's `script` is set only where episode_scripts links one.
    `previous` is forwarding.read_projection of the live projection: every id it served that
    this build does not is aliased or tombstoned (§3.5). `forwarding_from` is the same read of
    a wider projection built from the same database, whose forwarding a clean-only one takes."""
    loudness = loudness or {}
    transcripts = transcripts or {}
    if os.path.exists(dst):
        os.remove(dst)
    s = sqlite3.connect(f"file:{src}?mode=ro", uri=True)
    d = sqlite3.connect(dst)
    d.executescript(SCHEMA)
    states = ("keep_clean",) if clean_only else SERVED
    q = ",".join("?" * len(states))
    served = {r[0] for r in s.execute(f"SELECT id FROM episodes WHERE state IN ({q})", states)}
    script_of, script_report = ES.links(s, served, ES.load_bundle() if scripts is None else scripts)
    print(json.dumps({"episodeScripts": script_report}), file=sys.stderr)

    names = {k: n for k, n in s.execute("SELECT key, name FROM series")}
    people_rows = {}
    credits_by_ep = {}
    for eid, pid, name, role, character in s.execute(
            "SELECT episode_id, person_id, name, role, character FROM episode_credits"):
        if eid in served:
            credits_by_ep.setdefault(eid, []).append((pid, name, role, character))
            people_rows.setdefault(pid, name)

    portraits = served_portraits(s, people_rows)   # person id -> art row id, rows written to `art`
    for aid, (file, cls, template, author, w, h, face) in enumerate(portraits["rows"], 1):
        d.execute("INSERT INTO art VALUES (?,?,?,?,?,?,?,?,?)", (
            aid, AP.image_url(file), w, h, cls, author if AP.license_name(cls, template) else None,
            AP.credit(cls, template, author), AP.evidence_url(file), face))
    faces = set(portraits["by_person"])
    series_of = dict(s.execute("SELECT id, series_key FROM episodes"))
    credited_by_series = {}
    for eid, creds in credits_by_ep.items():
        credited_by_series.setdefault(series_of.get(eid), {})[eid] = [(p, r) for p, _n, r, _c in creds]
    stars = {sk: AP.series_star(eps, faces) for sk, eps in credited_by_series.items()}

    recs_by_ep = {}
    for row in s.execute("SELECT episode_id, rank, archive_id, file, format, kbps, length_s, variant, partial "
                         "FROM recordings ORDER BY episode_id, rank"):
        if row[0] in served:
            recs_by_ep.setdefault(row[0], []).append(row)

    sponsor_runs = SP.load(s)
    per_series = {}
    searchable = 0
    for (eid, sk, air, dsrc, num, title, aka, state, rb, wb, nr, net, nsrc) in s.execute(
            "SELECT id, series_key, air_date, date_source, num, title, aka, state, rec_bucket, work_bucket, "
            "no_recommend, network, network_source FROM episodes"):
        if eid not in served:
            continue
        recs = recs_by_ep.get(eid) or []
        if not recs:
            continue
        lr = loudness.get(eid)
        if not loudness_usable(lr, download_url(recs[0][2], recs[0][3])):
            lr = None
        turl = T.transcript_url(recs[0][2], recs[0][3])
        text = T.text_for(transcripts.get(eid), turl)
        shown = text is not None and TG.shown(text, recs[0][6])[0]
        searchable += shown
        for i, (_, _rank, aid, file, fmt, kbps, length, variant, partial) in enumerate(recs):
            d.execute("INSERT INTO recordings VALUES (?,?,?,?,?,?,?,?,?)",
                      (eid, i, aid, download_url(aid, file), fmt, kbps, length, variant, int(bool(partial))))
        credits = credits_by_ep.get(eid, [])
        for pid, _name, role, ch in credits:
            d.execute("INSERT INTO credits VALUES (?,?,?,?)", (eid, pid, role, ch))
        cur = d.execute("INSERT INTO episodes VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", (
            eid, sk, air, dsrc, season(air), num, display_title(title), aka, recs[0][6],
            "clean" if state == "keep_clean" else "unclaimed", rb, nr, net, nsrc, int(shown), None,
            None, lr and lr["I"], lr and lr["TP"], turl if shown else None,
            AP.episode_star([(p, r) for p, _n, r, _c in credits], faces, stars.get(sk)), script_of.get(eid), SP.sponsor_for(sponsor_runs, sk, air)))
        d.execute("INSERT INTO episodes_fts (rowid, title, series, people, transcript) VALUES (?,?,?,?,?)",
                  (cur.lastrowid, " ".join(dict.fromkeys(x for x in (display_title(title), title, aka) if x)),
                   names.get(sk, ""),
                   " ".join(n for _, n, _, _ in credits), text if shown else ""))
        per_series[sk] = per_series.get(sk, 0) + 1

    for key, name, re_genre, otrr_genres, lv, first, last, nets in s.execute(
            "SELECT key, name, genre, genres_otrr, is_librivox, first_date, last_date, networks FROM series"):
        if key in per_series:
            genre, gsrc = genre_of(json.loads(otrr_genres) if otrr_genres else None, re_genre, bool(lv))
            d.execute("INSERT INTO series VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                      (key, name, genre, gsrc, first, last, nets, per_series[key], stars.get(key), sort_name(name),
                       None))
    for pid, name, birth, death in s.execute("SELECT id, name, birth, death FROM people"):
        if pid in people_rows:
            d.execute("INSERT INTO people VALUES (?,?,?,?,?)",
                      (pid, name, birth, death, portraits["by_person"].get(pid)))

    try:
        counts_by_item = dict(s.execute("SELECT id, downloads FROM items WHERE downloads IS NOT NULL"))
    except sqlite3.OperationalError:  # a registry built before the column: no popularity shelf
        counts_by_item = {}
    used = {aid for (aid,) in d.execute("SELECT DISTINCT archive_id FROM recordings")}
    d.executemany("INSERT INTO items VALUES (?,?)",
                  sorted((a, n) for a, n in counts_by_item.items() if a in used and isinstance(n, int)))
    series_dl = SH.series_downloads(d.execute(
        "SELECT e.series_key, r.archive_id FROM episodes e JOIN recordings r ON r.episode_id = e.id AND r.rank = 0"),
        dict(d.execute("SELECT archive_id, downloads FROM items")))
    recommendable = {k for (k,) in d.execute("SELECT DISTINCT series_key FROM episodes WHERE no_recommend IS NULL")}
    d.executemany("UPDATE series SET downloads = ? WHERE key = ?",
                  [(n, k) for k, n in SH.browse_downloads(series_dl, recommendable).items()])
    write_arcs(d)
    fwd = write_forwarding(d, previous, forwarding_from)
    d.executescript(INDEXES)
    counts = {t: d.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
              for t in ("episodes", "recordings", "series", "people", "credits", "art", "arcs", "arc_parts")}
    counts["portraits"] = d.execute("SELECT COUNT(*) FROM people WHERE portrait IS NOT NULL").fetchone()[0]
    counts["seriesStars"] = d.execute("SELECT COUNT(*) FROM series WHERE star IS NOT NULL").fetchone()[0]
    counts["seriesDownloads"] = d.execute("SELECT COUNT(*) FROM series WHERE downloads IS NOT NULL").fetchone()[0]
    counts["episodeStars"] = d.execute("SELECT COUNT(*) FROM episodes WHERE star IS NOT NULL").fetchone()[0]
    counts["clean"] = d.execute("SELECT COUNT(*) FROM episodes WHERE rights = 'clean'").fetchone()[0]
    counts["loudness"] = d.execute("SELECT COUNT(*) FROM episodes WHERE loudness_i IS NOT NULL").fetchone()[0]
    counts["transcripts"] = d.execute("SELECT COUNT(*) FROM episodes WHERE has_transcript = 1").fetchone()[0]
    counts["transcriptsSearchable"] = searchable
    counts["scripts"] = d.execute("SELECT COUNT(*) FROM episodes WHERE script IS NOT NULL").fetchone()[0]
    counts["aliases"] = d.execute("SELECT COUNT(*) FROM episode_aliases").fetchone()[0]
    counts["tombstones"] = d.execute("SELECT COUNT(*) FROM episode_tombstones").fetchone()[0]
    meta = {"schemaVersion": SCHEMA_VERSION, "generatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "cleanOnly": clean_only, "counts": counts, "rightsLines": RIGHTS_LINES, "forwarding": fwd,
            "listenShelves": SH.listen_shelves(
                d.execute("SELECT id, series_key, air_date, num, no_recommend, title FROM episodes"),
                {k: (g, n) for k, g, n in d.execute("SELECT key, genre, episodes FROM series")},
                downloads=series_dl)}
    for k, v in meta.items():
        d.execute("INSERT INTO meta VALUES (?,?)", (k, json.dumps(v)))
    d.execute("INSERT INTO episodes_fts (episodes_fts) VALUES ('optimize')")   # one b-tree, before VACUUM
    d.commit()
    d.execute("VACUUM")
    d.close()
    return meta


def write_arcs(d):
    """Derive the story arcs over the episodes this projection serves (arcs.py) and write them."""
    rows = list(d.execute("SELECT id, series_key, air_date, title FROM episodes"))
    found, report = ARCS.derive(rows, dict(d.execute("SELECT key, name FROM series")))
    bad = ARCS.violations(found, {r[0]: (r[1], r[2]) for r in rows})
    if bad:
        raise SystemExit("refusing to publish arcs: " + "; ".join(bad[:5]))
    quiet = {eid for (eid,) in d.execute("SELECT id FROM episodes WHERE no_recommend IS NOT NULL")}
    nxt = ARCS.next_arcs(found, lambda first: first not in quiet)
    for a in found:
        d.execute("INSERT INTO arcs VALUES (?,?,?,?,?,?)",
                  (a["id"], a["series"], a["title"], len(a["parts"]), a["method"], nxt[a["id"]]))
        d.executemany("INSERT INTO arc_parts VALUES (?,?,?)",
                      [(eid, a["id"], i) for i, eid in enumerate(a["parts"], 1)])
    print(json.dumps({"arcs": {k: report[k] for k in report}}), file=sys.stderr)


def write_forwarding(d, previous, forwarding_from):
    """Write episode_aliases and episode_tombstones (forwarding.py), refusing a projection whose
    forwarding breaks a rule. Returns the manifest's `forwarding`: the base it was computed
    against (the previous projection's .zz sha256, null on a first publish) and the report."""
    served = {r[0] for r in d.execute("SELECT id FROM episodes")}
    if forwarding_from is not None:
        aliases, tombstones = FW.inherit(forwarding_from, served)
        report = {"inherited": True}
        base = forwarding_from.get("base")
    else:
        copies = {}
        for eid, aid, url in d.execute("SELECT episode_id, archive_id, url FROM recordings ORDER BY episode_id, rank"):
            copies.setdefault(eid, []).append(FW.copy_key(aid, url))
        aliases, tombstones, report = FW.forward(previous, served, copies)
        base = (previous or {}).get("base")
    bad = FW.violations(aliases, tombstones, served)
    if bad:
        raise SystemExit("refusing to publish forwarding ids: " + "; ".join(bad[:5]))
    FW.write(d, aliases, tombstones)
    print(json.dumps({"forwarding": report}), file=sys.stderr)
    return {"base": base, **report}


def served_portraits(s, people):
    """The portraits art_policy serves for the people this projection carries:
    {"rows": [(file, cls, template, author, width, height, face)], "by_person": {pid: art id}}.
    A source without the people tables (a fixture, an older build) serves none."""
    tables = {r[0] for r in s.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
    out = {"rows": [], "by_person": {}}
    if not {"people_art", "people_wikidata"} <= tables:
        return out
    dims = {}
    if "art" in tables:
        for f, w, h in s.execute("SELECT file, width, height FROM art WHERE width IS NOT NULL"):
            dims[f[5:] if f.startswith("File:") else f] = (w, h)
    # The portrait's own size (harvest_people_wikidata.py --phase dims) wins: a client lays a
    # face out by its shape before the image arrives.
    cols = {r[1] for r in s.execute("PRAGMA table_info(people_art)")}
    if "width" in cols:
        for f, w, h in s.execute("SELECT file, width, height FROM people_art WHERE width > 0 AND height > 0"):
            dims[f] = (w, h)
    # The face box (harvest_people_wikidata.py --phase faces) is the anchor of a small crop;
    # face_text drops one that does not lie inside the image.
    focus = ({f: AP.face_text(AP.face_list(t)) for f, t in
              s.execute("SELECT file, face FROM people_art WHERE face IS NOT NULL")} if "face" in cols else {})
    by_person = {}
    for pid, file, cls, usable, via, author, template, basis in s.execute(
            "SELECT a.person_id, a.file, a.license_class, a.usable, a.found_via, a.author, a.template, w.basis "
            "FROM people_art a JOIN people_wikidata w ON w.person_id = a.person_id"):
        if pid in people and AP.served(basis, cls, usable, via, author):
            by_person.setdefault(pid, []).append((file, cls, template, author))
    ids = {}
    for pid in sorted(by_person):
        file, cls, template, author = AP.pick(by_person[pid])
        if file not in ids:
            out["rows"].append((file, cls, template, author) + dims.get(file, (None, None)) + (focus.get(file),))
            ids[file] = len(out["rows"])
        out["by_person"][pid] = ids[file]
    return out


def deflate(src, dst):
    c = zlib.compressobj(9, zlib.DEFLATED, -15)
    with open(src, "rb") as f, open(dst, "wb") as o:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            o.write(c.compress(chunk))
        o.write(c.flush())


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=os.path.join(ia.OUT, "radio-catalog.sqlite"))
    ap.add_argument("--out", default=os.path.join(ia.OUT, "publish"))
    ap.add_argument("--clean-only", action="store_true")
    ap.add_argument("--loudness", help="measure_loudness.py cache (.json or .json.gz); absent = columns NULL")
    ap.add_argument("--transcripts", help="fetch_transcripts.py cache (.json.gz); absent = none searchable or shown")
    ap.add_argument("--previous", help="the live projection (.sqlite or .zz) whose ids this one forwards; absent = "
                                       "a first publish, nothing to forward")
    ap.add_argument("--forwarding-from", help="a projection built from the same database whose forwarding this one "
                                              "takes (the clean-only build takes the served one's)")
    a = ap.parse_args()
    for flag in ("previous", "forwarding_from"):
        if getattr(a, flag) and not os.path.exists(getattr(a, flag)):
            raise SystemExit(f"--{flag.replace('_', '-')} {getattr(a, flag)} does not exist")
    previous = forwarding_from = None
    if a.previous:
        previous = FW.open_projection(a.previous)
        previous["base"] = sha256(a.previous) if a.previous.endswith(".zz") else None
    if a.forwarding_from:
        forwarding_from = FW.open_projection(a.forwarding_from)
        with open(os.path.join(os.path.dirname(a.forwarding_from), "manifest.json")) as f:
            forwarding_from["base"] = (json.load(f).get("forwarding") or {}).get("base")
    os.makedirs(a.out, exist_ok=True)
    db = os.path.join(a.out, "ear-drama.sqlite")
    if a.loudness and not os.path.exists(a.loudness):
        raise SystemExit(f"--loudness {a.loudness} does not exist (omit the flag to build without loudness)")
    if a.transcripts and not os.path.exists(a.transcripts):
        raise SystemExit(f"--transcripts {a.transcripts} does not exist (omit the flag to build without transcripts)")
    meta = build(a.db, db, a.clean_only, load_loudness(a.loudness) if a.loudness else None,
                 T.load(a.transcripts) if a.transcripts else None, previous=previous,
                 forwarding_from=forwarding_from)
    floor = 1_000 if a.clean_only else MIN_EPISODES
    if meta["counts"]["episodes"] < floor:
        raise SystemExit(f"refusing to publish: {meta['counts']['episodes']} episodes is below the floor of {floor}")
    deflate(db, db + ".zz")
    meta["bytes"] = {"sqlite": os.path.getsize(db), "zz": os.path.getsize(db + ".zz")}
    meta["sha256"] = {"zz": sha256(db + ".zz")}
    ia.write_json(os.path.join(a.out, "manifest.json"), meta)
    print(json.dumps(meta, indent=1))


if __name__ == "__main__":
    main()
