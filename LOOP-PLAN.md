# The 1.0 build loop

On October 22, 2026, with the research done and the repository set up, Ben
asked for this: *"We are starting the work of building out Ear Drama as a fully
functional web app and set of native apps across all of the platforms for which
it makes sense ... you will be drafting a robust autonomous loop that will build
out everything we need for a true version 1.0 of Ear Drama."* He answered the
open questions the same day, and his answers are Decisions 056 to 060 and
`catalog/DECISIONS.md` 004 to 007. This file turns them into work.

I want a loop I can walk away from and come back to, with every claim in it
true: shipped where it says shipped, verified only where a real device or a
re-downloaded artifact showed it, and honest about what is still open. So the
loop works in milestones that each end with something a person can play, and it
keeps building the next one while I play the last.

## Starting and resuming the loop

Type `/loop Read LOOP-PLAN.md and run the next tick`. The first tick runs at
once; after that a tick runs when a batch agent reports, with a 30-minute
fallback (owner, 2026-10-23, replacing the 5-minute cooldown of 2026-10-22).

Each tick reads, in order: this file; the Current State in `SCRATCHPAD.md`;
the last three entries of `AUTONOMOUS_PROGRESS.md` (create it on tick 1);
`docs/AUTONOMOUS-LOOPS.md` and the `autonomous-loop-cadence` skill on the first
tick of a session; then the platform page in `docs/platforms/` and any binding
design doc for the platform it is about to touch. A tick after a compaction
starts here too, because this file and the progress log are the loop's memory.

## How the loop runs (rewritten 2026-10-23)

The owner, after two session limits in one day: *"We have hit our session
limits multiple times, but it doesn't seem as though we are very far at all
... we need to be tackling significant work and not just running the same
checks each loop tick ... How can we rewrite the loop so that we are
optimizing token usage and also committing significant work with each
tick?"* Then: wake on results with a 30-minute fallback; Sonnet for ports,
Opus for design; and *"I want you to work on significant features before I
start testing them."*

**Wake on results.** A tick runs when a batch agent reports, or after 30
minutes (`ScheduleWakeup` 1800 as the fallback heartbeat). An agent's interim
"waiting on its own work" notice is not a tick: answer it in one line or not
at all. A session-limit stop schedules the resume for the reset time and does
nothing else.

**A tick is a batch merge, not a check.** When an agent reports:
1. CI: `gh run list -L 20`, anything red since the last tick fixed or
   explained first (owner, 2026-10-23).
