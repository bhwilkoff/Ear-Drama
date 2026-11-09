"""P-10: one broadcast in one place, one show under one name, a label on every copy, and the last raw titles
(tools/display_text.py, tools/polish.py, tools/build_projection.py; catalog DECISIONS 031, owner 2026-11-09).

    python3 tests/test_same_broadcast.py
    PROJECTION=out/publish/ear-drama.sqlite python3 tests/test_same_broadcast.py

Fixtures prove each fold and its refusal; the guard over a real projection counts classes and never pins a row:
no pair of series repeats each other's broadcasts MIN_SHARED times or more, every copy of an episode with several
has a label, and no title carries a reel track tail, a "1942-xx-xx" date or a recurring shelf code. Seen failing
on the 2026-11-09 dry-run projection of the unchanged tools (374 Jack Benny broadcasts also under "Grape Nuts
Program", 21,974 copies with no label) and on the 62e7d02-era tools for every fixture below marked P-10.
"""
import os
import sqlite3
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import display_text as DT
import polish as PL
import arcs as ARCS

ran = failed = 0


def check(name, got, want):
    global ran, failed
    ran += 1
    if got != want:
        failed += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


def P(name, own=True, eps=10, dates=(), run=(None, None), aliases=(), items=None, feeds=None, titles=(), lv=False):
    ds = sorted(dates)
    lo = [x for x in (run[0], ds[0] if ds else None) if x]
    hi = [x for x in (run[1], ds[-1] if ds else None) if x]
    return {"name": name, "own": own, "librivox": lv, "eps": eps, "aliases": list(aliases), "dates": ds,
            "run": (min(lo) if lo else None, max(hi) if hi else None), "items": dict(items or {}),
            "feeds": dict(feeds or {}), "titles": list(titles)}


# ---- same_broadcasts: the same date and title in two series is one broadcast, on evidence ----
series = {"jack": P("Jack Benny Program", False, 900), "grape": P("Grape Nuts Program", True, 700),
          "lux": P("Lux Radio Theater", False, 600), "camp": P("Campbell Playhouse", False, 300)}
eps = {"jack|1947-11-09": ("jack", "1947-11-09", "Corner Drug Store", False, {"a"}),
       "grape|1947-11-09": ("grape", "1947-11-09", "Corner Drug Store", False, {"b"}),
       "lux|1940-12-24": ("lux", "1940-12-24", "A Christmas Carol", False, {"c"}),
       "camp|1940-12-24": ("camp", "1940-12-24", "A Christmas Carol", False, {"d"})}
folds, shared = DT.same_broadcasts(eps, series)
check("P-10 an upload-named series' copy of a broadcast folds into the program", folds.get("grape|1947-11-09"), "jack|1947-11-09")
check("control: one coincidence between two registry programs is two productions", "camp|1940-12-24" in folds or "lux|1940-12-24" in folds, False)
eps2 = dict(eps, **{"camp|1940-12-24": ("camp", "1940-12-24", "A Christmas Carol", False, {"c"})})
check("P-10 two registry programs that share an archive.org item share the broadcast",
      len(DT.same_broadcasts(eps2, series)[0]), 2)
many = {}
for i, day in enumerate(("1941-01-05", "1941-01-12", "1941-01-19")):
    many[f"gold|{day}"] = ("gold", day, f"Chapter Title Number {i}", False, {f"g{i}"})
    many[f"tarz|{day}"] = ("tarz", day, f"Chapter Title Number {i}", False, {f"t{i}"})
many["gold|1942-02-02"] = ("gold", "1942-02-02", "Another Program Entirely", False, {"x"})
many["cecil|1942-02-02"] = ("cecil", "1942-02-02", "Another Program Entirely", False, {"y"})
two = {"gold": P("The Golden Age of Radio", False, 500), "tarz": P("Tarzan", False, 150), "cecil": P("Cecil and Sally", False, 90)}
got, sh = DT.same_broadcasts(many, two)
check("P-10 registry programs that repeat each other three times fold, toward the one with fewer partners",
      sorted(v.split("|")[0] for k, v in got.items() if k.startswith("gold|1941")), ["tarz"] * 3)
