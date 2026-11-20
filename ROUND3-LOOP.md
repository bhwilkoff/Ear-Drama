# Round 3 loop: a Home that reads as one thing, and reading plays together

On 2026-11-19 the owner set the next scope, in two parts (verbatim):

> 1. We need to continue making the app more visually appealing, both from the home screen
> perspective (which still reads like a long list of items that feel unrelated) and the individual
> item perspective. We have very few images that represent only a few Ear Dramas (radio shows,
> plays, news programs, and real recorded Ear Dramas). We need to do much better research for
> images and designs that could represent all of the different Ear Dramas throughout the app. On
> Archive Watch, we pull "hero images", posters, and many other types of visual representations of
> the movies. We should be able to do that for this app too (from wikipedia or any other public
> repository). We also can design default (or programatically generated) designs that could take
> the place of images that don't exist (or don't yet exist, anyway). The goal is to have the home
> view feel more cohesive and inviting from the moment that you open the app.
>
> 2. We theoretically have built the functionality for recording a play as a "class" with a
> "teacher" organizing the process, but that functionality really doesn't exist yet. We need to
> build out how a teacher actually would manage that process. We also need to build out how someone
> would do this with a bunch of different devices in the same room (whether a classroom of kids or a
> group of adults doing a table read). Ideally, all of this would work quite easily and would be
> fully tested on the many devices that you have access to for testing.

Also: "The apple tv version has been approved on the app store, but the iOS and macOS haven't yet.
I'm okay to keep building these apps while we wait for those two other platforms to be approved."

This file is the loop's memory. DESIGN-LOOP.md and LOOP-PLAN.md are earlier rounds; their open
items do not block this one.

## Research (done 2026-11-19, cited, read before briefing)

- `docs/research/design/R3a-visual-cohesion.md`: audio products, collections, era graphics;
  diagnosis of Home and Detail; three drawn-art options (sketch in `img/r3a/`); Home rules §4.1;
  build order §8.
- `docs/research/design/R3b-image-sources.md`: the current pipeline, Archive Watch's (TMDb and
  Fanart do not carry over), every open source with its evidence field, coverage and precision
  measured on 490 items (`docs/research/data/r3b/`), harvest stages H1-H9, matching rules §5.2,
  projection fields §5.5.
- `docs/research/design/R3c-table-reads-and-classes.md`: audit of classes, productions, Listen
  Together and the reader (file:line); table reads, Readers Theater, classroom join flows, same-room
  audio; four modes; teacher and student flows; transport (§5.1), data model, Worker changes; failure
  states; real-bench test plan §8. **Its R2 recommendations are superseded** by the rulings below.

## Owner rulings, 2026-11-19

1. **Drawn art: option C, "the label"**: a flat transcription disc drawn from each item's own data
   (genre board color, an arc on a 1930-1962 dial for the run, monogram or air date on the label,
   network and decade on the rim at large sizes, cast part colors on a finished ear drama). R3a §3.4.
2. **Home: all of R3a §4.1**: On the air is the lead object with a row of genre stations under it;
   the doors become two quiet buttons; every rail one window size and one art system; a show at most
   once per Home; two inks per screen; Today's scene a normal wide card, not a slab.
3. **Classes bundle**: a class owns a production, visible only to its seats; parts a teacher assigns
   may all record at once (elsewhere the one-part relay stays); a seat (a name the teacher typed)
   records without an account, its takes belonging to the teacher's account; one cross-platform read
   room, no SharePlay.
4. **Storage is archive.org, never Cloudflare**: "We are using archive.org for storage, not
   cloudflare. We already decided that teachers could upload the full recording under their name."
   No R2, no audio at rest in a Durable Object or KV.
5. **Takes pass through**: each device records its own lines; a take passes through the Worker to
   the teacher's (leader's) device during the session and is deleted the moment it arrives. Relay
   at home works only while the receiving app is open (or the take waits on the student's device
   and sends when both are present).

### Answered from our rules (not asked)

