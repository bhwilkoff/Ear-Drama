"""Photo archives beyond Commons: rights classes from a record's own statement,
conservative series/person matching, and radio-magazine copyright by year.

    python3 tests/test_photo_archives.py

Synthetic inputs only (no caches, no network). Broken controls, 2026-10-21,
each run against a mutated copy of the tool (the count is what that copy
scored); see reports/F-photo-archives.md:

    government creator beats "publication may be restricted"   37/39
    radio word no longer required for a series match            38/39
    series year window ignored                                  38/39
    generic one-word series names allowed                       38/39
    subject-heading lifespan not compared                       38/39
    an ambiguous name resolved to its first person              38/39
    OBP CCE-only check trusted for 1951-1963 issues             38/39
    renewal floor month ignored (whole first year PD)           38/39
    NPG portrait lifespan not compared                          38/39
    NPG portrait accepted with no lifespan to compare           38/39
    CCE block runs into the next title's renewal                37/39

The lifespan control first PASSED (34/34, an earlier count) against its mutation: its case also
tripped the "record year before the person was 10" rule. It now has no record
year and an open-ended heading, so only the lifespan comparison can refuse it.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import photo_match as M  # noqa: E402
import enrich_photo_archives as E  # noqa: E402
import harvest_magazine_rights as H  # noqa: E402

RESULTS = []


def check(name, cond):
    RESULTS.append((name, bool(cond)))
    if not cond:
        print("FAIL", name)


# ---- rights classes (verbatim LoC statements)
NKR = "No known restrictions on publication. For more information, see Harris & Ewing Photographs"
WTS = 'Publication may be restricted. For information see "New York World-Telegram & ...," https://www.loc.gov/rr/print/res/076_nyw.html'
FSA = "No known restrictions. For information, see U.S. Farm Security Administration/Office of War Information Black & White Photographs"
check("nkr statement -> no_known_restrictions", M.rights_class(NKR, "Harris & Ewing")[0] == "no_known_restrictions")
check("World-Telegram restricted -> restricted", M.rights_class(WTS, "NYWTS - BIOG")[0] == "restricted")
check("FSA/OWI -> government", M.rights_class(FSA, "farm security administration/office of war information black-and-white negatives")[0] == "government")
check("OWI creator but restricted print -> restricted",
      M.rights_class(WTS, "United States. Office of War Information")[0] == "restricted")
check("not evaluated -> unknown", M.rights_class("Rights status not evaluated.", "")[0] == "unknown")
check("no statement -> unknown", M.rights_class("", "")[0] == "unknown")
check("restricted is not usable", "restricted" not in M.USABLE and "unknown" not in M.USABLE)

# ---- series matching
SER = [("fibbermcgeeandmolly", "Fibber McGee And Molly", 1935, 1959), ("suspense", "Suspense", 1942, 1962),
       ("lone", "The Lone Ranger", 1933, 1956)]
t = "Jim and Marian Jordan as Fibber McGee and Molly at the NBC microphone"
check("series name + radio word + year in run -> match", [k for k, _ in M.match_series(t, 1941, SER)] == ["fibbermcgeeandmolly"])
check("year far outside the run -> no match", M.match_series(t, 1975, SER) == [])
check("generic one-word series name never matched", M.match_series("Suspense radio program cast at CBS", 1945, SER) == [])
check("no radio word -> no match", M.match_series("Fibber McGee and Molly at home", 1941, SER) == [])
check("leading The dropped", [k for k, _ in M.match_series("Brace Beemer, the Lone Ranger of radio", 1945, SER)] == ["lone"])

# ---- people matching
IDX = {"jack benny": {"p1"}, "john smith": {"p2", "p3"}, "orson welles": {"p4"}}
YRS = {"p1": (1894, 1974), "p2": (1900, None), "p3": (1920, None), "p4": (1915, 1985)}
f, r = M.match_people("Jack Benny", ["Benny, Jack, 1894-1974"], 1940, IDX, YRS)
check("subject heading with agreeing lifespan -> match", [p for p, _ in f] == ["p1"])
f, r = M.match_people("Jack Benny", ["Benny, Jack, 1860-"], None, IDX, YRS)
check("heading lifespan disagrees -> refused", f == [] and r)
f, r = M.match_people("John Smith at the microphone, radio", [], 1940, IDX, YRS)
check("ambiguous name -> refused", f == [] and any("resolves to 2" in w for _, w in r))
f, r = M.match_people("Orson Welles at his desk", [], 1940, IDX, YRS)
check("free-text name with no radio word -> refused", f == [])
f, r = M.match_people("Orson Welles radio broadcast", [], 1920, IDX, YRS)
check("record year before person aged 10 -> refused", f == [])
f, r = M.match_people("Orson Welles radio broadcast", [], 1938, IDX, YRS)
check("free-text name + radio word + plausible year -> match", [p for p, _ in f] == ["p4"])

# ---- NPG portraits
SIT = M.sitters(["Arnold Newman, 3 Mar 1918 - 6 Jun 2006", "Orson Welles, 6 May 1915 - 10 Oct 1985"])
check("sitter lines parsed with lifespans", ("orson welles", 1915, 1985) in SIT)
f, r = M.match_portrait("Orson Welles", SIT, IDX, YRS)
check("portrait titled with the sitter, lifespan agrees -> match", [p for p, _ in f] == ["p4"])
f, r = M.match_portrait("Orson Welles", [("orson welles", 1850, 1900)], IDX, YRS)
check("portrait with a disagreeing lifespan -> refused", f == [] and r)
f, r = M.match_portrait("Orson Welles", [("orson welles", None, None)], IDX, YRS)
check("portrait with no lifespan to compare -> refused", f == [])
f, r = M.match_portrait("Orson Welles and Rita Hayworth", SIT, IDX, YRS)
check("title not exactly the sitter -> no portrait match", f == [])

# ---- magazine status
RM = {"statement": "issues actively renewed from January 1944 (v. 21 no. 3); see 1971; contributions actively "
                   "renewed from June 1938; see 1966 January-June", "source": "x", "detail": "d"}
RG = {"statement": "no issue renewals found in CCE; no contribution renewals found in CCE", "source": "x", "detail": "d"}
RL = {"statement": "issues renewed from November 1948 (v. 1 no. 1); see 1977 July-December", "source": "x", "detail": "d"}
check("obp_rule parses first renewed issue", E.obp_rule(RM["statement"]) == ((1944, 1), None, 1938))
check("1930 -> pd_by_age", E.magazine_status("Radio Digest", 1930, RG, {}, True)[0] == "pd_by_age")
check("1931 never renewed (OBP CCE) -> not_renewed", E.magazine_status("Radio Guide", 1931, RG, {}, True)[0] == "not_renewed")
check("Radio Mirror 1943 -> not_renewed", E.magazine_status("Radio Mirror", 1943, RM, {}, True)[0] == "not_renewed")
check("Radio Mirror 1944 -> renewed", E.magazine_status("Radio Mirror", 1944, RM, {}, True)[0] == "renewed")
check("Radio Mirror 1950 -> renewed", E.magazine_status("Radio Mirror", 1950, RM, {}, True)[0] == "renewed")
check("first renewed year beginning mid-year -> renewed_from_month",
      E.magazine_status("Radioland and Television", 1948, RL, {}, True)[0] == "renewed_from_month")
check("OBP CCE-only, 1955 issue -> unchecked", E.magazine_status("Radio Guide", 1955, RG, {}, True)[0] == "unchecked")
check("1964 -> in_copyright", E.magazine_status("X", 1964, None, {}, True)[0] == "in_copyright")
hit = {"src": "s", "renewals": ["R1"], "orig_dates": ["1940-01-01"], "vol_year": 1967}
check("our CCE renewal beats OBP's none", E.magazine_status("Radio Guide", 1940, RG, {1940: [hit]}, True)[0] == "renewed")
check("unlisted title, 1945, CCE read -> not_renewed", E.magazine_status("Tune In", 1945, None, {}, True)[0] == "not_renewed")
check("unlisted title, CCE not read -> unchecked", E.magazine_status("Tune In", 1945, None, {}, False)[0] == "unchecked")
check("unlisted title, 1952 -> unchecked", E.magazine_status("Radio Album", 1952, None, {}, True)[0] == "unchecked")

# ---- CCE periodical renewal parser
TXT = """RADIO MIRROR.
© Macfadden-Bartell Corp. (PCW)
v.21, no.
3, Jan44. © 10Dec43; B611211.
7Dec71; R519469.

RADIOGRAPHY AND CLINICAL PHOTOGRAPHY.
© Eastman Kodak Co. (PCW)
v.19, no.
3. © 29Dec43; BO615047.
7Jan71; R502509.

RADIO GUIDE.
© Annenberg (PCW)
v.1, no. 1. © 1Jan20; B1.
"""
hits = H.parse_cce(TXT, 1971, "vol")
check("CCE: renewal block found with its original date",
      len(hits) == 1 and hits[0]["canonical"] == "Radio Mirror" and hits[0]["orig_dates"] == ["1943-12-10"])
check("CCE: the next title's R-number is not attributed", hits and hits[0]["renewals"] == ["R519469"])
check("CCE: heading with no renewal number -> no hit", all(h["canonical"] != "Radio Guide" for h in hits))

n = sum(ok for _, ok in RESULTS)
print(f"{n}/{len(RESULTS)} passed")
sys.exit(0 if n == len(RESULTS) else 1)
