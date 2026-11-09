"""A show's "about" text (tools/series_about.py, catalog DECISIONS 030): Wikipedia's own lead,
only for the article the series' Wikidata match names, only when it is about the radio program.

    python3 tests/test_series_about.py
Fixtures prove each rule; enrich_external.write_about and the two projections are run over a
fixture; when out/publish/ear-drama.sqlite exists, the real artifact's about columns are checked
for shape. Broken controls, 2026-11-09, each run against a mutated copy of series_about.py:
    gate() skips the qid test                      1 failed
    trim() ignores END (keeps a colon paragraph)   1 failed
    years_ok() always passes                       3 failed
    rejected_for() ignores the article             1 failed
"""
import json
import os
import re
import sqlite3
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import series_about as SA
import enrich_external as EE
import build_projection as B
import build_web_projection as W

ran = failed = 0


def check(name, got, want):
    global ran, failed
    ran += 1
    if got != want:
        failed += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


def page(title="Suspense (radio drama)", qid="Q1", sd="Radio drama series (1940 to 1962)", extract=None, **kw):
    return {"title": title, "qid": qid, "shortdesc": sd, "url": "https://en.wikipedia.org/wiki/" + title.replace(" ", "_"),
            "extract": extract if extract is not None else
            "Suspense is a radio drama series broadcast on CBS Radio from 1940 through 1962.\n"
            "One of the premier drama programs of the Golden Age of Radio, it featured leading Hollywood actors.",
            "fetched": "2026-11-09", "missing": False, "disambiguation": False, **kw}


# --- cleaning ------------------------------------------------------------------------
check("template residue goes: empty parentheses, a citation mark, IPA",
      SA.clean("Fibber McGee ( ; ) is a show.[1] It is said /ˈfɪbər/ fast."),
      ["Fibber McGee is a show. It is said fast."])
check("a hatnote opening the intro goes",
      SA.clean("For the 1946 film, see Breakfast in Hollywood (film).\n\nBreakfast in Hollywood is a radio show."),
      ["Breakfast in Hollywood is a radio show."])
check("control: a sentence that only mentions 'see' stays",
      SA.clean("You will see the show. It ran on radio."), ["You will see the show. It ran on radio."])

# --- sentences and trimming ------------------------------------------------------------
check("no split after an abbreviation, an initial, or a.k.a.",
      SA.sentences("Mr. Keen ran at 8 p.m. Tuesday. Beyond Tomorrow (a.k.a. Beyond This World) was J. Smith's. It ended."),
      ["Mr. Keen ran at 8 p.m. Tuesday.", "Beyond Tomorrow (a.k.a. Beyond This World) was J. Smith's.", "It ended."])
paras = ["A" * 300 + ".", "B" * 300 + ".", "C" * 400 + "."]
check("whole paragraphs while they fit", SA.trim(paras), paras[0] + "\n\n" + paras[1])
check("a paragraph ending on a colon stops the text there",
      SA.trim(["The show began in 1943.", "A critic wrote:", "It was fine."]), "The show began in 1943.")
long = " ".join(f"Sentence number {i} is here." for i in range(60))
got = SA.trim([long])
check("a long first paragraph gives whole sentences only", (len(got) <= SA.MAX_CHARS, got.endswith("here."),
                                                           long.startswith(got)), (True, True, True))
check("control: a first sentence over the limit gives nothing", SA.trim(["x" * 1000 + "."]), None)
check("control: a lead that never ends a sentence gives nothing",
      SA.trim(["The Zane Grey Show is an American Western radio drama"]), None)

# --- the gate --------------------------------------------------------------------------
check("a radio short description passes", SA.gate(page(), "Q1"), (True, None))
check("control: another item's article is refused", SA.gate(page(), "Q2"), (False, "qid_mismatch"))
check("control: a character article is refused",
      SA.gate(page("The Shadow", sd="Fictional character",
                   extract="The Shadow is a fictional character created by Street & Smith. The radio drama followed."),
              "Q1")[1], "shortdesc_not_the_show")
check("control: a person is refused",
      SA.gate(page("Bob Hope", sd="American comedian and actor (1903-2003)",
                   extract="Bob Hope starred on radio for decades. He made films too."), "Q1")[1],
      "shortdesc_not_the_show")
