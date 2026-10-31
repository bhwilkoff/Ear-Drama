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
import shutil
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
        ("suspense|1949-09-15", "p1", "Agnes Moorehead", "cast", None),
        ("suspense|1943-05-25", "p1", "Agnes Moorehead", "narrator", None),
        ("suspense|1944-02-24", "p2", "Orson Welles", "cast", None)])
    d.executemany("INSERT INTO people VALUES (?,?,?,?)", [("p1", "Agnes Moorehead", "1900", "1974"),
                                                         ("p2", "Orson Welles", "1915", "1985")])
    d.execute("CREATE TABLE sponsors (series_key, otrr_idp, sponsor, start, end, source)")
    d.executemany("INSERT INTO sponsors VALUES (?,?,?,?,?,?)", [
        ("suspense", "1", "Roma Wines", "1943-01-01", "1943-12-31", "x"),
        ("suspense", "1", "Autolite", "1948-01-01", "", "x"),
        ("suspense", "1", "Sustained", "1949-01-01", "1949-12-31", "x"),
        ("suspense", "1", "Undated Soap", "", "", "x")])
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
    for f in sorted(os.listdir(os.path.join(out, "series"))):
        page = load(out, "series", f)
        if page["key"] not in index:
            v.setdefault("every series page is in the index", []).append(page["key"])
        dates = [e[1] for e in page["episodes"] if e[1]]
        if dates != sorted(dates):
            v.setdefault("episodes run oldest first (R1)", []).append(page["key"])
        for e in page["episodes"]:
            listed[e[0]] = page["key"]
    clean_only = load(out, "manifest.json")["cleanOnly"]
    with_transcript = set()
    ti = load(out, "manifest.json")["fields"]["detail"].index("transcript")
    for f in sorted(os.listdir(os.path.join(out, "episodes"))):
        for eid, d in load(out, "episodes", f).items():
            if d[ti]:
                with_transcript.add(eid)
            if listed.get(eid) != d[0]:
                v.setdefault("every shard id is on its series page in the index", []).append(eid)
            if W.shard_of(eid) + ".json" != f:
                v.setdefault("every id sits in its own shard", []).append(eid)
            if clean_only and d[7] != "clean":
                v.setdefault("the gate: clean rows only", []).append(eid)
            if d[7] == "clean" and d[8] not in W.RIGHTS_LINES:
                v.setdefault("every clean basis has its line", []).append(d[8])
    # withPerson: the shard shape the browser reads (API.personPage), and the gatekeeper over its rows.
    fields = load(out, "manifest.json")["fields"]
    people = {}
    for f in sorted(os.listdir(os.path.join(out, "people"))) if os.path.isdir(os.path.join(out, "people")) else []:
        for pid, p in load(out, "people", f).items():
            people[pid] = p
            if W.shard_of(pid) + ".json" != f:
                v.setdefault("every person sits in its own shard", []).append(pid)
            if len(p) != len(fields["person"]) or any(len(c) != len(fields["personCredit"]) for c in p[4]):
                v.setdefault("person rows have the published fields", []).append(pid)
                continue
            if not p[4]:
                v.setdefault("a person page has at least one credit", []).append(pid)
            for c in p[4]:
                if listed.get(c[0]) != c[4]:
                    v.setdefault("every person credit is listed on its series page", []).append(c[0])
            dates = [c[1] for c in p[4] if c[1]]
            if dates != sorted(dates):
                v.setdefault("a person's credits run oldest first (R1)", []).append(pid)
    sp = os.path.join(out, "search", "people")
    for f in sorted(os.listdir(sp)) if os.path.isdir(sp) else []:
        d = load(out, "search", "people", f)
        for r in d["rows"]:
            if len(r) != len(fields["people"]) or r[0] not in people:
                v.setdefault("every people search row has its person page", []).append(r[0])
            elif f[:-5] not in {W.term_file(w) for w in W.tokens(r[1]) if len(w) >= 2}:
                v.setdefault("a person is filed under a word of their name", []).append(r[0])
            elif len(people[r[0]]) != len(fields["person"]):
                continue  # a malformed person row is reported by its own rule above, never indexed here
            elif r[2] != len({c[0] for c in people[r[0]][4]}):
                v.setdefault("a search row counts the person's episodes", []).append(r[0])
    for f in sorted(os.listdir(os.path.join(out, "index", "days"))):
        for r in load(out, "index", "days", f)["rows"]:
            if r[0] not in listed:
                v.setdefault("every day row is listed", []).append(r[0])
    # What is said and when it aired (search/said, search/dates): doc numbers the browser can resolve.
    m = load(out, "manifest.json")
    chunk = m["search"]["docChunk"]
    docs = []
    for k in range(len(os.listdir(os.path.join(out, "search", "docs")))):
        docs += load(out, "search", "docs", f"{k}.json")
    sd = os.path.join(out, "search", "said")
    for f in sorted(os.listdir(sd)) if os.path.isdir(sd) else []:
        for w, deltas in load(out, "search", "said", f).items():
            if W.term_file(w) + ".json" != f or len(w) < m["search"]["saidMinWord"]:
                v.setdefault("a transcript word is filed under its term file, long enough", []).append(w)
            if any(d_ <= 0 for d_ in deltas[1:]) or not deltas or deltas[0] < 0:
                v.setdefault("transcript doc numbers rise", []).append(w)
                continue
            n = 0
            for d_ in deltas:
                n += d_
                if n >= len(docs) or docs[n][0] not in with_transcript:
                    v.setdefault("a transcript word finds only a doc whose transcript is shown", []).append(w)
                    break
    dd = os.path.join(out, "search", "dates")
    dated = 0
    for f in sorted(os.listdir(dd)) if os.path.isdir(dd) else []:
        rows = load(out, "search", "dates", f)["rows"]
        dated += len(rows)
        if rows != sorted(rows, key=lambda r: (r[2], r[4])):
            v.setdefault("a year's dates run oldest first", []).append(f)
        for r in rows:
            n = r[4]
            if not r[2].startswith(f[:-5]) or n >= len(docs) or docs[n] != r[:4]:
                v.setdefault("a date row is its doc's own row, in its year", []).append(f"{f}:{n}")
    if os.path.isdir(dd) and dated != sum(1 for r in docs if r[2]):
        v["every dated doc is in its year once"] = [dated]
    # Forwarding ids (contract §3.5): an alias ends at a listed id; a forwarded or tombstoned id is not listed.
    fwd = load(out, "index", "aliases.json") if os.path.exists(os.path.join(out, "index", "aliases.json")) else {}
    tp = os.path.join(out, "index", "tombstones.json")
    tombs = load(out, "index", "tombstones.json") if os.path.exists(tp) else []
    for o, n in sorted(fwd.items()):
        if n not in listed:
            v.setdefault("every alias ends at a listed episode", []).append(o)
        if o in listed:
            v.setdefault("an aliased id is not listed", []).append(o)
    for t in tombs:
        if t in listed:
            v.setdefault("a tombstoned id is not listed", []).append(t)
    if tombs != sorted(set(tombs)):
        v["tombstones are sorted and unique"] = [len(tombs)]
    # The same for series keys: an alias ends at an indexed series; a forwarded or tombstoned key is not indexed.
    sp = os.path.join(out, "index", "series-aliases.json")
    s_fwd = load(out, "index", "series-aliases.json") if os.path.exists(sp) else {}
    stp = os.path.join(out, "index", "series-tombstones.json")
    s_tombs = load(out, "index", "series-tombstones.json") if os.path.exists(stp) else []
    for o, n in sorted(s_fwd.items()):
        if n not in index:
            v.setdefault("every series alias ends at an indexed series", []).append(o)
        if o in index:
            v.setdefault("an aliased series key is not indexed", []).append(o)
    for t in s_tombs:
        if t in index:
            v.setdefault("a tombstoned series key is not indexed", []).append(t)
    if s_tombs != sorted(set(s_tombs)):
        v["series tombstones are sorted and unique"] = [len(s_tombs)]
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


