"""The castable-script rights test: ordered buckets, hides before rescues, first match wins.

A script may be cast (Decision 059, owner 2026-10-22) only when its OWN record
carries rights evidence a reader can open, with no approval queue. This is the
test, written like audit_audio_rights: every hide runs before every rescue, and
every row returns the evidence it rests on.

The law each rescue rests on (docs/research/08b-scripts.md §1.2, statute read
2026-10-18):
    published 1930 or earlier     95 years from publication; the line is
                                  today.year - 96 and moves every 1 January
    registered 1930 or earlier    95 years from registration (unpublished, Class D)
    registered 1931-1963, not     the 28-year first term lapsed; proven by the
      renewed                     renewal file AND a recorded search of the
                                  renewal-era volumes, never by a missing row alone
    US government work            17 U.S.C. §105, when the script's own author and
                                  employer are on record (a collection is not authorship)
    source clearance              Project Gutenberg's "Public domain in the USA."
                                  and Standard Ebooks' US public-domain statement,
                                  institutional clearances of the edition, translation
                                  included (not an uploader's word)

"Before 1931" does NOT free an unpublished broadcast script (§303: a 1928 work
for hire runs to 2048). "Individual author died by 1955" (§302(a), life + 70)
is research 08 C9, which the owner has not ruled on: it is RECORDED as
`script_author_died_unapplied` and is not castable until they do.

States:
    castable        a rescue fired
    hide_claim      a claim a reader can open (takedown, renewal, source terms,
                    a non-commercial licence)
    not_castable    not enough evidence either way (the default)
    owner_pending   evidence of a kind the owner has not yet accepted (C9)
"""
import datetime
import gzip
import json
import os
import re
import sys

CLEARING_SOURCES = {"Project Gutenberg": "Public domain in the USA",
                    "Standard Ebooks": "public domain in the United States"}
LAST_RENEWAL_REQUIRED = 1963
# A renewal of NEW material on an old play (an adaptation, a translation, an acting
# version) claims that material, not the play: measured 2026-10-22, 21 of the first
# 24 title matches on Gutenberg's shelf were these (Hamlet "rendered into modern
# American", Ibsen "adapted for production"), and one more was registered two years
# after its author died. Matched by registration number they still hide.
DERIVATIVE = re.compile(r"\b(adapt\w*|translat\w*|arrang\w*|version|rewritten|abridg\w*|dramati[sz]\w*|"
                        r"brought up to date|rendered into|lyrics|revised)\b", re.I)
FIRST_ONLINE_RENEWAL_YEAR = 1978


def pd_line(today=None):
    """Newest publication (or registration) year whose 95-year term has ended: 1930 in 2026."""
    return (today or datetime.date.today()).year - 96


def author_died_line(today=None):
    """Newest death year whose life + 70 term has ended: 1955 in 2026."""
    return (today or datetime.date.today()).year - 71


def norm_title(t):
    t = re.sub(r"^(the|a|an)\s+", "", (t or "").lower().strip())
    return re.sub(r"[^a-z0-9]", "", t)


def surname(name):
    n = (name or "").strip()
    return (n.split(",")[0] if "," in n else n.split()[-1] if n.split() else "").upper()


def reg_key(reg):
    m = re.match(r"\s*([A-Z])\s*(?:unp\.?|pub\.?|U|P)?\s*(\d+)", reg or "", re.I)
    return (m.group(1).upper(), int(m.group(2))) if m else None


def renewal_index(rows):
    by_reg, by_title = {}, {}
    for r in rows:
        k = reg_key(r.get("reg"))
        if k:
            by_reg.setdefault(k, []).append(r)
        nt = norm_title(r.get("title"))
        if len(nt) >= 6:
            by_title.setdefault(nt, []).append(r)
    return {"by_reg": by_reg, "by_title": by_title}


def _ren_ev(r):
    return {"claim": "renewed: " + (r.get("text") or "")[:160], "src": r.get("src"), "registration": r.get("reg"),
            "renewal": r.get("r") or r.get("r_printed"), "renewed": r.get("r_date"), "claimant": r.get("claimant")}


def _live(r, today):
    return r["orig_year"] + 96 > (today or datetime.date.today()).year


def _cleared(s):
    src = s.get("source") or {}
    want = CLEARING_SOURCES.get(src.get("name"))
    return bool(want and want.lower() in (src.get("rights_text") or "").lower() and src.get("rights_src"))


