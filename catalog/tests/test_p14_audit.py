"""P-14 (catalog DECISIONS 037): what the 035 split and the 036 date notes left in the served catalog, each decided by
a rule we already had, guarded over a real build.

    python3 tests/test_p14_audit.py
    PROJECTION=out/publish/ear-drama.sqlite SOURCE=out/radio-catalog.sqlite python3 tests/test_p14_audit.py

1. A dated broadcast outside every production's span, but less than a silence (two years) from exactly one, is that
   production's (035's own silence): the split no longer leaves a broadcast a week before a run's first recording
   in a remainder that then reads as a second series of the same name and years.
2. A date a file's own number contradicts is not shown (016): "Chandu the Magician 135 48-01-03" sits between #134
   1948-12-31 and #139 1949-01-07.
3. A two-digit year is read by the parser's own order (YY-MM-DD, else MM-DD-YY) in this century when that reading is
   on or before the item's upload and no 19YY reading in the first order exists ("BB_06-17-07" is 2007-06-17).
4. A "._" file is a macOS resource fork, never audio.
5. The parser reads "#167 39-10-17" and a capitalized title glued to the date.

The guards over a real build never pin a row; each asks whether the build serves something a rule withholds:
  - a served broadcast within a season (SEASON_DAYS) of a broadcast of another served series of its name (one
    production split in two);
  - two served series of one name a list cannot tell apart (same years, or both undated, and the same count);
  - more broadcasts of one series on one night than MAX_PER_NIGHT;
  - a served dated broadcast whose own number its neighbours contradict;
  - a served episode whose two-digit year the build would read in this century;
  - a served copy that is a "._" resource fork.
Seen failing on the dry-run artifacts of the unchanged tools (counts in DECISIONS 037).
"""
import collections
import os
import sqlite3
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import build_db as B
import display_text as DT
import otr_parse as P

ran = failed = 0
# One series' broadcasts on one night: a serial's two daily episodes, a doubleheader's halves, a two-network night.
# MEASURED on the catalog-2026-11-10 dry run: after every fold the most is 2 (DECISIONS 037), so 3 means a set of
# files took one date that is not theirs.
MAX_PER_NIGHT = 2
SEASON_DAYS = 91   # thirteen weeks: two productions of one name are never one season apart on the air


def check(name, got, want):
    global ran, failed
    ran += 1
    if got != want:
        failed += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


# ---- fixtures: placement by a production's reach (035's silence) ----
eps = {f"a{i}": (f"1932-0{1 + i % 9}-1{i % 9}", "NBC", None) for i in range(9)}
eps.update({f"b{i}": (f"1951-0{1 + i % 9}-1{i % 9}", "CBS", None) for i in range(9)})
eps["near"] = ("1950-12-20", "CBS", None)      # eleven days before the 1951 run's first recording
eps["far"] = ("1941-06-01", None, None)        # nine years from either
cast = {f"a{i}": {"gordon"} for i in range(9)}
cast.update({f"b{i}": {"johnson"} for i in range(9)})
RUNS = [("1932-01-01", "1932-12-31"), ("1951-01-01", "1951-12-31")]
prods, rest = DT.productions(eps, cast, runs=RUNS)
check("a broadcast days outside one production's span is that production's",
      [sorted(p["eps"]) for p in prods if "near" in p["eps"]] != [], True)
check("a broadcast years from every production stays in the remainder", "far" in rest, True)
eps2 = dict(eps, mid=("1949-12-01", None, None))
eps2.update({f"c{i}": (f"1948-0{1 + i % 9}-1{i % 9}", "Mutual", None) for i in range(9)})
cast2 = dict(cast, **{f"c{i}": {"stanley"} for i in range(9)})
prods2, rest2 = DT.productions(eps2, cast2, runs=RUNS + [("1948-01-01", "1948-12-31")])
check("control: a broadcast within reach of two productions is placed by neither", "mid" in rest2, True)

