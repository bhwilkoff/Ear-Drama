"""The Listen shelves (tools/shelves.py) in both projections, against docs/CATALOG-CONTRACT.md §5.

    python3 tests/test_listen_shelves.py
Fixture databases prove each guarantee and break it once; when a real
projection exists ($PROJECTION or out/publish/ear-drama.sqlite, $WEB_PROJECTION
or out/web/), its published list is checked for shape only (never its contents).
"""
import json
import os
import sqlite3
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import build_projection as B
import build_web_projection as W
import genres as G
import shelves as SH

ran = failed = 0


def check(name, got, want):
    global ran, failed
    ran += 1
    if got != want:
        failed += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


# --- onThisDay: the golden cases every client's query is held to --------------
with open(os.path.join(os.path.dirname(__file__), "golden", "on_this_day.json"), encoding="utf-8") as f:
    golden = json.load(f)
for c in golden["cases"]:
    check(f"onThisDay {c['month']:02d}-{c['day']:02d} limit {c.get('limit')}",
          SH.on_this_day(golden["episodes"], c["month"], c["day"], c.get("limit", SH.SHELF_LIMIT)), c["want"])
check("control: a month/day swap is a different day", SH.on_this_day(golden["episodes"], 12, 5) ==
      SH.on_this_day(golden["episodes"], 5, 12), False)


# --- fixture: a research database the real builders read -----------------------
# (series key, RadioEchoes tag, [(date, num, state, no_recommend)])
CLEAN, UNCL, HIDE = "keep_clean", "keep_unclaimed", "hide_claim"
SERIES = [
    ("d1", "OTR-Drama", [("1945-03-01", 1, CLEAN, None), ("1945-03-08", 2, CLEAN, None), ("1945-03-15", 3, CLEAN, None)]),
    ("d2", "OTR-Drama", [(None, None, CLEAN, None), ("1950-05-25", 4, CLEAN, None)]),
    ("d3", "OTR-Drama", [("1948-05-25", 9, CLEAN, None), ("1948-05-25", 2, CLEAN, None)]),
    ("d4", "OTR-Drama", [("1939-05-25", 1, CLEAN, "Nazi-state speech or broadcast"), ("1941-01-01", 1, HIDE, None),
                         ("1942-01-01", 7, CLEAN, None), (None, None, CLEAN, None)]),
    ("d5", "OTR-Drama", [(None, 3, CLEAN, None), (None, 1, CLEAN, None)]),
    ("m1", "OTR-Thriller", [("1943-05-25", 46, UNCL, None), ("1949-09-15", 300, CLEAN, None)]),
    ("m2", "OTR-Thriller", [("1944-01-01", 1, CLEAN, None)]),
    ("m3", "OTR-Thriller", [("1944-02-01", 1, CLEAN, None)]),
    ("m4", "OTR-Thriller", [("1944-03-01", 1, UNCL, None)]),
    ("m5", "OTR-Thriller", [("1944-04-01", 1, UNCL, None), ("1944-04-08", 2, UNCL, None)]),
    ("w1", "OTR-Western", [("1952-01-01", 1, CLEAN, None)]),
    ("w2", "OTR-Western", [("1952-01-02", 1, CLEAN, None)]),
    ("w3", "OTR-Western", [("1952-01-03", 1, CLEAN, None)]),
    ("w4", "OTR-Western", [("1952-01-04", 1, CLEAN, None)]),
    ("w5", "OTR-Western", [("1952-01-05", 1, CLEAN, "WWII propaganda")]),
    ("x1", None, [("1947-05-25", 1, CLEAN, None)]),
]


def eid(key, date, num):
    return f"{key}|{date or 'undated'}-{num}"


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
    for key, tag, eps in SERIES:
        d.execute("INSERT INTO series VALUES (?,?,?,?,?,?,?,?)", (key, key.upper(), tag, None, 0, None, None, None))
        for date, num, state, nr in eps:
            i = eid(key, date, num)
            d.execute("INSERT INTO episodes VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                      (i, key, date, "filename", num, "T " + i, None, state,
                       "rec_gov_work" if state == CLEAN else "rec_orphan_unclaimed", "work_none_found", nr,
                       None, None, 0))
            d.execute("INSERT INTO recordings VALUES (?,?,?,?,?,?,?,?,?)",
                      (i, 0, "item", i.replace("|", "_") + ".mp3", "VBR MP3", 64, 1700.0, None, 0))
    d.commit()
    d.close()