unclaimed = dict(eps, **{"grape|1947-11-09": ("grape", "1947-11-09", "Corner Drug Store", False, {"b"}, False)})
check("control: an unclaimed copy never joins a clean episode (the public web would serve it as clean)",
      "grape|1947-11-09" in DT.same_broadcasts(unclaimed, series)[0], False)
clean_into_unclaimed = dict(eps, **{"jack|1947-11-09": ("jack", "1947-11-09", "Corner Drug Store", False, {"a"}, False)})
check("P-10 a clean copy may join an unclaimed episode (the stricter line holds)",
      DT.same_broadcasts(clean_into_unclaimed, series)[0].get("grape|1947-11-09"), "jack|1947-11-09")
check("control: a title composed from the date is no evidence",
      DT.same_broadcasts({"a|1950-01-01": ("a", "1950-01-01", "A, January 1, 1950", True, set()),
                          "b|1950-01-01": ("b", "1950-01-01", "A, January 1, 1950", True, set())},
                         {"a": P("A"), "b": P("B")})[0], {})
check("control: a title that is only the series' name is no evidence",
      DT.same_broadcasts({"a|1950-01-01": ("a", "1950-01-01", "Louella Parsons", False, set()),
                          "b|1950-01-01": ("b", "1950-01-01", "Louella Parsons", False, set())},
                         {"a": P("Louella Parsons"), "b": P("Hollywood Gossip")})[0], {})
check("control: a short title (under six letters) is no evidence",
      DT.same_broadcasts({"a|1950-01-01": ("a", "1950-01-01", "Fire", False, set()),
                          "b|1950-01-01": ("b", "1950-01-01", "Fire", False, set())}, {"a": P("A"), "b": P("B")})[0], {})

# ---- same_program: an upload- or sponsor-named series that is one program ----
def run(s, shared=None):
    return {k: v for k, v in DT.same_program(s, shared).items()}


fib = P("Fibber McGee and Molly", False, 1300, run=("1935-04-16", "1956-03-23"), aliases=["FMM", "Fibber McGee & Molly"])
check("P-10 alias: the letters of a registry alias", run({"fmandm": P("FM&M", eps=67, dates=["1935-11-18", "1938-01-24"]), "fib": fib}),
      {"fmandm": ("fib", "alias")})
check("control: alias outside the program's run", run({"fmandm": P("FM&M", eps=67, dates=["1968-01-01"]), "fib": fib}), {})
red = P("The Red Skelton Show", False, 300, run=("1941-10-07", "1952-06-25"))
check("P-10 variant: the names differ by the and show", run({"rs": P("Red Skelton", eps=13, dates=["1945-12-25"]), "red": red}),
      {"rs": ("red", "variant")})
check("control: variant needs the larger program", run({"rs": P("Red Skelton", eps=400, dates=["1945-12-25"]), "red": red}), {})
check("control: variant outside the run", run({"rs": P("Red Skelton", eps=13, dates=["1962-01-01"]), "red": red}), {})
check("control: a LibriVox reading never folds", run({"lv": P("Red Skelton Show", eps=3, lv=True), "red": red}), {})
jb = P("Jack Benny Program", False, 950, run=("1932-05-02", "1974-12-29"), aliases=["Jack Benny"])
gn_dates = ["1947-10-05", "1947-11-09", "1948-06-27"]
item = "Jack Benny - Single Episodes - 1947-1948"
gn = P("Grape Nuts Program", False, 735, dates=gn_dates, items={item: 735}, feeds={item: {"gn"}})
check("P-10 item: archive.org items titled for one program, and a shared broadcast", run({"gn": gn, "jb": jb}, {("gn", "jb"): 374}),
      {"gn": ("jb", "item")})
check("control: item with no shared broadcast and a name that is not a season", run({"gn": gn, "jb": jb}), {})
gn_mixed = dict(gn, feeds={item: {"gn", "other"}})
check("control: an item feeding a third series is a compilation", run({"gn": gn_mixed, "jb": jb, "other": P("Other")}, {("gn", "jb"): 374}), {})
ha = P("High Adventure", False, 94, run=("1947-03-22", "1958-01-01"))
sa = P("High Adventure (South Africa)", False, 52, dates=["1950-01-01", "1951-01-01", "1952-01-01"],
       items={"High Adventure": 52}, feeds={"High Adventure": {"sa"}})
