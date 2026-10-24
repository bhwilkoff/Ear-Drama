"""The castable-script rights test, one case per bucket, each with a control that
should produce the opposite verdict.

    python3 tests/test_script_rights.py
Broken controls, 2026-10-22, each run against a mutated copy of script_rights.py
(the count is how many cases still passed; every mutation must fail at least one):
    rescue before hide (clearance first)   17/22    age line off by one              19/22
    missing renewal row alone opens        19/22    collection counts as authorship  20/22
    author death (C9) applied, pre-ruling  21/22    renewals never expire            21/22
    title renewal ignores the author       21/22    adaptation renewal hides a play  21/22
    GRW terms not a hide                   21/22    translation ignored              21/22
    any "public domain" text clears        21/22
C9 accepted (owner 2026-10-23), 2026-10-24: the bucket left not castable 21/22; a
registration on record ignored 21/22.
The adaptation control first PASSED 22/22: its only fixture's author had died
before the renewal, which a second rule already refuses. Tarkington's case fixed it.
"""
import datetime
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import script_rights as R

TODAY = datetime.date(2026, 10, 22)
PG = {"name": "Project Gutenberg", "url": "https://www.gutenberg.org/ebooks/27357",
      "rights_text": "Public domain in the USA.", "rights_src": "https://www.gutenberg.org/ebooks/27357.rdf"}
GRW_TERMS = {"reuse": "ask", "quote": "TLDR: Assume Copyright", "src": "https://www.genericradio.com/copyright"}


def script(**kw):
    s = {"id": "s1", "kind": "radio", "title": "The Landing of the Pilgrims",
         "authors": [{"name": "Carlton, Henry Fisk", "born": 1892, "died": 1973}], "translators": [],
         "source": {"name": "A Library", "url": "https://example.org/s1"}}
    s.update(kw)
    return s


def renewal(**kw):
    r = {"title": "Good grammar", "author": "QUILLAN, DON", "claimant": "S. C. Johnson", "reg": "D10032",
         "orig_date": "1947-05-06", "orig_year": 1947, "r": "R570001", "r_date": "1974-05-01",
         "text": "Good grammar ... D10032. R570001", "src": "https://archive.org/details/catalogofcopyrig32834libr"}
    r.update(kw)
    return r


def ctx(renewals=(), **kw):
    c = {"renewals": R.renewal_index(list(renewals)), "takedowns": {}, "today": TODAY}
    c.update(kw)
    return c


def j(s, c=None):
    return R.judge(s, c or ctx())


CASES = []


def case(fn):
    CASES.append(fn)
    return fn


def reg(year=1947, reg="D unp. 10032"):
    return {"reg": reg, "year": year, "src": "https://archive.org/details/catalogofcopyrig3134libr"}


SEARCH = {"volumes": [1974, 1975], "src": "https://archive.org/details/catalogofcopyrig32834libr",
          "by": "editor", "date": "2026-10-22"}


@case
def nothing_on_record_is_not_castable_and_says_what_was_checked():
    r = j(script())
    assert (r["bucket"], r["state"]) == ("script_no_evidence", "not_castable"), r
    assert r["evidence"][0]["src"] == "https://example.org/s1"


@case
def every_row_carries_evidence_with_a_source():
    rows = [script(), script(source=PG), script(published={"year": 1927, "src": "https://x/y"}),
            script(registration=reg(), renewal_search=SEARCH), script(gov={"agency": "USDA", "src": "https://x"})]
    for s in rows:
        r = j(s)
        assert r["evidence"] and all(e.get("src") for e in r["evidence"]), r


@case
def takedown_hides_even_a_cleared_text():
    c = ctx(takedowns={"s1": {"claim": "request from the estate", "src": "https://example.org/letter"}})
    assert j(script(source=PG), c)["bucket"] == "script_takedown"
    assert j(script(id="s2", source=PG), c)["bucket"] == "script_source_cleared"


@case
def grw_transcription_waits_on_permission_even_when_the_work_is_free():
    s = script(source={"name": "Generic Radio Workshop", "url": "https://grw/x", "terms": GRW_TERMS},
               published={"year": 1927, "src": "https://www.gutenberg.org/ebooks/27357"})
    r = j(s)
    assert (r["bucket"], r["state"]) == ("script_source_terms", "hide_claim"), r
    s["source"].pop("terms")
    assert j(s)["bucket"] == "script_pd_published_age"


@case
def non_commercial_licence_is_not_castable():
    nc = {"reuse": "nc", "quote": "free to use for all non-commercial purposes", "src": "https://folger.edu/x"}
    assert j(script(source={**PG, "terms": nc}))["bucket"] == "script_nc_licence"
    assert j(script(source=PG))["bucket"] == "script_source_cleared"


