---
name: shared-data-plane-contract
description: Use when multiple clients consume the same content/data (a catalog, feed, corpus, or library), when designing how published data reaches the apps, when a browser client needs the shared data (CORS/Range realities), or when changing the published schema. Carries the consumers-only rule, the contract doc, hosting trade-offs (GitHub Releases vs Pages vs git), verified CORS/Range matrix, ETag refresh, raw-DEFLATE on-device decompression, additive schema evolution, merge-guarded mutations, contract tests over the real artifact, the projection ladder with one gatekeeper index, field tiers by use, named filter clauses, pipeline-side policy flags (never recommended, always findable), stricter outbound tiers, and small extension files. Triggers on data plane, shared catalog, published database, sqlite over http, data contract, CORS, range requests, ETag, schema version, "where should the data live".
---

# Shared Data Plane Contract

When several clients (iOS, tvOS, macOS, Android, web) consume the same
content, build the data ONCE as a published plane and make every
client a consumer. Distilled from shipping a ~40k-item catalog to
five clients with zero per-client data logic. (macOS queries the same
read-only DB on disk as the other Apple platforms — no new mechanics,
just another consumer.)

## The one rule

**No client re-implements or re-hosts any part of the pipeline.**
No client re-derives content flags, re-audits policy, re-matches
external metadata, or publishes its own copy. The pipeline (CI /
build-time) compiles everything — including policy flags like
visibility, maturity, rights — into the published artifacts; clients
filter with a `WHERE` clause and inherit every policy fix for free.

The moment a second client exists, author `docs/DATA-CONTRACT.md`
(seed: `docs/templates/DATA-CONTRACT-template.md`). It specifies:
the published assets (URL, host, CORS, Range), the schema, the
editorial JSON shapes, the **query verbs** every client reproduces
natively, and the refresh protocol. When doc and code disagree, the
code wins — then fix the doc in the same change.

## Architecture that scales

For content beyond a few MB, publish a **prebuilt SQLite database**
(with FTS if you need search) and have clients query ON DISK — not a
JSON blob decoded into memory. The binding constraint on a TV/phone
is resident memory, not download: a 95 MB JSON decodes into 150–250
MB of live objects; query-on-disk keeps residency at the visible
rows and scales to 1M+ items.

- Ship a small **bundled seed** DB for first paint; swap in the full
  downloaded DB when ready.
- Compress as **raw DEFLATE** (`zlib.compressobj(wbits=-15)`), not
  gzip: Apple's Compression framework (`COMPRESSION_ZLIB`) and
  Android's `Inflater(nowrap=true)` both decode raw DEFLATE
  natively, streaming file-to-file in small chunks (peak memory
  ~64 KB instead of the whole DB).
- **Validate before swap**: size floor + `PRAGMA integrity_check`
  (or an open-probe) on the staged file, then atomic rename. A
  half-downloaded DB must never become the live one.
- **ETag-conditional GET** (`If-None-Match` → 304 = keep cache) for
  refresh — don't re-download an unchanged 30 MB asset daily.

## Hosting: the verified matrix

Where an asset lives determines who can read it. Measured, not
assumed (re-verify with **GET**, not HEAD — HEAD lies about Range
support):

| Host | CORS on fetch() | Byte-range (206) | Native clients |
|---|---|---|---|
| GitHub **Release** assets | **none** (302 to objects.githubusercontent.com) | 206 but no CORS | fine (URLSession/OkHttp) |
| GitHub **Pages** | yes (`*`) | **206 + CORS on GET** | fine |
| Third-party media hosts (e.g. archive.org download nodes) | usually none | varies | fine; `<img>`/`<video>` elements are CORS-exempt |

Consequences:
- **Big rolling artifacts → GitHub Releases** (a rolling tag,
  clobbered per publish). Native apps consume them directly.
- **Anything the BROWSER must fetch() → Pages** (or another
  CORS-enabled host). If the browser needs the big DB, deploy it to
  Pages via an Actions artifact — never committed to git — and query
  in place over range requests (sql.js-httpvfs class tooling), or
  publish a slim index JSON as the browser plane.
