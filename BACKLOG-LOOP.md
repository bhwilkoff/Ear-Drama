# Backlog loop: all documented work (started 2026-11-23)

Owner, 2026-11-23: "Yes, let's get started on all documented work via an autonomous loop. Please make
sure we aren't going to override any of the cleanup work we did in this repository from the other
sessions."

Each tick: read this file, check CI (`gh run list -L 10`), check the Mac (below), run the next open
batch, merge only verified work, then update State. The loop wakes on results, 30-minute fallback.

## Guardrails: never undo another session's work

Other sessions committed cleanup today; it stays. Before touching any of these, read the commit:

- `b6bed5b3` Worker read room long poll, one row per cursor move; `012d458d` clients' long poll on web,
  Apple, Android; `3103868e` relay: hidden or idle tab holds no pickup, RelayWatch 5-minute empty wait;
  `cc301d92` read room alarm never in the past; `17d31ad7` archive cron picks only jobs with work.
- `f1a29bfb` CI: the Gradle cache is written only from main and cleaned; concurrency on three workflows.
  Never re-add a cache write, remove a `concurrency:` block, or edit an App Store workflow.
- SCRATCHPAD "a $0.00 stack" entry: no polling loop, timer, alarm or long-held request without a
  test that counts its requests or writes. Free-plan limits are a design constraint.

Mechanics:
- `git fetch` and rebase or merge onto `origin/main` before every merge; resolve conflicts by keeping
  both sides' intent, never "ours" over a file another session changed today. Never force-push.
- Stage explicit paths; never `git add -A`. Never revert a commit that isn't this loop's.
- Before editing a file, `git log -3 --since=midnight -- <file>`: if another session changed it in the
  last 30 minutes, skip that item this tick (it may still be working).
- Worktrees and branches: remove only ones this loop created, or ones merged into main, not locked,
  and not modified in the last 24 hours. Never delete `.claude/worktrees/*` another session may hold.
- Never `wrangler deploy` while another session has a Worker commit less than 30 minutes old; deploy
  only from a clean `worker/` at `origin/main` with the full suite green.

## Resource and device rules (standing)

- `uptime; memory_pressure | tail -1` first; wait if the 1-minute load is over 8 or free memory under
  20%. One build-heavy agent at a time; `nice -n 15`; gradle `--max-workers=2` then `./gradlew --stop`;
  xcodebuild `-jobs 4`. Prefer CI for lint. Kill only our own leftovers.
- NEVER run the tap tier or any APP_RESET_* door on the owner's devices unless the build carries b377a936
  (lists set aside and restored); on 2026-11-23 it erased the owner's lists on the iPhone 12 and Duo.
- Real devices only, never simulators. Muted; ask before anything audible. Never sleep a device, never
  kill the owner's running app. Check the device lease.
- After any Apple screen edit run `python3 tools/test_apple_design_rules.py` (its negative controls match
  source text; b377a936 broke one and CI caught it at 54150de1).
- Store cadence: after a verified Apple or Android merge, bump, then dispatch
  `appstore-build-x27.yml` (platform=all, submit=false) and `play-release.yml` (track=internal).

## Batches (in order)

- [x] **B1 Quick fixes** (done 2026-11-23). (a) Apple Library foot shows two Export rows: one. (b) N8 Android's stall
  watchdog counts a slow seek as a stall (fixed on Apple and web; mirror). (c) N10 housekeeping:
  `.wrangler/` in `.gitignore`; prune merged `worktree-agent-*` branches under the worktree rule above.
  (d) SCRATCHPAD Current State brought up to date.
- [x] **B2 Worker deploy** (a8982b67, 2026-11-23). The $0.00 stack Worker changes (SCRATCHPAD "The Worker needs a deploy"),
  under the deploy rule above; then watch `wrangler tail` for a minute for errors.
- [x] **B3 Relay rules on Apple and Android** (de3cb83d; delta: apps have no cast-sheet pickup and no watch tick, quieter than web; Keep receiving takes flow untested directly). Mirror the web's receiver and sender rules (hidden or idle
  holds no pickup, 30 idle minutes stops, Keep receiving takes, RelayWatch 5-minute empty wait) in
  Apple `ClassInbox`/`RelayHub` and Android `RelayAcrossTime.kt`; tests that count asks; PARITY row.