@case
def registration_renewed_by_number_hides():
    c = ctx([renewal()])
    r = j(script(registration=reg(), renewal_search=SEARCH), c)
    assert (r["bucket"], r["state"]) == ("script_renewed", "hide_claim"), r
    assert r["evidence"][0]["src"].startswith("https://archive.org/")
    # control: another number in the same volume is not this script's renewal
    assert j(script(registration=reg(reg="D unp. 10033"), renewal_search=SEARCH), c)["bucket"] \
        == "script_registered_not_renewed"


@case
def renewal_by_title_needs_the_same_author_and_year():
    c = ctx([renewal(title="The Landing of the Pilgrims", author="CARLTON, HENRY FISK", reg="D90000",
                     orig_year=1935)])
    pub = {"year": 1935, "src": "https://example.org/titlepage"}
    assert j(script(source=PG, published=pub), c)["bucket"] == "script_renewed"
    assert j(script(source=PG, published={**pub, "year": 1931}), c)["bucket"] == "script_source_cleared"
    other = script(source=PG, published=pub, authors=[{"name": "Smith, Jane"}])
    assert j(other, c)["bucket"] == "script_source_cleared"


@case
def renewal_of_an_adaptation_claims_the_adaptation_not_the_play():
    ham = [{"name": "Shakespeare, William", "died": 1616}]
    adapted = renewal(title="Hamlet, Prince of Denmark", author="SHAKESPEARE, WILLIAM", reg="D40000", orig_year=1937,
                      text="HAMLET, PRINCE OF DENMARK, by William Shakespeare; brought up to date & rendered "
                           "into modern American")
    s = script(title="Hamlet, Prince of Denmark", authors=ham, source=PG)
    assert j(s, ctx([adapted]))["bucket"] == "script_source_cleared"
    plain = renewal(title="Night Must Fall", author="WILLIAMS, EMLYN", reg="D36020", orig_year=1935,
                    text="NIGHT MUST FALL, a play in 3 acts by Emlyn Williams. D36020")
    nm = script(title="Night Must Fall", authors=[{"name": "Williams, Emlyn", "died": 1987}], source=PG)
    assert j(nm, ctx([plain]))["bucket"] == "script_renewed"
    rewritten = renewal(title="The Man from Home", author="TARKINGTON, BOOTH", reg="D80000", orig_year=1941,
                        text="THE MAN FROM HOME, a play in 4 acts by Booth Tarkington. Completely rewritten & revised")
    home = script(title="The Man from Home", authors=[{"name": "Tarkington, Booth", "died": 1946}], source=PG)
    assert j(home, ctx([rewritten]))["bucket"] == "script_source_cleared"
    # an author dead before the registration cannot have registered it
    assert j(script(title="Night Must Fall", authors=[{"name": "Williams, Emlyn", "died": 1930}], source=PG),
             ctx([plain]))["bucket"] == "script_source_cleared"


@case
def an_expired_renewal_is_no_longer_a_claim():
    c = ctx([renewal(title="Old Play Here", author="CARLTON, H", orig_year=1925, reg="D70000")])
    s = script(title="Old Play Here", source=PG, published={"year": 1925, "src": "https://x"})
    assert j(s, c)["bucket"] == "script_pd_published_age"
    c2 = ctx([renewal(title="Old Play Here", author="CARLTON, H", orig_year=1931, reg="D70000")])
    assert j(script(title="Old Play Here", source=PG, published={"year": 1931, "src": "https://x"}), c2)["bucket"] \
        == "script_renewed"


@case
def adaptation_of_an_unchecked_story_is_not_castable():
    s = script(published={"year": 1927, "src": "https://x"}, adapts={"work": "War Eagle War", "src": "https://y"})
    assert j(s)["bucket"] == "script_adaptation_unchecked"
    s["adapts"]["free_evidence"] = {"claim": "Julian Rothery, US Forest Service", "src": "https://z"}
    assert j(s)["bucket"] == "script_pd_published_age"


@case
def modern_translation_of_an_old_play_is_not_castable_on_the_playwrights_age():
    tr = [{"name": "Fjelde, Rolf", "year": 1965}]
    s = script(published={"year": 1879, "src": "https://x"}, translators=tr)
    assert j(s)["bucket"] == "script_translation_unchecked"
    assert j(script(published={"year": 1879, "src": "https://x"},
                    translators=[{"name": "Archer, William", "year": 1889}]))["bucket"] == "script_pd_published_age"
    # Gutenberg cleared the edition, translation included
    assert j(script(source=PG, translators=tr))["bucket"] == "script_source_cleared"


@case
def foreign_play_after_the_line_may_be_restored():
    s = script(country="GB", published={"year": 1935, "src": "https://x"})
    assert j(s)["bucket"] == "script_foreign_restorable"
    assert j(script(country="GB", published={"year": 1925, "src": "https://x"}))["bucket"] \
        == "script_pd_published_age"
    assert j(script(country="GB", source=PG))["bucket"] == "script_source_cleared"


