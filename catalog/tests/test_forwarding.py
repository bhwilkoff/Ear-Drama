"""Forwarding ids (tools/forwarding.py, contract §3.5), each rule with its broken control.

    python3 tests/test_forwarding.py

Fixtures only: two builds of a small research database, the second with ids
changed the way a parse fix changes them. When out/publish/ear-drama.sqlite
exists, the forwarding rules also run over the real artifact.
"""
import json
import os
import sqlite3
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import build_projection as B
import forwarding as FW

ran = failed = 0


def check(name, got, want):
    global ran, failed
    ran += 1
    if got != want:
        failed += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


def prev(served, copies=None, aliases=None, tombstones=()):
    return {"served": set(served), "copies": copies or {}, "aliases": dict(aliases or {}),
            "tombstones": set(tombstones), "base": "sha-of-live"}


K = lambda n: ("item", f"{n}.mp3")

# --- successor: the recording decides, never the title -------------------------------
holders = {K(1): {"new"}, K(2): {"other"}, K(3): {"new", "other"}}
check("the episode now holding the default copy is the successor", FW.successor([K(1), K(2)], holders), "new")
check("a default copy no one serves: the holder of most of the other copies",
      FW.successor([K(9), K(1), K(3)], holders), "new")
check("control: a tie between holders is no successor", FW.successor([K(9), K(1), K(2)], holders), None)
check("a default copy two episodes hold: its holders' other copies decide",
      FW.successor([K(3), K(1)], holders), "new")
check("... whichever of them holds the other copies", FW.successor([K(3), K(2)], holders), "other")
check("control: no copy served anywhere is no successor", FW.successor([K(9)], holders), None)
check("control: an id with no copies is no successor", FW.successor([], holders), None)
check("a copy key reads the file back from the percent-encoded URL",
      FW.copy_key("OTRR_x", "https://archive.org/download/OTRR_x/Jack%20Benny%2043-11-21.mp3"),
      ("OTRR_x", "Jack Benny 43-11-21.mp3"))
check("a nested file keeps its folder", FW.copy_key("a", B.download_url("a", "Disc 1/Café.mp3")), ("a", "Disc 1/Café.mp3"))

# --- forward: fresh aliases, tombstones, carried and collapsed ------------------------
served = {"jb|1943-11-21", "jb|1944-01-02", "z"}
copies = {"jb|1943-11-21": [K(1)], "jb|1944-01-02": [K(2)], "z": [K(5)]}
p = prev({"jb|1921-03-11", "jb|1944-01-02", "gone", "y"},
         {"jb|1921-03-11": [K(1)], "jb|1944-01-02": [K(2)], "gone": [K(7)], "y": [K(5)]},
         aliases={"old-slug": "jb|1921-03-11", "older": "gone", "back": "jb|1944-01-02", "z": "y"},
         tombstones={"taken-down", "jb|1943-11-21"})
aliases, tombs, report = FW.forward(p, served, copies)
check("an id that left forwards to the episode holding its default copy", aliases.get("jb|1921-03-11"), "jb|1943-11-21")
check("an id whose copies no one serves is tombstoned", "gone" in tombs and "gone" not in aliases, True)
check("a chain collapses: old-slug -> 1921 -> 1943 is old-slug -> 1943", aliases.get("old-slug"), "jb|1943-11-21")
check("an alias whose end is tombstoned is tombstoned", ("older" in tombs, "older" in aliases), (True, False))
check("aliases carry forward", aliases.get("back"), "jb|1944-01-02")
check("a tombstone carries forward", "taken-down" in tombs, True)
check("an id served again sheds its tombstone", "jb|1943-11-21" in tombs, False)
check("an id served again sheds its alias", "z" in aliases, False)
check("a merge into an id that was already served (y -> z)", aliases.get("y"), "z")
check("the report counts what left", (report["left"], report["aliased"], report["tombstoned"], report["returned"]),
      (3, 2, 1, 2))
