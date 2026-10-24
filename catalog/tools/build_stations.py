"""Genre stations: one per genre, on one shared clock (R10; Decisions 058, 068;
docs/CATALOG-CONTRACT.md §8).

A station is a published schedule, never a client's shuffle: back-to-back slots
(UTC start, length, episode) built here and read by every client, so everyone
tuned to Mystery hears the same episode at the same moment. Each build keeps
every slot already published and appends after the last one until the window
reaches AHEAD past the build, so a schedule once published never changes (a
withdrawal, an episode no longer served, becomes a withheld slot of the same
length: the clock does not move).

The order is data, no text: a station plays its genre's served, recommendable,
complete episodes in the order they first aired (dated before undated; undated
by log number, so series interleave), continuing from its last published slot
and wrapping at the end. An episode already in the window is never scheduled
again, and a series that aired in the last MIX slots waits its turn (it is
passed over this cycle), so series mix.

    python3 tools/build_stations.py build --previous live/stations.json --out stations.json
    python3 tools/build_stations.py web --src stations.json --web out/web --out out/web/stations.json
    python3 tools/build_stations.py kept --old live/stations.json --new stations.json
    python3 tools/build_stations.py check --file stations.json
"""
import argparse
import datetime as dt
import json
import math
import os
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(__file__))
from genres import GENRES, NAMES  # noqa: E402
from shelves import MIN_SERIES, front_matter  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECTION = os.environ.get("EARDRAMA_PROJECTION", os.path.join(ROOT, "out", "publish", "ear-drama.sqlite"))
# The publish runs daily and its cron lands hours late; four days ahead survives
# three missed runs. The guard (`violations`) requires at least FLOOR ahead.
AHEAD = dt.timedelta(days=4)
FLOOR = dt.timedelta(days=3)
# A slot already over this long before the build leaves the file.
BEHIND = dt.timedelta(hours=1)
# A recording shorter than five minutes is a fragment or a promo, and one past
# ninety minutes a whole broadcast day or a book: neither is a station's slot.
MIN_S, MAX_S = 300, 5400
MIX = 6          # a series waits until this many other slots have aired
LOOKAHEAD = 500  # how far past its cursor a station looks for a slot it may air
FMT = "%Y-%m-%dT%H:%M:%SZ"
SLOT_KEYS = {"utc_start", "utc_end", "length_s", "episode", "withheld"}
EPISODE_KEYS = {"id", "series", "title"}


def iso(t):
    return t.strftime(FMT)


def parse(s):
    return dt.datetime.strptime(s, FMT).replace(tzinfo=dt.timezone.utc)


def order_key(e):
    """Broadcast order: dated by air date, then undated by log number, each then by
    series and id, so a station walks the genre's surviving broadcasts as they aired."""
    date, num = e["air_date"], e["num"]
    if date:
        return (0, date, "", e["series_key"], e["id"])
    return (1, "", f"{num if num is not None else 0:08d}", e["series_key"], e["id"])


def pools(db_path=PROJECTION):
    """Genre -> its station's episodes in broadcast order: served (the projection
    holds it), recommendable, its default copy complete and 5-90 minutes long, never
    a book's front matter, its series in that genre. Genres with fewer than
    MIN_SERIES series get no station (a station of one or two shows is a playlist)."""
    db = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    rows = db.execute(
        "SELECT e.id, e.series_key, s.name, e.title, e.air_date, e.num, e.length_s, s.genre "
        "FROM episodes e JOIN series s ON s.key = e.series_key "
        "JOIN recordings r ON r.episode_id = e.id AND r.rank = 0 "
        "WHERE e.no_recommend IS NULL AND s.genre IS NOT NULL AND r.partial = 0 "
        "AND e.length_s BETWEEN ? AND ?", (MIN_S, MAX_S)).fetchall()
    db.close()
    out = {}
    for eid, sk, sname, title, date, num, length, genre in rows:
        e = {"id": eid, "series_key": sk, "series": sname, "title": title, "air_date": date, "num": num,
             "length_s": int(math.ceil(length))}
        if front_matter((eid, sk, date, num, None, title)):
            continue
        out.setdefault(genre, []).append(e)
    for g in out:
        out[g].sort(key=order_key)
    return {g: out[g] for g in GENRES if len({e["series_key"] for e in out.get(g, ())}) >= MIN_SERIES}


def slot_of(start, e):
    end = start + dt.timedelta(seconds=e["length_s"])
    ep = {"id": e["id"], "series": e["series"]}
    if e.get("title"):
        ep["title"] = e["title"]
    return {"utc_start": iso(start), "utc_end": iso(end), "length_s": e["length_s"], "episode": ep}