check("control: a name with a production qualifier stays its own", run({"sa": sa, "ha": ha}, {("sa", "ha"): 3}), {})
sh_season = P("Season 11 (9-7-47 to 5-30-48)", eps=27, dates=["1947-09-07", "1947-11-09", "1948-05-16"],
              items={"The Shadow Season 11 (9-7-47 to 5-30-48)": 27}, feeds={"The Shadow Season 11 (9-7-47 to 5-30-48)": {"s11"}})
shadow = P("The Shadow", False, 600, run=("1937-09-26", "1954-12-26"))
check("P-10 item: a season-named series whose items name the program", run({"s11": sh_season, "shadow": shadow}),
      {"s11": ("shadow", "item")})
gg = P("The Great Gildersleeve", False, 579, run=("1941-08-31", "1957-03-21"))
ggs = P("GG Season 05", eps=41, dates=["1945-09-02", "1946-06-09"])
check("P-10 initials: a program's initials and a season, with a shared broadcast", run({"ggs": ggs, "gg": gg}, {("ggs", "gg"): 10}),
      {"ggs": ("gg", "initials")})
check("control: initials with no shared broadcast", run({"ggs": ggs, "gg": gg}), {})
check("control: initials that two programs share", run({"ggs": ggs, "gg": gg, "gg2": P("Gene and Glenn", False, 600, run=("1941-01-01", "1950-01-01"))},
                                                        {("ggs", "gg"): 10, ("ggs", "gg2"): 1}), {})
esc = P("Escape", False, 378, run=("1947-07-07", "1954-09-25"))
check("P-10 prefix: a program's name and one of its episode titles, dated in its run",
      run({"eb": P("Escape the Birds", eps=1, dates=["1954-07-10"], titles=["The Birds"]), "esc": esc}), {"eb": ("esc", "prefix")})
check("control: prefix with no date", run({"eb": P("Escape the Birds", eps=1, titles=["The Birds"]), "esc": esc}), {})
check("control: prefix whose rest is not a title the series has",
      run({"gw": P("George Washington Whistler", eps=1, dates=["1932-02-22"], titles=["Whistling"]),
           "gw2": P("George Washington", False, 30, run=("1932-01-01", "1932-12-31"))}), {})

# ---- dissolve: more than half of an upload-named series' dated broadcasts are one show's ----
base = P("Let George Do It", False, 226, run=("1946-04-01", "1954-09-27"))
dated = [f"1950-{m:02d}-01" for m in range(1, 11)]
check("P-10 dissolve: more than half shared", DT.dissolve({"lg": P("Let George Do Itge Do It", eps=10, dates=dated), "base": base},
                                                          {("base", "lg"): 6}), {"lg": "base"})
check("control: half is not more than half", DT.dissolve({"lg": P("Let George Do Itge Do It", eps=10, dates=dated), "base": base},
                                                         {("base", "lg"): 5}), {})
check("control: a registry series is not dissolved by shared broadcasts",
      DT.dissolve({"lg": P("Let George Do Itge Do It", False, 10, dates=dated), "base": base}, {("base", "lg"): 9}), {})

# ---- same_day_in_series, merge_into's registry twin, arc ids ----
rows = {"j|1947-11-09": ("j", "1947-11-09", "Corner Drug Store", False, "j"),
        "g|1947-11-09": ("j", "1947-11-09", "The Corner Drug Store", False, "g"),
        "n|1939-09-03": ("news", "1939-09-03", "Chamberlain Declares War", False, "news"),
        "m|1939-09-03": ("news", "1939-09-03", "King George Speaks", False, "m")}
check("P-10 a moved episode on a date its new series holds, with a title one contains, is that broadcast",
      DT.same_day_in_series(rows, {"g|1947-11-09", "m|1939-09-03"}), {"g|1947-11-09": "j|1947-11-09"})