def said(out, q):
    """The browser's transcript search, in Python: every query word of saidMinWord or more begins a word said."""
    m = load(out, "manifest.json")
    words = [w for w in W.tokens(q) if len(w) >= m["search"]["saidMinWord"]]
    hits = None
    for w in words:
        try:
            terms = load(out, "search", "said", W.term_file(w) + ".json")
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
    chunk = m["search"]["docChunk"]
    return [load(out, "search", "docs", f"{n // chunk}.json")[n % chunk][0] for n in sorted(hits or [])]


def aired(out, prefix):
    """The docs aired on a date prefix (YYYY, YYYY-MM, YYYY-MM-DD), oldest first."""
    try:
        rows = load(out, "search", "dates", prefix[:4] + ".json")["rows"]
    except FileNotFoundError:
        return []
    return [r[0] for r in rows if r[2].startswith(prefix)]


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
    with sqlite3.connect(served) as c:   # forwarding as the served projection publishes it (contract §3.5)
        c.executemany("INSERT INTO episode_aliases VALUES (?,?)",
                      [("suspense|old-slug", "suspense|1943-05-25"), ("suspense|1921-02-24", "suspense|1944-02-24")])
        c.execute("INSERT INTO episode_tombstones VALUES ('suspense|gone')")
        c.executemany("INSERT INTO series_key_aliases VALUES (?,?)", [("suspence", "suspense"), ("gated", "nowhere")])
        c.execute("INSERT INTO series_key_tombstones VALUES ('folkweave')")
    out = os.path.join(tmp, "web")
    m = W.build(served, out)
    check("gate closed by default", m["cleanOnly"], True)
    check("contract holds on the fixture", violations(out), {})
    idx = load(out, "index", "series.json")
    sn = idx["fields"].index("sortName")
    check("series index carries sortName", {r[0]: r[sn] for r in idx["rows"]},
          {"suspense": "suspense", "mrsorrowful": "mr. sorrowful", "speeches": "speeches"})
    check("series index is ordered by sortName", [r[sn] for r in idx["rows"]], sorted(r[sn] for r in idx["rows"]))
    page = load(out, "series", "suspense.json")
    ids = [e[0] for e in page["episodes"]]
    check("series page: oldest first, undated last (R1)", ids,
          ["suspense|1943-05-25", "suspense|1949-09-15", "suspense|tundated"])
    check("series page: seasons", page["seasons"], ["1942-43", "1949-50"])
    sp_i = load(out, "manifest.json")["fields"]["detail"].index("sponsor")
    check("detail shard carries the computed sponsor, null where none covers",
          [load(out, "episodes", W.shard_of(i) + ".json")[i][sp_i] for i in ("suspense|1943-05-25", "suspense|1949-09-15")],
          ["Roma Wines", None])
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
    check("search: people are words too", search(out, "moore"), ["suspense|1943-05-25", "suspense|1949-09-15"])
    check("search: diacritics fold", search(out, "cafe"), ["suspense|tundated"])
    check("control: search is never substring", search(out, "orry"), [])
    listen = load(out, "index", "listen.json")
    shelved = {r[0] for s in listen["shelves"] for r in s["series"]} | {r[0] for r in listen["most"]}
    check("control: a never-recommended series stays off the shelves", "speeches" in shelved, False)
    day = [r[0] for r in load(out, "index", "days", "05-25.json")["rows"]]
    check("this day: oldest first, never-recommended left out", day, ["suspense|1943-05-25", "mrsorrowful|1950-05-25"])
    check("never recommended, always findable", search(out, "rede"), ["speeches|1939-05-25"])
    check("dates: a year, oldest first", aired(out, "1943"), ["suspense|1943-05-25"])
    check("dates: a month", aired(out, "1950-05"), ["mrsorrowful|1950-05-25"])
    check("dates: a day", aired(out, "1939-05-25"), ["speeches|1939-05-25"])
    check("control: a day nothing aired finds nothing", aired(out, "1939-05-26"), [])
    check("control: an undated episode is in no year",
          any("suspense|tundated" in aired(out, f[:-5]) for f in os.listdir(os.path.join(out, "search", "dates"))),
          False)
    check("control: no transcript cache, no transcript words", os.path.isdir(os.path.join(out, "search", "said")), False)

    opened = os.path.join(tmp, "web-open")
    W.build(served, opened, include_unclaimed=True)
    check("gate open: the unclaimed row is served", "suspense|1944-02-24" in
          [e[0] for e in load(opened, "series", "suspense.json")["episodes"]], True)
    check("contract holds with the gate open", violations(opened), {})

    # withPerson (contract §5): every served credit, oldest first, the gate applied to people too.
    person = load(out, "people", W.shard_of("p1") + ".json")["p1"]
    check("person: facts from the people row", person[:3], ["Agnes Moorehead", "1900", "1974"])
    check("person: every credit, oldest first, two roles in one episode kept",
          [(c[0], c[5]) for c in person[4]],
          [("suspense|1943-05-25", "cast"), ("suspense|1943-05-25", "narrator"), ("suspense|1949-09-15", "cast")])
    check("person: a credit row carries what the row draws", person[4][0][1:], ["1943-05-25", "Sorry, Wrong Number",
                                                                               46, "suspense", "cast", "Mrs. Stevenson"])
    found = load(out, "search", "people", W.term_file("moorehead") + ".json")["rows"]
    check("people search: filed by a word of the name, counting episodes", found, [["p1", "Agnes Moorehead", 2, None]])
    voices = load(out, "index", "voices.json")
    check("voices: the web ranks its own served credits, most first (same fields as a people row)",
          (voices["fields"], voices["rows"]), (W.PEOPLE_FIELDS, [["p1", "Agnes Moorehead", 2, None]]))
    check("control: the gate open adds the unclaimed-only voice, ranked after",
          [r[0] for r in load(opened, "index", "voices.json")["rows"]], ["p1", "p2"])
    check("art arrays end with the grade, [k, o] or null", W.ART_FIELDS[-1], "grade")
    check("control: an unclaimed-only person has no page with the gate closed",
          os.path.exists(os.path.join(out, "people", W.shard_of("p2") + ".json")), False)
    check("gate open: the unclaimed-only person has a page", "p2" in
          load(opened, "people", W.shard_of("p2") + ".json"), True)

    # Broken controls for the person shards: a misplaced person, a stray credit, a lost field.
    broken = os.path.join(tmp, "web-broken")
    shutil.copytree(out, broken)
    psh = W.shard_of("p1") + ".json"
    p1 = load(broken, "people", psh)["p1"]
    W.dump(os.path.join(broken, "people", "zzz.json"), {"p1": p1})
    W.dump(os.path.join(broken, "people", psh), {"p1": p1[:4] + [p1[4] + [["ghost|1950-01-01", "1950-01-01", "Ghost",
                                                                            None, "ghost", "cast", None]]]})
    got = violations(broken)
    check("control: a person outside their shard is caught", got.get("every person sits in its own shard"), ["p1"])
    check("control: a credit to an unlisted episode is caught",
          got.get("every person credit is listed on its series page"), ["ghost|1950-01-01"])
    W.dump(os.path.join(broken, "people", psh), {"p1": p1[:3] + [p1[4]]})
    check("control: a person row missing a field is caught",
          "p1" in violations(broken).get("person rows have the published fields", []), True)

    check("aliases: only to an episode the web serves (an unclaimed target stays off with the gate closed)",
          load(out, "index", "aliases.json"), {"suspense|old-slug": "suspense|1943-05-25"})
    check("tombstones.json carries the served projection's tombstones", load(out, "index", "tombstones.json"),
          ["suspense|gone"])
    W.dump(os.path.join(out, "index", "aliases.json"), {"old-a": "nowhere|1950-01-01", "suspense|1949-09-15": "suspense|1943-05-25"})
    W.dump(os.path.join(out, "index", "tombstones.json"), ["suspense|1943-05-25"])
    got = violations(out)
    check("control: an alias to an unlisted id is caught", got.get("every alias ends at a listed episode"), ["old-a"])
    check("control: an aliased id still listed is caught", got.get("an aliased id is not listed"), ["suspense|1949-09-15"])
    check("control: a tombstoned id still listed is caught", got.get("a tombstoned id is not listed"),
          ["suspense|1943-05-25"])
    W.dump(os.path.join(out, "index", "aliases.json"), {})
    W.dump(os.path.join(out, "index", "tombstones.json"), [])
    check("series-aliases.json: only to a series the web serves", load(out, "index", "series-aliases.json"),
          {"suspence": "suspense"})
    check("series-tombstones.json carries the served projection's", load(out, "index", "series-tombstones.json"),
          ["folkweave"])
    W.dump(os.path.join(out, "index", "series-aliases.json"), {"old-a": "nowhere", "mrsorrowful": "suspense"})
    W.dump(os.path.join(out, "index", "series-tombstones.json"), ["speeches"])
    got = violations(out)
    check("control: a series alias to an unindexed series is caught",
          got.get("every series alias ends at an indexed series"), ["old-a"])
    check("control: an aliased series key still indexed is caught",
          got.get("an aliased series key is not indexed"), ["mrsorrowful"])
    check("control: a tombstoned series key still indexed is caught",
          got.get("a tombstoned series key is not indexed"), ["speeches"])
    W.dump(os.path.join(out, "index", "series-aliases.json"), {"suspence": "suspense"})
    W.dump(os.path.join(out, "index", "series-tombstones.json"), ["folkweave"])

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

    # Broken controls for the date files: a misdated row and a lost row are each caught.
    y = load(opened, "search", "dates", "1943.json")
    r0 = y["rows"][0]
    W.dump(os.path.join(opened, "search", "dates", "1943.json"), {**y, "rows": [r0[:2] + ["1943-05-26"] + r0[3:]]})
    check("control: a misdated row is caught", violations(opened).get("a date row is its doc's own row, in its year"),
          ["1943.json:%d" % r0[4]])
    W.dump(os.path.join(opened, "search", "dates", "1943.json"), {**y, "rows": []})
    check("control: a lost dated doc is caught", "every dated doc is in its year once" in violations(opened), True)
    # Broken controls for search/said: a word finding a doc with no shown transcript, a word too short.
    W.dump(os.path.join(opened, "search", "said", "zz.json"), {"zzz": [0]})
    W.dump(os.path.join(opened, "search", "said", "ab.json"), {"ab": [0]})
    got = violations(opened)
    check("control: a said word finding a doc without a shown transcript is caught",
          got.get("a transcript word finds only a doc whose transcript is shown"), ["ab", "zzz"])
    check("control: a said word shorter than saidMinWord is caught",
          got.get("a transcript word is filed under its term file, long enough"), ["ab"])

real = os.environ.get("WEB_PROJECTION") or os.path.join(os.path.dirname(__file__), "..", "out", "web")
if os.path.exists(os.path.join(real, "manifest.json")):
    check("contract holds on the real web build", violations(real), {})
    check("real build: Sorry, Wrong Number is found by its words", "suspense|1948-11-18" in search(real, "sorry wrong")
          if not load(real, "manifest.json")["cleanOnly"] else True, True)
    rm = load(real, "manifest.json")
    if "dateYears" not in rm["counts"] and not os.environ.get("WEB_PROJECTION"):
        print("  SKIP  real web build: the local build predates search/dates and search/said; rebuild or name it with WEB_PROJECTION")
    else:
        check("real build: every dated doc has a year file", rm["counts"]["dateYears"] > 0, True)
        check("real build: transcript words exist exactly when a shown transcript does",
              rm["counts"]["saidTerms"] > 0, rm["counts"]["saidDocs"] > 0)
elif os.environ.get("WEB_PROJECTION"):
    check("the web build named by WEB_PROJECTION exists", False, True)   # asked for, so never a skip
else:
    print("  SKIP  real web build: out/web/ not built")

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