- Never `fetch()` a Release asset or a no-CORS media host from
  browser JS. Media elements (`<img>`, `<video>`) are exempt — use
  them.

## Git hygiene

**Generated accumulators do not live in git.** A multi-MB
machine-generated file committed per rebuild bloats `.git`
unboundedly (a real repo hit 624 MB and GitHub's 100 MB push limit
before the purge + history rewrite). Hand-authored editorial JSON,
tools, and the small bundled seed stay in git; the full artifact
lives on the Release. Gitignore the artifact path so it can't come
back.

## Mutation safety (the expensive lessons)

- **Additive, merge-guarded builds.** Once the artifact lives
  outside git, there is no diff review to catch a clobber. Any
  workflow that REBUILDS (rather than incrementally enriches) must
  merge its output INTO the fetched current artifact and **abort if
  the result would shrink**. A from-scratch rebuild once silently
  replaced a 30k-item catalog with 1.1k — the merge guard is the
  permanent fix.
- **Serialize writers.** Multiple CI jobs mutating the published
  artifact share one concurrency group (fetch → mutate → publish is
  stateful).
- **Policy removals are reversible flags, not deletes.** Hiding
  content (rights, maturity, quality) sets `excluded: true` in the
  source; the publish step filters it. Restorable, reviewable,
  auditable — and a wrong hide is a one-line fix.
- **Schema evolution is additive.** New columns/keys only; clients
  ignore unknown keys (decode leniently). Bump a `schemaVersion`
  for readers that care. Never rename/repurpose a field — add a new
  one and let the old age out with old clients.

## Refresh cadence + manifest

Publish on a schedule (daily cron) + on relevant pushes. Alongside
the artifact, publish a small `manifest.json` (schemaVersion,
generatedAt, counts, bytes) — a cheap version probe for tooling and
future clients, even if today's clients go straight to the asset
with ETag.

## Client consumption rules (every consumer, every platform)

Cross-platform UX bugs hide in the *consumption* layer even when the
plane itself is clean. Four rules earned in production:

- **Two-phase progressive load for a big JSON catalog**: ship a small
  head file (the first ~500 items, a couple hundred KB) that loads
  synchronously for an instant first frame, then hydrate the full
  catalog behind it. One 5 MB decode before first paint reads as a
  hung app. (For corpora past a few MB, prefer the SQLite
  query-on-disk route above instead.)
- **Search is word-prefix, never substring.** One shared matcher per
  platform: "amon" finds "Amon-Ra" and never "Damon". A raw
  `.contains()` matcher sprayed across surfaces produces different
  results per screen and surfaces embarrassing mismatches. Specify
  the matching semantics in the data contract so every client
  reproduces them.
- **Items with imagery sort ahead of image-pending placeholders** in
  every grid — the primary sort key, applied identically on all
  platforms. A wall of placeholders at the top of a browse surface
  reads as broken.
- **Display vocabulary is part of the contract.** Schema field names
  are frozen (renames are a migration); what users SEE is a
  render-layer mapping every client applies identically (field
  `element` renders as "Weapon"). Put the mapping table in the data
  contract doc — see the DATA-CONTRACT template's Display Vocabulary
  section — so no client leaks schema language into the UI and no
  two clients translate differently.

## A data contract is a test, not a docstring

A shape the contract states is asserted by a test over the REAL
published artifact (every shard, every row), not only unit fixtures.
Archive Watch (Decision 116): the detail builder documented "cast is
always a list" and emitted a bare string when a person had no photo.
The web happened to check `Array.isArray` and coped; Roku trusted the
docstring and crashed on 5.4% of titles. **One client's tolerance
hides the defect from every other client.** A second reader coping is
not evidence the contract holds.

- Fix the PRODUCER first when the defect is in data: republishing
  repairs already-shipped clients with no store review. Then fix the
  client too, because a client may not crash on a shape.
- Every contract test has a negative control (break the producer,
  watch it fail).

## Projections: one ladder, one gatekeeper

Not every client can read the full artifact. Publish a ladder of
projections, each cut from the one above it:

