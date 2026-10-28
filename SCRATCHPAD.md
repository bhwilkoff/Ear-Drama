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
  10. **Setup steps** in LOOP-PLAN's Needs Ben (Pages source, DMCA agent, the
     take-down email, store records, OAuth clients, Worker, archive.org account).
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
- **Status (2026-10-27, 8:40 PM MT, tick 94)**: the loop runs from
  `LOOP-PLAN.md` (wakes on results, 30-minute fallback; each tick starts with
  the GitHub Actions check). Main is at 1.0.76. Today: the crash on play fixed
  (1.0.68: Now Playing artwork ran a main-actor closure on MediaPlayer's queue);
  headerless VBR MP3s play and seek at their real length on Apple (1.0.73) and
  Android (1.0.74, Pixel-checked), the web unaffected; offline and error states
  everywhere; queue verbs on Apple and Android; Credits, Privacy, Take-down in
  the apps. The iPhone 12 runs a committed tap tier, `python3
  tools/ios_uitest.py` (16 tests, lease "iphone"), green in one run on 1.0.73.
  TestFlight: 1.0.68, 1.0.70, 1.0.71 submitted; 1.0.73 building. Not verified
  anywhere: anything heard (sleep fade, leveling, a seek landing on its scene).
  Log: `AUTONOMOUS_PROGRESS.md` ticks 86-94.
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
| A separate Fire TV build without Google Play services | Owner 2026-10-28: "I don't think that the fire tv needs its own separate build if there are so few benefits." One Android build; Fire TV is guarded at run time (no Cast button, no Google sign-in without Play services) | Amazon rejects the build, or a Play-services library crashes on Fire TV |

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
