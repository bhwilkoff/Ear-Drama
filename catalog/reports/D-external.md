# Track D — external facts, art and witnesses (2026-10-19/20)

Built and run in this session; every number below is MEASURED from the caches
and from `out/radio-catalog.sqlite` after `tools/enrich_external.py` (DB as
rebuilt by the other tracks at 22:42 UTC: 77,891 dated episodes).

## What was built

| File | Does |
|---|---|
| `tools/harvest_ext_wm.py` | Polite Wikimedia client: SPARQL, Action API, `action=raw`, `Special:EntityData`, and MWAPI-through-SPARQL; every response cached under `.cache/<source>/`, failures listed, never read as empty |
| `tools/harvest_ext_wikidata.py` | Every item typed radio program (Q1555508) or a subclass with an English label, plus every article in enwiki's American radio categories (to depth 3), fetched whole; episode items; value labels |
| `tools/harvest_ext_wikipedia.py` | Episode tables (`{{Episode list}}` and wikitables with a date + title column) from the radio-program articles that name a series we hold and their `List of … episodes` pages |
| `tools/harvest_ext_commons.py` | Commons files from the network publicity-photo categories, a `deepcat` + PD-template search, Wikidata P18/P154, and US radio items' P373 categories; each file's licence template, categories, `\|source=` links and Structured Data depicts |
| `tools/harvest_ext_haendiges.py` | All Jerry Haendiges logs (otrsite.com), fixed-width parse to (series, date, episode no., title, length) |
| `tools/enrich_external.py` | POST-BUILD step: adds `series_wikidata`, `episode_witnesses`, `episode_external`, `external_disagreements`, `art`, `external_meta`; drops and rebuilds only its own tables; writes `out/enrich_external_report.json` |
| `tests/test_enrich_external.py` | 37 checks on synthetic data, 15 mutation controls (docstring) |

Run order (all resumable from cache; the Wikipedia step reads the DB for series names):

    python3 tools/harvest_ext_haendiges.py      # ~2.2 h first run at 3 s/page
    python3 tools/harvest_ext_wikidata.py       # ~25 min
    python3 tools/harvest_ext_wikipedia.py      # ~30 min (1,505 raw pages)
    python3 tools/harvest_ext_commons.py        # ~2 h first run
    python3 tools/build_db.py && python3 tools/enrich_external.py
    python3 tests/test_enrich_external.py       # 37/37

## Access as measured (this changes the method)

- **Wikimedia's Action and REST APIs answered this egress IP 429 almost
  continuously** (en.wikipedia, commons, www.wikidata; `retry-after` 22-35 s;
  shared with other sessions). Three routes still worked and are what the
  harvesters use: the **query service** (SPARQL) for entities and labels; the
  query service's **MWAPI bridge** for enwiki/Commons category listings and
  image info; and **`index.php?action=raw`** plus **`Special:EntityData`** for
  page wikitext and Structured Data, one request per 1.5 s.
- MWAPI drops `apiOutputItem` inside `OPTIONAL` (2,616 articles, 0 ids); ids are
  joined back from Wikidata sitelinks (2,555 of 2,616).
- SPARQL bodies of ~300-590 KB were cut mid-stream through the proxy; retried
  at most 3 times, then recorded as failed. Final runs: 0 failed calls.
