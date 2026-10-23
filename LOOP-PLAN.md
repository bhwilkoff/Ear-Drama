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
once, and each tick ends by scheduling the next one five minutes after it
finishes: a cooldown, never a wall-clock cron (owner, 2026-10-22: *"Make sure
that loops run on a 5 minute cool down"*).

Each tick reads, in order: this file; the Current State in `SCRATCHPAD.md`;
the last three entries of `AUTONOMOUS_PROGRESS.md` (create it on tick 1);
`docs/AUTONOMOUS-LOOPS.md` and the `autonomous-loop-cadence` skill on the first
tick of a session; then the platform page in `docs/platforms/` and any binding
design doc for the platform it is about to touch. A tick after a compaction
starts here too, because this file and the progress log are the loop's memory.

## Every tick

0. **Check GitHub Actions first** (owner, 2026-10-23: *"I do occasionally get
   alerts that the github builds are failing. Can you check on that as a part
   of this loop?"*): `gh run list -L 40` for anything not green since the last
   tick. A failure is diagnosed from `gh run view <id> --log-failed` and fixed
   before new work, or logged with its cause when it is not ours to fix. A
   `pages-build-deployment` cancelled by a newer push is superseded, not
   broken: say so in the log rather than chase it.
1. **Take the next unblocked item** from the earliest open milestone in
   "Milestones" below, or from "Owner feedback" first when there is any.
   Feedback from a play session always goes to the top of the queue.
2. **Read the runbook before acting.** Grep `docs/`, `tools/`, and the memory
   folder for the task. Invoke the skill the AGENTS.md table names; before any
   new feature, run `learning-orientation-design`.
3. **Diagnose, build, verify, log.** One verified unit per tick, never an
   unverified fix stacked on another. Verification is external observation:
   the glass (window-only screenshots on the Mac), the published artifact
   downloaded again, the store's own API, tap-audio metering.
4. **Mirror the verb on every core platform** in the same milestone, update
   `PARITY.md` in the same commit, and mark a platform not yet reached ⏳ with a
   note, never silence.
5. **Commit and push** the verified unit with `git commit -F` and a quoted
   heredoc. App-source commits bump PATCH and build in `AppVersion.xcconfig`;
   MINOR goes up only for a release carrying something new. Docs, data, and CI
   commits do not bump.
6. **Log the tick** in `AUTONOMOUS_PROGRESS.md` (Context, Implementation,
   Verification, Lessons, Next) with the words *verified*, *fixed*, and
   *shipped* kept apart. A lesson that cost a CI cycle becomes a memory file.
7. **Announce, then schedule.** The last line is `Next tick: <time>` in
   Mountain time, written before the scheduling call.

**Rotation.** Inside a milestone that spans platforms, the least mature core
platform gets two ticks in five, and every fifth tick is an opt tick that must
net-remove lines. The first opt tick rolls `DECISIONS.md` (72 KB, past its
50 KB roll point) into `docs/decisions/`, verbatim, with an index.

**Scope per tick** (owner, 2026-10-22, after twelve small ticks: *"Are you
doing enough substantial work on each tick? It seems like every tick is such a
tiny scope of work."*). A tick is not one small item. Every tick (1) reads the
reports of the milestone agents running in their own worktrees, reviews each
finished branch's diff and evidence, and merges what is verified (bumping the
version and updating PARITY.md in the merge commit); (2) relaunches or redirects
an agent wherever one is idle, so the core platforms are always being built at
once; and (3) does a substantial unit on the main thread itself, normally the
data plane. A tick that only edits a doc is the exception, not the rule.

**Parallel work.** Two or three milestones may run at once, as the Human
Shaped site's loop did, through background agents in their own worktrees, each
merged only when verified. Data work (M1) and the web client (M2) overlap;
Apple (M3) and Android (M4) run side by side. An agent's summary is a claim:
read its diff and its evidence before merging.

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
- [ ] The icon from the ring microphone (09 §2.3, candidate 1): a cut-out on a
      flat ground from the brand palette, a tvOS parallax stack, an Android
      adaptive icon with a monochrome layer, generated dark and tinted iOS
      variants, every size from `tools/render-app-icon.py`, and each one read
      at its real size before it is called done.
- [ ] Fonts: Big Shoulders and Public Sans self-hosted for the web, with their
      OFL files; system faces for body text on Apple and Android.

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

- [ ] SharePlay on iOS, macOS, and tvOS (`shareplay-activities`); Worker rooms
      for web and Android, ported from Archive Watch's rooms; the guest plays
      the host's copy (Archive Watch Decision 143).

**Play gate:** a room across an iPhone, the Pixel, and the web.

### M7. Plays, phase 1: pass the phone

- [ ] The script corpus: radio scripts and public-domain stage plays, each
      castable only when its own record carries the evidence (059), with roles
      parsed by the prototypes in `catalog/prototypes/scripts/`.
- [ ] Record role after role on one device against live system-voice stand-ins
      that are never stored; mix locally; play the finished play back. Full
      recording on iPhone, iPad, Mac, and Android; the web with headphones
      only; TVs play back only (research 08 §5).
- [ ] The learning test before it ships, with the owner's play as the check.

**Play gate:** record a two-role scene on the iPhone and on the Pixel.

### M8. Plays, phase 2: invite links and classes

- [ ] Invite-only productions by link through the Worker; roles claimed and
      recorded across devices; report, block, and filter (guideline 1.2).
- [ ] The consent screen with the CC0 warning (059); the words go to the owner
      before the screen ships.
- [ ] Uploads to archive.org through the Ear Drama account, credits from data.
- [ ] Teacher classes with school consent for students under 13, behind the
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
| Register a DMCA agent at copyright.gov ($6) | unclaimed episodes on the public web | before M2's public launch |
| Request the CarPlay audio entitlement (developer.apple.com/contact/carplay) | the CarPlay stub, later the car | now; Apple is slow |
| Enable Sign in with Apple and Group Activities on the `app.eardrama` App ID, remake the profiles, then uncomment `CODE_SIGN_ENTITLEMENTS` in `project.yml` (the file `apple/Resources/EarDrama.entitlements` holds both keys) | Apple sign-in (M5), SharePlay (M6) | before either play gate |
| Create the App Store Connect record for `app.eardrama` and the seven signing secrets (`docs/CLOUD-SUBMISSION.md`) | TestFlight | before M3's gate |
| Create the Play Console app and the upload key | Play internal | before M4's gate |
| Apple Services ID and Google OAuth clients for Ear Drama (`docs/runbooks/google-oauth-setup.md`; Android needs clients for `app.eardrama` with Play's signing SHA-1 and the debug id; then the Worker steps in `docs/WORKER.md`, which include switching on the Sign in with Apple entitlement) | sign-in | before M5's play gate |
| A Cloudflare Worker and D1 for Ear Drama, or approval for the loop to create them | M5 to M8 | before M5 |
| An Ear Drama archive.org account and its S3 keys, stored as Worker secrets | play uploads | before M8 |
| The take-down email address, and the DMCA agent's details once registered (`js/site.js` TAKEDOWN_EMAIL; takedown/index.html) | the take-down page | before the public launch |
| Approve the consent screen and store words | M8, M10 | as drafted |
| Free API keys for NARA, NYPL, and DPLA (V6) | more photos | any time; optional |

## Owner feedback

Feedback from play sessions goes here, newest first, and the next tick takes it.

(none yet)
