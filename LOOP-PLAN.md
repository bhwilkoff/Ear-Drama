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

**Logs are short.** `AUTONOMOUS_PROGRESS.md` gets one entry per batch merged:
what exists now, the evidence, what is not verified. Lessons go to memory.

## Feature batches (in order; each is one agent, every platform)

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
- [ ] Confirm that a push triggers CI (the open question in the scratchpad):
      push an `android/` change and watch Android Build start on its own.
- [x] The generated project is named for the app: rename `AppName` in
      `project.yml`, `xcodegen generate`, unsigned builds for iOS, tvOS, and
      macOS, the Core tests, and an Android debug build, all warning-free.
- [ ] **Palette and genre research** (060). Read the Human Shaped color work
      (`humanshaped-site/design/research/`, `design/directions/`,
      `design/round-2/`, `design/round-3/`, its DECISIONS.md, and
      `UniversalAppTemplate/docs/platforms/design-system.md`), the brand
      research (09 §4), and the genre needs (05 §3.3). Propose three palette
      directions, each with a new eight-hue genre set, WCAG AA checked in both
      modes and clear of each other by CIEDE2000. Render each on a real listen
      screen, a series page, and the player, light and dark, at 375 px and on
      a TV frame, and publish them as one comparison page for the owner.
      **Owner picks.**
- [ ] On the owner's pick: `design-tokens.json`, `node tools/design_tokens.mjs`,
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
- [ ] The catalog workflows on a schedule, with `workflow-health.yml` and
      `retry-infra-failures.yml` on (`ci-fleet-engineering`).

**Play gate:** a short report of what the published plane holds, with links to
five episodes the owner can open in a browser.

### M2. The web app: listening

The web goes first, because it is the landing twin for every share link and
the fastest to see. Seed `docs/WEB-DESIGN.md` from the template at five views
and bind to it.

- [ ] Listen (Continue, Tonight in 19xx, This Day in Radio, shelves by rule),
      Series (genre, network, decade, kind; runs, then seasons, then episodes,
      oldest first, R1), Episode detail (date, network, sponsor, cast, writer,
      versions, other performances, rights line), Search (titles, people,
      transcript text, dates), Library (on the device until M5).
- [x] (built, ticks 16 and 27; device play pending) The player: background play where the browser allows it, Media Session,
      speed, skip, the sleep timer that offers "end of this episode" first and
      fades (R20), serials that stop at the end of an arc (R3), commercials
      chaptered and never skipped (R8), loudness gain applied at playback.
- [ ] The Radio tab on the one clock, local time drawn, the Eastern air time
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
- [ ] The cloud build with `submit=false` first, then TestFlight.

**Play gate:** TestFlight on iPhone, iPad, Mac, and Apple TV.

### M4. Android listening

- [x] (built, tick 16, downloads tick 28; ANDROID-DESIGN.md not yet) The M2 verbs in Compose and Material 3 (`android-production-gotchas`),
      a Media3 session service, notification and lock-screen controls,
      downloads, TalkBack on every control. Seed `ANDROID-DESIGN.md` at five
      views.
- [ ] `play-release.yml` to the internal track.

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

- [~] (Worker side built, Decision 066, 171 tests; no client yet) Invite-only
      productions by link through the Worker; roles claimed and
      recorded across devices; report, block, and filter (guideline 1.2).
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

- [ ] A full parity audit (`cross-platform-parity-discipline`) and a
      `human-shaped-review` pass, with everything they find fixed.
- [ ] Clean release builds on every platform with zero warnings.
- [ ] The public web serves the full audited catalog (the DMCA agent is
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
| Pick a palette direction | M0 tokens and icon | end of M0 |
| Settings > Pages > Source: GitHub Actions (CATALOG-CONTRACT §4) | the web's data on Pages | before M1's publish |
| ~~Register a DMCA agent at copyright.gov ($6)~~ DONE 2026-10-23: DMCA-1083942; `DMCA_AGENT_REGISTERED` true; the take-down page still wants the agent's details as registered | unclaimed episodes on the public web | done |
| Request the CarPlay audio entitlement (developer.apple.com/contact/carplay) | the CarPlay stub, later the car | now; Apple is slow |
| Enable Sign in with Apple and Group Activities on the `app.eardrama` App ID, remake the profiles, then uncomment `CODE_SIGN_ENTITLEMENTS` in `project.yml` (the file `apple/Resources/EarDrama.entitlements` holds both keys) | Apple sign-in (M5), SharePlay (M6) | before either play gate |
| Create the App Store Connect record for `app.eardrama` and the seven signing secrets (`docs/CLOUD-SUBMISSION.md`) | TestFlight | before M3's gate |
| Create the Play Console app and the upload key | Play internal | before M4's gate |
| ~~Apple Services ID and Google OAuth clients~~ Done 2026-10-24: Services ID `app.eardrama.signin`; Google clients for web, iOS/Mac, Android debug (`app.eardrama.debug`) and Android Play (`app.eardrama`, Play signing SHA-1); consent screen published; Worker audiences deployed; Apple entitlements on | sign-in | before M5's play gate |
| A Cloudflare Worker and D1 for Ear Drama, or approval for the loop to create them | M5 to M8 | before M5 |
| An Ear Drama archive.org account and its S3 keys, stored as Worker secrets | play uploads | before M8 |
| The take-down email address, and the DMCA agent's details once registered (`js/site.js` TAKEDOWN_EMAIL; takedown/index.html) | the take-down page | before the public launch |
| Approve the consent screen and store words | M8, M10 | as drafted |
| Free API keys for NARA, NYPL, and DPLA (V6) | more photos | any time; optional |

## Owner feedback

Feedback from play sessions goes here, newest first, and the next tick takes it.

(none yet)
