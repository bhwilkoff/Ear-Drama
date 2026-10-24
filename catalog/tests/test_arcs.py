"""Story arcs (tools/arcs.py) against Decision 067 and docs/CATALOG-CONTRACT.md §3.3.

    python3 tests/test_arcs.py
Fixture rows prove each rule, and every guard in `violations` is broken once and
seen to fail. A fixture research database runs through both builders, so the
served tables and the web's `arc` field are checked as published. When the
served projection exists (PROJECTION, else out/publish/ear-drama.sqlite), its
arcs (or arcs derived over it, for a build older than the tables) are checked for
shape only: the catalog's contents are never pinned.
"""
import json
import os
import sqlite3
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import arcs as A  # noqa: E402
import build_projection as B  # noqa: E402
import build_web_projection as W  # noqa: E402

ran = failed = 0


def check(name, got, want):
    global ran, failed
    ran += 1
    if got != want:
        failed += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


# --- parse: what a title says ----------------------------------------------------
check("parse: an episode mark", A.parse("The Molly K Matter - Ep 3"), ("the molly k matter", "episode", 3, None))
check("parse: a comma and Part", A.parse("Space Station of Danger, Part 2"), ("space station of danger", "part", 2, None))
check("parse: a stated count", A.parse("operation luna - episode 01 of 13 "), ("operation luna", "episode", 1, 13))
check("parse: a parenthesized part", A.parse("In Jail (Part 4)"), ("in jail", "part", 4, None))
check("parse: a chapter with its own name", A.parse("Chapter 2 - The Monk's Letter"), ("", "chapter", 2, None))
check("parse: Pt with no space", A.parse("The Molly K Matter pt5"), ("the molly k matter", "part", 5, None))
check("parse: a log date ahead of the title", A.parse("XX-XX - The Hermit (Part 1)"), ("the hermit", "part", 1, None))
check("control: no mark, no part", A.parse("Sorry, Wrong Number"), None)
check("control: two marks are ambiguous", A.parse("01 - Part 1 Chapter 1"), None)
check("control: a word that holds 'ep' is no mark", A.parse("The Deep 4"), None)
check("control: a part past its stated count", A.parse("Ep 6 of 5"), None)
check("control: part zero", A.parse("Part 0"), None)
check("control: a part with words after it that are not a subtitle", A.parse("Part 2 and more"), None)

# --- derive: when the evidence agrees with itself ----------------------------------
JD = [(f"jd|1955-10-{3 + i:02d}", "jd", f"1955-10-{3 + i:02d}", f"The Macormack Matter - Ep {i + 1}") for i in range(5)]
MOLLY = [(f"jd|1955-10-{10 + i:02d}", "jd", f"1955-10-{10 + i:02d}", f"The Molly K Matter - Ep {i + 1}")
         for i in range(5)] + [("jd|1955-10-15", "jd", "1955-10-15", "The Molly K Matter - Ep 5")]
ROWS = JD + MOLLY + [
    ("jd|1955-10-17", "jd", "1955-10-17", "The Chesapeake Fraud Matter - Ep 1"),
    ("jd|1955-10-18", "jd", "1955-10-18", "The Chesapeake Fraud Matter - Ep 2"),
    ("tc|1952-03-25", "tc", "1952-03-25", "Mission of Mercy, Part 2"),        # parts named out of date order
    ("tc|1952-03-27", "tc", "1952-03-27", "Mission of Mercy, Part 1"),
    ("sm|a", "sm", None, "Pillar of Fire - Pt 01"), ("sm|b", "sm", None, "Pillar of Fire - Pt 02"),
    ("sm|c", "sm", None, "Pillar of Fire - Pt 04"),                           # a gap: part 3 is lost
    ("sm|d", "sm", None, "Hunger Inc - Pt 01"), ("sm|e", "sm", None, "Hunger Inc - Pt 02"),
    ("uc|1", "uc", None, "episode 1"), ("uc|2", "uc", None, "episode 2"),     # numbers the series
    ("bd|1", "bd", None, "Barnaby Druthers Episode 1"), ("bd|2", "bd", None, "Barnaby Druthers Episode 2"),
    ("lv|1", "lv", None, "Chapter 1"), ("lv|2", "lv", None, "Chapter 2 - Dew of Morning"),
    ("lv|3", "lv", None, "Chapter 3"),
    ("wk|1950-01-01", "wk", "1950-01-01", "Long Story Part 1"),
    ("wk|1950-06-01", "wk", "1950-06-01", "Long Story Part 2"),               # five months apart: not one story
    ("one|1", "one", None, "Lonely Part 1"),
]
NAMES = {"bd": "Barnaby Druthers"}
arcs, report = A.derive(ROWS, NAMES)
by_title = {a["title"]: a for a in arcs}
check("derive: Johnny Dollar's five-part story, in order", by_title.get("The Macormack Matter", {}).get("parts"),
      [r[0] for r in JD])