check("forwarding written by forward() breaks no rule", FW.violations(aliases, tombs, served), [])
check("a first publish forwards nothing", FW.forward(None, served, copies)[:2], ({}, set()))

# --- violations: every rule seen red -----------------------------------------------------
ok = {"a": "b"}
check("clean forwarding passes", FW.violations(ok, {"t"}, {"b"}), [])
check("control: a chain", any(v.startswith("chain") for v in FW.violations({"a": "b", "b": "c"}, set(), {"c"})), True)
check("control: a cycle", any(v.startswith("cycle") for v in FW.violations({"a": "b", "b": "a"}, set(), set())), True)
check("control: a self-forward", any(v.startswith("cycle") for v in FW.violations({"a": "a"}, set(), {"a"})), True)
check("control: an alias to a missing id", any(v.startswith("missing") for v in FW.violations(ok, set(), set())), True)
check("control: a tombstoned id served again",
      any(v.startswith("tombstone served") for v in FW.violations({}, {"t"}, {"t"})), True)
check("control: an aliased id that is served", any(v.startswith("served") for v in FW.violations(ok, set(), {"a", "b"})), True)
check("control: an id both aliased and tombstoned", any(v.startswith("both") for v in FW.violations(ok, {"a"}, {"b"})), True)

# --- inherit: the clean-only projection takes the served one's --------------------------
src = {"aliases": {"a": "clean-ep", "u": "unclaimed-ep"}, "tombstones": {"t"}}
check("an alias to an episode the narrower projection serves is kept", FW.inherit(src, {"clean-ep"})[0], {"a": "clean-ep"})
check("tombstones are inherited", FW.inherit(src, {"clean-ep"})[1], {"t"})

# --- check-base: computed against what is live now --------------------------------------
with tempfile.TemporaryDirectory() as t:
    def man(name, obj):
        path = os.path.join(t, name)
        json.dump(obj, open(path, "w"))
        return path
    live = man("live.json", {"sha256": {"zz": "abc"}})
    check("forwarding computed against the live catalog passes",
          FW.check_base(live, man("b1.json", {"forwarding": {"base": "abc"}})), None)
    check("control: another publish landed meanwhile",
          FW.check_base(live, man("b2.json", {"forwarding": {"base": "old"}})) is not None, True)
    check("a first publish with nothing live passes",
          FW.check_base(os.path.join(t, "absent.json"), man("b3.json", {"forwarding": {"base": None}})), None)
    check("control: a first-publish build when a catalog is live",
          FW.check_base(live, man("b4.json", {"forwarding": {"base": None}})) is not None, True)


# --- end to end: two builds, the second after a parse fix --------------------------------
def research(path, rows):
    d = sqlite3.connect(path)
    d.executescript("""
    CREATE TABLE series (key, name, genre, genres_otrr, is_librivox, first_date, last_date, networks);
    CREATE TABLE episodes (id, series_key, air_date, date_source, num, title, aka, state, rec_bucket, work_bucket,
        no_recommend, network, network_source, has_transcript);
    CREATE TABLE recordings (episode_id, rank, archive_id, file, format, kbps, length_s, variant, partial);
    CREATE TABLE episode_credits (episode_id, person_id, name, role, character);
    CREATE TABLE people (id, name, birth, death);
    CREATE TABLE sponsors (series_key, otrr_idp, sponsor, start, end, source);
    """)
    d.execute("INSERT INTO series VALUES ('jb','The Jack Benny Program','OTR-Comedy',NULL,0,NULL,NULL,NULL)")
    for eid, date, files, state in rows:
        d.execute("INSERT INTO episodes VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                  (eid, "jb", date, "filename", None, "Show", None, state, "rec_orphan_unclaimed", "work_none_found",
                   None, None, None, 0))
        for rank, f in enumerate(files):
            d.execute("INSERT INTO recordings VALUES (?,?,?,?,?,?,?,?,?)",
                      (eid, rank, "PDP_JackBenny", f, "VBR MP3", 64, 1700.0, None, 0))
    d.commit()
    d.close()