| Consumer | Projection |
|---|---|
| Native apps (Apple, Android) | full SQLite, queried on disk |
| Browser, Roku, other thin clients | slim index JSON (browse/search rows) + detail files sharded by a stable hash of the id (e.g. 256 FNV-1a shards, positional arrays, fields APPEND-only so indices never shift), one shard fetched per Detail view |
| Free-tier Worker endpoints, partner feeds | smaller shards again, cut from the slim index |

- **The slim index is the gatekeeper for every thin surface.** An id
  absent from it is never requested from a shard, never put in a feed,
  never answered by an endpoint. A builder never re-derives
  membership.
- **Policy predicates are imported by every builder, never copied.**
  Archive Watch's index build had its own looser copy of the mature
  rule; a title the Apple TV hid showed on Roku (Decision 105). Its
  hero rule had been copied by half, and web and Roku admitted 46% and
  67% more films than the apps. Import the function; test the parity.
- The client-side shard function mirrors the builder's exactly (see
  `cross-platform-determinism`).

## Tier fields by how they are used

Every new field goes to the cheapest layer that supports its use:

- **Detail-only** ("find out more"): the per-row JSON blob, decoded
  only on Detail. Zero query cost.
- **Searchable text**: the FTS index.
- **Values people filter by**: a small normalized join table
  `(id, value)` with an index.
- Never a new hot-path or sort column for a nice-on-Detail field.

Budget both before committing: the compressed download size (set a
ceiling and measure on a real build) and query cost (`EXPLAIN QUERY
PLAN` plus timings before and after on browse, sort, search, Detail).

## Named filter clauses, and verbs that state which they apply

Name each universal WHERE fragment once in the contract (e.g.
`adultAnd`, `typeAnd`, `homeAnd`, `notCommercial`) and give every
query verb a column saying exactly which clauses it applies.

- **Advertising surfaces are gated more strictly than lookups.** A
  shelf or hero that headlines an item applies the stricter clause;
  Search, Browse, and Detail by id do not (Detail must resolve
  anything the app can link to).
- A verb whose filter column is unwritten will be reimplemented
  differently on every platform.

## Policy lives in the pipeline

- **Put a guard in the shared selector, not a downstream sweep.** A
  sweep that hides what the picker admitted is a race the catalog
  loses every time a new item lands (Archive Watch Decision 104).
- **Rank once in the pipeline and store the why.** "Related" ranked
  per client gave the same item a different shelf on every screen.
  Compute it once over the post-policy rows, publish ids plus the
  reason for each link, and let clients fall back to a simple query
  when a row is missing (Decision 139).
- **If the pipeline can compute a shared value, publish the result**
  rather than mirroring an algorithm on every device (see
  `cross-platform-determinism` Rule 0).

## "Never recommended, always findable" is a data flag

Some items belong in the catalog but must never be chosen FOR the
person: propaganda, titles with a rights caveat. Model it as a flag
(e.g. `noRecommend` plus a reason), recomputed every build from
sourced evidence.

- Every surface that picks for the viewer skips it: shelves, heroes,
  related, channels, widgets, Top Shelf, surprise picks, social posts.
- Every surface the viewer drives keeps it: search, browse filters,
  collections, Detail.
- Each platform names the gate once (`isRecommendable`, `noRecAnd`)
  and a test asserts every pipeline output honors it, with an
  unflagged control.

## Outbound surfaces use a stricter tier

A feed handed to a third party (a store's search index, a partner
catalog) is a stronger claim than showing an item in your own app.
Give it its own stricter tier, still cut from the served index. But a
playlist or export of what the app already shows follows the app's
gate, not the partner tier (Archive Watch Decisions 113 vs 145).

- **Feed ids never change once submitted.** If the partner caps id
  length, derive a stable hashed id and never "clean it up".
- A deploy refuses a feed below a floor count, so a shrunken feed
  cannot ship green.

## Small purpose-built files for extensions

Top Shelf, widgets, complications, and heroes should not open the
full DB. Publish tiny JSON the pipeline computes (e.g. `topshelf.json`
rows, `tonight.json` as `{ "YYYY-MM-DD": id }`).

- Key daily picks by calendar date and let each client read its OWN
  local date; start the schedule at yesterday so every time zone
  finds today.
- Days already published keep their value across rebuilds, so a
  midday publish never changes today.
