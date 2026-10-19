# Track C: people, programs, networks, sponsors (2026-10-19)

## What was built

| File | Purpose |
|---|---|
| `tools/harvest_goldin.py` | All of RadioGOLDINdex through its own search endpoint (`POST /Home/radioGoldIndexSearch`, `count=1000`, `sortby=CATALOGNUM-ASC`). Each page is cached as it arrives (`.cache/goldin/pages/NNNN.json.gz`), merged into `.cache/goldin/records.json.gz`. `--record-pages N` samples record pages (`/ProgramMoreinfo/<n>`) for the fields the JSON leaves out. 3 s between requests; a failed page is recorded and the run exits non-zero |
| `tools/harvest_otrrpedia.py` | OTRRpedia over `jqSelectM7.php`: `progPedia`, `peoplePedia`, `otterlog` (one request each), then `programData&idp=` per program (programs with logs first) and `personData&idp=` per person (most-credited first). One file per response under `.cache/otrrpedia/`; 1.5 s apart; resumable |
| `tools/enrich_db.py` | Runs after `build_db.py`. It adds tables and columns to `out/radio-catalog.sqlite` and never rewrites build_db's rows. It works on a copy, swaps the copy in atomically, and refuses the swap if the DB was rebuilt in the meantime. A re-run drops and rebuilds only what it added |
| `tests/test_enrich_db.py` | 52 checks: parsers, series-name matching, and a full join on a small DB built from `schema.sql`. Each control was seen to fail (counts are in the docstring) |

Tables added: `people`, `episode_credits`, `program_runs`, `sponsors`, `goldin_records`, `series_map`.
Columns added: `series.{otrr_idp, networks, first_broadcast, last_broadcast, broadcast_span_source, genres_otrr, sponsors_otrr}` and `episodes.{network, network_source, goldin_cat, otrr_eid}`.

Prose rule: Goldin's PLOT is kept only in `goldin_records.plot`, with `plot_display_allowed = 0` and `plot_provenance` (for example "RadioGOLDINdex (J. David Goldin), radiogoldin.library.umkc.edu, record 24104"). OTRR `infos`/`synopses` stay in the cache and are not loaded. Every other field is a fact.

## Measured: RadioGOLDINdex

- **124,919 records** harvested (the 2026-10-17 count was 124,659). 125 of 125 pages read, 0 missing against the claimed total, and every CATALOGNUM is distinct. The server reset the connection several times; the retry logic recovered each one.
- How full each field is: PLOT 115,637 · ARTIST 113,393 · SOURCE 119,610 · DURATION 119,275 · SDATE 96,097 (one parsable date per record; no partial dates) · TITLE 46,083 · PROGNUMB 53,177 · **SPONSOR 0 in the JSON**.
- **Sponsor exists only on the record pages.** In a random sample, 82 of 119 record pages so far carry a Sponsor; the sample is still running toward 300. Fetching every record page would take about 125k requests (~4 days at 3 s), so it was not started. That is a decision for the main session.
- What the Source field says (one record can count twice): network 62,048 · syndicated 30,819 · AFRS 3,133 · local stations (WOR 1,757, WNYC 1,575, WGN 553...) · **television 4,212**. TV records are kept in the table but never linked to a radio episode.
- Artists are parsed into (name, role, character, note). A parenthesis holding a list of short roles becomes roles; a quoted parenthesis becomes a character; a long parenthesis becomes a note. "Sammy Davis, Jr." stays one name. Roles are normalized (adapter/adaptor, the commercial spokes-forms, m.c./emcee).
- Durations: exact timings ("29:42") go to `duration_s`. Goldin's starred nominal lengths ("*30 minutes", "*1/2 hour") go to `duration_nominal_min`.

## Measured: OTRRpedia

- `progPedia` 10,783 programs · `peoplePedia` 51,130 people · `otterlog` 3,918 logged programs (single requests, cached).
- `programData` adds **dated** sponsors and program-level people. `personData` adds birth and death dates, birth name and place, and a link to the person's Goldin artist page (idtype 102, "Bagni, Gwen&ArtistNumber=16440"). That link is the bridge used to resolve Goldin names to OTRR people.
- **Harvest status at report time: programData 980 of 10,816, personData 963 of 51,131. Both are still running** under nohup at ~2 s a request, so roughly 5 h and 28 h remain. progPedia already holds every program's histories and its undated sponsors, so the remaining programData mainly adds sponsor dates. Re-run `enrich_db.py` when the harvests finish; restart either harvester with the same command if it gets killed.

