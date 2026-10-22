---
name: third-party-revocation-resilience
description: "Use when the app depends on a third party's data, images, or API (a price guide, a metadata provider, a scraping target, a partner feed) — both BEFORE the dependency becomes load-bearing (design the exit path) and the day a partner revokes authorization (execute a compliant removal without losing the product). Carries the independence posture, the prohibition-list-first removal protocol, the replacement-architecture table, frozen-legacy-data vs live-automation split, grep-verified compliance, and the backfill methodology. Also shared per-app API quotas (price each call, never retry quota errors, degrade, keep a no-API path). Triggers on revocation, cease and desist, takedown, \"they pulled our access\", data partner, third-party dependency, remove the integration, backfill, provenance flip, compliance removal, quota, quotaExceeded, per-app quota, API units."
---

# Third-Party Revocation Resilience

A data/image/API partner can revoke authorization at any time — by
email, with no notice, often the moment they decide you're a
competitor. Distilled from a production removal: a partner's lead
developer emailed revoking use of their data, images, pricing,
mapping, lookup logic, and automated workflows; the full compliant
removal (472 code references across 52 files, three client
platforms, a Worker fleet, and an ingestion pipeline) plus the
replacement architecture shipped in ~2 days over 24 logged ticks.

## Part 1 — Prevention posture (before it's load-bearing)

**Operate independently of any single third party.** That's the
load-bearing principle. Every external data dependency gets an exit
path designed BEFORE the feature ships on top of it:

- **Ask at integration time: "what happens the day this email
  arrives?"** If the answer is "the feature dies," either don't
  build the dependency, or build the replacement seam now (an
  abstraction the replacement will slot into).
- **Prefer generating and owning your own data** over renting
  someone else's — see `provenance-honest-market-data` for the
  snapshot/vanish-inference pattern that manufactures an owned
  dataset from public live state.
- **Record provenance per record.** Every ingested asset/row
  carries a source attribution field. When a source is revoked, the
  attribution field IS your removal work-list and your backfill
  queue — without it you can't even enumerate what must go.
- **Never let a third party's identifiers become your primary
  keys.** Your canonical IDs are yours; theirs are a mapped,
  droppable column.

### Shared per-app quotas (a slow revocation)

Many APIs meter quota per PROJECT (the one behind the app's shipped
client id), not per signed-in user. Every user then draws on the same
daily pool, and one popular evening can spend it for everyone. Archive
Watch measured a two-hour YouTube live show at ~7,700 of the 10,000
daily units (~7,200 of them chat polling at the provider's own 5 s
interval): about one show a day for all users. Rules (Decision 136):

- **Price every call before adding it** (units x calls per session) and
  write the price next to the call. Poll at the slowest cadence the
  feature tolerates; make expensive reads opt-in.
- **Never retry a quota error.** Stop, say so on screen, back off
  exponentially on anything else.
- **Degrade, never die.** Every quota-backed feature has a defined
  state for "quota gone" in which the core verb still works.
- **Keep a no-API path first-class**, not a debug door (a pasted stream
  key needs no API and spends no quota). It is the one route whose
  capacity does not depend on the vendor.
- **File the vendor's quota extension early**; it is a separate review
  from OAuth verification. "Bring your own cloud project" gives each
  user their own quota but is a wall almost nobody climbs; offer it as
  an option, never the default.

## Part 2 — The removal protocol (the day the email arrives)

### 1. Transcribe the revocation into a binding, checkable list FIRST

Before touching code, convert the counterparty's message into:

- **The prohibition list** — every MUST-NOT, quoted verbatim (e.g.
  no use in derived calculations; no display/cache/store/republish;
  no derived mappings or lookup logic; no automated
  probing/crawling/API-style workflows; no notifications triggered
  by their updates; no partner-branding language).
- **The allowance** — the one thing still permitted (commonly:
  "ordinary user-facing linking where the user leaves your app").
  The allowance is as load-bearing as the prohibitions — **it
  defines the shape of the surviving feature.** Confirm scope with
  the owner before building on it.

Paraphrase is where wishful reading enters. Quote.

### 2. Owner's product principles sit alongside the legal constraints