def _year(s):
    for k in ("published", "registration"):
        if (s.get(k) or {}).get("year"):
            return s[k]["year"]
    return None


def bucket(s, ctx):
    """`s`: a script record (see tests/test_script_rights.py `script()` for the shape).
    `ctx`: {"renewals": renewal_index(...), "takedowns": {id: evidence}, "today": date}."""
    today = ctx.get("today")
    line = pd_line(today)
    src = s.get("source") or {}

    # Hides: a claim a reader can open.
    if s["id"] in ctx.get("takedowns", {}):
        return "script_takedown", [ctx["takedowns"][s["id"]]]
    terms = src.get("terms") or {}
    if terms.get("reuse") in ("ask", "forbidden"):
        return "script_source_terms", [{"claim": terms.get("quote"), "src": terms.get("src")}]
    if terms.get("reuse") == "nc":
        return "script_nc_licence", [{"claim": terms.get("quote"), "src": terms.get("src")}]
    ren = ctx.get("renewals") or {"by_reg": {}, "by_title": {}}
    k = reg_key((s.get("registration") or {}).get("reg"))
    hits = [r for r in ren["by_reg"].get(k, []) if _live(r, today)
            and abs(r["orig_year"] - (s["registration"].get("year") or r["orig_year"])) <= 1] if k else []
    if hits:
        return "script_renewed", [_ren_ev(hits[0])]
    nt, yr = norm_title(s.get("title")), _year(s)
    names = {surname(a.get("name")) for a in s.get("authors") or []} - {""}
    died = {surname(a.get("name")): a.get("died") for a in s.get("authors") or []}
    for r in ren["by_title"].get(nt, []) if len(nt) >= 6 else []:
        if not _live(r, today) or surname(r.get("author")) not in names or DERIVATIVE.search(r.get("text") or ""):
            continue
        d = died.get(surname(r.get("author")))
        if (yr is not None and abs(r["orig_year"] - yr) <= 1) or (yr is None and not (d and d < r["orig_year"])):
            return "script_renewed", [_ren_ev(r)]

    # Not enough evidence for a part of the text the rescues below cannot see.
    ad = s.get("adapts")
    if ad and not ad.get("free_evidence"):
        return "script_adaptation_unchecked", [{"claim": f"adapts {ad.get('work')}", "src": ad.get("src")}]
    if s.get("translators") and not _cleared(s):
        tr = [t for t in s["translators"] if not (t.get("year") and t["year"] <= line)]
        if tr:
            return "script_translation_unchecked", [{"claim": f"translated by {tr[0].get('name')}",
                                                     "src": src.get("url")}]
    if s.get("country") and s["country"] != "US" and not _cleared(s) and not (yr and yr <= line):
        return "script_foreign_restorable", [{"claim": f"first published in {s['country']} after {line}; "
                                                       "URAA may have restored it", "src": src.get("url")}]

    # Rescues.
    gov = s.get("gov") or {}
    if gov.get("agency") and gov.get("author") and gov.get("employer_src"):
        return "script_gov_work", [{"claim": f"{gov.get('author')}, {gov['agency']}", "src": gov.get("employer_src")}]
    pub = s.get("published") or {}
    if pub.get("year") and pub.get("src") and pub["year"] <= line:
        return "script_pd_published_age", [{"claim": pub.get("claim") or f"published {pub['year']}", "src": pub["src"]}]
    reg = s.get("registration") or {}
    if reg.get("year") and reg.get("src") and reg["year"] <= line:
        return "script_registered_age", [{"claim": f"registered {reg['reg']} in {reg['year']}", "src": reg["src"]}]
    if _cleared(s):
        return "script_source_cleared", [{"claim": src["rights_text"], "src": src["rights_src"]}]
    if reg.get("year") and reg.get("src") and reg["year"] <= LAST_RENEWAL_REQUIRED:
        due = reg["year"] + 28
        search = s.get("renewal_search") or {}
        covers = search.get("src") and search.get("volumes") and (due < FIRST_ONLINE_RENEWAL_YEAR
                                                                    or search.get("online_records"))
        if covers:
            return "script_registered_not_renewed", [
                {"claim": f"registered {reg['reg']} in {reg['year']}", "src": reg["src"]},
                {"claim": f"no renewal found in {', '.join(map(str, search.get('volumes') or []))}"
                          + (" and the online records" if search.get("online_records") else ""),
                 "src": search.get("src")}]
        return "script_registered_unchecked", [{"claim": f"registered {reg['reg']} in {reg['year']}; renewal "
                                                         f"due {due} not searched", "src": reg["src"]}]

    # Not castable.
    if gov.get("agency"):
        return "script_gov_unverified", [{"claim": f"{gov['agency']} series; this script's author is not on record",
                                          "src": gov.get("src")}]
    authors = s.get("authors") or []
    if (authors and s.get("for_hire") is False and not pub.get("year")
            and all(a.get("died") and a["died"] <= author_died_line(today) for a in authors)):
        return "script_author_died_unapplied", [{"claim": f"{a['name']} died {a['died']}", "src": a.get("src")}
                                                for a in authors]
    return "script_no_evidence", [{"claim": "no publication, registration, clearance, or government authorship "
                                            "on record", "src": src.get("url")}]


