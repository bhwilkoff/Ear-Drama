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
- **Status (2026-11-04)**: main is 1.0.118. Screen audits and redesigns done on web, iPad, Apple TV,
  Mac and Pixel. The loop is stopped; next round starts from "Next round" in `DESIGN-LOOP.md` (N5, N7 to N10,
  N12, N13). Not verified: anything heard; lock-screen controls; AirPlay or Cast; Create's three modes on a device.
- **Catalog now**: published 2026-11-03 from the daily schedule; 6,794 series served, 1,708 with five
  or more episodes. Research database and caches: `catalog/README.md`.
- **Open infrastructure**: `workflow-health.yml` and `retry-infra-failures.yml` run on schedule and
  are green. `www.eardrama.org` answers (301) and the apex serves.
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
