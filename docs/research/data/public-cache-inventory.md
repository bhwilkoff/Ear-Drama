# What the public catalog Releases hold (R4-9a, 2026-11-24)

Every top-level part of `harvest-cache.tar.xz` and every table of
`radio-catalog.sqlite.xz`, as cut on `catalog-2026-11-21`: where it came from, what
words of other people it holds, what our own documents say of that source's terms, and
whether the publish job reads it. The Releases are public, so this is a list of what we
publish. Counts are MEASURED over the unpacked assets; "prose" counts strings of 60
characters or more. Nothing here is legal advice, and nothing but the Generic Radio
Workshop's text was changed in this batch.

"CI reads" is measured, not guessed: an audit hook on every `open()` during a full
`tools/catalog_dryrun.sh --with-suites` over the new assets.

## 1. The finding, and others of its kind

| Part | The same defect? | Recommendation |
|---|---|---|
| **Generic Radio Workshop**: `grw/text` (1,028 scripts), `script_cues` (251,775 rows) | Yes. Decisions 067 and 088: none ships without their answer | **Done here** (catalog DECISIONS 043) |
| **RadioGOLDINdex plots**: `goldin_records.plot` (115,637 rows, 18.9 M characters), `goldin/records.json.gz`, and again in `goldin/pages` | **Yes, the largest left.** "Permission required before displaying them verbatim" (research 03 §1.1); `plot_display_allowed = 0` on every row. A public database is the display. No build step reads a plot (`enrich_db` copies it and counts it) | Take `PLOT` out of the packed records and the column out of the published table (keep it locally); drop `goldin/pages` and `goldin/records`, which CI does not read. Small: same shape as this batch. Owner question already open: research 03 §5.1 |
| **Haendiges logs**: `haendiges/logs` (2,370 whole pages, "© 1996 - 2020", no license), `index.html.gz` | **Yes.** "Never republish someone's log" (research 03, finding 5); `harvest_ext_haendiges.py`: "only FACTS are kept". CI reads only `witnesses.json.gz`, the facts | Add `haendiges/logs` and the index page to the denylist; CI needs no change |
| **OTRRpedia notes**: `info` and `synopsis` inside `otrrpedia/programs` (705 and 392 strings) and `otrrpedia/people` (597), about 348,000 characters | **Yes.** Contributors' prose, "cached ... display_allowed = 0" (`harvest_otrrpedia.py`); no build step loads them (report C) | Strip the two fields when packing; the rest of each record is facts CI needs |
| **archive.org reviews**: `reviews.texts` inside `meta` (6,895 bodies, 2.6 M characters), each a user's own words, and uploaders' `description` and `notes` (20.0 M and 1.8 M) | Reviews: **yes in kind**; the build reads only their count and stars. Descriptions: the audit reads them as rights evidence | Strip review bodies when packing. Keep descriptions: they are the evidence, already public on the item page, and a rights decision must be repeatable; ask the owner if that is not enough |
| **Magazine pages**: `magazine_pages/items` (565 issues, 18,183 page texts, 18.3 M characters of OCR) | Not the same: kept only for issues whose year is not renewed or is public domain by age (Decision 040). But the owner ruled the feature OFF, so nothing served needs it | Leave out of the next cut while `SERVE_MAGAZINE_PAGES` is False (9.5 MB), or keep on the rights evidence; the owner's choice. The test that reads it must be checked first |
| **Wikipedia**: `wikipedia/raw` (1,515 pages of wikitext, 16.9 M characters), `wikipedia/api`, `about.json`; `series_about` | No: CC BY-SA 4.0. Republishing asks for attribution and the license | Keep. `series_about` and `about.json` carry URL and license on every row; the raw folder carries neither. Add a `LICENSES.md` to the tar naming it, or leave `raw` and `api` out (CI reads only `about.json` and `witnesses.json.gz`) |
| **Transcripts**: `transcripts-latest`, a Release of its own (9,542 archive.org automatic transcripts, 31.6 M words) | **Not in this cache, but a question.** The contract says the text is "served by archive.org, not re-hosted" to clients, and the pipeline's own Release re-hosts all of it in public. The words are the broadcasts' | Owner's ruling wanted. The build needs the text (search index, gate), so the choices are a private store read with a token, or fetching in the job each time |
| **RadioEchoes**: `radioechoes/series` (5,069 pages parsed to title, date, length, file) | No: facts, no prose. The spine as a whole is one source's compilation (no terms stated; the owner's ruling, research RESEARCH.md §3) | Keep |
| **OTRR logs**: `otrr` | No: `plots` and `infos` are not kept (`harvest_otrr.py`); 5,908 "titles" are long facts about a broadcast, longest 580 characters | Keep |
| **UIUC finding aid**: `uiuc/findingaid_1994.html` (one 2 MB page) | Partly: a library's published finding aid, whole. No terms recorded in our docs | Replace by the parsed sides (a fact file) at the next harvest; low |
| **Library of Congress notes**, **Smithsonian notes** | No: federal catalog text, and Smithsonian Open Access metadata (CC0) (report F) | Keep; `loc/q` (14 MB of raw answers) is not read by CI |