def extend(slots, pool, until, start):
    """Append slots after the last one (or from `start`) until one ends at or past
    `until`. Returns the new list; stops short only when the pool has nothing left
    to air without a repeat inside the window."""
    slots = list(slots)
    if not pool:
        return slots
    by_id = {e["id"]: i for i, e in enumerate(pool)}
    series_of = {e["id"]: e["series_key"] for e in pool}
    in_window = {s["episode"]["id"] for s in slots if s.get("episode")}
    aired = [s for s in slots if s.get("episode")]
    # Continue after the latest aired episode still in the pool (one that left it
    # since has no place in the order any more).
    cursor = next((by_id[s["episode"]["id"]] for s in reversed(aired) if s["episode"]["id"] in by_id), -1)
    # A series waits for MIX others, or for every other series when a genre has fewer.
    mix = min(MIX, len(set(series_of.values())) - 1)
    recent = [series_of.get(s["episode"]["id"], s["episode"].get("series")) for s in aired[-mix:]] if mix else []
    t = parse(slots[-1]["utc_end"]) if slots else start
    while t < until:
        pick = None
        fallback = None
        for step in range(1, min(LOOKAHEAD, len(pool)) + 1):
            j = (cursor + step) % len(pool)
            e = pool[j]
            if e["id"] in in_window:
                continue
            if fallback is None:
                fallback = j
            if e["series_key"] not in recent:
                pick = j
                break
        if pick is None:
            pick = fallback
        if pick is None:
            break
        e = pool[pick]
        slots.append(slot_of(t, e))
        in_window.add(e["id"])
        recent = (recent + [e["series_key"]])[-mix:] if mix else []
        cursor = pick
        t = parse(slots[-1]["utc_end"])
    return slots


def withhold(slots, served):
    """A slot whose episode `served` refuses keeps its time and length and loses its
    episode (`withheld: true`): unclaimed recordings are removed on request, and the
    clock never moves for it."""
    out = []
    for s in slots:
        ep = s.get("episode")
        if ep and not served(ep["id"]):
            s = {k: v for k, v in s.items() if k != "episode"}
            s["withheld"] = True
        out.append(s)
    return out


def build(pool_by_genre, now, previous=None, served=None):
    """The stations file for a build at `now`: each published slot still running or
    ahead is kept as it is (withheld when no longer served); new slots follow until
    the window reaches `now + AHEAD`. A first publish starts on the hour."""
    old = {s["genre"]: s for s in (previous or {}).get("stations", [])}
    first = now.replace(minute=0, second=0, microsecond=0)
    stations = []
    for g in GENRES:
        pool = pool_by_genre.get(g)
        kept = [s for s in old.get(g, {}).get("slots", []) if parse(s["utc_end"]) > now - BEHIND]
        if served:
            kept = withhold(kept, served)
        if not pool and not kept:
            continue
        slots = extend(kept, pool or [], now + AHEAD, first)
        stations.append({"genre": g, "name": NAMES[g], "slots": slots})
    return {"schemaVersion": 1, "generatedAt": iso(now),
            "rule": "R10, Decisions 058 and 068: each genre's served, recommendable, complete episodes in the "
                    "order they first aired, back to back on one clock; no repeat in the window; series mix; "
                    "a published slot never changes",
            "stations": stations}


def violations(doc, served_ids=None, recommended_ids=None, now=None):
    """The guarantees over a published file: name -> offending items. `served_ids`
    and `recommended_ids` are the projection's own id sets (None skips that check);
    `now` defaults to the file's generatedAt."""
    bad = {}
    add = lambda k, v: bad.setdefault(k, []).append(v)
    if not isinstance(doc, dict) or not isinstance(doc.get("stations"), list) or not doc["stations"]:
        return {"stations is a non-empty list": [type(doc).__name__]}
    now = now or parse(doc["generatedAt"])
    seen = set()
    for st in doc["stations"]:
        g = st.get("genre")
        if g not in GENRES:
            add("every station is one of the eight genres", g)
        if g in seen:
            add("one station per genre", g)
        seen.add(g)
        if st.get("name") != NAMES.get(g):
            add("a station's name is its genre's name from data", st.get("name"))
        slots = st.get("slots") or []
        if not slots:
            add("a station is never empty", g)
            continue
        ids = []
        for i, s in enumerate(slots):
            if set(s) - SLOT_KEYS:
                add("a slot carries only its keys (no text)", (g, sorted(set(s) - SLOT_KEYS)))
            a, b = parse(s["utc_start"]), parse(s["utc_end"])
            if s.get("length_s") != int((b - a).total_seconds()) or s["length_s"] <= 0:
                add("a slot's length is its start to its end", (g, s["utc_start"]))
            if i and s["utc_start"] != slots[i - 1]["utc_end"]:
                add("no gap or overlap between slots", (g, slots[i - 1]["utc_end"], s["utc_start"]))
            ep = s.get("episode")
            if ep is None:
                if not s.get("withheld"):
                    add("a slot without an episode is withheld", (g, s["utc_start"]))
                continue
            if s.get("withheld"):
                add("a withheld slot carries no episode", (g, s["utc_start"]))
            if set(ep) - EPISODE_KEYS:
                add("an episode carries only id, series, title", (g, sorted(set(ep) - EPISODE_KEYS)))
            ids.append(ep["id"])
            if served_ids is not None and ep["id"] not in served_ids:
                add("every slot is served", (g, ep["id"]))
            elif recommended_ids is not None and ep["id"] not in recommended_ids:
                add("every slot is recommendable", (g, ep["id"]))
        dupes = sorted({i for i in ids if ids.count(i) > 1})
        if dupes:
            add("no episode repeats in a station's window", (g, dupes[:5]))
        if parse(slots[0]["utc_start"]) > now:
            add("a station is on the air at the build", (g, slots[0]["utc_start"]))
        if parse(slots[-1]["utc_end"]) < now + FLOOR:
            add(f"a station's window reaches {FLOOR.days} days ahead", (g, slots[-1]["utc_end"]))
    return bad


