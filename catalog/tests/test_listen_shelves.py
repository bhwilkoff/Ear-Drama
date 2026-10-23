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
          ["a genre shelf is never empty"])


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
    real_shape("real projection", meta.get("listenShelves"), served, rec)
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
    real_shape("real web build", wm.get("listenShelves"), ws, ws)
elif os.environ.get("WEB_PROJECTION"):
    check("the web build named by WEB_PROJECTION exists", False, True)
else:
    print("  SKIP  real web build: out/web/ not built")

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
