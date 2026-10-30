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
art for a person with no portrait. Seen to fail on 2026-10-28 (V4): the builder
publishing NULL for every face; face_text accepting a box off its image. Seen to fail on
2026-10-29 (D2c-2, show-first pictures): show_served ignoring the identity (a title-only match),
the license class, the size floor, television, or a date after the run; series_identity calling
a title alone or a television item an identity; the builder serving every series_art row;
series_face ignoring the marks or the marked share (a one-season host).
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
    "no image is published that no person or series wears": "SELECT COUNT(*) FROM art a WHERE NOT EXISTS "
        "(SELECT 1 FROM people p WHERE p.portrait = a.id) AND NOT EXISTS (SELECT 1 FROM series s WHERE s.picture = a.id)",
    "a series' picture is a published image of a known kind, with its source": "SELECT COUNT(*) FROM series s WHERE "
        "(picture IS NULL) != (picture_kind IS NULL) OR (picture IS NULL) != (picture_source IS NULL) OR "
        "picture_kind NOT IN ({}) OR (picture IS NOT NULL AND NOT EXISTS (SELECT 1 FROM art a WHERE a.id = s.picture))"
        .format(",".join(f"'{k}'" for k in AP.KINDS)),
    "a star's or person's picture is that person's portrait": "SELECT COUNT(*) FROM series s WHERE picture_kind IN "
        "('star', 'person') AND NOT EXISTS (SELECT 1 FROM people p WHERE p.id = s.star AND p.portrait = s.picture)",
    "a show picture comes from one of the show's own records": "SELECT COUNT(*) FROM series WHERE picture_kind = 'show' "
        "AND picture_source NOT IN ({})".format(",".join(f"'{x}'" for x in AP.SHOW_SOURCES)),
    "a person's portrait leads at most one show": "SELECT COUNT(*) FROM (SELECT star FROM series WHERE picture_kind IN "
        "('star', 'person') GROUP BY star HAVING COUNT(*) > 1)",
    "every portrait is a published image": "SELECT COUNT(*) FROM people p WHERE portrait IS NOT NULL AND NOT EXISTS "
        "(SELECT 1 FROM art a WHERE a.id = p.portrait)",
    "a series' star wears a portrait": "SELECT COUNT(*) FROM series s WHERE star IS NOT NULL AND NOT EXISTS "
        "(SELECT 1 FROM people p WHERE p.id = s.star AND p.portrait IS NOT NULL)",
    "an episode's star wears a portrait and is credited in it": "SELECT COUNT(*) FROM episodes e WHERE star IS NOT NULL "
        "AND NOT EXISTS (SELECT 1 FROM people p JOIN credits c ON c.person_id = p.id WHERE p.id = e.star "
        "AND c.episode_id = e.id AND p.portrait IS NOT NULL)",
}


def _face_ok(text):
    try:
        x, y, w, h = (float(v) for v in text.split(","))
    except ValueError:
        return False
    return w > 0 and h > 0 and x >= 0 and y >= 0 and x + w <= 1.0001 and y + h <= 1.0001


def violations(db):
    c = sqlite3.connect(db)
    pictured = "picture" in {r[1] for r in c.execute("PRAGMA table_info(series)")}
    rules = {n: q for n, q in CONTRACT.items() if pictured or "picture" not in q}
    if not pictured:   # a projection from before series pictures (contract section 3.3a)
        rules["no image is published that no person wears"] = (
            "SELECT COUNT(*) FROM art a WHERE NOT EXISTS (SELECT 1 FROM people p WHERE p.portrait = a.id)")
    out = {name: c.execute(sql).fetchone()[0] for name, sql in rules.items()}
    # A face box is "x,y,w,h" inside its image (contract section 3.3a): a crop is never
    # centered on a point off the picture, and a client parses exactly four numbers.
    if "face" in {r[1] for r in c.execute("PRAGMA table_info(art)")}:
        out["a face is four numbers inside its image"] = sum(
            1 for (t,) in c.execute("SELECT face FROM art WHERE face IS NOT NULL") if not _face_ok(t))
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
    cols = {r[1] for r in s.execute("PRAGMA table_info(people_art)")}
    own = "a.own_work" if "own_work" in cols else "0"
    dated = "a.date_field" if "date_field" in cols else "NULL"
    died = "w.death" if "death" in {r[1] for r in s.execute("PRAGMA table_info(people_wikidata)")} else "NULL"
    for pid, file, cls, usable, via, author, basis, own_work, when, died in s.execute(
            f"SELECT a.person_id, a.file, a.license_class, a.usable, a.found_via, a.author, w.basis, {own}, "
            f"{dated}, {died} FROM people_art a JOIN people_wikidata w ON w.person_id = a.person_id"):
        if AP.served(basis, cls, usable, via, author, own_work, when, died):
            ok.add((pid, AP.evidence_url(file)))
    s.close()
    return sorted(published - ok) + retrace_shows(projection, source)