- Image evidence (catalog rule: an image is used when its own record carries the evidence):
  LoC "No known restrictions on publication" is the record's own statement: **usable** (V2).
  Smithsonian NPG CC0: **usable** (V4). Federal Theatre Project photos with no rights sentence:
  **not usable** (V3). A series' run years from its own enwiki article (the item's sitelink), source
  recorded: **usable as identity** (V10).
- Images stay hot-linked from Commons with H9 liveness checks and fallback; no mirror (ruling 4).
- Networks and sponsors: names in our type, never logos (trademarks; R3a §1.4) (V8).
- User-made ear dramas: the drawn label only; no uploaded pictures (V9).
- Under-13 class work: never published publicly; the teacher uploads the full recording under
  their own name only for classes marked 13 and over, with the CC0 consent; an under-13 class
  exports a file (Decision 059's school route stays blocked until P5).

### Waiting on the owner (never blocks the loop)

- **V1** serve undated person matches (about 1 in 30 wrong)? **V5** magazine pages from unrenewed
  issues on the issue's evidence alone? **V6** free API keys (NYPL, DPLA, NARA) need an account.
- **Privacy policy words (P5)**: shared productions, seats, classes, school consent, a written
  retention rule (R3c recommends: class takes deleted with the class; an inactive class deleted
  after a school year, with notice), and whether to sign the SDPC data privacy agreement.
- **Hands-on sessions** (audible, ask first): H1 table read with 4-6 people, H2 record in the room,
  H3 classroom pilot, H4 accessibility (R3c §8.2).

## Binding constraints

Everything in AGENTS.md, plus: feature parity with native idiom on web, iOS/iPadOS (incl. the open
Duo), macOS, tvOS, Android (incl. Google TV); fix the binding design doc first; only essential words
on screen; no AI-written copy; the agent is never the tester (real devices, never simulators or
emulators; ask before anything audible; muted doors); design work on Opus with the design skills
(`artwork-presentation-design`, `uniform-imagery-design`, `catalog-experience-design`,
`mobile-first-density-design`); ports and plumbing on Sonnet; one agent at a time on overlapping
code; the main thread reads every frame before a merge.

**Shipping while iOS and macOS are in review**: commit and push every verified batch (bump patch +
build). TestFlight builds are fine. Do not submit a new App Store version until iOS and macOS are
approved (`tools/asc_release.py status`); then ship the latest on all three Apple platforms. Android:
no new Play upload while one is in review. Web deploys on push.

## Tracks and batches

Two tracks run side by side (one agent each; they touch different code). A batch builds its feature
on every platform it belongs on, web first, then Apple and Android ports in the same batch or the
next. Check a box only with evidence (suite counts, frames read, device runs).

### Track V: visuals

- [x] **V0 Docs and decision (Opus).** Decision 081 (label art + Home rules, from rulings 1-2 and
  R3a). Amend WEB-DESIGN §4.2/§6, iOS-DESIGN, macOS-DESIGN, tvOS-DESIGN, ANDROID-DESIGN Home and art
  sections, and the `artwork-presentation-design` skill's default-art section, before code. PARITY.md
  rows for label art, Home composition, hero/gallery/title page, each ⏳.
- [x] **V1 Pipeline: identity and network (Opus, data plane).** `series.network` (one normalized
  primary network, with source); H1 wider identity (name variants in one SPARQL batch, enwiki
  `wikibase_item`, V10 run years from the article); matching rules R3b §5.2 each with a guard seen to
  fail (TV/film twins, topic-not-show, file date outside the run, org by QID). Dry-run on real data
  before publish; catalog change runs the client suites.
- [ ] **V2 Pipeline: more real images (Sonnet after V1).** H2-H4 (Wikidata, enwiki lead image only
  when free and on Commons, Commons by name with categories), H7 plays (edition title pages pre-1931,
  author portraits, work P18), period sponsor ads; H9 liveness with fallback. Projection fields
  `series.hero`, `series.gallery`, `play.titlePage`, `play.authorArt` (R3b §5.5) in
  CATALOG-CONTRACT first. Report coverage per kind against R3b's baseline.
- [x] **V3 The label, web (Opus).** `art.label` tokens in design-tokens.json and the generator;
  pure `labelSpec(item)` with golden cases; drawn for series, episodes (date on the label), people
  (groove ring), finished ear dramas (part colors), plays (script page + voice marks); 56 px to TV
  hero, light and dark. `web_fit_home.py` checks.
- [ ] **V4 The label, Apple and Android (Sonnet).** Same goldens pass in Swift and Kotlin
  (`cross-platform-determinism`); drawn natively (SwiftUI Canvas, Compose Canvas); tvOS hero; lock
  screen and Now Playing art per episode.
- [ ] **V5 Home composition, web (Opus).** R3a §4.1 rules 1-8; the hero is the largest window on the
  first screen; no rail opens on the show above it; a show at most once. Frames at 320-1440, light and
  dark, read by the main thread.
- [ ] **V6 Home composition, Apple and Android (Sonnet, Opus review).** iPhone, Duo open, iPad, Mac,
  Apple TV (focus does the work), Pixel, Google TV.
- [ ] **V7 Detail pages (Opus web, Sonnet ports).** Series, episode, person, play pages with R3a §4.3:
  hero or label, gallery when there is one, an episode's own label, the recordings section quieter.
- [ ] **V8 Visual audit on every device (Opus).** Every screen touched, light and dark, the 56 px
  row tile on the iPhone 12 and the Duo, a TV hero across the room; faults fixed on every platform.

### Track T: reading together

- [x] **T0 Docs and decision (Opus).** Decision 082 (read rooms and classes: rulings 3-5; a Durable
  Object per read room for the live cursor, which reverses Decision 065's reason for read rooms only;
  the pass-through take path, nothing at rest; teacher uploads the full recording under their name;
  supersedes 066's R2 take store). PLAYS-DESIGN §12 "Reading together"; tvOS-DESIGN §4.13 and the
  Android TV panel rule gain the cursor-driven screen and pairing code; PARITY.md rows (four modes,
  seats, casting board, review, shared screen); SCRATCHPAD Out of scope rows (R3c §9 list).
- [x] **T1 Worker read room (Opus).** Pure `read-protocol.js` (cursor, lead, parts, late join,
  leader gone, claims) with goldens; `ReadRoom` Durable Object over WebSockets plus the D1-polling
  fallback carrying the same messages; rate limits keyed by member or seat (a class behind one
  address); max 40 members. Tests T1-T3 (R3c §8.1), each rule's mutant seen to fail.
- [x] **T2 Worker classes (Opus).** Seats (add from a pasted list, claim by code + name, release),
  class productions, assignments (several parts record at once), review (Approve / Again, typed
  notes), progress counts; take pass-through (sender to leader, deleted on delivery, refused if no
  receiver is present); teacher publishes the full recording under their name to archive.org via the
  existing uploader (073), 13+ classes only. Remove the R2 path from class flows.
- [ ] **T3 Web client (Opus design).** Join a read room by code (no account for seats), follow the
  lit line, I'm playing + Hide my lines, lead controls (Next, keys), the shared screen
  (`?screen`), the teacher's class page (seats, casting board with line counts and Fill evenly,
  progress, review queue), Table read and Rehearse modes. Frames at 375 and 1440.
- [ ] **T4 Apple and Android clients (Sonnet).** Same verbs, native idioms (R3c §5.4): iPhone, iPad
  drag-to-cast, Duo outer display line, Mac windows and menu, Android; Apple TV and Google TV as the
  shared screen with a pairing code (record nothing, rule 12).
- [ ] **T5 Record in the room (Opus web, Sonnet ports).** Only the device holding the current line
  records; takes pass through to the leader; the leader's mix and Listen through; the teacher's
  full-recording upload; failure states R3c §6.
- [ ] **T6 Relay across time (Sonnet).** Assigned parts at home; takes wait on the student's device
  and pass through when the teacher's app is present; teacher progress list.
- [ ] **T7 The bench (Sonnet, then Opus for failures).** Launch doors on every platform
  (`APP_START_READ_ROOM`, `APP_START_SEAT`, `APP_START_SCREEN` and twins); one orchestrator opens a
  room on a staging Worker across iPhone 12, Duo, iPad, Mac (only when the owner is away), Apple TV,
  Pixel, both Google TVs, Safari and Chrome; T4 cursor-delay gate (p95 under 300 ms on the socket);
  T5-T12. Muted, stub microphones, never a simulator.
- [ ] **T8 Owner sessions (owner).** H1-H4, asked for when T7 passes.

## Order and gates

Tick 1 launches V0+V1 (one Opus agent) and T0+T1 (one Opus agent). Then each track takes its next
box when its agent reports and the main thread has merged and verified. V3 waits on V0; V5 on V3;
T3 on T1+T2; T5 on T3; T7 starts when T3 exists and grows with each client. An owner answer (V1, V5,
privacy words) is folded in when it arrives, never waited on.

## Every tick

1. `gh run list -L 10` (fix or explain red first); `tools/asc_release.py status` once a day.
2. Read this file's State. Grep code and `git log` for the feature before any brief (memory: loop
   token economy). Brief through `docs/AGENT-BRIEF.md`, with what exists, the research section, the
   rulings, the verify list, and "no simulators, muted, stage explicit paths".
