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
- **CI**: Android builds and its unit tests pass in CI (run 39839218802,
  dispatched). **To check**: on 2026-10-22 no push to this repo triggered any
  workflow, and GitHub's event feed showed no push events, while dispatches
  ran. Push the next `android/` change and confirm Android Build starts on
  its own; if it does not, look at the repository's Actions settings and
  GitHub status before touching the workflows.
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

## When to add a binding design doc

When a platform crosses ~5 views OR you find yourself making
inconsistent UI choices, create that platform's binding doc
(`tvOS-DESIGN.md`, `iOS-DESIGN.md`, `macOS-DESIGN.md`, `WEB-DESIGN.md`,
`ANDROID-DESIGN.md`), seeded from the matching per-platform template
in `docs/templates/` (start from `PLATFORM-DESIGN-template.md`, the
index). Invoke
`binding-design-doc-discipline` for the workflow. Treat as binding
from the moment it exists.

The sibling docs share a shape: the **principles** are identical;
the **idioms** they reference diverge per platform. Deliberate
rule inversions between platforms (tvOS auto-focuses Play; iOS
never steals focus) are stated explicitly so they don't get
"harmonized" away.

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
| <!-- e.g. Web push notifications | Too-inconsistent UX across browsers; APNs/FCM cover the need on mobile | iOS + Android push ship and a real cross-platform request appears --> | | |

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