check("control: a lead opening on a person is refused, whatever the description says",
      SA.gate(page(sd=None, extract="Jack Benny was an American comedian on radio and television."), "Q1")[1],
      "lead_is_a_person")
check("control: a radio network is refused", SA.gate(page(sd="American radio network"), "Q1")[1],
      "shortdesc_not_the_show")
check("a show on a network is not a network", SA.gate(page(sd="American radio program on the CBS Radio Network"), "Q1"),
      (True, None))
check("a soap opera is not an opera, a comic-strip adaptation not a comic",
      [SA.gate(page(sd=d), "Q1")[0] for d in ("American radio soap opera", "1940s radio sitcom adapted from the comic strip")],
      [True, True])
check("control: a television description is refused", SA.gate(page(sd="1949 American TV series or program"), "Q1")[1],
      "shortdesc_not_radio")
check("control: a comic strip is refused", SA.gate(page(sd="American comic strip (1928-1970)"), "Q1")[1],
      "shortdesc_not_radio")
check("no description: the first sentence must name a radio program",
      [SA.gate(page(sd=None, extract=e), "Q1") for e in (
          "Beyond Tomorrow was an American radio drama series developed for CBS in 1950.",
          "Stars for Defense is a series of albums recorded for the government. Radio stations played them.")],
      [(True, None), (False, "lead_not_a_radio_program")])
check("control: a disambiguation page is refused", SA.gate(page(disambiguation=True), "Q1")[1], "disambiguation")

# --- years -----------------------------------------------------------------------------
v = page("The War of the Worlds (1968 radio drama)", sd="1968 radio drama")
check("a version article needs the series to begin in its year",
      [SA.years_ok(v, y) for y in ((1968, 1968), (1938, 1988), (None, None))],
      [(True, None), (False, "version_years_disagree"), (False, "version_years_unknown")])
check("a description's range must overlap the run", [SA.years_ok(page(sd="2002–2012 radio drama series"), y)[0]
                                                     for y in ((1961, 1961), (2005, 2006))], [False, True])
check("a two-digit range end reads in its century", SA.years_ok(page(sd="American radio program (1933–55)"), (1954, 1955)),
      (True, None))
check("a single year is when it began", [SA.years_ok(page(sd="1941 radio show"), y)[0]
                                         for y in ((1945, 1954), (1930, 1935))], [True, False])

# --- the whole decision ------------------------------------------------------------------
a, why = SA.about_of(page(), "Q1", (1942, 1962))
check("about: the text, its source, URL and license", (a["source"], a["license"], a["url"], a["text"].count("\n\n")),
      ("Wikipedia", "CC BY-SA 4.0", "https://en.wikipedia.org/wiki/Suspense_(radio_drama)", 1))
rejects = {"suspense": {"article": "Suspense (radio drama)", "reason": "test"}}
check("an editor's refusal of this article holds", SA.about_of(page(), "Q1", None, SA.rejected_for(rejects, "suspense", page()))[1],
      "editorial_reject")
check("control: a refusal names its article; another article is judged afresh",
      SA.rejected_for(rejects, "suspense", page("Suspense (1949 TV series)")), None)
check("the editorial file parses and every row names an article and a reason",
      all(r.get("article") and r.get("reason") for r in SA.load_rejects().values()), True)


