"""Series registry, abbreviation learning, OTRR log matching and content kinds (Track B,
2026-10-19). Every rule has a control: the case the rule must NOT fire on.

Broken controls, 2026-10-19, each run against a mutated copy (RADIO_TOOLS=<copy>):
    prefix rule without word ends                   56/59
    an alias two programs share is folded           58/59
    one-word generic aliases kept ("Interviews")    58/59
    a conflicting log title is applied              58/59
    no duration check on series + date              58/59
    title -> date in an unchecked series            58/59 (first PASSED 59/59: the control series
                                                     had no log titles at all; Escape's row added)
    number -> date in an unchecked series           58/59
    podcast rule ignores a known series             58/59
    no abbreviation-plausibility check              57/59
    short learned prefixes always applied           58/59
"""
import collections
import os
import sys

sys.path.insert(0, os.environ.get("RADIO_TOOLS") or os.path.join(os.path.dirname(__file__), "..", "tools"))
import otr_parse as P
import build_db as B

failed = 0
ran = 0


def check(name, got, want):
    global failed, ran
    ran += 1
    if got != want:
        failed += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


# --- normalization -----------------------------------------------------------------
same = [("Lone Ranger, The", "The Lone Ranger"), ("TheShadow", "The Shadow"),
        ("Amos 'n' Andy", "Amos and Andy"), ("AmosNAndy", "Amos & Andy"),
        ("Lux Radio Theatre", "Lux Radio Theater"), ("Fibber McGee & Molly", "Fibber McGee and Molly")]
for a, b in same:
    check(f"norm {a!r} == {b!r}", P.norm_series(a), P.norm_series(b))
check("control: The Shadow is not Shadow of Fu Manchu",
      P.norm_series("The Shadow") == P.norm_series("Shadow of Fu Manchu"), False)

# --- the registry ------------------------------------------------------------------
re_series = [{"series": "The Shadow", "episodes": [{}] * 5}, {"series": "Escape", "episodes": [{}] * 9},
             {"series": "Lum And Abner", "episodes": [{}] * 9}, {"series": "Suspense", "episodes": [{}] * 9},
             {"series": "Grey Goose", "episodes": []}, {"series": "The Adventures Of Superman", "episodes": []},
             {"series": "Conflict", "episodes": []}, {"series": "Heritage", "episodes": []},
             {"series": "The Whistler", "episodes": []}]
otrr = {"1": "Shadow, The", "2": "Fleischmann Yeast Hour, The", "3": "Theater of the Air", "4": "Showboat",
        "5": "Superman, The Adventures of", "6": "Adventures by Morse"}
ptitles = [{"idp": "1", "title": "Blue Coal Mystery Revue"},       # an alias of The Shadow
           {"idp": "2", "title": "Rudy Vallee Show, The"},
           {"idp": "3", "title": "Palace Theater"}, {"idp": "4", "title": "Palace Theater"},  # ambiguous
           {"idp": "5", "title": "Superman"},                         # one word, a program's own name
           {"idp": "6", "title": "Interviews"}]                       # one word, a kind of program
reg, _ = B.build_registry(re_series, otrr, ptitles, {"esc": "Escape"}, [])
check("OTRR alias folds into the spine's series", reg.resolve("Blue Coal Mystery Revue")[0], "shadow")
check("OTRR ', The' title meets the spine name", reg.resolve("Shadow, The")[0], "shadow")
check("alias of an OTRR-only program", reg.resolve("The Rudy Vallee Show")[0], reg.resolve("Fleischmann Yeast Hour")[0])
check("control: an alias two programs share folds into neither", reg.k2c.get(P.norm_series("Palace Theater")), None)
check("one-word alias that names a program is kept", reg.resolve("Superman")[0], "adventuresofsuperman")
check("control: one-word alias that names a kind of program is dropped",
      reg.k2c.get("interviews"), None)
check("editorial abbreviation", reg.resolve("ESC")[0], "escape")

# variants and the prefix rule
check("OTRR set words removed", reg.resolve("OTRR Suspense Singles")[0], "suspense")
check("leading collection words removed", reg.resolve("Aus 108 - Grey Goose")[0], "greygoose")
check("'Adventures of' form", reg.resolve("Superman #0942")[0], "adventuresofsuperman")
check("prefix ending at a word", reg.resolve("Lum and Abner Remembers Pine Ridge"), ("lumandabner", "prefix"))
check("control: prefix inside a word", reg.resolve("Conflicting Concepts of Education")[0], None)
check("control: prefix with a possessive", reg.resolve("Whistler's Mother Painting")[0], None)
check("control: one-word prefix", reg.resolve("Heritage of Home Economics in Illinois")[0], None)

