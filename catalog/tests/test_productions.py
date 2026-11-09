"""A series is one production (catalog DECISIONS 035). OTRRpedia files several productions of one character under one
program ("Sherlock Holmes", 8101), and the folds trusted it; 026: another producer, network, run or cast is another
program. display_text.productions splits a series only where its credits' casts, the registry's silences, the
networks and the program names a source writes separate its broadcasts.

    python3 tests/test_productions.py
    PROJECTION=out/publish/ear-drama.sqlite SOURCE=out/radio-catalog.sqlite python3 tests/test_productions.py

Fixtures prove each rule and its refusal. The guard over a real build asks the same question of every served series,
with the same evidence (build_projection.production_inputs): does the evidence still separate its broadcasts into
two productions? Seen failing on the 2026-11-09 dry-run artifacts of the unchanged tools (counts in DECISIONS 035).
"""
import json
import os
import sqlite3
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import audit_audio_rights as A
import display_text as DT

ran = failed = 0


def check(name, got, want):
    global ran, failed
    ran += 1
    if got != want:
        failed += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


def weekly(prefix, start_year, n, net, cast=(), name=None, every=7):
    """n weekly broadcasts from January of `start_year`: ({id: (date, network, title)}, {id: cast}, {id: names})."""
    import datetime
    d0 = datetime.date(start_year, 1, 5)
    eps, people, names = {}, {}, {}
    for i in range(n):
        eid = f"{prefix}{i:03d}"
        eps[eid] = ((d0 + datetime.timedelta(days=every * i)).isoformat(), net, f"{prefix} story number {i}")
        if cast:
            people[eid] = set(cast)
        if name:
            names[eid] = {name}
    return eps, people, names


def merge(*parts):
    eps, cast, names = {}, {}, {}
    for e, c, n in parts:
        eps.update(e)
        cast.update(c)
        names.update(n)
    return eps, cast, names


def split(eps, cast, names, runs, nights=None):
    prods, rest = DT.productions(eps, cast, names, runs, nights)
    return [(p["first"][:4], p["last"][:4], len(p["eps"])) for p in prods], len(rest)


# ---- fixtures: what separates two productions ----
gordon = weekly("g", 1932, 30, "NBC Blue", ("Richard Gordon", "Leigh Lovell"), "The Adventures Of Sherlock Holmes")
rathbone = weekly("r", 1940, 40, "NBC Blue", ("Basil Rathbone", "Nigel Bruce"), "The New Adventures Of Sherlock Holmes")
conway = weekly("c", 1946, 20, "ABC", ("Tom Conway", "Nigel Bruce"), "The New Adventures Of Sherlock Holmes")
stanley = weekly("s", 1947, 40, "Mutual", ("John Stanley", "Alfred Shirley"), "Sherlock Holmes")
runs = [("1932-01-01", "1933-06-14"), ("1939-10-02", "1947-07-07"), ("1947-09-28", "1949-06-06")]
eps, cast, names = merge(gordon, rathbone, conway)
check("silence and two casts: Richard Gordon's run and Rathbone's are two productions",
      split(eps, cast, names, runs), ([("1932", "1932", 30), ("1940", "1946", 60)], 0))
check("one cast: Nigel Bruce joins Rathbone's seasons to Tom Conway's on another network",
      split(*merge(rathbone, conway), runs), ([], 0))