def retrace_shows(projection, source):
    """Every show picture traced to its series_art rows and judged again by show_served:
    the (series, file page) pairs no row passes (a title-only match, a file without evidence)."""
    p = sqlite3.connect(projection)
    if "picture" not in {r[1] for r in p.execute("PRAGMA table_info(series)")}:
        return []
    published = {(k, ev) for k, ev in p.execute(
        "SELECT s.key, a.evidence_url FROM series s JOIN art a ON a.id = s.picture WHERE s.picture_kind = 'show'")}
    p.close()
    s = sqlite3.connect(f"file:{source}?mode=ro", uri=True)
    ok = set()
    if "series_art" in {r[0] for r in s.execute("SELECT name FROM sqlite_master")}:
        run = AP.run_dates(s)
        for k, file, src, identity, cls, author, w, h, cats, when in s.execute(
                "SELECT series_key, file, source, identity, license_class, author, width, height, categories, "
                "date_field FROM series_art"):
            if AP.show_served(identity, src, cls, author, w, h, file, json.loads(cats or "[]"), when,
                              *reversed(run.get(k, (None, None)))):
                ok.add((k, AP.evidence_url(file)))
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
# An uploader's word is not evidence: an own-work license dated after the person's death (2026-10-29).
check("own work: a {{self}} license on a 2019 file of a man who died in 1971 is refused",
      AP.served(DATED, "cc_by_sa", 1, "wikidata:P18", "Welty07", True, "2019-07-05 14:59:35", "1971-01-07"), False)
check("control: the same file with no own-work marker is served", AP.served(
      DATED, "cc_by_sa", 1, "wikidata:P18", "Welty07", False, "2019-07-05 14:59:35", "1971-01-07"), True)
check("control: an own work dated in the person's lifetime is served", AP.served(
      DATED, "cc_by_sa", 1, "wikidata:P18", "Welty07", True, "1965-07-05", "1971-01-07"), True)
check("control: an own work with no date, or a living person, is served",
      [AP.served(DATED, "pd_release", 1, "wikidata:P18", None, True, None, "1971-01-07"),
       AP.served(DATED, "pd_release", 1, "wikidata:P18", None, True, "2019", None)], [True, True])
check("earliest death of the marked people", AP.earliest_death([("a", "1971-01-07"), ("a", "1950"), ("b", None)]),
      {"a": 1950})
KOLLMAR = "=={{int:filedesc}}==\n{{Information\n|date=2019-07-05\n|source={{own}}\n|author=[[User:Welty07|Welty07]]\n}}\n{{self|cc-by-sa-4.0}}"
check("own_work reads a {{self}} license", E.own_work(KOLLMAR), True)
check("own_work reads PD-self", E.own_work("{{PD-self}}"), True)
check("control: a PD-US template on a scan its uploader calls own is not an own-work license",
      E.own_work("|source={{own}}\n|permission=PD-US\n{{PD-US-no notice}}"), False)
check("own_work: source {{own}} with a Creative Commons license", E.own_work("|source={{own}}\n{{cc-by-sa-4.0}}"), True)
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
    bad.execute("INSERT INTO art VALUES (9, ?, NULL, NULL, 'pd_us', NULL, NULL, ?, NULL)",
                (AP.image_url("Mary.jpg"), AP.evidence_url("Mary.jpg")))
    bad.execute("UPDATE people SET portrait = 9 WHERE id = 'p2'")
    bad.execute("UPDATE art SET credit = NULL WHERE license = 'cc_by'")
    bad.commit()
    bad.close()
    check("control: the contract catches a dropped credit", sorted(violations(dst)),
          ["an image owes a credit exactly when its license does"])
    check("control: retrace catches an undated match's portrait", retrace(dst, src), [("p2", AP.evidence_url("Mary.jpg"))])