The four marked **Yes** (RadioGOLDINdex plots, Haendiges logs, OTRRpedia notes, reviews) are the same
mistake: a harvester cached prose for its own use and the whole cache was packed. Each is also in every
older dated Release, so a second round of deletions would follow any of them.

## 2. `harvest-cache.tar.xz`, by folder

| Path | From | Others' words in it | Terms, as our docs record them | CI reads |
|---|---|---|---|---|
| `art_grade.json` | measured by us | none | ours | yes |
| `art_v2/` | Commons, English Wikipedia lead images, archive.org search (`harvest_art_v2.py`) | Commons file pages (71 K characters in a sample of 40), license words, captions | each file's own license; Decision 040; Commons text is CC BY-SA | the five parsed files and `commons_raw`; not `ia`, `pages`, `search/`, `enwiki`, `sparql` |
| `cce_drama_renewals.json.gz` | Catalog of Copyright Entries, parsed | none (registrations) | US government publication (catalog README) | yes |
| `commons/` | Commons file pages and data | file descriptions | Commons text CC BY-SA; file rights on each record (report D) | `files.json.gz`, `depicts_labels.json`, `raw`; not `mwapi`, `sdc`, `test` |
| `goldin/` | RadioGOLDINdex JSON | **plots, 36.5 M characters (kept twice)** | no robots.txt, no terms stated; facts free, plots need permission (research 03 §1.1, report C) | `records.json.gz` (its plots are copied, never used); **not `pages`, `records/`** |
| `grw/scripts.json` | Generic Radio Workshop index | none: id, series, title, date, page | facts; the page is linked (DECISIONS 030) | yes |
| `grw/text_ids.json` | made here from `grw/text` | none: 1,028 ids | ours | yes |
| `grw/text/` | Generic Radio Workshop | **1,028 whole scripts** | "remain ... the copyright of their respective owners" (research 01 M20), "Assume Copyright" | **removed** |
| `haendiges/` | otrsite.com | **whole log pages**; `witnesses.json.gz` is facts | "© 1996 - 2020", no license; robots allows (research 03 H2) | **`witnesses.json.gz` only** |
| `librivox.json.gz` | LibriVox API | project descriptions | public domain recordings (research 01) | yes |
| `loc/` | Library of Congress P&P JSON | notes and summaries, 16 M characters | federal; each record's rights advisory (report F) | `records.json.gz` only; not `q`, `item` |
| `magazine_pages/` | archive.org OCR of unrenewed issues | **18.3 M characters of page text** | issue-year `not_renewed` or `pd_by_age` (Decision 040) | `items` (for a table nothing serves) |
| `magazines/` | Online Books Page, CCE Part 2, archive.org | short statements, 24 K characters | evidence quoted with its source (report F) | `evidence.json` |
| `meta/` | archive.org item metadata, 18,834 items | **reviews (2.6 M)**, descriptions (20.0 M), notes (1.8 M) | archive.org's terms were read 2026-11-24 for R4-9 (§3); uploaders' words | yes (not the review bodies) |
| `otrr/` | otrr.org JSON | none kept | robots allows all; sets "are not to be sold" (research 03 §1.2) | `otterlog`, `pTitles`, `programs` |
| `otrrpedia/` | otrr.org JSON | **info, synopsis: 348 K characters** | robots allows all; prose not for display (`harvest_otrrpedia.py`) | all but the duplicate `otterlog` |
| `p72_schedules.json.gz` | US Copyright Office | none | government record (research 02) | yes |
| `people_wd/` | Wikidata, Commons | file page text | Wikidata CC0; Commons text CC BY-SA | `files`, `names`, `entities`, `commons_raw`; not `sparql` |
| `radioechoes/` | radioechoes.com pages, parsed | none | no terms; robots 10 s; spine by the owner's ruling (research RESEARCH.md §3) | `series` |
| `seeds.json` | archive.org search | item titles | facts | yes |
| `series_art/` | Commons, Wikidata | file page text, 7.7 K characters in a sample | as Commons | the four parsed files and `commons_raw` |
| `smithsonian/` | Smithsonian Open Access bulk metadata | notes, 11.5 M characters | CC0 metadata; each image's own usage (report F) | yes |
| `uiuc/` | University of Illinois Archives | one whole finding aid, 2 MB | none recorded | yes (parsed in the build) |
| `wikidata/` | Wikidata, enwiki short descriptions | short descriptions | CC0 (Wikidata); CC BY-SA (enwiki) | the parsed files; not `sparql`, `enwiki` |
| `wikipedia/` | English Wikipedia | **raw articles, 16.9 M characters**; leads | CC BY-SA 4.0 (research 03 §1.6, contract 3.3) | **`about.json`, `witnesses.json.gz` only** |

