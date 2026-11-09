"""An uploader's or a collection's mixed bag is not a series (tools/reattribute.grab_bag, build_db.merge_grab_bags,
build_projection's bag donors; catalog DECISIONS 032, owner 2026-11-09: "Obviously, a grab bag of uploads isn't a
series.").

    python3 tests/test_grab_bag.py
    PROJECTION=out/publish/ear-drama.sqlite SOURCE=out/radio-catalog.sqlite python3 tests/test_grab_bag.py

Fixtures prove each rule and its refusal (a real anthology whose titles name films, a program named "Mixed Doubles",
a broadcast program, a LibriVox project). The guard over a real build never pins a row: no served series is a grab
bag by the same test run on what is served. Seen failing on the 2026-11-09 dry-run artifacts of the unchanged tools
("Michael Fisher Acc", "News from the 30's Through the 70's", "Christmas Shows", "1945 Radio News" served).
"""
import json
import os
import sqlite3
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import display_text as DT
import reattribute as RA

ran = failed = 0


def check(name, got, want):
    global ran, failed
    ran += 1
    if got != want:
        failed += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


def F(n, how="file", item="i1", programs=()):
    progs = list(programs) + [None] * (n - len(programs))
    return [{"how": how, "item": item, "program": p} for p in progs]


# item: named for a mixed upload.
check("item: named for an item filed under many series, two programs lead its files",
      RA.grab_bag("Michael Fisher Acc", F(20, "item", "fisher", ["worldseries", "texasrangers"]), {"fisher": 95}, {"fisher": 300}),
      "item")
check("item: or it holds under half of that item", RA.grab_bag("Grandpa's Stories", F(10, "item", "g"), {"g": 30}, {"g": 40}), "item")
check("control: a program named for its own item, holding most of it, is a program",
      RA.grab_bag("The Delirious Insomniac", F(30, "item", "d"), {"d": 8}, {"d": 40}), None)
check("control: an item filed under few series is not a mixed upload",
      RA.grab_bag("Suspense", F(30, "item", "s", ["luxradiotheater", "escape"]), {"s": 3}, {"s": 30}), None)
# programs: many programs lead its file names.
check("programs: three programs lead a quarter of its files",
      RA.grab_bag("Rare Comedy", F(12, programs=["townhalltonight"] * 2 + ["texacostartheater", "burnsandallen"]), {"i1": 1}, {"i1": 12}),
      "programs")
check("control: a few crossovers in a long run are not a bag",
      RA.grab_bag("Jack Benny Program", F(100, programs=["fredallenshow", "bingcrosby", "melblancshow"]), {"i1": 2}, {"i1": 100}),
      None)
check("control: a broadcast program is judged only by its name",
      RA.grab_bag("Lux Radio Theater", F(8, programs=["thinman", "remember", "wutheringheights"]), {"i1": 1}, {"i1": 8},
                  broadcast=True), None)
# collection: a collection's name with programs in it, or a dated news collection.
check("collection: a collection's name with two programs leading its files",
      RA.grab_bag("Christmas Shows", F(40, programs=["adayinthelifeofdennisday", "bobhopeshow"]), {"i1": 1}, {"i1": 40},
                  broadcast=True), "collection")
check("collection: a year's radio news", RA.grab_bag("1945 Radio News", F(40), {"i1": 1}, {"i1": 40}, broadcast=True), "collection")
check("collection: an uploader's news files", [RA.grab_bag(n, F(4), {"i1": 1}, {"i1": 4}) for n in
      ("Radio News", "WWII News and Related Sound files from", "1930's Radio News")], ["collection"] * 3)
check("control: a network's news program is a program", RA.grab_bag("NBC News", F(4), {"i1": 1}, {"i1": 4}), None)
check("collection: decades of news", RA.grab_bag("News From The 30's Through The 70's", F(4), {"i1": 1}, {"i1": 4}), "collection")
for name in ("Mixed Doubles", "The Wizard of Odds", 'General Electric "Excursions in Science" programs'):
    check(f"control: {name!r} is a program", RA.grab_bag(name, F(2), {"i1": 2}, {"i1": 2}), None)
check("control: a LibriVox collection is a work",
      RA.grab_bag("One-Act Play Collection 004", F(12, "item", "lv", ["a1", "b2"]), {"lv": 12}, {"lv": 12}, librivox=True), None)

