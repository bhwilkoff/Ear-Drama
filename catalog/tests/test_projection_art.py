"""Portraits in the projections (tools/art_policy.py, contract §3.3): nothing is served
without its own evidence, and a series' or episode's face is a served portrait.

    python3 tests/test_projection_art.py
    PROJECTION=path/ear-drama.sqlite SOURCE=path/radio-catalog.sqlite python3 tests/test_projection_art.py

A fixture proves each rule beside a control that must produce the opposite
verdict; when out/publish/ear-drama.sqlite exists, the contract runs over every
row of it, and when the research database exists too, every published image is
traced back to its source rows and judged again by the same predicate.

Mutation controls, each seen to fail this suite on 2026-10-24: `served` accepting
the undated basis (dated_match returning True for it); `served` ignoring
found_via; `credit` returning None for cc_by; the web builder writing a credit's
art for a person with no portrait.
"""
import json
import os
import sqlite3
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import art_policy as AP
import build_projection as B
import build_web_projection as W

ran = failed = 0


def check(name, got, want):
    global ran, failed
    ran += 1
    if got != want:
        failed += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


CONTRACT = {
    "every image's class is served": "SELECT COUNT(*) FROM art WHERE license NOT IN ({})".format(
        ",".join(f"'{c}'" for c in AP.SERVED_CLASSES)),
    "an image owes a credit exactly when its license does": "SELECT COUNT(*) FROM art WHERE (credit IS NOT NULL) != "
        "(license IN ({}))".format(",".join(f"'{c}'" for c in AP.NEEDS_CREDIT)),
    "a credit names an author": "SELECT COUNT(*) FROM art WHERE credit IS NOT NULL AND (author IS NULL OR author = '')",
    "every image is a Commons file with its file page": "SELECT COUNT(*) FROM art WHERE url NOT LIKE '{}%' OR "
        "evidence_url NOT LIKE '{}%'".format(AP.FILEPATH, AP.FILE_PAGE),
    "no image is published that no person wears": "SELECT COUNT(*) FROM art a WHERE NOT EXISTS "
        "(SELECT 1 FROM people p WHERE p.portrait = a.id)",
    "every portrait is a published image": "SELECT COUNT(*) FROM people p WHERE portrait IS NOT NULL AND NOT EXISTS "
        "(SELECT 1 FROM art a WHERE a.id = p.portrait)",
    "a series' star wears a portrait": "SELECT COUNT(*) FROM series s WHERE star IS NOT NULL AND NOT EXISTS "
        "(SELECT 1 FROM people p WHERE p.id = s.star AND p.portrait IS NOT NULL)",
    "an episode's star wears a portrait and is credited in it": "SELECT COUNT(*) FROM episodes e WHERE star IS NOT NULL "
        "AND NOT EXISTS (SELECT 1 FROM people p JOIN credits c ON c.person_id = p.id WHERE p.id = e.star "
        "AND c.episode_id = e.id AND p.portrait IS NOT NULL)",
}


def violations(db):
    c = sqlite3.connect(db)
    out = {name: c.execute(sql).fetchone()[0] for name, sql in CONTRACT.items()}
    c.close()
    return {k: v for k, v in out.items() if v}


def retrace(projection, source):
    """Every published image traced to its source rows and judged again: the file
    names (from the evidence URL) whose person rows no longer pass `served`."""
    p = sqlite3.connect(projection)
    published = {(pid, ev) for pid, ev in p.execute(
        "SELECT p.id, a.evidence_url FROM people p JOIN art a ON a.id = p.portrait")}
    p.close()
    s = sqlite3.connect(f"file:{source}?mode=ro", uri=True)
    ok = set()
    for pid, file, cls, usable, via, author, basis in s.execute(
            "SELECT a.person_id, a.file, a.license_class, a.usable, a.found_via, a.author, w.basis "
            "FROM people_art a JOIN people_wikidata w ON w.person_id = a.person_id"):
        if AP.served(basis, cls, usable, via, author):
            ok.add((pid, AP.evidence_url(file)))
    s.close()
    return sorted(published - ok)


# --- the predicate ---------------------------------------------------------------
import enrich_people_art as E
check("the served classes are exactly the ones the license reader calls usable", set(AP.SERVED_CLASSES), E.USABLE)
DATED = "name+birth_day+death_day"
check("served: a dated match's own PD image", AP.served(DATED, "pd_us", 1, "wikidata:P18", None), True)
check("control: the undated rule is never served", AP.served(AP.UNDATED_BASIS, "pd_us", 1, "wikidata:P18", None), False)
check("control: an unmatched person is never served", AP.served("ambiguous_dated", "pd_us", 1, "wikidata:P18", None), False)
check("control: a depicts file is never served", AP.served(DATED, "pd_us", 1, "commons:depicts", None), False)
check("control: 'no known restrictions' is never served",
      AP.served(DATED, "no_known_restrictions", 0, "wikidata:P18", None), False)
check("control: a usable flag cannot rescue an unserved class", AP.served(DATED, "pd_source_only", 1, "wikidata:P18", None),
      False)
