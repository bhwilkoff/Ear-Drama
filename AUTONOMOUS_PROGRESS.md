# Autonomous progress: the 1.0 loop

One entry per tick, newest last. The plan is `LOOP-PLAN.md`.

Ticks 1-30 are in `docs/progress/ticks-001-030.md`, verbatim.

### Tick 31, 2026-10-22, Apple + Android: the loudness level on every core platform
- Merged a466c86 (Apple) and 43ef6d6 (Android): both read `loudness_i`/`loudness_tp` when the columns exist (NULL otherwise), a pure `LoudnessLevel` mirroring the web's `playbackVolume` and its six cases, unity for any copy but rank 0, the player's base volume set on load (Android per queued item, at each transition), and the sleep fade multiplying from it.
- Verified on main (my run): macOS 43/43 in 10 suites; iOS build; 0 Swift warnings; Android with `--no-build-cache --rerun-tasks` BUILD SUCCESSFUL, 50 tests, 0 skipped, 0 failures, 0 `w:` (settling the agent's cached-warning caveat). The agent's clamp controls failed exactly the clamp case on both. Not heard on a device. A Gradle daemon on Android Studio's Java (pid 99280) was not ours and was left alone. 1.0.13 (14); PARITY loudness row 🚧 on all five.

### Tick 32, 2026-10-22, data: transcripts in the data plane
- Merged b492794: `fetch_transcripts.py` (stable-hash batches of served default copies with a transcript, gzip cache with the gate's verdict, 404/410 retried after 30 days, 429/5xx never recorded, one request a second, a breaker and a budget), `catalog-transcripts.yml` (daily 08:17 UTC = 2:17 AM MT, 1,200 a run, `transcripts-latest` with a `.prev`, shrink guard, verdict job), `catalog-publish.yml` restores it; `build_projection.py` sets `has_transcript` and a new `transcript_url` only where `transcript_gate.shown` passes (re-run at build), indexes every fetched text in FTS, and the FTS is now `detail=column` (positions dropped: phrase/NEAR queries stop; the clients' prefix and column queries still work). Catalog DECISIONS 008 by the agent. Serving: archive.org's own `.txt` URL (MEASURED with curl: CORS `*` on the 302 and the node's 200, preflight 204; a browser check from eardrama.org is still owed).
- MEASURED by the agent: 8,999 served candidates; 50 fetched live, all with text, 3.1 s each; 229 of 233 pass the gate; full cache ~68 MB gzipped; projection now 24.66 MB (detail=column, no transcripts) and an estimated 36-44 MB with all 8,999 (positions kept would be ~+78 MB).
- Verified on main: all 18 catalog suites on rebuilt projections; Apple macOS 43/43 and Android 50/50 against the new schema and seed. Follow-ups delegated: clients read `transcript_url` and show transcripts labeled automatic; Android's series search must stop matching transcript words; web search lacks transcripts (contentless FTS).

### Tick 33, 2026-10-22, data + template: evenings measured; lessons upstreamed
- Android Build 39901679916 (ca84a5a, the loudness merge) passed in CI.
- Upstreamed to UniversalAppTemplate (87f85fcd, pushed): the identity test's literal `AppName` fix, and AUTONOMOUS-LOOPS §8 "Parallel agents share the owner's machine" (no unattended simulators, runs judged by logs, fixture tests), with its PROVENANCE row.
- Evenings merged (49553d7, 1005f97): `build_evenings.py` rebuilds a CBS or NBC night from JJ's Washington Post radio grid (WRC for NBC, WJSV/WTOP for CBS; quarter-hour rows; Eastern time), fills a slot only with an episode of that night's own date (asserted where used), never a `no_recommend` one, makes an OCR collision a gap; `test_evenings.py` 39/39 with controls; `catalog/prototypes/tonight.json` for Oct 21-Nov 3 2026; `docs/research/evenings.md`. MEASURED: 1,180 evenings, 586 readable; coverage median 0, 61% nothing, p75 0.125, p90 0.25, max 0.56; late 1940s best, Sunday richest. Proposed floor 0.25 (every well-sampled anniversary date has a year above it). Floor and the gap's printed text are the owner's to confirm (scratchpad). On main: all 19 catalog suites pass. JJ's site has no robots.txt or terms; facts only, the page linked as witness.