eps3 = dict(eps, stray=("1933-01-18", None, None))
cast3 = dict(cast, stray={"johnson"})          # credited with the 1951 cast, dated eighteen years before its run
prods3, rest3 = DT.productions(eps3, cast3, runs=RUNS)
check("a cast's stray date a silence from its production is placed as any date is", "stray" in rest3 or any(
    "stray" in p["eps"] and p["first"] <= "1933-01-18" for p in prods3), True)
check("control: it does not stretch the 1951 production back to 1933",
      [p for p in prods3 if "stray" in p["eps"] and "b0" in p["eps"]], [])


# ---- fixtures: one name, nothing between them (merge_into) ----
def ser(name, own=True, first=None, last=None, eps=1):
    return {"name": name, "cleaned": False, "librivox": False, "own": own, "eps": eps, "first": first, "last": last,
            "aliases": []}


check("two undated uploads of one name are one series",
      DT.merge_into({"09noelcowardhayfever": ser("Noël Coward Hay Fever"),
                     "09anoelcowardhayfever": ser("Noël Coward Hay Fever")}),
      {"09noelcowardhayfever": "09anoelcowardhayfever"})
check("control: dated uploads of one name stay apart for their years to tell",
      DT.merge_into({"lightsout": ser("Lights Out", first="1936-01-01", last="1943-01-01"),
                     "lightsout1945": ser("Lights Out", first="1945-01-01", last="1946-01-01")}), {})


# ---- fixtures: a date its own number contradicts (016) ----
def frec(num, date, key="chandu"):
    return {"key": key, "num": num, "name_num": num, "date": date, "decade": "1940s", "date_source": "filename",
            "idt": {}}


# Chandu the Magician's files as the corpus holds them: the 1948-49 serial, and the 1932 serial numbered again
run = [frec(n, d) for n, d in ((130, "1948-12-24"), (131, "1948-12-27"), (132, "1948-12-28"), (133, "1948-12-29"),
                               (134, "1948-12-30"), (135, "1948-01-03"), (136, "1948-01-04"), (136, "1932-09-12"),
                               (137, "1932-09-13"), (138, "1949-01-05"), (138, "1932-09-14"), (139, "1949-01-06"),
                               (142, "1949-01-12"), (143, "1949-01-13"))]
got = B.number_contradicted_dates(run)
check("a slipped year between its numbered neighbours is dropped", sorted(r["num"] for r in got), [135, 136])
check("its number stays", sorted(r["num"] for r in run if r["date"] is None), [135, 136])
check("control: the other run's broadcasts keep their dates", sorted(r["date"] for r in run if r["date"] and
                                                                     r["date"] < "1940"),
      ["1932-09-12", "1932-09-13", "1932-09-14"])
sup = [frec(n, d, "superman") for n, d in ((8, "1940-03-01"), (9, "1940-03-04"), (10, "1940-03-05"),
                                         (11, "1940-03-06"), (12, "1940-03-08"), (14, "1940-03-12"),
                                         (15, "1940-03-13"), (16, "1940-03-14"), (13, "1949-03-07"),
                                         (17, "1949-03-11"), (18, "1949-03-14"))]
check("control: a run numbered again whose other broadcasts sit beside it keeps its dates",
      B.number_contradicted_dates(sup), [])
ctl = [frec(n, f"1948-12-{n - 100:02d}") for n in range(101, 112)] + [frec(112, "1948-12-14")]
check("control: a broadcast a few days off its neighbours keeps its date", B.number_contradicted_dates(ctl), [])
gaps = [frec(1, "1948-01-05"), frec(2, "1948-01-12"), frec(3, "1948-01-19"), frec(4, "1949-06-01"),
        frec(30, "1949-06-08"), frec(31, "1949-06-15")]
check("control: neighbours whose own dates disagree with their numbers witness nothing",
      B.number_contradicted_dates(gaps), [])

