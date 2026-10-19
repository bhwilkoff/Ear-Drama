# Track B — identify every episode (2026-10-19)

Owned: `tools/otr_parse.py`, the identity part of `tools/build_db.py`, `tools/schema.sql`
(columns/tables added only), `editorial/series_aliases.json`, `tests/test_otr_parse.py`,
`tests/test_identity.py`. The rights audit is called exactly as before and the existing tables keep
their columns.

## Measured before/after (same caches: 12,174 items, 240,509 chosen files)

"Before" is the committed `build_db.py`/`otr_parse.py` re-run on today's caches (it reproduces
`out/build_report.json` exactly). Each row adds one step to the row above it (`RADIO_SKIP=...`
turns steps off; the builds are in the scratchpad, not `out/`).

| Build | episodes | hide_unidentified | `x:` ids | undated (non-LibriVox) | series | RadioEchoes-matched series | OTRR-identified files |
|---|---|---|---|---|---|---|---|
| before | 203,946 | 41,927 | 43,390 | 107,197 | 18,639 | 1,301 | 26,024 |
| 1. registry + normalization + md5 merge | 154,105 | 20,431 | 22,613 | 75,921 | 7,767 | 1,748 | 26,024 |
| 2. + learned abbreviations | 153,907 | 20,431 | 22,613 | 75,908 | 7,621 | 1,748 | 26,024 |
| 3. + 11 new file-name families, title-only names | 142,620 | 7,120 | 7,430 | 62,432 | 8,655 | 1,781 | 26,024 |
| 4. + text dates, ID3 tags, item metadata | 141,173 | 6,869 | 7,095 | 59,960 | 8,657 | 1,781 | 26,024 |
| 5. + UIUC finding aid | 138,077 | 930 | 1,156 | 54,570 | 10,580 | 1,794 | 26,024 |
| 6. + OTRR logs / spine matching (= final) | **136,304** | **930** | **1,156** | **52,643** | **10,580** | **1,794** | **110,982** |

Episodes fall because copies of the same broadcast that used to sit under different spellings of the
series now share a `series|date` id. I audited the merges: 28,632 new episodes absorbed more than one
old one; in a 40-row sample every merge was the same program (`lonerangerthe|1943-05-03` +
`loneranger|1943-05-03`, `cbsrmt|1974-03-27` + `cbsradiomysterytheater|...`, `400212|1940-02-12` +
`adventuresofsuperman|...`). The series count goes back up from step 3 on because files that had no
identity before now land in series of their own (UIUC programs, title-only uploads). The final count is
6,635 singleton series, down from 13,170. 18,608 old series keys that had files resolve to 7,058 keys.
176,093 of 255,009 recordings now sit in a series that the spine or OTRR knows, up from 98,638.

`content_kind` across the 136,304 episodes: radio 130,276, lecture 2,125, podcast 1,761, commercial
1,015, scripture 971, music 156.

## 1. The canonical series registry (`build_db.Registry`, `build_registry`)

- **Sources.** OTRR's 3,918 program titles, plus **`.cache/otrr/pTitles.json`**: 14,976 alias titles
  for 10,783 program ids, fetched once from `jqSelectM7.php?qid=pTitles`. Also RadioEchoes' 5,069
  names, the editorial aliases, and the claim/government series names.
- **Canonical key.** An OTRR program whose aliases meet a spine name takes that name (2,972 programs).
  Otherwise its main title is reordered ("Shadow, The" becomes "The Shadow"). Every alias key resolves
  to the canonical key.
- **Rules that keep wrong names out.**
  - An alias key that two OTRR programs share is never folded into either (1,706 such keys, e.g.
    "Palace Theater").
  - A one-word alias that names a kind of program is dropped. "Interviews" had filed three shows under
    Adventures by Morse; "Superman" is kept.
- **New table and columns.**
  - `series_aliases(alias_key, series_key, alias, source)` has 3,556 rows over 2,055 series.
  - `series.otrr_programs` and `series.alias_names` are new columns.
- **`norm_series` (the key function).** CamelCase is split first, so "TheShadow" and "The Shadow"
  agree. Other forms that now agree: a trailing ", The"; "&" / "'n'" / "N" read as "and"; accents;
  Theatre/Theater.