check("P-10 a reel fragment beside a registry program of the same name joins it",
      DT.merge_into({"whistler": {"name": "The Whistler", "cleaned": False, "librivox": False, "own": False, "eps": 784, "first": None,
                                  "last": None, "aliases": []},
                     "whistlerreel": {"name": "The Whistler", "cleaned": True, "librivox": False, "own": True, "eps": 2, "first": None,
                                      "last": None, "aliases": []}}), {"whistlerreel": "whistler"})
check("P-10 an arc whose first part was folded in keeps that part's whole id", ARCS.arc_id("tarzan", "goldenage|n1"), "tarzan|arc|goldenage|n1")
check("control: an arc's id is unchanged for the series' own part", ARCS.arc_id("tarzan", "tarzan|n1"), "tarzan|arc|n1")
check("chains collapse", DT.resolve_chains({"a": "b", "b": "c"}), {"a": "c", "b": "c"})

# ---- titles ----
dec = lambda t, s, air=None, num=None, tags=(): DT.decide_episode(t, s, air, num, tags)[0]
check("P-10 a reel track that is only the reel's name has no title", dec("Six Shooter.Gunsmoke Reel.t01", "Six Shooter"), None)
check("P-10 a reel track that names its series and one title keeps the title",
      dec("Suspense-The Pit and the Pendulum Reel.t01", "Suspense"), "The Pit and the Pendulum")
check("P-10 a 1942-xx-xx date keeps its year at the end", dec("1942-xx-xx RRGO Paul Revere", "1942 Radio News"), "RRGO Paul Revere (1942)")
check("P-10 the series' initials and number go", dec("OMB #001 1st Show", "Our Miss Brooks"), "1st Show")
check("P-10 initials with the article", dec("ADWJ #097 Strange Case of Joseph Cotton", "A Date with Judy"), "Strange Case of Joseph Cotton")
check("P-10 initials and an episode code", dec("STSA - S01E04 - Charlie Higgin's Play", "Something to Shout About"), "Charlie Higgin's Play")
check("P-10 initials, a date and a number go", dec("ADWJ 1945-02-06 #097 Strange Case of Joseph Cotton", "A Date with Judy", "1945-02-06"),
      "Strange Case of Joseph Cotton")
check("P-10 initials and a six-digit date code go", dec("OMB 102950 The Dancer", "Our Miss Brooks"), "The Dancer")
check("control: a bare number after the initials is the title's", dec("MLM 100 Shares of Stock", "My Little Margie"), "100 Shares of Stock")
check("control: a network in front stays", dec("NBC WEAF Lets Dance", "News Broadcasting Company"), "WEAF Lets Dance".join(["NBC ", ""]))
check("P-10 a recurring shelf code goes", dec("Trapped at 350 Ft (DM)", "Superman", "1941-05-12", None,
                                             DT.recurring_tags(["a (DM)", "b (DM)", "c (DM)"])), "Trapped at 350 Ft")
check("control: a code seen twice stays", DT.recurring_tags(["a (DM)", "b (DM)"]), set())
check("control: a network tail stays", DT.recurring_tags(["a (NBC)"] * 5), set())
check("P-10 a title that repeats the series' name is composed from the date",
      dec("Louella Parsons", "Louella Parsons", "1947-11-09"), "Louella Parsons, November 9, 1947")
check("control: with no date or number the name is the work's title", dec("Hercule Poirot's Christmas", "Hercule Poirot's Christmas"),
      "Hercule Poirot's Christmas")
check("P-10 a placeholder Production N is no title", dec("Production 3", "X Show", "1950-01-02"), "X Show, January 2, 1950")
check("P-10 the series' one-word name is the witness to its possessive", dec("Tarzans First Birthday", "Tarzan"), "Tarzan's First Birthday")
check("control: no possessive without a following word", dec("Tarzans", "Tarzan"), "Tarzans")
check("P-10 an xx placeholder in front goes", dec("xx Thoughts", "The Jean Shepherd Show"), "Thoughts")
check("P-10 a glued small word is split", PL.polish_title("Battle WithThe Apes"), "Battle with the Apes")
check("P-10 a recording-condition note goes", [PL.polish_title(t) for t in ("Hippo clipped", "Army Life (end clipped)",
                                                                            "Hobbies, Potatoes, etc., clippe", "clipped Earth Day")],
      ["Hippo", "Army Life", "Hobbies, Potatoes, etc.", "Earth Day"])