- **Digital Deli Too: still unreachable** (TLS reset on both hosts; plain http
  unresolvable; web.archive.org's CDX also reset through the proxy). Nothing
  harvested. Re-probe from a machine outside this proxy.
- Haendiges: robots.txt disallows only `/cgi-bin/`, `/wusage`; 2,371 distinct
  log pages read at 3 s; **1 failed** (`loge1042.htm`, 404 — a dead index link).

## 1. Wikidata series (`series_wikidata`)

9,851 items considered (8,410 radio-class items with English labels + 1,441
enwiki radio-category articles). Matching is conservative:

- names reach a series only by its OWN name/key/editorial alias. OTRR's
  alternate titles were tried and dropped for identity: OTRR files
  predecessors under one id (Sam 'n' Henry under Amos 'n' Andy) — 615 such
  candidate matches refused;
- radio evidence = a radio-program class, or (only for an item with no P31 at
  all) an article in an enwiki radio-PROGRAM category; franchise categories
  (Lone Ranger films, Shadow magazine covers) never vouch. 1,343 items typed as
  something else (TV series, fictional character, film) refused — so The Jack
  Benny Program (TV item only), Dragnet (radio item is a list article) and Our
  Miss Brooks have NO match, by design;
- years must overlap ±2 (Wikidata dates, else the article's decade category);
  78 refused on years; with no years at all the match needs the label, a strong
  class and US origin or an American category (326 refused);
- a tie is left ambiguous (1: Adventures of Superman) unless the tied items are
  radio items with identical dates — Wikidata duplicates (2, e.g. The Lone
  Ranger Q107183100 / Q116487002); the other id is named in the evidence.

| Measure | Count |
|---|---|
| series keys matched to a QID | **573** (491 with overlapping years, 82 with none to compare) |
| …of them with a series row in the DB today | 415 (401 in the RadioEchoes spine) |
| OTRR-logged programs (3,901 keys) with a QID | **428** |
| RadioEchoes series (5,046 keys) with a QID | **525** |
| with enwiki article | 564 |
| MusicBrainz series id (P1407) | 180 |
| image (P18) / logo | 95 / 2 |
| start date | 112 |
| broadcaster (P449) or production company (P272) | 63 |
| genre | 62 |
| creators (P170/P50/P57/P58/P162/P86/P371) | 44 |
| cast (P161/P725) | 25 |
| IMDb | 28 |
| episode count (P1113) | 23 |
| Internet Archive id (P724) | 3 |

As 03-metadata-sources §0 predicted: Wikidata is a label + enwiki +
MusicBrainz layer; network, cast and counts are rare. Rows not yet in the DB
(`in_db = 0`) wait for a build that adds the series.

## 2. Episode witnesses (`episode_witnesses`, `episode_external`)

| Source | Rows | Joined to our (series, date) | Episodes |
|---|---|---|---|
| Haendiges logs | 107,737 (from 109,444 dated lines on 2,029 series headers; 85,622 with a title) | 37,025 | 36,817 |
| Wikipedia episode tables (89 pages) | 7,125 | 5,390 | 5,367 |
| Wikidata episode items | 12 | 8 | 8 |

- **38,993 of 77,891 dated episodes (50%) now have ≥1 external witness**;
  3,191 have two independent sources. By state: keep_unclaimed 30,760,
  keep_clean 391, hide_claim 7,823.
- Suspense: 929 of 971 dated episodes witnessed by Haendiges, 137 by Wikipedia.
- **71,231 (series, date) pairs are witnessed that we hold no episode for** —
  a ready "wants" list with a source per row.
- Unmatched: 628 of 2,029 Haendiges series names reach no key (6,816 rows; e.g.
  "THE JACK BENNY SHOW" 1,141, "TARZAN OF THE APES" 325, "THE BEULAH SHOW") —
  editorial aliases would recover the large ones (`series_aliases.json` is not
  mine to edit). Wikipedia rows outside a series' known years are dropped
  (1,848: TV-run lists such as Father Knows Best); 25 pages skipped as TV lists.

**Disagreements** (`external_disagreements`):

| Kind | Haendiges | Wikipedia | Wikidata |
|---|---|---|---|
| title (same series + date, other title) | 6,019 | 230 | 1 |
| date (our title on another date ≤400 days away) | 689 | 37 | — |

Titles agree on 34,370 rows and disagree on 6,250 (15%), after
case/article/punctuation normalization and a 0.85 spelling-similarity
allowance (Truck/Trunk, Bureacrat/Bureaucrat). Sampled, most title
disagreements are naming, not error: collectors' descriptive titles for
serials and variety ("Visits Art Gallery" vs "GOES TO THE ART GALLERY",
Superman chapter titles vs story-arc names). Date disagreements include
genuine re-broadcasts (Lux "Street with No Name" 1949-01-31 and 1949-12-12),
so they are candidates for review, not corrections.

## 3. Art (`art`)

2,004 Commons files read (145 publicity-category, 709 after the PD search, the
rest from Wikidata P18 and P373 categories); every page read, 0 unread.

| Licence class on the file page | Files |
|---|---|
| PD-US-no notice (incl. the redirects PD-Pre1978, PD-US-pre1978) | 546 |
| PD-US-not renewed (incl. PD-US-no renewal) | 170 |
| PD-US-expired | 29 |
| PD-US-no notice advertisement | 21 |
| PD-US-1978-89 | 1 |
| **usable total** | **767** |
| other (CC BY 389, PD-USGov* ~360, unknown 288, GFDL, CC BY-SA …) | 1,237 — recorded, `usable = 0` |

- Usable files tied to a series: **267, across 107 series** (Fibber McGee and
  Molly 18, Lux 15, The Goldbergs 14, Life of Riley 12, Monitor 10, The War of
  the Worlds 9 …), by: the series' P373 category 153, a "(… radio …)" category
  name 50, the item's P18/P154 81. Tied to a person (Structured Data depicts a
  human): 355. Unlinked but usable: 268.
- 148 usable files mention television in title or categories (a TV-run still of
  a radio series); flagged `mentions_television` in `found_via`.
- **Evidence is recorded, not judged**: `evidence_url` is the file page; the
  template as written and the `|source=` links (eBay listings, Heritage
  Auctions) are in `found_via`. Commons' own editors note many no-notice tags
  rest on no visible evidence (03 §2): a person should open the page before a
  photo ships. No archive.org art is used anywhere.
- Most Commons "Suspense" files are CBS-TV Suspense stills; only 2 tie to the
  radio series (by its "(radio series)" category).

## Tests and controls

`tests/test_enrich_external.py` 37/37. Each control was run against a mutated
copy of the tool and failed (counts in the docstring: e.g. no year check 36/37,
non-radio accepted 35/37, TV item vouched for by category 35/37, heading year
ignored 35/37, PD redirect unrecognized 36/37). Two first PASSED against their
mutation and were rewritten (a non-radio item that lost on score rather than
being refused; a licence test with no non-PD file). The existing
`test_otr_parse.py` (41/41) and `test_audio_rights.py` (22/22) still pass.

## Provenance and rights of what was taken

Facts only: dates, titles, episode numbers, lengths, ids, licence templates.
Not stored: Haendiges' comments column (cast/notes), Wikipedia synopsis/notes
columns (a notes column is refused as a title column, tested), any Commons
description prose. Wikidata is CC0; Wikipedia rows carry the page URL (CC
BY-SA attribution if a title list were ever displayed); Haendiges rows carry
the log URL (© Jerry Haendiges Productions; witness use only).

## Open

- Digital Deli Too unreachable from here.
- Aliases for the 628 unmatched Haendiges series names (editorial).
- The Wikipedia set is limited to articles that name a series we hold (469) and
  their list pages; widening it is cheap now that `action=raw` works.
- Wikidata contribution the project could make: RadioGOLDINdex / OTRR ids
  (no such properties exist, 03 §0 W9).
