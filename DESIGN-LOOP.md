# The design loop: finding, listening, making, sharing

On October 29, 2026, Ben asked for a second loop, about design and display:
*"Almost everything in the app functions as a list of items with sparse
images/graphics and a lot more metadata being surfaced than is necessary. We
need to level up the individual content experience as well as the collection or
"list views" that show a series of items. We do this as beautifully crafted
shelves on Archive Watch, but I'm not sure that is the right metaphor for this
implementation. Can you do ensure that the loop does extensive research on how
to display large databases of content in pleasing and easy to use ways. I think
we may need entirely new design patterns and smart choices for what content to
surface to create an easy to use experience to find Ear Dramas, Listen to them,
Create them yourself, and share them with others."*

This file is the loop's memory. `LOOP-PLAN.md` still holds the build backlog;
this loop owns how the app looks and what it chooses to show.

## Starting and resuming

`/loop Read DESIGN-LOOP.md and run the next tick`. A tick runs when an agent
reports, with a 30-minute fallback. Each tick: `gh run list -L 10` (fix or
explain red first); read this file's **State** section; act on the current
phase; update **State**; log one entry in `AUTONOMOUS_PROGRESS.md`. When the
phase waits on the owner and nothing runs, the loop stops and says what
unblocks it (memory: no idle ticks). A fresh session about every ten ticks.

## The four jobs

Every design choice is judged against the four things a person comes to do:
**Find** an ear drama worth their evening, **Listen** to it, **Create** one
(record a part, alone or with others), and **Share** it. A surface that serves
none of them is cut; a field that helps none of them is hidden.

## Binding constraints (unchanged by this loop unless the owner says so)

- Decision 068's shell: Home, Browse, Stations, Surprise, Search, Library.
  The loop may propose changing it; only the owner changes it.
- Only essential words on screen; no AI-written lists or copy (data or a human
  editor); unclaimed recordings never called public domain.
- On Air (Decision 064): ink for actions, red only for recording, blue for
  wayfinding, genre hues are content.
- `artwork-presentation-design`: the box takes the picture's shape; faces from
  the pipeline; the typographic card is the default art.
- Feature parity, native idiom: web, iOS/iPadOS, macOS, tvOS, Android.
- Design runs through a design skill; research first, cited (AGENT-BRIEF).
- Values: `learning-orientation-design`, `values-based-feed-ranking` for any
  "what to surface" ranking; nothing that makes a person more passive.

## Phases

**D1. Research (three Opus agents in parallel, cited, no code).** Each writes
`docs/research/design/D1-<topic>.md`: what the best products and collections do,
why it works, what Ear Drama's data can actually support (read the catalog
contract and the live projection, not guesses), and what to steal or refuse.
- **D1a Finding in a huge catalog**: browsing 100,000+ items beyond shelves
  (Criterion Channel, Apple Music and Podcasts, BBC Sounds, Pocket Casts,
  Letterboxd, Discogs, Are.na, museum collections such as Cooper Hewitt and the
  Rijksmuseum, archive.org itself, library catalogs, radio guides and almanacs);
  timelines, calendars, maps of networks and decades, people graphs, faceting,
  progressive disclosure, information scent; which metadata earns a place in a
  list row and which belongs only on detail.
- **D1b The single item and listening**: episode and series detail, Now
  Playing, queue and continue (podcast and audiobook apps, liner notes, museum
  object pages, broadcast archives such as BBC Genome and the Paley Center);
  how to make a 1947 broadcast feel like an event (its date, its evening, who
  was on) without a wall of fields.
- **D1c Making and sharing**: collaborative creation and invitation (GarageBand,
  Voice Memos, Descript, LibriVox, Off Book, table reads, multiplayer invites),
  link previews and share cards, what a finished production's page should be.
Each also audits the current app: 375 px web shots of every surface it covers
(headless Chrome through an iframe), and an inventory of every field each
surface shows, marked keep / move to detail / cut, with the reason.

**D2. Synthesis (one Opus agent).** Reads the three reports and writes:
- a design skill, `catalog-experience-design` (generic, with Ear Drama as the
  worked example), the rules the build phase follows;