### Tick 34, 2026-10-22, data + web: evenings published, the Radio tab
- Launched one agent for both halves: `tonight.json` as a pipeline output (served episodes only, a rolling window from yesterday through 13 days ahead, a published day never rewritten, the floor one provisional constant, wired into catalog-publish for /data/ and the Release) and the web Radio tab (the listener's own date, the one clock, Eastern air time as a fact, gaps as gaps, the evening ends). Pending the owner, a gap shows its time and a catalog-confirmed series name only, never the newspaper's OCR text. The transcripts-in-clients agent is still running. Machine: load 9.8 (the transcripts agent's build), no simulator.

### Tick 35, 2026-10-22, opt: the owner's questions in one list
- The scratchpad's six separate "for you" bullets (play, plays, loudness, evenings, palette with two questions folded in) became one numbered "Waiting on you" list, ordered by what each unblocks, every item pointing at its detail. 135 lines to 119.

### Tick 36, 2026-10-22, data: the rebuild had skipped three enrich steps
- Found while looking for Wikidata genres: the rebuild (mine and catalog-publish.yml) ran build_db and enrich_db only, so 13 tables the restored snapshot carries were silently absent (series_wikidata, episode_witnesses, episode_external, external_disagreements, art, external_meta, people_wikidata, people_art, people_art_meta, archive_photos, archive_photo_links, magazine_rights, magazine_scans). The publish workflow now runs enrich_external, enrich_people_art, and enrich_photo_archives after enrich_db (58f8fd9); the two art steps take `--db`. Verified on out/next: 28 tables, none missing; series_wikidata 573, art 2,281, people_art 3,876, archive_photos 34,141 (all equal to the snapshot), episode_external 39,028 (snapshot 38,993; the folds joined more episodes). No client reads these yet; images and Wikidata genres will.
- Transcripts in all three clients merged locally (fae3e48 Apple, 1f1d6b2 Android, a188ada web); verification on every client running.
- Transcripts in all three clients verified on main (my run): macOS 47/47 in 10 suites; iOS and tvOS builds; 0 compiler warnings; Android 54 tests, 0 skipped, 0 failures, 0 `w:` (fresh compile); web api tests 8/8, test_sw 46/46, test_web.sh green; nothing left running. The merge (8800427) had been concluded early by a log commit made while it was pending; it was amended to say so and held unpushed until these passed. 1.0.14 (15); PARITY transcripts row 🚧 on all five.

### Tick 37, 2026-10-22, M9: the stubs begin
- Android Build 39903777085 (the transcripts merge) passed in CI. Machine: load 4.1, no simulator.
- Launched the M9 stubs (Decision 056): Apple's CarPlay scene (four car tabs, R17; gated so the app runs without the not-yet-granted entitlement) and a watchOS target (Continue, waiting on the phone), the one Xcode build in flight; and the TV-web (webOS, Tizen) and Roku stubs, which need no Xcode or Gradle. Android's stubs (Auto library tree, Android TV, Wear OS) follow when the build slot frees. The evenings and Radio tab agent is still running.

### Tick 38, 2026-10-22, data: titles people can read
- Wikidata for genres: MEASURED, it reaches only 6 of the 8,518 genreless served series (161 episodes); not worth a rule. The genreless tail stays as it is.
- `catalog/tools/titles.py` `display_title`: undoes four upload habits found over 104,028 served titles (a file extension 181, underscores 99, track digits glued to a word 2,883, a title run together with no spaces 2,048), conservatively: a title that already reads as words is unchanged, a spaced leading number stays ("77 Sunset Strip"), Mc/Mac names stay whole, capitals never change. `build_projection` serves the display title and indexes both it and the raw upload name for search. `tests/test_titles.py` 14/14; two broken controls each fail (splitting titles that have spaces breaks "iPhone"; no Mc guard breaks "Fibber McGee"; the first control run reused cached bytecode and was rerun clean).
- After a rebuild: 0 extensions, underscores, glued digits, or run-together titles served; "ednawolfewantstogetnancyfowler" still finds "Edna Wolfe Wants To Get Nancy Fowler"; contract 42/42; all 20 catalog suites. Reaches every client through the data, no app release.

### Tick 39, 2026-10-22, M9: CarPlay and watchOS stubs merged
- Merged d741b4d: a CarPlay scene (an app delegate routes only the car's scene session to `CarPlaySceneDelegate`; a `CPTabBarTemplate` with the four R17 tabs; Continue lists in-progress episodes from the shared history and plays through the shared AudioPlayer to `CPNowPlayingTemplate`; the rest say "Not in the car yet"; no transcripts in the car) and an `EarDramaWatch` target (watchOS 11 floor; Continue, "Waiting on the phone"; shares only ListeningHistory; Design.swift left out, it does not compile on watchOS). `set_app_identity.py` handles the watch ids.
- Verified on main (my run): macOS 47/47; iOS, tvOS, and watchOS Simulator builds; 0 warnings; nothing left running. Not run anywhere: the car scene needs the entitlement, and whether the iPhone app still launches after the app-delegate change needs a device (first item in the owner's play note). 1.0.15 (16); PARITY §3c stubs table.

### Tick 40, 2026-10-22, opt: no-op
- Swept app code for template placeholders. `com.example.appname` package names are intended (set_app_identity leaves code packages alone). `APIClient.swift`'s FILL IN base URL, auth headers, and token refresh are M5's plug-in points, not dead code. The stale "FILL IN" comments in android `strings.xml` and the manifest's commented App Links block were left for after the Android stubs agent, which is editing those files now. Nothing else removable: a logged no-op (autonomous-loop-cadence: "If nothing is removable, log a no-op tick").

### Tick 41, 2026-10-22, M7: plays phase 1 on Apple
- Launched the Apple build of "pass the phone" (M7 phase 1), bound by docs/PLAYS-DESIGN.md: castable scripts, a cast screen, one role at a time with live AVSpeechSynthesizer stand-ins never written to disk, takes per line, a local AVAudioEngine mix, playback, delete; microphone permission only at recording. The owner's open plays questions take their most conservative reading, marked "pending owner" (C5 no previews, C6 an untaken role leaves the play unfinished, C7 strict relay, C9 not castable, C10 as published and no Personal Voice; phase 1 needs no sign-in). Android follows. Running alongside: Android stubs, TV-web and Roku stubs, evenings and the Radio tab. Machine: load 3.4, no simulator.

### Tick 42, 2026-10-22, M9: Android Auto, Android TV, and Wear OS stubs merged
- Merged 5e45975 (Auto: PlaybackService is a Media3 MediaLibraryService; `CarLibrary.kt` root of the four R17 tabs; Continue from the listening history, played through the phone's queue builder now shared as `takeQueue`; nothing plays at start), 8dca17e (TV / Fire TV: launcher entry, placeholder banner, leanback/touch/fingerprint not required, Listen focus on the first card, the media session kept on for TV-NP), 6ed0587 (a `:wear` module, Compose for Wear OS, minSdk 30, Continue "Waiting on the phone").
- Verified on main (my run, niced, alongside the plays agent's Xcode build): `--no-build-cache :app:assembleDebug :app:testDebugUnitTest :wear:assembleDebug` BUILD SUCCESSFUL, 0 `w:`, unit tests counted from the XML (below), the Wear APK built; daemons stopped. Only built on devices. 1.0.16 (17); PARITY §3c rows.
- Android unit tests on main: 63 tests, 0 skipped, 0 failures.
- TV-web and Roku stubs merged (f1925dd, c7f9a54): the webOS/Tizen layer now fits Ear Drama (Back walks the query-routed history and closes menus first, Tizen asks before exit, Up/Down stay in their column, remote media keys drive the player, dark palette forced, tv.css selectors re-targeted from Archive Watch's markup, packaged builds read https://eardrama.org/data/, the package script includes store.js and player.js and no longer corrupts config.xml, CSS shorthands 2022 Samsung sets cannot parse replaced); a Roku SceneGraph channel opening to Listen rows from the web projection. Verified on main: test_web.sh 23/23 (test_tv_focus 31/31, its 10 new cases fail against the old tv.js), api 8/8, US English, agent files; tv/dist and roku/dist gitignored, no package or certificate committed. Not installed on any TV. sw.js shell bumped; 1.0.17 (18); PARITY §3c rows; the Samsung author-certificate question added to the owner's list.

### Tick 43, 2026-10-22, upkeep: tick 40's deferred comments; the plan's checkboxes
- Android's `strings.xml` loses the template's FILL IN comment (the name is set); the manifest's commented App Links block now names eardrama.org and why it stays off (Play's signing fingerprint for assetlinks.json). Comments only.
- LOOP-PLAN: eight more items checked as built, each saying what is still open (evenings, the web player, transcripts, states, the Apple verbs and player, the Android verbs, the M9 stubs). Plays on Android waits for the Apple build so it can mirror its script format and words.

### Tick 44, 2026-10-22, docs: the four missing binding design docs
- Only WEB-DESIGN.md and PLAYS-DESIGN.md existed, though iOS, macOS, tvOS, and Android are far past AGENTS.md's ~5-view line. Launched a docs-only agent to write iOS-, macOS-, tvOS-, and ANDROID-DESIGN.md from the templates and the code as built, naming the deliberate inversions and listing what its reading finds inconsistent with R1-R21. Running alongside: plays on Apple, evenings and the Radio tab. Machine: load 3.4, no simulator.

### Tick 45, 2026-10-22, opt: the tick log rolled
- `AUTONOMOUS_PROGRESS.md` had reached 58 KB over 45 ticks; ticks 1-30 moved verbatim to `docs/progress/ticks-001-030.md` with a pointer (a script split both files on their `### Tick` headings and found every entry intact). The live log keeps ticks 31 onward.

### Tick 46, 2026-10-22, docs: four binding design docs, and a parity audit inside them
- Merged 16ee5eb: docs/iOS-DESIGN.md (with CarPlay and watchOS), macOS-DESIGN.md, tvOS-DESIGN.md, ANDROID-DESIGN.md (with Auto, TV, Wear), each in WEB-DESIGN's section order plus §11 deliberate inversions and §12 Open; no em dashes; US English and agent-file checks pass. Binding from now (binding-design-doc-discipline).
- Their §12 lists 35 inconsistencies found by reading the code: the queue rule differs on all three (an owner call, added to the scratchpad as item 9); player numbers differ (fade 10 s native vs 20 s web; speeds 0.75 vs 0.8 floor; save 5 s vs 10 s; resume rewind 3 s vs 5 s); tvOS has no way back to Now Playing, no versions picker, captions under 29 pt; the Mac's Play/Pause is bare Space (lost in the search field), no Go/Help menus, window close does not stop playback; Android's deep-link handlers still match the template's `appname` scheme, rights words hard-coded, no offline state on catalog screens; no haptics anywhere; no Queue/Following/Share on native Detail; R20's lock-screen step missing. These become the next fix round once the plays agent, which edits the same Apple code, is merged.

### Tick 47, 2026-10-22, decision + agent: one set of player numbers; Android and web parity round launched
- Decision 062 (eb8159c): 10 s sleep fade; speeds 0.75, 1, 1.25, 1.5, 2; save every 5 s and on pause; 3 s rewind on resume. Each is the value most platforms already used. The queue rule stays the owner's (scratchpad item 9).
- Launched an agent in a worktree to fix Android's §12 items (062 numbers, the `eardrama` deep-link scheme, published rights words, ISO dates, the transcript type level, "Played", offline states, TV focus on entry, decade filters from data, haptics) and 062 on the web (player.js, store.js, SHELL_VERSION). Apple's half waits for the plays agent, which edits the same code.
- Still running: plays phase 1 on Apple (verifying), evenings + web Radio (verifying). Machine: load 7.7, no simulators.

### Tick 48, 2026-10-23, merge + agents: plays phase 1 on Apple is on main; Apple parity round and the parser fix launched
- Merged 45bf90d (1.0.18 build 19): plays phase 1 on iPhone, iPad and Mac (cast sheet, relay, headphone check, room tone, line-by-line takes as FLAC, Listen Through, Export); 9 stage plays bundled. Verified on main: macOS `xcodebuild test` (unsigned) 60 tests in 16 suites pass; test_castable_scripts 4/4; US English passes. Each play's rights line quotes its source's own words with a link. Merely built, not verified: nothing has been recorded on a device (SCRATCHPAD item 11).
- PARITY: the plays rows now say 🚧 on iOS and macOS with what is missing.
- Found by reading the bundled file: all 9 plays carry front matter as speech (BOSTON, PRINTED BY, a publisher catalog making MORTON a castable part), Hamlet's first line is unclassified, and A Tender Attachment's opening dialogue is parsed as directions. A parser agent has the evidence; the bundle is replaced when it lands.
- Launched: Apple's half of the design-doc fixes (062 constants, tvOS Now Playing / versions / 29 pt captions, Mac menu commands and window close, haptics, Queue/Follow/Share). Android plays waits for the Android parity agent.
- Note: the macOS test needs CODE_SIGNING_ALLOWED=NO locally (no team set); the scheme is `EarDrama`, not `EarDrama_macOS`.

### Tick 49, 2026-10-23, merge: Tonight in 19xx in the data plane and on the web's Radio tab
- Three agents (Android/web parity, Apple parity, parser) stopped on the session limit overnight; resumed at 6:42 AM MT with their work intact.
- Merged 5fd3ffc (1.0.19 build 20): build_evenings publishes `tonight.json` (15-day window, a published day never rewritten except to withhold), the publish workflow restores and grows a facts-only `radiologs-latest` cache, and the web gains a fifth tab, Radio. Conflicts with the transcript work (api.js, api.test.js, sw.js, WEB-DESIGN) kept both sides; SHELL_VERSION ed-shell-v6.
- Verified on main: catalog run_all 21/21; js/api.test.js 10/10 with transcript, onAir and localDate; test_web ok; node --check on every js; workflow YAML parses; read the 375 px on-air screenshot (local and ET times, the slot on air marked, gaps as "Not surviving").
- Not verified: the publish run's new steps (dispatched: run 39955509726); Listen live switching between slots in a browser. With the web gate closed, the current window has 0 playable slots on the web (every surviving recording in it is unclaimed).

### Tick 50, 2026-10-23, merge + agent: Android and web parity round on main; Android plays launched
- Merged d494689 (1.0.20 build 21): Decision 062 on the web (player.js, speeds in index.html, new js/player.test.js run by test_web.sh) and Android (PlayerNumbers guarded against js/player.js); Android's `eardrama` deep-link parser (filters stay off until store records), published rights words, ISO dates, TypeLevelsTest over every source file, "Played", an offline line, TV focus on entry, decades from data, one Haptic mapping. player.js conflict kept both the Radio tab's startAt and the speed migration; SHELL_VERSION v7.
- Verified on main: Android 79 tests 0 failed, assembleDebug, 0 `w:`, no daemon; js/api.test.js 10/10; js/player.test.js 6/6; test_web no FAIL; US English. Not verified: TV D-pad focus (no device).
- PARITY: offline, OfflinePill and the sleep-timer row's 062 note updated.
- Launched Android plays phase 1 (mirrors Apple's format; also makes Android resume a saved position exactly, per 062). Running: Apple parity round, parser fix. Publish run 39955509726 still in progress at 4 min.

### Tick 51, 2026-10-23, merges: the Apple parity round and the stage-play parser; a publish-run fix
- Merged 04daca4 (1.0.21 build 22): the Apple parity round, docs first (5097278). Decision 062 in PlayerNumbers.swift; tvOS Now Playing from every tab, Versions on Detail, captions on the 29 pt floor (test_design_tokens fails under 29); the Mac's Play/Pause no longer eats Space in text fields, Go and Help menus, closing the window keeps playing (macOS-DESIGN 2.4, a written inversion); one iOS haptics mapping; Share as the https twin. New tools/test_apple_design_rules.py (7 rules, each with a negative control). Verified on main: macOS 70 tests / 20 suites, tvOS and iOS builds, 0 compiler warnings, tokens regenerate without drift. Not verified: no Mac key pressed, no TV screen seen.
- Merged df0db3b (1.0.22 build 23): the parser finds where the play begins and ends; front matter never becomes a part; full names expand frequent labels (Hamlet opens on BARN "Who's there?"); several plays or a mostly set-aside text is not clean. 11 plays bundled (Octavia and The Custom of the Country added). Verified: run_all 21/21, macOS tests with the new bundle. I sent back the B&F volume as a suspected multi-play text; the agent measured it as one play (one cast list, one Actus primus), which I confirmed in the cache. Open: it ships under the catalog title "Beaumont and Fletcher's Works, Vol. 01 of 10".
- Publish run 39955509726 failed at the new evenings step: `apt-get install poppler-utils` without `apt-get update` (mirror 404). Fixed in 869c7aa; redispatched as 39956803564.
- Running: Android plays phase 1.

### Tick 52, 2026-10-23, main thread + agents: the volume title fixed; Radio on Apple and plays on the web launched
- a5a66e1 (1.0.23 build 24): a collected-works record (Works / Volume / Vol. / Collection) shows the play its own text prints before the first speech, cased for a list and never reworded, with the volume kept as `collection`. gut-12039 now reads "The Custom of the Country". Two cases; three broken controls each failed (5/6); catalog run_all 21/21; US English. Apple's Codable decoding ignores the new key.
- Launched: the Radio tab (Tonight in 19xx) on iOS, macOS and tvOS, mirroring the web; plays phase 1 on the web, headphones only. Running: Android plays. M5 (Worker + sign-in) is next once an agent slot frees.
- Publish rerun 39956803564 still building at 7:00 AM MT (the first run failed at minute 5; this one is past it).

### Tick 53, 2026-10-23, agent + main thread: M5's Worker launched; the scratchpad brought current
- Launched M5's backend: a Worker + D1 ported from Archive Watch's worker/ (Apple and Google tokens verified at the Worker, sync with last-write-wins, account deletion, rate limits), local tests only; nothing deployed, no Cloudflare resource created, no secret copied.
- SCRATCHPAD's Current State said tick 25 at 1.0.8; rewritten to tick 53 at 1.0.23 with what is built and running.
- Running: Android plays, web plays, Radio on Apple, the Worker. Publish rerun 39956803564 still in the evenings step (it measures newspaper logs 3 s apart).

### Tick 54, 2026-10-23, merge + external check: Android plays on main; Tonight in 19xx published by CI
- Merged plays phase 1 on Android (1.0.24 build 25): ported from Apple's Core with the same files and keys; takes as 24-bit WAV; the device voice never written (a whole-play test with a leaky-microphone control); AAC mix; share-sheet Export; Plays tab hidden on TV; a saved position resumes exactly (062). Verified on main: 98 tests 0 failed, assembleDebug, 0 `w:`, the APK carries the 11-play bundle. Not verified: nothing recorded on a device.
- Publish rerun 39956803564 succeeded: catalog-latest/tonight.json (48,808 bytes, 15 days), radiologs-latest/radiologs.tar.xz (254 measured evenings), the web copy with 0 servable slots while the web gate is closed. Externally observed, so the evenings pipeline is verified in CI; the Radio tab itself is still unplayed.
- Apple has the same saved-position rewind drift; sent to the Radio-on-Apple agent, the only one in apple/.

### Tick 55, 2026-10-23, merge + agent: Radio on Apple; Radio on Android launched
- Merged 225ce6e (1.0.25 build 26): Tonight in 19xx on iOS, macOS and tvOS, docs first (e6d7ad1); RadioClock golden-checked against the web's onAir cases; the printed newspaper text never decoded; Listen live stops on pause, another episode, the sleep timer or the evening's end with nothing after; Apple now resumes a saved position exactly (062), test seen to fail against the old rewind. Verified on main: macOS 82 tests in 21 suites; tvOS and iOS builds; 0 warnings; design rules 7/7; tonight.json answers 200. Not verified: no screen seen.
- New owner item 12: six sections overflow an iOS 18 iPhone's tab bar (four and More).
- Launched Radio on Android (phone and TV). Running: web plays, the Worker.
- Opt tick note: tick 55 is an opt tick by cadence but carried a merge; the next quiet tick takes the cleanup (net-negative lines).

### Tick 56, 2026-10-23, opt: stale infrastructure notes removed (net -6 lines)
- Measured: push events start workflows again (Android Build on push at 13:10 and 13:14 UTC, both green); removed the scratchpad paragraph and the contract's parenthesis that said otherwise. www.eardrama.org still fails its certificate (curl 60); the apex answers 200. Scratchpad status now 1.0.25. 1f369cc: 13 insertions, 19 deletions.
- Running: Radio on Android, web plays, the Worker.

### Tick 57, 2026-10-23, merge + agent: M5's Worker on main; Apple sign-in launched
- Merged f3129d8 (1.0.26 build 27): the Worker + D1, Decision 063 written. Archive Watch's sign-in never reached its Worker, so the auth is new code under the same rules; ported only the shape, rate limits and deletion sweep. Verified on main: npm ci; 66/66 tests in workerd with a local D1; "all 11 mutations caught"; no secret in the diff (placeholders; test keys generated at run time). Worker Tests CI started on push (39960467550). Nothing deployed: the owner's eight setup steps are in docs/WORKER.md.
- Launched: sign-in and sync on Apple (Sign in with Apple everywhere, Google via ASWebAuthenticationSession with PKCE, no SDK; Keychain; single-flight refresh). Running: Radio on Android, web plays.

### Tick 58, 2026-10-23, merges + agents: plays on the web; Radio on Android; sign-in launched on Android and the web
- Merged 9fa674d (1.0.27 build 28): plays phase 1 on the web, headphones only (the person confirms them; a page cannot see the route); AudioWorklet capture, 24-bit WAV takes in IndexedDB via add(); OfflineAudioContext mix to WAV; the device voice never captured. PLAYS-DESIGN conflict kept both platforms (Android §4.5, web §4.6, the storage table per column). I added: smart-TV web hides the Plays tab (html.tv), WEB-DESIGN §4.10 says so; SHELL_VERSION v9. Verified on main: plays.test 161 checks, api 10, player 6, test_web no FAIL, US English. Not verified: a real microphone, iOS Safari.
- Merged 990fc8c (1.0.28 build 29): Radio on Android, phone and TV. Verified on main: 116 tests 0 failed (RadioTests 18), assembleDebug, 0 `w:`. Radio is now on all five core platforms (PARITY).
- Launched sign-in and sync on Android and on the web (with a public deletion page for Play). Running: Apple sign-in.

### Tick 59, 2026-10-23, main thread: store listing words drafted (M10)
- c4ff609: docs/store/LISTING-DRAFT.md, the App Store and Play text with each claim tied to a decision or PARITY row, lengths measured (subtitle 27/30, promotional 151/170, keywords 97/100, Play short 80/80). Caught while drafting: "eighty years ago" was wrong for 1944 (82), and "1940s radio" was wrong for 5 of the 15 published evenings (tonight.json: ten 1940s, three 1950s, two 1930s); the line now names neither. Owner item 13.
- Running: sign-in on Apple, Android and the web.

### Tick 60, 2026-10-23, owner ruling + merge: the palette is On Air; sign-in on the web
- Owner, mid-tick: "I really like the On Air colors and I think we should be building with those in mind." 04c2578 (1.0.29 build 30): Decision 064; design-tokens.json to On Air plus `secondary`, `onSecondary`, `link`; all 14 token files regenerated; test_design_tokens.mjs checks the new pairs (seen to fail on a light link at 1.72:1). Verified: web read at a true 375 px, light and dark; macOS and Android builds, 0 warnings. Memory saved; SCRATCHPAD item 1 closed.
- Instrument lesson: headless Chrome's --window-size=375 crops a wider layout; I almost fixed a tab bar that fit. Measured in a 375 px iframe (scrollWidth 375). Memory saved.
- Merged 875c8bf (1.0.30 build 31): web sign-in and sync, delete-account/ page. Added on merge: the privacy page's false lines (no accounts, no third-party scripts) corrected and the new storage listed, owner review marked; Delete links in every footer; SHELL_VERSION v11, because 04c2578 changed styles.css without a bump. Verified: account 11, api 10, player 6, plays 161, test_web clean.
- Next: genre hues (`color.genre`) and moving links/focus/selected tab to blue on every client, after Apple and Android sign-in merge. Running: sign-in on Apple and Android.

### Tick 61, 2026-10-23, merge + agent: sign-in on Apple; On Air's roles and genre hues launched
- Merged dd6a4e1 (1.0.31 build 32): sign-in and sync on iOS, macOS, tvOS (Library's last row; Apple everywhere; Google on iOS/macOS via ASWebAuthenticationSession + PKCE; tvOS Google ⏳). Changed on merge: the Sign in with Apple entitlement stays OFF in project.yml until the owner enables the capability, since a signed build naming it fails first (would have broken the cloud archive); WORKER.md step 4 says when to switch it on. Verified on main: macOS 94 tests / 22 suites; tvOS and iOS builds, 0 compiler warnings (two CoreData runtime log lines in xctest, not compiler output); design rules 7/7.
- Launched: On Air's genre hues as a `color.genre` token group with a 3:1 check, and red-for-live / blue-for-wayfinding on web and Apple. Running: Android sign-in.

### Tick 62, 2026-10-23, merge + main thread: sign-in on Android; M5 built on all five
- Merged c592e22 (1.0.32 build 33): Android sign-in and sync (Credential Manager for Google; a Custom Tab for Apple; Keystore-encrypted session). Added on merge: auth/apple/index.html, the https page Apple returns to on Android, forwarding the fragment to eardrama://oauth/apple and clearing it from the address bar; sw.js bypasses /auth/ (v12). Verified on main: 131 tests 0 failed 0 skipped, assembleDebug, 0 `w:`; test_web.
- LOOP-PLAN M5's three items checked as BUILT (not verified: nothing deployed, no real sign-in); the Needs Ben OAuth row now names Android's two clients and the entitlement switch.
- Running: On Air roles and genre hues (web, Apple). Next: the same on Android; M6 Listen Together.

### Tick 63, 2026-10-23, agent: Android parity round two
- Launched: Android's ANDROID-DESIGN §12 items with known answers (Detail's sponsor and order, the network facet and sort, route de-duplication, Following and Share verbs, TV focus on pushed screens; the Play deletion line closed since delete-account/ exists). No Queue verb (owner, item 9), no color or icon changes (the On Air agent owns those).
- CI: Android Build on push green twice since the last merge; Design Tokens green. Running: On Air roles (web, Apple), Listen Together rooms (Worker), Android round two.

### Tick 64, 2026-10-23, merge: On Air's roles and genre hues on the web and Apple
- Merged 6ca4f64 (1.0.33 build 34): color.genre tokens for every platform (checked against catalog GENRES and at 3:1 on every ground, lowest 3.19:1); red for what is live, blue for wayfinding, a genre mark on series rows; docs first. On merge: SHELL_VERSION v13 (both sides had made v12 independently, which would have shipped the merge without a cache bump); Decision 064 now counts Start recording as live (owner may overrule).
- Verified: tokens and contrast; test_web; Apple design rules; screenshots read at 375 in light and dark. The agent's blank Listen at 375 measured as a timing artifact (the view renders in the frame under three entry URLs). Not looked at: the Apple screens (no simulator; the branch's macOS 94 tests and iOS/tvOS/watch builds passed, and main's Apple code had not changed since its base).
- Android's roles wait for the Android round-two agent. Running: Android round two, Listen Together rooms.

### Tick 65, 2026-10-23, opt + merge: harnesses point at Ear Drama's tabs; Listen Together rooms on the Worker
- Opt 4b0fc4c (net -7 lines): every device runner expected the template's "Home"/"Settings"; scenarios now open listen/search and return to Listen, the anchor is the tab labels, FILL IN paragraphs cut to one line each, qa_suite SMOKE renamed. Ran the web sweep (no device needed): OK once, then red three times in different places; measured in a 375 px frame the app opens ?item= correctly, so the instability is the harness's. A per-shot Chrome profile is kept; a real-time --timeout made it worse and was reverted. Recorded as a KNOWN DEFECT in web_run.py: instrument the stages before trusting it.
- Merged 317d71d (1.0.34 build 35): Listen Together rooms (Archive Watch's D1-polled rooms, ported; six-character codes, hashed per-member keys, host handoff, hourly sweep). Decision 065: rooms need no account (057's text checked). Verified on main: 108/108 tests, "all 35 mutations caught".
- Launched: Listen Together on the web (rooms) and on Apple (SharePlay, same message shapes). Running: Android round two.

### Tick 66, 2026-10-23, merge + agent: Android parity round two; Android On Air and Listen Together launched
- Merged 0403a33 (1.0.35 build 36): no duplicate screens on a tab's stack; the web's sorts and a network facet sharing one filter clause; Follow / Following on the synced store; Detail in the web's order; Share as the https twin (golden-checked against node's encodeURIComponent); TV focus on pushed screens. Verified on main: 145 tests 0 failed 0 skipped; assembleDebug; 0 `w:`. PARITY's Series and Share rows updated.
- Launched one Android agent for two commits: On Air's roles (red live, blue wayfinding, genre marks), then Listen Together rooms. Running: web rooms, Apple SharePlay.

### Tick 67, 2026-10-23, main thread + agent: the web harness defect measured
- Instrumented the stage instead of rerunning: five --dump-dom loads of ?item= with fresh profiles gave the episode 3 times, an empty episode view once, no view once. The capture fires at a fixed virtual time, sometimes before the shard fetch completes. Recorded in web_run.py.
- Launched a tools-only agent: drive Chrome over the DevTools protocol (no new dependencies), set a real 375 px viewport, wait for the route's text, then capture; prove with five green sweeps and a negative control.
- Running: Android (On Air + rooms), web rooms, Apple SharePlay.

### Tick 68, 2026-10-23, CI check + quiet tick: the owner is on a call
- Step 0 (new, owner's request): CI green since the last tick (Android Build, Worker Tests, Design Tokens); a catalog publish in progress. Last 300 runs: two failures, both understood (10/22 Pages: Jekyll on "YYYY-MM-DD", fixed by .nojekyll; this morning's publish, fixed in 869c7aa); 22 Pages runs cancelled by newer pushes, likely the alerts. Step 0 is in LOOP-PLAN; memory saved.
- Load 19 with zoom.us and coreaudiod near the top: the owner is on a call, so no new build agent this tick. Scratchpad status brought to tick 68 at 1.0.35.
- Running: Android (On Air + rooms), web rooms, SharePlay, web harness fix.