# A portrait's own size is published, so a client lays the face out by its shape before the
# image arrives (contract section 3.3); a source without the columns publishes NULL, never a guess.
with tempfile.TemporaryDirectory() as tmp:
    src, dst, web = (os.path.join(tmp, n) for n in ("src.sqlite", "out.sqlite", "web"))
    fixture(src)
    d = sqlite3.connect(src)
    d.execute("ALTER TABLE people_art ADD COLUMN width")
    d.execute("ALTER TABLE people_art ADD COLUMN height")
    d.execute("UPDATE people_art SET width = 640, height = 800 WHERE file = 'Jack Benny 1938.jpg'")
    d.commit()
    d.close()
    B.build(src, dst)
    c = sqlite3.connect(dst)
    size = dict((pid, (w, h)) for pid, w, h in c.execute(
        "SELECT p.id, a.width, a.height FROM people p JOIN art a ON a.id = p.portrait"))
    c.close()
    check("size: the portrait's own width and height are published", size["p1"], (640, 800))
    check("control: a portrait whose size was never read publishes NULL", size["p3"], (None, None))
    W.build(dst, web)
    with open(os.path.join(web, "index", "series.json")) as f:
        idx = json.load(f)
    row = dict(zip(idx["fields"], idx["rows"][0]))
    check("size: the series row's art carries it", (row["art"][1], row["art"][2]), (640, 800))


# A face box is computed once in the pipeline and published beside the size (contract section
# 3.3a), so every client centers a small crop on the same point; none detects faces itself.
import harvest_people_wikidata as H  # noqa: E402

check("pick: the largest confident face", H.pick_face([[0.1, 0.1, 0.1, 0.1, 0.9], [0.5, 0.2, 0.3, 0.3, 0.8],
                                                       [0.0, 0.0, 0.9, 0.9, 0.2]]), [0.5, 0.2, 0.3, 0.3])
check("pick: a group's peer faces are held together, never one of them",
      H.pick_face([[0.1, 0.2, 0.1, 0.1, 0.9], [0.6, 0.3, 0.12, 0.12, 0.9], [0.9, 0.9, 0.02, 0.02, 0.9]]),
      [0.1, 0.2, 0.62, 0.22])
check("pick: clamped to the image", H.pick_face([[-0.1, 0.9, 0.3, 0.3, 1.0]]), [0.0, 0.9, 0.2, 0.1])
check("control: no confident face is None", H.pick_face([[0.1, 0.1, 0.2, 0.2, 0.3]]), None)
check("face_text: four numbers", AP.face_text([0.25, 0.1, 0.5, 0.4]), "0.25,0.1,0.5,0.4")
check("control: face_text refuses a box off the image", AP.face_text([0.8, 0.1, 0.5, 0.4]), None)
with tempfile.TemporaryDirectory() as tmp:
    src, dst, web = (os.path.join(tmp, n) for n in ("src.sqlite", "out.sqlite", "web"))
    fixture(src)
    d = sqlite3.connect(src)
    for col in ("width", "height", "face"):
        d.execute(f"ALTER TABLE people_art ADD COLUMN {col}")
    d.execute("UPDATE people_art SET width = 900, height = 500, face = '0.6,0.15,0.2,0.36' "
              "WHERE file = 'Jack Benny 1938.jpg'")
    d.execute("UPDATE people_art SET face = '0.9,0.1,0.3,0.3' WHERE file != 'Jack Benny 1938.jpg'")
    d.commit()
    d.close()
    B.build(src, dst)
    c = sqlite3.connect(dst)
    got = dict(c.execute("SELECT p.id, a.face FROM people p JOIN art a ON a.id = p.portrait"))
    c.close()
    check("face: the portrait's face box is published", got["p1"], "0.6,0.15,0.2,0.36")
    check("control: a box off the image is published as NULL", got["p3"], None)
    check("face: the contract holds", violations(dst), {})
    W.build(dst, web)
    with open(os.path.join(web, "index", "series.json")) as f:
        idx = json.load(f)
    row = dict(zip(idx["fields"], idx["rows"][0]))
    check("face: the series row's art carries [x, y, w, h]", row["art"][5], [0.6, 0.15, 0.2, 0.36])
    bad = sqlite3.connect(dst)
    bad.execute("UPDATE art SET face = '0.9,0.1,0.3,0.3'")
    bad.commit()
    bad.close()
    check("control: the contract catches a face off its image",
          sorted(violations(dst)), ["a face is four numbers inside its image"])