- three distinct **directions** for the app as a whole, each a clickable web
  prototype at 375 px and 1440 px of Home, Browse, a series, an episode, Now
  Playing, and the create flow, rendered to PNGs and published as one artifact
  for the owner; each names what it surfaces, what it hides, and its metaphor
  (shelves are one option, not the default).
**Owner gate:** the owner picks a direction or mixes them. The loop stops here
until they do.

**D3. Build, one surface per batch, every platform.** In the order the owner's
direction gives (default: Home and Browse, series and episode detail, Now
Playing and the queue, Library, Create, Share). Each batch: the binding design
doc rules first (`binding-design-doc-discipline`), then web, Apple, Android in
one worktree; Opus for the batch's design, Sonnet for straight ports; frames
read before merge; merged, pushed, shipped (the push-everything rule).

**D4. Review.** A `human-shaped-review` pass and a parity audit over the new
surfaces; the owner plays it on devices; their feedback opens the next round.

## Owner feedback on D2 (2026-10-29)

*"Unfortunately, I like elements of all three. Overall, I think the visual
approach of The Company makes the most sense. Images of people and of the shows
themselves are the most appealing for any user to use as a way of browsing and
selecting items. However, with no real way to standardize the images
(dimentions, quality, etc.), we will need to create skills to allow for
everything to look uniform even though it is not. I like the bulky blocks and
colors of The Sleeve and I like the data visualization options of the Almanac.
Overall, formatting and fitting things together could use some work on all three
(a share button that goes to the next line instead of being next to the other
buttons, poor word wrapping, etc.). In particular, the "Start an ear drama" on
the Company design is exactly what we are trying to avoid
(undifferentiated/undesigned lists of text without any visuals or colors
whatsoever). I also don't think we have gotten even close on the Record a Line
designs (on any of the designs). Can you create a cohesive design based upon
this feedback?"*

So **D2b** makes one cohesive direction, D:
- **Lead with images** (The Company): people and shows are the way in.
- **Uniform although the sources are not**: a new skill for making portraits and
  graphics of every size, quality and kind sit together as one set (it may revise
  `artwork-presentation-design`; fix the skill first, then the design).
- **Bulky blocks and color** (The Sleeve): genre hues and big type as structure.
- **Data visualization** (The Almanac): run strips, the day's years, the decade field.
- **No undesigned lists**: every list (including picking a play) has visuals and color.
- **Record a Line rethought from research**, not from the old flow.
- **Fit and finish checked mechanically**: button rows that never wrap apart, no
  orphaned or mid-word breaks, at 320, 375, 390 and 430 px.

## Owner feedback on D (2026-10-29)

*"This is looking much better so far, but the color combinations are looking
terrible, especially on dark mode. Can you use the tools we built for Human Shaped
(the universal app template) to better align on color combinations and making sure
it looks good on all differnet kinds of surfaces. Additionally, the design is still
not uniform for all different levels of content (some with images, some without,
some with more information, some with less). We need to a design approach that
evens out all of the inconsistencies and make the app look like one complete
thought. The images that should lead should always be ones that best represent the
whole Ear Drama. So, images/graphics that show the full "show" are better than
individual contributors. Images that show the star(s) are better than those that
show folks that are less recognizable. D is definitely the right approach to take
for design of the app, but we really need to work hard to make sure the colors are
working together instead of against each other and that all of the rough edges have
been smoothed out with better design."*

So **D is the direction** (the D2 gate is passed), and **D2c** refines it:
- **Color, with the Human Shaped tools**: `docs/research/palette/measure/palette_check.py`
  (APCA and WCAG, CIEDE2000, color-blind simulation, Simple Icons neighbors), the
  palette lessons in `docs/research/palette/README.md`, humanshaped-site's
  `research/notes/ai-design-anti-patterns.md`, `make-it-look-like-itself`, and the token
  generator and test. Every pairing on every surface (ground, surface, board, button,
  text, mark), light and dark, checked and rendered.
- **One grammar for every level of content**: an item with a picture, without one, rich
  or sparse, renders in the same structure, so the app reads as one thought.
- **The picture that represents the whole show leads**: the show's own image (title card,
  cast photo, logo) before any one contributor; the star(s) before less recognizable
  people; all from data with evidence.

## Owner rulings on the D questions (2026-10-29)