check("served: CC BY with its author", AP.served(DATED, "cc_by", 1, "wikidata:P18", "Alan Light"), True)
check("control: CC BY with no author to credit", AP.served(DATED, "cc_by_sa", 1, "wikidata:P18", "Unknown"), False)
check("credit: author and versioned license", AP.credit("cc_by_sa", "Cc-by-sa-3.0-de", "Jomarose"), "Jomarose, CC BY-SA 3.0")
check("credit: the LA Times archive is CC BY 4.0", AP.credit("cc_by", "LATimes UCLA", "Los Angeles Times"),
      "Los Angeles Times, CC BY 4.0")
check("control: a public-domain image owes no credit", AP.credit("pd_us", "PD-US-no notice", "NBC"), None)
check("pick: the most permissive class first",
      AP.pick([("b.jpg", "cc_by", "cc-by-2.0", "X"), ("a.jpg", "pd_us", "PD-US", None)])[0], "a.jpg")
check("url: spaces become underscores, the rest is quoted", AP.image_url("Jack Benny (1938 NBC Photo).jpg"),
      "https://commons.wikimedia.org/wiki/Special:FilePath/Jack_Benny_%281938_NBC_Photo%29.jpg")

FACES = {"p1", "p2", "p3"}
eps = {f"e{i}": [("p1", "cast")] for i in range(3)} | {"e3": [("p2", "cast")], "e4": [("p3", "writer")]}
check("star: the face heard on most episodes", AP.series_star(eps, FACES), "p1")
check("control: a writer is never the face", AP.series_star({"e4": [("p3", "writer")]} | {f"x{i}": [("p3", "writer")]
                                                                                           for i in range(4)}, FACES), None)
anthology = {f"e{i}": [(f"g{i}", "cast")] for i in range(9)} | {f"h{i}": [("p1", "cast")] for i in range(3)}
check("control: a guest of three weeks in twelve is not an anthology's face",
      AP.series_star(anthology, FACES | {f"g{i}" for i in range(9)}), None)
check("control: two episodes are too few", AP.series_star({"a": [("p1", "cast")], "b": [("p1", "cast")]}, FACES), None)
check("episode star: the series' star when heard", AP.episode_star([("p2", "cast"), ("p1", "host")], FACES, "p1"), "p1")
check("episode star: else the first face on the air",
      AP.episode_star([("p3", "writer"), ("p9", "cast"), ("p2", "cast")], FACES, "p1"), "p2")
check("control: no face, no star", AP.episode_star([("p9", "cast")], FACES, "p1"), None)


# --- the builders over a fixture ---------------------------------------------------
def fixture(path):
    d = sqlite3.connect(path)
    d.executescript("""
    CREATE TABLE series (key, name, genre, genres_otrr, is_librivox, first_date, last_date, networks);
    CREATE TABLE episodes (id, series_key, air_date, date_source, num, title, aka, state, rec_bucket, work_bucket,
        no_recommend, network, network_source, has_transcript);
    CREATE TABLE recordings (episode_id, rank, archive_id, file, format, kbps, length_s, variant, partial);
    CREATE TABLE episode_credits (episode_id, person_id, name, role, character);
    CREATE TABLE people (id, name, birth, death);
    CREATE TABLE people_wikidata (person_id, qid, basis);
    CREATE TABLE people_art (person_id, qid, file, found_via, license_class, usable, template, obligations, author);
    """)
    d.execute("INSERT INTO series VALUES ('benny','Jack Benny Program',NULL,'[\"Comedy\"]',0,'1932','1955',NULL)")
    people = [("p1", "Jack Benny", DATED), ("p2", "Mary Livingstone", AP.UNDATED_BASIS),
              ("p3", "Phil Harris", DATED), ("p4", "Dennis Day", DATED), ("p5", "Don Wilson", DATED)]
    for i in range(4):
        eid = f"benny|1946-0{i + 1}-06"
        d.execute("INSERT INTO episodes VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                  (eid, "benny", eid[6:], "filename", i, f"Show {i}", None, "keep_clean", "rec_pd_published_age",
                   "work_none_found", None, "NBC", "otrr", 0))
        d.execute("INSERT INTO recordings VALUES (?,?,?,?,?,?,?,?,?)", (eid, 0, "benny", f"{i}.mp3", "MP3", 64, 1700, None, 0))
        for pid, name, _ in people:
            d.execute("INSERT INTO episode_credits VALUES (?,?,?,?,?)", (eid, pid, name, "cast", None))
    d.executemany("INSERT INTO people VALUES (?,?,NULL,NULL)", [(p, n) for p, n, _ in people])
    d.executemany("INSERT INTO people_wikidata VALUES (?,?,?)", [(p, "Q" + p, b) for p, _, b in people])
    d.executemany("INSERT INTO people_art VALUES (?,?,?,?,?,?,?,?,?)", [
        ("p1", "Qp1", "Jack Benny 1938.jpg", "wikidata:P18", "pd_us", 1, "PD-US-no notice", None, "NBC"),
        ("p1", "Qp1", "Benny and Allen.jpg", "commons:depicts", "pd_us", 1, "PD-US", None, None),
        ("p2", "Qp2", "Mary.jpg", "wikidata:P18", "pd_us", 1, "PD-US", None, None),
        ("p3", "Qp3", "Phil Harris.jpg", "wikidata:P18", "cc_by", 1, "cc-by-2.0", "attribution", "Alan Light"),
        ("p4", "Qp4", "Dennis.jpg", "wikidata:P18", "no_known_restrictions", 0, "PD-Bain", None, None),
        ("p5", "Qp5", "Don.jpg", "wikidata:P18", "cc_by_sa", 1, "cc-by-sa-3.0", "attribution, share-alike", "")])
    d.commit()
    d.close()


