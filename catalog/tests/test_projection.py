"""The served projection (tools/build_projection.py) against docs/CATALOG-CONTRACT.md.

    python3 tests/test_projection.py
A fixture database proves each rule and its broken control; when
out/publish/ear-drama.sqlite exists, the contract's checks also run over every
row of the real artifact (a contract is a test, not a docstring).
"""
import json
import os
import sqlite3
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import build_projection as B
import genres as G

ran = failed = 0


def check(name, got, want):
    global ran, failed
    ran += 1
    if got != want:
        failed += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


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
    d.executemany("INSERT INTO series VALUES (?,?,?,?,?,?,?,?)", [
        ("suspense", "Suspense", "OTR-Thriller", '["Mystery", "Suspense", "Anthology"]', 0, "1942-06-17", "1962-09-30", None),
        ("shadow", "The Shadow", "OTR-Detective", None, 0, "1937-09-26", "1954-12-26", None)])
    d.executemany("INSERT INTO episodes VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)", [
        ("suspense|1943-05-25", "suspense", "1943-05-25", "filename", 46, "Sorry, Wrong Number", None,
         "keep_unclaimed", "rec_orphan_unclaimed", "work_none_found", None, "CBS", "otrr", 0),
        ("suspense|1949-09-15", "suspense", "1949-09-15", "filename", 300, "The Night Reveals", None,
         "keep_clean", "rec_pd_published_age", "work_none_found", None, None, None, 0),
        ("shadow|1938-01-02", "shadow", "1938-01-02", "filename", 15, "The Silent Avenger", None,
         "hide_claim", "rec_rights_holder_claim", "work_none_found", None, None, None, 0)])
    d.executemany("INSERT INTO recordings VALUES (?,?,?,?,?,?,?,?,?)", [
        ("suspense|1943-05-25", 0, "OTRR_Suspense_Singles", "Suspense 43-05-25 Sorry, Wrong Number.mp3",
         "VBR MP3", 64, 1740.0, None, 0),
        ("suspense|1943-05-25", 1, "afrs_set", "Suspense AFRS #12.mp3", "VBR MP3", 128, 1735.0, "AFRS", 0),
        ("suspense|1949-09-15", 0, "susp49", "Café Night/1949.mp3", "VBR MP3", 64, 1700.0, None, 0),
        ("shadow|1938-01-02", 0, "shadow38", "shadow.mp3", "VBR MP3", 64, 1700.0, None, 0)])
    d.executemany("INSERT INTO episode_credits VALUES (?,?,?,?,?)", [
        ("suspense|1943-05-25", "p1", "Agnes Moorehead", "cast", "Mrs. Stevenson"),
        ("shadow|1938-01-02", "p2", "Orson Welles", "cast", "Lamont Cranston")])
    d.executemany("INSERT INTO people VALUES (?,?,?,?)", [("p1", "Agnes Moorehead", "1900", "1974"),
                                                         ("p2", "Orson Welles", "1915", "1985")])
    d.commit()
    d.close()


# --- pure functions --------------------------------------------------------------
check("season: fall opens a season", B.season("1949-10-06"), "1949-50")
check("season: spring closes the season before", B.season("1950-04-13"), "1949-50")
check("season: September is the first month", B.season("1949-09-01"), "1949-50")
check("season: summer belongs to the season before", B.season("1950-08-31"), "1949-50")
check("season: century turn", B.season("1999-12-01"), "1999-00")
check("control: an undated episode has no season", B.season(None), None)
check("url: spaces, commas, and the path survive",
      B.download_url("OTRR_Suspense_Singles", "Suspense 43-05-25 Sorry, Wrong Number.mp3"),
      "https://archive.org/download/OTRR_Suspense_Singles/Suspense%2043-05-25%20Sorry%2C%20Wrong%20Number.mp3")
check("url: non-ASCII and folders", B.download_url("susp49", "Café Night/1949.mp3"),
      "https://archive.org/download/susp49/Caf%C3%A9%20Night/1949.mp3")
check("control: '#' and '?' cannot cut the path short", B.download_url("a", "x#1?.mp3"),
      "https://archive.org/download/a/x%231%3F.mp3")


CONTRACT = {
    "every episode is clean or unclaimed": "SELECT COUNT(*) FROM episodes WHERE rights NOT IN ('clean','unclaimed')",
    "every episode has exactly one rank-0 copy": "SELECT COUNT(*) FROM episodes e WHERE (SELECT COUNT(*) FROM "
        "recordings r WHERE r.episode_id = e.id AND r.rank = 0) != 1",
    "no URL holds a raw space": "SELECT COUNT(*) FROM recordings WHERE url LIKE '% %'",
    "every series row is served and counted right": "SELECT COUNT(*) FROM series s WHERE episodes != "
        "(SELECT COUNT(*) FROM episodes e WHERE e.series_key = s.key)",
    "no recording without its episode": "SELECT COUNT(*) FROM recordings r WHERE NOT EXISTS "
        "(SELECT 1 FROM episodes e WHERE e.id = r.episode_id)",
}

