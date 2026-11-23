"""The tap tier's shows, picked per run from the published catalog (DESIGN-LOOP N12).

Owner, 2026-11-04: "It seems to me that it is running the same things over and over."
The XCUITest `Fixture` pinned X Minus One and Hopalong Cassidy, so every run walked the
same pages. Now each run picks, from the live catalog, one show of each shape the pages
must hold: a rich series (picture, about text, a long run), a bare one (no picture, no
about, a handful of episodes), one with words but no picture, one with a very long name,
a 25 to 35 minute episode for the player and queue, and a one to four minute episode for
the download and sleep tests. The picks are shape checks over the data, never names.

Reproducible: the run prints its seed, the catalog's generatedAt and every chosen id.
`--fixture-seed N` (or UITEST_FIXTURE_SEED=N) against the same catalog picks the same
shows; `--fixture '{"short": "..."}'` (or UITEST_FIXTURE=JSON) pins any field outright.

The tests read the choice from UITEST_FIXTURE, which xcodebuild forwards into the test
runner as TEST_RUNNER_UITEST_FIXTURE (apple/UITests/UITestSupport.swift `Fixture`).

    /usr/bin/python3 tools/uitest_fixture.py                # pick and print
    /usr/bin/python3 tools/uitest_fixture.py --seed 42      # the same picks again
"""
import argparse
import json
import os
import random
import re
import sqlite3
import sys
import time
import urllib.request
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import app_config  # noqa: E402

RELEASE_URL = "https://github.com/bhwilkoff/Ear-Drama/releases/download/catalog-latest/ear-drama.sqlite.zz"
CACHE = app_config.REPO / "build" / "uitest-fixture" / "catalog.sqlite"
MAX_AGE_S = 12 * 3600

# A title the tests can find by its words: letters, apostrophes and spaces only (no digits, which
# displayTitle may spell as a date), at least two words, unique in the catalog.
TITLE_RX = re.compile(r"^[A-Za-z][A-Za-z' ]{6,38}[A-Za-z]$")
NAME_RX = re.compile(r"^[A-Za-z][A-Za-z' &.-]{2,38}[A-Za-z.]$")

FIELDS = ("long", "longTitle", "series", "seriesName", "short", "shortTitle",
          "rich", "bare", "noPicture", "longName")


def fetch(dest=CACHE, url=RELEASE_URL, max_age=MAX_AGE_S):
    """The published catalog, inflated (raw DEFLATE), cached for `max_age` seconds."""
    if dest.exists() and time.time() - dest.stat().st_mtime < max_age:
        return dest
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(".part")
    d = zlib.decompressobj(-15)
    with urllib.request.urlopen(url, timeout=120) as r, tmp.open("wb") as o:
        while chunk := r.read(1 << 20):
            o.write(d.decompress(chunk))
        o.write(d.flush())
    tmp.replace(dest)
    return dest


def _episode_pool(db, lo, hi):
    rows = db.execute(
        """SELECT e.id, e.title, s.key, s.name FROM episodes e JOIN series s ON s.key = e.series_key
           WHERE e.length_s BETWEEN ? AND ? AND e.rights IN ('clean', 'unclaimed') AND e.no_recommend IS NULL
             AND e.air_date IS NOT NULL AND e.title IS NOT NULL AND s.episodes >= 10
             AND EXISTS (SELECT 1 FROM recordings r WHERE r.episode_id = e.id AND r.rank = 0 AND r.partial = 0
                         AND r.length_s BETWEEN e.length_s * 0.9 AND e.length_s * 1.1)
           ORDER BY e.id""", (lo, hi)).fetchall()
    out = []
    for eid, title, key, name in rows:
        if not (TITLE_RX.match(title) and " " in title and NAME_RX.match(name)):
            continue
        if title.lower() == name.lower() or name.lower() in title.lower():
            continue
        out.append((eid, title, key, name))
    return out


def _unique_title(db, title):
    return db.execute("SELECT COUNT(*) FROM episodes WHERE title = ?", (title,)).fetchone()[0] == 1


