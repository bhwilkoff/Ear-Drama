"""Genre stations (tools/build_stations.py) against R10 and Decisions 058 and 068.

    python3 tests/test_stations.py
A fixture projection proves each rule, and every guard in `violations` and
`changed` is broken once and seen to fail. When the served projection exists
(PROJECTION, else out/publish/ear-drama.sqlite), a build over it is checked for
shape only: the catalog's contents are never pinned.
"""
import datetime as dt
import json
import os
import sqlite3
import sys
import shutil
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import build_stations as B  # noqa: E402
from forwarding import episode_forwards  # noqa: E402

ran = failed = 0


def check(name, got, want):
    global ran, failed
    ran += 1
    if got != want:
        failed += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


def fixture(path):
    d = sqlite3.connect(path)
    d.executescript("""
    CREATE TABLE series (key TEXT PRIMARY KEY, name TEXT, genre TEXT);
    CREATE TABLE episodes (id TEXT PRIMARY KEY, series_key TEXT, air_date TEXT, num INTEGER, length_s REAL,
        title TEXT, no_recommend TEXT);
    CREATE TABLE recordings (episode_id TEXT, rank INTEGER, partial INTEGER);
    """)
    series, eps, recs = [], [], []
    # Mystery: six series of forty half hours, a week apart, so the window (about
    # 200 slots) fills without a repeat. Western: four series, under MIN_SERIES.
    for genre, n in (("mystery", 6), ("western", 4)):
        for k in range(n):
            key = f"{genre}{k}"
            series.append((key, f"{genre.title()} Show {k}", genre))
            for i in range(40):
                date = (dt.date(1940, 1, 1) + dt.timedelta(days=7 * i + k)).isoformat()
                eid = f"{key}|{date}"
                eps.append((eid, key, date, None, 1790.4, f"Episode {i}", None))
                recs.append((eid, 0, 0))
    # What a station never airs: a never-recommended row, a partial default copy,
    # a fragment, a broadcast day, a cast list, and a series with no genre.
    odd = [("mystery0|1939-01-01", "mystery0", 1800, "Never", "fixture: never recommended", 0),
           ("mystery0|1939-01-02", "mystery0", 1800, "Partial", None, 1),
           ("mystery0|1939-01-03", "mystery0", 120, "Fragment", None, 0),
           ("mystery0|1939-01-04", "mystery0", 9000, "Broadcast day", None, 0),
           ("mystery0|1939-01-05", "mystery0", 1800, "Dramatis Personae", None, 0),
           ("nogenre|1939-01-06", "nogenre", 1800, "No genre", None, 0)]
    series.append(("nogenre", "No Genre", None))
    for eid, key, length, title, nr, partial in odd:
        eps.append((eid, key, eid.split("|")[1], None, length, title, nr))
        recs.append((eid, 0, partial))
    d.executemany("INSERT INTO series VALUES (?,?,?)", series)
    d.executemany("INSERT INTO episodes VALUES (?,?,?,?,?,?,?)", eps)
    d.executemany("INSERT INTO recordings VALUES (?,?,?)", recs)
    d.commit()
    d.close()
    return {e[0] for e in eps}, {e[0] for e in eps if e[6] is None}


tmp = tempfile.mkdtemp()
db = os.path.join(tmp, "p.sqlite")
served, recommended = fixture(db)
pool = B.pools(db)
NOW = B.parse("2026-10-24T18:20:00Z")

# --- the pool: served, recommendable, complete, a slot's length, by genre --------
check("only genres with MIN_SERIES series get a station", sorted(pool), ["mystery"])
ids = {e["id"] for e in pool["mystery"]}
for eid, why in (("mystery0|1939-01-01", "never recommended"), ("mystery0|1939-01-02", "a partial copy"),
                 ("mystery0|1939-01-03", "a fragment"), ("mystery0|1939-01-04", "a broadcast day"),
                 ("mystery0|1939-01-05", "front matter")):
    check(f"a station never airs {why}", eid in ids, False)
check("the pool is in broadcast order", [e["air_date"] for e in pool["mystery"]][:3],
      ["1940-01-01", "1940-01-02", "1940-01-03"])
