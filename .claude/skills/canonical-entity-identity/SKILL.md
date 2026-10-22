---
name: canonical-entity-identity
description: Use when a catalog/corpus needs stable per-entity identifiers, when designing or evolving a composite ID formula, when two records collide on the current ID, when migrating IDs across bundles + databases, or when an asset pipeline must guarantee one-asset-per-entity. Carries the one-formula-one-source rule, append-only formula evolution, read-don't-recompute, lockstep ID migration, the never-reverse-parse rule, and the md5 byte-collision guard for asset tiers. Triggers on canonical ID, composite ID, entity identity, ID collision, ID migration, primary key for catalog, dedupe, "same card different variant", one image per item, asset collision, stable identifiers.
---

# Canonical Entity Identity

**One ID per entity. One asset per entity.** Every unique entity in a
shipped catalog gets exactly one canonical identifier and exactly one
canonical asset; no two entities share either. Every script, tool,
lookup, correction table, and UI disambiguates by that ID. Distilled
from shipping a 17,974-entity trading-card catalog (BOBA Playbook)
across three platforms, where identity drift produced silent
wrong-image bugs and forced two formula migrations.

## The one-formula, one-source rule

The canonical ID is usually a **composite** of the fields that make an
entity unique:

```python
entityId = f"{number}-{name}-{variantA or ''}-{variantB or ''}-{variantC or ''}"
```

That formula lives in **exactly ONE source per language** — e.g.
`scripts/entity_id.py` (pipeline), `Entity.swift` (Apple),
`Entity.kt` (Android), one helper in `js/api.js` (web). Never
redefine it inline anywhere. If a second repo (a data-authoring agent,
a companion pipeline) needs the formula, it imports or mirrors the one
helper, and the mirror is **co-changed in the same commit** whenever
the formula changes — state that co-change rule in writing where both
sides will see it.

## Store the ID; don't recompute it

The ID is a **real field in every published bundle** (master catalog +
every downstream/slim bundle). Clients READ the field. Runtime
recomputation is a fallback for a missing field only — never the
primary path. Why: recomputation forks the formula into N client
implementations that drift; a stored field has exactly one producer.

Any **mutation table** (corrections, overrides, user-submitted fixes)
carries the canonical-ID column, and every new row — from any client —
MUST populate it. An audit row without the canonical ID can't be
joined back to the entity it corrects.

## Formula design and evolution

- **Append-only.** A new disambiguating field goes at the END of the
  formula. Existing prefixes stay stable, tooling that sorts or
  prefixes by the early fields keeps working, and the migration is a
  pure suffix change.
- **Empty segments are legitimate.** A null field renders as an empty
  segment; trailing delimiters are intentional and stable
  (`"12-Maverick--"` is a valid, permanent ID). Don't "clean them up" —
  that's a formula change.
- **Verify zero collisions across the full corpus** after ANY formula
  or data change. One script, one number: N unique IDs across N
  entities. Run it in the pipeline, not by hand.

### When a collision class appears

Two *real, physically distinct* entities identical on all N formula
fields means the formula is missing a discriminating field — **extend
the formula; never mutate the source data as a workaround.** The
cautionary tale: a catalog dodged collisions between variant siblings
by assigning them fake distinct numbers. That lie held until an
OCR-driven correction pass tried to restore the true numbers and
produced genuine duplicates. Adding the true discriminating field as
formula field N+1 removed both the collisions and the workaround. Data
that lies to protect an ID formula will eventually be corrected by
someone who doesn't know it's lying.

## Migrating the formula (vN → vN+1)

A formula change is a **deterministic, lockstep migration**:

1. Build an **old→new mapping table** covering every entity (the
   formula is deterministic, so this is mechanical).
2. Apply it **atomically across every surface that stores the ID**: the
   master catalog, every downstream bundle, every database column
   carrying the ID (user data, corrections, overrides, pipeline
   staging), and every derived index (search indexes, feature/embedding
   files — rebuild these from the new catalog rather than patching).
3. Update the N canonical formula sources (one per language) in the
   same change set.
4. **Storage keys and filenames that embed the OLD id stay valid.**
   They are stored strings, not derived values — an asset file named
   for the v2 id keeps working because the catalog stores the filename
   as its own field. Never rename CDN objects as part of an ID
   migration.
5. Re-run the zero-collision check.

**A merged or retired id keeps its public URL.** When two records merge
(duplicate uploads folded into one card), the losing id forwards to the
survivor everywhere it was stored: favorites, history, deep links, and
the public web page. Archive Watch stopped generating pages for merged
ids and Google Search Console reported 128 pages as 404, each one a
crawled URL or a link someone had shared. The fix: `/item/<old>/` is a
zero-second meta refresh plus a canonical link to the survivor, kept out
of the sitemap. An item that is hidden (not merged) still 404s, which is
correct. And when two distinct records share a title and year, their
pages must differ (name the source item in `<title>`), or the search
engine picks its own canonical and drops one.

