# catalog — the rights-designated catalog for Ear Drama

Owner, 2026-10-17: *"Can you start work on building out a full database with each
of the rights designations considered."* Research: `../docs/research/RESEARCH.md`.
Self-contained, stdlib Python only. It was built in Archive Watch's research
branch and moved here, with its history, on 2026-10-22. `editorial/film_renewals_cce.json` is a copy of Archive Watch's
`shared/editorial/cce_renewals.json`, the printed film renewals the Lux-style adaptation check reads.

## Start from the published snapshot

The built database and every harvest cache are on the
[`catalog-2026-10-21` Release](https://github.com/bhwilkoff/Ear-Drama/releases/tag/catalog-2026-10-21),
never in git. From this folder:

    gh release download catalog-2026-10-21 -R bhwilkoff/Ear-Drama -D dist
    (cd dist && shasum -a 256 -c SHA256SUMS)
    mkdir -p out .cache && xz -dc dist/radio-catalog.sqlite.xz > out/radio-catalog.sqlite
    xz -dc dist/harvest-cache.tar.xz | tar -x -C .cache    # rebuild without re-harvesting

## Publishing (`.github/workflows/catalog-publish.yml`)

The apps never read this folder's outputs from git. A workflow, daily and on
dispatch, restores the newest `catalog-YYYY-MM-DD` Release the way the block
above does, rebuilds, tests, and publishes (contract §7):

    python3 tools/build_db.py && python3 tools/enrich_db.py
    bash tests/run_all.sh                                       # every suite; a red one blocks publish
    python3 tools/build_projection.py --out out/publish         # apps: clean + unclaimed
    python3 tools/build_projection.py --clean-only --out out/publish-clean
    python3 tools/build_web_projection.py --src out/publish/ear-drama.sqlite --out out/web   # web: clean only
    PROJECTION=out/publish/ear-drama.sqlite python3 tests/test_projection.py
    WEB_PROJECTION=out/web python3 tests/test_web_projection.py
    python3 tools/publish_diff.py --old-manifest live/manifest.json --new-manifest out/publish/manifest.json

`ear-drama.sqlite.zz` and `manifest.json` go to the rolling Release
`catalog-latest`; the site goes to Pages with the web projection under `/data/`.
The publish refuses a catalog that serves more than 2% fewer episodes than the
live one unless it is dispatched with a `shrink_reason`, which the run summary
records. Every run's summary says what changed: counts and bytes, episodes per
rights state, and which ids left and why.

Two settings are the owner's. **Pages**: Settings > Pages > Source > GitHub
Actions; until then the deploy is skipped with a warning. **The public-web
gate**: the web serves unclaimed rows only when the repository variable
`DMCA_AGENT_REGISTERED` is `true`, set once the DMCA agent is registered.

The publish step reads caches; it does not harvest. New harvests reach the apps
when someone cuts a new dated Release (database, `harvest-cache.tar.xz`,
`SHA256SUMS`), which the next run picks up.

## Run

    python3 tools/harvest_ia.py --workers 4      # archive.org: ~12,171 items, ~3-4 h
    python3 tools/harvest_librivox.py            # 640 dramatic works, ~1 min
    python3 tools/fetch_p72_schedules.py         # 299,447 schedule rows, ~5 min
    python3 tools/harvest_radioechoes.py         # the spine: 5,069 pages at 10 s = ~14 h, resumable
    python3 tools/build_db.py                    # -> out/radio-catalog.sqlite + out/build_report.json
    python3 tests/test_audio_rights.py && python3 tests/test_otr_parse.py

Caches live in `.cache/` and outputs in `out/` (both gitignored; the database is
never committed, as Archive Watch Decisions 017/018). Every harvester exits
non-zero when it read nothing, and records what it could not read.

## Images (2026-10-21; reports/E and F)

    python3 tools/harvest_people_wikidata.py          # people -> Wikidata + portraits; ~2.8 h cold, resumable
    python3 tools/harvest_loc_photos.py --phase all   # Library of Congress; 20 req/min, exit 3 = blocked an hour, re-run
    python3 tools/harvest_smithsonian.py              # Smithsonian Open Access bulk files (no key)
    python3 tools/harvest_magazine_rights.py          # radio magazines: renewal status by title and year
    python3 tools/enrich_people_art.py && python3 tools/enrich_photo_archives.py   # post-build, seconds
    python3 tests/test_people_art.py && python3 tests/test_photo_archives.py

Images follow the audio's take-down rule (owner, 2026-10-21: no review queue):
used when the image's own record carries the evidence, removed on request.

## The rights states (`tools/audit_audio_rights.py`, DECISIONS 001-002)

| State | Buckets | Client |
|---|---|---|
| `keep_clean` | `rec_gov_work`, `rec_librivox`, `rec_cc_corroborated`, `rec_pd_published_age` | plays |
| `keep_unclaimed` | `rec_orphan_unclaimed` | plays; rights line "no claim known; removed on request", never "public domain" |
| `hide_claim` | `rec_takedown`, `rec_schedule_claim`, `rec_rights_holder_claim`, `rec_post_1972`, `rec_foreign_origin`, `work_script_claim`, `work_adapted_renewed` | hidden |
| `hide_unidentified` | `rec_no_evidence` | hidden: no series and date to check a claim against |
| `hide_out_of_scope` | `rec_out_of_scope` | hidden: identified as music, a modern podcast, scripture, a DJ/Top-40 aircheck or shortwave DX (`content_kind`). Vintage commercials and station lectures are broadcasts and stay in. Airchecks and shortwave are out by default — owner questions |

Order: hides before rescues, first match wins; the stricter of the recording and
underlying-work layers wins. Every row's `evidence` lists what decided it, each
with a source a reader can open.

**The owner's rulings** (2026-10-22, `DECISIONS.md` 004-007; 02-rights §11):
non-US productions hidden; post-1972 hidden; AFRS rebroadcasts of network series
judged as that series, and AFRS originals kept as government work only when no
commercial performer is credited; music and variety shows built on popular songs
hidden; unregistered scripts follow the recording (kept while unclaimed); a named,
sourced claimant hides a series. **Applied by the audit today**: script renewals in
the printed Catalog of Copyright Entries drama volumes (`work_script_renewed` for a
matched episode, `work_series_renewals` at 10+ live renewals; 469 and 1,703 episodes
in the 2026-10-21 snapshot). **Not yet applied**: the stricter music rule and the
AFRS credits rule (006), and film renewals after 1949 (Lux episodes adapting 1950s
films read `work_none_found` only because that index is not built).

## Script renewals in print (`tools/fetch_cce_drama_renewals.py`)

    python3 tools/fetch_cce_drama_renewals.py            # ~41 MB of OCR, ~6 min first run; then cached
    python3 tools/fetch_cce_drama_renewals.py --offline  # re-parse .cache/cce_drama/ only
    python3 tests/test_cce_drama_renewals.py

This reads the RENEWAL entries in the Catalog of Copyright Entries' "Dramas and
Works Prepared for Oral Delivery" volumes, the claim source 02-rights §3.1 names
for scripts registered 1923-1950 (renewals filed 1951-1977; from 1978 the
Copyright Office's online records take over). It writes
`.cache/cce_drama_renewals.json.gz`, one row per original registration:
title, episode, series, author, claimant, D/C registration and date, renewal
number and date, volume, line and a `src` link that opens the scan at a search
for the renewal number. `build_db.py` passes it to the audit as `script_renewals`.

**Measured 2026-10-17.** `title:("catalog of copyright entries") AND
title:(dramas)` returns all 31 Third Series volumes, 1947-1977, one a year (plus
14 New Series 1915-26 volumes with no relevant renewals). 1947-1950 print no
renewals (those years' are in Part 14A, Literature/Art/Film, not read). The
other 27 volumes give **11,166 renewals** (original registrations 1922-1950),
**679 flagged radio**, 110 in Class C (lectures and recording scripts), and 213
whose renewal number the OCR mangled. Those rows are kept with `r: null` and the
printed text in `r_printed`: the entry is a renewal, but its number is not
guessed. Four printed layouts are read: 1951-53 under the author with the
renewal number first; 1954-57 under the author with the claimant first; 1958-70
under the title in capitals, where a series lists every registration against one
renewal range; and 1971-77 in renewal-number order with the series in
parentheses. A row needs a © date, a D/C registration, a renewal number and a
renewal date 26-29 years later, so OCR damage causes misses (roughly a quarter to
a third of entries in the worst 1970s volumes), not false matches.

**Validation**, by series (rows; original years; claimant):

| Series | Rows | Registered | Renewed by |
|---|---|---|---|
| The Lone Ranger | 271 (258 by claimant) | 1934-49 | The Lone Ranger Inc., Wrather Corp., Lone Ranger Television (e.g. R300173-5, 1962) |
| Nick Carter | 146 | 1943-50 | Condé Nast (Street & Smith) |
| The Shadow | 71 | 1940-50 | Condé Nast (first: R420827, 1967) |
| Arch Oboler | 47 | 1939-49 | Arch Oboler |
| Green Hornet | 48 (42 by claimant) | 1936-44 | Green Hornet, Inc. (R336319, 1964) |
| The Greatest Story Ever Told | 29 | 1947-50 | Henry Denker |
| Vic and Sade | 15 | 1938-43 | the Rhymer family |
| Let's Pretend | 11 | 1934-49 | CBS, Inc. (R577542-6, 1974) |
| Norman Corwin | 5 | 1942-44 | Corwin, Lucille Fletcher |
| Fibber McGee and Molly | 4 | 1935-44 | Don Quinn's family (R296914, 1962) |
| Cavalcade of America | 4 | 1945-47 | Du Pont |
| The Witch's Tale | 1 | 1933 | Alonzo Deen Cole (R273162, 1961) |
| Suspense, Gunsmoke, Johnny Dollar, Dragnet, Lux, Inner Sanctum | 0 | | |

The raw OCR confirms the zeros: none of those names appears in a block that
carries a renewal number. Inner Sanctum and Lux were registered (Inner Sanctum
lists Tepperman scripts in one volume) and never renewed in print. Gunsmoke,
Dragnet and Johnny Dollar (1949-52) would renew in 1977-80, mostly in the online
records. The "Jack Benny" and "Lights Out" hits are stage plays with those
words in their titles, not the radio series.

**Never recommended, always findable** (`episodes.no_recommend`, Archive Watch
Decision 149 carried over): the Nazi state's own speeches and rallies — a named
official with a speech word, "Reichstagsrede", "Reichsparteitag". Track A found 287
such items entering through a RadioEchoes series. A program ABOUT Hitler is not
flagged (`tests/test_no_recommend.py` holds that control).

## Castable scripts (`tools/script_rights.py`, Decision 059; docs/PLAYS-DESIGN.md)

    python3 tools/harvest_gutenberg_plays.py --texts 20   # Gutenberg's offline catalogs + 20 texts from a mirror
    python3 tools/script_rights.py                        # bucket counts for Gutenberg and GRW
    python3 tools/script_parse.py measure                 # the 50 GRW + 20 play parse sample

A script may be cast only when its own record carries rights evidence: ordered
buckets, hides before rescues, like the audio audit. Measured 2026-10-22: 1,722
of Gutenberg's 1,740 English drama records are castable (4 of them radio plays),
and 0 of GRW's 1,371, all hidden on GRW's own terms until we ask (research 08
C8). "Author died by 1955" (C9) is recorded and not applied.

## Editorial (each entry needs a source a reader can open)

`audio_claims.json` (claimants), `takedowns.json`, `gov_series.json`,
`series_aliases.json`, `licence_evidence.json`, `published_records.json`,
`script_evidence.json` (text-source terms, script registrations, government series).

## Tests

`tests/test_audio_rights.py` (21 cases), `tests/test_otr_parse.py` (15) and
`tests/test_cce_drama_renewals.py` (13; its broken controls are in its docstring),
`tests/test_script_rights.py` (22) and `tests/test_script_parse.py` (7), whose
broken controls are in their docstrings.
Broken controls, 2026-10-17, each run against a mutated copy:

    orphan reads as clean              15/17     no post-1972 rule             16/17
    bare ABC counts as foreign         16/17     age line off by one           16/17
    AFRS copy counts as government     16/17     rescue before hide            16/17
    adaptation window open-ended       16/17     uploader licence rescues      16/17
    script date window open-ended      19/21     series renewal floor of 1     19/21
    script renewals never expire       20/21     script renewal not a hide     19/21
    parser: no leading-track strip     14/15

The "script renewal not a hide" control first PASSED 21/21: the new cases checked
which bucket fired but not the state. They now assert both.

**Schedule matching, measured on the first build**: matching a series to a
performer's name hid 1,318 episodes, nearly all of them radio shows of
performers whose COMMERCIAL RECORDS a label scheduled (Phil Harris 241, Delmore
Brothers 160, Gene Autry 74). A schedule protects the recording it lists, so a
series-level match now needs a scheduled row that is itself a broadcast, and an
episode-level match needs the whole artist name, not a shared first name.

**Script renewals** (`work_script_renewed`, `work_series_renewals`): a broadcast
whose script registration is within 30 days of its air date, or whose title and
year match, is hidden until registration year + 96. A series with 10 or more
live renewals is claimed as a series — a default for the owner, because the
printed catalogs lose a quarter to a third of entries to OCR.
