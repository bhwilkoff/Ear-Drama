"""An episode's `script` link (tools/episode_scripts.py, Decision 068): set only where the
match is series + date + title, and the script is in the castable bundle with a castable bucket.

    python3 tests/test_episode_scripts.py
A fixture proves each rule; when out/publish/ear-drama.sqlite exists, the guard also runs
over every linked row of the real artifact against the real bundle.
Broken controls, 2026-10-24, each run against a mutated copy of episode_scripts.py:
    links() skips the bundle test                 9 failed
    title_agrees() returns True for any pair     11 failed
    check() returns []                            1 failed
"""
import json
import os
import sqlite3
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import build_projection as B
import build_web_projection as W
import episode_scripts as E

ran = failed = 0


def check(name, got, want):
    global ran, failed
    ran += 1
    if got != want:
        failed += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


# --- titles ------------------------------------------------------------------------
check("equal titles agree", E.title_agrees("The Scrap of Lace", "The Scrap Of Lace"), True)
check("punctuation does not matter", E.title_agrees("Accident According to Plan", "Accident -- According to Plan"), True)
check("the shorter's words inside the longer", E.title_agrees("Execution of Dillinger", "The Execution Of John Dillinger"), True)
check("a bracketed note is dropped", E.title_agrees("Poltergeist", "Poltergeist (Gravestone)"), True)
check("control: different stories do not agree", E.title_agrees("Madame La Gimp", "Pick a Winner"), False)
check("control: one shared word is not enough", E.title_agrees("Romance", "Romance of Helen Trent"), False)
check("control: a number is not a title", E.title_agrees("Episode 170", "CaptainMidnight-Ep0004"), False)
check("control: an empty title agrees with nothing", E.title_agrees("", "Anything"), False)


def bundle_entry(sid, bucket, kind="radio"):
    return {"id": sid, "kind": kind, "title": sid, "rights": {"bucket": bucket, "evidence": []}, "roles": [],
            "lines": []}


BUNDLE = {e["id"]: e for e in (bundle_entry("grw-A1", "script_registered_not_renewed"),
                                bundle_entry("grw-A2", "script_registered_not_renewed"),
                                bundle_entry("grw-H1", "script_renewed"))}
TERMS_ASK = {"Generic Radio Workshop": {"reuse": "ask"}}


def research(path):
    d = sqlite3.connect(path)
    d.executescript("""
    CREATE TABLE series (key, name, genre, genres_otrr, is_librivox, first_date, last_date, networks);
    CREATE TABLE episodes (id, series_key, air_date, date_source, num, title, aka, state, rec_bucket, work_bucket,
        no_recommend, network, network_source, has_transcript);
    CREATE TABLE recordings (episode_id, rank, archive_id, file, format, kbps, length_s, variant, partial);
    CREATE TABLE episode_credits (episode_id, person_id, name, role, character);
    CREATE TABLE people (id, name, birth, death);
    CREATE TABLE scripts (id, source, series_key, air_date, title, url, text_cached, episode_id, display);
    """)
    d.executemany("INSERT INTO series VALUES (?,?,?,?,?,?,?,?)", [
        ("fibber", "Fibber McGee and Molly", "OTR-Comedy", None, 0, "1947-05-06", "1949-03-01", None)])
    eps = [("fibber|1947-05-06", "1947-05-06", "Good Grammar", "keep_unclaimed"),        # linked
           ("fibber|1947-05-13", "1947-05-13", "The Census Taker", "keep_clean"),        # wrong title
           ("fibber|1947-05-20", "1947-05-20", "Fibber Paints the Fence", "keep_clean"), # renewed script
           ("fibber|1947-05-27", "1947-05-27", "Molly's Hat", "keep_clean"),             # not in bundle
           ("fibber|1947-06-03", "1947-06-03", "Summer Plans", "hide_claim"),            # not served
           ("fibber|1947-06-10", "1947-06-10", "The Big Bet", "keep_clean")]             # date differs
    d.executemany("INSERT INTO episodes VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)", [
        (i, "fibber", dt, "filename", None, t, None, st, "rec_orphan_unclaimed", "work_none_found", None, None, None,
         0) for i, dt, t, st in eps])
    d.executemany("INSERT INTO recordings VALUES (?,?,?,?,?,?,?,?,?)", [
        (i, 0, "fibber47", f"{n}.mp3", "VBR MP3", 64, 1700.0, None, 0) for n, (i, *_r) in enumerate(eps)])
    d.executemany("INSERT INTO scripts VALUES (?,?,?,?,?,?,?,?,?)", [
        ("A1", "genericradio.com", "fibber", "1947-05-06", "Good Grammar", "u", 1, "fibber|1947-05-06", "link"),
        ("A2", "genericradio.com", "fibber", "1947-05-13", "Fibber Needs Glasses", "u", 1, "fibber|1947-05-13", "link"),
        ("H1", "genericradio.com", "fibber", "1947-05-20", "Fibber Paints the Fence", "u", 1, "fibber|1947-05-20", "link"),
        ("N1", "genericradio.com", "fibber", "1947-05-27", "Molly's Hat", "u", 1, "fibber|1947-05-27", "link"),
        ("S1", "genericradio.com", "fibber", "1947-06-03", "Summer Plans", "u", 1, "fibber|1947-06-03", "link"),
        ("D1", "genericradio.com", "fibber", "1947-06-11", "The Big Bet", "u", 1, "fibber|1947-06-10", "link")])
    d.commit()
    return d


