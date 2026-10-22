---
name: provenance-honest-market-data
description: Use when an app displays prices, valuations, comps, or any market signal (collectibles, resale, tickets, real-estate comps, marketplace data), when the sold-data API you wanted doesn't exist or won't grant access, when matching third-party listings to your own catalog entities, or when building/auditing a price estimator. Carries the provenance contract (transacted vs asking vs derived — never conflated), the Listed Range honest fallback, vanish-inference for generating your own sold history from live-only listings, match-precision gates, estimator honesty floors, the three durable data layers (snapshots/events/audits), pattern-based auditing with CI regression gates, and the dead-affordance UI rule. Triggers on pricing, market value, comps, sold data, asking price, price estimate, valuations, listings, "what's it worth", vanish inference, price tracker, comp matching, market est.
---

# Provenance-Honest Market Data

How to show users what things are worth without lying to them — and how
to build the sold-history dataset you need when no API will sell it to
you. Distilled from shipping a pricing system for a ~18k-item collectible
catalog (BOBA Playbook) after the only third-party sold-comps API turned
out to have rejected every applicant for ~5 years.

## The core contract: provenance is the label

**Every number states what KIND of data it is.** There are exactly four
kinds, and the most-specific *honestly-labeled* signal wins, in order:

1. **Recent Sales** (transacted — the real thing). Actual completed
   sales, each row carrying its own source pill and its own date.
   Shown only when real sold data exists.