2. Read the diff and the evidence; merge; confirm `MERGE_HEAD`; run each
   affected suite ONCE (`xcodegen generate` first on Apple, then compare the
   test count to the agent's); bump; PARITY in the merge commit; push.
3. Launch the next batch from "Feature batches" below, so one or two batch
   agents are always building.
4. One short report to the owner: what now exists that did not, what is not
   verified, what needs them. No per-merge narration, no holding-tick reports.
The main thread does not re-derive what an agent verified unless main moved
under it (`git log <base>..main -- <paths>`).

**A batch is a feature, everywhere.** One agent builds one significant feature
on every platform it belongs on (web, Apple, Android, and the data plane or
Worker it needs), or a backlog of three to five items, in one worktree and one
run. Never one agent per platform for the same feature: the shared reading is
paid once.

**Models.** Design, review, the data plane, the Worker, and hard bugs: Opus.
Porting a feature that already exists on one platform to another, mirroring a
rule, mechanical refactors: Sonnet (`model: "sonnet"` on the Agent call).

**Briefs are short.** Every brief points at `docs/AGENT-BRIEF.md` for the
standing rules (worktree, commits, verification, no simulators, US English,
On Air roles, the owner's calls not to make) and adds only the feature's goal,
its decisions, and its acceptance tests.

**Tokens** (owner, 2026-10-28: *"Are we being as economical with tokens on this loop as we
can be?"*): the main thread greps for an existing implementation before writing a brief;
Opus only for design, data-plane design and hard bugs, Sonnet for everything else
(plumbing, ports, docs, CI); a fresh session every ten ticks or so, since the state lives
here and in the progress log; reports to the owner stay short.

**Logs are short.** `AUTONOMOUS_PROGRESS.md` gets one entry per batch merged:
what exists now, the evidence, what is not verified. Lessons go to memory.

## Feature batches (in order; each is one agent, every platform)

**Current order (owner, 2026-10-28):** *"Yes, please start the loop with that
order and make sure you are proactively looking for things to fix and design
as you go through this loop."* Every agent reports, besides its feature, the
defects and design gaps it saw on the way (file, symptom, proposed fix); the
main thread fixes what needs no owner ruling in the next batch and lists the
rest under Needs Ben. A tick with no batch running mines PARITY, the binding
design docs and the device frames for the next fix before it ever stops.
P1. **Parity audit with fixes** (M10; `cross-platform-parity-discipline`):
   every row against the code, false cells corrected (e.g. `eardrama://` is
   marked ⏳ on iOS but SearchUITests opens it), missing rows added.
P2. **Harness: blind or perturbed means FAIL** (owner rule: an intermittent
   harness is a harness defect): `ios_uitest.py` fails a frame showing a
   system overlay (Screen Time's Time Limit passed a test 2026-10-27), and
   waits for the install to finish before the tests (a launch during a
   TestFlight-replacing install failed 2026-10-28).
P3. **Follow a series on Apple and Android** (the web has Follow and a
   Following row; Apple and Android store and sync follows with no control).
P4. **EmptyState and one-shot hints on all five** (PARITY ⏳ everywhere;
   essential words only, mobile-first-density rule 7).
P5. **tvOS Top Shelf**: the listener's Continue items.
P6. **Device tap tier for what is built and unchecked**: transcript search,
   a real Universal Link opening the app, lock-screen controls, icons,
   Android downloads and offline on the Pixel, tvOS focus and Now Playing.
P7. **Zero warnings in clean Release builds everywhere** (M10).
P8. **The first launch after a new install or a catalog publish quits** (seen
   2026-10-28 at 10:18 AM and 3:55 PM on the iPhone 12, each the phone's first
   launch after a publish or install): XCUITest launches the app, Home draws its
   loading placeholders, and ~3 s later Springboard is back; no EarDrama .ips; a
   JetsamEvent at the same second names tipsd and batterytrapd, not the app; the
   next launch passes. Not explained. Diagnose before any fix: the app's console
   from `devicectl device process launch --console` on a fresh install, and the
   device log at the exit; a user updating from TestFlight may meet it.
   Seen 4 times by 4:36 PM (each the first XCUITest launch after an install);
   NOT seen at 4:49 PM on a fresh Debug-over-Release install, nor on three
   Release launches by devicectl. **Diagnosed 2026-10-28 evening: not the app.**
   Every logged case (10:18, 3:55, 4:35) is SearchUITests' first
   `app.open(URL)` of the run, 5 s after a normal launch to idle: XCTest ends the
   running app ("Automation session connection to pid N interrupted"), the
   device starts no new process ("The process identifier of the launched
   application could not be determined", CoreDeviceError 10004), and Springboard
   shows. The app's captured output just stops; no process follows it. Not
   reproduced in 7 XCUITest runs on changed bundles nor 8 devicectl
   install-launch-URL-relaunch rounds. tools/ios_uitest.py now names it
   (BLIND launch_dropped) and keeps the device diagnostics xcodebuild was
   losing (no devicectl on its PATH). Device-side cause still unseen: the next
   occurrence carries its logs.
P9. **Android lint, then gate it** (P7 found lint never enforced: 10 errors,
   9 UnsafeOptInUsageError in PlaybackService.kt and CatalogLengthSeeking.kt,
   1 MissingIntentFilterForMediaSearch; 71 warnings). After the casting batch
   merges (both touch the player). The media-search intent is a voice-search
   feature: owner call. Merged 1.0.86 (lintRelease gates Android Build).
V2. **Visual pass, all artwork** (owner 2026-10-28: "Portraits should show wherever
   they are useful or joyful", then "The visual pass should be for all artwork. We
   want the app to be as visual as possible."). Merged 1.0.86. The remaining
   artwork sources (LoC, Federal Theatre, NPG CC0, magazine photos, undated
   matches) are closed by RESEARCH §12 V1-V5, the owner's rights questions.
V3. **Artwork of mixed shapes, from a design skill** (owner 2026-10-28: "I think
   you can find better solutions for different aspect ratios of images, then just
   blurring and black bars. As I said, anything that needs to be designed will
   require a design skill and you need to either research or build that skill."):
   research and write `artwork-presentation-design`, then redesign V2's slots on
   all five from it. Running.
A1. **Episode ids forward to their successor** (owner 2026-10-28: "Let's just get
   everything set up the way that we want it to be. We don't have to worry about
   current users, but we do have to worry about building for the future."):
   aliases and tombstones written every publish, resolved in one place per client.
   Running.
P12. **Replace or remove a published take** (owner 2026-10-29: "We don't want to provide a
   pathway for people to delete and re-upload a full recording?"): a performer can replace
   their take in a published production with a new one, or remove it, through Ear Drama's
   archive.org account (the Worker's uploader); the consent text says copies others made
   cannot be recalled. After P11 merges and once the archive.org account exists.
P16. **Published-production polish** (seen in P15): the Worker's record carries per-line
   archive state (`archive.lines`), so "Removed" survives a reload; "Open part" is
   disabled once published; the director's removal reason starts empty and must be chosen.
   Owner, 2026-10-29: *"Account deletion should definitely not remove their recordings from
   already submitted works. That would be nightmare to keep track of that. And community
   audio is just fine, as long as we are doing a good job of labeling the ear dramas within
   archive.org."* Account deletion leaves published items as they are; items stay in
   opensource_audio; the item labels make Ear Drama productions findable there.
P10. **Seen on the way (V2)**: RadioScreen.swift's evening-slot tile sits on
   a fixed `+ 14` offset that drifts with Dynamic Type; align to the time's
   first line with a scaled metric.
N1. **Play on another speaker or screen** (owner 2026-10-28: "native sharing
   like airplay or casting"). Merged 1.0.85.

Earlier batches (2026-10-23 to 2026-10-27; built unless marked):
Owner, 2026-10-23: build significant features before asking them to test.
0a. **The owner's rulings, listening side** (Decision 067): on-device volume
   leveling in every player (no per-file loudness; the measuring workflow is
   off); a serial plays to its arc's end, then one episode plus the queue until
   arcs exist; a Listen Together guest may pause and catch up; Tonight shows any
   evening with a surviving program, gaps name the matched series, and a
   listener may pick another year for the date; a popularity shelf from
   archive.org's download counts. (Search in More is superseded by 068.)
0b. **The owner's rulings, plays side** (Decision 067): listen-through with
   live device or on-device openly licensed voices for unrecorded parts (never
   stored); parts in any order, largest suggested; Export whenever complete;
   recording requires sign-in; Personal Voice offered live; commercials as their
   own parts; "author died by 1955" accepted in script_rights (C9), then the
   bundle rebuilt; plays marked only by facts from their records.
V. **Pictures for the shows** (owner 2026-10-24: "I don't see any images or
   artifacts from the shows yet"): evidence-backed portraits and typographic
   cards in the data plane and on every platform. Running 2026-10-24.
S. **The shell is actions** (Decision 068): Home, Browse, Stations, Surprise,
   Search, Library, placed as Archive Watch places them; no Plays section;
   "Start an ear drama" on any page whose item has a script; Library lists
   the person's ear dramas. Running 2026-10-24.
R. **Scripts for radio episodes** (068): which served episodes have a script a
   person may record from (rights by catalog rules; GRW only after they
   answer), as a `script` link in the data plane so "Start an ear drama"
   appears on those episodes and Browse's "Has a script" filter finds them.
1. **Plays phase 2 in the apps** (M8): resume the stopped web and Apple agents
   (their work is saved in their worktrees), then Android on Sonnet as a port
   of Apple's. Invite links, relay claims, uploads, report/block, consent
   step, classes.
2. **Downloads and offline listening** (R17, the car and bedtime): download an
   episode or a whole series run, play with no network, storage shown and
   cleared, on Apple and Android; the web's offline shell already exists.
   Opus on Apple first, Sonnet port to Android.
3. **Radio's genre channels** (R10, Decision 058): `channels.json` from the
   pipeline on the one clock, and a channel row on every Radio tab; the
   evenings already ship.
4. **People and casts** (`withPerson`): a person's page with every episode
   crediting them, cast lines on Detail as links, people in search.
5. **Serial arcs and commercials** (R3, R8): a runs table in the data plane so
   a serial plays to its arc's end and stops; commercials as chapters, never
   skipped. Needs the owner's queue rule (SCRATCHPAD item 9) before the
   play-on part ships; the data work does not wait.

## Standing rules for this app

These are the owner's, gathered from Decisions 055 to 060 and the memory
folder, so no tick has to re-derive them.

- **Rights.** Unclaimed recordings are kept and removed on request, and no
  client ever calls them public domain; their rights line says no claim is
  known and that they are removed on request. No paid license. A take-down
  takes effect at the next build. Every new claim source is a hide bucket with
  a test and a broken control.
- **The public-web gate.** Unclaimed (`keep_unclaimed`) episodes are not served
  on the public site until the DMCA agent is registered (Needs Ben). Until
  then, eardrama.org shows the clean pools only, behind one flag in the data
  plane, never a per-client filter.
- **No AI-written lists or copy in the product.** Shelves, blurbs, genres, and
  evenings come from data or a human editor. Store copy and asset words are
  drafted by the agent and ship only after the owner approves them (060).
- **Only essential words on screen**, US English, no emojis.
- **Real devices only**, never emulators or simulators for a "verified" claim
  (the simulator may compile and smoke-test). Check an Apple TV is on before
  any command; never sleep a test device; never kill the owner's running app;
  stop every test you start and verify that it stopped; clicks on the owner's
  Mac only when they are away, aimed from the element's accessibility frame.
- **The machine is the owner's.** Each tick starts with `uptime` and `pgrep
  launchd_sim`; a stray simulator or a load far above the core count is
  surfaced at once. Agents never boot a simulator unless they shut it down in
  the same step, run builds in the background with short foreground commands,
  and prove no simulator or Gradle daemon is left before they report (2026-10-22:
  an agent's simulator drove the load to 852 for three hours).
- **Ask before an audible run.** Every test door is muted, and playback is
  proven by tap metering under mute wherever the harness can read it. A run
  that must play sound aloud on the owner's machine or a device in their room
  is asked for first, kept short, and named in the log.
- **Vary the test content.** Prove each player feature on at least three
  series of different kinds (an anthology, a serial, a comedy) and two sources
  (OTRR and LibriVox), never the same episode every time.
- **Public Xcode only**; release builds run in CI; warnings are defects, so
  report the count from a clean build on every platform and aim for zero.
- **Ship mechanics** follow `docs/CLOUD-SUBMISSION.md` and
  `docs/APPLE-SUBMISSION-CLI.md`. For 1.0, Apple builds go to TestFlight and
  Android to Play's internal track; no public store release before the owner
  says so. No new Play upload while one is in review.
  Owner, 2026-10-28: *"We aren't live on anything. You need to keep pushing to
  update everything, including database."* Every merge goes all the way out:
  main (site), a new cache Release when harvest caches change, a catalog
  publish, and the App Store upload after the iPhone 12 launch check.

## Milestones

`[~]` marks an item built in part, with what is missing in the parentheses.

Each milestone ends at a **play gate**: a build on TestFlight or Play internal
(or a page on the live site), and a "Ready for you to play" entry at the top of
`SCRATCHPAD.md` that says what to try, on which device, and what would count as
broken. The loop moves on while the owner plays. A milestone is *verified* only
after the owner has played it; until then it is *built*.

### M0. Foundations

- [x] PARITY.md §0 records the platform set (core five, the stubs as ⏳ columns
      with Decision 056 as the reason), and a row for every 1.0 verb below.
- [x] (push runs seen: Android Build and Site deploy started on push for 1.0.92, runs 40808191235 and 40807437426)
      Confirm that a push triggers CI (the open question in the scratchpad):
      push an `android/` change and watch Android Build start on its own.
- [x] The generated project is named for the app: rename `AppName` in
      `project.yml`, `xcodegen generate`, unsigned builds for iOS, tvOS, and
      macOS, the Core tests, and an Android debug build, all warning-free.
- [x] (the owner picked On Air from the Human Shaped directions, tick 60, Decision 064;
      research in `docs/research/palette/`; the three-direction comparison page was not needed)
      **Palette and genre research** (060). Read the Human Shaped color work
      (`humanshaped-site/design/research/`, `design/directions/`,
      `design/round-2/`, `design/round-3/`, its DECISIONS.md, and
      `UniversalAppTemplate/docs/platforms/design-system.md`), the brand
      research (09 §4), and the genre needs (05 §3.3). Propose three palette
      directions, each with a new eight-hue genre set, WCAG AA checked in both
      modes and clear of each other by CIEDE2000. Render each on a real listen
      screen, a series page, and the player, light and dark, at 375 px and on
      a TV frame, and publish them as one comparison page for the owner.
      **Owner picks.**
- [x] (04c2578, tick 60, then `color.genre` in tick 61; Design Tokens CI green, run 40796824136)
      On the owner's pick: `design-tokens.json`, `node tools/design_tokens.mjs`,
      `node tools/test_design_tokens.mjs`, and every platform built and looked at.
- [x] The icon from the ring microphone (09 §2.3, candidate 1): a cut-out on a
      flat ground from the brand palette, a tvOS parallax stack, an Android
      adaptive icon with a monochrome layer, generated dark and tinted iOS
      variants, every size from `tools/render-app-icon.py`, and each one read
      at its real size before it is called done. (iOS default, dark, tinted and
      the Android layers come from the script; the Mac grid and tvOS layers
      from their own SVGs in `branding/`, commit 05c046f. Not yet seen on a
      device.)
- [x] Fonts: Big Shoulders and Public Sans self-hosted for the web, with their
      OFL files; system faces for body text on Apple and Android. (Big Shoulders
      Bold also bundled on Apple and Android for L1/L2, per Decision 060;
      `tools/build_fonts.py`, `font` in `design-tokens.json`.)

**Play gate:** the comparison page, then the tokens and icon on every platform.

### M1. The data plane

The clients read one published plane and re-derive nothing
(`shared-data-plane-contract`, `web-catalog-data-layer`,
`content-corpus-derivation`, `evidence-gated-catalog-curation`).

- [x] Restore the catalog from the `catalog-2026-10-21` Release and run all ten
      catalog test suites; record the counts as MEASURED with the date.
- [x] The CCE drama renewals reach the audit (catalog 004): already wired in
      `build_db.py`; 469 + 1,703 episodes hidden in the snapshot (tick 5).
- [x] Add the stricter music bucket and the AFRS credits rule (006), and the
      version ranking (007), each with a paired test and a control seen to fail
      (ticks 6-8).
- [x] Write `docs/CATALOG-CONTRACT.md` (v1 tick 9; updated with the publish step, tick 22): series, runs and their kinds, broadcast
      seasons, episodes, recordings and versions, people and credits, images
      with their evidence, transcripts, evenings, the rights line, and the
      `keep_unclaimed` publication flag. Test the documented shape against the
      real published artifact.
- [x] (built, tick 22; first GitHub run waits on the Pages switch) The publish step: the catalog source and SQLite to a GitHub Release
      (`catalog_release.py`, `sqlite_publish_guard.py`, `catalog_delta.py`),
      and the web's static index and shards on Pages. Every writer additive and
      merge-guarded; a run that read nothing goes red.
- [x] (seasons in the projection, tick 11; summer replacements as their own run wait on a runs table) Broadcast seasons computed in the pipeline (058), with summer
      replacements as their own run.
- [x] (sample done; target -21 LUFS, Decision 061; the whole catalog still to measure in CI) Loudness: measure a 200-file sample with ffmpeg `ebur128` and confirm the
      playback target near -18 LUFS, then measure the playable catalog in CI and
      store the gain. Never re-encode or re-host.
- [x] (gate fixed, Decision 058, tick 18) Transcripts: measure the quality of archive.org's speech-to-text on a
      sample across series and decades, set the on-screen gate from the
      measurement, and record the number in Decision 058.
- [x] (built and measured, tick 33; floor 0.25 awaits the owner; publishing in progress) Evenings: build Tonight in 19xx from the newspaper listings (05 §4),
      measure coverage over real evenings, set the floor from the numbers, and
      publish the evenings and the genre channels on the one clock.
- [x] (genres.py, tick 14; 69% of served episodes) Genres mapped from data (archive.org subjects, log genres, Wikidata) to
      the new hue set; never from a reading of the title.
- [x] (C2, 2026-10-28: `workflow-health.yml` daily 07:13 UTC and `retry-infra-failures.yml` at :07 and :37 are on;
      catalog-publish runs daily on cron, six scheduled successes 2026-10-23 to 2026-10-28, and catalog-transcripts is on cron)
      The catalog workflows on a schedule, with `workflow-health.yml` and
      `retry-infra-failures.yml` on (`ci-fleet-engineering`).

**Play gate:** a short report of what the published plane holds, with links to
five episodes the owner can open in a browser.

### M2. The web app: listening

The web goes first, because it is the landing twin for every share link and
the fastest to see. Seed `docs/WEB-DESIGN.md` from the template at five views
and bind to it.

- [x] (built as Home, Browse, Stations, Search, Library, Decision 068; web tests ok and seen in headless Chrome
      at 375 and 1440 px, ticks 99-104; PARITY cells stay 🚧 where no device has run them)
      Listen (Continue, Tonight in 19xx, This Day in Radio, shelves by rule),
      Series (genre, network, decade, kind; runs, then seasons, then episodes,
      oldest first, R1), Episode detail (date, network, sponsor, cast, writer,
      versions, other performances, rights line), Search (titles, people,
      transcript text, dates), Library (on the device until M5).
- [x] (built, ticks 16 and 27; device play pending) The player: background play where the browser allows it, Media Session,
      speed, skip, the sleep timer that offers "end of this episode" first and
      fades (R20), serials that stop at the end of an arc (R3), commercials
      chaptered and never skipped (R8), loudness gain applied at playback.
- [x] (built as Stations, ticks 25 and 99; PARITY Stations row; device-checked on the iPhone 12, 2026-10-27)
      The Radio tab on the one clock, local time drawn, the Eastern air time
      shown as a fact, and gaps stated (R9, R10).
- [x] (built, tick 36) Transcripts beside the audio where they pass the gate, labeled automatic.
- [x] (built, ticks 16 and 22) Every surface with its loading, empty, error, and offline states; every
      control labeled, and the first screen usable without sight (R21).
- [x] (built, tick 22; owner placeholders) Site pages: the take-down request route, the DMCA notice, credits to
      OTRR, RadioEchoes, Goldin, and the archives, and the privacy policy.
- [x] (web routes and 404 forwarder, tick 16; native filters wait on store records) Deep links: every `eardrama://` path has its `https://eardrama.org` twin.

**Play gate:** eardrama.org, clean pools only until the DMCA agent is registered.

### M3. Apple: iOS/iPadOS, macOS, tvOS listening

One target, four destinations, the shared `Core/`. Seed `iOS-DESIGN.md`,
`macOS-DESIGN.md`, and `tvOS-DESIGN.md` as each passes five views.

- [x] (built, tick 18; device play pending) The M2 verbs, in each platform's own idiom: tabs on iPhone, a split view
      with menus and keyboard on the Mac (`macos-platform-patterns`), the
      focus-driven ten-foot layout on tvOS (`tvos-platform-patterns`,
      `ten-foot-detail-design`).
- [x] (built, tick 18; lock-screen artwork B17 waits on the icon) AVPlayer with the audio session, Now Playing and remote commands, lock
      screen artwork from the brand square when an episode has none (B17), the
      sleep timer reachable from the lock screen's app surface in one step.
- [x] (built, tick 26; device check pending) Downloads on iOS and macOS (never tvOS, Archive Watch Decision 099's reasoning).
- [x] (privacy manifest tick 26; VoiceOver labels tick 16, unchecked on a device) A privacy manifest, VoiceOver on every control.
- [x] (App Store build (cloud) succeeded from 2026-10-24, run 40132845448; 1.0.68 run 40583842946;
      1.0.92 run 40808331721, upload-only)
      The cloud build with `submit=false` first, then TestFlight.

**Play gate:** TestFlight on iPhone, iPad, Mac, and Apple TV.

### M4. Android listening

- [x] (built, tick 16, downloads tick 28; ANDROID-DESIGN.md not yet) The M2 verbs in Compose and Material 3 (`android-production-gotchas`),
      a Media3 session service, notification and lock-screen controls,
      downloads, TalkBack on every control. Seed `ANDROID-DESIGN.md` at five
      views.
- [x] (run 40808816813, 2026-10-28: versionCode 2, 1.0.92, committed to internal, completed; 548d2f7)
      `play-release.yml` to the internal track.

**Play gate:** Play internal on the Pixel.

### M5. Accounts and sync

- [x] (built 2026-10-23, tick 57; Decision 063; local tests only, not deployed)
      The Worker and D1 (057): Sign in with Apple and Google verified at the
      Worker, ported from Archive Watch rather than rewritten
      (`authentication`, `zero-cost-hosted-backend`), the token refreshed before
      every call, all of it through each platform's one API client.
- [x] (built on all five by tick 62; stubbed-Worker tests; no real sign-in yet;
      tvOS has Apple only) Sign-in on all five platforms, optional, never at first launch; history,
      queue, and follows sync through the Worker, with a status row showing the
      account, the last sync, the last error, and Sync now.
- [x] (built with sign-in; web path `delete-account/`) Account deletion on every platform, and the anonymous history kept when
      someone signs in.

**Play gate:** sign in on two devices from different ecosystems; pause on one,
continue on the other.

### M6. Listen Together

- [x] (built 2026-10-23 on all five, ticks 65-73; Decision 065; nothing deployed,
      not run on devices) SharePlay on iOS, macOS, and tvOS (`shareplay-activities`); Worker rooms
      for web and Android, ported from Archive Watch's rooms; the guest plays
      the host's copy (Archive Watch Decision 143).

**Play gate:** a room across an iPhone, the Pixel, and the web.

### M7. Plays, phase 1: pass the phone

- [x] (built 2026-10-23: 11 stage plays and 4 radio plays, Carlton; no GRW text
      ships, owner item C8) The script corpus: radio scripts and public-domain stage plays, each
      castable only when its own record carries the evidence (059), with roles
      parsed by the prototypes in `catalog/prototypes/scripts/`.
- [x] (built on iPhone, iPad, Mac, Android, and the web by tick 58; not recorded
      on a device) Record role after role on one device against live system-voice stand-ins
      that are never stored; mix locally; play the finished play back. Full
      recording on iPhone, iPad, Mac, and Android; the web with headphones
      only; TVs play back only (research 08 §5).
- [~] (run on the build 2026-10-23, PLAYS-DESIGN §1; its one defect fixed in
      f045f77; the owner's play is the check still open) The learning test before
      it ships, with the owner's play as the check.

**Play gate:** record a two-role scene on the iPhone and on the Pixel.

### M8. Plays, phase 2: invite links and classes

- [~] (Worker side built, Decision 066; clients on web, iPhone, iPad, Mac,
      and Android, batch 1 2026-10-24 and M8a 2026-10-28; Apple TV plays
      back and reports; never run against a deployed Worker) Invite-only
      productions by link through the Worker; roles claimed and
      recorded across devices; report, block, and filter (guideline 1.2).
      Uploads need no consent and Publish waits for the consent screen
      (Decision 072, TODO(M8-consent-screen)).
- [ ] The consent screen with the CC0 warning (059); the words go to the owner
      before the screen ships.
- [ ] Uploads to archive.org through the Ear Drama account, credits from data.
- [~] (Worker side built; the gate waits on the policy, PLAYS-DESIGN §11.6) Teacher
      classes with school consent for students under 13, behind the
      privacy policy that covers it.

**Play gate:** a production finished by two accounts on two platforms.

### M9. The stubs

- [x] (all built, ticks 39 and 42; none run on a device) CarPlay, Android Auto, Android TV and Fire TV, Roku, webOS and Tizen,
      watchOS, and Wear OS: each a target that builds in CI and launches to
      its first screen, its PARITY column ⏳ with Decision 056 as the reason.
      Use each one's platform skill; the car stubs keep to four tabs (R17).

### M10. 1.0

- [~] (missing: a final 1.0 audit; the P1 parity audit ran in tick 99 and the human-shaped review in
      tick 77, 43891cb, with the owner's HUMAN-SHAPED answers still blank)
      A full parity audit (`cross-platform-parity-discipline`) and a
      `human-shaped-review` pass, with everything they find fixed.
- [~] (missing: a recorded Release-config build on every platform; seen so far, tick 107: generic iOS and
      tvOS 0 Swift warnings, Android lintRelease clean, macOS 199 tests)
      Clean release builds on every platform with zero warnings.
- [~] (done: DMCA agent registered, `DMCA_AGENT_REGISTERED` true, catalog published daily; Play internal
      versionCode 2 and TestFlight uploads at 1.0.92. Missing: the owner's take-down email, still a placeholder
      in `js/site.js`, and a TestFlight build processed and installed on each Apple device)
      The public web serves the full audited catalog (the DMCA agent is
      registered), and the four native apps are on TestFlight and Play
      internal at one version.
- [ ] Store listings, screenshots, and text-bearing assets drafted for the
      owner's approval, ready for the 1.x public release.

**1.0 is done** when all of M0 to M10 are checked, every 1.0 row in PARITY.md
reads ✅ on the core five, and the owner has played each milestone's gate.
That is the loop's stop condition. The others: the owner says stop, three ticks
in a row break CI, or the backlog is empty after a fresh mine.

## Needs Ben

The loop never blocks on these silently. It lists what each one unblocks,
works elsewhere, and checks again.

| What | Unblocks | By |
|---|---|---|
| ~~Pick a palette direction~~ DONE 2026-10-23: On Air, Decision 064 (tick 60) | M0 tokens and icon | done |
| ~~Settings > Pages > Source: GitHub Actions~~ DONE 2026-10-23 (c76c602; Site deploy runs on push, latest green run 40807437388) | the web's data on Pages | done |
| ~~Register a DMCA agent at copyright.gov ($6)~~ DONE 2026-10-23: DMCA-1083942; `DMCA_AGENT_REGISTERED` true; the take-down page still wants the agent's details as registered | unclaimed episodes on the public web | done |
| Request the CarPlay audio entitlement (developer.apple.com/contact/carplay) | the CarPlay stub, later the car | now; Apple is slow |
| ~~Enable Sign in with Apple and Group Activities~~ DONE 2026-10-24 (the Services ID row below; `CODE_SIGN_ENTITLEMENTS` is on in `project.yml`, signed cloud builds upload). Still unseen: a real Apple sign-in or SharePlay session | Apple sign-in (M5), SharePlay (M6) | done |
| ~~Create the App Store Connect record and the seven signing secrets~~ DONE: cloud builds upload from 2026-10-24 (run 40132845448), latest 1.0.92 (run 40808331721) | TestFlight | done |
| ~~Create the Play Console app and the upload key~~ DONE: the app by the owner 2026-10-24; the upload key and the five repo secrets by the owner 2026-10-28 (`tools/setup_play_upload_key.sh`) | Play internal | done |
| ~~Apple Services ID and Google OAuth clients~~ Done 2026-10-24: Services ID `app.eardrama.signin`; Google clients for web, iOS/Mac, Android debug (`app.eardrama.debug`) and Android Play (`app.eardrama`, Play signing SHA-1); consent screen published; Worker audiences deployed; Apple entitlements on | sign-in | before M5's play gate |
| ~~A Cloudflare Worker and D1 for Ear Drama~~ DONE 2026-10-23: 78e2a4d (D1, migrations 0001-0003) and 095cbb4 (eardrama-api.benwilkoff.workers.dev, in `js/config.js`) | M5 to M8 | done |
| ~~An Ear Drama archive.org account and its S3 keys~~ DONE 2026-10-29: the owner set Worker secrets `IA_S3_ACCESS_KEY` and `IA_S3_SECRET_KEY` (listed by `wrangler secret list`); Publish opens when P14's uploader deploys | play uploads | done |
| ~~The take-down email address~~ DONE 2026-10-29: ben@learningischange.com (owner) in `js/site.js`; the take-down page's reply-time sentence is still the owner's (`<!-- OWNER -->` in takedown/index.html) | the take-down page | before the public launch |
| Approve the consent screen and store words | M8, M10 | as drafted |
| ~~Enable App Groups~~ DONE 2026-10-28: the owner signed in; `group.app.eardrama` registered in the portal and assigned to `app.eardrama` and `app.eardrama.TopShelf`; entitlements on | the Apple TV Top Shelf's Continue items | done |
| ~~Cut the cache Release with portrait sizes and face boxes~~ DONE 2026-10-28 by the owner: catalog-2026-10-28, 5 assets digest-matched | sized, face-cropped portraits | done |
| Free API keys for NARA, NYPL, and DPLA (V6) | more photos | any time; optional |

## Owner feedback

Feedback from play sessions goes here, newest first, and the next tick takes it.

- 2026-10-28: *"Graphics count just as much as photos."* A person's served image
  (Wikidata P18 with evidence) stays whether it is a photograph, cartoon, plaque or
  title card; no photo-only rule in art_policy.

- 2026-10-28: be proactive: look for things to fix and design while building (see Feature batches).
- 2026-10-28: "You are claiming things without verification all over the place": verify a device's state (lease file, a frame) before reporting it.