check("a slot's length is whole seconds, rounded up", pool["mystery"][0]["length_s"], 1791)

# --- a first publish -------------------------------------------------------------
doc = B.build(pool, NOW)
check("a fixture build holds every guarantee", B.violations(doc, served, recommended), {})
st = doc["stations"][0]
check("a station is named from data", (st["genre"], st["name"]), ("mystery", "Mystery"))
check("a first publish starts on the hour", st["slots"][0]["utc_start"], "2026-10-24T18:00:00Z")
check("the window reaches AHEAD past the build", B.parse(st["slots"][-1]["utc_end"]) >= NOW + B.AHEAD, True)
series = [s["episode"]["id"].split("|")[0] for s in st["slots"]]
mix = min(B.MIX, 6 - 1)
check("series mix: none airs twice within MIX slots (or all others, when fewer)",
      [i for i in range(len(series)) if series[i] in series[max(0, i - mix):i]], [])
check("nothing in a slot but its keys", set().union(*(set(s) for s in st["slots"])) <= B.SLOT_KEYS, True)
check("the file is the same for the same inputs", json.dumps(B.build(pool, NOW)), json.dumps(doc))

# --- a rebuild keeps what was published ------------------------------------------
later = NOW + dt.timedelta(hours=26)
again = B.build(pool, later, previous=doc)
check("a rebuild holds every guarantee", B.violations(again, served, recommended), {})
check("a rebuild changes no published slot", B.changed(doc, again), [])
check("a rebuild drops slots over before the build", B.parse(again["stations"][0]["slots"][0]["utc_end"]) >
      later - B.BEHIND, True)
kept = [s for s in doc["stations"][0]["slots"] if B.parse(s["utc_end"]) > later - B.BEHIND]
check("a rebuild keeps every recent, running, and coming slot as published",
      again["stations"][0]["slots"][:len(kept)], kept)
running = [s for s in kept if B.parse(s["utc_end"]) > later]
check("a rebuild extends the window", B.parse(again["stations"][0]["slots"][-1]["utc_end"]) >= later + B.AHEAD,
      True)

# --- a withdrawal: the slot keeps its time, loses its episode --------------------
gone = running[2]["episode"]["id"]
w = B.build(pool, later, previous=doc, served=lambda i: i != gone)
ws = {s["utc_start"]: s for s in w["stations"][0]["slots"]}[running[2]["utc_start"]]
check("a withdrawn episode leaves a withheld slot of the same length",
      (ws.get("withheld"), "episode" in ws, ws["utc_end"]), (True, False, running[2]["utc_end"]))
check("a withdrawal is not a change", B.changed(doc, w), [])
check("a withheld slot holds every guarantee", B.violations(w, served, recommended), {})

# --- a moved id: the slot follows the alias (contract §3.5, §8) -------------------
airing = {s["episode"]["id"] for s in doc["stations"][0]["slots"] if s.get("episode")}
target = next(e for e in pool["mystery"] if e["id"] not in airing)
fwd = {gone: {"id": target["id"], "series": target["series"], "title": target["title"]}}
f = B.build(pool, later, previous=doc, served=lambda i: i != gone, forward=fwd)
fs = {s["utc_start"]: s for s in f["stations"][0]["slots"]}[running[2]["utc_start"]]
check("a moved id's slot follows its alias at the same instants",
      (fs["episode"]["id"], fs["utc_end"], fs.get("withheld")), (target["id"], running[2]["utc_end"], None))
check("following an alias is the one allowed change", B.changed(doc, f, fwd), [])
check("control: without the alias the same change is refused", [x[2] for x in B.changed(doc, f)], ["replaced"])
check("a followed slot holds every guarantee", B.violations(f, served, recommended), {})
t = B.build(pool, later, previous=doc, served=lambda i: i != gone, forward={})
check("a tombstoned id (no alias) stays a withheld gap",
      {s["utc_start"]: s for s in t["stations"][0]["slots"]}[running[2]["utc_start"]].get("withheld"), True)