# --- enrich_external -> projection -> web --------------------------------------------------
def research(path):
    d = sqlite3.connect(path)
    d.executescript("""
    CREATE TABLE series (key, name, genre, genres_otrr, is_librivox, first_date, last_date, networks);
    CREATE TABLE episodes (id, series_key, air_date, date_source, num, title, aka, state, rec_bucket, work_bucket,
        no_recommend, network, network_source, has_transcript);
    CREATE TABLE recordings (episode_id, rank, archive_id, file, format, kbps, length_s, variant, partial);
    CREATE TABLE episode_credits (episode_id, person_id, name, role, character);
    CREATE TABLE people (id, name, birth, death);
    """)
    d.executescript(EE.DDL.split("DROP TABLE IF EXISTS episode_witnesses;")[0])
    d.executemany("INSERT INTO series VALUES (?,?,?,?,?,?,?,?)", [
        ("suspense", "Suspense", None, None, 0, "1942-06-17", "1962-09-30", None),
        ("shadow", "The Shadow", None, None, 0, "1937-09-26", "1954-12-26", None)])
    eps = [("suspense|1943-05-25", "suspense", "1943-05-25", "Sorry, Wrong Number"),
           ("shadow|1938-01-02", "shadow", "1938-01-02", "The Silent Avenger")]
    d.executemany("INSERT INTO episodes VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)", [
        (i, k, dt, "filename", 1, t, None, "keep_clean", "rec_pd_published_age", "work_none_found", None, None, None, 0)
        for i, k, dt, t in eps])
    d.executemany("INSERT INTO recordings VALUES (?,?,?,?,?,?,?,?,?)", [
        (i, 0, "item" + str(n), "a.mp3", "VBR MP3", 64, 1700.0, None, 0) for n, (i, *_r) in enumerate(eps)])
    d.commit()
    return d


with tempfile.TemporaryDirectory() as tmp:
    src = os.path.join(tmp, "research.sqlite")
    d = research(src)
    matched = {"suspense": {"qid": "Q1"}, "shadow": {"qid": "Q9"}}
    items = {"Q1": {"enwiki": "Suspense (radio drama)"}, "Q9": {"enwiki": "The Shadow"}}
    about = {"pages": {"Suspense (radio drama)": page(),
                       "The Shadow": page("The Shadow", qid="Q9", sd="Fictional character",
                                          extract="The Shadow is a fictional character. The radio drama followed.")}}
    n, why = EE.write_about(d, matched, items, about, {"suspense": (1942, 1962), "shadow": (1937, 1954)}, rejects={})
    d.commit()
    check("enrich writes the passing article only", (n, dict(why)), (1, {"shortdesc_not_the_show": 1}))
    check("control: no cache, no rows", EE.write_about(d, matched, items, None, {}, rejects={})[0], 0)
    d.close()
    dst = os.path.join(tmp, "ear-drama.sqlite")
    B.build(src, dst)
    p = sqlite3.connect(dst)
    rows = dict((k, (t is not None, s, u)) for k, t, s, u in
                p.execute("SELECT key, about_text, about_source, about_url FROM series"))
    check("the projection copies the about columns, NULL together where none",
          rows, {"suspense": (True, "Wikipedia", "https://en.wikipedia.org/wiki/Suspense_(radio_drama)"),
                 "shadow": (False, None, None)})
    check("the manifest counts them", json.loads(p.execute("SELECT value FROM meta WHERE key = 'counts'").fetchone()[0])
          ["seriesAbout"], 1)
    p.close()
    web = os.path.join(tmp, "web")
    m = W.build(dst, web)
    sp = json.load(open(os.path.join(web, "series", "suspense.json")))
    check("the web series page carries about, with its license", (sorted(sp["about"]), sp["about"]["license"]),
          (["license", "source", "text", "url"], "CC BY-SA 4.0"))
    check("control: a series without one has no about key",
          "about" in json.load(open(os.path.join(web, "series", "shadow.json"))), False)
    check("the web manifest counts them", m["counts"]["seriesAbout"], 1)

# --- the real artifact, shape only ---------------------------------------------------------
real = os.environ.get("PROJECTION") or os.path.join(os.path.dirname(__file__), "..", "out", "publish", "ear-drama.sqlite")
if os.path.exists(real):
    p = sqlite3.connect(f"file:{real}?mode=ro", uri=True)
    if "about_text" in {r[1] for r in p.execute("PRAGMA table_info(series)")}:
        bad = 0
        for t, s_, u in p.execute("SELECT about_text, about_source, about_url FROM series "
                                  "WHERE COALESCE(about_text, about_source, about_url) IS NOT NULL"):
            if not (t and s_ == "Wikipedia" and u and u.startswith("https://en.wikipedia.org/wiki/")
                    and len(t) <= SA.MAX_CHARS and SA.END.search(t)):
                bad += 1
        check("real projection: every about is whole, sourced and linked", bad, 0)
    p.close()

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
