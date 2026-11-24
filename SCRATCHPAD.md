# Project Scratchpad: Ear Drama

> Active working notes, loaded into every session, so keep it small.
> Keep only the two most recent session-log entries; roll older ones
> word for word into `docs/SESSION-LOG.md` (create it on the first roll).
>
> See `PARITY.md` for the cross-platform feature matrix (the single
> source of truth; don't duplicate rows here).
>
> New to this template? Start with `docs/path/00-why-we-build.md` and
> `docs/path/01-first-prototype.md` before filling anything in.
>
> The Current State block below is injected at every session start.
> If it drifts behind the code, fix it FIRST, then work. A stale
> scratchpad is worse than none.

## Current state

- **Waiting on you** (most valuable first; numbers stay stable as items close;
  item 1, the palette, closed 2026-10-23: On Air, Decision 064):
  (Items 2, 4-9, 12, 14 and the store category answered 2026-10-23: Decision 067.)
  3. **Play the listening apps locally** (1.0.13; built, not yet played): web
     `ln -s catalog/out/web data && python3 -m http.server 8080`; Mac, run
     EarDrama.xcodeproj; Android `./gradlew :app:installDebug` with the Pixel
     awake. First check the iPhone app still opens normally (the CarPlay stub
     changed how its scenes start). Broken would be: playback that never starts, a sleep timer that
     starts the next episode, "public domain" anywhere.
  10. **Setup steps still open** (LOOP-PLAN Needs Ben): the CarPlay entitlement request,
     store-word approval, and the take-down page's reply time and agent details.
  11. **Record a play on a device** (M7's play gate): a two-role scene on the
     iPhone and on the Pixel (Android since 1.0.24), with headphones. Broken would be a
     take that never ends on silence, a cue line you cannot hear, or Listen
     Through out of order. Eleven stage plays ship; no radio play parses clean yet.
  13. **Store words** (`docs/store/LISTING-DRAFT.md`): approve or edit the App
     Store and Play text (category: Entertainment, decided).
  16. **Which radio scripts may people re-record?** (Decision 068, batch R,
     2026-10-24) 616 served radio episodes match a GRW transcription, but 0 are
     castable: GRW's consent alone opens none, because 1,360 of 1,371 scripts
     carry no rights evidence of their own (10 are government work with no
     author on record, 1 is registered with its renewal unsearched). A rule
     for radio scripts is the owner's call.
  15. **Ask the Generic Radio Workshop** before any GRW script is used (the
     owner sends it; a draft is in `docs/outreach/grw-request.md`).
- **Status (2026-11-24)**: main is 1.0.168 (169). It is on Play internal; TestFlight was redispatched (run 45405162430) after the first run built the pre-bump commit. Loop stopped by the owner; resume notes are at the end of `BACKLOG-LOOP.md` State. Disk cleaned to 50 GB free (2026-11-24). The backlog loop
  (`BACKLOG-LOOP.md`) ran B1-B14: Apple Export row, Android seek stall, Worker deploy (DO alarm loop fixed),
  relay free-plan rules on every stack, web voice labels, device passes, class-room silence (bench), tap-tier
  harness, two catalog title passes (2,133 titles), Apple TV Share QR, parity audit, Gutenberg illustration
  markers. Stopped waiting on the owner: iPhone 12 Screen Time limit, the Duo, a signed-in teacher, and the
  owner calls listed in BACKLOG-LOOP "Waiting on the owner". The tap tier's reset door erased the owner's lists
  on the iPhone 12 (not signed in: unrecoverable) and Duo before b377a936/7ecdd3d8 fixed it.
- **Catalog now**: published 2026-11-03 from the daily schedule; 6,794 series served, 1,708 with five
  or more episodes. Research database and caches: `catalog/README.md`.
- **Open infrastructure**: `workflow-health.yml` and `retry-infra-failures.yml` run on schedule and
  are green. `www.eardrama.org` answers (301) and the apex serves.
- **Free plan (2026-11-23)**: the read room long-polls, writes one row per cursor move, and a hidden or
  idle receiver holds no pickup. The Worker is deployed (2026-11-24 10:33, version 4167b816, from 3056b6c9; 496 tests; migration 0011 applied): a room survives refused storage and the hourly sweep erases a room whose alarm was lost. The one room left from 2026-11-23 was erased 2026-11-24; its code is in `read_room_objects` until the sweep finds nothing. Not
  yet mirrored: the receiver and sender rules in Apple `ClassInbox`/`RelayHub` and Android
  `RelayAcrossTime.kt` (PARITY, Relay across time).
- **Owner steps**: "Owner: only you" in `DESIGN-LOOP.md`, and the "Needs Ben" table in `LOOP-PLAN.md`.
  Outreach and trademark are off for now (Decision 060).

---

## Milestones

The 1.0 milestones (M0 to M10), their play gates, and the owner's open items
live in `LOOP-PLAN.md`; the tick log is `AUTONOMOUS_PROGRESS.md`. Ready-to-play
notes go at the top of this file's Current State.

---

## Open questions

<!-- Add questions as they arise; remove when resolved. Don't
     accumulate. Every question should have a path to resolution. -->

- **T4 gaps (2026-11-19), each with its path**: (1) the TV shows its own pairing code (tvOS-DESIGN §4.13) needs a Worker pairing route (a screen asks for a code, the leader binds it); today a TV is joined by the deep link or the debug door. (2) The open iPhone Duo's outer display showing the current line when folded (Decision 080) needs a device check. (3) Mac menu-bar commands for the Reading menu and Android drag-onto-a-part on the casting board. (4) "Read open parts" on the Apple and Android screens is carried in the snapshot (`read_open`) but the device voice that speaks it is not wired there yet. (5) No device run of any T4 screen (T7 bench).

---

## Out of scope (intentionally)

Document explicitly-rejected ideas so future sessions don't
re-litigate them. "We thought about this and chose not to design it
now" is far more useful than silently re-arriving at the same answer.

When a request gets declined, write a row. Format:
`**Idea**: Why declined. Revisit when …` (revisit condition lets
the entry retire when circumstances change).

| Idea | Why declined | Revisit when |
|---|---|---|
| SoundExchange statutory license for Radio channels | No paid license (owner 2026-10-17; catalog 001) | never, unless the owner reopens it |
| Noncommercial-use notices ($50 each) | Declined with the remaining buckets (catalog 006) | a series the take-down model cannot keep |
| A license restricting AI use of contributed plays | Owner chose CC0 with a clear warning (059) | the owner reopens it |
| Trademark clearance or filing for "Ear Drama" | Owner: neither for now (060) | before a public store release |
| Outreach to RadioEchoes, Goldin/UMKC, OTRR, archive.org | Owner: skip for now (060); harvests stay polite | a harvest needs an export or a contact |
| Archive Watch film cross-links in 1.0 | Owner left them out of 1.0 (058) | 1.x |
| A separate Fire TV build without Google Play services | Owner 2026-10-28: "I don't think that the fire tv needs its own separate build if there are so few benefits." One Android build; Fire TV is guarded at run time (no Cast button, no Google sign-in without Play services) | Amazon rejects the build, or a Play-services library crashes on Fire TV |
| A speech-following cursor in a read room (advance when the line is heard) | The reader who stumbles becomes the one the room waits on, publicly; a person always moves the play on (082, R3c §7) | a reader asks for hands-free paging for themselves alone, on their own device, never moving the room |
| Reading-level labels, or casting suggested by ability | It labels children; the casting board shows the script's facts and the teacher decides (082, owner rule 2026-10-23 on invented ratings) | never, unless the owner reopens it |
| Leaderboards, fluency scores, or ranking readers | Ranks children and scores performances (PLAYS-DESIGN §8 rule 6; `learner-experience-design` §5) | never, unless the owner reopens it |
| Every phone speaking stand-ins in sync in a read room | Needs sub-100 ms timing between devices and fills a room with competing voices; only the screen speaks, between takes (082) | a bench measurement shows clock alignment under 50 ms on every platform and teachers ask for it |
| The exquisite-corpse relay (each person hears only the line before theirs) | Hides the play from its performers, failing "does it deepen understanding" (R3c §3.5, §7) | a writing exercise, not a reading one, is proposed with its own learning test |

---

## Session log

<!-- Append-only. Format: state found -> work done -> state left. Keep the
     two newest here; roll older ones word for word into docs/SESSION-LOG.md. -->

**2026-11-23: a $0.00 stack.** Owner: *"We should optimize all of the repositories so that we can
continue to ensure we have a $0.00 stack for every app"* and *"We should not be anywhere close to the
limits on any plan if we are using them correctly."* Found: the read room's poll fallback asked every
second plus an HTTP ping every 10 s (a class of 30 is ~118,800 requests an hour, the shared account's day
in under an hour); ReadRoom.save wrote room, members and an alarm on every change; class pages and cast
sheets held a 25 s pickup forever, hidden tabs included; RelayWatch asked every 30 s per production; the
Actions cache at 9.96 of 10 GB. Done: `GET /v1/read/{code}?gen=N` is a long poll the room holds until a
change or 20 s (poll presence in memory, so a poll writes nothing), the web, Swift and Kotlin clients
use it with no HTTP ping; save writes members only on a real change and sets an alarm only when sooner;
an unchanged alarm writes nothing; `RelayCore.receive` holds a pickup only while shown and stops after
30 idle minutes (Keep receiving takes); RelayWatch skips hidden ticks and waits 5 minutes after an empty
ask; setup-gradle writes the cache only from main and cleans it; concurrency on three workflows. Each
new test seen to fail on the old code (worker 4, `read.test.js` 62 polls a minute, `relay.test.js` 21
asks in 10 minutes and a missing `receive`); worker 487/487, three new mutants caught, web PASS, Kotlin
`ReadRoomTest` 23/23, Swift `ReadCoreTests`+`ReadRecordTests` 21/21 (macOS, unsigned). Left: merely
fixed, not verified on a device or in production; the Worker needs a deploy.

**2026-10-22: the repository.** Owner: *"Alright, I think we are ready to
make a copy of the Universal App Template for Ear Drama and port over the full
set of research and information that we have done in this repository."* Made
`bhwilkoff/Ear-Drama` (public) from the template the same day it was brought
up to date with Archive Watch (template audit 2026-10-22). Moved the research
and `catalog/` from Archive Watch's `claude/radio-drama-research-lpvgea` branch
with their history (`git filter-repo`: 51 commits, the data stripped from every
one), joined the split data parts into the `catalog-2026-10-21` Release (every
part matched the branch's SHA256SUMS; the database opens with the counts its
README states), applied the renames in research 10 §3, and set the identity
(`app.eardrama`, "Ear Drama", eardrama.org). Left: green; see Current state.