def _series_pool(db, where):
    return [r[0] for r in db.execute(f"SELECT key FROM series WHERE {where} ORDER BY key").fetchall()]


def pick(db_path, seed):
    db = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    rng = random.Random(seed)

    def choose_episode(lo, hi, avoid=()):
        pool = [p for p in _episode_pool(db, lo, hi) if p[2] not in avoid]
        rng.shuffle(pool)
        for p in pool:
            if _unique_title(db, p[1]):
                return p
        raise SystemExit(f"uitest_fixture: no episode of {lo}-{hi} s fits the shape checks")

    def choose_series(label, where, avoid):
        pool = [k for k in _series_pool(db, where) if k not in avoid]
        if not pool:
            raise SystemExit(f"uitest_fixture: no {label} series in the catalog")
        return rng.choice(pool)

    long_ = choose_episode(1500, 2100)
    short = choose_episode(60, 240, avoid={long_[2]})
    used = {long_[2], short[2]}
    rich = choose_series("rich", "picture IS NOT NULL AND about_text IS NOT NULL AND episodes >= 50", used)
    used.add(rich)
    bare = choose_series("bare", "picture IS NULL AND about_text IS NULL AND star IS NULL AND network IS NULL"
                                 " AND episodes BETWEEN 2 AND 6 AND length(name) BETWEEN 6 AND 30", used)
    used.add(bare)
    no_pic = choose_series("no-picture", "picture IS NULL AND about_text IS NOT NULL AND episodes >= 20", used)
    used.add(no_pic)
    long_name = choose_series("long-name", "length(name) >= 60", used)
    meta = dict(db.execute("SELECT key, value FROM meta WHERE key = 'generatedAt'").fetchall())
    db.close()
    return {
        "seed": seed,
        "catalog": json.loads(meta.get("generatedAt", '"?"')),
        "long": long_[0], "longTitle": long_[1], "series": long_[2], "seriesName": long_[3],
        "short": short[0], "shortTitle": short[1],
        "rich": rich, "bare": bare, "noPicture": no_pic, "longName": long_name,
    }


def resolve(seed=None, override=None, db_path=None, env=os.environ):
    """The run's fixture: seed from the argument, else UITEST_FIXTURE_SEED, else the clock; then any
    fields pinned by `override` or UITEST_FIXTURE (JSON) replace the picks."""
    if seed is None and env.get("UITEST_FIXTURE_SEED"):
        seed = int(env["UITEST_FIXTURE_SEED"])
    if seed is None:
        seed = int(time.time()) % 1_000_000
    fx = pick(db_path or fetch(), seed)
    pinned = json.loads(override) if override else json.loads(env.get("UITEST_FIXTURE") or "{}")
    unknown = set(pinned) - set(FIELDS)
    if unknown:
        raise SystemExit(f"uitest_fixture: unknown field(s) {sorted(unknown)}; known: {', '.join(FIELDS)}")
    fx.update(pinned)
    if pinned:
        fx["pinned"] = sorted(pinned)
    return fx


def describe(fx):
    return (f"seed={fx['seed']} catalog={fx['catalog']}"
            + (f" pinned={','.join(fx['pinned'])}" if fx.get("pinned") else "")
            + f"\n  long={fx['long']} ({fx['longTitle']!r}, series {fx['series']} {fx['seriesName']!r})"
            + f"\n  short={fx['short']} ({fx['shortTitle']!r})"
            + f"\n  rich={fx['rich']} bare={fx['bare']} noPicture={fx['noPicture']} longName={fx['longName']}"
            + f"\n  reproduce: --fixture-seed {fx['seed']} (same catalog) or UITEST_FIXTURE='"
            + json.dumps({k: fx[k] for k in FIELDS}) + "'")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--seed", type=int)
    ap.add_argument("--fixture", help="JSON of fields to pin")
    ap.add_argument("--catalog-db", help="an inflated catalog sqlite instead of the published one")
    a = ap.parse_args()
    fx = resolve(a.seed, a.fixture, a.catalog_db and Path(a.catalog_db))
    print(describe(fx))
    return 0


if __name__ == "__main__":
    sys.exit(main())