The owner's own rules can veto technically-easy, legally-fine
fixes. (Worked example: filling content gaps by compositing from
sibling records was legal — and vetoed, because it violated the
project's "one entity, one canonical asset" mantra, forcing gap
recovery through genuinely independent sources instead.)
Compliance work is exactly where correctness shortcuts get
smuggled in; the principles are the guard.

### 3. Publish the replacement-architecture table before deleting

Two columns: *surface today* → *tomorrow*. Every removed capability
gets a named successor, or an explicit "removed — nothing replaces
it." This table is what makes aggressive deletion safe: nothing
disappears without an accounted-for destiny.

### 4. Tick 1 is inventory + parallel research — never deletion

- **Repo-wide grep → file:line inventory** of every reference,
  classified into removal phases before any change lands.
- **In parallel, a research agent evaluates replacement sources**
  and returns a verdict table. A table of all-SKIP verdicts (each
  with a one-line reason: coverage too narrow, no API, ToS forbids
  scraping, same takedown risk) is a *deliverable*, not a failure —
  it converts "find another vendor" into "build it ourselves,"
  which is usually the durable answer.

### 5. Delete in a defensible order, one verified tick at a time

Central service first (that's where the logic concentrates) → each
client → ingestion scripts and their cached artifacts → docs and
the parity matrix. Each tick = one hypothesis + one change + one
**observed** result (compile/lint output, line counts, reference
counts — evidence, not assertion), logged with its commit.

### 6. Frozen legacy data vs live automation

Data already on disk, acquired before the revocation, may serve the
explicitly-allowed use as **frozen static fields** — never
refreshed, never validated, never appended to. New records get null
and fall back to a neutral default (e.g. a homepage link).
Everything that *generates or refreshes* that data is deleted and
enumerated with strikethrough in the removal doc: map-builders,
appliers, probers, scrapers, alias tables, slug maps, resolvers,
endpoints, and any parameter that let a caller pass a lookup hint.

### 7. Verification = a grep that returns only intentional hits

The final audit greps the partner's name/domain repo-wide and
requires every surviving hit to be classifiable: the permitted link
helper, removal-marker comments (deliberate — they explain the hole
to the next reader), the frozen field, the replacement component.
Anything unclassifiable is un-removed work.

Report **two separate answers** — never let one imply the other:

- **Compliance**: "100% — zero lookups/scraping/probing/alias
  tables in any active code path; zero partner-branding language;
  the one allowed link preserved on all clients."
- **Replacement functionality**: "operating — X deployed, Y
  deployed, all clients fall back gracefully."

## Part 3 — Backfill (re-sourcing what the partner supplied)

When thousands of assets/rows carry the revoked source's
attribution, re-source them:

1. **Pre-register a hit-rate prediction**, then run a ~50-item
   test batch and compare. A match validates the approach; a miss
   says fix the sourcing before scaling.
2. **Validate throughput** on ~200 items with a worker pool before
   the full run; then run the full set in background.
3. **Overwrite at the same storage key** so existing client URLs
   stay valid — no client-side migration, no app release.
4. **Report the result as a source-attribution histogram**
   (before/after counts per source), not a bare percentage — the
   distribution shows what covers the remainder and when.
5. **Generalize the one-off script on second use** (`--source X` /
   `--from-source X` flags). That's how the removal leaves better
   tooling behind than it found.

## Part 4 — Codify the standing rule

After the removal, write the decision-log entry that makes the
prohibition permanent: **reject any PR reintroducing the
dependency** — fetches, URL construction beyond the permitted
fallback, alias tables, lookup logic, source pills, partner
language. The only permitted code is the explicitly-allowed surface
(e.g. the frozen per-record link + homepage fallback). Future
sessions will otherwise "helpfully" restore the integration.

## Anti-patterns

- **Deleting before inventorying** — you can't verify a removal you
  never enumerated.
- **Swapping one third-party dependency for another** — the same
  email arrives again with a different signature. Build owned data.
- **Letting compliance imply functionality (or vice versa)** — a
  fully compliant app with a dead feature, and a working feature
  that still probes the partner's API, are both failures.
- **Silent holes** — removed surfaces with no marker comment and no
  replacement-table row get "fixed" by a future session
  re-adding the dependency.
- **Refreshing frozen data "just once"** — frozen means frozen; one
  refresh is an automated workflow, which is on the prohibition
  list.