2. **Listed Range** (asking — what's on the market now). When there is
   NO sold data, the active listings ARE the honest primary signal:
   LOW/AVG/HIGH + count + a provenance line like
   *"N active listings · no recent sales data yet."*
3. **Buy Now** (asks — where to buy). Active asking prices as a
   separate, additive section. **Never folded into any sold or
   market-value number** — asks run 10–25% above transacted prices, so
   folding them in silently inflates every valuation.
4. **Estimate** (derived). A model output, shown ONLY when (a) it is
   explicitly labeled ("Estimated · based on N comparable items") AND
   (b) it was fed real comp data. An estimator with no real comps
   behind it is suppressed entirely, not shown with a hedge.

**Never label a weak signal with a strong signal's name.** The
cheapest, highest-leverage fix in the whole program was a copy change:
renaming a fabricated "Market Est." (backed by nothing) to "Listed
Range · median $X · 12 listed · no recent sales data." Zero
engineering, shipped in week 1, and it converts a state users read as
a bug into a state they read as information. Do this first; it
de-pressures the timeline for the hard tiers below.

Reject any change that (a) presents an asking/derived number as market
value without real sold data, (b) folds asks into a sold figure, or
(c) loosens a match gate so another entity's listings count.

## Vanish-inference: manufacture the history you can't buy

When "currently active listings" is public but "sold history" is gated
or nonexistent, build your own:

- **Snapshot** the public active-listings endpoint into a persistent
  store (D1/SQLite/Postgres) on an ongoing basis.
- When a listing **disappears** from a later snapshot, infer a
  completed sale at last-seen price — with a **confidence score**, not
  a boolean.
- Score additively, capped at 1.0, with explicit **negative** weights
  for the false-positive modes:
  - auction ended past its close time: **+0.70**
  - fixed-price listing that had been live a long time: **+0.40**
  - seller's *other* listings still present: **+0.20**
  - pulled before close: **−0.50**
  - vanished within 24h of posting (edit/typo relist): **−0.30**
  - seller's *entire* inventory vanished (bulk delist): **−0.40**
- Surface only rows **≥ 0.55**; persist everything below for audit and
  future threshold tuning. Ship the formula as a starting point — the
  first weeks of real data inform the weights.

After ~60 days you own the history the paid API would have sold you.
It accrues forever and no partner can revoke it.

**Push beats cron on constrained runtimes.** A nightly cron over the
whole catalog blew a serverless platform's per-invocation subrequest
cap immediately. Instead, piggyback a **one-item background ingest on
the user-facing request path** (`ctx.waitUntil` or equivalent): every
time someone views an item, snapshot that item. Under the cap by
construction, scales with real usage, snapshots exactly what people
care about — and vanish-detection evaluates per-item against a fresh
fetch of that same item, so an un-viewed item is never falsely swept
as "vanished" the way a time-based sweep would.

## Match-precision gates: one entity, one ID, one price

Matching third-party listing titles to catalog entities is where wrong
prices come from. Trade recall for precision, explicitly:

- **Require two independent identifiers to co-occur** (e.g. item
  number AND name) — one alone matches cousins.
- **Ordinal exclusion**: a bare "1" must not match "1st Edition".
- **Prefixed-number guard**: "1" must not match the suffix of
  "#OHBF-1" — require a token boundary.
- **Conflict-rejects**: if the title names a *different* value of a
  discriminating attribute (variant, edition, treatment) than the
  target entity has, reject decisively — absence of the attribute is
  tolerable, contradiction is not.
- **Brand/domain-relevance gate**: drop anything lacking a marker of
  your domain at all.
- **OR-match on alternate identifiers, then gate.** When sellers title
  by ID *or* by a prominent stat (rarely both), requiring the ID
  yields zero matches; `idHit OR statHit` gated by the
  conflict-rejects restores recall without losing precision.
- **Verify every tightening with a live before/after count** (e.g.
  "95 candidates → 10, all exact"). A gate you didn't measure is a
  gate you don't understand.

## Estimator honesty

- **Derive similarity axes from the domain's actual price driver, not
  the most visible attribute.** The v1 estimator weighted the visible
  attribute 0.6; the real driver was scarcity class. Nearest neighbors
  must share the scarcity/rarity tier; the visible attribute is a
  small secondary bonus.
- **Tier-lock unique items**: a 1-of-1 item only takes comps from
  other same-tier items; when none exist, emit a hedged range or
  nothing — never a confident point estimate from commodity comps.
- **Honesty floor on aggregation**: define the loosest bucket level
  you will ever emit and refuse to go looser. Collapsing a rare chase
  item and a common one onto one median is worse than emitting
  nothing. Use p25/median/p75 (IQR), never min/max, so one mispriced
  listing can't blow the band. Asks enter only with an explicit
  haircut multiplier (~0.82) and the result never claims "high
  confidence" while ask-derived.
- **Facts observed per-item beat any assumed lookup table.** When the
  catalog carries an observed field (a stamped print run, a graded
  count), it dominates any attribute→value mapping you assumed — the
  data will eventually prove the assumed mapping isn't 1:1.

## Three durable data layers (same ingest path, zero extra ops)

The point-in-time price table becomes a compounding asset when the
ingest path that already runs also writes:

1. **Snapshots** — one row per observed price *change*, because the
   primary row gets overwritten and would lose the $30 → $25 → $20
   trajectory.
2. **Events** — immutable, never overwritten, keyed by
   entity+timestamp, carrying the feature vector *at event time*.
   This is what a future model trains on.
3. **Audits** — `(prediction_at_time, actual, error_pct,
   model_version)` — the feedback loop that lets you A/B model
   versions against the same event stream.

Weight evolution is phased: hardcoded priors from documented ordinal
tiers → (at a few thousand events) hedonic regression
`log(price) ~ features` validated on a held-out set, **promoted only
if median |error| improves** → per-bucket corrections learned from the
audit log.

## Audit by pattern, never by symptom

When the owner reports "this item's price looks wrong," the answer is
a standing audit script, not a spot fix. Each check encodes a failure
class the system actually hit:

- **Monotonic-ordering violations** across a known-ordinal dimension
  (a rarer tier priced below a commoner one proves the model isn't
  reaching the output).
- **Coverage floors** per class (<80% covered = systematic skip, not
  bad luck).
- **Suspect-low / suspect-high** bounds against canonical limits.
- **Missing-inside-well-covered-clusters** (catches single outliers).
- **Within-cluster z-score > 3σ.**

Workflow: run the audit (don't spot-check) → read results by *which
audits fired*, not by which item → **tune the model's constants, not
the source data** (edit source data only for canonical truth) → re-run
and diff: the same pattern must not reappear AND no new pattern may
fire. Items flagged by **≥2 audits** are the priority list. Output is
machine-readable so the next run diffs against the prior one.

Run it daily in CI with: a **history row per day** (audit counts + the
build's threshold/multiplier config, so calibration has comparable
baselines); a **regression gate** that fails the workflow when any
critical audit goes 0 → ≥1 or coverage drops >5pp — the bad artifact
never reaches production; and **recommendation-only calibration**
("metric X inverted for 7+ days; consider bumping constant Y ~50%") —
never auto-applied, because auto-applying creates feedback loops on
noisy days.

## UI rules

- **Every user-visible affordance must control something real.** A
  time-window picker that visually scoped the whole pricing panel but
  actually filtered only one (empty) data source was a trust-erosion
  device — and worse, the differing `days` params each platform sent
  split the server cache into divergent buckets, so three platforms
  showed three different listing counts for the same item at the same
  moment. Remove the control; let per-row dates carry freshness.
- **Per-row provenance pills, never hidden behind disclosure.**
  Provenance IS the trust mechanism; each Recent Sales row names its
  source and date inline.
- **Lock the vocabulary across platforms** (section headers, tri-grid
  cell labels like LOW/AVG/HIGH, single-anchor forms like "FROM $X"
  vs "LAST SOLD $X") so the same signal reads identically everywhere.
- **Ship the estimate as a static artifact in the existing response
  shape.** All clients get every model improvement with zero client
  edits and no N-way logic drift; every rebuild improves user-visible
  quality without an app release.

## The anti-metric

Success metrics (coverage %, items with ≥1 real comp) need an
explicit anti-metric: **false-positive inferences**. Weekly, a human
samples ~20 inferred-sale rows; if more than ~3 are clearly wrong,
tighten the confidence threshold before chasing more coverage.
Coverage gained by lying is negative progress.