def native_sets(db):
    c = sqlite3.connect(db)
    served = {r[0] for r in c.execute("SELECT id FROM episodes")}
    rec = {r[0] for r in c.execute("SELECT id FROM episodes WHERE no_recommend IS NULL")}
    meta = {k: json.loads(v) for k, v in c.execute("SELECT key, value FROM meta")}
    c.close()
    return meta, served, rec


def strings(x):
    if isinstance(x, str):
        yield x
    elif isinstance(x, dict):
        for k, v in x.items():
            yield from strings(v)
    elif isinstance(x, list):
        for v in x:
            yield from strings(v)


def no_text(shelves, served):
    """Every string a published list carries is a rule, a genre key, or a served id: no copy rides along."""
    return sorted(s for s in strings(shelves) if s not in set(SH.RULES) | set(G.GENRES) | served)


def genre_order(shelves):
    return [s.get("genre") for s in shelves if s["rule"] == "genreFirsts"]


with tempfile.TemporaryDirectory() as tmp:
    raw, served_db = os.path.join(tmp, "raw.sqlite"), os.path.join(tmp, "served.sqlite")
    fixture(raw)
    B.build(raw, served_db)
    meta, served, rec = native_sets(served_db)
    shelves = meta.get("listenShelves")
    check("native: the meta key exists", shelves is not None, True)
    check("native: guarantees hold", SH.violations(shelves, served, rec), {})
    check("native: no text, only rules, genres, and served ids", no_text(shelves, served), [])
    check("native: onThisDay first, a query by rule (no ids)", shelves[0], {"rule": "onThisDay"})
    check("native: genres in GENRES order, a floor of MIN_SERIES", genre_order(shelves), ["drama", "mystery"])
    check("control: four recommendable westerns are under the floor", "western" in genre_order(shelves), False)
    westerns = [(eid(k, d, n), k, d, n, nr) for k, _t, eps in SERIES if k[0] == "w" for d, n, _s, nr in eps]
    wseries = {k: ("western", len(eps)) for k, _t, eps in SERIES if k[0] == "w"}
    check("control: the floor counts recommendable series, so a floor of 4 makes the western shelf",
          genre_order(SH.listen_shelves(westerns, wseries, min_series=4)), ["western"])
    check("control: and a floor of 5 does not (w5 is never recommended)",
          genre_order(SH.listen_shelves(westerns, wseries, min_series=5)), [])
    drama = next(s for s in shelves if s.get("genre") == "drama")["episodes"]
    check("genreFirsts: one per series, most served episodes first, ties by key, earliest recommendable", drama, [
        eid("d1", "1945-03-01", 1), eid("d4", "1942-01-01", 7), eid("d2", "1950-05-25", 4), eid("d3", "1948-05-25", 2),
        eid("d5", None, 1)])
    check("control: the earlier never-recommended and hidden episodes are passed over",
          {eid("d4", "1939-05-25", 1), eid("d4", "1941-01-01", 1)} & set(drama), set())
    check("control: a series with no genre is on no genre shelf", any(i.startswith("x1|") for s in shelves
                                                                      for i in s.get("episodes", [])), False)
    mystery = next(s for s in shelves if s.get("genre") == "mystery")["episodes"]
    check("native: unclaimed rows count and show", mystery[0], eid("m1", "1943-05-25", 46))

    out = os.path.join(tmp, "web")
    m = W.build(served_db, out)
    wshelves = m.get("listenShelves")
    with open(os.path.join(out, "manifest.json"), encoding="utf-8") as fh:
        check("web: the manifest key exists", "listenShelves" in json.load(fh), True)
    wserved = set()
    for f in os.listdir(os.path.join(out, "episodes")):
        with open(os.path.join(out, "episodes", f), encoding="utf-8") as fh:
            wserved |= set(json.load(fh))
    wrec = wserved & rec
    check("web: guarantees hold over the web's own served set", SH.violations(wshelves, wserved, wrec), {})
    check("web: no text", no_text(wshelves, wserved), [])
    check("web: the gate closed drops mystery under the floor (3 clean series)", genre_order(wshelves), ["drama"])
    check("web: the drama shelf matches native (all clean)", wshelves[1], shelves[1])
    opened = W.build(served_db, os.path.join(tmp, "web-open"), include_unclaimed=True)["listenShelves"]
    check("web, gate open: the same list as native", opened, shelves)

    # Break each guarantee once.
    def broken(f):
        s = json.loads(json.dumps(shelves))
        f(s)
        return sorted(SH.violations(s, served, rec))
    check("control: a missing key is caught", sorted(SH.violations(None, served, rec)),
          ["listenShelves is a non-empty list"])
    check("control: an unknown rule is caught", broken(lambda s: s.append({"rule": "mostEpisodes"})),
          ["every rule is from the known set"])
    check("control: a written title is caught", broken(lambda s: s[1].update(title="Golden age drama")),
          ["a shelf carries only its rule's keys (no text)"])
    check("control: the no-text sweep catches it too",
          no_text([{**shelves[1], "title": "Golden age drama"}], served), ["Golden age drama"])
    check("control: a hidden episode is caught", broken(lambda s: s[1]["episodes"].append(eid("d4", "1941-01-01", 1))),
          ["every published episode is served"])
    check("control: a never-recommended episode is caught",
          broken(lambda s: s[1]["episodes"].append(eid("d4", "1939-05-25", 1))),
          ["every published episode is recommendable"])
    check("control: a genre outside the eight is caught", broken(lambda s: s[1].update(genre="horror")),
          ["a genre shelf names one of the eight genres"])
    check("control: an empty genre shelf is caught", broken(lambda s: s[1].update(episodes=[])),
          ["an episode shelf is never empty"])


    check("native: a registry without download counts publishes no popularity shelf",
          [s["rule"] for s in shelves if s["rule"] == "mostDownloaded"], [])

    # --- mostDownloaded (Decision 067): archive.org's own download counts ---------
    pop_raw, pop_db = os.path.join(tmp, "pop.sqlite"), os.path.join(tmp, "pop-served.sqlite")
    fixture(pop_raw)
    c = sqlite3.connect(pop_raw)
    c.execute("UPDATE recordings SET archive_id = 'item_' || substr(episode_id, 1, instr(episode_id, '|') - 1)")
    c.execute("UPDATE recordings SET archive_id = 'shared' WHERE episode_id LIKE 'd3|%'")
    c.execute("CREATE TABLE items (id, downloads)")
    # m5 is all unclaimed; w5 never recommended; x1 has no count read (absent, not zero)
    counts = {"item_d1": 50, "item_d2": 900, "shared": 40, "item_d4": 10, "item_d5": 700, "item_m1": 5000,
              "item_m2": 80, "item_m5": 9999, "item_w1": 300, "item_w5": 8000}
    c.executemany("INSERT INTO items VALUES (?,?)", counts.items())
    c.commit()
    c.close()
    B.build(pop_raw, pop_db)
    pmeta, pserved, prec = native_sets(pop_db)
    pshelves = pmeta["listenShelves"]
    pop = next((s for s in pshelves if s["rule"] == "mostDownloaded"), None)
    check("native: mostDownloaded follows onThisDay and comes before the genres",
          [s["rule"] for s in pshelves][:3], ["onThisDay", "mostDownloaded", "genreFirsts"])
    check("native: guarantees hold with the popularity shelf", SH.violations(pshelves, pserved, prec), {})
    check("native: popularity shelf carries no text", no_text(pshelves, pserved), [])
    check("mostDownloaded: most downloaded series first, each by its earliest recommendable episode",
          pop["episodes"], [eid("m5", "1944-04-01", 1), eid("m1", "1943-05-25", 46), eid("d2", "1950-05-25", 4),
                            eid("d5", None, 1), eid("w1", "1952-01-01", 1), eid("m2", "1944-01-01", 1),
                            eid("d1", "1945-03-01", 1), eid("d3", "1948-05-25", 2), eid("d4", "1942-01-01", 7)])
    check("control: a never-recommended series is never on it, however downloaded",
          any(i.startswith("w5|") for i in pop["episodes"]), False)
    check("control: a series whose count was never read is not ranked as zero, it is absent",
          any(i.startswith("x1|") for i in pop["episodes"]), False)
    c = sqlite3.connect(pop_db)
    check("native: the projection carries the counts of its own items only",
          dict(c.execute("SELECT archive_id, downloads FROM items")).get("item_m5"), 9999)
    c.close()
    wpop = next((s for s in W.build(pop_db, os.path.join(tmp, "pop-web"))["listenShelves"]
                 if s["rule"] == "mostDownloaded"), None)
    check("web: the gate closed ranks only what the web serves (no unclaimed m5)",
          wpop and wpop["episodes"][:2], [eid("m1", "1949-09-15", 300), eid("d2", "1950-05-25", 4)])
    check("control: under MIN_SERIES ranked series, no popularity shelf",
          [s["rule"] for s in SH.listen_shelves([("a|1", "a", None, 1, None)], {"a": ("drama", 1)},
                                                downloads={"a": 5})], ["onThisDay"])
    check("control: a written title on it is caught",
          sorted(SH.violations([{"rule": "mostDownloaded", "episodes": pop["episodes"], "title": "Popular"}],
                               pserved, prec)), ["a shelf carries only its rule's keys (no text)"])

    # --- series.downloads: Browse's "Popular" key (contract §3.3), the shelf's per-series sum ---
    want = {"d1": 50, "d2": 900, "d3": 40, "d4": 10, "d5": 700, "m1": 5000, "m2": 80, "m5": 9999, "w1": 300}
    c = sqlite3.connect(pop_db)
    native_dl = dict(c.execute("SELECT key, downloads FROM series"))
    c.close()
    check("native series.downloads: the sum per series; unread and never-recommended are NULL, never 0",
          native_dl, {**{k: None for k, _t, _e in SERIES}, **want})
    with open(os.path.join(tmp, "pop-web", "index", "series.json"), encoding="utf-8") as fh:
        idx = json.load(fh)
    check("web index: downloads is a published field", "downloads" in idx["fields"], True)
    web_dl = {r[0]: r[idx["fields"].index("downloads")] for r in idx["rows"]}
    check("web index: the gate closed sums only what the web serves; unread is null",
          {k: v for k, v in web_dl.items() if v is not None}, {k: v for k, v in want.items() if k != "m5"})
    check("control: a series with no count read is in the index with null, not absent and not 0",
          ("x1" in web_dl, web_dl.get("x1")), (True, None))
    check("control: a zero count is not a count", SH.browse_downloads({"a": 0, "b": 3}, {"a", "b"}), {"b": 3})
    c = sqlite3.connect(served_db)
    check("control: a registry without counts publishes the column all NULL",
          c.execute("SELECT COUNT(*) FROM series WHERE downloads IS NOT NULL").fetchone()[0], 0)
    c.close()
    check("series_downloads: an item counts once per series, however many episodes it holds",
          SH.series_downloads([("a", "i"), ("a", "i"), ("a", "j"), ("b", "i")], {"i": 10, "j": 1}), {"a": 11, "b": 10})


