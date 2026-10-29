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

### Tick 69, 2026-10-23, quiet: the owner is still on a call
- CI green; catalog publish 39969504195 in progress. Load 12 with zoom.us running: no new build agent. SharePlay sent back for a deterministic host tie-break (two simultaneous starters both believed they were host); merge after it returns. Running: SharePlay fix, Android (On Air + rooms), web rooms, web harness fix.

### Tick 70, 2026-10-23, merge: Listen Together over SharePlay
- Merged 94565c8 (1.0.36 build 37): SharePlay on iOS, macOS, tvOS porting room-protocol.js (golden-checked; --check matches main's). Sent back once for a real bug: two simultaneous starters both became host; now the lower participant id wins on every device (test seen to fail inverted). Not rebuilt on main while the owner is on a call: main's Apple code had not changed since the branch's base (checked with git log), so the branch's macOS 106 tests and iOS/tvOS/watch builds stand. Not run on devices.
- The first merge attempt silently did not happen (no MERGE_HEAD; a momentary git lock, as at tick 67's commit); caught because the golden check could not find its file. Lesson: confirm MERGE_HEAD after every merge command before checking the tree.
- Needs Ben: one row for both Apple capabilities (Sign in with Apple, Group Activities) and the entitlement switch.

### Tick 71, 2026-10-23, merge: the web harness waits for the screen
- Merged 8c4c14e: web_run.py drives Chrome over the DevTools protocol (fresh profile, true 375x812 viewport, wait for each route's own ready text, then capture; a timeout grades `ready` FAIL rather than shooting blind). A second cause found by the agent: http.server's backlog of 5 dropped connections when the app loads ~16 scripts at once; `loads_complete` now catches it, and tools/devserve.py's backlog is 128. Verified: five agent sweeps OK plus a red negative control; two more sweeps OK on main.
- Conflict with my tick-67 defect note taken from the branch. A headless Chrome on port 9333 in this session's scratchpad belongs to another agent; left running.
- To upstream to UniversalAppTemplate (PROVENANCE): the DevTools-wait capture, the devserve backlog, and the 375 px window-floor lesson. Queued for the next opt tick.

### Tick 72, 2026-10-23, merge + agent: Listen Together on the web; M8's Worker side launched
- Merged c413fb4 (1.0.37 build 38): web Listen Together (Worker rooms; ?room= link that still needs a tap; client drift math checked against room-protocol.js on 1,000+ cases; guests follow, never drive). Verified on main: together.test 19, player 7, api 10, account 11; test_web; read the host sheet at 375. Listen Together now built on web, iOS, macOS, tvOS; Android in progress.
- Launched M8's server side (invite-link productions, part claims by relay order, per-line takes, report/block/filter, CC0 consent recorded by version id with the words left OWNER, the archive.org upload as a queued record only, classes with an under-13 consent gate). Worker only, light, local.
- Running: Android (On Air + rooms), M8 Worker.

### Tick 73, 2026-10-23, merge: On Air and Listen Together on Android; M6 built on all five
- Merged 98ab771 (1.0.38 build 39): Android's color roles (the theme's primary is blue so Material defaults follow; red only via OnAir.colors.live; the record button off the error color, per 012; genre marks; ColorRolesTest) and Listen Together (RoomProtocol.kt golden-checked against room-protocol.js, pinned by its SHA-256). DEEP_LINKS conflict combined into one row. Verified on main: 162 tests 0 failed; assembleDebug; 0 `w:`.
- On Air (064) now applied on all five platforms; Listen Together (M6) built on all five; LOOP-PLAN M6 checked as built. Told the M8 agent not to touch room-protocol.js (both native goldens pin it).
- Running: M8 Worker.

### Tick 74, 2026-10-23, CI check + upstream: the web capture fix reaches the template
- CI green (Android Build, Design Tokens; the catalog publish from 14:25 UTC succeeded). Owner still on a call: light work only.
- UniversalAppTemplate 7abb441f (pushed): web_run.py's DevTools-wait capture with a true 375 px viewport, `ready` and `loads_complete` grading, routes kept as FILL IN placeholders with a ready field; devserve.py's backlog 128; DEVICE-HARNESSES Web rules; a PROVENANCE row. The template had both defects. test_web clean, US English.
- Running: M8 Worker.

### Tick 75, 2026-10-23, main thread: M7's learning test, as built
- Ran learning-orientation-design against plays phase 1 as shipped (efb0807, PLAYS-DESIGN §1). Understanding, participation, clarity hold. Agency holds, with one defect read from the code: a bleed-flagged take (RecordingSession keeps it, RecordingScreen warns) still counts in Relay.isComplete and can be mixed, against §8 rule 3 (a synthetic voice is never part of a mix) and §5 rule 2.
- Launched the repair on Apple, Android and the web (a flagged take never completes a line; the mix refuses it; the take stays on disk), builds one at a time while the owner is on a call. CI green. Running: M8 Worker, the bleed fix.

### Tick 76, 2026-10-23, quiet + agent: the human-shaped review (M10) launched
- CI green; the owner still on a call. Launched a read-only human-shaped-review pass (words on screen, AI copy, side doors, automation that takes a judgment away, what a child or teacher meets in plays, pushed sign-in, autoplay), findings into HUMAN-SHAPED.md only, fix-now vs owner's call. Running: M8 Worker, bleed fix, review.

### Tick 77, 2026-10-23, merges + main thread: the human-shaped review; the bleed fix; the rights line's year
- Merged 43891cb: HUMAN-SHAPED.md, the owner's answers left blank (the skill forbids drafting them), the agent's notes marked as AI-written. Six fix-now findings, seven owner's calls (SCRATCHPAD item 14).
- b003138 (main thread): "Published before 1926" was a literal that goes false on January 1, 2027 (the rule frees through year - 101). rights_lines(today) builds it from the same function. My first test could not fail in 2026 (the literal equals this year's value); rewritten to ask for 2027's line, then seen to fail with the literal (44/45). run_all 21/21.
- Merged f045f77 (1.0.39 build 40): a bleed-flagged take never completes a line or reaches a mix, on Apple, Android, and the web (each rule break seen red). Not rebuilt on main during the call: the branch was based after every native merge (checked with merge-base).
- Launched: privacy page for the apps and rooms, explaining captions cut, credits for the tools and the agent. Remaining fix-now: Listen shelves following three rules (Decision 058 wants them from published data). Running: M8 Worker, the review fixes.

### Tick 78, 2026-10-23, agent: Listen shelves into the data plane
- CI green (Android Build 15:07 UTC). Launched the data-plane half of review finding 6: a published `listenShelves` rule list (onThisDay, then genreFirsts per genre) plus precomputed ids where the date does not matter; "Most episodes" excluded pending the owner (HUMAN-SHAPED.md B). Clients switch once the review-fixes agent leaves apple/ and android/. Running: M8 Worker, review fixes, shelves.

### Tick 79, 2026-10-23, merge + a break I caused: review fixes on main; Apple's rights test repaired
- Merged 0751b16 (1.0.40 build 41): privacy covers the apps and rooms (owner review marked), explaining captions cut on Apple and Android, credits name the tools and Claude Code (the OWNER note left open).
- My b003138 (tick 77) broke Apple's RightsDisplayTests.fallbackMatchesThePipeline, which reads build_projection.py for literal strings; I had run only catalog run_all. Repaired in the same commit (the published-age key checks the pattern and the fallback's words); macOS 107 tests in 24 suites pass on main. Memory saved: grep client tests for a pipeline file before committing.
- Review fix-now items left: Listen shelves (data plane in progress). Running: M8 Worker, shelves.

### Tick 80, 2026-10-23, merges: plays phase 2 on the Worker; Listen shelves in the data plane
- Merged 8e9c1cd: plays phase 2 on the Worker (Decision 066): invite-only productions checked against a castable manifest, relay rules in a pure module, immutable R2 takes behind the owner's switch, report/block/name filter, consent by version id, a queued archive.org job, classes with an under-13 gate. Verified on main: 171/171, "all 96 mutations caught". Owner items P1-P8 in PLAYS-DESIGN §11.6.
- Merged a238f8b: listenShelves published by both builders (onThisDay by rule with golden cases; genreFirsts with ids; "Most episodes" excluded pending the owner). Changed on merge: real-artifact checks skip a local build made before the key, strict when named. Following the new rule, ran the macOS suite after the pipeline change: 107 pass. Catalog 22/22.
- Launched: the three clients read the published shelves (one platform at a time). CI green; a loudness run in progress.

### Tick 81, 2026-10-23, plan + agent: M7/M8 marked honestly; the radio-script parser
- LOOP-PLAN: a `[~]` mark for built-in-part items with what is missing; M7's corpus (no radio script clean yet) and learning test (owner's play open) and M8's Worker-side items marked so; M7's recording item checked as built.
- Launched: the radio path of script_parse.py measured over every cached radio text and fixed by general rules, never loosening the 5% gate or a rights rule; GRW scripts never shipped (owner item C8); the Worker's castable manifest regenerated if the bundle changes.
- CI green; a loudness run in progress. Running: shelves on the clients, radio parser.

### Tick 82-83, 2026-10-23, merge + main thread: shelves on every client; front matter kept off them
- Merged d7b32b1 (1.0.41 build 42): web, Apple, Android draw the published listenShelves (same order and titles; "Most episodes" removed from the web; Android's date query had matched malformed dates, fixed).
- Read the 375 px screenshot: the Drama shelf opened on three "Dramatis Personae" cast lists. 1f8b670 (main thread): genreFirsts skips front matter by title (start-anchored, plus a collection's closing "Introduction"), never a section that also carries an act or chapter; 219 skipped on the real projection; the clean Drama shelf opens on "001 - Inferno I". Each guard broken once, red. run_all 22/22.
- Verification slip caught: my macOS runs after the shelves merge said 107 tests; the merge added ListenShelvesTests, which a stale generated project left out. After xcodegen: 111 pass. Memory saved.
- Running: radio parser. CI green; loudness run in progress since 15:13 UTC.

### Tick 84, 2026-10-23, merge: radio plays ship
- Merged b947614 (1.0.42 build 43): the radio parser reads the forms radio scripts use; all four Carlton radio plays parse clean (0% unclassified) and ship, so the bundle holds 15 scripts; GRW clean 827 -> 950 but never shipped (C8). Checked the radio plays' parts and the clients' decoders (mic and sound parts already handled). Verified on main against every reader of the bundle: catalog 22/22, worker 171, web 194, macOS 111 (after xcodegen), Android 167.
- LOOP-PLAN M7's corpus item checked. No agent running.

### Tick 85, 2026-10-23, agents: M8's clients on the web and Apple
- CI green (Worker Tests and Android Build at 15:45 UTC); the loudness run is long by design (in progress since 15:13). Launched M8's Apple client alongside the web one (invite links through the deep-link inbox, relay claims, uploads with every refusal path shown as one plain line, report/block, the consent step showing the Worker's OWNER placeholder, classes with the under-13 refusal). Android follows. The owner is still on a call: builds one at a time.

### Tick 86, 2026-10-27, main thread: the crash on play fixed (1.0.68); the loop resumed
- Owner: "many times attempting to play an ear drama results in an app crash." Reproduced on the iPhone 12 (1.0.67 Debug, muted autoplay, SIGTRAP at 40 s). Crash log: `_dispatch_assert_queue_fail` in AudioPlayer.mediaArtwork's closure, called from MPNowPlayingInfoCenter's accessQueue; MainActor default isolation made the artwork handler main-actor. Fix: @Sendable handler from a nonisolated func; the KVO and NWPathMonitor handlers @Sendable too. After: four varied episodes 45 s each, no crash log, frames show the clock moving; Release 1.0.68 launches; macOS and tvOS clean; Apple 164 tests pass. Shipped: App Store build run 40583842946.
- Launched: an iPhone 12 device sweep (every iOS surface, muted, fix what crashes) and offline/error states on the platforms still ⏳. Verified: the play crash fix on device. Not verified: audible playback, anything on the owner's own phone.

### Tick 87, 2026-10-27, merge: offline and error states everywhere (1.0.69)
- CI green; the 1.0.68 App Store build succeeded (run 40583842946, 11m42s).
- Merged d8c370c: "You are offline." on web, iOS, macOS, tvOS, Android from one rule per stack (Apple `Connectivity`, web `API.offlineLine`, Android `offlineLine()`); an episode that fails for want of network says so instead of "would not play"; APP_FORCE_OFFLINE door on Apple and Android, `?offline=1` on the web. Verified on main: macOS 167 tests in 38 suites, web 0 FAIL, Android 232/0 and 0 `w:`, design rules 8/8, US English. Not verified: any device; Detail offline shows both the old warning and the new line (owner's call).
- Running: the iPhone 12 sweep. TestFlight held until it merges, so one build carries both.

### Tick 88, 2026-10-27, merge: the iPhone 12 sweep (1.0.70 to TestFlight)
- CI green. Merged 4e3b3fa: no new crash across every tab, series, Detail, person, Search, the player (taps through XCUITest: skip, seek, speed, pause/play, sleep set and off, leveling, close), a 3.6-minute muted run, a download played from the file and removed, and offline; the off-main closure audit found nothing else. Fixed: Play glyphs drawn blue beside red labels (Detail, Surprise, Listen Through, Listen live; Decision 064 makes Play red), the Detail download row several rows tall. Conflict on APP_FORCE_OFFLINE (both branches added it): main's kept.
- Verified on main: macOS 167 tests in 38 suites, tvOS and iOS Release clean, design rules 8/8; Release 1.0.70 launches on the iPhone 12, crash logs unchanged. Not reached: next story at an arc's end, up next with a queue, Browse filter taps, Downloads place, versions. Not verified: anything audible.
- Harness defect logged: ios_run's app anchor regex wants tab-bar text, so player-sheet runs FAIL on correct frames.

### Tick 89, 2026-10-27, merge: queue verbs on Apple and Android (1.0.71)
- CI green; the 1.0.70 App Store build succeeded (run 40592132876).
- Merged b1b72e7 (Sonnet port of the web): add to the end (a queued episode moves to the end), remove, move up/down, drag on iOS/Mac; Detail button, row context menus, a Library Queue section on every Apple platform and Android; Mac Controls menu; Android rebuilds the Media3 tail on a queue change. What plays next unchanged (Decision 067). Verified on main: macOS 173 tests in 39 suites, tvOS clean, Android 238/0 and 0 `w:`, design rules, US English. Not verified: any gesture on a device.
- The iPhone 12 is lent to the Archive Watch session for one XCUITest; TestFlight waits for a device tap of the queue.

### Tick 90, 2026-10-27, main thread: the queue on the iPhone 12; 1.0.71 to TestFlight
- The iPhone 12 was lent to the Archive Watch session for its XCUITest (its lease lapsed mid-run; it apologized), then returned.
- XCUITest on the phone (local harness in a scratch worktree, under a devlease): Detail "Add to queue" to "In queue" on two episodes, Library's Queue section in added order, long-press Move down reorders, swipe Remove empties it and the section goes. Player "Next:" showed a serial's next part (Johnny Dollar Ep 4) ahead of the queue's head: correct by Decision 067; my assertion was wrong. Release 1.0.71 launches; crash logs unchanged (two, both 1.0.67 or older).
- Shipped: App Store build for 1.0.71 (build 72).

### Tick 91, 2026-10-27, merge: the iOS tap tier (1.0.72)
- CI green; the 1.0.71 App Store build succeeded (run 40603303302).
- Merged 4928443: `EarDramaUITests` (iOS only, own scheme): player verbs, queue add/reorder/remove, download/play-from-file/remove, a smoke test per section; each restores what it changes. `tools/ios_uitest.py` leases "iphone", exports frames, fails on a new crash log, verifies teardown. `IOS_ANCHOR_RX` (calibrated on real frames; Springboard is the negative control) so player-sheet runs no longer FAIL on correct frames.
- Verified on main: `python3 tools/ios_uitest.py` 9/9 PASS in one run on the iPhone 12, no new crash log, left as found; frames read (download played from the file). macOS 173 tests; test_ios_anchor ok.
- Lease naming: we and Archive Watch had leased the phone as "iphone12"; the bench name is "iphone" (memory saved, peer told).

### Tick 92, 2026-10-27, merge + main thread: links to the site pages; VBR MP3 timing (1.0.73)
- Merged 122e0f0: Credits, Privacy, Take-down requests in Library on iOS (Mac already had them in Help), plain addresses on tvOS, Custom Tabs on Android; tap tests for Browse, the Downloads place, versions, a person.
- An agent called a player failure after a seek a "stream flake". Measured instead: many archive VBR MP3s have no Xing/Info/VBRI table (Gang Busters 1954-08-02: first frame 32 kbps, file averages 85), so AVFoundation read 23:42 as about an hour and seeks past the real end froze the clock. Fix: `AVURLAssetPreferPreciseDurationAndTimingKey` (length now 24:27; start still 0.1 s); a saved place past the catalog length starts over (ResumePositionTests, seen red); `APP_PLAYBACK_DIAG` (DEBUG) draws the engine state and a failure's errors on the player; SeekUITests. The intermittent freezes (3 of 6 tests before the diagnostic build) have not recurred in 10 since; their cause is not proven. X Minus One's one "would not play" has not reproduced.
- Verified on main: macOS 176 tests in 40 suites, tvOS clean, iOS tap tier 16/16 in one run, no new crash log; Release 1.0.73 launches. Shipped to TestFlight.
- Held, not merged: Android's port (2556eb4). No Media3 flag fixes a headerless VBR file up front, so it wraps Mp3Extractor with a catalog-length seek map and rebased timestamps, tested only with a fake extractor; it needs a real-device seek check first. The web's `<audio>` likely has the same exposure, unmeasured.

### Tick 93, 2026-10-27, merge: Android VBR timing, device-checked on the Pixel 8a (1.0.74)
- Merged 2556eb4 after a real-device check on the Pixel 8a (muted, devlease "pixel"): Gang Busters 1954-08-02 shows 23:41 (not ~1 h); seeks to ~50% and ~80% keep the clock moving (12:12 to 12:19; 19:05 to 19:12, frame read); X Minus One control the same; logcat clean. Android 246/0, 0 `w:` on main. Not verified: that a seek lands on the matching scene (needs ears). No Play build (a version is in review).
- Running: the 1.0.73 App Store build.

### Tick 94, 2026-10-27, merge: the web and headerless VBR (1.0.75)
- Merged 0e3018d. Measured in headless Chrome (real timers): Gang Busters `duration` 1413.5 s against the catalog's 1421.6 (0.6%), X Minus One exact; seeks to 50% and 80% advance 5.00 s in 5 s, no error or stall. So the web needed only the resume rule: a saved place at or past 95% of the catalog length starts over (player.test.js, seen red twice). Web 0 FAIL on main. Not measured: Safari and iOS web.

### Tick 95, 2026-10-27, merge: the sponsor, computed once (1.0.77)
- Owner, after two idle ticks: "Wait, why are we looping with no new content." Loop stopped; memory saved; then "All that don't need me": transcript and date search (running), sponsors.
- Merged 138471a: `catalog/tools/sponsors.py` picks the OTRRpedia dated run covering an episode's air date (an open run lasts until the series' next run; Sustained, Multi, Syndicated never published; none when uncovered); `episodes.sponsor` in the projection and `sponsor` in the web detail shard. Apple and Android already drew the column when present. 14,265 of 121,907 episodes get one. Main-thread fix: test_projection's real-artifact check skips a local build that predates the column (strict under PROJECTION). Verified on main: catalog 27/27, macOS 176, web 0 FAIL, Android unit tests. Not verified: any client showing it from a published catalog (next publish); none of the clean-only web episodes has a run.

### Tick 96, 2026-10-27, merge: Search by what is said and by air date (1.0.78, not on TestFlight)
- Merged 23ff9c3: transcript words (gated by Decision 058 only) in Search as "Automatic transcript" with a verbatim line cut on the device from archive.org's own text (catalog DECISIONS 012; shipping snippets measured at 11-30 MB gzip, refused), and an "Aired {date}" section for dates ("1954", "August 1954", "8/2/1954"), on all five platforms; the web gets `search/said/` (4.7 MB gzip with the gate open) and `search/dates/`. Conflict: CATALOG-CONTRACT's episodes table. Main-thread fix: test_web_projection's real-build checks skip a local build that predates the new files (strict under WEB_PROJECTION).
- Verified on main: catalog 27/27, macOS 178 tests in 40 suites, tvOS clean, web 0 FAIL, Android 249/0 and 0 `w:`, design rules, US English. Web 375 px frame read ("zeppelin": four transcript lines).
- Not verified on the iPhone: SearchUITests passed, but its frame shows iOS Screen Time's "Time Limit" screen over Ear Drama (9:35 PM); a pass with that screen up proves nothing. Not tapped through (the owner's setting). TestFlight held until a clean device run and the Release launch check.
- Harness defect: ios_uitest grades XCTest's verdict only; it must fail a frame showing Screen Time's Time Limit (or any system overlay).

### Tick 97, 2026-10-28, device check and ship: 1.0.78 on the iPhone 12
- Owner: "I don't believe the arhcive watch session is still using the iphone 12. Why didn't you check for that when you established the 90 minutes?" and "You are claiming things without verification all over the place". Both claims I had relayed were false: Archive Watch's lease ran 7:17 to 8:47 AM and its pid was gone when its message arrived at 10:08; the Screen Time limit was gone. Memories saved (check the lease file and pid before relaying a peer's claim; look at a frame before claiming a device state).
- Verified on the iPhone 12 (lease "iphone"): SearchUITests "gangbusters august 1954" draws "Aired August 1954" with 1954-08-02 and 1954-08-09 (frame read). Full tap tier 17/17 in one run, no new crash log, left as found; all 34 frames read, no system overlay. Release 1.0.78 installed, alive after 20 s on Home (frame read), crash logs 2 before and after, terminate verified.
- First run of SearchUITests FAILED: "The process identifier of the launched application could not be determined"; the video shows the app icon still "Waiting..." (installing) at launch. Likely cause, not proven: the phone held a TestFlight build (Archive Watch: "Ear Drama 1.0.70 stays installed"), and replacing it is a slow install. Harness defect: ios_uitest should confirm the install finished before tests start. The rerun passed.
- Not verified on the device: the "Automatic transcript" section (no tap test types a phrase; the web frame is the only evidence).
- Catalog publish run (10:16 AM MT) is the first with the new outputs; live manifest: saidDocs 6,581, saidFiles 834, dateYears 53; search/said/ze and search/dates/1954 return 200.
- Seen in the Browse A-Z frame: several "01 30 Adolf Hitler Rede..." speech recordings sort near the top. A content call for the owner, not changed.
- Shipped: App Store build for 1.0.78 (run 40727877211, success): three uploads succeeded (10:42, 10:45, 10:48 AM MT), not submitted for review (no What's New). Not checked: App Store Connect processing (the local ASC client lacks `jwt`).

### Tick 98, 2026-10-28, main thread: racist caricature is never recommended (1.0.80)
- Owner: "If we don't yet have flags for offensive materials we need to implement them. Archive watch has multiple different flags for racist materials that allow them to be searched for but never recommended on the surfaces we want users to leverage for discovery."
- Found: `no_recommend` existed (every choosing surface on every client already skips it, with tests), but only for Nazi speeches, and that rule missed 87 of the regime's own recordings. Built catalog DECISIONS 013: `build_db.no_recommend_reason` (Nazi speaker-led titles and German compounds; archive.org's own `deemphasize` collection; `editorial/racist_caricature.json`, six sourced patterns, each Wikipedia source fetched and read for the claim, plus four `not` exemptions with reasons). archive.org subject tags measured and refused (they mark programs ABOUT racism).
- Verified: test_no_recommend 32/32, seen red four ways (a name-led title rule flags "Hitler's Secret Army in America"; skipping `not`; ignoring deemphasize; a loosened minstrel pattern flags "Minstrel Boy" and The New Christy Minstrels; Beulah read on titles). All 27 catalog suites. A scratch rebuild against a baseline rebuild of HEAD from the same caches: the same 155,608 episodes, states and titles; only no_recommend differs (1,137 rows): racist caricature 1,012, Nazi-state 184 (was 97), archive.org deemphasize 5.
- Not verified: any client showing the change (next catalog publish); the clients need no code change (they read the flag).
- Left for the owner (DECISIONS 013): Charlie Chan; Frank Watanabe; the Goon Show parody (exempted); Jungle Jim wartime slurs; coon songs and "darkies" record titles; Blue Coal Minstrels; Al Jolson's "Mammy"; guest spots by the Amos 'n' Andy act are flagged.

