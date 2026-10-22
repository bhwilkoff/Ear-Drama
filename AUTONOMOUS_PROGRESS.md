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
