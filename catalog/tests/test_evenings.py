"""Tonight in 19xx (tools/build_evenings.py) against rules R9 and R10 and Decision 058.

    python3 tests/test_evenings.py
A fixture catalog proves each rule and its broken control. When the cached Washington
Post log for 1947-10-16 and the served projection exist, the real CBS evening is
checked too.
"""
import datetime as dt
import os
import sqlite3
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import build_evenings as B

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
    CREATE TABLE series (key TEXT PRIMARY KEY, name TEXT, first_date TEXT, last_date TEXT);
    CREATE TABLE episodes (id TEXT PRIMARY KEY, series_key TEXT, air_date TEXT, network TEXT, length_s REAL,
        title TEXT, rights TEXT, no_recommend TEXT);
    """)
    d.executemany("INSERT INTO series VALUES (?,?,?,?)", [
        ("suspense", "Suspense", "1942-06-17", "1962-09-30"),
        ("mrkeentraceroflostpersons", "Mr. Keen, Tracer of Lost Persons", "1937-10-12", "1955-04-19"),
        ("aldrichfamily", "The Aldrich Family", "1939-07-02", "1953-04-19"),
        ("mancalledx", "The Man Called X", "1944-07-10", "1952-05-20"),
        ("speeches", "Speeches", "1933-01-01", "1945-12-31"),
        ("jackhaleythewondershow", "Jack Haley The Wonder Show", "1937-01-01", "1939-12-31")])
    d.executemany("INSERT INTO episodes VALUES (?,?,?,?,?,?,?,?)", [
        ("suspense|1947-10-09", "suspense", "1947-10-09", "CBS", 1790, "The Man Who Liked Dickens", "unclaimed", None),
        ("suspense|1947-10-16", "suspense", "1947-10-16", "CBS", 1772, "Self Defense", "unclaimed", None),
        ("mrkeentraceroflostpersons|1947-10-09", "mrkeentraceroflostpersons", "1947-10-09", "CBS", 1700, "A",
         "unclaimed", None),
        ("mrkeentraceroflostpersons|1947-10-23", "mrkeentraceroflostpersons", "1947-10-23", "CBS", 1700, "B",
         "unclaimed", None),
        ("aldrichfamily|1947-10-16", "aldrichfamily", "1947-10-16", "NBC", 1750, "Henry's Date", "unclaimed", None),
        ("mancalledx|1947-10-16", "mancalledx", "1947-10-16", "CBS", 1657, "Timber Country", "unclaimed",
         "fixture: never recommended"),
        ("jackhaleythewondershow|1938-10-14", "jackhaleythewondershow", "1938-10-14", None, 1750, "Pepe", "unclaimed",
         None),
    ])
    d.commit()
    d.close()


def slots(*rows):
    out = []
    for start, end, text in rows:
        h, m = (int(x) for x in start.split(":"))
        h2, m2 = (int(x) for x in end.split(":"))
        out.append({"start": h * 60 + m, "end": h2 * 60 + m2, "printed": text})
    return out


tmp = tempfile.mkdtemp()
db = os.path.join(tmp, "p.sqlite")
fixture(db)
cat = B.Catalog(db, registry=None)

CBS_1016 = slots(("20:00", "20:30", "Band:Suspense"), ("20:30", "21:00", "Mr. Keen, Tracer of Lost Persons"),
                 ("21:00", "21:30", "Dick Haymes"), ("22:30", "23:00", "Man Called X"))

# --- R9: a historical evening plays only what aired that night ---------------------
ev = B.match_slots(CBS_1016, "1947-10-16", "CBS", cat)
check("R9: the slot whose program survives that night plays it", ev[0].get("episode", {}).get("id"),
      "suspense|1947-10-16")
check("R9: Mr. Keen survives on 10-09 and 10-23, not 10-16: a stated gap", (ev[1].get("gap"), ev[1].get("episode")),
      (True, None))
check("R9: every filled slot's episode aired on the evening's own date",
      {s["episode"]["id"].split("|")[1] for s in ev if s.get("episode")}, {"1947-10-16"})
check("R9: a program with no recording that night is a gap", ev[2].get("gap"), True)
check("contract §9.4: a never-recommended episode is a gap, never in an evening", ev[3].get("gap"), True)

ev9 = B.match_slots(CBS_1016, "1947-10-09", "CBS", cat)
check("own date only: the same grid on 10-09 plays 10-09's episodes",
      [s.get("episode", {}).get("id") for s in ev9[:2]],
      ["suspense|1947-10-09", "mrkeentraceroflostpersons|1947-10-09"])

# control: a candidate query that forgets the date must be caught at the point of use
real_on = cat.episodes_on
cat.episodes_on = lambda date: [dict(zip(("id", "series_key", "series", "network", "length_s", "title", "rights",
                                          "no_recommend"), r)) for r in cat.db.execute(
    "SELECT e.id, e.series_key, s.name, e.network, e.length_s, e.title, e.rights, e.no_recommend "
    "FROM episodes e JOIN series s ON s.key = e.series_key WHERE e.id LIKE 'mrkeen%'")]
try:
    B.match_slots(CBS_1016, "1947-10-16", "CBS", cat)
    caught = False
except AssertionError:
    caught = True
cat.episodes_on = real_on
check("control: another date's episode reaching a slot is refused (the R9 guard fires)", caught, True)

# network: the episode is recorded as NBC's that night, so it cannot fill CBS's grid
nbc = slots(("20:00", "20:30", "Aldrich Family"))
check("network: an NBC broadcast never fills a CBS slot", B.match_slots(nbc, "1947-10-16", "CBS", cat)[0].get("gap"),
      True)
check("control: the same text on NBC plays", B.match_slots(nbc, "1947-10-16", "NBC", cat)[0].get("episode", {}).get("id"),
      "aldrichfamily|1947-10-16")

# wrapped names and short names
wrap = slots(("20:30", "20:45", "Mr. Keen, Tracer of"), ("20:45", "21:00", "Lost Persons"))
w = B.match_slots(wrap, "1947-10-09", "CBS", cat)
check("a name wrapped over two rows is one slot", [(B.hhmm(s["start"]), B.hhmm(s["end"])) for s in w],
      [("20:30", "21:00")])
check("short name: a few letters in order are not a name", B.name_score("Suspense", "Sus pen"), 0.0)
check("control: the whole short name is", B.name_score("Suspense", "Band:Suspense"), 1.0)
check("a recording's length absorbs a stray fragment in its half hour",
      [(B.hhmm(s["start"]), B.hhmm(s["end"])) for s in
       B.match_slots(slots(("20:00", "20:15", "Suspense"), ("20:15", "20:30", "Lowe")), "1947-10-16", "CBS", cat)],
      [("20:00", "20:30")])
check("control: a fragment beyond the recording's length stays its own gap",
      len(B.match_slots(slots(("20:00", "20:30", "Suspense"), ("20:30", "20:45", "Lowe")), "1947-10-16", "CBS", cat)), 2)

# a name the OCR read into two columns at once is not given to the weaker reading
wrc = {"call": "WRC", "slots": slots(("19:30", "20:00", "Jack Haley Wondr Shw"))}
wjsv = {"call": "WJSV", "slots": slots(("19:30", "20:00", "Jack Haley's Wonder Show"))}
got = B.refuse_bleed(B.match_slots(wrc["slots"], "1938-10-14", "NBC", cat), wrc, [wrc, wjsv], "NBC", cat)
check("bleed: the column that reads the name better keeps it; this one is a gap", (got[0].get("gap"), "refused" in got[0]),
      (True, True))
got = B.refuse_bleed(B.match_slots(wjsv["slots"], "1938-10-14", "CBS", cat), wjsv, [wrc, wjsv], "CBS", cat)
check("control: the better reading keeps its episode", got[0].get("episode", {}).get("id"), "jackhaleythewondershow|1938-10-14")
tie = {"call": "WRC", "slots": slots(("19:30", "20:00", "Jack Haley's Wonder Show"))}
got = B.refuse_bleed(B.match_slots(tie["slots"], "1938-10-14", "NBC", cat), tie, [tie, wjsv], "NBC", cat)
check("bleed: an equal reading in two columns, network unknown: a gap, not a guess", got[0].get("gap"), True)

# coverage is the share of 7-11 PM Eastern minutes with a surviving episode
check("coverage: one half hour of four hours", B.coverage(ev), 30 / 240)

# --- R10: times are Eastern, the zone is stated, one clock -----------------------
check("R10: an October evening replays at 8 PM Eastern = 00:00 UTC (EDT)",
      B.to_utc(dt.date(2026, 10, 22), "20:00"), "2026-10-23T00:00:00Z")
check("R10: after the clocks change it is 01:00 UTC (EST)", B.to_utc(dt.date(2026, 11, 2), "20:00"),
      "2026-11-03T01:00:00Z")
check("control: the zone is America/New_York, not UTC", B.ZONE, "America/New_York")
check("R10: a quarter past midnight belongs to the same night", B.to_utc(dt.date(2026, 10, 22), "00:15"),
      "2026-10-23T04:15:00Z")

# --- the grid parser on a synthetic Washington page -------------------------------
def page(with_hours=True):
    words = [[90, 50, 110, 58, "WRC"], [190, 50, 215, 58, "WTOP"], [290, 50, 315, 58, "WMAL"]]
    cells = {("WTOP", "20:00"): "Suspense", ("WTOP", "20:15"): '"', ("WTOP", "20:30"): "Mr. Keen",
             ("WRC", "20:00"): "Aldrich Family"}
    x = {"WRC": 80, "WTOP": 180, "WMAL": 280}
    for i in range(64):  # 9:00 AM to 12:45 AM, a row every 9 points
        t = 9 * 60 + 15 * i
        y = 100 + 9 * i
        hh, mm = t // 60 % 12 or 12, t % 60
        label = f"{hh}:{mm:02d}" if (with_hours and mm == 0) else f":{mm:02d}"
        words.append([20, y, 40, y + 7, label])
        for call in ("WRC", "WTOP", "WMAL"):
            text = cells.get((call, B.hhmm(t)), "News" if mm == 0 else "Music")
            if (call, B.hhmm(t)) not in cells and call == "WTOP" and t >= 20 * 60 and t < 21 * 60:
                text = '"'
            words.append([x[call], y, x[call] + 40, y + 7, text])
    return words


g, err = B.parse_grid(page(), "1947-10-16")
check("grid: parses", err, None)
st = {s["call"]: s for s in g["stations"]}
check("grid: the station stands for its network", (st["WTOP"]["network"], st["WRC"]["network"]), ("CBS", "NBC"))
sus = [s for s in st["WTOP"]["slots"] if s["printed"] == "Suspense"][0]
check("grid: ditto marks continue the program above (Eastern clock)", (B.hhmm(sus["start"]), B.hhmm(sus["end"])),
      ("20:00", "20:30"))
check("grid: a readable page covers prime time", (g["readable"], g["prime_rows"]), (True, 16))
check("control: a page with no printed hour is refused, not guessed", B.parse_grid(page(False), "1947-10-16")[1],
      "no printed hour")

# --- Decision 058: which evening tonight plays ------------------------------------
def rec(date, cov, readable=True, net="CBS"):
    return {"date": date, "network": net, "station": "WTOP", "coverage": cov, "readable": readable,
            "witness": {"paper": "Washington Post"},
            "slots": [{"et_start": "20:00", "et_end": "20:30", "length_min": 30, "printed": "Suspense",
                       "episode": {"id": f"suspense|{date}"}}]}


m = {("1947-10-23", "CBS"): rec("1947-10-23", 0.6), ("1952-10-23", "CBS"): rec("1952-10-23", 0.2),
     ("1948-10-21", "CBS"): rec("1948-10-21", 0.9), ("1950-10-23", "CBS"): rec("1950-10-23", 0.95, readable=False)}
day = dt.date(2026, 10, 23)  # a Friday; 1947-10-23 was a Thursday, 1948-10-21 a Thursday
check("058: the anniversary in its best-surviving year when it clears the floor",
      [x["date"] if isinstance(x, dict) else x for x in B.pick_tonight(day, m, 0.5)], ["1947-10-23", "anniversary"])
fri = dt.date(2026, 10, 22)  # Thursday; no 10-22 anniversary measured
m2 = dict(m)
m2[("1949-10-22", "CBS")] = rec("1949-10-22", 0.1)
check("058: below the floor, the best evening for today's weekday",
      [x["date"] if isinstance(x, dict) else x for x in B.pick_tonight(fri, m2, 0.5)], ["1948-10-21", "weekday"])
check("control: an unreadable page is never offered, however high it scores",
      B.pick_tonight(dt.date(2026, 10, 23), {("1950-10-23", "CBS"): rec("1950-10-23", 0.95, readable=False)}, 0.5)[0],
      None)
doc = B.tonight(dt.date(2026, 10, 22), 2, m2, 0.5)
check("tonight: keyed by calendar date", list(doc["days"]), ["2026-10-22", "2026-10-23"])
check("tonight: the zone is stated", doc["zone"], "America/New_York")
one = doc["days"]["2026-10-23"]
check("tonight: one evening, never stitched: every slot is that evening's date",
      {s["episode"]["id"].split("|")[1] for s in one["slots"] if s.get("episode")}, {one["evening"]})
check("tonight: each slot carries its Eastern time and the replay instant",
      (one["slots"][0]["et_start"], one["slots"][0]["utc_start"]), ("20:00", "2026-10-24T00:00:00Z"))
old = {"days": {"2026-10-21": {"evening": "x"}, "2026-10-22": {"evening": "1940-10-22"}}}
kept = B.keep_published(doc, old, "2026-10-22")
check("contract §8: a published day keeps its value", kept["days"]["2026-10-22"]["evening"], "1940-10-22")
check("contract §8: days before the window drop off", "2026-10-21" in kept["days"], False)
check("control: a new day is added", kept["days"]["2026-10-23"]["evening"], "1947-10-23")

# --- the published file: window, never-change, served only -------------------------
check("window: starts yesterday (the build's UTC date minus one)", B.window(dt.date(2026, 10, 22))[0],
      dt.date(2026, 10, 21))
check("window: runs through 13 days ahead of today", B.window(dt.date(2026, 10, 22))[1], 15)
pool = {(f"{y}-{md}", "CBS"): rec(f"{y}-{md}", 0.4) for y in (1947, 1948)
        for md in ("10-20", "10-21", "10-22", "10-23", "11-04", "11-05")}
w0, wn = B.window(dt.date(2026, 10, 22))
every = lambda eid: True  # noqa: E731  (the pool's episodes are not in the fixture catalog)
doc = B.tonight(w0, wn, pool, served=every)
check("window: the file's first day is yesterday, its last today + 13", (min(doc["days"]), max(doc["days"])),
      ("2026-10-21", "2026-11-04"))
check("control: a build a day later starts a day later", min(B.tonight(*B.window(dt.date(2026, 10, 23)), pool)["days"]),
      "2026-10-22")
check("floor: one named constant, stated in the file and marked provisional",
      (doc["floor"], doc["floor_provisional"], B.tonight.__defaults__[0]), (B.FLOOR, True, B.FLOOR))
check("R10: each slot carries the instant it ends", doc["days"]["2026-10-22"]["slots"][0]["utc_end"],
      "2026-10-23T00:30:00Z")

# a hidden episode never fills a slot: the fixture serves suspense|1947-10-16, not suspense|1948-10-16
hid = {("1947-10-16", "CBS"): rec("1947-10-16", 0.3), ("1948-10-16", "CBS"): rec("1948-10-16", 0.9)}
got = B.tonight(dt.date(2026, 10, 16), 1, hid, served=cat.served)["days"]["2026-10-16"]
check("served: an episode the projection does not serve never fills a slot; the pick sees served coverage",
      (got["evening"], got["slots"][0]["episode"]["id"]), ("1947-10-16", "suspense|1947-10-16"))
two = dict(rec("1947-10-16", 0.5), slots=[dict(rec("1947-10-16", 0)["slots"][0], et_end="21:00", length_min=60),
    {"et_start": "21:00", "et_end": "21:30", "length_min": 30, "printed": "Mr. Keen",
     "episode": {"id": "mrkeentraceroflostpersons|1947-10-16", "series": "Mr. Keen, Tracer of Lost Persons"}}])
gone = B.tonight(dt.date(2026, 10, 16), 1, {("1947-10-16", "CBS"): two}, served=cat.served)["days"]["2026-10-16"]
check("served: the unserved episode's slot is a withheld gap that names its series; coverage counts what plays",
      (gone["slots"][1].get("episode"), gone["slots"][1].get("gap"), gone["slots"][1].get("withheld"),
       gone["slots"][1].get("known_series"), gone["coverage"]),
      (None, True, True, "Mr. Keen, Tracer of Lost Persons", 0.25))
check("control: with no served check the same episode would have filled it",
      B.tonight(dt.date(2026, 10, 16), 1, {("1947-10-16", "CBS"): two})["days"]["2026-10-16"]
      ["slots"][1].get("episode", {}).get("id"), "mrkeentraceroflostpersons|1947-10-16")
check("served: an evening whose every episode is unserved is not offered",
      B.tonight(dt.date(2026, 10, 16), 1, {("1948-10-16", "CBS"): rec("1948-10-16", 0.9)}, served=cat.served)["days"],
      {})
nr = {("1947-10-16", "CBS"): dict(rec("1947-10-16", 0.9), slots=[two["slots"][0],
    {"et_start": "22:30", "et_end": "23:00", "length_min": 30, "printed": "Man Called X",
     "episode": {"id": "mancalledx|1947-10-16", "series": "The Man Called X"}}])}
check("served: a never-recommended episode never fills a slot (contract §9.4)",
      B.tonight(dt.date(2026, 10, 16), 1, nr, served=cat.served)["days"]["2026-10-16"]["slots"][1].get("episode"), None)

# a day once published never changes
pub = B.tonight(*B.window(dt.date(2026, 10, 22)), pool, served=every)
import copy  # noqa: E402
richer = dict(pool)
richer[("1950-10-22", "CBS")] = rec("1950-10-22", 0.9)
again = B.keep_published(B.tonight(*B.window(dt.date(2026, 10, 23)), richer, served=every), copy.deepcopy(pub),
                         "2026-10-22", served=every)
check("never-change: a richer evening found later does not replace a published day",
      again["days"]["2026-10-22"], pub["days"]["2026-10-22"])
check("never-change: the guard finds nothing changed", B.changed_days(pub, again, "2026-10-22"), [])
check("never-change: yesterday's yesterday drops off the window", "2026-10-21" in again["days"], False)
check("control: a day never published takes the new value", again["days"]["2026-11-05"]["evening"], "1948-11-05")
fresh = B.tonight(*B.window(dt.date(2026, 10, 23)), richer, served=every)
check("control: without the merge the day would have changed, and the guard says so",
      (fresh["days"]["2026-10-22"]["evening"], B.changed_days(pub, fresh, "2026-10-22")), ("1950-10-22", ["2026-10-22"]))
swapped = copy.deepcopy(pub)
swapped["days"]["2026-10-23"]["slots"][0]["episode"]["id"] = "suspense|1947-10-09"
check("control: the guard refuses a published slot given another episode",
      B.changed_days(pub, swapped, "2026-10-22"), ["2026-10-23"])
taken = B.keep_published(B.tonight(*B.window(dt.date(2026, 10, 23)), pool), copy.deepcopy(pub), "2026-10-22",
                         served=lambda eid: eid != "suspense|1948-10-23")
check("withdrawal: an episode taken down after publishing leaves its published day as a withheld gap",
      (taken["days"]["2026-10-23"]["evening"], taken["days"]["2026-10-23"]["slots"][0].get("withheld")),
      ("1948-10-23", True))
check("withdrawal: the guard accepts a withdrawal as the one allowed change", B.changed_days(pub, taken, "2026-10-22"), [])

# the web's file: the same evenings, the web projection's own shards decide
web = os.path.join(tmp, "web")
os.makedirs(os.path.join(web, "episodes"))
import json  # noqa: E402
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
from build_web_projection import shard_of  # noqa: E402
with open(os.path.join(web, "episodes", f"{shard_of('suspense|1948-10-22')}.json"), "w") as f:
    json.dump({"suspense|1948-10-22": []}, f)
wdoc = B.for_web(pub, web)
check("web: the same evening on the same date as the apps (one clock)",
      {d: v["evening"] for d, v in wdoc["days"].items()}, {d: v["evening"] for d, v in pub["days"].items()})
check("web: an episode the web projection does not serve is withheld",
      wdoc["days"]["2026-10-23"]["slots"][0].get("withheld"), True)
check("control: one it serves still plays", wdoc["days"]["2026-10-22"]["slots"][0]["episode"]["id"],
      "suspense|1948-10-22")

# --- the real page, when cached --------------------------------------------------
pdf = os.path.join(B.CACHE, "radiologs", "pdf", "w1947-10-16.pdf")
if os.path.exists(pdf) and os.path.exists(B.PROJECTION):
    real = B.Catalog()
    g, err = B.parse_grid(B.words_of(pdf), "1947-10-16")
    wtop = [s for s in g["stations"] if s["call"] == "WTOP"][0]
    got = B.match_slots([s for s in wtop["slots"] if 19 * 60 <= s["start"] < 23 * 60], "1947-10-16", "CBS", real)
    eight = [s for s in got if B.hhmm(s["start"]) == "20:00"][0]
    check("real: WTOP 8 PM 1947-10-16 plays Suspense of that night", eight.get("episode", {}).get("id"),
          "suspense|1947-10-16")
    check("real: every filled slot is that night's", {s["episode"]["id"].split("|")[1] for s in got if s.get("episode")},
          {"1947-10-16"})
else:
    print("  SKIP  real page: cached log or projection missing")

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