@case
def government_work_needs_this_scripts_author_and_employer():
    gov = {"agency": "USDA Forest Service", "src": "https://archive.org/details/usda-unclesamsforrang"}
    r = j(script(gov=gov))
    assert (r["bucket"], r["state"]) == ("script_gov_unverified", "not_castable"), r
    full = {**gov, "author": "C. E. Randall", "employer_src": "https://archive.org/details/CAT11087275262"}
    assert j(script(gov=full))["bucket"] == "script_gov_work"


@case
def published_age_line_moves_every_new_year():
    s = script(published={"year": 1930, "src": "https://x"})
    assert j(s, ctx(today=datetime.date(2025, 12, 31)))["bucket"] == "script_no_evidence"
    assert j(s, ctx(today=datetime.date(2026, 1, 1)))["bucket"] == "script_pd_published_age"
    assert j(script(published={"year": 1931, "src": "https://x"}))["bucket"] == "script_no_evidence"


@case
def published_needs_a_source_a_reader_can_open():
    assert j(script(published={"year": 1927}))["bucket"] == "script_no_evidence"


@case
def before_1931_does_not_free_an_unpublished_broadcast():
    s = script(date="1928-12-21", authors=[{"name": "Network Staff"}])
    assert j(s)["bucket"] == "script_no_evidence"


@case
def registered_1930_or_earlier_is_free_by_registration_age():
    assert j(script(registration=reg(year=1930)))["bucket"] == "script_registered_age"
    assert j(script(registration=reg(year=1931)))["bucket"] == "script_registered_unchecked"


@case
def missing_renewal_row_alone_never_opens_a_script():
    r = j(script(registration=reg()))
    assert (r["bucket"], r["state"]) == ("script_registered_unchecked", "not_castable"), r
    r = j(script(registration=reg(), renewal_search=SEARCH))
    assert (r["bucket"], r["state"]) == ("script_registered_not_renewed", "castable"), r
    assert len(r["evidence"]) == 2


@case
def renewal_due_in_1978_or_later_needs_the_online_records():
    s = script(registration=reg(year=1950), renewal_search=SEARCH)
    assert j(s)["bucket"] == "script_registered_unchecked"
    s["renewal_search"] = {**SEARCH, "online_records": True}
    assert j(s)["bucket"] == "script_registered_not_renewed"


@case
def registered_after_1963_renewed_automatically():
    assert j(script(registration=reg(year=1964), renewal_search=SEARCH))["bucket"] == "script_no_evidence"


@case
def author_died_by_1955_is_castable_c9():
    a = [{"name": "Carlton, Henry Fisk", "died": 1955, "src": "https://www.wikidata.org/wiki/Q1"}]
    r = j(script(authors=a, for_hire=False))
    assert (r["bucket"], r["state"], r["castable"]) == ("script_author_died", "castable", True), r
    assert r["evidence"] == [{"claim": "Carlton, Henry Fisk died 1955", "src": "https://www.wikidata.org/wiki/Q1"}]
    assert j(script(authors=[{**a[0], "src": None}], for_hire=False))["bucket"] == "script_no_evidence"
    assert j(script(authors=a + [{"name": "Hire, Some", "src": "https://x"}], for_hire=False))["bucket"] \
        == "script_no_evidence"
    assert j(script(authors=a, for_hire=False, registration=reg(year=1964)))["bucket"] == "script_no_evidence"
    assert j(script(authors=a, for_hire=False, published={"year": 1940, "src": "https://x"}))["bucket"] \
        == "script_no_evidence"
    assert j(script(authors=[{**a[0], "died": 1956}], for_hire=False))["bucket"] == "script_no_evidence"
    assert j(script(authors=a, for_hire=None))["bucket"] == "script_no_evidence"
    assert j(script(authors=a, for_hire=False), ctx(today=datetime.date(2025, 6, 1)))["bucket"] \
        == "script_no_evidence"


@case
def source_clearance_needs_the_clearing_sources_own_words_and_link():
    assert j(script(source=PG))["bucket"] == "script_source_cleared"
    assert j(script(source={**PG, "rights_text": "Copyrighted. Read the copyright notice inside this book."})) \
        ["bucket"] == "script_no_evidence"
    assert j(script(source={**PG, "name": "Some Uploader"}))["bucket"] == "script_no_evidence"
    assert j(script(source={**PG, "rights_src": None}))["bucket"] == "script_no_evidence"


def main():
    failed = 0
    for fn in CASES:
        try:
            fn()
        except AssertionError as e:
            failed += 1
            print(f"FAIL {fn.__name__}: {e}")
    print(f"{len(CASES) - failed}/{len(CASES)} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
