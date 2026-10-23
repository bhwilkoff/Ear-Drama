"""The served projection: the database every Ear Drama app reads (docs/CATALOG-CONTRACT.md §3).

    python3 tools/build_projection.py                 # out/radio-catalog.sqlite -> out/publish/
    python3 tools/build_projection.py --clean-only    # the public-web gate: keep_clean rows only
    python3 tools/build_projection.py --db PATH --out DIR
    python3 tools/build_projection.py --loudness .cache/loudness.json.gz   # fill loudness_i, loudness_tp
    python3 tools/build_projection.py --transcripts .cache/transcripts.json.gz   # FTS text, has_transcript

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
from titles import display_title
from measure_loudness import load as load_loudness, usable as loudness_usable
import fetch_transcripts as T
import transcript_gate as TG
from audit_audio_rights import pd_published_year

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
    networks TEXT, episodes INTEGER NOT NULL);
CREATE TABLE episodes (id TEXT PRIMARY KEY, series_key TEXT NOT NULL, air_date TEXT, date_source TEXT,
    season TEXT, num INTEGER, title TEXT, aka TEXT, length_s REAL, rights TEXT NOT NULL, rights_basis TEXT,
    no_recommend TEXT, network TEXT, network_source TEXT, has_transcript INTEGER NOT NULL DEFAULT 0,
    gain_db REAL, detail_json TEXT, loudness_i REAL, loudness_tp REAL, transcript_url TEXT);
CREATE TABLE recordings (episode_id TEXT NOT NULL, rank INTEGER NOT NULL, archive_id TEXT NOT NULL,
    url TEXT NOT NULL, format TEXT, kbps INTEGER, length_s REAL, variant TEXT,
    partial INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (episode_id, rank));
CREATE TABLE people (id TEXT PRIMARY KEY, name TEXT NOT NULL, birth TEXT, death TEXT);
CREATE TABLE credits (episode_id TEXT NOT NULL, person_id TEXT NOT NULL, role TEXT, character TEXT);
CREATE TABLE episode_aliases (old_id TEXT PRIMARY KEY, new_id TEXT NOT NULL);
-- Contentless: a match's rowid is the episode's rowid (join episodes ON rowid). Only the index
-- is stored, so the transcript column costs its postings, never its text. detail=column keeps
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


def build(src, dst, clean_only=False, loudness=None, transcripts=None):
    """`loudness` is the measurement cache (measure_loudness.py), id -> result; only
    a usable measurement of the episode's default copy URL is published.
    `transcripts` is the transcript cache (fetch_transcripts.py), id -> entry: a text
    of the default copy's own transcript is indexed for search whatever the gate says;
    `has_transcript` and `transcript_url` are set only where the gate passes."""
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

    names = {k: n for k, n in s.execute("SELECT key, name FROM series")}
    people_rows = {}
    credits_by_ep = {}
    for eid, pid, name, role, character in s.execute(
            "SELECT episode_id, person_id, name, role, character FROM episode_credits"):
        if eid in served:
            credits_by_ep.setdefault(eid, []).append((pid, name, role, character))
            people_rows.setdefault(pid, name)

    recs_by_ep = {}
    for row in s.execute("SELECT episode_id, rank, archive_id, file, format, kbps, length_s, variant, partial "
                         "FROM recordings ORDER BY episode_id, rank"):
        if row[0] in served:
            recs_by_ep.setdefault(row[0], []).append(row)

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
        searchable += text is not None
        for i, (_, _rank, aid, file, fmt, kbps, length, variant, partial) in enumerate(recs):
            d.execute("INSERT INTO recordings VALUES (?,?,?,?,?,?,?,?,?)",
                      (eid, i, aid, download_url(aid, file), fmt, kbps, length, variant, int(bool(partial))))
        credits = credits_by_ep.get(eid, [])
        for pid, _name, role, ch in credits:
            d.execute("INSERT INTO credits VALUES (?,?,?,?)", (eid, pid, role, ch))
        cur = d.execute("INSERT INTO episodes VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", (
            eid, sk, air, dsrc, season(air), num, display_title(title), aka, recs[0][6],
            "clean" if state == "keep_clean" else "unclaimed", rb, nr, net, nsrc, int(shown), None,
            None, lr and lr["I"], lr and lr["TP"], turl if shown else None))
        d.execute("INSERT INTO episodes_fts (rowid, title, series, people, transcript) VALUES (?,?,?,?,?)",
                  (cur.lastrowid, " ".join(dict.fromkeys(x for x in (display_title(title), title, aka) if x)),
                   names.get(sk, ""),
                   " ".join(n for _, n, _, _ in credits), text or ""))
        per_series[sk] = per_series.get(sk, 0) + 1

    for key, name, re_genre, otrr_genres, lv, first, last, nets in s.execute(
            "SELECT key, name, genre, genres_otrr, is_librivox, first_date, last_date, networks FROM series"):
        if key in per_series:
            genre, gsrc = genre_of(json.loads(otrr_genres) if otrr_genres else None, re_genre, bool(lv))
            d.execute("INSERT INTO series VALUES (?,?,?,?,?,?,?,?)",
                      (key, name, genre, gsrc, first, last, nets, per_series[key]))
    for pid, name, birth, death in s.execute("SELECT id, name, birth, death FROM people"):
        if pid in people_rows:
            d.execute("INSERT INTO people VALUES (?,?,?,?)", (pid, name, birth, death))

    d.executescript(INDEXES)
    counts = {t: d.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
              for t in ("episodes", "recordings", "series", "people", "credits")}
    counts["clean"] = d.execute("SELECT COUNT(*) FROM episodes WHERE rights = 'clean'").fetchone()[0]
    counts["loudness"] = d.execute("SELECT COUNT(*) FROM episodes WHERE loudness_i IS NOT NULL").fetchone()[0]
    counts["transcripts"] = d.execute("SELECT COUNT(*) FROM episodes WHERE has_transcript = 1").fetchone()[0]
    counts["transcriptsSearchable"] = searchable
    meta = {"schemaVersion": SCHEMA_VERSION, "generatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "cleanOnly": clean_only, "counts": counts, "rightsLines": RIGHTS_LINES}
    for k, v in meta.items():
        d.execute("INSERT INTO meta VALUES (?,?)", (k, json.dumps(v)))
    d.execute("INSERT INTO episodes_fts (episodes_fts) VALUES ('optimize')")   # one b-tree, before VACUUM
    d.commit()
    d.execute("VACUUM")
    d.close()
    return meta


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
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    db = os.path.join(a.out, "ear-drama.sqlite")
    if a.loudness and not os.path.exists(a.loudness):
        raise SystemExit(f"--loudness {a.loudness} does not exist (omit the flag to build without loudness)")
    if a.transcripts and not os.path.exists(a.transcripts):
        raise SystemExit(f"--transcripts {a.transcripts} does not exist (omit the flag to build without transcripts)")
    meta = build(a.db, db, a.clean_only, load_loudness(a.loudness) if a.loudness else None,
                 T.load(a.transcripts) if a.transcripts else None)
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
