"""Finding a play (BACKLOG-LOOP B31 C1, C3, C4; catalog DECISIONS 050): the pictures attach for real or the build
stops, the facets and scenes every row carries, the collections, characters and words said, and the title audit.

    python3 tests/test_play_facets.py

Golden cases: catalog/tests/golden/play_facets.json. Every refusal has a planted control: a volume's title or a
collection's subject taken as a play's form, an editor's play id that does not resolve, a library with no pictures,
an empty picture cache, a credit line or a periodical issue kept as a title.
"""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tools"))
import check_play_library as C  # noqa: E402
import play_art as PA  # noqa: E402
import play_facets as PF  # noqa: E402
import play_titles as PT  # noqa: E402

GOLDEN = json.load(open(os.path.join(HERE, "golden", "play_facets.json"), encoding="utf-8"))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
ran = failed = 0


def check(name, got, want):
    global ran, failed
    ran += 1
    if got != want:
        failed += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


def raises(name, fn, exc):
    global ran, failed
    ran += 1
    try:
        fn()
    except exc:
        return
    failed += 1
    print(f"FAIL {name}: no {exc.__name__}")


# --- golden: form, era, balance, headings, title audit, credits ---------------------------------------
for c in GOLDEN["form"]:
    check("form: " + c["name"], list(PF.form_of(c["subjects"], c["title"], c.get("split", False), c.get("play_title"))),
          [c["form"], c["source"]])
for c in GOLDEN["era"]:
    check(f"era {c['born']}-{c['died']}", PF.era_of(c["born"], c["died"]), c["era"])
for c in GOLDEN["balance"]:
    check(f"balance {c['cast']}", PF.balance_of(c["cast"]), c["balance"])
for c in GOLDEN["heading"]:
    check(f"heading {c['source']!r}", PF.heading_of(c["source"]), c["heading"])
for c in GOLDEN["title_audit"]:
    check(f"title audit {c['title']!r}", PT.not_a_play(c["title"], {"shelves": c.get("shelves", [])}) is not None, c["held"])
for c in GOLDEN["credits"]:
    check(f"credits {c['authors'][:30]!r}", [[p, a] for p, a in PT.catalog_credits(c["authors"])], c["credits"])

# --- a row's facets from its record ------------------------------------------------------------------
REC = {"id": "gut-7", "title": "How He Lied to Her Husband: A Comedy", "authors": [{"name": "Shaw, Bernard", "born": 1856, "died": 1950, "role": "author"}],
       "subjects": ["Man-woman relationships -- Drama", "Comedies", "PR"], "shelves": ["One Act Plays"]}


def speech(i, role, words=30):
    return {"id": f"L{i:04d}", "kind": "speech", "role": role, "parts": [{"say": " ".join(["word"] * words)}]}


ENTRY = {"id": "gut-7", "authors": [{"name": "Shaw, Bernard", "born": 1856, "died": 1950}],
         "roles": [{"name": "HER", "lines": 40}, {"name": "HE", "lines": 30}, {"name": "HUSBAND", "lines": 10}],
         "lines": [speech(i, "HER" if i % 2 else "HE") for i in range(1, 41)] + [speech(i, "HUSBAND") for i in range(41, 81)],
         "sections": [{"line": "L0001", "source": "SCENE I.--_A FLAT IN CROMWELL ROAD._"}, {"line": "L0041", "source": "SCENE II"}]}
ROW = {"id": "gut-7", "title": "How He Lied to Her Husband", "sort_name": "how he lied", "authors": ["Bernard Shaw"],
       "voices": 3, "minutes": 20, "cast": [35, 30, 15]}
row = PF.facet_row(dict(ROW), ENTRY, REC)
check("row: form, its source and the board it borrows", (row.get("form"), row.get("formSource"), row.get("hue")), ("comedy", "subject", "comedy"))
check("row: era and life from the record's author", (row.get("era"), row.get("life")), ("1900-1930", {"born": 1856, "died": 1950}))
check("row: one act from the shelf, LoCC, the topic", (row.get("oneAct"), row.get("locc"), row.get("subjects")), (True, "PR", ["Man-woman relationships"]))
check("row: balance from the cast", row.get("balance"), "mixed")
check("row: a scene for two voices, cut at its first punctuation", row.get("scenes"),
      [{"line": "L0001", "heading": "Scene I", "voices": 2, "minutes": 8, "parts": ["HE", "HER"]}])
check("control: a one-voice section is no scene", [s["line"] for s in row["scenes"]], ["L0001"])
check("LoCC from the catalog's class number when the record lists none", PF.facet_row(dict(ROW), ENTRY, dict(REC, subjects=["Comedies"]), {"LoCC": "E201"}).get("locc"), "E")
bare = PF.facet_row(dict(ROW, id="gut-8"), dict(ENTRY, id="gut-8"), None)
check("a row with no record keeps only what its script says", sorted(k for k in bare if k not in ROW), ["balance", "era", "life", "scenes"])

