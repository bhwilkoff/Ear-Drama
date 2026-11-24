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

- [ ] **B11 Follow-ups from the audit.** A full iPhone 12 tap-tier run on a build with 7ecdd3d8 (lists set
  aside and kept across a test's relaunch) to settle the pre-redesign iOS cells (SiteLinks via About, ShowArt,
  Browse, Detail/Person); a real-browser web pass (Safari on the Mac, Chrome on the Pixel) for web cells.
- [x] **B12 Catalog follow-ups** (6aefa199, publish dispatched). Roman numerals cased as words ("Henry Iii" -> "Henry III"); all-caps titles
  (Cisco Kid, Escape) only where certain (acronyms kept). Dry run first.
- [ ] **B13 Device follow-ups.** Duo Record "Plays" indent (when the Duo is home); Apple class review screen;
  Pixel empty-library door frame; Apple TV foot alignment frame.

## Waiting on the owner (never blocks the loop)

Android Auto: fill or hide the empty Stations and Browse tabs (needs a car-review release). 
Kokoro re-export for Android and web word marks; a read-only Cloudflare analytics token for a usage
check; N5 Stations day switcher (ask first); SCHOOL_CONSENT_POLICY; OPERATOR_TOKEN; H1-H4 sessions;
store words; radio-script rights rule; GRW request.

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
