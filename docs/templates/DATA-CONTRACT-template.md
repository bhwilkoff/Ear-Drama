# [APP NAME] shared data contract

<!-- Author this as docs/DATA-CONTRACT.md the moment a SECOND client
     consumes the same content/data. See the
     `shared-data-plane-contract` skill for the full pattern. -->

The shared data plane all clients ([list: tvOS, iOS, macOS, Web, Android])
implement against. Source of truth for everything below: [the
pipeline scripts / CI workflows / the reference client's query
layer]. **When this doc and the code disagree, the code wins. Then
fix this doc in the same change.**

---

## 1. Overview + the one rule

[One paragraph: what the pipeline compiles, from what sources, into
what published artifacts, with what policy flags baked in.]

**The one rule:** no client re-implements or re-hosts any part of
the pipeline. No client re-derives flags, re-audits policy, or
publishes its own copy. Every client consumes the published
artifacts below and reproduces the query verbs in §5 natively.
User state (favorites/progress/preferences) is per-ecosystem
(`per-ecosystem-sync-islands`) and is **out of scope** here.

---

## 2. Published assets

| Asset | URL | Host | CORS | Range | Refresh |
|---|---|---|---|---|---|
| <!-- main DB / feed --> | | GitHub Release (rolling tag) | none | 206, no CORS | daily cron + on push |
| <!-- browser-facing index / config JSON --> | | GitHub Pages | `*` | 206 + CORS on GET | on push |
| <!-- bundled seed --> | | app bundle | n/a | n/a | per release |

Notes to keep verified (re-measure with GET, not HEAD):
- Release assets send **no CORS** and 302-redirect, so they serve native clients
  only; the browser plane lives on Pages.
- Use **ETag-conditional GET** on the main artifact; 304 = keep
  cache.
- [Compression format + on-device decompression path, if any:
  raw DEFLATE for Apple Compression / Android Inflater(nowrap).]
- [Validation before swap: size floor + integrity check + atomic
  rename.]

---

## 2b. Projections (one ladder, one gatekeeper)

I want every client to show the same catalog, even the ones that
cannot open the full database. So the pipeline cuts smaller
projections from one served index, and no builder decides membership
on its own.

| Projection | Consumers | Cut from | Shape |
|---|---|---|---|
| Full database | [native apps] | pipeline | [SQLite, queried on disk] |
| Slim index | [web, Roku, feeds] | full database | [one row per item: browse and search fields] |
| Detail shards | [web, Roku] | slim index members only | [N files by a stable hash of the id; positional arrays, append-only] |
| [Endpoint or feed shards] | [Worker, partner feeds] | slim index | [a few KB each] |

**The slim index is the gatekeeper.** An id absent from it is never in
a shard, a feed, or an endpoint answer. Every builder imports the same
policy predicates (`[module.function]`); none keeps its own copy. The
shard function is mirrored in [client file] and tested against the
builder.

---

## 3. Schema

<!-- Tier every field by how it is used, and say which tier each new
     field went to:
       - Detail-only fields go in the per-row JSON blob (decoded only
         on Detail; zero query cost).
       - Searchable text goes in the FTS index.
       - Values people filter by go in a small join table (id, value)
         with an index.
       - Never a new hot-path or sort column for a Detail-only field.
     Budget: compressed download <= [N] MB, measured on a real build.
     Query cost: EXPLAIN QUERY PLAN plus timings before and after on
     browse, sort, search and Detail. -->

<!-- Tables/columns (or JSON shape) with types. Mark policy flag
     columns (visibility/maturity/rights) and which are COMPUTED at
     build time. Note FTS tables. Schema evolution is ADDITIVE ONLY:
     new columns/keys; clients ignore unknowns; bump schemaVersion.
     Evolution rules that bite in production:
       - Column/field ORDER is load-bearing if any client positionally
         parses (CSV, packed rows). Append only, never reorder.
       - Each client VERSIONS + KEYS its local cache on schemaVersion, so
         a schema bump invalidates stale caches instead of mis-parsing.
       - A field that breaks the shared shape (a new item type) earns its
         own ADDITIVE, separately-bundled file, so the main artifact contract
         stays unchanged (see shared-data-plane-contract).
       - Any value selected deterministically across clients (a "daily"
         pick, a shuffle) is a CROSS-CLIENT CONTRACT, not an implementation
         detail: spec the algorithm here (see cross-platform-determinism). -->

---

## 4. Editorial / config JSON shapes

<!-- Each hand-authored file clients read (featured/config/etc.):
     shape, where served, which clients consume it. -->