# --- abbreviations -----------------------------------------------------------------
check("prefix abbreviation", P.is_abbreviation("esca", "escape"), True)
check("subsequence abbreviation", P.is_abbreviation("dimx", "dimensionx"), True)
check("initials", P.initials("Yours Truly, Johnny Dollar"), "ytjd")
check("control: letters out of order", P.is_abbreviation("xmid", "dimensionx"), False)
check("control: different first letter", P.is_abbreviation("scap", "escape"), False)


def fr(ident, series, item):
    return {"p": {"series": series}, "item_series": item, "ident": ident, "orow": None}


files = [fr("Escape1953", "esca", "Escape")] * 5 + [fr("Suspense1", "zork", "Suspense")] * 5 + \
        [fr("LumAbner1", "la", "Lum and Abner")] * 30 + [fr("LumAbner2", "la", "Lum and Abner")] * 0 + \
        [fr("ShadowX", "sh", "The Shadow")] * 30 + [fr("Odd", "esco", "Escape")] * 2
learned = B.learn_abbreviations(files, reg, set())
check("learned from file prefix vs item title", learned.get("esca", {}).get("series"), "Escape")
check("learned and applied (4+ letters)", learned.get("esca", {}).get("applied"), True)
check("control: a prefix that cannot abbreviate is not learned", "zork" in learned, False)
check("control: two letters from one upload are recorded, not applied", learned.get("la", {}).get("applied"), False)
learned2 = B.learn_abbreviations(files + [fr("LumAbner2", "la", "Lum and Abner")] * 30, reg, set())
check("two letters from two uploads are applied", learned2.get("la", {}).get("applied"), True)
check("control: two letters that are not initials are not learned", "sh" in learned, False)
check("control: fewer than 3 files is not learned", "esco" in learned, False)
check("control: a vetoed abbreviation is not learned", "esca" in B.learn_abbreviations(files, reg, {"esca"}), False)

# --- OTRR log matching -------------------------------------------------------------
reg2, _ = B.build_registry([{"series": "Suspense", "episodes": []}, {"series": "Escape", "episodes": []}],
                           {"10": "Suspense", "11": "Escape"}, [], {}, [])


def row(eid, idp, date, title, epnum="", secs=None, people=()):
    return {"eid": eid, "idp": idp, "program": "", "date": date, "title": title, "epnum": epnum,
            "files": [{"seconds": str(secs)}] if secs else [], "people": list(people), "exists": True}


def rec(key, date, title, num=None, length=1800.0, ds="filename"):
    return {"key": key, "date": date, "title": title, "title0": title, "num": num, "num0": num, "length": length,
            "date_source": ds if date else None, "orow": None, "idt": {}, "decade": None}


rows = [row("1", "10", "1942-06-17", "The Burning Court", "1", 1790, [{"id": "9", "name": "Charles Ruggles", "role": "cast"}]),
        row("2", "10", "1942-06-24", "Wanted, Single Woman", "2", 1790),
        row("3", "10", "1942-07-01", "Road to Freedom", "3", 600),
        row("4", "10", "1942-07-08", "Cabin B-13", "4"),
        row("5", "10", "1942-07-15", "Wraith", "5"),
        row("6", "11", "1950-01-01", "Wanted, Single Woman")]       # Escape's log has the title too
# five dated files in Suspense whose own titles agree with the log -> titles may date others
trusted = [rec("suspense", r["date"], r["title"]) for r in rows if r["idp"] == "10"]
r1 = rec("suspense", "1942-06-17", None)
r2 = rec("suspense", "1942-07-01", "Road to Freedom", length=1800)      # the log's copy is 600 s
r3 = rec("suspense", "1942-07-08", "The Hitch-Hiker")                    # the log says Cabin B-13
r4 = rec("suspense", None, "Wanted, Single Woman")
r5 = rec("escape", None, "Wanted, Single Woman")                         # untrusted series
stats = collections.Counter()
B.match_logs(trusted + [r1, r2, r3, r4, r5], rows, reg2, {}, stats)
check("series + date fills the title", r1["title"], "The Burning Court")
check("series + date fills the number", r1["num"], 1)
check("series + date carries the credits", (r1["orow"] or {}).get("people", [{}])[0].get("name"), "Charles Ruggles")
check("series + date is duration verified", r1["idt"].get("otrr_match"), "series_date:duration_verified")
check("control: a copy at 3x the log's length is not matched", r2["orow"], None)
check("control: a conflicting title is not overwritten", r3["title"], "The Hitch-Hiker")
check("series + title dates an undated file", (r4["date"], r4["date_source"]), ("1942-06-24", "otrr_title"))
check("control: title -> date in a series never checked", r5["date"], None)