# --- the counts themselves: harvest_downloads.py and build_db.download_counts ---
import harvest_downloads as HD  # noqa: E402
import build_db as BD  # noqa: E402


def stub_get(answers):
    calls = []

    def get(url, params, pause=0.0):
        calls.append(params["q"])
        a = answers.pop(0)
        return None if a is None else {"response": {"docs": a}}
    return get, calls


get, calls = stub_get([[{"identifier": "a", "downloads": 7}, {"identifier": "b"}, {"identifier": "zz", "downloads": 1}],
                       None])
doc = HD.harvest(["a", "b", "c", "d"], 2, 0, previous={"items": {"c": 3}}, get=get)
check("harvest: one batched identifier lookup per batch", calls, ['identifier:("a" OR "b")', 'identifier:("c" OR "d")'])
check("harvest: a count read is kept; one archive.org omits is not written", doc["items"], {"a": 7, "c": 3})
check("harvest: a batch that could not be read is unread, never zero, and keeps the earlier count",
      (doc["unread"], doc["items"].get("c"), "d" in doc["items"]), (["c", "d"], 3, False))
check("control: an id archive.org returned that was not asked for is ignored", "zz" in doc["items"], False)
with tempfile.TemporaryDirectory() as cache:
    ia_write = HD.ia.write_json
    ia_write(os.path.join(cache, "seeds.json"), {"items": {"a": {"downloads": 5}, "b": {"downloads": None}, "c": {}}})
    ia_write(os.path.join(cache, "downloads.json"), {"items": {"a": 9, "d": 2}})
    check("build_db: the newer harvest wins over the seed scrape; an unread item is absent",
          BD.download_counts(cache), {"a": 9, "d": 2})
    os.remove(os.path.join(cache, "downloads.json"))
    check("control: without the harvest, the seed scrape's counts", BD.download_counts(cache), {"a": 5})