other = next(e for e in pool["mystery"] if e["id"] not in airing and e["id"] != target["id"])
wrong = json.loads(json.dumps(f))
{s["utc_start"]: s for s in wrong["stations"][0]["slots"]}[running[2]["utc_start"]]["episode"]["id"] = other["id"]
check("broken: a slot rewritten to anything but its alias is refused", [x[2] for x in B.changed(doc, wrong, fwd)],
      ["replaced"])
dup = B.build(pool, later, previous=doc, served=lambda i: i != gone,
              forward={gone: {"id": running[3]["episode"]["id"], "series": "x"}})
check("an alias to an episode the station already airs leaves a withheld gap, not a repeat",
      ({s["utc_start"]: s for s in dup["stations"][0]["slots"]}[running[2]["utc_start"]].get("withheld"),
       B.violations(dup, served, recommended)), (True, {}))
fdb = os.path.join(tmp, "fwd.sqlite")
shutil.copy(db, fdb)
con = sqlite3.connect(fdb)
con.execute("CREATE TABLE episode_aliases (old_id TEXT PRIMARY KEY, new_id TEXT NOT NULL)")
con.execute("INSERT INTO episode_aliases VALUES ('mystery0|1900-01-01', ?)", (target["id"],))
con.execute("INSERT INTO episode_aliases VALUES ('mystery0|1900-01-02', 'mystery0|1939-01-01')")
con.commit()
con.close()
fw = episode_forwards(fdb)
check("the projection's aliases are read (only to a served, recommendable target)", sorted(fw),
      ["mystery0|1900-01-01"])
check("an alias carries the target's series name and title",
      fw["mystery0|1900-01-01"], {"id": target["id"], "series": target["series"], "title": target["title"]})
check("no projection, no aliases", episode_forwards(os.path.join(tmp, "absent.sqlite")), {})

import zlib  # noqa: E402
import subprocess  # noqa: E402
zz = fdb + ".zz"
with open(fdb, "rb") as f, open(zz, "wb") as o:
    c = zlib.compressobj(9, zlib.DEFLATED, -15)
    o.write(c.compress(f.read()) + c.flush())
check("(a) the publish job's deflated projection yields the same aliases as its sqlite",
      episode_forwards(zz), fw)

# The publish job holds only the .zz: `kept` on a re-attributed id follows the alias through it (case a),
# a withheld slot stays withheld and a refilled one is still refused (case b), a missing projection is refused.
old_ep = {"id": "mystery0|1900-01-01", "series": "Old", "title": "t"}
mk = lambda ep, **kw: {"schemaVersion": 1, "generatedAt": "2026-11-01T00:00:00Z", "stations": [{"genre": "mystery", "slots": [
    dict({"utc_start": "2026-11-02T00:00:00Z", "utc_end": "2026-11-02T00:30:00Z", "length_s": 1800}, **ep, **kw)]}]}
fo, fn, fb = (os.path.join(tmp, n) for n in ("kold.json", "knew.json", "kbad.json"))
json.dump(mk({"episode": old_ep}), open(fo, "w"))
json.dump(mk({"episode": {k: target[k] for k in ("id", "series", "title")}}), open(fn, "w"))
json.dump(mk({"episode": {"id": "mystery0|1939-01-01", "series": "x"}}), open(fb, "w"))
kept = lambda new, proj: subprocess.run([sys.executable, os.path.join(os.path.dirname(__file__), "..", "tools", "build_stations.py"), "kept", "--old", fo,
                                         "--new", new, "--projection", proj], capture_output=True, text=True)
check("(a) kept accepts a re-attributed id resolved through the .zz", kept(fn, zz).returncode, 0)
check("(b) kept refuses a slot refilled with a different recording", kept(fb, zz).returncode, 1)
check("kept refuses a missing projection instead of judging with no aliases",
      kept(fn, os.path.join(tmp, "absent.zz")).returncode, 1)

# --- every guard, broken once ----------------------------------------------------


def broken(mutate):
    d = json.loads(json.dumps(doc))
    mutate(d["stations"][0]["slots"], d)
    return sorted(B.violations(d, served, recommended))