# ---- fixtures: two-digit years by the parser's own order, this century from the upload date ----
for stem, date, pub, want in (
        ("BB_06-17-07", None, "2021-12-17 22:26:41", "2007-06-17"),                 # WAMU's The Big Broadcast
        ("10. \"The '70s- The Hard Years\" 03-11-28", "1928-03-11", "2021-05-07", "2003-11-28"),
        ("25 - Dean Koontz - 01-22-02", None, "2023-09-20", "2002-01-22"),
        ("BB_06-17-07", None, "2006-01-01", None),                                  # after the upload: not read
        ("Amos and Andy 28-07-27 Democrats", "1928-07-27", "2025-03-04", None),     # the first order's 19YY stands
        ("Camel Caravan - 11-26-49 - 1", None, "2024-08-20", None),                  # a 19YY broadcast date
        ("Show 01-03-05 and 02-04-06", None, "2020-01-01", None),                   # two dates: not known apart
        ("TARZ.1932.09.16_03_TARZAN_IN_YOUNG_MANHOOD", "1932-09-16", "2010-01-01", None),   # a four-digit date's tail
        ("1932-06-16-04APassToPekin", "1932-06-16", "2010-01-01", None),           # "-04" is a track, not a year
        ("MIDNIGHT SUN 14 - 12_23_16, 7.44 AM", None, "2016-12-23", "2016-12-23")):
    check(f"this century: {stem}", P.this_century(stem, date, pub), want)

# ---- fixtures: the parser ----
for name, want in (
        ("Captain Midnight #167 39-10-17 (JD REEL 0990).mp3", ("1939-10-17", 167)),
        ("Chandu the Magician 113 48-12-02LUPU ARRIVES (JD REEL 1901).mp3", ("1948-12-02", 113)),
        ("Rex Stout's Nero Wolfe 04 82-02-06 The Cop Killer.mp3", ("1982-02-06", 4)),
        ("Dimension X 011 Zero Hour.mp3", (None, 11))):
    p = P.parse(name)
    check(f"parse: {name}", (p["date"], p["num"]), want)
files = [{"name": "._Treasury Star Parade 001.mp3", "format": "VBR MP3", "source": "original"},
         {"name": "Treasury Star Parade 001.mp3", "format": "VBR MP3", "source": "original"},
         {"name": "disc/._Track 02.mp3", "format": "VBR MP3", "source": "original"}]
check("pick_files never takes a resource fork", [f["name"] for f in B.pick_files(files)],
      ["Treasury Star Parade 001.mp3"])

