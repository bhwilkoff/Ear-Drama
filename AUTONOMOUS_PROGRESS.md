# Autonomous progress: the 1.0 loop

One entry per tick, newest last. The plan is `LOOP-PLAN.md`.

### Tick 1, 2026-10-22, all platforms: M0 platform set in PARITY.md; palette research started
- Context: first tick of the 1.0 loop (5-minute cron, started 3:55 PM MT).
- Implementation: PARITY.md §0 records the core five, the web as lead, and the stubs (Decision 056); §1 carries the six 1.0 top-level verbs; §2 Listening and §3 Making plays carry every 1.0 feature row, all ⏳. A background agent is doing the palette and genre-hue research (M0), writing `docs/research/palette/` for the owner's pick.
- Verification: docs only; `git diff` read before commit. Nothing to observe on a device.
- Owner: opened the DMCA Designated Agent Directory (dmca.copyright.gov) in Chrome at the owner's request; registration is theirs.
- Next: confirm a push triggers CI (an `android/` change), then the `AppName` rename in `project.yml`.

### Tick 2, 2026-10-22, Apple: the generated project is named EarDrama
- Context: M0 "the generated project is named for the app", and the open push-triggers-CI question.
- Implementation: `project.yml` name, target, PRODUCT_NAME, and test target `AppName` -> `EarDrama`; `EarDramaApp.swift`; `tools/app_config.py` (app and executable names, the repo, eardrama.org, mention terms) and `submit-appstore.sh` (project, schemes); `apple/README.md`. `tools/test_app_identity.py` read the target as the literal `AppName`, so adopting the template broke its own test: it now reads the target from `project.yml`'s name (template-worthy; upstream). Version 1.0.1 (2).
- Verification: `xcodegen generate`; unsigned Debug builds with Xcode 27.1 (DEVELOPER_DIR; xcode-select points at the Command Line Tools) for iOS Simulator, tvOS Simulator, and macOS: BUILD SUCCEEDED, no compiler warnings (one appintentsmetadataprocessor log line). Core tests: Swift Testing 1 test passed (XCTest's "Executed 0" counts only XCTest). Identity, version-contract, and US English tests pass. Built, not device-verified.
- CI: today's pushes each started a Pages deploy (push events arrive), but 9cffd08 touched `android-build.yml`, inside its own push paths, and no Android Build ran. This push changes `AppVersion.xcconfig`, also in those paths: watching for a push-triggered run.
- Next: confirm the Android run; the Android debug build (M0).
- CI result: no push-triggered run for e798457 after 80 s; Pages ran. Checked: workflow active, Actions enabled (all actions), not a fork, githubstatus operational, event feed has no PushEvent since the Release at 1:03 PM MT. Dispatched Android Build (39862707734) instead; result read next tick. Recorded in SCRATCHPAD Current State.

### Tick 3, 2026-10-22, Android: zero warnings on the Android build
- Context: dispatched Android Build 39862707734 (e798457) passed, with the debug build and unit tests run (not skipped), and printed one Kotlin warning: `centerAlignedTopAppBarColors()` is deprecated.
- Implementation: `AppRoot.kt` uses `topAppBarColors()`; its title reads "Ear Drama", not "App Name". `android/local.properties` (gitignored) points at `~/Library/Android/sdk`, as Archive Watch's does. Version 1.0.2 (3).
- Verification: local `assembleDebug testDebugUnitTest`: BUILD SUCCESSFUL, no `w:` lines; Gradle daemons stopped after. CI run dispatched for the push (push events still start nothing). Built, not device-verified. M0's rename item is checked: Apple and Android both build warning-free.
- Next: read this tick's CI run; then the fonts item (palette and icon wait on the owner's pick).

### Tick 4, 2026-10-22, data: the catalog restore is measured
- Context: tick 3's dispatched Android Build (39863770465, 4efd2d1) passed with no `w:` lines. M1 item 1.
- Verification, MEASURED 2026-10-22 against the `catalog-2026-10-21` restore (all 4 SHA256SUMS entries OK): all ten catalog suites pass, 362 tests (audio_rights 22, cce_drama_renewals 13, discover_corpus 24, enrich_db 52, enrich_external 37, identity 59, no_recommend 6, otr_parse 41, people_art 66, photo_archives 42). 157,503 episodes, 16,113 series, 300,935 recordings. Rights states: keep_unclaimed 106,782; keep_clean 15,125; hide_claim 25,021; hide_out_of_scope 9,285; hide_unidentified 1,290. These are before catalog Decisions 004-007 are wired in.
- Next: wire the CCE drama renewals into the audit (catalog 004), with a test and a control seen to fail.