## 3. `radio-catalog.sqlite.xz`, by table

The publish job restores this file only to compare with the rebuild
(`publish_diff.py`: `episodes`) and `catalog-transcripts.yml` reads `episodes` and
`recordings` from it. Every other table is there because the file is the whole database.

| Table | Rows | From | Others' words |
|---|---|---|---|
| `archive_photos`, `archive_photo_links` | 34,141; 14,847 | Library of Congress, Smithsonian | titles, subjects (federal, CC0) |
| `art`, `series_art` | 2,281; 287 | Commons | file facts, licenses |
| `credits`, `episode_credits`, `people`, `series_marks` | 242,357; 341,431; 53,122; 813 | OTRR, RadioGOLDINdex | names and roles |
| `episodes`, `recordings`, `items`, `wants` | 152,935; 292,655; 18,834; 79,745 | archive.org, RadioEchoes | titles, file names; `evidence` quotes the words a rights decision rests on |
| `episode_external`, `episode_witnesses`, `external_disagreements`, `external_meta` | 39,286; 114,768; 7,143; 34 | Haendiges, Wikipedia, Wikidata | dates and titles |
| `goldin_records` | 124,919 | RadioGOLDINdex | **`plot`: 115,637, 18.9 M characters, `plot_display_allowed = 0`** |
| `magazine_rights`, `magazine_scans` | 91; 1,447 | Online Books Page, CCE | evidence sentences, quoted |
| `people_art`, `people_art_meta`, `people_wikidata`, `series_wikidata`, `wikipedia_sitelinks` | 3,875; 2; 18,500; 573; 5,550 | Wikidata, Commons | short descriptions (CC0) |
| `program_runs`, `sponsors`, `series`, `series_aliases`, `series_map` | 4,916; 1,365; 13,810; 3,922; 3,580 | OTRR, RadioEchoes | facts |
| `series_about` | 538 | English Wikipedia | leads, with URL and license (CC BY-SA 4.0) |
| `series_genre`, `series_scope`, `meta` | 1,338; 1,532; 3 | our rules over the above | none |
| `scripts` | 1,371 | Generic Radio Workshop index | none |
| `script_cues` | 251,775 | Generic Radio Workshop scripts, parsed | **their words; removed** |