with tempfile.TemporaryDirectory() as t:
    before = [("jb|1921-03-11", "1921-03-11", ["Jack Benny Show, The 43-11-21.mp3"], "keep_unclaimed"),
              ("jb|1943-11-21", "1943-11-21", ["jb 1943-11-21 other copy.mp3"], "keep_unclaimed"),
              ("jb|1944-01-02", "1944-01-02", ["jb 44-01-02.mp3"], "keep_unclaimed"),
              ("jb|1945-05-06", "1945-05-06", ["jb 45-05-06.mp3"], "keep_unclaimed")]
    after = [("jb|1943-11-21", "1943-11-21", ["jb 1943-11-21 other copy.mp3", "Jack Benny Show, The 43-11-21.mp3"],
              "keep_unclaimed"),
             ("jb|1944-01-02", "1944-01-02", ["jb 44-01-02.mp3"], "keep_unclaimed"),
             ("jb|1945-05-06", "1945-05-06", ["jb 45-05-06.mp3"], "hide_claim")]
    research(os.path.join(t, "r1.sqlite"), before)
    research(os.path.join(t, "r2.sqlite"), after)
    B.build(os.path.join(t, "r1.sqlite"), os.path.join(t, "p1.sqlite"), scripts={})
    m = B.build(os.path.join(t, "r2.sqlite"), os.path.join(t, "p2.sqlite"), scripts={},
                previous=FW.open_projection(os.path.join(t, "p1.sqlite")))
    con = sqlite3.connect(os.path.join(t, "p2.sqlite"))
    check("built: the misdated id merges into the broadcast's existing id",
          dict(con.execute("SELECT old_id, new_id FROM episode_aliases")), {"jb|1921-03-11": "jb|1943-11-21"})
    check("built: a hidden episode is tombstoned",
          [r[0] for r in con.execute("SELECT id FROM episode_tombstones")], ["jb|1945-05-06"])
    con.close()
    check("built: the manifest counts them", (m["counts"]["aliases"], m["counts"]["tombstones"]), (1, 1))
    check("built: the manifest names no base for a plain-file previous", m["forwarding"]["base"], None)
    p2 = FW.open_projection(os.path.join(t, "p2.sqlite"))
    research(os.path.join(t, "r3.sqlite"), before)
    B.build(os.path.join(t, "r3.sqlite"), os.path.join(t, "p3.sqlite"), scripts={}, previous=p2)
    con = sqlite3.connect(os.path.join(t, "p3.sqlite"))
    check("built: a parse change reverted sheds the alias and the tombstone",
          (con.execute("SELECT COUNT(*) FROM episode_aliases").fetchone()[0],
           con.execute("SELECT COUNT(*) FROM episode_tombstones").fetchone()[0]), (0, 0))
    con.close()
    mem = sqlite3.connect(":memory:")
    mem.execute("CREATE TABLE episodes (id TEXT)")
    mem.execute("CREATE TABLE recordings (episode_id, rank, archive_id, url)")
    real_forward = FW.forward
    FW.forward = lambda *_: ({"a": "b", "b": "c"}, set(), {})
    try:
        B.write_forwarding(mem, None, None)
        refused = False
    except SystemExit:
        refused = True
    finally:
        FW.forward = real_forward
    check("control: forwarding that breaks a rule refuses the build", refused, True)

# --- the real artifact --------------------------------------------------------------------
REAL = os.environ.get("PROJECTION") or os.path.join(os.path.dirname(__file__), "..", "out", "publish", "ear-drama.sqlite")
if os.path.exists(REAL):
    con = sqlite3.connect(f"file:{REAL}?mode=ro", uri=True)
    r = FW.read_projection(con)
    con.close()
    check("real: the published forwarding breaks no rule", FW.violations(r["aliases"], r["tombstones"], r["served"])[:3], [])

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