def changed(old, new):
    """Published slots (still running or ahead at the new build) the new file would
    change, beyond a withdrawal. Empty is the never-change rule holding."""
    now = parse(new["generatedAt"])
    by_genre = {s["genre"]: s["slots"] for s in new.get("stations", [])}
    bad = []
    for st in old.get("stations", []):
        keep = [s for s in st["slots"] if parse(s["utc_end"]) > now]
        got = {s["utc_start"]: s for s in by_genre.get(st["genre"], [])}
        for s in keep:
            w = got.get(s["utc_start"])
            if w is None or w["utc_end"] != s["utc_end"]:
                bad.append((st["genre"], s["utc_start"], "moved"))
            elif w.get("episode") and w["episode"]["id"] != (s.get("episode") or {}).get("id"):
                bad.append((st["genre"], s["utc_start"], "replaced"))
    return bad


def for_web(doc, web_dir):
    """The web's stations.json: the same schedules (one clock on every platform), each
    slot whose episode the web projection does not serve withheld; a station left with
    nothing to play is not offered. The public-web gate is applied once, upstream."""
    from build_web_projection import shard_of
    shards = {}

    def served(eid):
        k = shard_of(eid)
        if k not in shards:
            p = os.path.join(web_dir, "episodes", f"{k}.json")
            shards[k] = json.load(open(p)) if os.path.exists(p) else {}
        return eid in shards[k]
    stations = [dict(st, slots=withhold(st["slots"], served)) for st in doc["stations"]]
    return dict(doc, stations=[st for st in stations if any(s.get("episode") for s in st["slots"])])


def served_from(db_path):
    db = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    rec = {r[0] for r in db.execute("SELECT id FROM episodes WHERE no_recommend IS NULL")}
    db.close()
    return rec


def write(doc, path):
    with open(path, "w") as f:
        json.dump(doc, f, separators=(",", ":"))


def _now(s):
    return parse(s) if s else dt.datetime.now(dt.timezone.utc).replace(microsecond=0)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("build")
    a.add_argument("--now", default="", help="the build's instant, YYYY-MM-DDTHH:MM:SSZ (default: now)")
    a.add_argument("--previous", default="", help="the stations.json published now (missing = first publish)")
    a.add_argument("--out", required=True)
    a = sub.add_parser("web")
    a.add_argument("--src", required=True)
    a.add_argument("--web", required=True)
    a.add_argument("--out", required=True)
    a = sub.add_parser("kept")
    a.add_argument("--old", required=True)
    a.add_argument("--new", required=True)
    a = sub.add_parser("check")
    a.add_argument("--file", required=True)
    args = ap.parse_args()
    if args.cmd == "build":
        now = _now(args.now)
        old = json.load(open(args.previous)) if args.previous and os.path.exists(args.previous) else {}
        rec = served_from(PROJECTION)
        doc = build(pools(PROJECTION), now, old, served=lambda i: i in rec)
        bad = violations(doc, served_ids=rec, recommended_ids=rec, now=now)
        write(doc, args.out)
        kept = sum(1 for st in old.get("stations", []) for s in st["slots"] if parse(s["utc_end"]) > now - BEHIND)
        total = sum(len(st["slots"]) for st in doc["stations"])
        print(f"wrote {args.out}: {len(doc['stations'])} stations, {total} slots ({kept} kept as published), "
              f"through {min(st['slots'][-1]['utc_end'] for st in doc['stations']) if doc['stations'] else '-'}")
        for k, v in bad.items():
            print(f"VIOLATION {k}: {v[:5]}")
        return 1 if bad else 0
    if args.cmd == "web":
        doc = for_web(json.load(open(args.src)), args.web)
        write(doc, args.out)
        playable = sum(1 for st in doc["stations"] for s in st["slots"] if s.get("episode"))
        print("wrote", args.out, len(doc["stations"]), "stations,", playable, "slots the web serves")
        return 0
    if args.cmd == "kept":
        old = json.load(open(args.old)) if os.path.exists(args.old) else {}
        bad = changed(old, json.load(open(args.new)))
        print(f"published station slots changed: {len(bad)}" + (f"; {bad[:5]}" if bad else ""))
        return 1 if bad else 0
    if args.cmd == "check":
        bad = violations(json.load(open(args.file)))
        for k, v in bad.items():
            print(f"VIOLATION {k}: {v[:5]}")
        print("stations file holds" if not bad else f"{len(bad)} rules broken")
        return 1 if bad else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
