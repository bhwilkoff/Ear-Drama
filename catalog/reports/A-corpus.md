# Track A: completing the archive.org audio corpus

2026-10-19. Everything below was measured; none of it is estimated.

## Result

| | Items | Distinct audio files (originals) | Hours |
|---|---:|---:|---:|
| Before: the five seeds | 12,172 | 242,067 | 102,044 |
| **Added: `editorial/extra_seeds.json`** | **6,659** | **45,922** | **23,052** |
| of which `kind: program` | 3,940 | 38,060 | 18,176 |
| of which `kind: aircheck` | 2,700 | 7,977 | 5,311 |
| of which `kind: shortwave_dx` | 19 | 103 | 27 |

- Of the added files, 16,642 have a file name that `otr_parse` reads as a dated broadcast.
- The hours come from the files' own `length`. 44 added files report more than 6 hours and are counted as 0.
- The `kind` counts in the second table count stems per derivative, so they add up to slightly more than the originals-only total.
- `harvest_ia.py` now reads extra_seeds.json. Its final run read the seeds plus 6,659 extra ids: 18,832 unique items, all in `.cache/meta/` (18,834 files there; the 2 extra files were already in the cache before this track). Every fetch succeeded.
- `collection:oldtimeradio` grew from 8,953 to 9,009 while this ran. One genuinely new seed item was fetched.

`kind` is a coarse label for the build (`aircheck` = DJ, Top-40 or jingles; `shortwave_dx` = DX loggings; `program` = everything else). It never decides whether an item is accepted. **Integrator note:** `build_db.py` globs all of `.cache/meta`, so these items enter the next build. Airchecks and the many talk or public-affairs `program` items (for example *AU Profiles*, WRMC college radio, JTS *Eternal Light* talks) are vintage radio but not drama. Filter on `kind`, or on series, if the app wants drama only.

## Method (`tools/discover_corpus.py`, three resumable stages)

1. **queries**: 449 queries, each cached in `.cache/discover/q/<sha>.json.gz`.
   - Every query records `numFound`.
   - A query is read with scrape only when `numFound` is at most 30,000 and the read reaches at least 98% of `numFound` (the scrape anomaly from 07 §3).
   - `collection:radioprograms` is never read whole. `run_query` raises on it, and the test checks that.