*"1. Having more shows is better, so 5.
2. On an invite link, they should be able to see everything. They just can't
contribute until they sign in.
3. Finished ear dramas should definitely be listed and credited. Why else would we
record them?
4. I think you should be able to have mutliple modes for recording your part. One
option should let you record and have the other parts play (either human voices or
generated voices for parts that haven't been taken yet) and it should play right
through with your opportunity to record your part as it shows up naturally within
the Ear Drama script. Another option should allow you to record each line
individually or re-record any lines again by tapping them and re-recording. Another
option could be a "wait for tap" to advance through the script as you are
describing."*

- **A show is 5 or more episodes** (2,037 shows; the rest is the counted tail).
- **An invite link shows everything signed out**: the play, its parts, who is in, and
  the takes (playable). Claiming a part and recording need an account.
- **Finished ear dramas are listed and credited** on Ear Drama's own pages (and the
  share page), performers by their chosen names.
- **Three recording modes**: *Run through* (the play plays straight through, other
  parts in human takes or live device voices, and the mic opens at each of your lines
  as it comes); *Line by line* (record any line, tap any line to re-record); *Step*
  (each cue waits for a tap to advance).

## State

- Phase: **D4** (2026-11-04): D3 is built and on TestFlight at 1.0.117. **Work from "Next round"
  at the end of this file**; the entries below are history. The D3 phase opened 2026-10-29. Owner:
  "Yes to both" (build D everywhere; one face per star).
- **One face per star**: a person leads at most one show, the one they are most identified
  with (a title role first, then the highest share of episodes); every other show they would
  have led falls to its next picture or its title block.
- D3 order: (1) the shared grammar and tokens on every platform (board, mark, onBoard, print
  emitted natively; the tile, title block, row and event line as one component per platform,
  reading picture / pictureKind); (2) Home and Browse with the A to Z shelf; (3) series and
  episode pages; (4) Now Playing and the queue; (5) Library; (6) Create with the three
  recording modes; (7) invite, finished dramas and share pages. One surface per batch, every
  platform, frames read before merge, merged, pushed, shipped.
- Running: D3-1 (the grammar and tokens on every platform) and P-1 (pipeline: one face per
  star; refuse an own-work license on a picture of someone who died before the file's date,
  e.g. File:Kollmar.jpg; build_db made deterministic locally).
- 2026-10-29 night: the disk filled (ENOSPC) and stopped both agents; the owner freed space
  (57 GB). D3-1 had committed native board/onBoard/onGenre/print tokens (7b99c81, unmerged);
  P-1 had one face per star measured, uncommitted. Both resumed in place 2026-10-30. P-1 adds a
  floor: a marked title role wins only on a show holding at least half the person's episodes on
  their biggest show (Jack Webb stays with Dragnet).
- 2026-10-30: P-1 merged and live (one face per star; a show named for its star first, then a
  marked role at or above the floor; 19 implausible own-work portraits refused; build_db
  deterministic). D3-1 merged (004f5b4): the grammar on all five platforms, Apple not yet
  seen on a device; iPad Pro frames of 1.0.111 read 2026-10-30. D3-2 merged (64c7035): Home's day
  board and tiles, Browse's decade-by-genre field and tile grid. Running: D3-3 (series and episode
  pages, head board adopted) and P-2 (portraits that pass the size floor, display titles, per-year
  counts). Briefs say real
  devices only: a D3-1 simulator wedged the Mac (owner: "We never use simulators").
- Owner calls open from D3-1: one Big Shoulders cut (web's woff2 is narrower than the native
  TTF); Android's Play button (36 dp filled circle) vs web's plain icon.
- 2026-10-30 midday: merged on main (unpushed until checks pass): P-2 (portraits past the size
  floor via one-face depicts photos, owner-approved; display titles; per-year counts), D3-3 (series
  and episode pages, head board), D3-fix (A to Z letter jump, short decade headers, run strips from
  real years, Android long dates, genre link), D3-4 (Now Playing and mini player). Next: push
  1.0.112, publish the catalog, run scratchpad suite/run.sh (iPad, Pixel, Movie Room ATV, iPad tap
  tier with a glass frame for the XCTest passcode prompt).