### Tick 5, 2026-10-22, data: the script renewals were already in the audit
- Context: M1 "wire the CCE drama renewals into the audit (catalog 004)".
- Finding: they were already wired. `build_db.py` loads `.cache/cce_drama_renewals.json.gz` into the audit's `script_renewals`; the restored snapshot holds 469 `work_script_renewed` and 1,703 `work_series_renewals` episodes (and 2,391 `work_script_claim`, 347 `work_adapted_renewed`); `test_audio_rights.py` covers the match, the 10-renewal floor against 9, and the 96-year expiry. `catalog/README.md` said "not yet wired in", and catalog Decision 004's "How to apply" repeated it from the README. Absence in a doc is not evidence: the database said otherwise.
- Implementation: README's defaults paragraph now states the owner's rulings, what the audit applies, and what it does not yet (the music rule, the AFRS credits rule, post-1949 film renewals). LOOP-PLAN splits the item.
- Next: the stricter music bucket (006), with a test and a control.

### Tick 6, 2026-10-22, data: music-led series hide (catalog 006)
- Context: M1, the stricter music rule.
- Measured first (restored snapshot, series.genres_otrr): OTRRpedia genres leading with Music or Songs cover 195 series and 5,487 kept episodes (Bing Crosby 651, Guest Star 389, Grand Ole Opry 373, Bob Hope Show 238, Kraft Music Hall 167); music with no story genre adds 14 series and 154 episodes (Good News of 1937-40, Eddie Cantor's Time to Smile). Comedy with songs (Jack Benny: Comedy, Variety, Music) stays. 182 RadioEchoes-only "OTR-Variety" series with no OTRR genres carry no music evidence ("Christmas Shows" holds dramas) and stay under the drama rule.
- Implementation: `audit_audio_rights.music_led(genres)` and the `work_music_led` hide (after a sourced work claim, before renewals); `build_db.py` reads OTRRpedia's program genres through the registry's `idp2c` map at audit time, as it does the script renewals, and warns when none match.
- Verification: `test_audio_rights.py` 23/23; the new case fails under two broken controls (never hides; ignores story genres, which hides Jack Benny). A rebuild into the scratchpad is running to measure the real counts.
- Next: read the rebuild's rights table; then the AFRS credits rule.
- Rebuild result (MEASURED 2026-10-22, build_db into the scratchpad, no warnings; 157,503 episodes as before): `work_music_led` 5,961 episodes in 205 series (Bing Crosby 654, Guest Star 389, Grand Ole Opry 373, Jubilee 252, Bob Hope Show 240), none of Jack Benny. States: keep_unclaimed 106,782 -> 101,507; keep_clean 15,125 -> 14,873; hide_claim 25,021 -> 30,548. The 252 clean episodes now hidden are AFRS's Jubilee, a government recording full of other people's songs: the stricter layer wins, as designed. `out/` keeps the restored snapshot until the publish step rebuilds and enriches it.

### Tick 7, 2026-10-22, data: AFRS originals with credited stars are not government work (catalog 006)
- Implementation: `credited_performers(ep)` (any credit outside announcer, writer, producer, director, and crew roles) and a guard in `rec_bucket`: an episode of an AFRS series in `gov_series.json` that credits a performer skips both government rescues (the series list and the producer-text match) and falls through to the recording layer's own state, usually `rec_orphan_unclaimed`. It is not hidden: it stays playable with the unclaimed rights line instead of the clean one. Other agencies (OWI, Treasury) are unchanged.
- Verification: `test_audio_rights.py` 24/24; the new case fails under three broken controls (never sees a performer; counts announcers as performers; leaves the producer-text rescue unguarded). MEASURED on the restored snapshot's credits: Command Performance 203 of 315 episodes credit a performer and move from keep_clean to keep_unclaimed; Jubilee 106 of 252 (already hidden by the music rule).
- Owner question (logged, not blocking): 112 Command Performance episodes have no credits at all, so the literal rule keeps them as government work, though nearly every episode of the series had network stars. Presume stars for the whole series instead?
- Next: the version ranking (catalog 007).

### Tick 8, 2026-10-22, data: the default copy is tested (catalog 007)
- Finding: `build_db` already ranked recordings complete-before-partial, then domestic before variant, then OTRR, then bitrate. Catalog 007's "How to apply", written this afternoon, said kind first, which would play a seven-minute domestic fragment ahead of a whole AFRS disc. The code was right; the decision's wording was not.
- Implementation: the sort moved into `build_db.order_recordings` (no behavior change); catalog 007's "How to apply" amended with the reason; LOOP-PLAN's rights item checked (ticks 6-8).
- Verification: `test_identity.py` 61/61 with two new checks (domestic OTRR, domestic, AFRS, fragment; bitrate never outranks the domestic copy); a kind-first ordering fails the first. All ten catalog suites pass.
- Next: `docs/CATALOG-CONTRACT.md` (M1).

### Tick 9, 2026-10-22, data: CATALOG-CONTRACT.md, draft v1
- Context: M1. Read `shared-data-plane-contract`, `web-catalog-data-layer`, and research 06 §1-2.3 (Archive Watch's contract carried to audio) first.
- Implementation: `docs/CATALOG-CONTRACT.md` DRAFT v1: assets (native SQLite projection on a rolling Release, raw DEFLATE, ETag, validate-then-swap; web JSON on Pages deployed by Actions; audio never re-hosted), the served projection (only `keep_*` rows leave the pipeline), episodes/recordings/series/runs/people/credits/art, word-prefix FTS, an `episode_aliases` forwarding table, query verbs with the `recommendAnd` clause, display vocabulary (unclaimed is never "public domain"), the public-web gate as a publish-step flag, and six contract tests to write with the publish step.
- Measured along the way: 79,612 episodes are undated, with ids from a title slug or an archive path (why the aliases table is in v1); stored download URLs hold raw spaces (the publish step percent-encodes).
- Owner item added to Needs Ben: Pages source to GitHub Actions before the first publish.
- Next: the publish step's projection builder, measuring the sizes the draft marks.

### Tick 10, 2026-10-22, opt: DECISIONS.md rolled, 72 KB to 25.5 KB
- Implementation: entries 001-045 (the template's inherited decisions) moved verbatim to `docs/decisions/DECISIONS-001-045.md`; `DECISIONS.md` keeps its preamble, a one-line index of all 60 entries (archived ones marked), and 046-060 in full.
- Verification: a script split the pre-roll file from git on its `## NNN` headings and found every entry verbatim in one of the two files; agent-files and US English checks pass. LOOP-PLAN's first-opt-tick item done.
- Next: the publish step's projection builder (M1), measuring the sizes the contract marks.

### Tick 11, 2026-10-22, data: the served projection, built and measured
- Implementation: `catalog/tools/build_projection.py` cuts `ear-drama.sqlite` from the research database: only `keep_*` rows; recordings in the pipeline's rank with percent-encoded URLs; series, people, credits; contentless FTS5; `season()` (September opens a season); a floor that refuses a shrunken projection; raw DEFLATE `.zz`; `manifest.json` with counts, bytes, sha256. `--clean-only` is the public-web gate.
- MEASURED (restored snapshot, 16 s): 121,907 episodes, 239,304 recordings, 10,910 series, 17,046 people, 285,751 credits. First cut 190 MB / 35.7 MB compressed; credits were stored twice and the FTS kept its own text copy; after removing both and the raw file path: 133 MB on disk, 27.4 MB compressed. Clean-only: 15,125 episodes, 6.2 MB / 1.2 MB. Every episode has a rank-0 recording; no URL holds a raw space. "sorr* wrong" finds Sorry, Wrong Number; people:moorehead finds credited episodes.
- Data defect seen (for the pipeline, not the client): a 1943-05-25 Suspense broadcast sits under series `1943radionews` with an upload's raw title ("CBS-Suspense---Sorry-Wrong-Number-East-Coast").
- Not yet: the snapshot predates ticks 6-8's rules (the projection follows whatever database it reads); contract tests; the web projection; publishing. Contract §2-3.4 updated with the sizes and the slimmer shape.
- Next: `catalog/tests/test_projection.py` (season, URL encoding, the served-state and rank-0 contract tests, with controls).