with tempfile.TemporaryDirectory() as tmp:
    src = os.path.join(tmp, "research.sqlite")
    s = research(src)
    served = {r[0] for r in s.execute("SELECT id FROM episodes WHERE state LIKE 'keep%'")}
    got, report = E.links(s, served, BUNDLE, TERMS_ASK)
    check("only the series + date + title match with a castable bundled script is linked", got,
          {"fibber|1947-05-06": "grw-A1"})
    check("a castable script on the wrong episode's title is not linked", "fibber|1947-05-13" in got, False)
    check("a renewed script is never linked", "fibber|1947-05-20" in got, False)
    check("a script missing from the bundle waits on its source", report["awaiting_permission"], 2)
    check("the disagreeing title is counted", report["title_disagrees"], 1)
    check("control: no bundle, no links", E.links(s, served, {}, TERMS_ASK)[0], {})
    s.close()

    dst = os.path.join(tmp, "ear-drama.sqlite")
    B.build(src, dst, scripts=BUNDLE)
    p = sqlite3.connect(dst)
    check("the projection carries the link", dict(p.execute("SELECT id, script FROM episodes WHERE script IS NOT NULL")),
          {"fibber|1947-05-06": "grw-A1"})
    check("the manifest counts it", json.loads(p.execute("SELECT value FROM meta WHERE key = 'counts'").fetchone()[0])
          ["scripts"], 1)
    check("guard: every link is castable and bundled", E.check(p, BUNDLE), [])
    p.close()

    # Negative controls for the guard: a link to a script the bundle lacks, and one whose bucket hides it.
    p = sqlite3.connect(dst)
    p.execute("UPDATE episodes SET script = 'grw-Z9' WHERE id = 'fibber|1947-05-13'")
    p.execute("UPDATE episodes SET script = 'grw-H1' WHERE id = 'fibber|1947-05-20'")
    check("guard control: unbundled and hidden links are caught", sorted(E.check(p, BUNDLE)),
          [("fibber|1947-05-13", "grw-Z9"), ("fibber|1947-05-20", "grw-H1")])
    p.close()

    B.build(src, dst, scripts=BUNDLE)
    web = os.path.join(tmp, "web")
    W.build(dst, web, include_unclaimed=True)
    m = json.load(open(os.path.join(web, "manifest.json")))
    idx = json.load(open(os.path.join(web, "index", "series.json")))
    row = dict(zip(idx["fields"], idx["rows"][0]))
    check("the web index counts a series' scripted episodes", row["scripts"], 1)
    eid = "fibber|1947-05-06"
    shard = json.load(open(os.path.join(web, "episodes", W.shard_of(eid) + ".json")))
    check("web detail carries the script id", dict(zip(m["fields"]["detail"], shard[eid]))["script"], "grw-A1")
    other = "fibber|1947-05-13"
    shard = json.load(open(os.path.join(web, "episodes", W.shard_of(other) + ".json")))
    check("control: an unlinked episode's script is null", dict(zip(m["fields"]["detail"], shard[other]))["script"],
          None)

# --- the real artifact, shape only ------------------------------------------------------
real = os.path.join(os.path.dirname(__file__), "..", "out", "publish", "ear-drama.sqlite")
if os.path.exists(real):
    p = sqlite3.connect(f"file:{real}?mode=ro", uri=True)
    check("real projection: every linked script is castable and bundled", E.check(p, E.load_bundle()), [])
    p.close()
check("the real bundle's linked kinds are castable buckets only",
      all(E.castable_entry(b) for b in E.load_bundle().values()), True)

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