STATE = {
    "script_takedown": "hide_claim", "script_source_terms": "hide_claim", "script_nc_licence": "hide_claim",
    "script_renewed": "hide_claim",
    "script_adaptation_unchecked": "not_castable", "script_translation_unchecked": "not_castable",
    "script_foreign_restorable": "not_castable",
    "script_gov_work": "castable", "script_pd_published_age": "castable", "script_registered_age": "castable",
    "script_source_cleared": "castable", "script_registered_not_renewed": "castable",
    "script_registered_unchecked": "not_castable", "script_gov_unverified": "not_castable",
    "script_author_died_unapplied": "owner_pending", "script_no_evidence": "not_castable",
}


def judge(s, ctx):
    b, ev = bucket(s, ctx)
    return {"bucket": b, "state": STATE[b], "castable": STATE[b] == "castable", "evidence": ev}


# ---- the two corpora measured today -------------------------------------------------------------

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "..", ".cache")
EDITORIAL = os.path.join(HERE, "..", "editorial", "script_evidence.json")


def from_gutenberg(p):
    kind = "radio" if any("Radio plays" in x for x in p.get("subjects") or []) else "stage"
    pub = None
    if p.get("year_basis") == "front_matter_copyright":
        pub = {"year": p["year"], "src": p["source_url"], "claim": p["evidence"][-1]["claim"]}
    return {"id": p["id"], "kind": kind, "title": re.split(r"[\n:;]", p["title"])[0],
            "authors": p.get("authors") or [], "translators": p.get("translators") or [], "published": pub,
            "source": {"name": "Project Gutenberg", "url": p["source_url"], "rights_text": p["rights"]["text"],
                       "rights_src": p["rights"]["src"]}}


def from_grw(g, ev):
    terms = ev["source_terms"]["Generic Radio Workshop"]
    s = {"id": "grw-" + g["id"], "kind": "radio", "title": g["title"], "authors": [],
         "source": {"name": "Generic Radio Workshop", "url": g["url"], "terms": terms}}
    gov = ev.get("gov_series", {}).get(g["series"])
    if gov:
        s["gov"] = {"agency": gov["agency"], "src": gov["src"]}
    reg = ev.get("registrations", {}).get(g["id"])
    if reg:
        s["registration"] = reg
    return s


def main():
    today = datetime.date.today()
    ev = json.load(open(EDITORIAL))
    ren = json.load(gzip.open(os.path.join(CACHE, "cce_drama_renewals.json.gz"), "rt"))
    ctx = {"renewals": renewal_index(ren), "takedowns": ev.get("takedowns", {}), "today": today}
    report = {}
    plays = json.load(open(os.path.join(CACHE, "gutenberg", "plays.json")))["plays"]
    grw = json.load(open(os.path.join(CACHE, "grw", "scripts.json")))["scripts"]
    for name, rows, conv in (("gutenberg", plays, from_gutenberg), ("grw", grw, lambda g: from_grw(g, ev))):
        counts, castable = {}, {"radio": 0, "stage": 0}
        for row in rows:
            s = conv(row)
            j = judge(s, ctx)
            counts[j["bucket"]] = counts.get(j["bucket"], 0) + 1
            castable[s["kind"]] += j["castable"]
        report[name] = {"records": len(rows), "buckets": counts, "castable": castable}
    # GRW's work layer, as if the transcription's terms allowed reuse (research 08 C8).
    work = {}
    for g in grw:
        s = from_grw(g, ev)
        s["source"].pop("terms")
        b = bucket(s, ctx)[0]
        work[b] = work.get(b, 0) + 1
    report["grw_if_permission"] = work
    json.dump(report, sys.stdout, indent=1)
    print()


if __name__ == "__main__":
    main()