- **`series_variants`.** A name is also tried with these parts removed: bracketed text; leading
  collection words (OTRR, Aus 108 -, AFRS, Ron Bowser-John Dunning Project); trailing set words
  (Singles, Digitally Restored, Broadcast Ready, Show, Program, Hour, a volume or number, "15 minute
  shows"). It is also tried piece by piece across " - ", and in both "Adventures of" forms. A variant
  is used only if the registry knows it.
- **Prefix rule.** A name like "Lum and Abner of the classic Show" matches the longest known key that
  ends where a word ends, has at least two words and at least 8 letters.
  - Before the word rules, the sample had "Conflicting Concepts of Education" becoming "Conflict",
    "Whistler's Mother Painting" becoming The Whistler, and "American Armed Forces Radio No 51"
    becoming Americana. Those are now test controls.
  - ID3 tags never use the prefix rule.
- **Series candidates, first known wins.** File-name series, then folder names inside the item, then
  item series, then the item title, then ID3 album, then ID3 artist. If none is known: the file series
  (5+ letters), then the folder, then the item.
- **Learned abbreviations (`learn_abbreviations`).** A file prefix the registry does not know, in items
  whose title or OTRR row names a known series, is learned when all of these hold:
  - it could abbreviate the series (prefix, ordered subsequence or initials, same first letter);
  - 3 or more files say so, and 80% of them agree.
- **Result.** 188 learned; 115 are applied. A 2–3-letter one ("la", "md", "st") applies corpus-wide
  only when 2+ uploads use it for the same series with 20+ files; otherwise it is recorded but not
  applied. Examples: `landa`→Lum And Abner (1,647 files), `ahter`→American History Through The Eyes
  Of Radio (533), `esca`→Escape (270), `tiyfbi`, `hgwt`, `cbsrw`, `atmota`.
- **Where they are written.** Learning reruns every build. `--write-aliases` writes the results with
  their evidence (file count, disagreements, items) to `series_aliases.json` under `_learned`. Moving a
  key into `_rejected` vetoes it.

## 2. OTRR logs beyond exact files (`build_db.match_logs`)

Exact archive file to log row is unchanged: 26,024 files. On top of that, three rules fill gaps:

- **Series + air date.** When the log has a row for that series and date, that row fills number,
  title, credits and the OTRR eid. This matched **84,958 files**:
  - 35,168 checked against the duration of a copy the log lists (0.6–1.6×);
  - 49,790 where the row lists no copy (`otrr_match: series_date:no_duration`).

  It is **not applied**, and the disagreement is recorded instead, in four cases:
  - a duration mismatch (589);
  - several rows on the date and no title to pick one (907);
  - the file's own title shares under 34% of its words with the log title (11,803). For example, a
    file titled "Public Defender {Frank Lovejoy}" on Suspense's 1953-03-23 is left as it is.
  - When titles differ but are similar (35,024), the log's title wins and the file's own title is kept
    in `identity.title_by_name`.
- **Series + title → date.** Applied only in series where the title→date answer already matches files
  that carry both a date and their own title, on 90% of 5 or more checks.
  - The unbiased check over all dated files: OTRR 45,773/49,002 (93%); trusted series
    41,025/42,070 (97.5%).
  - The spine: 46,545/48,190; trusted 44,024/44,908 (98.0%).
  - Dated: 1,840 files from OTRR and 609 from the spine.
  - My first check measured only files the date match had not already claimed, and gave 21%. That
    population was biased toward disagreements, and is the reason the per-series gate exists.
- **Series + number → date.** Under the same gate: 207 of 437 series trusted, 40,756/49,482 checks
  agree corpus-wide, 266 files dated.

`date_source` now takes these values: filename, filename_alt, filename_text, id3_title_text,
id3_album_text, item_metadata, album_tag, otrr_log, otrr_title, otrr_num, spine_title,
uiuc_findingaid. `episodes.identity` (JSON) records how the series was found (and under what name),
the OTRR eid and match method, and every disagreement.

## 3. The unidentified and the undated

- **UIUC.** 27,845 of the 43,390 `x:` files were University of Illinois Archives disc sides named like
  `UIUC_Archives_1306005_0913_B`. They come from 9 overlapping uploads of the same 5,959 files.
  - The Archives' public finding aid for record series 13/6/5 (WILL Sound Recordings, 1927–1999)
    names every side. I cached it once, at 2 MB, in `.cache/uiuc/findingaid_1994.html`.
  - `P.parse_uiuc_findingaid` parses it: 6,121 sides with title, program, speaker and duration, 5,016
    of them with dates.
  - Each episode links to its finding-aid anchor (`identity.uiuc`).
  - BBC London Column and London Forum sides are now `hide_claim` as foreign.
  - Entries with a speaker are `content_kind=lecture`, unless the program is a known radio series
    (Town Meeting of the Air, the University of Chicago Round Table).
- **New file-name families** (each tested with a real name):
  - dotted series: `esca.53.04.12_...`
  - 1980s YYMMDD: `Mindwebs-830326__...`
  - glued YYMMDD first: `481209TheSisters`
  - YYMMDD + number + title: `521029 1030 The Microfilm of Death` (9,078 files)
  - M-D-YY last: `GrandOleOpry05-10-58`
  - ISO date last; D-M-Y or M-D-Y last, where an ambiguous one is not guessed
  - sNNeNN
  - a bracketed number with no date
  - episode markers: `Ep 045`, `ep048`, `Prg #152`, `e049`, `Episode 3`
  - a number last, where "Christmas 1950" reads as a year
  - YY-MM-DD with a number (F2 extended)
  - a 19xx decade
  - title-only names ("Guest Is Victor Moore", 21,336 files), whose series comes from the folder or
    item

  A leading track number is no longer taken as the episode number, and junk stems ("Audio file",
  "30", "Intro") are not taken as titles.
- **Fallbacks.** Dates written out in the ID3 title or album tag ("27 August 1944",
  "November 9, 1947"), and a single-file item's own title and full `date`.
- **Duplicates.** Identical unidentified files (same md5) across items collapse into one `x:` episode
  (113 merged).
- **`content_kind`** (new `episodes` column), each rule with controls:
  - scripture: book + chapter, only in an upload with 20 or more such files, so "Amos 05" alone stays
    radio;
  - music: "Artist & His Orchestra - Song (1934)" under 7 minutes, or a music collection under 7
    minutes;
  - commercial: spot or promo words under 4 minutes;
  - podcast: a podcast collection or title, **only when the series is not a known program**. MindWebs'
    tape archive sits in `podcasts`.
- **What remains.**
  - **1,156 `x:` files**: bare numbers (`33_20210223/30.mp3`), `di101612`, `MaP003`, BBC My Word
    items with no series resolved.
  - **52,643 undated**: 27,276 are in spine series and 26,834 in OTRR-known series, but neither the
    title nor the number appears dated in the log. 1,984 are Grandpa's Stories, which no log covers.
    Others are V-Disc and AFRS compilations whose items carry only a disc number.

## Tests (all pass; broken controls recorded in each docstring)

- `tests/test_otr_parse.py`: 41 cases, up from 15. 26 new names and 6 controls. Mutations:
  - year kept as the number: 39/41
  - M-D guessed: 40/41
  - track number kept: 40/41
  - junk titles kept: 40/41
- `tests/test_identity.py` (new): 59 cases. Ten mutations give 56–58/59 each. The "title → date in an
  unchecked series" control first PASSED (59/59) because the control series had no log titles; it was
  fixed by adding Escape's row.
- `test_audio_rights.py` (21), `test_cce_drama_renewals.py` (13) and the other tracks' tests still
  pass.

## For the integrator / owner

- **Non-radio content is now identified and therefore `keep_unclaimed`.** The audit does not read
  `content_kind`:
  - scripture 968, music 156, podcast 1,693, lecture 2,123, commercial 995.
  - The two choices are that clients play only `content_kind='radio'`, or that the rights track adds a
    hide bucket for these kinds. That is a rights call, so I did not make it here.
- **UIUC.** 2,125 WILL lectures are kept unclaimed: speakers own their talks, and WILL is a state, not
  a federal, station.
- **The `out/` database was not rebuilt.** Run `python3 tools/build_db.py` (add `--write-aliases` to
  refresh the learned list).
  - Existing column names are untouched. `enrich_db.py` adds and NULLs `otrr_eid`/`otrr_idp`, so I
    used `identity` and `otrr_programs` instead.
- **Errors left in the data.**
  - OTRR folds some alias titles that are too wide: Rudy Vallee's shows under one program; Eddie
    Cantor's shows under "Eddie Cantor Its Time To Smile"; any "Sherlock Holmes" under "The Newly
    Discovered Casebook". `_rejected` and the editorial aliases are the levers.
  - The editorial alias `mbf` → "Mr. and Mrs. North" (inherited) looks doubtful.