# --- facets_meta, collections, characters, words said -------------------------------------------------
rows = [dict(ROW, id=f"gut-{k}", sort_name=f"play {k:02d}", voices=2 + k % 3, minutes=5 + 10 * k, balance="ensemble" if k % 2 else "lead",
             form="comedy" if k < 6 else None) for k in range(10)]
meta = PF.facets_meta(rows)
check("meta: voices bins count every row", sum(b["count"] for b in meta["voices"]), 10)
check("meta: a form on five or more plays is listed; the rest are Not named", [(f["value"], f["count"]) for f in meta["form"]], [("comedy", 6), (None, 4)])
few = [dict(r, form="melodrama") if k < 2 else r for k, r in enumerate(rows)]
check("control: a form on fewer than five plays folds into Not named", [(f["value"], f["count"]) for f in PF.facets_meta(few)["form"]], [(None, 10)])
recs = {f"gut-{k}": {"shelves": ["One Act Plays"] if k < 3 else [], "subjects": ["Christmas -- Drama"] if k == 4 else []} for k in range(10)}
doc = PF.collections_doc(rows, recs, {"collections": []})
got = {c["id"]: c for c in doc["data"]}
check("collections: plays for two voices, A to Z", got["two-voices"]["plays"], ["gut-0", "gut-3", "gut-6", "gut-9"])
check("collections: ten minutes or less, shortest first", got["ten-minutes"]["plays"], ["gut-0"])
check("collections: the One Act shelf", got["one-act"]["count"], 3)
check("collections: Christmas from a subject", got["christmas"]["plays"], ["gut-4"])
check("collections: every data collection states its rule", all(c["rule"] for c in doc["data"]), True)
check("collections: an author with five or more plays", got["author-bernard-shaw"]["count"], 10)
check("collections: the editor file empty means no editor collection", doc["editor"], [])
ed = {"collections": [{"id": "pairs", "title": "For a pair", "by": "Ben", "plays": ["gut-1", "gut-2", "gut-3"], "added": "2026-11-26"},
                      {"id": "two", "title": "Too few", "by": "Ben", "plays": ["gut-1", "gut-2"], "added": "2026-11-26"}]}
check("editor: a collection of three plays is published with its credit; one of two is not",
      [(c["id"], c["by"], c["count"]) for c in PF.editor_collections(rows, ed)], [("pairs", "Ben", 3)])
raises("planted: an editor's play id that does not resolve fails the build",
       lambda: PF.editor_collections(rows, {"collections": [dict(ed["collections"][0], plays=["gut-1", "gut-2", "gut-404"])]}), ValueError)
raises("planted: an editor collection with no credit fails", lambda: PF.editor_collections(rows, {"collections": [dict(ed["collections"][0], by="")]}), ValueError)
shipped = json.load(open(PF.EDITOR_FILE, encoding="utf-8"))
check("the shipped editor file parses, with the credit field in its shape", ("by" in shipped["shape"], isinstance(shipped["collections"], list)), (True, True))

ents = [dict(ENTRY, id=f"gut-{k}") for k in range(3)]
chars = PF.characters_doc(rows[:3], ents)
check("characters: a part's name in capitals, each play it speaks in with its lines", chars["names"]["HER"], [[0, 40], [1, 40], [2, 40]])
ents[1] = dict(ents[1], lines=[{"id": "L0001", "kind": "speech", "role": "HE", "parts": [{"say": "The quality of mercy is not strained"}]}])
shards = PF.said_shards(rows[:3], ents)
check("said: a word filed by its first two letters, play numbers delta-coded", shards["qu"]["quality"], [1])
check("said: a word in every play", shards["wo"]["word"], [0, 2])
check("control: words under three letters are not filed", "is" in shards.get("is", {}), False)

# --- the title audit holds by one rule, and never a bundled play --------------------------------------
entries = [{"id": "gut-1", "title": "Edited by Havelock Ellis"}, {"id": "gut-2", "title": "Candida"},
           {"id": "gut-3-1", "title": "Translated by Mrs. Bernard Shaw"}, {"id": "gut-4", "title": "The Glebe 1914/01 (Vol. 1, No. 4)"}]
report = {"clean": 4, "failures": {}, "_held": {"held": []}}
kept = PT.hold_not_plays(entries, {"gut-2": {"shelves": ["Category: Plays/Films/Dramas"]}}, report, protect={"gut-4"})
check("title audit: credit lines held, a bundled play kept", [e["id"] for e in kept], ["gut-2", "gut-4"])
check("title audit: held rows are in held.json's ledger with their evidence",
      [(r["id"], r["why"]) for r in report["_held"]["held"]], [("gut-1", "title_not_a_play"), ("gut-3-1", "title_not_a_play")])
