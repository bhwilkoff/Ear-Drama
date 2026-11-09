"""A rights hide follows the work wherever an upload filed it (tools/same_work.py, tools/build_db.follow_work;
catalog DECISIONS 032, owner 2026-11-09: "Obviously The Shadow is still under copyright. All seasons should be hidden
if the copyright is still active.").

    python3 tests/test_same_work.py
    PROJECTION=out/publish/ear-drama.sqlite SOURCE=out/radio-catalog.sqlite python3 tests/test_same_work.py

Fixtures prove each rule and its refusal. The guard over a real build counts leaks and never pins a row: no served
episode is the broadcast (full date and title) of an episode the audit hid on a claim that follows the work, when its
series is upload-named or carries the hidden episode's item; and no served upload-named series carries a hidden work's
name with one of the work's titles or a date inside its run. Seen failing on the 2026-11-09 dry-run artifacts of the
unchanged tools ("Season 11 (9-7-47 to 5-30-48)", "20 best The Shadow", "The Shadow Recreations" served).
"""
import os
import sqlite3
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import audit_audio_rights as A
import same_work as SW

ran = failed = 0


def check(name, got, want):
    global ran, failed
    ran += 1
    if got != want:
        failed += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


HID = ("hide_claim", "rec_rights_holder_claim", "work_series_renewals")
OK = ("keep_unclaimed", "rec_orphan_unclaimed", "work_none_found")


def build(extra_series, extra_eps):
    series = {"shadow": {"name": "The Shadow", "own": False, "librivox": False}}
    series.update(extra_series)
    eps = {f"shadow|1947-09-{d:02d}": ("shadow", f"1947-09-{d:02d}", t, {"shadowitem"})
           for d, t in ((7, "The Phantom of the Lighthouse"), (14, "The Face of Murder"), (21, "Murder in the Death House"),
                        (28, "The Ghost Walks Again"))}
    eps["shadow|1938-02-13"] = ("shadow", "1938-02-13", "The House of Horror", {"shadowitem"})
    verdicts = {e: HID for e in eps}
    for e, row in extra_eps.items():
        eps[e] = row
        verdicts[e] = OK
    return eps, series, verdicts


# 1. broadcast: the same date and title in an upload-named series.
eps, series, ver = build({"season11": {"name": "Season 11 (9-7-47 to 5-30-48)", "own": True, "librivox": False}},
                         {"season11|1947-09-07": ("season11", "1947-09-07", "The Phantom of the Lighthouse", {"s11"})})
got = SW.find(eps, series, ver)
check("broadcast: an upload-named series' copy of a hidden broadcast follows it",
      {k: (v["key"], v["rule"], v["episode"]) for k, v in got.items()},
      {"season11|1947-09-07": ("shadow", "broadcast", "shadow|1947-09-07")})

# control: two registry programs, one coincidence, no shared item, no item naming the work: two productions.
eps, series, ver = build({"suspense": {"name": "Suspense", "own": False, "librivox": False}},
                         {"suspense|1947-09-07": ("suspense", "1947-09-07", "The Phantom of the Lighthouse", {"susp"})})
check("control: one coincidence between two registry programs is two productions", SW.find(eps, series, ver), {})

# the gate's other doors: a shared item, an item that names the work.
eps, series, ver = build({"houseofhorror": {"name": "House of Horror", "own": False, "librivox": False}},
                         {"houseofhorror|1938-02-13": ("houseofhorror", "1938-02-13", "The House Of Horror", {"ghost-of-radio-shadow"})})
check("broadcast: an item whose own name carries the work's opens the gate",
      sorted(SW.find(eps, series, ver, {"ghost-of-radio-shadow": "ghost of radio shadow 1938 02 13"})),
      ["houseofhorror|1938-02-13"])
check("control: the same row with an item that names nothing stays", SW.find(eps, series, ver, {"ghost-of-radio-shadow": "ghost of radio"}), {})

# 2. series: most of an upload-named series' dated episodes are the work's broadcasts: all of it.
rows = {f"season11|1947-09-{d:02d}": ("season11", f"1947-09-{d:02d}", t, {"s11"})
        for d, t in ((7, "The Phantom of the Lighthouse (Recreation 2019)"), (14, "The Face of Murder"), (21, "Murder in the Death House"))}
rows["season11|1947-10-05"] = ("season11", "1947-10-05", "A title no log has", {"s11"})
eps, series, ver = build({"season11": {"name": "Season 11", "own": True, "librivox": False}}, rows)
got = SW.find(eps, series, ver)
check("series: a season upload goes whole, a note in parentheses is not the title",
      sorted((k, v["rule"]) for k, v in got.items()),
      [("season11|1947-09-07", "broadcast"), ("season11|1947-09-14", "broadcast"), ("season11|1947-09-21", "broadcast"),
       ("season11|1947-10-05", "series")])

# 3. named: the work's name as whole words, corroborated by a title, a date in its run or the program-title form.
eps, series, ver = build({"best": {"name": "20 best The Shadow", "own": True, "librivox": False}},
                         {"best|tface": ("best", None, "The Face of Murder", {"b"}), "best|tx": ("best", None, "Something Else", {"b"})})
check("named: a series carrying the work's name and one of its titles goes whole",
      sorted((k, v["rule"]) for k, v in SW.find(eps, series, ver).items()), [("best|tface", "named"), ("best|tx", "named")])
eps, series, ver = build({"pulp": {"name": "The Shadow The Golden Master Pulp Audiobook", "own": True, "librivox": False}},
                         {"pulp|x": ("pulp", None, "The Shadow - The Golden Master (Pulp Audiobook)", {"p"})})