s2 = ({e: ("1946-0" + str(6 + int(e[1:]) // 8) + "-" + f"{1 + int(e[1:]) % 8 * 3:02d}", "Mutual", t)
       for e, (d, n, t) in stanley[0].items()}, stanley[1], stanley[2])   # Stanley's Mutual run right after Conway's
check("boundary: the network changes where two casts meet and the names differ (Conway's ABC to Stanley's Mutual)",
      split(*merge(rathbone, conway, s2), runs)[0][-1][2], 40)
s3 = (s2[0], s2[1], {e: {"The New Adventures Of Sherlock Holmes"} for e in s2[0]})
check("control: a recast under the same name on the next network is one program (Mr. Keen, Red Ryder)",
      split(*merge(rathbone, conway, s3), runs), ([], 0))
keen = weekly("k", 1941, 40, "CBS", ("Bennett Kilpack",), "Mr. Keen, Tracer Of Lost Persons")
keen2 = weekly("q", 1942, 20, "CBS", ("Phillip Clarke",), "Mr. Keen, Tracer Of Lost Persons")
check("control: a recast on one name and network with no silence is one program (Johnny Dollar)",
      split(*merge(keen, keen2), [("1941-01-01", "1943-12-31")]), ([], 0))
check("control: with no registry runs a gap in the surviving recordings is no silence on the air",
      split(eps, cast, names, []), ([], 0))
check("control: no silence where a registry run covers the gap",
      split(eps, cast, names, runs + [("1933-06-15", "1939-10-01")]), ([], 0))
slip = merge(gordon, rathbone)
slip[1]["r000"] = {"Basil Rathbone", "Nigel Bruce", "Leigh Lovell"}
check("control: one shared credit may be a slip; two casts need two broadcasts together to be one",
      split(*slip, runs)[0], [("1932", "1932", 30), ("1940", "1940", 40)])
slip[1]["r001"] = {"Basil Rathbone", "Leigh Lovell"}
check("two broadcasts together make one cast", split(*slip, runs), ([], 0))
tarzan = weekly("t", 1932, 30, "Syndicated", (), "Tarzan Of The Apes")
tarzan51 = weekly("u", 1951, 30, "Mutual-Don Lee", ("Lamont Johnson",), "Tarzan")
truns = [("1932-09-12", "1934-03-01"), ("1951-01-01", None), ("1952-03-22", "1953-06-27")]
check("silence: an uncredited run under its own name and a cast fifteen years on are two productions",
      split(*merge(tarzan, tarzan51), truns), ([("1932", "1932", 30), ("1951", "1951", 30)], 0))
bare = (tarzan[0], tarzan[1], {})
check("control: an uncredited run with no program name is not a production of its own", split(*merge(bare, tarzan51), truns)[0], [])
undated = merge(gordon, rathbone)
undated[0].update({"x1": (None, None, "r story number 3"), "x2": (None, None, "Das Beryll-Diadem"),
                   "x3": (None, None, "The Viennese Strangler (04-09-45)")})
undated[1]["x4"] = {"Richard Gordon", "Leigh Lovell"}
undated[0]["x4"] = (None, None, "An undated Gordon story")
prods, rest = DT.productions(*undated, runs, {DT._undated_key("The Viennese Strangler"): {"1940-02-02"}})
place = {e: i for i, p in enumerate(prods) for e in p["eps"]}
check("undated: placed by a dated broadcast of the same title", place.get("x1"), 1)
check("undated: placed by its cast", place.get("x4"), 0)
check("undated: placed by the night a source gives its title (a date note dropped)", place.get("x3"), 1)
check("undated: nothing places it, so it is the remainder", sorted(rest), ["x2"])
check("a registry date with zeros", DT._day("1931-00-00"), "1931-01-01")
check("a registry end date with zeros", DT._day("1936-09-00", end=True), "1936-09-28")
check("goldin cast: performers and a character", DT.goldin_cast(
    ' Richard Gordon ; Edith Meiser (writer); Louis Hector  (as "Sherlock Holmes"), Alec McCowan (?)'),
    ["Richard Gordon", 'Louis Hector'])

# ---- fixtures: a registry that files another country's productions vouches for none (033's exemption, 035) ----
us = {"idp": "1", "histories": [{"country": "USA"}], "titles": [{"title": "Hello Americans"}]}
umbrella = {"idp": "2", "histories": [{"country": "USA"}, {"country": "United Kingdom"}],
            "titles": [{"title": "Sherlock Holmes"}]}
labeled = {"idp": "3", "histories": [{"country": "USA"}], "titles": [{"title": "Stories of Sherlock Holmes (SA)"}]}
check("a US run vouches for an American production", A.us_program(us), True)
check("a run in another country: the program files more than one country's productions", A.us_program(umbrella), False)
check("a title with a production label files another country's production", A.us_program(labeled), False)
check("control: a program with no run says nothing either way", A.files_foreign({"histories": [], "titles": []}), False)
keys = {"1": ["hello"], "2": ["sherlock"], "3": ["sherlock"], "4": ["hello"]}
check("a series mapped to a program that files another country's productions is not vouched for",
      A.us_series_keys([us, umbrella, labeled, {"idp": "4", "histories": [], "titles": []}],
                       lambda p: keys.get(p["idp"], [])), {"hello"})

# ---- the guard over a real build ----
real = os.environ.get("PROJECTION") or os.path.join(os.path.dirname(__file__), "..", "out", "publish", "ear-drama.sqlite")
src_db = os.environ.get("SOURCE") or os.path.join(os.path.dirname(__file__), "..", "out", "radio-catalog.sqlite")
if os.path.exists(real) and os.path.exists(src_db):
    import build_projection as BP
    d = sqlite3.connect(f"file:{real}?mode=ro", uri=True)
    s = sqlite3.connect(f"file:{src_db}?mode=ro", uri=True)
    names = dict(d.execute("SELECT key, name FROM series"))
    librivox = {k for (k,) in s.execute("SELECT key FROM series WHERE is_librivox = 1")}
    try:
        detail = json.load(open(os.path.join(os.path.dirname(os.path.abspath(real)), "display_text.json")))
    except (OSError, ValueError):
        detail = {}
    members = {k: {k} for k in names}
    for old, new in (detail.get("merged") or {}).items():
        if new in members:
            members[new].add(old)
    for parent, units in ((detail.get("folded") or {}).get("split") or {}).items():
        for u in units:
            if u["key"] in members:
                members[u["key"]] |= members.get(parent, {parent}) | {parent}
    eps_of = {}
    for eid, sk, air, raw, title in d.execute("SELECT id, series_key, air_date, raw_title, title FROM episodes"):
        if sk not in librivox:
            eps_of.setdefault(sk, {})[eid] = (air, raw or title)
    eps_of = {k: v for k, v in eps_of.items() if len(v) >= 2 * DT.MIN_RUN}
    inputs = BP.production_inputs(s, eps_of, {k: sorted(members.get(k, {k})) for k in eps_of}, names)
    mixed = []
    for k in sorted(inputs):
        eps, cast, wit, runs, nights, _umbrella = inputs[k]
        prods, _rest = DT.productions(eps, cast, wit, runs, nights)
        if prods:
            mixed.append((names[k], [(p["first"][:4], p["last"][:4], len(p["eps"])) for p in prods]))
    check("guard: no served series holds two productions its credits, runs, networks and witnesses separate",
          (len(mixed), mixed[:6]), (0, []))
elif os.environ.get("PROJECTION"):
    check("the build named by PROJECTION and SOURCE exists", False, True)
else:
    print("  SKIP  guard: no build at out/publish/ear-drama.sqlite and out/radio-catalog.sqlite (name them)")

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