2. **fetch**: a light gate runs on the search fields. Any item that passes has its `/metadata` fetched into `.cache/discover/meta/`, using `harvest_ia.slim`. That was 14,175 fetches at 4 workers in about 55 minutes; 4 came back empty and were recorded as such.
3. **classify**: writes `editorial/extra_seeds.json` (each id with `found_by`, `families`, `reason`, `kind` and `audio_files`) and `.cache/discover/report.json` (every query's counts, and every fetched-and-rejected item with its reason).

### Queries by family (counts are summed over the family's queries; ids repeat across queries)

| Family | Queries | Read | Overlap with the 12,172 | New | Accepted |
|---|---:|---:|---:|---:|---:|
| subject/title/description terms (incl. narrowed broad phrases) | 96 | 168,309 | 16,349 | 151,960 | 20,564* |
| radioprograms filtered by date/decade | 18 | 11,656 | 2,580 | 9,076 | 4,064* |
| OTRR + RadioEchoes series titles (6,566 names, 40 per OR query) | 156 | 139,206 | 5,766 | 133,440 | 4,534* |
| uploaders of existing items (106 with at least 10 items) | 106 | 41,476 | 10,740 | 30,736 | 665* |
| co-collections of existing items (at least 3 items) | 59 + 14 measured only | 142,564 | 4,169 | 138,395 | 145* |
| OTRR log `files[].archive_id` not yet harvested | 2 ids | | | 2 | 1 |

\* These are hit counts taken before the final private-file rule, so one item counts once per query that found it. The deduplicated total is 389,580 candidates and 6,659 accepted.

Top queries by items accepted:

| Query | numFound | Accepted |
|---|---:|---:|
| `subject:radio AND date:[1920 TO 1979]` | 8,732 | 3,157 |
| `subject:otr` | 7,915 (4,302 already held) | 3,086 |
| `radioprograms AND date:[1920 TO 1979]` | 4,329 | 2,007 |
| `collection:airchecks` narrowed | 2,146 | 1,881 |
| `subject:aircheck` | 28,189 | 1,560 |
| `title:"old time radio"` | 1,423 | 1,160 |
| `subject:"radio programs"` | 12,252 | 973 |
| `uploader:alan@smithee.com` | 22,631 | 206 |
| `uploader:qualityradioproductions@yahoo.com` | 1,208 | 102 |
| `subject:"radio drama"` | 4,753 (1,730 already held) | 90 (most of the rest is modern audio drama) |

Measured only, too broad to read (numFound): `subject:"radio program"` 3,817,962 (it matches the radioprograms token); `subject:airchecks` 149,210; `subject:"radio show"` 38,963; `title:"radio show"` 35,442; `radioprograms AND subject:(drama OR mystery …)` 153,475. The co-collections `radioprograms` (5,082,659), `radioshowarchive` (220,085), `radioshowinbox` (170,248), `hifidelity` (236,058), `airchecks` (77,043) and `podcasts` (1,310,989) were read only through narrowed queries (OTR terms or a pre-1980 date).

**OTRR's own archive ids:** only 2 of the 1,188 ids that OTRR's logs cite were missing from the harvest. `lp_the-golden-age-of-comedy-…` was accepted. `OTRR_Cinnamon_Bear_Singles_201901` is dark (recorded as rejected, not as empty).

## Classifier (`classify()`; reasons are stored per item)

| Accepted because | Items |
|---|---:|
| radio term (incl. bare "radio", "broadcast", "air date") + pre-1980 evidence (item year, a title date, or a dated file) | 4,446 |
| file names parse as pre-1980 broadcasts (at least 1, and at least 30% of dated files) | 1,401 |
| old-time-radio term (OTR, golden age of radio, AFRS/AFRTS, transcription disc…) | 545 |
| OTR term + pre-1980 evidence | 141 |
| series title or OTR uploader + a pre-1980 broadcast date in the title | 82 |
| OTR episode in a podcast feed (public files) | 43 |
| named in OTRR's log | 1 |

| Rejected because | Items |
|---|---:|
| light gate: no radio term and no pre-1980 year | 262,154 |
| light gate: not audio | 114,697 |
| **every audio file is private** (the `podcasts_mirror` episode feeds) | 3,144 |
| pre-1980 but nothing says radio (78s, LPs, oral histories, speeches) | 2,193 |
| radio term, no pre-1980 evidence (modern audio drama) | 218 |
| no audio files | 180 |
| OTR term on an item dated 1990+, with no series title and nothing pre-1980 | 157 |
| podcast, no pre-1980 evidence | 147 |
| files dated 1980 or later (≥80% of dated files) | 26 |

Rejected sample, with each item's own title:
- *Filthy '47 – Part 1* (2020 podcast drama tagged old-time radio): podcast
- *Northern Lights Part 1* (BBC 2003): radio drama with no pre-1980 evidence
- *041615 OTR Mixdown* and *Wolfman Jack 032016*: OTR term on a 2016 item
- *Kate Smith – Feudin' and Fightin' (MGM 10041) 1947* and *Erskine Hawkins – Sammy's Nightmare*: pre-1980 music, nothing says radio
- *John F. Kennedy Dictabelt Recording, Tape B*: nothing says radio
- *Becker House Detective 1996-04-13* and *Clean Sweep 97-09-13*: files dated 1980+
- *Raymond Scott – Ectoplasm (1948-1949)*: no audio files
- *Star Bright by X Minus One* (podcasts_mirror): every file private
- radio4all's 885 *Classic Radio* items: modern community radio. "Classic Radio" was found to be a radio4all genre tag and removed from the strong terms; 19 radio4all items that carry their own pre-1980 dates stay, e.g. Norman Corwin's *On a Note of Triumph, 8 May 1945*.

**Known misses (deliberate):**
- 2,853 accepted-looking OTR episodes in `podcasts_mirror` have only private files, so they carry no playable audio. If the build wants their titles and dates as metadata, the reason string identifies them in report.json.
- Single-word series names shorter than 8 letters ("Escape", "Suspense") were not title-queried, because they match too much modern audio. The seeds already hold those series.
- 287 Third Reich speech items (ids containing Hitler or Reichs) (for example "Adolf Hitler – Reichstagsrede") were accepted through a RadioEchoes series of that name. The build should apply a recommendation rule like Archive Watch's Decision 149.

**Precision check:** in a seeded random sample of 40 accepted items, about 36 were vintage radio broadcasts: airchecks, BBC and Radio Caroline shows, Chesterfield/Crosby, *Murder By Experts*, shortwave loggings, college radio. The doubtful ones were a 1971 Weather Report concert, an Apollo 12 recording, a telegraph recording, and a modern psychedelic-scene tribute.

## Files

- `tools/discover_corpus.py` (new). Run `python3 tools/discover_corpus.py [--stage queries|fetch|classify|all]`. Every stage resumes from `.cache/discover/`.
- `tools/harvest_ia.py` (extended). It enumerates the 5 seeds plus extra_seeds.json `queries` (none were needed: every addition is an explicit id) and `ids`, plus an optional `--ids FILE`. It copies metadata that discover already fetched instead of fetching it twice, and a run that only copied still counts as having read something.
- `editorial/extra_seeds.json` (new, 3.6 MB). `.cache/discover/report.json` holds every query and rejection.
- `tests/test_discover_corpus.py` (new): 24 checks.
  - The control was seen failing twice. With `classify()` forced to accept everything, 12 checks failed. With the 1980+ file rule deleted, 1 check failed.
  - `tests/test_otr_parse.py` is unaffected.

Re-run after new uploads: `python3 tools/discover_corpus.py && python3 tools/harvest_ia.py --workers 4`. Cached queries are not re-asked, so delete `.cache/discover/q/` to refresh them.