### Tick 99, 2026-10-28, merges P1-P5 and the harness (1.0.82)
- Owner: "Yes, please start the loop with that order and make sure you are proactively looking for things to fix and design as you go through this loop." LOOP-PLAN now carries P1-P8; AGENT-BRIEF asks every agent for "Seen on the way".
- P1 (audit): PARITY honest against main; ~42 cells changed, 7 rows added; ✅ only with named device evidence (10 demoted, 7 iOS rows promoted on the 2026-10-28 tap tier).
- P2 (harness, main thread): build, install, ask the device which build it holds, then test-without-building; every frame OCR'd, a system overlay fails its test, an unreadable frame fails as blind (test_ios_overlay, seen red both ways; 35 real frames: the Time Limit frame caught, none blind). It did NOT cure the first-launch failure: LOOP-PLAN P8 (the app opens and is gone ~3 s later, no crash log, each time the first launch after a publish or install).
- P3 (Follow): Apple's Follow/Following button, Following on Home and in Library on iOS, macOS, tvOS; Android's Home Following shelf and haptic. FollowUITests on the iPhone 12: FAILED first (the test: Following sits under ten Continue rows off screen, and the tap hit a Continue episode); test fixed (scroll, series row by label), PASSED, frames read (Following on Home, gone after unfollow).
- P4 (empty states): one EmptyState per platform with at most one action; Library's empty state no longer hides Account and the site pages (Apple, tvOS, Android); no hints anywhere (each candidate repeated a visible control; HintBanner 🚫 with the reason). EmptyStateUITests 2/2 on the iPhone, frames read; the door now also hides Following.
- P5 (Top Shelf): extension and App Group snapshot built and unit-tested; merged with the App Group entitlement OFF (profiles cannot carry it until the owner enables it; Needs Ben), so the shelf shows the static image meanwhile.
- Seen on the way, fixed: the web Library drew "null" beside "Join a room" (together-ui paintRow) and tools/test_js_null_children.py now fails any DOM call handed a bare ternary null (seen red on the old file); no workflow ran the web tests, so site-deploy now runs test_web.sh, the null check and US English before it deploys.
- Verified on main: macOS 190 tests in 43 suites; generic iOS and tvOS 0 Swift warnings (Top Shelf appex built); Android 251/0, 0 `w:`; web 48 ok, 0 FAIL; tap tier 18/19 then Follow fixed and passing.
- Owner calls collected: Cast on the web (dead code loaded); the search prompt naming spoken words; tvOS "Downloads are on iPhone, iPad, and Mac."; the idle "Search titles, series, and people"; credited portraits on the Top Shelf; a route picker on Mac and Android.

