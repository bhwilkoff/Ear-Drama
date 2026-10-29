"""Forwarding ids: where an episode id that left the served catalog went (docs/CATALOG-CONTRACT.md §3.5).

    python3 tools/forwarding.py check-base --live live/manifest.json --built out/publish/manifest.json

A parse fix changes ids (catalog DECISIONS 014): an episode filed under a misread
date moves to its real one, or merges into the broadcast already there. Every
person's history, queue, download, and share link names the old id. So every
publish compares itself with the projection that is live (the previous one),
and each id that is no longer served gets either an alias, the served episode
that now holds its default copy, or a tombstone, when no served episode does.

Identity is the recording, never the title: archive.org item plus file name.
Aliases and tombstones are cumulative (the previous projection's are carried
forward), every chain collapses to its end, and an id served again sheds its
alias or tombstone.

Series keys forward the same way (follows, series links): a key that left gets an
alias to the served series now holding more than half of its recordings, or a
tombstone (forward_series).
"""
import argparse
import json
import os
import sqlite3
import sys
import tempfile
import urllib.parse
import zlib

TABLES = """
CREATE TABLE IF NOT EXISTS episode_aliases (old_id TEXT PRIMARY KEY, new_id TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS episode_tombstones (id TEXT PRIMARY KEY);
CREATE TABLE IF NOT EXISTS series_key_aliases (old_key TEXT PRIMARY KEY, new_key TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS series_key_tombstones (key TEXT PRIMARY KEY);
"""


def copy_key(archive_id, url):
    """A recording's identity: its archive.org item and file, read back from the served URL."""
    path = url.split("/download/", 1)[-1]
    file = path.split("/", 1)[1] if "/" in path else path
    return archive_id, urllib.parse.unquote(file)


def tables_of(con):
    return {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}


def series_copies(con):
    """Each served series' recordings: the distinct copy keys of every copy of every episode it serves."""
    out = {}
    for sk, aid, url in con.execute("SELECT e.series_key, r.archive_id, r.url FROM recordings r "
                                    "JOIN episodes e ON e.id = r.episode_id"):
        out.setdefault(sk, set()).add(copy_key(aid, url))
    return out


def read_projection(con):
    """What a projection says: its served ids, each one's copies in rank order, its aliases and tombstones,
    and the same for its series keys (`series`: served, copies, aliases, tombstones)."""
    names = tables_of(con)
    copies = {}
    for eid, aid, url in con.execute("SELECT episode_id, archive_id, url FROM recordings ORDER BY episode_id, rank"):
        copies.setdefault(eid, []).append(copy_key(aid, url))
    return {
        "series": {
            "served": {r[0] for r in con.execute("SELECT key FROM series")},
            "copies": series_copies(con),
            "aliases": dict(con.execute("SELECT old_key, new_key FROM series_key_aliases"))
            if "series_key_aliases" in names else {},
            "tombstones": {r[0] for r in con.execute("SELECT key FROM series_key_tombstones")}
            if "series_key_tombstones" in names else set(),
        },
        "served": {r[0] for r in con.execute("SELECT id FROM episodes")},
        "copies": copies,
        "aliases": dict(con.execute("SELECT old_id, new_id FROM episode_aliases")) if "episode_aliases" in names else {},
        "tombstones": {r[0] for r in con.execute("SELECT id FROM episode_tombstones")}
        if "episode_tombstones" in names else set(),
    }


def open_projection(path):
    """A projection as a dict (read_projection); a raw-DEFLATE `.zz` is inflated to a temp file first."""
    with tempfile.TemporaryDirectory() as tmp:
        if path.endswith(".zz"):
            dst = os.path.join(tmp, "previous.sqlite")
            d = zlib.decompressobj(-15)
            with open(path, "rb") as f, open(dst, "wb") as o:
                for chunk in iter(lambda: f.read(1 << 20), b""):
                    o.write(d.decompress(chunk))
                o.write(d.flush())
            path = dst
        con = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        try:
            return read_projection(con)
        finally:
            con.close()


def successor(old_copies, holders):
    """The served episode that now holds an id's recordings, or None.

    The default copy decides: the one episode holding it is the successor. When no
    served episode holds it, or several do, the episode holding the most of the id's
    copies (among those holders, if any) is, and a tie is no successor at all."""
    if not old_copies:
        return None
    first = holders.get(old_copies[0], set())
    if len(first) == 1:
        return next(iter(first))
    score = {}
    for k in old_copies:
        for e in holders.get(k, ()):
            if not first or e in first:
                score[e] = score.get(e, 0) + 1
    if not score:
        return None
    best = max(score.values())
    top = sorted(e for e, n in score.items() if n == best)
    return top[0] if len(top) == 1 else None