check("named: the program-and-title form is the program's", sorted(SW.find(eps, series, ver)), ["pulp|x"])
for name in ("The Shadow of a Gunman", "Tales from the Shadows", "Charity Blackstock Shadow of Murder"):
    eps, series, ver = build({"x": {"name": name, "own": True, "librivox": False}},
                             {"x|1": ("x", "1947-09-14", "The Face of Murder", {"x"})})
    check(f"control: {name!r} is another work", {k for k, v in SW.find(eps, series, ver).items() if v["rule"] == "named"}, set())
eps, series, ver = build({"x": {"name": "The Shadow Sings", "own": True, "librivox": False}},
                         {"x|1": ("x", None, "A Song", {"x"})})
check("control: the name alone, with no title, date or program-and-title form, is not evidence", SW.find(eps, series, ver), {})
eps, series, ver = build({"librivox1": {"name": "The Shadow", "own": False, "librivox": True}},
                         {"librivox1|s1": ("librivox1", None, "The Face of Murder", {"lv"})})
check("control: a LibriVox project reads a public-domain text and is never caught", SW.find(eps, series, ver), {})
eps, series, ver = build({"x": {"name": "20 best The Shadow", "own": False, "librivox": False}},
                         {"x|1": ("x", None, "The Face of Murder", {"x"})})
check("control: a registry program's own name is never read as an upload's", SW.find(eps, series, ver), {})

# A work is hidden on a claim that follows it; a post-1972 or foreign series is one production, not a work.
eps, series, ver = build({"season11": {"name": "Season 11", "own": True, "librivox": False}},
                         {"season11|1947-09-07": ("season11", "1947-09-07", "The Phantom of the Lighthouse", {"s11"})})
ver = {e: (("hide_claim", "rec_foreign_origin", "work_none_found") if v == HID else v) for e, v in ver.items()}
check("control: a foreign producer's broadcast is judged where it stands", SW.find(eps, series, ver), {})
check("FOLLOW holds only claim buckets the audit has",
      SW.FOLLOW <= set(A.REC_STATE) | A.WORK_HIDES and not SW.FOLLOW & {"rec_post_1972", "rec_foreign_origin"}, True)

# ---- the guard over a real build ----
real = os.environ.get("PROJECTION") or os.path.join(os.path.dirname(__file__), "..", "out", "publish", "ear-drama.sqlite")
src = os.environ.get("SOURCE") or os.path.join(os.path.dirname(__file__), "..", "out", "radio-catalog.sqlite")
if os.path.exists(real) and os.path.exists(src):
    d = sqlite3.connect(f"file:{real}?mode=ro", uri=True)
    s = sqlite3.connect(f"file:{src}?mode=ro", uri=True)
    own = {k for (k,) in s.execute("SELECT key FROM series WHERE COALESCE(in_spine, 0) = 0 AND otrr_programs IS NULL "
                                   "AND COALESCE(is_librivox, 0) = 0")}
    snames = dict(s.execute("SELECT key, name FROM series"))
    hitems = {}
    for eid, aid in s.execute("SELECT episode_id, archive_id FROM recordings"):
        hitems.setdefault(eid, set()).add(aid)
    hidden, works, total = {}, {}, {}
    for eid, sk, air, t, rb, wb in s.execute(
            "SELECT id, series_key, air_date, title, rec_bucket, work_bucket FROM episodes WHERE state = 'hide_claim'"):
        if rb in SW.FOLLOW or wb in SW.FOLLOW:
            k = SW.title_key(t, snames.get(sk))
            if air and len(air) == 10 and k:
                hidden.setdefault((air, k), []).append((sk, eid))
            if rb in SW.SERIES_WIDE or wb in SW.SERIES_WIDE:
                works.setdefault(sk, []).append((air, k))
    for sk, n in s.execute("SELECT series_key, COUNT(*) FROM episodes GROUP BY series_key"):
        total[sk] = n
    works = {k: v for k, v in works.items() if len(v) * 2 > total.get(k, 0)}
    pitems = {}
    for eid, aid in d.execute("SELECT episode_id, archive_id FROM recordings"):
        pitems.setdefault(eid, set()).add(aid)
    pnames = dict(d.execute("SELECT key, name FROM series"))
    leaks, by_series = [], {}
    for eid, sk, air, t in d.execute("SELECT id, series_key, air_date, title FROM episodes"):
        by_series.setdefault(sk, []).append((air, t))
        k = SW.title_key(t)
        for hk, h in hidden.get((air, k), ()) if air and k else ():
            if hk != sk and k == SW.title_key(t, snames.get(hk)) and (sk in own or pitems.get(eid, set()) & hitems.get(h, set())):
                leaks.append((sk, air, t, hk))
                break
    check("guard: no served episode is the broadcast of an episode hidden on a claim that follows the work",
          (len(leaks), leaks[:5]), (0, []))
    named = []
    for sk, rows in sorted(by_series.items()):
        if sk not in own:
            continue
        for hk, wrows in sorted(works.items()):
            if not SW.name_carries(pnames.get(sk), snames.get(hk)):
                continue
            ds = sorted(a for a, _k in wrows if a and len(a) == 10)
            wt = {k for _a, k in wrows if k}
            if any(SW.title_key(t, pnames.get(sk), snames.get(hk)) in wt or (ds and a and len(a) == 10 and ds[0] <= a <= ds[-1])
                   for a, t in rows):
                named.append((pnames.get(sk), snames.get(hk)))
                break
    check("guard: no served upload-named series carries a hidden work's name and its titles or dates", named[:5], [])
elif os.environ.get("PROJECTION"):
    check("the build named by PROJECTION and SOURCE exists", False, True)
else:
    print("  SKIP  guard: no build at out/publish/ear-drama.sqlite and out/radio-catalog.sqlite (name them)")

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