# lead_program: a registry program's name leads the file name; two words and eight letters at least.
k2c = {"cbsworldnewstoday": "cbsworldnewstoday", "luxradiotheater": "luxradiotheater", "lux": "luxradiotheater",
       "remember": "remember"}
reg = set(k2c.values())
check("lead: a program's whole name leads", RA.lead_program("1944-06-06 CBS World News Today - D-Day", k2c, reg),
      "cbsworldnewstoday")
check("control: a one-word program is a common word, never read", RA.lead_program("Remember the Alamo", k2c, reg), None)
check("control: a name the registry does not hold is none", RA.lead_program("Bob Hope #3", k2c, reg), None)

# A bag gives broadcasts and never keeps one (P-10 survivor rank).
eps = {"bag|1": ("bag", "1944-12-24", "A Christmas Carol Story", False, {"x"}),
       "show|1": ("show", "1944-12-24", "A Christmas Carol Story", False, {"y"})}
series = {"bag": {"name": "Christmas Shows", "own": True, "eps": 400, "bag": True},
          "show": {"name": "Some Show", "own": True, "eps": 3}}
check("a bag's copy of a broadcast another series holds folds into that series", DT.same_broadcasts(eps, series)[0],
      {"bag|1": "show|1"})
series["bag"]["bag"] = False
check("control: without the bag mark the larger series would keep it", DT.same_broadcasts(eps, series)[0], {"show|1": "bag|1"})

# ---- the guard over a real build ----
real = os.environ.get("PROJECTION") or os.path.join(os.path.dirname(__file__), "..", "out", "publish", "ear-drama.sqlite")
src = os.environ.get("SOURCE") or os.path.join(os.path.dirname(__file__), "..", "out", "radio-catalog.sqlite")
if os.path.exists(real) and os.path.exists(src):
    d = sqlite3.connect(f"file:{real}?mode=ro", uri=True)
    s = sqlite3.connect(f"file:{src}?mode=ro", uri=True)
    registry = {k for (k,) in s.execute("SELECT key FROM series WHERE in_spine = 1 OR otrr_programs IS NOT NULL")}
    k2c = {k: k for k in registry}
    for ak, sk in s.execute("SELECT alias_key, series_key FROM series_aliases"):
        if sk in registry:
            k2c[ak] = sk
    lv = {k for (k,) in s.execute("SELECT key FROM series WHERE is_librivox = 1")}
    runs = {k: (a, b) for k, a, b in s.execute("SELECT key, first_broadcast, last_broadcast FROM series")}
    how = {eid: (json.loads(i).get("series") if i else "") or "" for eid, i in s.execute("SELECT id, identity FROM episodes")}
    files = {}
    for eid, aid, f in s.execute("SELECT episode_id, archive_id, file FROM recordings"):
        files.setdefault(eid, []).append((aid, f))
    served = dict(d.execute("SELECT id, series_key FROM episodes"))
    names = dict(d.execute("SELECT key, name FROM series"))
    feeds, item_files, by = {}, {}, {}
    for eid, sk in served.items():
        for aid, f in files.get(eid, ())[:1]:
            feeds.setdefault(aid, set()).add(sk)
            item_files[aid] = item_files.get(aid, 0) + 1
            stem = os.path.splitext(f.rsplit("/", 1)[-1])[0]
            p = RA.lead_program(stem, k2c, registry) if how.get(eid) != "otrr_log" else None
            by.setdefault(sk, []).append({"how": how.get(eid), "item": aid, "program": p if p != sk else None})
    feeds_n = {k: len(v) for k, v in feeds.items()}
    bags = []
    for sk in sorted(by):
        a, b = runs.get(sk, (None, None))
        broadcast = sk in registry and bool(a and b) and int(b[:4]) - int(a[:4]) <= RA.BAG_RUN_YEARS
        rule = RA.grab_bag(names.get(sk), by[sk], feeds_n, item_files, broadcast, sk in lv)
        if rule:
            bags.append((names.get(sk), rule, len(by[sk])))
    bags.sort(key=lambda x: -x[2])
    check("guard: no served series is a grab bag", (len(bags), bags[:8]), (0, []))
elif os.environ.get("PROJECTION"):
    check("the build named by PROJECTION and SOURCE exists", False, True)
else:
    print("  SKIP  guard: no build at out/publish/ear-drama.sqlite and out/radio-catalog.sqlite (name them)")

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
