"""The web projection (tools/build_web_projection.py) against docs/CATALOG-CONTRACT.md §4.

    python3 tests/test_web_projection.py
A fixture proves each rule and its broken control; when out/web/ (or
$WEB_PROJECTION) exists, the gatekeeper and rights checks also run over every
file of the real build.
"""
import json
import os
import sqlite3
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import build_projection as B
import build_web_projection as W

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
        ("suspense", "Suspense", "OTR-Thriller", None, 0, "1942-06-17", "1962-09-30", '["CBS"]'),
        ("mrsorrowful", "Mr. Sorrowful", "OTR-Comedy", None, 0, "1950-01-01", "1950-12-31", None),
        ("speeches", "Speeches", None, None, 0, "1939-01-01", "1939-12-31", None)])
    eps = [
        ("suspense|1949-09-15", "suspense", "1949-09-15", "filename", 300, "The Night Reveals", None, "keep_clean",
         "rec_pd_published_age", None),
        ("suspense|1943-05-25", "suspense", "1943-05-25", "filename", 46, "Sorry, Wrong Number", None, "keep_clean",
         "rec_gov_work", None),
        ("suspense|tundated", "suspense", None, None, None, "Café Undated", None, "keep_clean", "rec_librivox", None),
        ("suspense|1944-02-24", "suspense", "1944-02-24", "filename", 80, "The Hitchhiker", None, "keep_unclaimed",
         "rec_orphan_unclaimed", None),
        ("mrsorrowful|1950-05-25", "mrsorrowful", "1950-05-25", "filename", 1, "Pilot", None, "keep_clean",
         "rec_librivox", None),
        ("speeches|1939-05-25", "speeches", "1939-05-25", "filename", 1, "Rede", None, "keep_clean",
         "rec_gov_work", "Nazi-state speech or broadcast"),
        ("suspense|1950-05-25", "suspense", "1950-05-25", "filename", 400, "Hidden Claim", None, "hide_claim",
         "rec_rights_holder_claim", None)]
    d.executemany("INSERT INTO episodes VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                  [(i, s, a, ds, n, t, aka, st, rb, "work_none_found", nr, None, None, 0)
                   for i, s, a, ds, n, t, aka, st, rb, nr in eps])
    d.executemany("INSERT INTO recordings VALUES (?,?,?,?,?,?,?,?,?)", [
        (e[0], 0, "item" + str(k), "file %d.mp3" % k, "VBR MP3", 64, 1700.0, None, 0) for k, e in enumerate(eps)] + [
        ("suspense|1943-05-25", 1, "afrs", "afrs.mp3", "VBR MP3", 128, 1690.0, "AFRS", 0)])
    d.executemany("INSERT INTO episode_credits VALUES (?,?,?,?,?)", [
        ("suspense|1943-05-25", "p1", "Agnes Moorehead", "cast", "Mrs. Stevenson"),
        ("suspense|1944-02-24", "p2", "Orson Welles", "cast", None)])
    d.executemany("INSERT INTO people VALUES (?,?,?,?)", [("p1", "Agnes Moorehead", "1900", "1974"),
                                                         ("p2", "Orson Welles", "1915", "1985")])
    d.commit()
    d.close()


def load(out, *parts):
    with open(os.path.join(out, *parts), encoding="utf-8") as f:
        return json.load(f)


def violations(out):
    """The gatekeeper and rights rules over every file of a built web projection: rule -> offenders."""
    v = {}
    index = {r[0] for r in load(out, "index", "series.json")["rows"]}
    listed = {}
    for f in os.listdir(os.path.join(out, "series")):
        page = load(out, "series", f)
        if page["key"] not in index:
            v.setdefault("every series page is in the index", []).append(page["key"])
        dates = [e[1] for e in page["episodes"] if e[1]]
        if dates != sorted(dates):
            v.setdefault("episodes run oldest first (R1)", []).append(page["key"])
        for e in page["episodes"]:
            listed[e[0]] = page["key"]
    clean_only = load(out, "manifest.json")["cleanOnly"]
    for f in os.listdir(os.path.join(out, "episodes")):
        for eid, d in load(out, "episodes", f).items():
            if listed.get(eid) != d[0]:
                v.setdefault("every shard id is on its series page in the index", []).append(eid)
            if W.shard_of(eid) + ".json" != f:
                v.setdefault("every id sits in its own shard", []).append(eid)
            if clean_only and d[7] != "clean":
                v.setdefault("the gate: clean rows only", []).append(eid)
            if d[7] == "clean" and d[8] not in W.RIGHTS_LINES:
                v.setdefault("every clean basis has its line", []).append(d[8])
    for f in os.listdir(os.path.join(out, "index", "days")):
        for r in load(out, "index", "days", f)["rows"]:
            if r[0] not in listed:
                v.setdefault("every day row is listed", []).append(r[0])
    lines = " ".join(load(out, "manifest.json")["rightsLines"].values()).lower()
    if "public domain" in lines:
        v["no rights line says public domain"] = [lines]
    return v