# --- the picture that leads a show (contract section 3.3a) ------------------------------
YEARS, NET = {"years": "overlap"}, {"years": "unknown"}
check("identity: the title with overlapping years", AP.series_identity(YEARS, ["CBS"], []), "title+years")
check("identity: the title with the network", AP.series_identity(NET, ["Mutual"], ["Mutual Broadcasting System"]),
      "title+network")
check("control: a title alone is no identity", AP.series_identity(NET, ["CBS"], ["NBC"]), "title")
check("control: a title with no network or years is no identity", AP.series_identity({}, [], []), "title")
GUN = {"years": "unknown", "our_years": [1949, 1961]}
check("identity: the years the item's own description names",
      AP.series_identity(GUN, [], [], "American radio Western drama series (1952-1961)"), "title+years")
check("identity: a decade in the description", AP.description_years("drama from the mid-1980s"), (1980, 1989))
check("control: a description's years that miss ours are no identity",
      AP.series_identity(GUN, [], [], "radio drama (1975-1980)"), "title")
check("control: a description without years is no identity", AP.series_identity(GUN, [], [], "radio soap opera"),
      "title")
SHOW = ("title+years", "wikidata:P18", "pd_us", None, 640, 480, "Gildersleeve cast.jpg", ["Category:The Great Gildersleeve"])
check("show: the item's own PD image, matched on the years", AP.show_served(*SHOW), True)
check("control: a title-only match is refused", AP.show_served("title", *SHOW[1:]), False)
check("control: a show image without license evidence is refused", AP.show_served(*SHOW[:2], "unknown", *SHOW[3:]), False)
check("control: 'no known restrictions' is refused", AP.show_served(*SHOW[:2], "no_known_restrictions", *SHOW[3:]), False)
check("control: archive.org cover art is not a show source", AP.show_served(SHOW[0], "archive.org:cover", *SHOW[2:]),
      False)
check("control: CC BY with no author is refused", AP.show_served(*SHOW[:2], "cc_by", "Unknown", *SHOW[4:]), False)
check("control: smaller than a show tile is refused", AP.show_served(*SHOW[:4], 150, 480, *SHOW[6:]), False)
check("control: an unsized file is refused", AP.show_served(*SHOW[:4], None, None, *SHOW[6:]), False)
check("control: a television still is refused", AP.show_served(*SHOW[:6], "Riley TV cast.jpg", []), False)
check("control: a television category is refused",
      AP.show_served(*SHOW[:7], ["Category:The Life of Riley (TV series)"]), False)
check("control: a file dated after the run is refused",
      AP.show_served(*SHOW, date_field="March 1958", last_date="1952-07-29"), False)
check("control: a file whose name dates it after the run is refused",
      AP.show_served(*SHOW[:6], "Bob Barker 1958 Truth or Consequences headshot.jpg", [], None, "1952-07-29"), False)
check("control: a depicts file dated before the first broadcast is refused (Hill Top House, 1914)",
      AP.show_served("title+years", "commons:P180", "pd_us", None, 1678, 1086, "Hill Top House, Harpers Ferry, WV.jpg",
                     [], "1914", "1953-12-15", "1937-01-01"), False)
check("control: a show image dated before the first broadcast is refused, whatever its source",
      AP.show_served(*SHOW, date_field="1928-03-26", last_date="1948-05-23", first_date="1935-03-22"), False)
check("show: a year before our first episode but inside the logged run passes",
      AP.show_served(*SHOW[:6], "Ralph Edwards Truth or Consequences 1942.JPG", [], "1942-03-08", "1952-07-29",
                     "1943-12-18"), True)
check("show: an own-work image dated after the star's death is refused",
      AP.show_served(*SHOW, own_work=True, date_field="1951", died=1950), False)
check("control: ...and served when dated before it", AP.show_served(*SHOW, own_work=True, date_field="1951", died=1960),
      True)
check("show: a file dated inside the run passes", AP.show_served(*SHOW, date_field="1951", last_date="1952-07-29"), True)
check("control: an item its own description calls a television program is no identity",
      AP.series_identity(YEARS, ["CBS"], ["CBS"], "1949-1956 CBS television program"), "television")
check("identity: a radio and television series is still the radio one",
      AP.series_identity(YEARS, [], [], "Radio and television series"), "title+years")
check("pick_show: the item's own image before a depicts file",
      AP.pick_show([("a.jpg", "commons:P180", "pd_us"), ("b.jpg", "wikidata:P18", "cc_by")])[0], "b.jpg")