Which Releases hold the Workshop's words (each opened and counted, 2026-11-24): all eight
dated Releases hold `grw/text` (1,028 files); `catalog-2026-11-10`, `-11-20` and `-11-21` hold `script_cues`
(251,775 rows). No rolling Release is cut from either. The git repository does not: no tracked file shares a
12-word run with a Workshop text beyond Shakespeare and the Declaration of Independence.

## 4. The stripped assets, and the proof

Staged from `catalog-2026-11-21`'s own assets (`SHA256SUMS` checked), by the README's recipe.

| | Old | New |
|---|---|---|
| `harvest-cache.tar.xz` | 199,327,412 bytes, 115,117 members | 191,908,372 bytes, 114,089 members: `grw/text` (1,029 with its folder) out, `grw/text_ids.json` in after `grw/scripts.json`; every other member the same order, size, date and bytes (`tar -tv`, `diff -rq`) |
| `radio-catalog.sqlite.xz` | 60,237,548 bytes, 35 tables | 50,882,936 bytes, 34 tables: `script_cues` out by `VACUUM INTO`, `integrity_check` ok, 0 free pages, the other 34 tables equal row for row |
| `build_report.json`, `coverage.json` | | byte for byte |

**No words remain.** 20 phrases from 20 scripts, all found in the old database file, are in neither the
new one's cells nor its raw bytes. Every 12-word run of the 1,028 texts (one start in three, 1,588,204 runs)
against every row, the raw file and every unpacked cache member: 51 runs in the database and the same 51 in its raw
bytes, all program openings and cast lists another source quotes (Wikipedia's lead of The Whistler, a Goldin plot),
and the same kind in 147 cache members (Wikipedia, Goldin, archive.org item pages).

**The publish is the same.** Two full `catalog_dryrun.sh` runs on 2026-11-24, the rolling inputs held fixed:
`origin/main` on the old assets against this change on the new, the second with every suite (51 of 51). The projection
(20 tables, 684,046 rows, its search index included), the clean-only projection (34,627 rows) and 15,438 web files are equal. The only
differences are `generatedAt` (in `meta` and the three manifests), the `sha256.zz` that follows from it, and `bytes.zz` of
the clean-only file (2 bytes). In the research database: `script_cues` is gone, one comment in `scripts`' DDL, and the
build times in `meta` and `people_art_meta`; `scripts.text_cached` is 1,028 in both.

One thing CI loses: `test_script_parse.py`'s two checks over cached radio texts now skip there (no texts); they run where the texts are.

## 5. Cutting it, and what to delete after

The folder is staged and passes `--dry-run`; nothing was cut, uploaded or deleted. The tag is any
`catalog-YYYY-MM-DD` newer than the newest dated Release (`catalog-2026-11-21`); the day of the cut is the custom.
Either order of merging this change and cutting works: the old code on the new assets publishes the same projection.

    bash tools/cut_catalog_release.sh --dry-run <staged> catalog-2026-11-24
    bash tools/cut_catalog_release.sh <staged> catalog-2026-11-24
    gh workflow run catalog-publish.yml -R bhwilkoff/Ear-Drama      # wait for green, and read "restoring from catalog-2026-11-24"

Then, and only then (a deleted asset cannot be brought back), these eleven:

| Release | Delete |
|---|---|
| `catalog-2026-10-21`, `-10-28`, `-10-29`, `-10-30`, `-11-09` | `harvest-cache.tar.xz` |
| `catalog-2026-11-10`, `-11-20`, `-11-21` | `harvest-cache.tar.xz`, `radio-catalog.sqlite.xz` |

    for d in 10-21 10-28 10-29 10-30 11-09 11-10 11-20 11-21; do
      gh release delete-asset catalog-2026-$d harvest-cache.tar.xz -R bhwilkoff/Ear-Drama -y
    done
    for d in 11-10 11-20 11-21; do
      gh release delete-asset catalog-2026-$d radio-catalog.sqlite.xz -R bhwilkoff/Ear-Drama -y
    done

Keep a local copy of `catalog-2026-11-21`'s cache: after this, the texts exist only on the machine that harvested them.
The five older databases hold no Workshop words. The root `README.md` and `docs/research/10-repository-move.md` name
`catalog-2026-10-21`; the first should point at the Releases page once its cache is gone.
