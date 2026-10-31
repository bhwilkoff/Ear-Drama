"""A genre from evidence the records carry (tools/enrich_genres.py, tools/genres.py, DECISIONS 024).

    python3 tests/test_genre_evidence.py
Each rule has its broken control: a title never decides, a minority never decides, two specific
genres never decide, and a series a source already places is never touched.
"""
import gzip
import json
import os
import sqlite3
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import enrich_genres as E
import genres as G

ran = failed = 0


def check(name, got, want):
    global ran, failed
    ran += 1
    if got != want:
        failed += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


# --- the words ---------------------------------------------------------------------------
check("subject keywords split on commas and semicolons, trimmed",
      E.terms("Old Time Radio; Hoorspel, Radio Drama"), ["Old Time Radio", "Hoorspel", "Radio Drama"])
check("a subject given as a list is read the same", E.terms(["otr", "Mystery"]), ["otr", "Mystery"])
check("an item names the genres its own keywords, collection and file tag name",
      G.item_genres(["Old Time Radio", "Suspense"], ["Comedy", "OTR"]),
      {"mystery": ["subject:suspense"], "comedy": ["file:comedy"]})
check("control: a collection names no genre (audio_news is where news and everything not music is filed)",
      G.item_genres([], []), {})
check("control: a word counts whole and exact, never inside another word",
      G.item_genres(["crimson", "westerner", "newsreel", "dramatic", "old time radio", "otr", "music"], ["Other"]), {})
check("control: no keyword maps outside the eight", set(G.KEYWORD.values()) <= set(G.GENRES), True)

# --- a series from its items -------------------------------------------------------------
dr = {"drama": ["subject:hoorspel"]}
mys = {"mystery": ["subject:suspense"]}
check("more than half of the items name one genre: that genre, with the words that said so",
      G.archive_genre([dr, dr, {}]), ("drama", {"subject:hoorspel": 2}))
check("control: exactly half is not more than half", G.archive_genre([dr, {}]), (None, {}))
check("control: no item names a genre", G.archive_genre([{}, {}]), (None, {}))
check("a specific genre beats drama when both pass", G.archive_genre([{**dr, **mys}])[0], "mystery")
check("control: two specific genres that both pass are no evidence",
      G.archive_genre([{**mys, "comedy": ["subject:comedy"]}])[0], None)
check("control: a series with no items has no evidence", G.archive_genre([]), (None, {}))

# --- the step over a database ------------------------------------------------------------
with tempfile.TemporaryDirectory() as tmp:
    E.META = os.path.join(tmp, "meta")
    os.makedirs(E.META)

    def meta(aid, subject, files):
        with gzip.open(os.path.join(E.META, aid + ".json.gz"), "wt") as f:
            json.dump({"item": {"subject": subject, "collection": ["radioprograms"]},
                       "files": [{"name": n, "genre": g} for n, g in files]}, f)

    meta("hoor1", "Hoorspel; old time radio", [("a.mp3", "Other")])
    meta("hoor2", "hoorspel", [("b.mp3", None)])
    meta("gen1", "old time radio; otr", [("c.mp3", "OTR")])
    meta("placed", "comedy", [("d.mp3", None)])
    meta("mixed1", "suspense, comedy", [("e.mp3", None)])
    meta("tv", "sitcom", [("f.mp3", None)])
    meta("day", "comedy", [("g.mp3", None), ("h.mp3", None)])
    con = sqlite3.connect(":memory:")
    con.executescript("""
    CREATE TABLE series (key, name, genre, genres_otrr, is_librivox, networks);
    CREATE TABLE episodes (id, series_key, state);
    CREATE TABLE recordings (episode_id, rank, archive_id, file);
    CREATE TABLE series_wikidata (series_key, qid, in_db, match_evidence, broadcaster, genre);
    """)
    series = [("hoorspel", "Een Hoorspel", None, None, 0), ("plain", "Plain Title Comedy", None, None, 0),
              ("placed", "Placed", "OTR-Western", None, 0), ("mixed", "Mixed", None, None, 0),
              ("hidden", "Hidden", None, None, 0), ("tvmatch", "TV Match", None, None, 0),
              ("wd", "Wikidata", None, None, 0), ("dayA", "Day A", None, None, 0), ("dayB", "Day B", None, None, 0)]
    con.executemany("INSERT INTO series VALUES (?,?,?,?,?,NULL)", series)
    eps = [("hoorspel|1", "hoorspel", "keep_clean", "hoor1", "a.mp3"), ("hoorspel|2", "hoorspel", "keep_clean", "hoor2", "b.mp3"),
           ("plain|1", "plain", "keep_clean", "gen1", "c.mp3"), ("placed|1", "placed", "keep_clean", "placed", "d.mp3"),
           ("mixed|1", "mixed", "keep_unclaimed", "mixed1", "e.mp3"), ("hidden|1", "hidden", "hide_claim", "hoor1", "a.mp3"),
           ("tvmatch|1", "tvmatch", "keep_clean", "tv", "f.mp3"), ("wd|1", "wd", "keep_clean", "gen1", "c.mp3"),
           ("dayA|1", "dayA", "keep_clean", "day", "g.mp3"), ("dayB|1", "dayB", "keep_clean", "day", "h.mp3")]
    for eid, sk, st, aid, f in eps:
        con.execute("INSERT INTO episodes VALUES (?,?,?)", (eid, sk, st))
        con.execute("INSERT INTO recordings VALUES (?,0,?,?)", (eid, aid, f))
    ev_years = json.dumps({"years": "overlap"})
    con.execute("INSERT INTO series_wikidata VALUES ('wd', 'Q21590660', 1, ?, '[]', ?)",
                (ev_years, json.dumps([{"qid": "Q21590660", "label": "Western"}])))
    con.execute("INSERT INTO series_wikidata VALUES ('tvmatch', 'Q170238', 1, ?, '[]', ?)",
                (json.dumps({"years": "none"}), json.dumps([{"qid": "Q170238", "label": "sitcom"}])))
    rows, stats = E.run(con)
    got = {r[0]: r[1:4] for r in rows}
    check("a Dutch hoorspel is drama, from the keyword both its items carry",
          got.get("hoorspel"), ("drama", "archive.org", json.dumps({"subject:hoorspel": 2})))
    check("control: a title that says comedy decides nothing", "plain" in got, False)
    check("control: a series a source already places is never touched", "placed" in got, False)
    check("control: two specific genres on one item is no evidence", "mixed" in got, False)
    check("control: a hidden series is not read", "hidden" in got, False)
    check("a Wikidata genre, once matched on the years, wins", got.get("wd", (None,))[0:2], ("western", "wikidata:genre"))
    check("control: a Wikidata item matched on its title alone is refused, and the records are read instead",
          got.get("tvmatch", (None, None))[0:2], ("comedy", "archive.org"))
    check("control: an item holding several series' broadcasts describes the item, not any one program",
          ("dayA" in got, "dayB" in got), (False, False))
    check("the step counts what it did", (stats["without a genre"], stats["archive.org"], stats["wikidata:genre"]),
          (7, 2, 1))

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