3. Merge a reported batch, run each touched suite once (web, catalog, Worker, macOS tests + iOS/tvOS
   builds after xcodegen, Android tests + lintRelease), read the frames, bump, commit `-F`, push.
4. Update State and log one entry in AUTONOMOUS_PROGRESS.md.
5. Announce the next tick time (Mountain), then schedule: wake on agent results, 30-minute fallback.
   Stop when only owner items remain, and list what unblocks the rest.

## State

- **2026-11-19, tick 0**: research merged; rulings recorded; nothing built. iOS and macOS in App
  Review; tvOS approved (owner). `asc_release.py status` needs this repo's own ASC env (the
  classifier refused borrowing Archive Watch's credentials file); ask the owner where it lives.
- **2026-11-19, tick 1**: DECISIONS 046-065 rolled (43 KB). Running: V0+V1 (Opus, worktree),
  T0+T1 (Opus, worktree). Next: merge each when it reports, then V3 (after V0) and T2.
- **2026-11-19, tick 2**: T0+T1 merged (4fa85f7; Worker 341/341 on main; not deployed: needs the
  full mutation run, then `wrangler deploy` + D1 migration 0006). V0+V1 on its branch with a
  dry-run fix; official catalog dry run running before merge (the agents' runs were killed for
  memory: run heavy jobs one at a time). Running: T2 (Opus). Owner question added: should rule 4
  accept a show's own Wikidata picture of its star when our records credit no one on it (~9 images)?