def search(out, q):
    """The browser's word-prefix search, in Python: every query word is a prefix of some indexed word."""
    words = [w for w in W.tokens(q) if len(w) >= 2]
    hits = None
    for w in words:
        try:
            terms = load(out, "search", "terms", W.term_file(w) + ".json")
        except FileNotFoundError:
            return []
        ns = set()
        for t, deltas in terms.items():
            if t.startswith(w):
                n = 0
                for dlt in deltas:
                    n += dlt
                    ns.add(n)
        hits = ns if hits is None else hits & ns
    docs = []
    chunk = load(out, "manifest.json")["search"]["docChunk"]
    for n in sorted(hits or []):
        docs.append(load(out, "search", "docs", f"{n // chunk}.json")[n % chunk][0])
    return docs


check("fnv1a: the empty string is the offset basis", W.fnv1a(""), 0x811C9DC5)
check("fnv1a: a published test vector", W.fnv1a("a"), 0xE40C292C)
check("fnv1a: UTF-8 bytes, not code points", W.fnv1a("é"), W.fnv1a("é"))
check("shard: three hex digits", W.shard_of("suspense|1943-05-25"), format(W.fnv1a("suspense|1943-05-25") & 0xFFF, "03x"))
check("tokens: unicode61 folding", W.tokens("Café, Sorry-Wrong_Number's"), ["cafe", "sorry", "wrong", "number", "s"])
check("term file: safe name for non-ASCII", W.term_file("ñu"), "xf175")

with tempfile.TemporaryDirectory() as tmp:
    raw, served = os.path.join(tmp, "raw.sqlite"), os.path.join(tmp, "served.sqlite")
    fixture(raw)
    B.build(raw, served)
    out = os.path.join(tmp, "web")
    m = W.build(served, out)
    check("gate closed by default", m["cleanOnly"], True)
    check("contract holds on the fixture", violations(out), {})
    page = load(out, "series", "suspense.json")
    ids = [e[0] for e in page["episodes"]]
    check("series page: oldest first, undated last (R1)", ids,
          ["suspense|1943-05-25", "suspense|1949-09-15", "suspense|tundated"])
    check("series page: seasons", page["seasons"], ["1942-43", "1949-50"])
    everything = ""
    for root, _d, fs in os.walk(out):
        for f in fs:
            everything += open(os.path.join(root, f), encoding="utf-8").read()
    check("control: an unclaimed id never appears with the gate closed", "suspense|1944-02-24" in everything, False)
    check("control: an unclaimed episode's people never appear either", "Orson Welles" in everything, False)
    check("control: a hidden id never appears", "suspense|1950-05-25" in everything, False)
    detail = load(out, "episodes", W.shard_of("suspense|1943-05-25") + ".json")["suspense|1943-05-25"]
    check("detail: versions in rank order", [r[5] for r in detail[12]], [None, "AFRS"])
    check("detail: credits joined to people", detail[13][0][:3], ["Agnes Moorehead", "cast", "Mrs. Stevenson"])
    check("search: word-prefix across words", search(out, "sorr wrong"), ["suspense|1943-05-25"])
    check("search: people are words too", search(out, "moore"), ["suspense|1943-05-25"])
    check("search: diacritics fold", search(out, "cafe"), ["suspense|tundated"])
    check("control: search is never substring", search(out, "orry"), [])
    listen = load(out, "index", "listen.json")
    shelved = {r[0] for s in listen["shelves"] for r in s["series"]} | {r[0] for r in listen["most"]}
    check("control: a never-recommended series stays off the shelves", "speeches" in shelved, False)
    day = [r[0] for r in load(out, "index", "days", "05-25.json")["rows"]]
    check("this day: oldest first, never-recommended left out", day, ["suspense|1943-05-25", "mrsorrowful|1950-05-25"])
    check("never recommended, always findable", search(out, "rede"), ["speeches|1939-05-25"])

    opened = os.path.join(tmp, "web-open")
    W.build(served, opened, include_unclaimed=True)
    check("gate open: the unclaimed row is served", "suspense|1944-02-24" in
          [e[0] for e in load(opened, "series", "suspense.json")["episodes"]], True)
    check("contract holds with the gate open", violations(opened), {})

    # Broken controls: a stray shard id, a misplaced id, and a leaked unclaimed row must each be caught.
    sh = W.shard_of("suspense|1943-05-25") + ".json"
    rows = load(out, "episodes", sh)
    rows["ghost|1950-01-01"] = rows["suspense|1943-05-25"][:]
    rows["suspense|1943-05-25"][7] = "unclaimed"
    W.dump(os.path.join(out, "episodes", sh), rows)
    got = violations(out)
    check("control: the gatekeeper catches a stray id", got.get("every shard id is on its series page in the index"),
          ["ghost|1950-01-01"])
    check("control: the gate catches a leaked unclaimed row", got.get("the gate: clean rows only"),
          ["suspense|1943-05-25"])

real = os.environ.get("WEB_PROJECTION") or os.path.join(os.path.dirname(__file__), "..", "out", "web")
if os.path.exists(os.path.join(real, "manifest.json")):
    check("contract holds on the real web build", violations(real), {})
    check("real build: Sorry, Wrong Number is found by its words", "suspense|1948-11-18" in search(real, "sorry wrong")
          if not load(real, "manifest.json")["cleanOnly"] else True, True)
elif os.environ.get("WEB_PROJECTION"):
    check("the web build named by WEB_PROJECTION exists", False, True)   # asked for, so never a skip
else:
    print("  SKIP  real web build: out/web/ not built")

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