check("genre: OTRR's first mappable label", G.genre_of(["Horror", "Mystery", "Science Fiction"]), ("mystery", "otrrpedia"))
check("genre: a serial queues by arc", G.genre_of(["Action", "Super Hero", "Youth", "Adventure", "Serial"]),
      ("serial", "otrrpedia"))
check("genre: a comedy in serial form stays comedy", G.genre_of(["Serial", "Sitcom", "Comedy"]), ("comedy", "otrrpedia"))
check("genre: RadioEchoes when OTRR is silent", G.genre_of(None, "OTR-Western"), ("western", "radioechoes"))
check("genre: a LibriVox work is drama", G.genre_of(None, None, librivox=True), ("drama", "librivox"))
check("control: an unmapped label is no genre", G.genre_of(["Music", "Other"], "OTR-Miscellaneous"), (None, None))
check("control: every mapped value is one of the eight",
      set(G.OTRR.values()) | set(G.RADIOECHOES.values()) <= set(G.GENRES), True)


def violations(db):
    """The contract's checks over every row of a built projection: name -> offending rows."""
    c = sqlite3.connect(db)
    out = {name: c.execute(sql).fetchone()[0] for name, sql in CONTRACT.items()}
    c.close()
    return {k: v for k, v in out.items() if v}


with tempfile.TemporaryDirectory() as tmp:
    src, dst = os.path.join(tmp, "src.sqlite"), os.path.join(tmp, "out.sqlite")
    fixture(src)
    meta = B.build(src, dst)
    c = sqlite3.connect(dst)
    ids = {r[0] for r in c.execute("SELECT id FROM episodes")}
    check("served: the kept rows", ids, {"suspense|1943-05-25", "suspense|1949-09-15"})
    check("control: a hidden row never leaves the pipeline", "shadow|1938-01-02" in ids, False)
    check("control: a hidden row's people never leave either",
          c.execute("SELECT COUNT(*) FROM people WHERE id = 'p2'").fetchone()[0], 0)
    check("default copy keeps the pipeline's rank",
          c.execute("SELECT variant FROM recordings WHERE episode_id = 'suspense|1943-05-25' AND rank = 0").fetchone()[0], None)
    check("rights shown", dict(c.execute("SELECT id, rights FROM episodes")),
          {"suspense|1943-05-25": "unclaimed", "suspense|1949-09-15": "clean"})
    check("search is word-prefix",
          [r[0] for r in c.execute("SELECT e.id FROM episodes_fts f JOIN episodes e ON e.rowid = f.rowid "
                                   "WHERE episodes_fts MATCH 'sorr* wrong'")], ["suspense|1943-05-25"])
    check("control: search is not substring",
          c.execute("SELECT COUNT(*) FROM episodes_fts WHERE episodes_fts MATCH 'orry'").fetchone()[0], 0)
    check("search finds credited people",
          c.execute("SELECT COUNT(*) FROM episodes_fts WHERE episodes_fts MATCH 'people:moorehead'").fetchone()[0], 1)
    check("series genre stored with its source", c.execute("SELECT genre, genre_source FROM series WHERE key = 'suspense'").fetchone(),
          ("mystery", "otrrpedia"))
    check("the rights lines are published, never 'public domain'",
          json.loads(c.execute("SELECT value FROM meta WHERE key = 'rightsLines'").fetchone()[0])["unclaimed"],
          "No rights claim known. Removed on request.")
    check("control: no published rights line says public domain",
          any("public domain" in v.lower() for v in B.RIGHTS_LINES.values()), False)
    check("seasons stored", c.execute("SELECT season FROM episodes WHERE id = 'suspense|1949-09-15'").fetchone()[0],
          "1949-50")
    c.close()
    check("contract holds on the fixture", violations(dst), {})
    clean = os.path.join(tmp, "clean.sqlite")
    B.build(src, clean, clean_only=True)
    check("public-web gate: clean rows only",
          [r[0] for r in sqlite3.connect(clean).execute("SELECT id FROM episodes")], ["suspense|1949-09-15"])

    # Broken control: a projection that leaks a hidden row must fail the contract.
    bad = sqlite3.connect(dst)
    bad.execute("UPDATE episodes SET rights = 'hide_claim' WHERE id = 'suspense|1949-09-15'")
    bad.execute("UPDATE recordings SET url = 'https://archive.org/download/a/b c.mp3' WHERE rank = 1")
    bad.commit()
    bad.close()
    check("control: the contract catches a leaked hidden row and a raw space", sorted(violations(dst)),
          ["every episode is clean or unclaimed", "no URL holds a raw space"])

real = os.environ.get("PROJECTION") or os.path.join(os.path.dirname(__file__), "..", "out", "publish", "ear-drama.sqlite")
if os.path.exists(real):
    check("contract holds on the real artifact", violations(real), {})
else:
    print("  SKIP  real artifact: out/publish/ear-drama.sqlite not built")

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
