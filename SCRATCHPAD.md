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
  2. **May the loop download** the two fonts (google/fonts) and the CC0
     microphone photo (Wikimedia Commons)? The icon (the white ring microphone
     on On Air's tally red) waits on the photo.
  3. **Play the listening apps locally** (1.0.13; built, not yet played): web
     `ln -s catalog/out/web data && python3 -m http.server 8080`; Mac, run
     EarDrama.xcodeproj; Android `./gradlew :app:installDebug` with the Pixel
     awake. First check the iPhone app still opens normally (the CarPlay stub
     changed how its scenes start). Broken would be: playback that never starts, a sleep timer that
     starts the next episode, "public domain" anywhere.
  4. **Tonight in 19xx** (`docs/research/evenings.md`): the floor, a quarter of
     prime time surviving (61% of evenings have nothing)? May a gap show the
     newspaper's printed listing, or only its time?
  5. **Command Performance**: 112 uncredited episodes stay government work under
     the AFRS rule; presume network stars for the whole series instead?
  6. **Loudness pace**: once a day (~25 GB, ~108 days) or four (~100 GB/day,
     ~27 days), or tell archive.org first?
  7. **Plays** (`docs/PLAYS-DESIGN.md`): ask the Generic Radio Workshop (C8)?
     C5 previews, C6 unfilled roles, C7 relay order, C9 "author died by 1955",
     C10 commercials and Personal Voice; does "sign-in required to record"
     cover a local recording never shared?
  8. **Samsung TV certificate**: the stub's `.wgt` was signed with your active
     `archivewatchSamsung` author profile; Samsung requires every later update to
     use the first upload's certificate, so give Ear Drama its own before a store
     upload? (The Tizen package id `EarDramaTV` is a placeholder.)
  9. **What plays next** (R3/R14): the three apps disagree. Apple plays on
     through the rest of the series (up to 50), Android through the rest of the
     season, the web only what you queued. Which one rule? (The research's R3:
     a serial plays to its arc's end and stops; the next arc is offered, not
     started. Arcs need a runs table the catalog does not have yet.)
  10. **Setup steps** in LOOP-PLAN's Needs Ben (Pages source, DMCA agent, the
     take-down email, store records, OAuth clients, Worker, archive.org account).
  11. **Record a play on a device** (M7's play gate): a two-role scene on the
     iPhone and on the Pixel (Android since 1.0.24), with headphones. Broken would be a
     take that never ends on silence, a cue line you cannot hear, or Listen
     Through out of order. Eleven stage plays ship; no radio play parses clean yet.
  12. **Six sections** (Listen, Series, Radio, Plays, Library, Search): an iOS 18
     iPhone's tab bar fits five, so it shows four and More (iOS 26 sets Search
     apart). Which one gives way on iOS 18, and does the web's bar (five today,
     six now that Plays has landed) follow the same order? (iOS-DESIGN §3.1, §12)
  13. **Store words** (`docs/store/LISTING-DRAFT.md`): approve or edit the App
     Store and Play text, and pick the category (Entertainment or Education).
- **Status (2026-10-23, 7:25 AM MT, tick 56)**: the 1.0 loop runs from
  `LOOP-PLAN.md` (a 5-minute cooldown; tick log `AUTONOMOUS_PROGRESS.md`).
  Built on main at 1.0.25: listening on all five core platforms (M2 to M4);
  Tonight in 19xx published by CI and on the Radio tab (web, iOS, macOS, tvOS);
  plays phase 1 on iPhone, iPad, Mac and Android with 11 stage plays (M7); the
  design-doc parity fixes (Decision 062 everywhere); the stubs (M9). None of it
  is verified until you play it. Running: Radio on Android, the web plays, the
  M5 Worker (local only). Rulings: Decisions 056-062, catalog 004-008.
- **Catalog now** (rebuilt on main, tick 22-23): 155,608 episodes in 15,695
  series; served 108,005 (25.7 MB compressed); clean 7,716 (LibriVox projects
  still being recorded are not served). Research database and caches: the
  `catalog-2026-10-21` Release (`catalog/README.md`).
- **Open infrastructure**: `https://www.eardrama.org` fails its certificate
  (re-measured 2026-10-23; the apex serves). If Settings > Pages lists only the
  apex, remove and re-add the custom domain.
- **Owner steps**: the "Needs Ben" table in `LOOP-PLAN.md` (Pages source to
  GitHub Actions, the DMCA agent and `DMCA_AGENT_REGISTERED`, the take-down
  email, store records and signing secrets, OAuth clients, the Worker, the
  archive.org account, the CarPlay entitlement). Outreach and trademark are off
  for now (Decision 060).

---

## Milestones

The 1.0 milestones (M0 to M10), their play gates, and the owner's open items
live in `LOOP-PLAN.md`; the tick log is `AUTONOMOUS_PROGRESS.md`. Ready-to-play
notes go at the top of this file's Current State.

---

## Open questions

<!-- Add questions as they arise; remove when resolved. Don't
     accumulate. Every question should have a path to resolution. -->

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

---

## Session log

<!-- Append-only. Format: state found -> work done -> state left. Keep the
     two newest here; roll older ones word for word into docs/SESSION-LOG.md. -->

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