## Consumption rules (where identity bugs actually bite)

- **Never reverse-parse a composite ID.** `id.substringBefore('-')`
  breaks the day a component itself contains the delimiter. Look the
  record up by ID and read the canonical field.
- **Dedupe on the true ID, never on the display name.** Distinct
  entities share names (variants, reprints, editions). A dedupe keyed
  on name silently no-ops for legitimate distinct records — the UI
  never updates, the queue never appends, and nothing errors.
- **Lookups tolerate normalization variants, keyed by ID.** Exact
  string matching on names misses capitalization typos, punctuation
  variants, and aliases; where a name must be matched (imports, OCR,
  handoffs from another system), resolve through a normalization/alias
  layer to the canonical ID, then operate on the ID.
- **Import/resolution precedence is ID-exact first**, then
  progressively looser keys (number, name) — and that precedence must
  match on every platform, or the same import file resolves to
  different variants per client.

## One asset per entity — enforce at the byte layer

The ID discipline guarantees "one ID per entity" at the catalog layer.
Nothing guarantees "one asset per entity" at the CDN-payload layer —
an optimizer or upload step can silently overwrite entity A's image
with entity B's bytes while the catalog metadata stays perfectly
correct. Only byte comparison catches this:

- End the asset pipeline with an **md5-uniqueness pass per tier**: any
  group of files resolving to *different* entity keys but sharing
  *identical bytes* is written to a collision report with a per-tier
  remediation hint (re-run the tier step, or re-source the master
  art).
- **If the collision report is non-empty, STOP.** Do not sync to the
  CDN until every group is resolved. A post-mortem on one catalog
  found 35 such silently-collided pairs.
- When the correct asset doesn't exist anywhere, reclassify the entity
  into the missing-asset queue rather than shipping the wrong bytes.

The principle: **every invariant the app relies on is enforced where
it can be measured.** "One asset per entity" lives in binary content,
so the check runs against binary content.

## Sub-item identity: many works inside one source item

Sources often file many works in one item: a whole TV series in one
archive.org upload, a season of radio episodes in one folder, an album,
a box set. Archive Watch first served `FireballXL5.complete` (39 files)
as ONE episode that played episode 25, and 150 such items on 85 shows
were hiding about 4,800 episodes (AW Decisions 166, 167). The rules it
settled on:

- **Each work gets its own id, `<item>@<token>`**, where the token is
  the work's OWN number or name as the source states it (`e01`,
  `s2e05`, `x-<slug>` for an unnumbered extra). Never its position in
  a file list and never its file name: a token that moves loses every
  person's progress and favorites. Pick a delimiter the source's ids can
  never contain and that survives URLs, deep links, routers, and
  storage keys (AW tested `/`, which broke deep links and the 404
  router, and `~`, which broke the Worker's id regex, before `@`).
- **Store the parent as a field** (`sourceID`) on every sub-item. Tools
  read the item from that field; clients that must reach the source
  split at the FIRST delimiter through one helper (`item_of`) per
  language. That helper is the one sanctioned exception to "no split
  parsing" below, and it is grep-able.
- **Place a file by the evidence it carries** (its own title first,
  then its number, then the season its item names), not by order.
  An uploader may number by production order while the authority
  numbers by broadcast ("08. Space Immigrants" is 1x03). A file far
  shorter than its slot (under 40% of the episode's runtime, or a few
  minutes) is a fragment, not the episode.
- **Demand evidence that a bundle is a series.** Numbered files are
  lectures, launch coverage, and audiobooks as often as shows, and a
  film split into reels is one work. AW requires episode words in file
  names, a TV typing, per-file titles, a run of ten or more, or the
  item's own metadata saying "series," and keeps a control for each
  false positive it met.
- **Judge per work, cache per item** (see
  `evidence-gated-catalog-curation` §9): the item answers for its
  license and collections only.
- **Old clients**: a build made before sub-ids existed will show the
  works but cannot split the id. Ship the client helper before, or with,
  the data that needs it, and say so in the decision.

## Checklist for a new catalog project

- [ ] Composite ID formula written in ONE source per language, with a
      comment naming the other sources
- [ ] ID stored as a field in every published bundle
- [ ] Zero-collision check wired into the pipeline
- [ ] Mutation/correction tables carry the ID column (NOT NULL for new
      rows)
- [ ] md5 byte-collision guard at the end of the asset pipeline, with
      a hard stop on non-empty report
- [ ] No `split`/`substring` parsing of the ID anywhere (grep for the
      delimiter), except the one `item_of` helper per language for
      sub-item ids, which reads a stored `sourceID` first
- [ ] Dedupe and equality checks keyed on ID, never display name