check("derive: a two-part story", len(by_title.get("The Chesapeake Fraud Matter", {}).get("parts", [])), 2)
check("derive: an undated serial", by_title.get("Hunger Inc", {}).get("parts"), ["sm|d", "sm|e"])
check("derive: a book's chapters", by_title.get(None, {}).get("parts"), ["lv|1", "lv|2", "lv|3"])
check("control: a part twice makes no arc", "The Molly K Matter" in by_title, False)
check("control: parts against the calendar make no arc", "Mission of Mercy" in by_title, False)
check("control: a gap makes no arc", "Pillar of Fire" in by_title, False)
check("control: a bare episode number makes no arc", any(a["series"] in ("uc", "bd") for a in arcs), False)
check("control: parts months apart make no arc", "Long Story" in by_title, False)
check("control: one part makes no arc", "Lonely" in by_title, False)
check("derive: the report counts each refusal",
      {k: report[k] for k in ("repeated", "gap", "dates", "single", "arcs", "episodes")},
      {"repeated": 1, "gap": 1, "dates": 2, "single": 1, "arcs": 4, "episodes": 12})
check("derive: arcs ordered by series, then date", [a["series"] for a in arcs], ["jd", "jd", "lv", "sm"])
check("derive: every arc says how it was derived", {a["method"] for a in arcs}, {"titled-parts"})
check("derive: ids are stable and distinct", [a["id"] for a in arcs][:2], ["jd|arc|1955-10-03", "jd|arc|1955-10-17"])
nxt = A.next_arcs(arcs)
check("next story: the series' following arc", nxt["jd|arc|1955-10-03"], "jd|arc|1955-10-17")
check("next story: none after the last", nxt["jd|arc|1955-10-17"], None)
check("next story: never another series'", nxt[by_title["Hunger Inc"]["id"]], None)
check("control: an arc whose first part is not recommendable is never offered",
      A.next_arcs(arcs, lambda first: first != "jd|1955-10-17")["jd|arc|1955-10-03"], None)

served = {r[0]: (r[1], r[2]) for r in ROWS}
check("guards hold on the derived arcs", A.violations(arcs, served), [])
ok = by_title["The Macormack Matter"]
broken = {
    "one part": ([{**ok, "parts": ok["parts"][:1]}], "1 part"),
    "unserved": ([{**ok, "parts": ok["parts"] + ["jd|gone"]}], "is not served"),
    "another series": ([{**ok, "parts": ok["parts"] + ["tc|1952-03-25"]}], "another series"),
    "two arcs": ([ok, {**ok, "id": "jd|arc|x"}], "is in"),
    "repeated id": ([ok, {**ok, "parts": ["sm|d", "sm|e"], "series": "sm"}], "id repeated"),
    "out of order": ([{**ok, "parts": list(reversed(ok["parts"]))}], "out of date order"),
}
for name, (bad, needle) in broken.items():
    check(f"control: the guard catches {name}", any(needle in v for v in A.violations(bad, served)), True)


# --- both builders: the served tables and the web's field ----------------------------
def fixture(path):
    d = sqlite3.connect(path)
    d.executescript("""
    CREATE TABLE series (key, name, genre, genres_otrr, is_librivox, first_date, last_date, networks);
    CREATE TABLE episodes (id, series_key, air_date, date_source, num, title, aka, state, rec_bucket, work_bucket,
        no_recommend, network, network_source, has_transcript);
    CREATE TABLE recordings (episode_id, rank, archive_id, file, format, kbps, length_s, variant, partial);
    CREATE TABLE episode_credits (episode_id, person_id, name, role, character);
    CREATE TABLE people (id, name, birth, death);
    """)
    d.execute("INSERT INTO series VALUES ('jd','Yours Truly, Johnny Dollar',NULL,NULL,0,'1955','1956',NULL)")
    stories = [("Macormack", 3, "keep_clean"), ("Molly K", 10, "keep_clean"), ("Chesapeake", 17, "keep_unclaimed"),
               ("Alvin Summers", 24, "keep_clean")]
    for name, day, state in stories:
        for i in range(5):
            eid = f"jd|1955-10-{day + i:02d}"
            d.execute("INSERT INTO episodes VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                      (eid, "jd", eid[3:], "filename", None, f"The {name} Matter - Ep {i + 1}", None,
                       "keep_clean" if i == 0 else state,
                       "rec_orphan_unclaimed", "work_none_found", None, "CBS", None, 0))
            d.execute("INSERT INTO recordings VALUES (?,0,'jd55',?,'VBR MP3',64,900.0,NULL,0)", (eid, f"{eid[3:]}.mp3"))
    d.commit()
    d.close()