# --- front matter is not where a shelf starts (2026-10-23, the web's Drama shelf) ---
fm_series = {"rd": ("drama", 3), "otr": ("drama", 2), "act": ("drama", 2)}
fm_eps = [
    ("rd|s0", "rd", None, 0, None, "Dramatis Personae"),
    ("rd|s1", "rd", None, 1, None, "Chapter 1"),
    ("otr|1", "otr", "1950-01-01", 1, None, "Cartoon Characters"),
    ("act|s0", "act", None, 0, None, "Personen - 1. Aufzug"),
    ("act|s1", "act", None, 1, None, "Zweiter Aufzug"),
]
firsts = SH.genre_firsts(fm_eps, fm_series, "drama")
check("a cast list is skipped for the series' first real section", "rd|s1" in firsts and "rd|s0" not in firsts, True)
check("a program titled with the word mid-title is kept", "otr|1" in firsts, True)
check("a section that also carries the first act is kept", "act|s0" in firsts, True)
check("control: a collection's closing Introduction is front matter",
      SH.front_matter(("x", "x", None, 0, None, "Frontier Gentleman Introduction")), True)
check("control: a row without a title is never front matter", SH.front_matter(("x", "x", None, 0, None)), False)


# --- the real projections: shape only, never contents ---------------------------
def real_shape(name, shelves, served, rec):
    check(f"{name}: listenShelves published", isinstance(shelves, list), True)
    if isinstance(shelves, list):
        check(f"{name}: guarantees hold", SH.violations(shelves, served, rec), {})
        check(f"{name}: no text", no_text(shelves, served), [])
        check(f"{name}: onThisDay leads", shelves[:1], [{"rule": "onThisDay"}])
        order = genre_order(shelves)
        check(f"{name}: genres in GENRES order", order, [g for g in G.GENRES if g in order])