with tempfile.TemporaryDirectory() as tmp:
    src, dst, web = (os.path.join(tmp, n) for n in ("src.sqlite", "out.sqlite", "web"))
    fixture(src)
    meta = B.build(src, dst)
    c = sqlite3.connect(dst)
    worn = dict(c.execute("SELECT p.id, a.evidence_url FROM people p JOIN art a ON a.id = p.portrait"))
    check("served: only the dated, own-image, evidenced portraits", sorted(worn), ["p1", "p3"])
    check("the person's own image, not the group photograph", worn["p1"], AP.evidence_url("Jack Benny 1938.jpg"))
    check("the CC BY image carries its credit", c.execute("SELECT credit FROM art a JOIN people p ON p.portrait = a.id "
                                                          "WHERE p.id = 'p3'").fetchone()[0], "Alan Light, CC BY 2.0")
    check("the series' face", c.execute("SELECT star FROM series").fetchone()[0], "p1")
    check("every episode wears its series' star", {r[0] for r in c.execute("SELECT star FROM episodes")}, {"p1"})
    check("the manifest counts what it served", (meta["counts"]["art"], meta["counts"]["portraits"],
                                                 meta["counts"]["seriesStars"]), (2, 2, 1))
    c.close()
    check("the contract holds on the fixture", violations(dst), {})
    check("retrace: every published image passes the predicate again", retrace(dst, src), [])

    W.build(dst, web)
    with open(os.path.join(web, "index", "series.json")) as f:
        idx = json.load(f)
    row = dict(zip(idx["fields"], idx["rows"][0]))
    check("web: the series row names its face and carries the image",
          (row["star"], row["art"][0], row["art"][3]), ("Jack Benny", AP.image_url("Jack Benny 1938.jpg"), None))
    shard = {}
    for n in os.listdir(os.path.join(web, "episodes")):
        with open(os.path.join(web, "episodes", n)) as f:
            shard.update(json.load(f))
    m = json.load(open(os.path.join(web, "manifest.json")))
    detail = dict(zip(m["fields"]["detail"], next(iter(shard.values()))))
    credits = [dict(zip(m["fields"]["credit"], c)) for c in detail["credits"]]
    check("web: a credit carries its person's portrait, and only a served one",
          {c["person"]: bool(c["art"]) for c in credits}, {"p1": True, "p2": False, "p3": True, "p4": False, "p5": False})
    check("web: the CC credit travels with the image",
          next(c["art"][3] for c in credits if c["person"] == "p3"), "Alan Light, CC BY 2.0")
    check("web: Detail names the episode's face", detail["star"], "p1")
    check("web: the art fields are published", m["fields"]["art"], W.ART_FIELDS)

    # Broken control: a projection that serves an undated match's image must fail both checks.
    bad = sqlite3.connect(dst)
    bad.execute("INSERT INTO art VALUES (9, ?, NULL, NULL, 'pd_us', NULL, NULL, ?)",
                (AP.image_url("Mary.jpg"), AP.evidence_url("Mary.jpg")))
    bad.execute("UPDATE people SET portrait = 9 WHERE id = 'p2'")
    bad.execute("UPDATE art SET credit = NULL WHERE license = 'cc_by'")
    bad.commit()
    bad.close()
    check("control: the contract catches a dropped credit", sorted(violations(dst)),
          ["an image owes a credit exactly when its license does"])
    check("control: retrace catches an undated match's portrait", retrace(dst, src), [("p2", AP.evidence_url("Mary.jpg"))])

here = os.path.dirname(__file__)
real = os.environ.get("PROJECTION") or os.path.join(here, "..", "out", "publish", "ear-drama.sqlite")
source = os.environ.get("SOURCE") or os.path.join(here, "..", "out", "radio-catalog.sqlite")
if os.path.exists(real):
    has_art = "art" in {r[0] for r in sqlite3.connect(real).execute("SELECT name FROM sqlite_master")}
    if has_art:
        check("contract holds on the real artifact", violations(real), {})
        if os.path.exists(source):
            check("retrace holds on the real artifact", retrace(real, source)[:5], [])
    else:
        print("  SKIP  real artifact predates the art table")
elif os.environ.get("PROJECTION"):
    check("the projection named by PROJECTION exists", False, True)
else:
    print("  SKIP  real artifact: out/publish/ear-drama.sqlite not built")

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