def served_arcs(path):
    c = sqlite3.connect(path)
    got = {aid: (n, nxt, [e for (e,) in c.execute("SELECT episode_id FROM arc_parts WHERE arc_id = ? ORDER BY part",
                                                  (aid,))])
           for aid, n, nxt in c.execute("SELECT id, parts, next_arc FROM arcs")}
    c.close()
    return got


with tempfile.TemporaryDirectory() as tmp:
    raw, dst, out = (os.path.join(tmp, n) for n in ("raw.sqlite", "served.sqlite", "web"))
    fixture(raw)
    m = B.build(raw, dst)
    got = served_arcs(dst)
    check("served: four stories, five parts each", sorted(v[0] for v in got.values()), [5, 5, 5, 5])
    check("served: next_arc chains the stories", got["jd|arc|1955-10-03"][1], "jd|arc|1955-10-10")
    check("served: the last story offers none", got["jd|arc|1955-10-24"][1], None)
    check("served: parts in order", got["jd|arc|1955-10-03"][2], [f"jd|1955-10-{d:02d}" for d in range(3, 8)])
    check("served: the manifest counts arcs and parts", (m["counts"]["arcs"], m["counts"]["arc_parts"]), (4, 20))
    q = sqlite3.connect(dst)
    q.execute("UPDATE episodes SET no_recommend = 'x' WHERE id = 'jd|1955-10-10'")
    q.commit()
    q.close()
    W.build(dst, out, include_unclaimed=True)

    def detail(eid):
        with open(os.path.join(out, "episodes", f"{W.shard_of(eid)}.json")) as f:
            row = json.load(f)[eid]
        return dict(zip(W.ARC_FIELDS, row[W.DETAIL_FIELDS.index("arc")])) if row[W.DETAIL_FIELDS.index("arc")] else None

    check("web: a part names the next part", detail("jd|1955-10-03"),
          {"id": "jd|arc|1955-10-03", "part": 1, "parts": 5, "next": "jd|1955-10-04", "nextStory": None})
    check("web: the last part names the next story's first part, skipping one not recommended",
          detail("jd|1955-10-07")["nextStory"], "jd|1955-10-17")
    W.build(dst, out)   # the gate closed: Chesapeake's parts 2-5 are unclaimed
    check("web: an arc the gate cuts is not served", detail("jd|1955-10-17"), None)
    check("web: and is never the next story", detail("jd|1955-10-14")["nextStory"], "jd|1955-10-24")
    with open(os.path.join(out, "manifest.json")) as f:
        man = json.load(f)
    check("web: the manifest names the arc fields", man["fields"]["arc"], W.ARC_FIELDS)
    check("web: and counts what it serves", (man["counts"]["arcs"], man["counts"]["arcEpisodes"]), (3, 15))

# --- the real artifact: shape only --------------------------------------------------
real = os.environ.get("PROJECTION") or os.path.join(os.path.dirname(__file__), "..", "out", "publish", "ear-drama.sqlite")
if os.path.exists(real):
    c = sqlite3.connect(f"file:{real}?mode=ro", uri=True)
    rows = list(c.execute("SELECT id, series_key, air_date, title FROM episodes"))
    tables = {r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
    if {"arcs", "arc_parts"} <= tables:
        found = {}
        for aid, sk, eid in c.execute("SELECT a.id, a.series_key, p.episode_id FROM arcs a JOIN arc_parts p "
                                      "ON p.arc_id = a.id ORDER BY a.rowid, p.part"):
            found.setdefault(aid, {"id": aid, "series": sk, "parts": []})["parts"].append(eid)
        found = list(found.values())
    else:
        found, _ = A.derive(rows, dict(c.execute("SELECT key, name FROM series")))
    c.close()
    check("real: the guards hold", A.violations(found, {r[0]: (r[1], r[2]) for r in rows})[:3], [])
    check("real: some arcs exist", len(found) > 0, True)
elif os.environ.get("PROJECTION"):
    check("the projection named by PROJECTION exists", False, True)
else:
    print("  SKIP  real artifact: out/publish/ear-drama.sqlite not built")

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