def gap(sl, d):
    s = sl[5]
    s["utc_start"] = B.iso(B.parse(s["utc_start"]) + dt.timedelta(seconds=60))
    s["length_s"] -= 60


def overlap(sl, d):
    s = sl[5]
    s["utc_start"] = B.iso(B.parse(s["utc_start"]) - dt.timedelta(seconds=60))
    s["length_s"] += 60


def long_slot(sl, d):
    sl[5]["length_s"] += 1


check("broken: a gap between slots", broken(gap), ["no gap or overlap between slots"])
check("broken: an overlap", broken(overlap), ["no gap or overlap between slots"])
check("broken: a length that is not start to end", broken(long_slot), ["a slot's length is its start to its end"])
check("broken: an unserved episode", broken(lambda sl, d: sl[3]["episode"].update(id="ghost|1940-01-01")),
      ["every slot is served"])
check("broken: a never-recommended episode",
      broken(lambda sl, d: sl[3]["episode"].update(id="mystery0|1939-01-01")), ["every slot is recommendable"])
check("broken: a repeat in the window",
      broken(lambda sl, d: sl[9]["episode"].update(id=sl[2]["episode"]["id"])),
      ["no episode repeats in a station's window"])
check("broken: a window shorter than FLOOR", broken(lambda sl, d: d.update(
      generatedAt=B.iso(B.parse(sl[-1]["utc_end"]) - B.FLOOR + dt.timedelta(minutes=1)))),
      [f"a station's window reaches {B.FLOOR.days} days ahead"])
check("broken: a station not on the air at the build", broken(lambda sl, d: d.update(
      generatedAt=B.iso(B.parse(sl[0]["utc_start"]) - dt.timedelta(seconds=1)))),
      ["a station is on the air at the build"])
check("broken: free text on a slot", broken(lambda sl, d: sl[0].update(blurb="A classic")),
      ["a slot carries only its keys (no text)"])
check("broken: a name not from data", broken(lambda sl, d: d["stations"][0].update(name="Spooky FM")),
      ["a station's name is its genre's name from data"])
check("broken: an empty slot that is not withheld", broken(lambda sl, d: sl[4].pop("episode")),
      ["a slot without an episode is withheld"])
check("broken: no stations", sorted(B.violations({"stations": []})), ["stations is a non-empty list"])

moved = json.loads(json.dumps(again))
moved["stations"][0]["slots"][3]["episode"]["id"] = "mystery5|1940-09-01"
check("broken: a rebuild that replaces a published slot", [x[2] for x in B.changed(doc, moved)], ["replaced"])
shifted = json.loads(json.dumps(again))
shifted["stations"][0]["slots"][3]["utc_end"] = "2099-01-01T00:00:00Z"
check("broken: a rebuild that moves a published slot", [x[2] for x in B.changed(doc, shifted)], ["moved"])

# --- a pool too small for the window stops short, and the guard says so ----------
small = {"mystery": pool["mystery"][:50]}
short = B.build(small, NOW)
check("a pool too small never repeats to fill the window", sorted(B.violations(short, served, recommended)),
      [f"a station's window reaches {B.FLOOR.days} days ahead"])

# --- the real projection, shape only ---------------------------------------------
real = os.environ.get("PROJECTION") or os.path.join(os.path.dirname(__file__), "..", "out", "publish",
                                                    "ear-drama.sqlite")
if os.path.exists(real):
    rec = B.served_from(real)
    rdoc = B.build(B.pools(real), NOW, served=lambda i: i in rec)
    check("real: a build over the served projection holds every guarantee",
          B.violations(rdoc, served_ids=rec, recommended_ids=rec), {})
    check("real: every station is a genre", all(s["genre"] in B.GENRES for s in rdoc["stations"]), True)
    print(f"real: {len(rdoc['stations'])} stations, {sum(len(s['slots']) for s in rdoc['stations'])} slots")
else:
    print("real projection absent: shape check skipped")

print(f"{ran - failed} of {ran} passed")
sys.exit(1 if failed else 0)