check("title audit: the report counts what it held", (report["clean"], report["failures"]), (2, {"title_not_a_play": 2}))
credited = PT.credit_attributed([{"id": "gut-68576", "authors": []}, {"id": "gut-2", "authors": [{"name": "Shaw, Bernard"}]}],
                                {"gut-68576": {"Authors": "Cabell, James Branch, 1879-1958 [Dubious author]"},
                                 "gut-2": {"Authors": "Cabell, James Branch, 1879-1958 [Dubious author]"}})
check("Poor Jack: a record with no author takes the catalog's attribution, marked",
      [(a["display"], a.get("attributed")) for a in credited[0]["authors"]], [("James Branch Cabell", True)])
check("control: a record that names its author keeps it", credited[1]["authors"], [{"name": "Shaw, Bernard"}])
check("an attributed author marks the index row", PF.facet_row(dict(ROW), credited[0] | {"lines": [], "roles": []}, None).get("attributed"), True)

# --- C1: no picture cache stops the build; the check fails a library with no pictures ----------------
with tempfile.TemporaryDirectory() as d:
    saved = PA.DIR, PA.CACHE
    PA.DIR, PA.CACHE = os.path.join(d, "art_v2"), d
    try:
        raises("planted: an empty picture cache stops attach (it used to return the rows bare)", lambda: PA.attach([{"id": "gut-1"}]), PA.NoArtCache)
        check("a context passed in is used as it is", PA.attach([{"id": "gut-1"}], {"plays": {}, "files": {}, "live": {}, "ftp": {}}), [{"id": "gut-1"}])
    finally:
        PA.DIR, PA.CACHE = saved
    marker = os.path.join(d, "planted")
    os.makedirs(marker)
    open(os.path.join(marker, ".restored-catalog-2000-01-01"), "w").close()
    rc = subprocess.run(["bash", os.path.join(ROOT, "tools", "restore_play_art_caches.sh"), marker], capture_output=True, text=True,
                        env=dict(os.environ, PLAY_ART_TAG="catalog-2000-01-01")).returncode
    check("planted: a restore that leaves no art_v2/plays.json.gz exits 1, so the refresh stops", rc, 1)

idx = {"plays": [{"id": "gut-1"}, {"id": "gut-2", "picture": {"url": "u", "kind": "work"}}], "pictures": PA.summary([{"id": "gut-1"}, {"id": "gut-2", "picture": {"url": "u", "kind": "work"}}])}
check("pictures summary by kind, with the window count (1.4)", (idx["pictures"]["kinds"], idx["pictures"]["window"]), ({"work": 1}, 1))
C.check_pictures(idx, 0.25)
none = {"plays": [{"id": "gut-1"}, {"id": "gut-2"}], "pictures": PA.summary([{"id": "gut-1"}, {"id": "gut-2"}])}
raises("planted: a library with 0% pictures fails the check", lambda: C.check_pictures(none, C.MIN_PICTURE_SHARE), AssertionError)
C.check_pictures({"plays": [{"id": "gut-1"}]}, C.MIN_PICTURE_SHARE)   # no summary: a library from before the rule
check("a title-page lead is not a window picture (1.4)", PA.summary([{"id": "a", "picture": {"url": "u", "kind": "titlePage"}}])["window"], 0)

# --- the check reads the files beside the index ---------------------------------------------------------
with tempfile.TemporaryDirectory() as d:
    lib = {"plays": [dict(ROW, id="gut-1"), dict(ROW, id="gut-2")]}
    json.dump({"format": 1, "editor": [], "data": [{"id": "x", "title": "X", "rule": "r", "count": 1, "plays": ["gut-1"]}]},
              open(os.path.join(d, "collections.json"), "w"))
    C.check_finding(d, lib)
    json.dump({"format": 1, "editor": [], "data": [{"id": "x", "title": "X", "rule": "r", "count": 1, "plays": ["gut-9"]}]},
              open(os.path.join(d, "collections.json"), "w"))
    raises("planted: a collection naming a play not in the index fails the check", lambda: C.check_finding(d, lib), AssertionError)
    os.remove(os.path.join(d, "collections.json"))
    os.makedirs(os.path.join(d, "search", "said"))
    json.dump({"word": [0, 5]}, open(os.path.join(d, "search", "said", "wo.json"), "w"))
    raises("planted: a said play number past the index fails the check", lambda: C.check_finding(d, lib), AssertionError)

# --- the real library, when built ------------------------------------------------------------------------
REAL = os.path.join(HERE, "..", "out", "plays-library", "index.json")
if os.path.exists(REAL):
    real = json.load(open(REAL, encoding="utf-8"))
    if "facets" in real:
        check("real: no row's title is a credit line or a periodical issue",
              [p["id"] for p in real["plays"] if PT.not_a_play(p["title"])], [])
        check("real: every row has a balance (the cast is always known)", all("balance" in p for p in real["plays"]), True)

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
