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

- **Ready for you (2026-10-22)**: pick a palette. Open
  `docs/research/palette/index.html` (or the PNGs in `shots/`); the method and
  every number are in its README. Three directions: On Air, Tuning Eye,
  Catalin (the research recommends Catalin; it advises against On Air, whose
  red is iHeartRadio's). Your pick unblocks the tokens and the icon (M0). **Also**: may the loop
  download the two fonts (google/fonts on GitHub) and the CC0 microphone
  photo (Wikimedia Commons)? And a rights call: 112 Command Performance
  episodes credit nobody, so they stay government work under the AFRS rule;
  presume network stars for the whole series instead (tick 7)?
- **Status**: research done, owner questions answered, the 1.0 loop drafted
  (2026-10-22); nothing built yet. The web app and the native apps are still
  the template's starters, renamed to Ear Drama. **The build runs from
  `LOOP-PLAN.md`**: `/loop Read LOOP-PLAN.md and run the next tick`.
- **1.0** (Decisions 056-060, catalog 004-007): the core five at parity,
  every other platform a stub; done when the web is live with the full audited
  catalog and the natives are on TestFlight and Play internal. Optional
  Apple/Google sign-in on a Worker + D1; Radio evenings, Listen Together,
  transcripts; shared plays phases 1-2 (radio and stage scripts, CC0, archive.org,
  teacher classes). Palette and genre hues wait on design research (M0).
- **Identity**: `app.eardrama` on every platform; home eardrama.org
  (DECISIONS 054). **eardrama.org is live on GitHub Pages over HTTPS**
  (2026-10-22): DNS at WordPress.com (my.wordpress.com/domains/eardrama.org)
  holds GitHub's four A and four AAAA records at the apex and `www` as a
  CNAME to `bhwilkoff.github.io`; the `_github-pages-challenge` TXT record
  verifies the domain. Pages serves `main` from the root, with `CNAME` and
  `.nojekyll` committed. `http://` and `http://www` redirect to
  `https://eardrama.org`. **Open**: the certificate covered only the apex
  at first, so `https://www.eardrama.org` fails its certificate check (as
  `https://www.archivewatch.org` does today). `www` moved from a CNAME to the
  apex to one to `bhwilkoff.github.io` (GitHub's documented form) at 13:21 MT,
  but the old record's TTL is 4 hours. After that, if Settings > Pages still
  lists only eardrama.org, remove and re-add the custom domain there.
- **CI**: **push events do not start Actions workflows in this repo**
  (measured 2026-10-22). e798457 changed `AppVersion.xcconfig` and 9cffd08
  `android-build.yml`, both inside Android Build's push paths, and neither
  started a run; Pages deploys do run on every push. The workflow is active,
  Actions is enabled with all actions allowed, the repo is not a fork, GitHub
  status is operational, and the repo's event feed holds no PushEvent at all.
  Until it is solved, dispatch: `gh workflow run android-build.yml --ref main`
  (run 39862707734 for e798457). Next to try: the owner looks at Settings >
  Actions > General, or asks GitHub Support.
- **The research** starts at `docs/research/RESEARCH.md` (§7 owner
  questions, §8 the first build session in order). The catalog pipeline is
  `catalog/` with its own `DECISIONS.md`; its database and caches are on the
  `catalog-2026-10-21` Release (`catalog/README.md`, "Start from the
  published snapshot"). 157,503 episodes, 16,113 series; all ten catalog
  test suites pass against a restore from that Release.
- **Next actions**: M0 in `LOOP-PLAN.md`; the owner's open items are its
  "Needs Ben" table (DMCA agent, CarPlay entitlement, store records, OAuth
  clients, Worker, archive.org account). Outreach and trademark are off for now
  (Decision 060).
- **Not set up yet, and why**: App Store Connect and Play records, and the
  signing secrets `appstore-build.yml` and `play-release.yml` need
  (`docs/CLOUD-SUBMISSION.md`). They wait for the first build worth
  uploading. The Tizen package id `EarDramaTV` is a placeholder until a
  Samsung submission.

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