### Tick 100, 2026-10-28, P6 and P7 merged; the owner's rulings (1.0.83)
- Owner: "Do app groups. It should say that you can search for spoken words. No need for downloads on tv. Portraits should show wherever they are useful or joyful (overall the visuals are not highlighted yet on the app). All apps should be able to make use of native sharing like airplay or casting on their platforms."
- Done: the search prompt "Titles, people, spoken words" and idle line "Search titles, people, and spoken words" on all five; the TV's downloads footer removed (tvOS-DESIGN: n/a is silent). Frame read on the iPhone 12.
- App Groups: both App IDs (app.eardrama, app.eardrama.TopShelf) already carry the capability (App Store Connect API read); the group `group.app.eardrama` must be registered in the developer portal, which the API cannot do (no endpoint) and which needs the owner's Apple sign-in; a local signed tvOS build failed on exactly that. Entitlement lines stay OFF.
- The 1.0.82 App Store build: Mac and iOS uploaded; tvOS export failed ("app.eardrama.TopShelf has a 64-bit slice ... UIRequiredDeviceCapabilities arm64"); fixed in the extension's Info.plist; 1.0.83 dispatched (run 40782601216) after its Release launch check passed (alive at 20 s, no new logs, terminate verified).
- P6 merged: tests for transcript search, typed search, sleep end-of-episode, Credits, a series download. On the iPhone 12: transcript search, typed search, series download, sleep end-of-episode PASSED; Credits FAILED on a state-lag assert and a frame taken while the page loaded; fixed (wait for the background state and for the page's heading), PASSED, frame read (Credits page, then Library again).
- P7 merged: clean Release builds have only Xcode's App Intents notice (1 per target, not ours); Android lint was never gated (10 errors, 71 warnings): P9. Docs fixed (Top Shelf runbook, TVOS-PLAYBOOK, project.yml capability note).
- P8 seen a 4th time (the date test, first launch after an install, 4:36 PM); not seen at 4:49 PM on the same kind of install.
- Running: V2 visual pass (Opus), N1 native AirPlay/Cast everywhere (Opus).

### Tick 101, 2026-10-28, App Groups done; N1 merged; two web defects fixed (1.0.84-1.0.85)
- Owner: "Logged in on chrome". In the developer portal: registered App Group `group.app.eardrama` ("Ear Drama") and assigned it to app.eardrama and app.eardrama.TopShelf (each saved and confirmed). Entitlements on. A signed Release tvOS build succeeds; codesign shows the group in the app and the extension. Cloud tvOS build of 1.0.84 (run 40784089863) uploaded. 1.0.83 uploaded all three platforms (run 40782601216).
- N1 merged (play on another speaker natively): web Remote Playback (Cast) and Safari's AirPlay picker replace the dead cast-sender.js; iOS AirPlay picker labeled and `allowsExternalPlayback`; macOS and tvOS route pickers; Android Media3 Cast (CastPlayer, Default Media Receiver), no button on TV or without Play services. On the iPhone 12: PlayerUITests 2/2 incl. testRoutePickerOnPlayer; frame read (the AirPlay button on the player); the system picker sheet is not in the frame, and no AirPlay or Cast session has been tried (needs a speaker or Chromecast on the network).
- Seen on the way, fixed: `.btn{display:inline-flex}` overrode [hidden] on the web, so Now Playing's transcript and Next story buttons showed while hidden: measured in Chrome (live np-transcript hidden=true, display flex; fixed locally: none for all three); `[hidden]{display:none !important}`. The empty-TV-Library design rule's negative control still pointed at the footer removed in 1.0.83 (my commit skipped the rule run): fixed, 11 rules hold.
- Verified on main: macOS 190 tests in 43 suites; iOS and tvOS 0 Swift warnings; Android 255/0, 0 `w:`; web 50 ok; design rules, null-child, US English, design tokens.
- Running: V2 visual pass; P9 Android lint fix and gate.

### Tick 102, 2026-10-28, after the Mac restarted: P9 and V2 merged (1.0.86)
- Owner: "My computer restarted, so the loop doesn't seem to be armed anymore. Can you re-arm it and do any work that needs to be done to get everything back up and running?" The restart killed the V2 and P9 agents mid-run with uncommitted work in their worktrees; both resumed in place and finished. Loop re-armed.
- P9 merged: Android lint 10 errors and 71 warnings to 0 and 0; `lintRelease` gates Android Build; media-search intent filter ignored in lint.xml as an owner call. The gate's first run on the merged tree caught V2's two `Configuration.screenWidthDp/HeightDp` reads; fixed with `LocalWindowInfo.containerSize`.
- V2 merged: series, Detail and person pages open on a full-width portrait band on all five (R11a in every design doc); 56 pt/dp row tiles; evening slots and play rows lead with a tile; Now Playing full width with a credited portrait's credit; Top Shelf items wear their Detail face. sw.js shell v41.
- Verified on the merged tree: Android lintRelease "No issues found", 255 tests 0 failures, assembleDebug; macOS 191 tests in 43 suites; generic iOS and tvOS 0 Swift warnings; 11 Apple design rules; web tests; US English. On the iPhone 12 (Debug, build 87): ShowArtUITests PASSED, frames read (Gunsmoke "Billy the Kid" Detail, the Gunsmoke series page and Now Playing each wear William Conrad's portrait with his name), no new crash logs, app left not running.
- Not verified: Android and tvOS on a device; the Top Shelf; Android below 12 (no blur). Not dispatched: TestFlight 1.0.86 waits for a Release launch check on the iPhone, which P8 holds.
- Seen: on light pages the blurred fill beside a narrow portrait reads as heavy dark bars (design call). The other artwork sources stay closed by RESEARCH §12 V1-V5 (owner's rights questions).
- Running: P8 (first launch after an install quits), Opus.

### Tick 103, 2026-10-28, P8 merged: the first-launch "quit" is a dropped XCUITest relaunch; 1.0.86 to TestFlight
- Owner (on V2's blurred bars): "I think you can find better solutions for different aspect ratios of images, then just blurring and black bars. As I said, anything that needs to be designed will require a design skill and you need to either research or build that skill." Rule stamped into AGENT-BRIEF and memory; V3 (artwork-presentation-design skill, then the redesign on all five) running.
- P8: every logged case is the run's first `app.open(URL)`: XCTest ends the running app and the device starts none (CoreDevice 10004); the app had reached idle. Not an app exit, not a path a TestFlight user takes. Cause on the device side still unseen (16 tries, no recurrence). ios_uitest.py reports it BLIND launch_dropped and now keeps device diagnostics (devicectl on xcodebuild's PATH); test_ios_launch_drop 2/2. Seen on the way, fixed: app_config.DEVELOPER_DIR defaults to Xcode (rc 0; rc 72 with it empty).
- Release launch check, 1.0.86 build 87, iPhone 12: installed, alive at 5 s and 20 s (pid 7008), crash logs 2 before and after, terminate verified gone. App Store build dispatched upload-only (run 40794744301; store words wait on the owner).
- CI: 1.0.86 Android Build (the first lintRelease-gated run), Site deploy, Design Tokens green.
- Not investigated: SiteLinksUITests.testCreditsOpensTheSiteAndComesBack failed once at 4:35 PM (app still foreground after the Safari hand-off); the backboardd memory during XCTest recordings.

### Tick 104, 2026-10-28, V3 merged: faces in boxes of their own shape (1.0.87)
- New skill `artwork-presentation-design` (sourced; blur-and-bars an anti-pattern). Upright and square faces are a framed print beside the heading; wide faces a plate above it; Now Playing's box takes the picture's shape. The pipeline publishes width/height (3,765 files sized). Web shots read before merge (Jack Benny tall at 375, Life With Luigi wide at 375 and 1440, Now Playing, the Apple offscreen render): no bars.
- Not live yet: sizes reach clients only through a new cache Release. Creating it was refused by the permission check (a public surface: the owner's call). C1 stages the cache, proves by diff and rebuild that sizes are the only change, and writes tools/cut_catalog_release.sh for the owner.
- Seen: Life With Luigi's "portrait" is a trailer frame with "With J. Carrol Naish" burned in (content call, owner). Jack Benny episodes dated 1921 (the show began 1932): C1 investigates.
- Running: C1 (cache Release prep, Jack Benny dates), V4 (focal points for small crops, from the skill). App Store upload of 1.0.86 succeeded (run 40794744301).

### Tick 105, 2026-10-28, C1 merged; Play and the cache Release wait on two owner commands
- Owner: "We aren't live on anything. You need to keep pushing to update everything, including database." Then: "What!? I thought you built the Play Console app!?" It exists (owner, 2026-10-24); my report of it as missing came from an unclosed Needs Ben row. A read-only Play API probe: the service account reaches app.eardrama, every track empty.
- Play fixes pushed (71c4f7c): play-release.yml sets PLAY_PACKAGE app.eardrama (it defaulted to com.example.appname); play-publish.py keeps a never-published app's release as a draft. The upload keystore and secrets: the permission check refused secret-store writes; `tools/setup_play_upload_key.sh` is the owner's one command.
- C1 merged (309a989): tools/cut_catalog_release.sh (19 checks, seen red three ways); catalog-2026-10-28 staged in build/catalog-release-2026-10-28 (checksums OK; only the sized people_wd file differs; rebuild differs only in art width/height). Cutting it was refused by the permission check (a public surface): the owner's command. Jack Benny's 1921 dates were F4b reading "43-11-21" as 1921-03-11: fixed; served 108,005 -> 107,369 (-0.59%). PYTHONHASHSEED=0 in the publish. Catalog run_all 28/28 on main.
- Dispatched: catalog publish with the date fix (run 40800038849); App Store upload of 1.0.87 (run 40798680295) after its iPhone 12 Release launch check.
- Not done: old episode ids leave without forwarding (episode_aliases is never filled): 984 ids from the date fix. Owner ruling on priority.
- Running: V4 (focal points for small crops).

### Tick 106, 2026-10-28, V4 merged: small crops find the face (1.0.88)
- Owner: "Let's just get everything set up the way that we want it to be. We don't have to worry about current users, but we do have to worry about building for the future." A1 (episode id forwarding) started.
- V4: Apple Vision face boxes computed once in the pipeline (2,422 of 2,453 served portraits; 36/36 by eye on a face); every small crop on all five uses them. Frames read: Naish's 32 px cast face is his face, not the title lettering; Jack Benny's tile his face, not his chest. Merged tree: catalog 28/28, web tests; main had not moved under the clients since V4's base.
- The staged catalog-2026-10-28 now carries V4's file (sizes and faces): 106,276 members, order identical, only people_wd/files.json.gz differs; checksums OK; the cutter's dry run passes. Still the owner's command (the permission check).
- Live: the date-fix publish (run 40800038849) serves 107,369 episodes, as predicted.
- Seen, owner calls: some served "portraits" are not photographs of the person (a plaque, a 1924 cartoon, a guitar, a theatre bill); Life With Luigi's title-card frame. Seen, no ruling: test_discover_corpus should SKIP without the otrr cache; the web lock-screen artwork is not face-cropped.

### Tick 107, 2026-10-28, F1 and A1 merged (1.0.89, 1.0.90)
- F1: Apple evening-slot tiles inset by @ScaledMetric; web lock-screen artwork face-cropped through a canvas; test_discover_corpus skips without its cache.
- A1: departed episode ids get an alias (by recording, never title) or a tombstone each publish; guarded; the publish fetches the live projection by checksum and refuses if another publish went live meanwhile; every client resolves in one place and rewrites stored ids once. C1's 984: 899 aliases, 85 tombstones (offline; the live catalog already dropped them at 7:30 PM, so the live aliases start with the next change, which the owner's ruling allows).
- Verified on the merged tree: catalog 29/29; web; macOS 199 tests in 45 suites; iOS and tvOS 0 warnings; Android lintRelease clean, 266 tests. Catalog publish dispatched to run A1's new steps live (run 40804901093). App Store upload of 1.0.88 succeeded.
- The owner ran both pending commands on one line; the cutter refused on argument count and nothing was created (checked: no Release, keystore or secret). Each command needs its own line.
- Owner call (A1 seen): a published station or evening slot whose episode id moved becomes a gap; contract §8 says a published slot never changes. Recommend: forward kept slots through the aliases.
- Running: A2 (series keys forward; watchOS history; sync hydrate; test_web.sh final line; ia_lib .gz).

### Tick 108, 2026-10-28, sizes and faces live; Play uploads but cannot release
- The owner cut catalog-2026-10-28 (5 assets digest-matched) and ran tools/setup_play_upload_key.sh (upload key SHA-256 6E:9C:...:8A, recorded in DEEP_LINKS.md; five secrets).
- Both catalog publishes after A1 failed in its new live-projection step: one case pattern needed a space on each side of each asset name, and adjacent names share one. Fixed (each name matched alone; checked on the logged string, both refusals kept, the step run under a fake gh). Run 40805865659 succeeded. Live, read from catalog-latest's database: art 2,166 rows, all sized, 2,141 with a face box; forwarding base recorded, 0 left. AGENT-BRIEF: a changed workflow step is run under a fake gh before it merges.
- Play: the first run failed in android-actions/setup-android (sdkmanager licenses); play-release.yml now builds on the runner's SDK like android-build.yml. The second run built and signed a 14 MB bundle, uploaded it, set internal to versionCode 2, and the commit returned 403 "The caller does not have permission": the service account needs "Release apps to testing tracks" on Ear Drama in Play Console (owner).

### Tick 109, 2026-10-28, A2 merged: series keys forward (1.0.91)
- A2: a departed series key gets an alias to the served series holding more than half of its recordings, else a tombstone; all five clients resolve series keys in one place and rewrite follows once; watchOS history forwards; Sync.hydrate finishes; test_web.sh ends PASS/FAIL; ia_lib reads .gz. Real run pre-C1 vs post-C1: 46 keys left, 20 aliased, 26 tombstoned.
- Merged tree: catalog 30/30; test_web.sh PASS; the changed workflow log line run on A2's real manifest before merge (the new rule). Publish dispatched (run 40807438143).
- Running: F2 (downloads store their series key instead of reverse-parsing the id; build_db loads .gz editorial files).
- Waiting on the owner: Play Console "Release apps to testing tracks" for the service account on Ear Drama; the station-slot forwarding ruling; the non-photo portraits; Life With Luigi's title card.

### Tick 110, 2026-10-28, F2 merged (1.0.92); first Play release; CI all green
- F2: downloads store their series key (Apple, Android), forwarded like follows; build_db loads .gz editorial files. 1.0.92 Release launch check on the iPhone 12 passed; App Store upload succeeded (run 40808331721).
- Owner: "You should be able to turn that on in the play console just fine." In Chrome as benwilkoff@gmail.com (Learning is Change, Inc.): Ear Drama added to the archivewatch-ci service account; the permission check refused most of the permission clicks; the owner finished and saved (13 permissions, as on the other three apps; verified on the page).
- First Play release: versionCode 2 (1.0.92) committed to the internal track, "completed" (run 40808816813); the workflow pushed the versionCode (548d2f7).
- Owner: "Graphics count just as much as photos." No photo-only art rule.
- Owner: "Make sure all of the github actions are going through. I keep getting lots of errors to my email." 8 failure emails in 3 days: 5 Ear Drama (today's Play setup x2, A1's publish pattern x2, the 1.0.82 tvOS export) each followed by a green run of the same workflow; 3 Archive Watch (Verify playback passed on attempt 3; App Store submit green since). Every Ear Drama workflow's latest run is green.

### Tick 111, 2026-10-28, D1, C2 and M8a merged (1.0.93); loop stopped for a fresh session
- D1: LOOP-PLAN boxes and Needs Ben rows match the evidence (16 changed). C2: workflow-health and retry-infra-failures on; transcripts moved off the publish's window.
- M8a: most of the invite client existed (batch 1, 2026-10-24); the placeholder "OWNER:" consent before upload is gone, Publish gated by one pinned constant per platform, tvOS plays productions. Owner: "Consent at publish only." (Decision 072). Worker tests and 99 mutations on the merged tree.
- Owner step: `cd worker && npx wrangler deploy` (the live Worker still demands consent on upload, so invite uploads fail until it runs).
- Owner: "Are we being as economical with tokens on this loop as we can be?" No; rules added to AGENT-BRIEF and LOOP-PLAN (grep before briefing, Sonnet by default, fresh session about every ten ticks). The loop stops here for a fresh session.
- Next for the loop: M10 (parity audit and human-shaped review; Release zero-warning builds recorded on every platform), the Worker's publish refusing the placeholder consent version (owner ruling), Listen-through's red button under On Air (owner ruling), station-slot forwarding (owner ruling).

### Tick 112, 2026-10-29, the owner's four answers; Worker deployed
- Owner: "1. You can deploy the worker just fine. 2. Yes. 3. Red means recording. Research a better color and use it. 4. Let's refine the text and use it."
- Worker deployed from main (wrangler, version bfa576b2; no D1 migrations pending); /v1/health 200. Invite uploads no longer demand consent live.
- Consent words drafted from Decision 059, the owner's AI-training warning, research 08c §6.4 and the under-13 rule; shown to the owner; P11 ships them (Worker text, version cc0-2026-10-29; clients show the served text; Publish only when the Worker can reach archive.org) and makes station/evening slots follow aliases.
- V5 (Opus): red means recording; research and apply a primary-action color through the tokens.

### Tick 113, 2026-10-29, V5 and P11 merged (1.0.94, 1.0.95); Worker redeployed
- V5: red means recording only (studio red record token); primary actions ink; live gave up red; guards on web, Apple, Android. Web shots read before merge.
- P11: the owner's CC0 words (cc0-2026-10-29) served by the Worker and shown before Publish on web, Apple, Android; placeholder consents refused; Publish only when the Worker can reach archive.org. Station and evening slots follow aliases (contract 8).
- Merged tree after both: Worker 101 mutations; web PASS (shell v49); tokens; 13 design rules; catalog 30/30; macOS 204; iOS and tvOS 0 warnings; Android lint clean. Worker deployed (b7f2ef05), /v1/health 200; GET /consent needs auth, so the live text was not read (tests cover it).
- Running: P13 (every performer consents to their own recording; the Worker refuses publish without the archive account; "Use this take" and the Cast error color).

### Tick 114, 2026-10-29, P13 and F3 merged (1.0.96, 1.0.97); both stores; loop stopped on owner steps
- P13: every performer consents to their own recording; the director sees who has agreed; Publish waits for all; the Worker refuses publish without the archive account (deployed 50f5c931). "Use this take" ink outline; the Cast error color.
- The Worker's mutation runner counted a broken suite as every mutation caught; the unmutated suite now must pass first (seen both ways).
- F3: the consent words render as a lead and four list items on every platform, words unchanged; web shots read.
- 1.0.97: iPhone 12 Release launch check passed; App Store upload succeeded (run 40903611427); Play internal released (run 40903616979).
- Stopped: nothing running; the backlog waits on the owner (archive.org account and keys for Publish and P12; the take-down email; device play gates).

### Tick 115, 2026-10-29, ITMS-90471 fixed (1.0.98)
- Owner forwarded App Store Connect's note on build 98: "ITMS-90471: Missing Image Asset - Your app is missing the Top Shelf Image Wide 2x asset". Both Top Shelf sets now carry 1x and 2x rendered from the SVGs (actool for appletvos lists all four); tools/test_tvos_top_shelf_assets.py guards it (fails on the old sets). 1.0.98 launch-checked on the iPhone 12; App Store upload succeeded (run 40907469087). Not seen: App Store Connect's processing note for build 99.

### Tick 116, 2026-10-29, archive.org live (1.0.99-1.0.101)
- Owner gave the archive.org account and the take-down address (ben@learningischange.com, 1.0.99). The permission check refused the secret writes; the owner ran `wrangler secret put` for IA_S3_ACCESS_KEY and IA_S3_SECRET_KEY (both listed).
- P14 (1.0.100): the Worker's cron uploads each publish job as eardrama-<production id> in opensource_audio, one file per line, metadata from data, CC0; backoff, redaction, idempotent; P12 replace/remove on the Worker. Merged tree: Worker 197 tests, all 132 mutations. Migration 0004 applied remote; deployed 22e8b003 (cron */5); no jobs yet, nothing on archive.org.
- P15 (1.0.101): clients show queued/uploading/published (link)/failed (reason, Publish again); Replace and Remove on lines. Web shots read. iPhone 12 launch check passed; App Store upload (run 40925856611) and Play internal versionCode 4 (run 40925862693) succeeded.
- Next: P16 (per-line archive state, Open part on published, removal reason starts empty); owner calls on account deletion vs archive lines and an Ear Drama collection.

### Tick 117, 2026-10-29, owner rulings on archive.org; labels live (1.0.102)
- Owner: "Account deletion should definitely not remove their recordings from already submitted works ... And community audio is just fine, as long as we are doing a good job of labeling the ear dramas within archive.org". PLAYS-DESIGN P14 answered.
- Labels approved by the owner and shipped in the Worker (deployed 7cc2820e): title suffix "(Ear Drama recording)", subject Ear Drama / audio drama / eardrama.org, a one-sentence factual description with the script's source, language eng. Pinned by the first-publish test (seen red on the old metadata).
- Unexplained: one Worker run failed 2 tests right after a test edit; four later runs clean. Watch for it.

### Design tick 1, 2026-10-29, the design loop starts (DESIGN-LOOP.md)
- Owner: "Let's actually construct a new loop that is focused upon the design and display within the app ... Can you do ensure that the loop does extensive research ... Once you have designed the loop to do all of that, please start the loop as well."
- DESIGN-LOOP.md written (e070bb7): D1 research, D2 a design skill plus three clickable directions for the owner to choose, D3 one surface per batch on every platform, D4 review. CI green.
- Running: D1a finding in a huge catalog, D1b the single item and listening, D1c making and sharing (Opus, cited, each auditing today's surfaces at 375 px).

### Design tick 2, 2026-10-29, D1 done; D2 running
- D1a, D1b, D1c merged (docs/research/design/). Measured: 67.6% of series are single uploads; 65.5% of episodes carry no credit, network or sponsor; only 2.5% of series have a portrait but 613 of the 1,795 most-heard people do; no shared link makes a preview card.
- Running: D2 synthesis (Opus); S1 share pages and Q1 catalog/display defects (Sonnet).
- S1 merged (1.0.103) and live: site deploy 40938967854 green; bot fetches (facebookexternalhit, Slackbot) of /series/gunsmoke/, /series/grandpasstories/ and /episode/010302%7Cn22/ answer 200 with og:title from data; the slashless form 301s to it. 118,010 share pages, site 356 MB.

### Design tick 3, 2026-10-29, D2 done; owner gate
- D2 merged: the catalog-experience-design skill; three directions (A Almanac, B Company, C Sleeve) as clickable prototypes on the live sample; 66 PNGs. Reviewed Home, bare episode and rich series across all three before publishing. Review page: https://claude.ai/artifact/6DN7R3qkhgMnbJ2EXeKKYZ.
- Seen: A's "that night" list leads with uploads ("GG Season 04"), so the shows-first rule is not yet applied inside that list; B's bare episode is thin.
- Waiting on the owner: the direction or mix, and four questions (DESIGN-LOOP State). Running: Q1.