---

## 5. Query verbs (every client reproduces these natively)

<!-- The canonical queries: name, semantics, SQL/filter sketch.
     e.g. browse(filters, sort, page) · search(text) · related(item)
     · home shelves. State the universal WHERE clauses (excluded=0,
     maturity gate) that EVERY query applies. -->

### Named filter clauses

Name each WHERE fragment once. Every verb below says which it applies,
because a verb with no filter column gets rebuilt differently on every
platform.

| Clause | SQL | Applied where |
|---|---|---|
| `[matureAnd]` | `AND i.isAdult = 0` | [every verb while the setting is off] |
| `[advertiseAnd]` | `AND [stricter rights or quality test]` | [surfaces that headline an item: shelves, hero, widgets. Never Search, Browse or Detail] |
| `[noRecAnd]` | `AND i.noRecommend = 0` | [every surface the app picks for the viewer] |

Surfaces that advertise are gated more strictly than lookups. Detail
by id applies no advertising clause, because it must resolve anything
the app can link to.

| Verb | Inputs | SQL sketch | Clauses |
|---|---|---|---|
| [shelf] | | | [matureAnd, advertiseAnd, noRecAnd] |
| [search] | | | [matureAnd] |
| [item] | | | none |

---

## 5.5 Display vocabulary (render-layer mapping)

<!-- Schema field names are frozen (a rename is a migration); what
     users SEE is a mapping every client applies identically. List
     each field whose user-facing name differs from its schema name,
     the community/domain term to render, and any deliberate
     exceptions (one surface where a different word is correct).
     Community vocabulary is a design contract: if your users call
     them "weapons," the field can stay `element` forever but no UI
     string may say "Element." E.g.:

     | Schema field | Renders as | Exceptions |
     |---|---|---|
     | element      | Weapon     | none |
     | treatment    | Treatment  | the one "Rarity by ..." explainer section |
-->

---

## 6. Refresh protocol

<!-- Cadence, manifest shape, client behavior on failure (keep
     serving the cached artifact), and the mutation safety rules:
     writers serialized, rebuilds merge-guarded (abort on shrink),
     removals are reversible flags. -->

---

## 7. Policy flags

<!-- Every flag the pipeline computes, where its evidence lives, and
     which surfaces honor it. Recomputed every build, so removing the
     evidence clears the flag. Guards live in the shared selector,
     never a downstream sweep. -->

| Flag | Set by | Evidence | Skipped by | Kept by |
|---|---|---|---|---|
| `excluded` | [builder] | [source file] | every surface | none |
| `noRecommend` + reason | [builder] | [sourced list] | [feeds, heroes, shelves, related, widgets, social] | [search, browse, collections, Detail] |

"Never recommended, always findable" is this second row: the item
stays in the catalog, and no surface that chooses for the person ever
shows it.

Values the pipeline can compute are published, not mirrored: [related
lists with the reason for each link, schedules, daily picks]. Name the
file that carries each.

---

## 8. Outbound surfaces and extension files

| File | Reader | Tier | Shape |
|---|---|---|---|
| [partner search feed] | [third party] | [stricter than in-app: only what the rights audit keeps] | [ids never change once submitted] |
| [playlist or export] | [other players] | [same as the served index] | |
| [topshelf.json] | [Top Shelf, widgets] | served index | [a few rows, a few KB] |
| [tonight.json] | [widget, hero] | served index, `noRecAnd` | `{ "YYYY-MM-DD": id }` |

- A feed handed to another company is a stronger claim than showing
  the item in our own app, so it gets its own tier.
- Feed ids never change once submitted. A hashed stable id covers
  length caps.
- Daily files are keyed by calendar date, start at yesterday, and each
  client reads its own local date. Published days keep their value
  across rebuilds.
- A deploy refuses a feed below [floor] items.

---

## 9. Contract tests

A data contract is a test, not a docstring. One client's tolerance
hides a shape defect from every other client, so we assert the shape
over the real published artifact.

| Test | Asserts | Runs over | Negative control |
|---|---|---|---|
| [test_details_contract] | [every field's documented shape] | [every published shard] | [a producer that emits the old shape must fail] |
| [test_policy_parity] | [every builder imports the same predicate] | [builders] | |
| [test_no_recommend] | [no picked surface contains a flagged id] | [every pipeline output] | [an unflagged item still appears] |

When a test finds a data defect, fix the producer first:
republishing repairs clients that already shipped, with no store
review. Then fix the client, because a client may not crash on a
shape.