def carry(previous, served, fresh):
    """The forwarding a build publishes from the live one's and this build's fresh successors
    ({left id: successor or None}): (aliases, tombstones, report). Cumulative, every chain
    collapsed to its end, and an id served again sheds its alias or tombstone."""
    aliases, tombstones = {}, set()
    for o, n in fresh.items():
        if n is None:
            tombstones.add(o)
        else:
            aliases[o] = n
    returned = 0
    for o, n in previous["aliases"].items():
        if o in served:
            returned += 1
            continue
        end = n if n in served else fresh.get(n)
        if end is None:
            tombstones.add(o)
        else:
            aliases[o] = end
    for o in previous["tombstones"]:
        if o in served:
            returned += 1
        else:
            tombstones.add(o)
    report = {"left": len(fresh), "aliased": sum(1 for n in fresh.values() if n),
              "tombstoned": sum(1 for n in fresh.values() if n is None),
              "carriedAliases": sum(1 for o in previous["aliases"] if o in aliases),
              "carriedTombstones": sum(1 for o in previous["tombstones"] if o in tombstones) +
              sum(1 for o in previous["aliases"] if o in tombstones),
              "returned": returned}
    return aliases, tombstones, report


EMPTY_REPORT = {"left": 0, "aliased": 0, "tombstoned": 0, "carriedAliases": 0, "carriedTombstones": 0, "returned": 0}


def forward(previous, served, copies):
    """The aliases and tombstones this build publishes: (aliases {old: new}, tombstones set, report).

    `previous` is read_projection of the live projection (None on a first publish);
    `served` and `copies` are this build's."""
    if previous is None:
        return {}, set(), dict(EMPTY_REPORT)
    holders = {}
    for eid, keys in copies.items():
        for k in keys:
            holders.setdefault(k, set()).add(eid)
    fresh = {o: successor(previous["copies"].get(o, []), holders) for o in sorted(previous["served"] - served)}
    return carry(previous, served, fresh)


def series_successor(old_keys, holders):
    """The served series now holding more than half of a departed series' recordings, or None.

    The denominator is every recording the series served, so one mostly taken down is not
    forwarded on its remainder; a majority is never a tie (contract §3.5)."""
    if not old_keys:
        return None
    score = {}
    for k in old_keys:
        for s in holders.get(k, ()):
            score[s] = score.get(s, 0) + 1
    best = max(score, key=lambda s: (score[s], s), default=None)
    return best if best is not None and 2 * score[best] > len(old_keys) else None


def forward_series(previous, served, copies):
    """forward() for series keys: `previous` is read_projection's `series` part of the live
    projection (None on a first publish); `served` is this build's series keys and `copies`
    series_copies of it."""
    if previous is None:
        return {}, set(), dict(EMPTY_REPORT)
    holders = {}
    for sk, keys in copies.items():
        for k in keys:
            holders.setdefault(k, set()).add(sk)
    fresh = {o: series_successor(previous["copies"].get(o, set()), holders)
             for o in sorted(previous["served"] - served)}
    return carry(previous, served, fresh)


def inherit(source, served):
    """A narrower projection (clean-only) takes the served projection's forwarding: an alias
    whose target it does not serve is not its own (the id is simply not served here)."""
    return ({o: n for o, n in source["aliases"].items() if n in served and o not in served},
            {o for o in source["tombstones"] if o not in served})


def violations(aliases, tombstones, served):
    """What a published projection's forwarding must never hold (contract §3.5, each a guard)."""
    bad = []
    for o, n in sorted(aliases.items()):
        if o == n:
            bad.append(f"cycle: {o} forwards to itself")
        elif n in aliases:
            seen, cur = {o}, n
            while cur in aliases and cur not in seen:
                seen.add(cur)
                cur = aliases[cur]
            bad.append(f"{'cycle' if cur in seen else 'chain'}: {o} -> {n} -> {aliases[n]}")
        elif n not in served:
            bad.append(f"missing: {o} forwards to {n}, which is not served")
        if o in served:
            bad.append(f"served: {o} is served and also forwards to {n}")
        if o in tombstones:
            bad.append(f"both: {o} is aliased and tombstoned")
    for t in sorted(tombstones & served):
        bad.append(f"tombstone served: {t} is tombstoned and served again")
    return bad


def write(d, aliases, tombstones, series_aliases=None, series_tombstones=()):
    d.executescript(TABLES)
    d.executemany("INSERT INTO episode_aliases VALUES (?,?)", sorted(aliases.items()))
    d.executemany("INSERT INTO episode_tombstones VALUES (?)", [(t,) for t in sorted(tombstones)])
    d.executemany("INSERT INTO series_key_aliases VALUES (?,?)", sorted((series_aliases or {}).items()))
    d.executemany("INSERT INTO series_key_tombstones VALUES (?)", [(t,) for t in sorted(series_tombstones)])


def check_base(live_manifest, built_manifest):
    """The publish job, under the lock: the forwarding was computed against what is live NOW.
    Another publish landing between this run's build and its upload would leave the ids
    that publish retired unforwarded. Returns an error line, or None."""
    live = json.load(open(live_manifest)) if live_manifest and os.path.exists(live_manifest) else None
    built = json.load(open(built_manifest))
    base = (built.get("forwarding") or {}).get("base")
    want = ((live or {}).get("sha256") or {}).get("zz")
    if base != want:
        return (f"the forwarding was computed against {base or 'no previous catalog'}, but catalog-latest "
                f"now serves {want or 'nothing'}; re-run the publish")
    return None


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check-base")
    c.add_argument("--live", default="")
    c.add_argument("--built", required=True)
    a = ap.parse_args()
    if a.cmd == "check-base":
        err = check_base(a.live, a.built)
        if err:
            print(f"::error::{err}")
            return 1
        print("forwarding base matches what is live")
        return 0


if __name__ == "__main__":
    sys.exit(main())