- D3 left: (5) Library, (6) Create with the three recording modes, (7) invite, finished dramas,
  share pages; then D4. Leftovers: Apple long dates; Now Playing's On the air and That night
  sections; Android rows carry no network; web player lacks queue and share verbs. (All built in D3-9, 2026-10-30:
  Now Playing's On the air and That night on the radio, Voices, the web queue and Share verbs, Android's network.)
- Enforced now (.claude/hooks/device-guard.py): no simulators, no unmuted Chrome, the runbook
  section before device commands. webdrive.Browser is muted by default.
- 2026-10-30 afternoon: D3 is built. D3-5 Library, D3-6 Create (three modes), D3-fix2, P-3
  titles, the tap-tier and seek fixes, and D3-7 invite/dramas/share are merged. Device bench:
  iPad, Pixel, and Ben Bedroom (lease atv). Waiting on the next ship: branch
  worktree-agent-ade95e0af07854150 (the stall watchdog on all three players: 30 s with no new
  bytes while wanting data goes through LoadRecovery; dae2f06, 9c3f7ca, d31ce15; checks green,
  not yet seen on a device). Merge it, then verify once.
- Next: D4 (human-shaped review, parity audit, the owner plays on devices). Token rules are in
  memory (loop_token_economy): Sonnet agents, one at a time on overlapping code, verify once per
  ship.
- 2026-10-30 night: merged and pushed: stall watchdog, P-4 (genres, voices, art.grade, sameDay;
  cache Release catalog-2026-10-30), D3-8 (Stations, Surprise, Search, person page), D3-9 (On the
  air, That night on the radio, Voices, web player verbs, Android network), D4 review
  (reviews/2026-10-30-human-shaped-review.md) and parity audit, P-5 (one spelling per network;
  live catalog 44 networks, guard 53/53), E1 (rights line from data, Replay after the evening,
  Queue and Share in player sheets, export, Worker docs). Every check green on main (d285197).
- Blocked on the owner: the iPad shows "Enter iPad Passcode for XCTest"; enter it, then run the
  tap tier and ship 1.0.114. Bench at d285197's parent: iPad, Pixel, Ben Bedroom 3/3.
- Next work: a Stations day switcher (tonight.json holds 13 days), the owner's own words in
  HUMAN-SHAPED.md and the credits opening, device-play of Create's three modes and sign-in.
- Review page: https://claude.ai/artifact/18ay3AKgXdN53V32TGTqMB
- 2026-10-31 to 11-01, after the owner's iPhone and text feedback: 1.0.114 to 1.0.117 shipped to
  TestFlight. The iPad needs no passcode while unlocked (the prompt above is closed). Display text
  P-6 to P-8; two iPhone 12 design passes; dates spelled out; recording labels from data; a cut-off
  copy counts as a failed load; tiles are Buttons (wrong show, wrong Back); background play works.

## Next round (written 2026-11-04, from an audit of main, CI, the live catalog and last week's session)

Each tick takes the first open item, one agent at a time on overlapping code, Sonnet unless the
item says otherwise. Check a box only with evidence. Items marked **owner** never block the rest:
list them and move on. Stop when only owner items remain.

**Found 2026-11-04.** Main is 97a3275 (1.0.117), clean; all workflows' latest runs green; the site
is current (no web change since its last deploy); catalog published 2026-11-03. Nothing is running.

### A. Put what is built in front of people
- [ ] **N1 Android to Play internal.** Play's last release is 1.0.101 (2026-10-29, c849ae7), before
  direction D: anyone on Play has the old app. Check nothing is in review, run the Pixel bench, then
  dispatch `Play release`.
- [ ] **N2 Verify 1.0.117 beyond the iPhone.** Its last run was the iPhone 12 tap tier only. Tile
  navigation changed for iPad and Mac (`PushLink`) and page identity changed on tvOS. Run qa_suite and
  the iPad tap tier, the Pixel, Ben Bedroom, and press tiles and Back on the Mac (when the owner is away).
- [ ] **N3 Read the built Info.plist on iOS, tvOS and macOS.** Background play failed because a key
  never reached the built app, and the test added reads the source file. `NSMicrophoneUsageDescription`
  is still an `INFOPLIST_KEY_` in `project.yml`; no built app was on disk to check it on 2026-11-04.
  Missing, the first recording crashes. Add a guard on the built product (a test failing first).