check("control: a title that is about clipping stays", PL.polish_title("The Clipped Wings"), "The Clipped Wings")
check("P-10 an uploader's combined-dates note goes", PL.polish_title("Big Town (Combines all dates)"), "Big Town")

# ---- copy labels ----
C = lambda **k: dict(dict(source=None, variant=None, partial=0, length_s=1800, kbps=64, uploaded="2015-01-01"), **k)
check("P-10 every copy has a label", None in PL.copy_labels([C(source="Old Time Radio Researchers"), C(), C(kbps=128)]), False)
check("P-10 a variant tells a copy apart", PL.copy_labels([C(), C(variant="AFRS")]), ["Best copy", "AFRS rebroadcast"])
check("P-10 a shared source name gets the fact that differs", PL.copy_labels([C(source="X"), C(source="X", length_s=2400)]),
      ["X, shorter copy", "X, longer copy"])
check("P-10 bitrate", PL.copy_labels([C(kbps=128), C(kbps=32)]), ["Higher quality (128 kbps)", "Lower quality (32 kbps)"])
check("P-10 upload year", PL.copy_labels([C(uploaded="2012-03-01"), C()]), ["Uploaded 2012", "Uploaded 2015"])
check("P-10 a partial copy", PL.copy_labels([C(), C(partial=1, length_s=600)]), ["Longer copy", "Partial copy"])
check("P-10 nothing differs: best copy, then another", PL.copy_labels([C(), C()]), ["Best copy", "Another copy"])
check("control: distinct source names are kept as they are", PL.copy_labels([C(source="A"), C(source="B")]), ["A", "B"])
check("control: one copy keeps its source name or none", (PL.copy_labels([C(source="A")]), PL.copy_labels([C()])), (["A"], [None]))

# ---- the guard over a real projection ----
real = os.environ.get("PROJECTION") or os.path.join(os.path.dirname(__file__), "..", "out", "publish", "ear-drama.sqlite")
if os.path.exists(real):
    d = sqlite3.connect(f"file:{real}?mode=ro", uri=True)
    names = dict(d.execute("SELECT key, name FROM series"))
    counts = dict(d.execute("SELECT key, episodes FROM series"))
    items = {}
    for eid, aid in d.execute("SELECT episode_id, archive_id FROM recordings"):
        items.setdefault(eid, set()).add(aid)
    rows = {eid: (sk, air, t, False, items.get(eid, set()), rights == "clean") for eid, sk, air, t, rights in
            d.execute("SELECT id, series_key, air_date, title, rights FROM episodes WHERE air_date IS NOT NULL")}
    info = {k: {"name": n, "own": False, "eps": counts[k]} for k, n in names.items()}
    left, _ = DT.same_broadcasts(rows, info)
    check("guard: no two series repeat each other's broadcasts (or share their item)", sorted(left.items())[:5], [])
    bare = d.execute("SELECT COUNT(*) FROM recordings WHERE label IS NULL AND episode_id IN "
                     "(SELECT episode_id FROM recordings GROUP BY episode_id HAVING COUNT(*) > 1)").fetchone()[0]
    check("guard: every copy of an episode with several has a label", bare, 0)
    raw = [(i, t) for i, t in d.execute("SELECT id, title FROM episodes")
           if DT.TRACK_TAIL.search(t or "") or DT.XX_DATE.match(t or "")]
    check("guard: no reel track tail or xx-date in a title", raw[:5], [])
    by = {}
    for sk, t in d.execute("SELECT series_key, title FROM episodes"):
        by.setdefault(sk, []).append(t)
    tags = sorted((sk, sorted(DT.recurring_tags(ts))) for sk, ts in by.items() if DT.recurring_tags(ts))
    check("guard: no series' titles carry a recurring shelf code", tags[:5], [])
elif os.environ.get("PROJECTION"):
    check("the projection named by PROJECTION exists", False, True)
else:
    print("  SKIP  guard: no projection at out/publish/ear-drama.sqlite (name one with PROJECTION)")

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