- **2026-11-19, tick 3**: V0+V1 merged (0ad8ba8) after the official dry run passed (contract tests
  and catalog suites over real data, 638 s); web 22 suites green. Android unit tests running for the
  catalog change. H1's names cache (`.cache/wikidata/names.json.gz`) is not in a cache Release yet:
  V2 cuts the Release with its harvest. Running: T2, V3 (Opus). Worker full mutation run waits for
  T2's merge, then deploy.
- **2026-11-19, tick 4**: V3 merged (abdf582, 1.0.139): the label on the web; frames read (sheet,
  Home 1440, series 375 dark). Android unit 555/555 on the catalog merge. Running: T2 (Opus), V4
  (Sonnet ports). Queued for V5: On the air shows a raw upload title ("AbyM #026 ...", rule: no raw
  upload text); tools/test_tv_compat.py fails on main (16 color-mix() outside @supports).
- **2026-11-19, tick 5**: T2 merged (0a2f150; Worker 378/378): seats, class productions,
  assignments, review, TakeRelay pass-through (memory only, ~64 KiB per transfer), R2 removed
  everywhere per Decision 082. Answered from rules: a seat's take is the teacher's, so the teacher's
  CC0 consent is the one asked; deleting a class keeps its published production listed (P16 ruling;
  T3 fixes). Full mutation run (247) running in a scratch worktree; then deploy (D1 migrations 0006
  + 0007 remote, wrangler deploy: READ_ROOMS, TAKE_RELAY, limiters 8313-8318). Running: V4 (Sonnet),
  T3 (Opus). Note: invite productions' members can no longer hear each other's takes from the Worker
  (it was always 503 in production); T3/T4 move clients to the inbox.