real = os.environ.get("PROJECTION") or os.path.join(os.path.dirname(__file__), "..", "out", "publish", "ear-drama.sqlite")
if os.path.exists(real):
    meta, served, rec = native_sets(real)
    if "listenShelves" in meta or os.environ.get("PROJECTION"):
        real_shape("real projection", meta.get("listenShelves"), served, rec)
    else:
        # A local build from before the key; PROJECTION names one that must carry it.
        print("  SKIP  real projection: built before listenShelves (rebuild to check it)")
elif os.environ.get("PROJECTION"):
    check("the projection named by PROJECTION exists", False, True)
else:
    print("  SKIP  real projection: out/publish/ear-drama.sqlite not built")

real_web = os.environ.get("WEB_PROJECTION") or os.path.join(os.path.dirname(__file__), "..", "out", "web")
if os.path.exists(os.path.join(real_web, "manifest.json")):
    with open(os.path.join(real_web, "manifest.json"), encoding="utf-8") as fh:
        wm = json.load(fh)
    ws = set()
    for f in os.listdir(os.path.join(real_web, "episodes")):
        with open(os.path.join(real_web, "episodes", f), encoding="utf-8") as fh:
            ws |= set(json.load(fh))
    # The web publishes no no_recommend field; a genre shelf's ids must at least be served there.
    if "listenShelves" in wm or os.environ.get("WEB_PROJECTION"):
        real_shape("real web build", wm.get("listenShelves"), ws, ws)
    else:
        print("  SKIP  real web build: built before listenShelves (rebuild to check it)")
elif os.environ.get("WEB_PROJECTION"):
    check("the web build named by WEB_PROJECTION exists", False, True)
else:
    print("  SKIP  real web build: out/web/ not built")

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