check("pick_show: in one source, a file whose name names the show first",
      AP.pick_show([("Buff Cobb 1949.JPG", "commons:category", "pd_us"),
                    ("Ralph Edwards Truth or Consequences 1942.JPG", "commons:category", "pd_us")],
                   "Truth Or Consequences")[0], "Ralph Edwards Truth or Consequences 1942.JPG")
check("marks: the title role", AP.marks_star("Boston Blackie(beginning in 1945)", "Boston Blackie"), True)
check("marks: the host", AP.marks_star("Host", "Lux Radio Theatre"), True)
check("control: a supporting character is no star", AP.marks_star("Mary Wesley", "Boston Blackie"), False)
check("control: a short character is no title role", AP.marks_star("Al", "Al Pearce and His Gang"), False)
check("recognizability: no Wikipedia weighs 1", AP.recognizability(0), 1.0)
blackie = {f"e{i}": [("woods", "cast"), ("kollmar", "cast")] for i in range(10)} | {"e10": [("woods", "cast")]}
both = {"woods", "kollmar", "morris"}
check("face: today's rule takes the person heard most", AP.series_star(blackie, both), "woods")
check("face: the title role the program marks beats who is heard most",
      AP.series_face(blackie, both, {"kollmar"}, {}), ("kollmar", "star", "otrrpedia:noted-role"))
check("face: a marked film star heard on 3 of 190 loses to the marked regular",
      AP.series_face(blackie | {f"m{i}": [("morris", "cast")] for i in range(3)}, both, {"kollmar", "morris"},
                     {"morris": 40, "kollmar": 2})[0], "kollmar")
anth = {f"e{i}": [(f"g{i}", "cast")] for i in range(40)} | {f"h{i}": [("monty", "host")] for i in range(3)}
check("control: a host marked for one season of a long anthology is not its face",
      AP.series_face(anth, {"monty"}, {"monty"}, {"monty": 30}), None)
check("control: a marked person never heard here is no face",
      AP.series_face(blackie, both, {"morris"}, {"morris": 40})[0], "woods")
check("face: unmarked, the regular more Wikipedias cover",
      AP.series_face(blackie, both, (), {"kollmar": 3}), ("kollmar", "star", "wikipedia:sitelinks"))
check("face: no one covered falls back to the heard-most rule",
      AP.series_face(blackie, both, (), {}), ("woods", "person", "credits:heard-most"))
check("face: a marked star of an uncredited series", AP.series_face({}, both, {"morris"}, {}),
      ("morris", "star", "otrrpedia:noted-role"))
check("control: no portrait, no face", AP.series_face(blackie, set(), {"kollmar"}, {"kollmar": 9}), None)

# One face per star (owner, 2026-10-29): a person leads the one show they are most identified with.
gun = {f"g{i}": [("conrad", "cast"), ("g" + str(i), "cast")] for i in range(10)}
esc = {f"s{i}": [("conrad", "host")] for i in range(4)} | {f"t{i}": [("other", "cast")] for i in range(4)}
trio = {"gun": (gun, ()), "esc": (esc, ())}
pool = {"conrad", "other"}
got = AP.assign_faces(trio, pool, {"conrad": 30, "other": 3})
check("one face: the show a star is heard on most keeps them", got["gun"][0], "conrad")
check("one face: the other show falls to its next candidate", got["esc"][0], "other")
esc6 = {f"s{i}": [("conrad", "host")] for i in range(6)} | {f"t{i}": [("other", "cast")] for i in range(4)}
check("one face: a marked role beats the larger count when it holds half the biggest show's episodes",
      AP.assign_faces({"gun": (gun, ()), "esc": (esc6, {"conrad"})}, pool, {"conrad": 30, "other": 3})["esc"][0], "conrad")
check("control: a marked title role in a show with under half the episodes does not take the star (Pete Kelly)",
      AP.assign_faces({"gun": (gun, ()), "esc": (esc, {"conrad"})}, pool, {"conrad": 30, "other": 3})["gun"][0], "conrad")
check("one face: ...and the show that lost them, with no one else eligible, has none",
      AP.assign_faces({"gun": (gun, ()), "esc": (esc6, {"conrad"})}, pool, {"conrad": 30, "other": 3})["gun"], None)
check("one face: a show with no one left has none",
      AP.assign_faces({"a": (gun, ()), "b": (gun, ())}, {"conrad"}, {})["b"], None)
check("one face: a tie goes to the first series key",
      [k for k, f in AP.assign_faces({"b": (gun, ()), "a": (gun, ())}, {"conrad"}, {}).items() if f], ["a"])
