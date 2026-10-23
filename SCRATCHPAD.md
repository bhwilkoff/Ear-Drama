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

- **Ready for you to play (2026-10-22, built, not yet played)**: the listening
  apps on all five (web M2, Apple M3, Android M4; 1.0.8). Each play gate waits on
  one setup step of yours: the web's data needs Settings > Pages > Source:
  GitHub Actions; TestFlight needs the App Store Connect record and signing
  secrets; Play internal needs the Play Console app. Meanwhile, locally: web,
  `ln -s catalog/out/web data && python3 -m http.server 8080`; Mac, open
  EarDrama.xcodeproj and run (the seed bundles from catalog/out/publish-clean);
  Android, `./gradlew :app:installDebug` with the Pixel awake. Try: the sleep
  timer's "End of this episode", a Suspense season, search "sorry wrong", an
  episode's rights line. Broken would be: playback that never starts, a timer
  that starts the next episode, "public domain" anywhere.
- **Plays questions (docs/PLAYS-DESIGN.md)**: 1,722 Gutenberg plays are castable
  today; all 1,371 Generic Radio Workshop scripts are closed by GRW's own terms
  ("TLDR: Assume Copyright") unless we ask (C8, which meets your "no outreach for
  now"). Also open: C5 previews of a half-voiced play, C6 a role nobody takes,
  C7 relay order, C9 "author died by 1955", C10 commercials and Personal Voice,
  and whether Decision 057's "sign-in required to record" covers a local
  recording that is never shared.
- **Ready for you (2026-10-22)**: pick a palette. Open
  `docs/research/palette/index.html` (or the PNGs in `shots/`); the method and
  every number are in its README. Three directions: On Air, Tuning Eye,
  Catalin (the research recommends Catalin; it advises against On Air, whose
  red is iHeartRadio's). Your pick unblocks the tokens and the icon (M0). **Also**: may the loop
  download the two fonts (google/fonts on GitHub) and the CC0 microphone
  photo (Wikimedia Commons)? And a rights call: 112 Command Performance
  episodes credit nobody, so they stay government work under the AFRS rule;
  presume network stars for the whole series instead (tick 7)?
- **Status (2026-10-22, 10:10 PM MT, tick 25)**: the 1.0 loop runs from
  `LOOP-PLAN.md` (`/loop Read LOOP-PLAN.md and run the next tick`, a 5-minute
  cooldown); its tick log is `AUTONOMOUS_PROGRESS.md`. Built on main at 1.0.8:
  the listening apps on all five core platforms (M2 to M4), the catalog with the
  owner's rights rulings, genres, folds, the transcript gate, the publish
  workflow, the web's site pages and offline, and the plays groundwork (M7).
  Running in agents: evenings (Tonight in 19xx), Apple downloads, loudness at
  catalog scale. Decisions 056-061 and catalog 004-007 hold this session's rulings.
- **Catalog now** (rebuilt on main, tick 22-23): 155,608 episodes in 15,695
  series; served 108,005 (25.7 MB compressed); clean 7,716 (LibriVox projects
  still being recorded are not served). Research database and caches: the
  `catalog-2026-10-21` Release (`catalog/README.md`).
- **Open infrastructure**: push events start no Actions workflow in this repo
  (measured 2026-10-22: the workflow is active, Actions enabled, not a fork,
  GitHub status fine, no PushEvent in the feed); dispatch by hand meanwhile
  (`gh workflow run android-build.yml --ref main`). `https://www.eardrama.org`
  failed its certificate after the DNS change; if Settings > Pages still lists
  only the apex, remove and re-add the custom domain.
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