# number -> date only where numbers have been seen to agree
nums = [rec("suspense", r["date"], None, num=int(r["epnum"])) for r in rows if r["epnum"]]
u = rec("suspense", None, None, num=3)
stats = collections.Counter()
B.match_logs(nums + [u], rows, reg2, {}, stats)
check("number -> date in a series whose numbers agree", u["date"], "1942-07-01")
bad = [rec("suspense", r["date"], None, num=int(r["epnum"]) + 1) for r in rows if r["epnum"]]
u2 = rec("suspense", None, None, num=3)
B.match_logs(bad + [u2], rows, reg2, {}, collections.Counter())
check("control: number -> date where numbers disagree", u2["date"], None)

# --- text dates --------------------------------------------------------------------
check("day month year", P.parse_text_date("Sunday, 27 August 1944"), "1944-08-27")
check("month day, year", P.parse_text_date("Louella Parsons - November 9, 1947"), "1947-11-09")
check("control: a month and year is not a date", P.parse_text_date("May 1944"), None)
check("control: a modern date is not a broadcast date here", P.parse_text_date("20 August 2023"), None)

# --- content kinds -----------------------------------------------------------------
check("scripture", P.content_kind("1 Chronicles 01", 276)[0], "scripture")
check("commercial record",
      P.content_kind("Jim Davidson & His ABC Dance Orchestra - Faithful Forever (1940)", 168)[0], "music")
check("commercial spot", P.content_kind("VintageCommercialsAlkaSeltzer", 117)[0], "commercial")
check("podcast item", P.content_kind("rdsh032", 2194, "Retro Radio Show", ["podcasts"])[0], "podcast")
check("control: a podcast-collection file of a known program is radio",
      P.content_kind("137 Paradise Regained", 1836, "MINDWEBS", ["podcasts"], known_series=True)[0], None)
check("control: a long file in a music collection is radio",
      P.content_kind("War of the Worlds Special Part 5", 3560, "", ["audio_music"])[0], None)
check("control: a half-hour broadcast with 'Show' is not a spot",
      P.content_kind("The Jack Benny Show 1945 Promo Special", 1800)[0], None)
check("scripture needs an upload of many", B.SCRIPTURE_ITEM_FLOOR >= 10, True)

# --- the UIUC finding aid ----------------------------------------------------------
html = """<dt class='faitem'><a name="id116697"></a>Item 7A: U.S. Objectives in Korea, 9/1/1950</dt>
<dd class='faitemcontent'>Speaker: Truman, Harry S.</dd>
<dd class='faitemcontent'>Filename: UIUC_Archives_1306005_0007_A</dd>
<dt class='faitem'><a name="id116725"></a>Item 21A/B: What the University Means, 2/5/1951</dt>
<dd class='faitemcontent'>Program: Farm and Home Week</dd>
<dd class='faitemcontent'>Filename: UIUC_Archives_1306005_0021_A</dd>
<dd class='faitemcontent'>Filename: UIUC_Archives_1306005_0021_B</dd>
<dt class='faitem'><a name="id1"></a>Item 1B: BBC London Column #337</dt>
<dd class='faitemcontent'>Filename: UIUC_Archives_1306005_0001_B</dd>
</dl>"""
u = P.parse_uiuc_findingaid(html)
check("finding aid: title and date", (u["UIUC_Archives_1306005_0007_A"]["title"], u["UIUC_Archives_1306005_0007_A"]["date"]),
      ("U.S. Objectives in Korea", "1950-09-01"))
check("finding aid: one entry, two sides", u.get("UIUC_Archives_1306005_0021_B", {}).get("program"), "Farm and Home Week")
check("control: finding aid entry with no date", u["UIUC_Archives_1306005_0001_B"]["date"], None)

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