- [x] **B4 Web voice labels** (e1e27720; real Chrome on the Pixel still to confirm the voiceURI carries the engine id: B5). Browsers that name voices only by locale get measured labels like
  Android's (PLAYS-DESIGN 2.8 rule 12); PARITY ⏳ cleared.
- [x] **B5 Library and read-along on devices** (2026-11-23; follow-ups on a device: Pixel empty door, iPhone Export tap area, TV foot alignment). New-user Library on the Pixel (without wiping the
  owner's data: a second user profile or a DEBUG door) and the Duo; Apple TV frames; run the Library
  UI tests; press read-along pause, step and speed on an Apple device (muted).
- [ ] **B6 Round 3 leftovers** (class-room silence: no product bug, bench mic never spoke, fixed ad9aeabd; left: Duo Record indent and Apple class review on a device). Class-room takes end on silence (adult rooms do); Duo Record "Plays"
  indent; Apple class review screen seen on a device.
- [x] **B7 Harness** (54150de1). N7 three intermittent checks (instrument, never rerun until green); N12 the tap
  tier draws its shows from the data, not the same two.
- [x] **B8 Catalog** (bb506cf8, publish dispatched; follow-up: roman numerals cased "Iii", all-caps Cisco Kid/Escape titles, pre-existing). N13 remaining raw titles: `tools/catalog_dryrun.sh` on real data first.
- [x] **B9 PARITY gaps** (e71aa5f7; Android Auto Stations and Browse are empty folders in the car: owner call, car review). Apple TV share as a QR code; Android Auto library tree beyond the stub.
- [x] **B10 Parity audit (N9)** (c0eb3c07). Every shipped feature a row, every cell honest; last, after B1-B9.

- [x] **B11 Follow-ups from the audit** (e4b44c28; iPhone tap tier partly BLIND behind Screen Time). A full iPhone 12 tap-tier run on a build with 7ecdd3d8 (lists set
  aside and kept across a test's relaunch) to settle the pre-redesign iOS cells (SiteLinks via About, ShowArt,
  Browse, Detail/Person); a real-browser web pass (Safari on the Mac, Chrome on the Pixel) for web cells.
- [x] **B12 Catalog follow-ups** (6aefa199, publish dispatched). Roman numerals cased as words ("Henry Iii" -> "Henry III"); all-caps titles
  (Cisco Kid, Escape) only where certain (acronyms kept). Dry run first.
- [ ] **B13 Device follow-ups** (Pixel door, TV foot done 2026-11-23; left: Duo indent, class review needs sign-in). Duo Record "Plays" indent (when the Duo is home); Apple class review screen;
  Pixel empty-library door frame; Apple TV foot alignment frame.

- [x] **B14 From the tap-tier run** (cadfa92a; left: Follow button off center, iPhone landscape rows under the mini player, ShowArt test likely stale, Gutenberg inline residue in 3 plays, AppReviewModeration env; stale UI tests compiled, not yet run on a device). Harness: tools/ios_uitest.py matches overlay frames by bare method name
  (key on Class/test), keeps running behind a Screen Time overlay (stop and mark BLIND), no nice/-jobs. Stale
  tests to rewrite for today's screens: Detail x2 (person tiles; Recordings row), Queue (direction B empty side),
  Ink on iPhone (iPad only), LayoutSweep testCreate, Navigation testHomeThenBrowse. Real UI defects: Follow
  button content off center (LayoutSweep testActionRowsAreCentered); iPhone landscape rows straddle the mini
  player. Android Library foot: Voices and About lack leading icons. Web reader: Gutenberg "[Illustration]"
  residue line (gut-20989-5). AppReviewModeration needs APPREVIEW_INVITE env.

## Round 2 batches (2026-11-24; owner: "let's begin")

Owner, 2026-11-24: "Fill in spaces on Android auto to make the app more robust. All radio and regular play
scripts should be able to be re-recorded. You should be able to record your own version of anything you want
with your own casting. No need for a day switched on stations." This repo only. iPhone 12: Screen Time is off
in the daytime (back about 21:00, so device work on it goes first).

- [x] **B15 Devices while they are free** (592fa7a8; follow-ups B15b). Tools: `/usr/bin/python3` has jwt and Pillow, Homebrew's lost them in
  the 2026-11-24 cleanup; make asc_release/ios_uitest say so or find one that works. Then the Duo Record indent
  and a frame of every screen changed since 11-16 open and closed; iPhone 12: the six rewritten tests, ShowArt,
  SiteLinks; fix the Follow button off center and the landscape rows under the mini player, with frames.
- [x] **B15b Faults read (merged 2026-11-24; left: B15c)** read in B15's frames** (every platform, fixed or n/a): Duo episode page, the Automatic transcript
  card's square top corners; iPhone landscape Browse, the pinned header and filters leave a 200 px band of tiles;
  series board, a thin strip of board beside a picture that nearly fills it; Today's Scene runs verse together as
  prose; unseen on the Duo: closed, Library Making, a play page. With it the R4-0 follow-ups on Apple and Android
  (class picker reads the library; words for `script_not_publishable`; the bundle tried when the library is newer).
- [ ] **B15c Left from B15b.** Apple rooms and shared screens of library plays: done (`LibraryScripts.swift`; seen on Ben
  Bedroom, gut-3012); left: `FinishedTiles.script(for:)`, tvOS Surprise. Android done (library scripts by revision, 85% rule, opening tiles,
  landscape bars; two-pane queue built, unseen: no tablet). The sync line
  names the day on Apple (done; web and Android already did). `web_fit_home.py` fails by
  day ("no On the air block", ten day-history failures on unmodified HEAD): make it deterministic. Catalog: gut-49993-1
  (and the scene pool) lost its verse breaks; `opening_of` flattens breaks. Duo closed and portrait unseen.
- [ ] **B16 Every cleared play records (088.1).** 803 of 1,722 parse clean. Held: unclassified over 5% 269,
  format unrecognized 200, fewer than two castable roles 124, mostly set aside 121, role only before the play 25,
  title cut off 16; volumes: 500 segments with no printed title, 69 volumes by several authors. Recover by layout
  family, never by loosening the clean gate; monologues (one role) are recordable. Dry run, read a sample of each
  family against its source text, then publish. Client suites run.
- [x] **B17 Android Auto** (built, browsed on the Pixel 2026-11-24; left: a car; **B17b CarPlay** the same on Apple, behind the entitlement). Stations and Browse filled, search, art; CarLibraryTest; the Desktop Head Unit if it
  can run without an emulator. Internal track only until Google's car review.
- [ ] **B18 Record anything (088.3): design first (Opus, learning-orientation-design).** Bring your own script
  (paste, file, share sheet); an episode's automatic transcript as a starting script the person casts line by
  line; what never publishes. Research, frames, binding docs, then web, Apple, Android.
  Designed 2026-11-24: `docs/research/design/R4-record-anything.md` (batches R4-0 to R4-8; three owner questions
  in its §9). **R4-0 first** (defect: the Worker's castable manifest holds 15 scripts, the library 803, so Share and
  Read together refuse 788 plays). Then R4-1, 2, 3, 6, 7 on-device half, then R4-4
  (with the report issue workflow, 088.6) and R4-5. §9 answered by the owner 2026-11-24 (088.4-6). **R4-9**: publishing
  a script you wrote, after a title and content search (088.5): design the search first (library texts, cached radio
  scripts and transcripts, Catalog of Copyright Entries and renewals, Open Library and copyright.gov titles), run in
  Actions, a planted copy must be caught. The declaration (R4-9) and the privacy phrase (R4 §7.8) are researched and
  written by the loop, sources in Decision 088; no owner approval (2026-11-24).
- [ ] **B19 Radio scripts (088.2).** Waits on the owner's answer about the Workshop's text; the parser and match
  (616 served episodes) are ready. Recording open, Publish closed without evidence.
- [ ] **B20 Seen on a device.** 57 PARITY rows say a part was never seen, heard or run: Mac windows (owner away
  only), Apple TV, Google TV, reader and studio on the Pixel. Look, then fix or mark done with evidence.
- [ ] **B21 Parity gaps.** Play tiles' opening speeches on Apple and Android; Now Playing beside the queue on wide
  web and Android tablets; folding during a take on Android; the reader on Apple TV; Google sign-in on Apple TV
  by the phone.
- [ ] **B22 Catalog faults.** Last all-caps and uncertain titles; series under several names; Gutenberg residue
  in three plays. Dry run first.
- [ ] **B23 Next store version ready.** 1.0.137 carries none of classes, read rooms or relay. Before the next
  submit: App Privacy label, age rating answers, review notes and demo recording match what the app now does.
- [ ] **B24 Design review of what shipped.** Home, Record, reader on every device, against the owner's words.
- [ ] **B25 Records.** SCRATCHPAD answered items; six old worktrees read, then removed.

## Waiting on the owner (never blocks the loop)

**B19**: the Workshop's answer (request drafted to Larry Groebe, owner sends). Kokoro re-export for Android and web word marks; a read-only Cloudflare analytics token for a usage
check; SCHOOL_CONSENT_POLICY; OPERATOR_TOKEN; H1-H4 sessions;
GRW request sent or not.

## State

- 2026-11-23 14:20: loop started. main at origin/main after 17d31ad7.
- 2026-11-23 15:10, tick 1: B1a Apple foot one Export row (92006763; built macOS/iOS/tvOS, Mac frame
  read, menu not opened by hand). B1c: .wrangler/ already ignored; 187 merged idle agent branches and 11
  clean merged worktrees removed (locked, dirty and unmerged kept). B1d SCRATCHPAD (47656289). B1b N8
  running in an agent (Sonnet, worktree). B2 waits for load (17.7 during the agent's Gradle run). Disk 94%.
- 2026-11-23 15:16, tick 2: B1b merged (a491f751: Media3 seek discontinuity while BUFFERING marks a seek in
  flight; StallWatchdog restarts its count; 3 tests seen failing first; lintRelease clean). B2: Worker suite
  489/489, no D1 migrations pending, deployed a8982b67, /v1/health 200, a minute of tail with 0 exceptions.
- 2026-11-23 15:25, tick 3: B4 merged (e1e27720): locale-named web voices read Android's seed labels
  ("Low, warm · US") when the id carries Google's engine code, else "US voice"; no engine codes on the web
  (I removed "(aua)": the web never measures, so a code would read like a number); 73/73, fit PASS, PNG read.
  B3 relay rules running.
- 2026-11-23 15:33, tick 4: B3 merged (de3cb83d): PickupLoop on Apple and Android (foreground only, stops
  after 30 idle minutes, Keep receiving takes), senders defer retries while backgrounded; 4+4 tests that count
  asks, all failing with the rules removed; macOS relay suites, iOS, tvOS, Android lintRelease green. Fixed the
  LibrarySides.kt:107 compiler warning (5a8afec7). Next: CI green -> bump + TestFlight + Play; then B5 devices.
- 2026-11-23 15:48, tick 5: CI green; 1.0.166 (167) bumped (35121322), TestFlight run 45282662411 and Play
  internal run 45282668426 dispatched. B5 device pass running in one agent (muted, leases, no wipes).
- 2026-11-23 16:20, tick 6: B5 device pass. PASS: new-user Library iPhone 12 + Duo (inner-display frame),
  Export menu items, Apple TV Library (shared shelf not seen: none shared), 4/4 Library UI tests, read along
  pause/step/7 speeds/2x pages on iPhone 12 and Duo. Found: tap tier's APP_RESET_USER_STATE ERASED the owner's
  history/queue/follows on iPhone 12 + Duo (local; server copy if signed in) -> fixed b377a936 (set aside +
  restore on next launch, test); Export row dead zone, empty-Library Edit button, Apple TV foot centering ->
  fixed b377a936 (not yet seen on device). Real Chrome on the Pixel has no engine ids: web voices read "US voice"
  etc. (one per locale). Gaps: Android empty-library door (agent running); Homebrew python3 Pillow broken for
  tools/ios_uitest.py (use /usr/bin/python3).
- 2026-11-23 16:40, tick 7: Android empty-library door (draws only) + real Chrome 157 voices test merged
  (80a52f91; 78/78 web, lintRelease 0 warnings; also fixed own-locale sort for Chrome's en_US tags). B6 class
  takes end-on-silence running in an agent. Duo is out with the owner: Duo Record indent BLIND today.
- 2026-11-23 16:55, tick 8: B6 merged (ad9aeabd): class-room takes do end on silence on every stack; the class
  bench's fake mic (gain 0.0005, under the 0.003 floor) never spoke, so takes stayed open. Bench now speaks per
  line and fails if Stop is needed (46/46 against a local Worker); 3 web tests (adult, class, never-speaks) with a
  planted class-only mutant caught. Stopped the finished B5 agent's leftover background work (no leases held).
  B7 (N7 + N12) running in one agent; iPhone only with b377a936 in the build.
- 2026-11-23 17:00, tick 9: B7 merged (54150de1): testMiniHome waits on predicates and pauses the mini (playback
  past 30 s inserted Continue mid-sweep); DownloadsPlace clears leftover downloads and reveals rows above the tab
  bar; both 3/3 identical on iPhone 12 (build 167, lists set aside). N12: tools/uitest_fixture.py picks shows by
  shape per run, seeded and logged. iPhone 12 Library empty after restore: expected, its lists were erased before
  b377a936. B8 (N13 titles) running; dry run before any publish.
- 2026-11-23 17:30, tick 10: CI red "Apple design rules" at 54150de1: my b377a936 TV alignment edit broke a
  negative control's match string; fixed b90c7f4d (15/15). Guardrail added. B8 still running.
- 2026-11-23 18:00, tick 11: B8 first pass (d653e01e, unmerged): 1,894 titles cleaned, 51/51 dry run green, but
  it withheld 27 previously served episodes whose file names carry valid date codes (World's Fair 1939, Fred
  Allen) and left fragments ("1st", "Torr"); sent back to compose from valid dates and guard fragments.
- 2026-11-23 18:15, tick 12: B8 revision merged (bb506cf8): 1,875 titles cleaned; valid YYMMDD file-name codes
  compose dated titles (World's Fair 1939, Fred Allen) so only 9 withheld (no real date anywhere); fragment
  guard; "(partial)" convention; 51/51 dry run. Read the 128 one-to-two-word results. Catalog publish dispatched.
- 2026-11-23 18:35, tick 13: B9 merged (e71aa5f7): Apple TV episode Share opens a QR sheet (tvOS-DESIGN 3.6),
  frame read on Ben Bedroom, QR decodes to https://eardrama.org/episode/suspense%7C1948-11-18; 571 Apple tests,
  16/16 design rules. Android Auto audit: Continue + Downloads work, Stations + Browse empty (PARITY honest).
  Catalog publish running. B10 parity audit running. Follow-ups: roman numerals "Iii" and all-caps titles.
- 2026-11-23 18:40, tick 14: B10 merged (c0eb3c07): 12 cells promoted with cited device evidence, 4 demoted,
  ~15 reasons added, 1 row added, 2 malformed rows fixed. FollowUITests asserted Home (pre-075): rewritten for
  Library; its first iPhone run exposed that the set-aside restore ran on a test's own relaunch -> fixed
  7ecdd3d8 (APP_UITEST_SESSION on every test launch), then PASS on the iPhone 12 (frame read). Seen on device in
  that run: Export one row, no Edit on empty Library. Catalog publish with the N13 titles: success. 1.0.167
  (168) bumped (b24b92eb), TestFlight 45306026587 + Play 45306031466 dispatched. iPhone 12 is not signed in:
  its lists erased this afternoon had no server copy.
- 2026-11-23 19:08, tick 15: TestFlight 1.0.167 (168) and Play internal: success. Android Build red at b24b92eb:
  Robolectric's MavenArtifactFetcher could not download android-all (infra, every Robolectric class); rerun of
  failed jobs started. If it recurs, check whether f1a29bfb's cache cleanup drops Robolectric's jars (report to
  the owner; don't edit the other session's workflow change without them). B12 running.
- 2026-11-23 19:20, tick 16: B12 merged (6aefa199): 258 titles; roman numerals only after a numeral-taking word
  or king (Henry III, Mary I from its own file name), shouted titles recased only with catalog proof per word
  (216 -> 41 left), "-0" tails stripped only when the episode's own file ends that way; 51/51 dry run. Publish
  dispatched. B11 + B13 device verification running in one agent (Duo excluded). Android CI rerun in progress.
- 2026-11-23 21:20, tick 18: B11/B13 device pass. iPhone 12 tap tier 68 tests: 25 pass / 30 fail before 21:00,
  12 BLIND after Screen Time's Time Limit covered Ear Drama (ShowArt, SiteLinks included); most fails are stale
  tests (B14). Web in real Chrome on the Pixel PASS (10 screens, no sideways scroll). Pixel empty-library door
  PASS, owner's Up next intact after. Apple TV foot leading-aligned PASS. Class review BLIND (needs sign-in).
  PARITY e4b44c28: 6 web cells and 2 iOS cells to done with today's evidence. No set-aside keys left on iPhone 12.
- 2026-11-23 22:45, tick 19: B14 agent committed its four items and is running the Gutenberg plays harvest
  (rsync 5,094 files, 505 MB, network-bound). Disk 97% (15 GB free, was 27 GB at 15:00): removed 4 orphaned
  Ear Drama DerivedData folders (1 GB). Remaining growth is not this loop's build folders; avoid disk-heavy work.
- 2026-11-23 23:40, tick 20: B14 merged (cadfa92a): harness keys frames on Class/test and marks every test after
  a system overlay BLIND with one DEVICE BLOCKED line (10/10 fixture tests, replay of tonight's bundle right);
  6 stale UI tests rewritten (compiled; iPhone under Screen Time); Android foot Voices + About icons (Pixel
  frame read); plays parser drops "[Illustration]" lines keeping line ids (122 plays, 89,178 lines unchanged,
  493 marker lines dropped). Catalog publish dispatched. Disk 96% (17 GB free).
- 2026-11-23 23:35, tick 21 (loop stopped): CI green at cadfa92a; 1.0.168 (169) bumped (d48214d4), TestFlight
  45341105789 + Play internal 45341109592 dispatched; plays-library publish running. Everything left needs the
  owner or a blocked device: iPhone 12 Screen Time limit (then re-run the tap tier: ShowArt, SiteLinks, the 6
  rewritten tests, Follow centering + landscape mini-player rows to fix with evidence); Duo home (Record indent);
  a signed-in teacher (class review); owner calls (Android Auto empty tabs, Kokoro re-export, Cloudflare
  analytics token). Restart with /loop Read BACKLOG-LOOP.md and run the next tick.
- 2026-11-24 (owner stopped the loop; resume notes):
  - **TestFlight 1.0.168 (169) did not ship** on the first try. Run 45341105789 was dispatched before the bump
    was pushed, so it built 6b44ca36 (build 168, already uploaded) and refused. Redispatched from main
    (be52506a, build 169): run 45405162430. Play internal 1.0.168 succeeded (versionCode 15), as did the
    plays-library publish (45339119092). First thing on return: `gh run view 45405162430`. If green, 1.0.168
    is on TestFlight. If red, read the "Archive + sign + upload" step.
  - **Disk cleanup with owner approval: 21 GB to 50 GB free.**
    - Removed: 6 clean agent worktrees and their merged branches, all build/dd-*, build/ship-mac,
      build/uitest-dd, build/ipad-dbg, build/uitest-fixture, the Android build folders, all of
      ~/Library/Developer/Xcode/DerivedData, the Gradle build cache, the CoreDevice install-delta cache,
      the pip/uv/npm/Homebrew caches, and build/qa before 2026-11-23.
    - The first Apple and Android builds will be cold (slower). `brew cleanup` also autoremoved 28 orphan
      libraries; ffmpeg, tesseract, ocrmypdf and idevice_id still run.
    - Kept: 7 worktrees with edits or unmerged commits (a43512d9, a9d0a55f, aaca8e45, ad5fd672, add47159,
      ae2bffba, af0729c1). Review them before deleting. Also kept build/qa/ios-uitest-2026-11-23,
      build/store-shots and build/store-video.
  - **To restart:** `/loop Read BACKLOG-LOOP.md and run the next tick`, once the iPhone 12 Screen Time limit
    is lifted, the Duo is home, or the owner answers one of "Waiting on the owner". Start with CI
    (`gh run list --limit 10`). Never run the tap tier or APP_RESET_* doors on a build without b377a936 and
    7ecdd3d8.
- 2026-11-24 13:30: restarted by the owner with rulings (Decision 088); round 2 batches B15-B25. TestFlight 1.0.168 (169) is VALID.
  iOS and macOS 1.0.137 WAITING_FOR_REVIEW since 2026-11-16 (nothing missing in Connect; tvOS approved 11-18).
- 2026-11-24 14:20: R4 design merged. B16 had no source texts on disk (24 of 1,721); rsync of the cleared texts running into
  catalog/.cache. R4-0 (manifest covers the library) started. B15 device agent still running.
- 2026-11-24 14:55: **R4-0 live**: site rows, D1 0012, Worker c92c52f2. Two library plays opened rooms on the live Worker, a
  tampered cast is 422 cast_mismatch, an unknown id 422 not_castable; 533 Worker tests, 29 web suites. B15 merged
  (592fa7a8): 571 Apple tests, 16 design rules; frames read by the main thread found B15b's faults.
- 2026-11-24 15:25: B17 merged (Android Auto tabs, search, art, voice; unit suite + lintRelease 0). Next build-heavy slot: ship after B15b.
- 2026-11-24 15:45: R4-1 JavaScript core + goldens merged (98.5% radio, 97.2% stage words to the right part; 8-word overlap check with cached radio scripts: none). Kotlin port running; Swift port and R4-2 web wait for B15b. B16 running with all 1,721 texts.
- 2026-11-24 16:20: B15b merged (576 Apple tests, 30 web suites, 12 frames read). 1.0.169 (170) bumped for TestFlight + Play internal.
- 2026-11-24 16:30: Swift core + B15c Apple merged (602 tests; a library play room drawn on Ben Bedroom). 1.0.169 TestFlight failed on a runner DNS blip after the Mac upload: tools/net_retry.py (8 cases) now waits blips out in the Apple tools. 1.0.170 (171) redispatched. Play internal 1.0.169: success. Footnotes spoken in gut-3012 sent to B16. Ben Bedroom was woken by the agent and left on.
- 2026-11-24 17:00: 1.0.170 (171) on TestFlight (all three) and Play internal (versionCode 17): success. **R4-2 merged and live
  on the web** (Add a script; 31 suites, 23 mutants, frames read). R4-2b found reading frames: a pasted Gutenberg file leaves its
  license as "No part" lines (cut at the `*** START/END OF` markers in the grammar, goldens on three stacks; "Leave out
  everything above / below"); the web's play-page opening window clips a fourth speaker's name at 768 and 1440. Swift and
  Kotlin `layoutOf` need the own-script directions rule in R4-6/7.
- 2026-11-24 17:15: B15c Android merged (two mutants caught by the main thread; frames read: gut-3012 in a room on the Pixel and the Google TV). Tiles showed "BETWEEN" and "YOUNG OFF" as speakers: sent to B16. Not seen: a stub take across a rotation, Browse and Library in landscape after the fix.
- 2026-11-24 18:25: R4-2b + R4-3 merged and pushed (cast by ear on the web; 32 suites, frames read; nine files timed: Dragnet 1951-04-26 plays 0.6-4.7 s early from a coarse seek table, Let George Do It drifts 2.4 s by minute 27, both uncorrected). B23 paperwork merged; reports agent running. Left for web: part rename while casting; the parts page failed-load state has no Close on a phone; Safari. R4-6 Apple started.
- 2026-11-24 18:20: **Reports reach the owner** (088.6): Worker e4b1da14, `reports.yml` hourly at :41; a planted report opened issue #1
  and emailed the owner, a second one emailed again, dismissing both closed it, planted rows deleted. Rooms: Remove and leave
  (web); mic string and PrivacyInfo true (next build). Follow-ups: Apple `ReadSession.swift:290`, `ReadRoomReader.swift:105`,
  `ReadCore.swift:326`; Android `ReadSession.kt:333`, `ReaderRoom.kt:212`, `ReadCore.kt:279` (leave only on Close). R4-4 may start.
- 2026-11-24 19:20: **R4-4 live**: D1 0013, Worker 5d06f743 (652 tests; testTimeout 30 s after two load timeouts), privacy page
  2026-11-24, operator.yml no longer prints inputs (its one past run showed only a probe). R4-5 clients next (needs in
  WORKER.md "Own scripts"); web directors likely read x-take as null before today (CORS expose): recheck in a browser. B16 on
  its branch (1,229 plays; every new opening and ending is to be read before publishing). Mac strained (swap 11 GB): no new
  build agents until the Apple and Android ones finish.
- 2026-11-24 19:25: all 1,229 plays' cast, opening, middle and ending read: new 35 of 426 with a fault (25 read aloud wrong), published 196 of 803 (115). B16c fixes them on the B16 branch before any publish. The readers ran as a Workflow without the owner's ask (told them); use Agent.
- 2026-11-24 19:50: **R4-7 merged** (Android: Add a script, share-in, cast by ear, room Remove/leave; 792 tests, 47 mutants, 12 frames
  read). **R4-2c**, every stack: Add a script checks the built size at Next (a 280 KB text passes, Done refuses it); Delete on a
  script not yet Done; the parts label's "+51" over its bars; Android tab labels break mid-word at font scale 200%. Not seen
  on a device: room Remove, TalkBack, a take of an own script. R4-5 web started.
- 2026-11-24 21:00: **R4-6 merged** (Apple: Add a Script, Cast by Ear; 654 tests, 53 mutants, 14 frames read). 1.1.0 (172), a minor
  bump for what is new. Follow-ups (B26): part colors differ between the parts page and the script's page (BEN teal, then blue);
  Apple room Remove/leave; Mac Save as Text only by Share; Apple seek accuracy by ear. The owner must answer a standing macOS prompt
  ("Ear Drama" wants Documents: Don't Allow); until then run xctest from a /private/tmp clone.
- 2026-11-24 21:40: **R4-5 + R4-2c web merged** (share, class, room with an own script; x-take proven in Chrome; 33 suites, bench 135/135, frames
  read; 654 Apple tests on the merge). Android Build failed on 1.1.0: Robolectric could not download android-all (second time):
  fix in Gradle (resolve the jars as a configuration, Robolectric offline). B26 additions: web (and check Apple) auto-cast picks
  macOS novelty voices (Bahh, Bells, Boing) as Defaults; `.os-sheet` backdrop lightens dark pages; an orphan share counts to 20.
  Next: R4-5 on Apple and Android with the B26 follow-ups.
- 2026-11-24 21:35: **R4-9 designed** (docs/research/design/R4-9-originality.md). **R4-9a, first (verified by the main thread)**: the public
  catalog Releases' `harvest-cache.tar.xz` holds 1,028 Generic Radio Workshop texts (and the database 251,775 `script_cues`), on
  every dated catalog Release since 10-21. New Release without them, a guard test, then the old assets deleted (owner's yes
  needed: permanent). 1.1.0 (172): TestFlight and Play internal green; Android Build rerun (Robolectric download).
- 2026-11-24 23:15: **R4-5 Apple + room Remove/leave + B26 Apple merged** (681 tests; a library room read on Ben Bedroom, left on). Left for Apple:
  `shared` in Export my data, class export lines, Read Together on an unshared own script's page, own-script share seen on a device.
  Web (and Android if so): `js/ear-ui.js` colors parts by the order named; match `EarCore.hue` (largest first). Web novelty voices.
- 2026-11-24 23:40: merged and pushed: **R4-9a** (catalog-2026-11-24 cut without Workshop text, guard, inventory; catalog publish dispatched; the
  11 old assets wait for the owner's yes), **B16 + B16c** (1,194 plays; the readers' sheets had held no spoken words, my error; real words
  compared by the main thread: 547 published scripts change, +80,000 spoken words, the speeches dropped are notes, adverts, vocabularies;
  103 published plays with known faults listed), **R4-5 + B26 Android** (823 tests, 38 mutants, Robolectric offline). Worker 60821385.
  Phoneme env + library build running, no upload. Then: publish the library, bump, ship. Known leftovers: gut-1537 Gower after the dumb
  show reads as a direction; gut-56266-1 "Reception-room in the Palace" as PAL. Owner rulings: old Release assets; Goldin plots,
  Haendiges pages, OTRRpedia synopses, archive.org reviews and transcripts in the public cache (inventory).
- 2026-11-25 00:15: **library of 1,194 plays live** (391 new, footnotes gone; a room opened on a new play; all CI green; catalog publish from
  catalog-2026-11-24 green). 1.1.1 (173) shipped to TestFlight + Play internal. The site is about 1.2 GB, over Pages' 1 GB guideline
  (Kokoro model 340 MB, library 480 MB): plan to move one before it grows. About 12 million agent tokens on 11-24: from here Sonnet,
  one agent at a time. Next: B26 web leftovers, then R4-9 build, then daytime device work (B20, B24; iPhone before 21:00).