check("control: two stars of different shows both keep theirs",
      sorted(f[0] for f in AP.assign_faces({"gun": (gun, ()), "oth": ({f"x{i}": [("other", "cast")] for i in range(3)}, ())},
                                           pool, {}).values() if f), ["conrad", "other"])

with tempfile.TemporaryDirectory() as tmp:
    src, dst, web = (os.path.join(tmp, n) for n in ("src.sqlite", "out.sqlite", "web"))
    fixture(src)
    d = sqlite3.connect(src)
    d.executescript("""
    CREATE TABLE series_art (series_key, qid, file, source, identity, license_class, template, author, width, height,
        face, categories, date_field, served, evidence_url);
    CREATE TABLE series_marks (series_key, person_id, character);
    CREATE TABLE wikipedia_sitelinks (qid, n);
    """)
    d.executemany("INSERT INTO series_art VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", [
        ("benny", "Q1", "Benny title card.png", "wikidata:P154", "title", "pd_us", "PD-US", None, 800, 600, None, "[]",
         None, 0, ""),
        ("benny", "Q1", "Benny cast 1946.jpg", "commons:category", "title+years", "pd_us", "PD-US", None, 900, 700,
         "0.1,0.2,0.6,0.3", "[]", "1946", 1, ""),
        ("benny", "Q1", "Benny unknown.jpg", "wikidata:P18", "title+years", "unknown", None, None, 900, 700, None, "[]",
         None, 0, ""),
        ("benny", "Q1", "Benny 1960 special.jpg", "wikidata:P18", "title+years", "pd_us", "PD-US", None, 900, 700, None,
         "[]", "1960-03-01", 0, "")])
    d.execute("INSERT INTO series_marks VALUES ('benny', 'p3', 'Star')")
    d.commit()
    d.close()
    meta = B.build(src, dst)
    c = sqlite3.connect(dst)
    pic = c.execute("SELECT s.picture_kind, s.picture_source, a.evidence_url, a.face, s.star FROM series s "
                    "JOIN art a ON a.id = s.picture").fetchone()
    c.close()
    check("show: the evidenced show image leads, not the title-only logo or the unlicensed P18",
          pic[:4], ("show", "commons:category", AP.evidence_url("Benny cast 1946.jpg"), "0.1,0.2,0.6,0.3"))
    check("show: the series still names its star (the marked one)", pic[4], "p3")
    check("show: the manifest counts the kinds", (meta["counts"]["seriesPictureShow"], meta["counts"]["seriesPictureStar"]),
          (1, 0))
    check("show: the contract holds", violations(dst), {})
    check("show: retrace holds", retrace(dst, src), [])
    W.build(dst, web)
    with open(os.path.join(web, "index", "series.json")) as f:
        idx = json.load(f)
    row = dict(zip(idx["fields"], idx["rows"][0]))
    check("web: the series row carries its picture, kind and source",
          (row["picture"][0], row["pictureKind"], row["pictureSource"], row["art"][0]),
          (AP.image_url("Benny cast 1946.jpg"), "show", "commons:category", AP.image_url("Phil Harris.jpg")))
    with open(os.path.join(web, "series", "benny.json")) as f:
        page = json.load(f)
    check("web: the series page carries it too", (page["pictureKind"], page["picture"][0]),
          ("show", AP.image_url("Benny cast 1946.jpg")))
    # Broken controls: a source whose match is title-only, and a projection that serves a show image without a
    # passing row, must each be caught.
    d = sqlite3.connect(src)
    d.execute("UPDATE series_art SET identity = 'title'")
    d.commit()
    d.close()
    check("control: retrace catches a show image whose match is a title alone", retrace(dst, src),
          [("benny", AP.evidence_url("Benny cast 1946.jpg"))])
    B.build(src, dst)
    c = sqlite3.connect(dst)
    check("control: a title-only match serves no show image; the marked star leads",
          c.execute("SELECT picture_kind, picture_source FROM series").fetchone(), ("star", "otrrpedia:noted-role"))
    c.execute("UPDATE series SET picture_kind = 'show', picture_source = 'archive.org:cover'")
    c.commit()
    c.close()
    check("control: the contract catches a show picture from no show record",
          sorted(violations(dst)), ["a show picture comes from one of the show's own records"])

here = os.path.dirname(__file__)
real =os.environ.get("PROJECTION") or os.path.join(here, "..", "out", "publish", "ear-drama.sqlite")
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