## Series mapping (Goldin/OTRR program name to our series key)

A program can map to several of our keys, because build_db splits series (loneranger / lonerangerthe; Jungle Jim 01-05). It maps two ways:
1. **By name**: `otr_parse.norm_series` on the raw name and on the "X, The" reordering, plus `editorial/series_aliases.json`.
2. **By date corroboration**: at least 3 of the program's dated records fall on dates where the series has an episode, the qualifying keys together cover at least 30% of those dates, **and** `same_name` holds. `same_name` means one of two things: one name's significant words all appear in the other (the smaller side has at least 2 words and at least 2/3 of the larger's), or one name's whole word sequence (with "The", network prefixes, "Adventures of", "Show" and "NN Eps" stripped) sits inside the other and is at least half its letters. "Shares a word" was tried first and mapped CBS News of the World to Radio News, Star and the Story to Pacific Story, and Eddie Bracken to Pacific Story. Letter containment mapped BBC Radio Newsreel to Radio News. A bare word subset mapped Guest Star to Jack Benny As A Guest Star. All of these are now test controls.

Result: **OTRR** 1,429 programs mapped (1,599 keys by name, 220 by dates); 9,387 not mapped, almost all with no archive.org series of ours. **Goldin** 1,192 programs mapped (1,148 keys by name, 243 by dates), holding 62,170 records; 12,592 programs not mapped. Of Goldin's 92,246 dated radio records, 39,728 are in programs we did not map. A spot check of 45 random date-corroborated keys found 1 doubtful one ("A Christmas Carol" to a "Christmas" grab-bag series, where the dates do coincide). Every link is in `series_map` with its method and its hit counts.

## Coverage of our 203,946 episodes (82,239 dated)

| Measure | Before | After |
|---|---|---|
| Episodes with any credit | **15,732** | **41,404** (OTRR 34,026 · Goldin 16,219) |
| Playable (keep_*) episodes with credits | — | 37,932 of 142,461 |
| Episodes matched to a Goldin record | 0 | **31,353** (28,036 of 70,869 dated playable) |
| Episodes matched to an OTRR log row | 14,860 (file-dated) | 59,778 |
| Episodes with a network | 0 | **49,572** (Goldin's source first, else the OTRR run covering the date) |
| Episodes with a Goldin plot (stored, `display_allowed = 0`) | 0 | **28,752** |
| Series with networks / OTRR genres / a first–last broadcast span | 0 | 1,283 / 1,333 / 1,565 |

Within the series Goldin covers, 27.7k of 40.5k dated episodes (68%) found a Goldin record; within the series OTRR maps, 55k of 57k dated episodes have a log row. Undated episodes link only on a title that is unique on both sides: 4,653 OTRR and 327 Goldin. Most of the 121,707 undated episodes cannot be reached on (series, date). Better dates and series keys from build_db will raise every number above with no change here.

Totals: 376,811 `episode_credits` (157,322 carried over from build_db's file-matched credits, 146,522 OTRR by series+date, 72,952 Goldin; 192,135 Goldin credits skipped as duplicates of OTRR's, since OTRR imports Goldin's roles). Goldin artists resolved to an OTRR person id: 61,310 credits (7,163 people). Goldin-only people: 2,637. `people` 53,768 (675 with a birth date so far; this grows as personData lands). `program_runs` 6,268 · `sponsors` 1,722 (282 dated).

## Notes for the main session

- Run order: `build_db.py` then `enrich_db.py` (about 40 s), then `tests/test_enrich_db.py`. Results also land in `out/enrich_report.json` and in `meta.enrich_report`.
- OTRR network strings are raw and include typos ("Bllue", "ABC Blue"). They were left as OTRR wrote them.
- Goldin's own catalogue numbers and record URLs are in `goldin_records.url`, so a client can credit and link every fact.