# ---- the guards over a real build ----
real = os.environ.get("PROJECTION") or os.path.join(os.path.dirname(__file__), "..", "out", "publish", "ear-drama.sqlite")
src_db = os.environ.get("SOURCE") or os.path.join(os.path.dirname(__file__), "..", "out", "radio-catalog.sqlite")
if os.path.exists(real) and os.path.exists(src_db):
    d = sqlite3.connect(f"file:{real}?mode=ro", uri=True)
    s = sqlite3.connect(f"file:{src_db}?mode=ro", uri=True)
    series = {k: (n, f, l, c) for k, n, f, l, c in d.execute(
        "SELECT key, name, first_date, last_date, episodes FROM series")}
    by_name = collections.defaultdict(list)
    for k, (n, f, l, c) in sorted(series.items()):
        by_name[(n or "").casefold()].append(k)
    dates = collections.defaultdict(list)
    for k, a in d.execute("SELECT series_key, air_date FROM episodes WHERE air_date IS NOT NULL"):
        if DT.FULL_DATE.match(a):
            dates[k].append(a)
    span = {k: sorted(v) for k, v in dates.items()}

    def within(day, k):   # within a season of one of its broadcasts: 035's boundaries are runs apart (Lights Out
        return any(abs(DT._days(day, o)) <= SEASON_DAYS for o in span[k])   # 1943 CBS to 1945 NBC: 21 months)
    overlap, alike = [], []
    for n, ks in sorted(by_name.items()):
        for i, a in enumerate(ks):
            for b in ks[i + 1:]:
                fa, la, ca = series[a][1:]
                fb, lb, cb = series[b][1:]
                near = [(x, y, day) for x, y in ((a, b), (b, a)) if y in span for day in dates.get(x, ())
                        if within(day, y)]
                if near:
                    overlap.append((series[a][0], a, b, len(near), near[0]))
                if (fa or "")[:4] == (fb or "")[:4] and (la or "")[:4] == (lb or "")[:4] and ca == cb:
                    alike.append((series[a][0], a, b, fa, la, ca))
    check("guard: no served broadcast falls within reach of another served series of its name (one production "
          "in two)", (len(overlap), overlap[:8]), (0, []))
    check("guard: no two served series of one name look alike in a list", (len(alike), alike[:8]), (0, []))
    piled = d.execute("SELECT series_key, air_date, COUNT(*) n FROM episodes WHERE air_date IS NOT NULL "
                      "GROUP BY 1, 2 HAVING n > ? ORDER BY n DESC", (MAX_PER_NIGHT,)).fetchall()
    check(f"guard: no series airs more than {MAX_PER_NIGHT} broadcasts on one night", (len(piled), piled[:8]), (0, []))
    raw = {}
    for eid, f, pub, rk, idn in s.execute(
            "SELECT e.id, r.file, i.publicdate, e.series_key, e.identity FROM episodes e JOIN recordings r ON "
            "r.episode_id = e.id AND r.rank = 0 LEFT JOIN items i ON i.id = r.archive_id"):
        raw[eid] = (f or "", pub, rk, idn or "")
    served = d.execute("SELECT id, series_key, air_date, num FROM episodes").fetchall()
    recs = []
    for eid, sk, a, n in served:   # a file's own number beside its own date (the research series: before any split)
        p = P.parse(raw[eid][0].rsplit("/", 1)[-1]) if a and eid in raw else None
        if a and eid in raw:
            logged = '"otrr_match": "series_date' in raw[eid][3]          # a log confirms the night
            own = p and p["date"] == a and p["num"] is not None
            recs.append({"key": raw[eid][2], "num": p["num"] if own else None, "name_num": p["num"] if own else None,
                         "date": a, "decade": None, "date_source": "filename", "idt": {}, "id": eid,
                         "orow": {"date": a} if logged else None})
    contra = sorted((r["key"], r["id"], r["num"]) for r in B.number_contradicted_dates(recs))
    check("guard: no served broadcast's date is contradicted by its own number", (len(contra), contra[:8]), (0, []))
    century = []
    for eid, sk, a, n in served:
        if eid in raw and (a is None or a < "1972"):
            f, pub, _rk, _i = raw[eid]
            if a and P.parse(f.rsplit("/", 1)[-1])["date"] != a:   # dated by a log, a tag or the item, not this name
                continue
            got = P.this_century(P.stem(f.rsplit("/", 1)[-1]), a, pub)
            if got:
                century.append((sk, a, got, f.rsplit("/", 1)[-1]))
    check("guard: no served episode carries a two-digit year of this century", (len(century), century[:8]), (0, []))
    cols = {r[1] for r in d.execute("PRAGMA table_info(recordings)")} if d.execute(
        "SELECT 1 FROM sqlite_master WHERE name = 'recordings'").fetchone() else set()
    forks = [u for (u,) in d.execute("SELECT url FROM recordings")] if "url" in cols else []
    forks = sorted(u for u in forks if (u or "").rsplit("/", 1)[-1].startswith(("._", "%2E_")))
    check("guard: no served copy is a resource fork", (len(forks), forks[:8]), (0, []))
elif os.environ.get("PROJECTION"):
    check("the build named by PROJECTION and SOURCE exists", False, True)
else:
    print("  SKIP  guards: no build at out/publish/ear-drama.sqlite and out/radio-catalog.sqlite (name them)")

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