### B. Design on the other devices
- [ ] **N4 Bring the iPad, Pixel, Apple TV and Mac to the iPhone's depth (Opus for design calls).** The
  owner found the 10-31 faults on the iPhone, not the harness: spacing, images, bottom scroll, button
  close-ups, malformed icons. Only the iPhone had that pass. One device per batch: every screen, every
  button row up close in each state, light and dark, last row reachable with the mini player up.
- [ ] **N5 Stations day switcher: ask first.** `tonight.json` holds 15 days; no client lets a person
  pick another day. This came from an agent, not the owner: run `learning-orientation-design` and get
  a yes before building.

### C. Catalog pass P-9 (classes, not names; rules per `display_text_ruling`)
- [ ] **N6 Remaining junk names, each class with a guard seen to fail.** Live on 2026-11-04:
  - page and side fragments: Superman page01, page02, page08; Side 1; Side 2
  - cut-off names: Banter (s01, Banter (s02; The Best of Fibber McGee & Molly Side
  - reel compilations: Mystery Reel.Suspense.X Minus One.Black Museum; Christmas Reel; FDR Speaks.Reel Series
  - leading track numbers: 10 Maigret's Boyhood Friend; 1 Julian Simpson Fragments
  - uploader strings: 101 Vintage No 2 D D Teoli Jr A C; Jills All Time Jukebox31; GG Ep119
  - the same show under several names (21 groups by normalized name, some legitimately distinct
    productions such as Henry V: judge each): Bergen & McCarthy three ways; "The Army Hour" in quotes
  A first scan matched 200 of 6,794 series, with false positives (33 Half Moon Street, 2000 Plus).
  Read before cleaning, and scan the live index, not only these examples.

### D. Harness and player defects
- [ ] **N7 Three intermittent checks** (a harness defect, never rerun until green):
  `LayoutSweepUITests/testMiniHome`, `DownloadsPlaceUITests`, and `web_fit_library` (failed 3 of 4 under
  load on 10-31). No fix is in the log for any of them.
- [ ] **N8 Android's stall watchdog can count a slow seek as a stall.** Fixed on Apple and web
  2026-10-31; Android has no in-flight seek signal. It was promised a note and got none until now.

### E. Records
- [ ] **N9 Parity audit.** PARITY shows 7 iPhone ✅ against a 50-test tap tier, and row "Background
  play" still says not seen on a device. Promote what the tap tier proves, nothing more.
- [ ] **N10 Housekeeping.** Add `.wrangler/` to `.gitignore`. Prune 100 `worktree-agent-*` branches and
  10 worktrees (2.6 GB; one is locked), reading each first: two show commits off main, but D3-3 landed
  by another route (90611e6). Confirm the two transcript failures (11-01, 11-02, "nothing came back",
  green since) were archive.org and not ours.

### Owner: only you
- [ ] **O1 Play it.** This is D4: an evening on the phone and the Apple TV, and your notes open the
  next round. Include the lock-screen controls: unchecked, and agents may not lock a test device.
- [ ] **O2 Record a two-role scene with headphones,** trying Run through, Line by line and Step; and
  sign in once on a device. None of these has been played.
- [x] **O3 Take-down page:** agent details and the one-week reply time are on the page (2026-11-04).
- [ ] **O4 Remove the Ear Drama App Limit on the iPhone 12 for good.** It came back on 11-01.
- [ ] **O5 Your words in `HUMAN-SHAPED.md`,** blank at the last review. Someone other than you trying it
  is that review's largest open question.
- [ ] **O6 Before a public store release:** store words, the CarPlay entitlement, the radio-script rule
  and the GRW ask (SCRATCHPAD 13, 15, 16), and trademark (Decision 060).
- [x] **O7 Take-down process (Archive Watch's note, 2026-11-04):** approved and built (Decision 074; catalog 029). Deploy steps are in Decision 074.

Closed, do not carry forward: the iPad XCTest passcode; the Big Shoulders cut and Android's Play button
(native look per platform, 2026-10-30); the stall watchdog branch; the credits page's OWNER notes; `ios_uitest.py` failing a system-overlay
frame (`SYSTEM_OVERLAY_RX`, already in).
