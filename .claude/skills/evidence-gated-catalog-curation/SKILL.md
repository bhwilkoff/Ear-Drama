---
name: evidence-gated-catalog-curation
description: "Use when an app serves a catalog it did not author (public-domain media, an archive, user uploads, third-party metadata) and must decide what to show, hide, recommend, or say about each item. Carries the rules Archive Watch paid for across ~30 decisions: a hide needs a claim a reader can open, and not knowing is not a claim; an uploader's word is not evidence; restore by adding evidence, never by loosening a rule; never recommended, always findable; date lines computed from the calendar; provenance on every field, and accuracy checked, not form; a cleared match scrubs what it filled; an alternate edition is a version, never the default; judge per work; the reconcile trap; owner-reserved content calls. Triggers on rights audit, public domain, copyright, license check, takedown, hide/exclude flag, wrong match, metadata quality, synopsis source, catalog review, propaganda, version picker, 'why is this title showing'."
---

# Evidence-gated catalog curation

Archive Watch serves about 27,000 films and episodes that other people
uploaded to archive.org, with metadata stitched together from TMDb,
Wikidata, OMDb, and TVmaze. Almost every hard call it made in its first
six months was about one question: what is the catalog allowed to say
about a thing it did not make? These are the answers, each with the
incident that produced it. They apply to any app that curates material
it does not own: old-time radio, scanned books, museum collections,
public datasets, user-submitted content.

The thesis: **the catalog acts only on evidence a reader could open.**

## 1. A hide needs a claim a reader can open

- Hide on a specific, citable claim: a copyright renewal record, a
  takedown, a Wikidata statement with a reference, the source's own
  license field. Record it on the item (`claimEvidence: {url, kind,
  claimant}`), so anyone can follow the link and disagree.
- **Not knowing is not a claim.** A title with no evidence either way
  stays, and says nothing. Archive Watch's owner, 2026-09-28: *"If we
  truly don't know about the copyright status, then they can stay
  because of that ambiguity."* (AW Decision 151: 947 items hidden on
  Copyright Office renewals; 13,905 with no claim kept.)
- A reviewer's reasoned judgment is not "we don't know." When a person
  looked and wrote down why an undated item is modern, list it with that
  reason (`likely_modern.json: {id: reason}`) and hide it until it is
  identified (AW Decision 159). Never list on a hunch about an uploader
  alone; check two of their titled uploads first.
- Match a claim narrowly and test the near-misses as controls. AW's
  renewal matcher counts a renewal of THIS title, of a motion picture,
  originally registered within a year of this item's year. It refuses
  a later registration of new material (a colorized edition), a renewal
  of a song from the film, and a same-titled work from another year.
  OCR or fuzzy noise may only cause a miss, never a match.
- A failed fetch is never evidence. Only a definitive answer (404/410,
  an explicit license) changes a verdict; 403/429/5xx/timeouts leave
  the item as it was and retry later.

## 2. An uploader's word is not evidence

- Whoever uploaded a thing can type any license on it. AW measured that
  96% of its catalog was labeled public domain, and 7,400 items dated
  1978 or later carried that label wrongly (a 2015 studio film wearing
  a "Public Domain Mark"). The source's own license field is the
  starting signal, not the verdict (AW Decision 027).
- A modern or undated item kept only on its uploader's license needs
  independent corroboration: a Wikidata license statement on the item
  whose archive id is this one, or a curated evidence file with a source
  URL. Owner, 2026-09-25: *"Unless we have evidence for CC or PD, an
  uploader's word is not enough."* (AW Decision 140: 1,321 hidden.)
- Sourced evidence of a genuine free license outranks a popularity
  heuristic (AW Decision 152: *Sita Sings the Blues*, a real CC0 film
  with 5,000 votes, was hidden by a "popular means pirated" gate until
  evidence was allowed to win). Never loosen the heuristic itself.
- The uploader's description is the uploader's voice, not the work's.
  It may be a review, a shot list, or a note about digitizing. Prefer
  a checked source (§6).

## 3. Restore by adding evidence, never by loosening a rule

When a rule hides something it should not, the fix is a WITNESS the
build can read: an evidence file entry with a source, a sibling copy
with a verified match, a corrections file, an override with a reason
(`overrides.json: {id: reason}`). The rule stays as strict as it was,
and the next build re-derives every verdict from rules plus evidence.

The same goes the other way: a false positive is tuned by a rule with a
control in the test file, never by a list of ids that silences it.

## 4. Never recommended, always findable

Some items belong in the catalog but should never be chosen FOR a
person: state propaganda, works whose rights are restored abroad,
material that needs more context than a caption can give. A data flag
(`noRecommend` plus a reason), set by the pipeline every build from
sourced evidence, takes them off every machine-chosen surface (home
rows, heroes, related, channels, widgets, surprise picks, social posts)
and leaves them on every surface the person drives (search, browse,
collections, the item's own page). Never widen it on a keyword: a plain
"propaganda" tag sat on 200 titles including *Battleship Potemkin* and
*Why We Fight*; the evidence-based rule caught 60 (AW Decisions 149,
156). Details in `values-based-feed-ranking` §5.

## 5. Compute thresholds; never write them as literals

"Public domain by age" moves every January 1. AW carried a literal
`1929` for two years and left 1,691 titles in the wrong tier (AW
Decision 137). Compute every date line from today (`today.year - 95`
for US works), in the pipeline AND in every client that states it, and
pin the arithmetic in a test across a New Year boundary (Dec 31 vs
Jan 1). The same goes for "new this month," "recently added," and any
window: compute from a real `addedAt`, never from an upload date that
merely looks recent or a bulk fallback stamp (one timestamp on 1,555 old
titles made them all "new"). And a "New" shelf takes the STRICTEST
evidence bar in the app, because the newest items have had the least
time in the audits (Archive Watch's owner: *"often items that are not
fully vetted"*).

## 6. Every text field carries its provenance, and accuracy is checked

- Stamp every synopsis, credit, and date with where it came from
  (`synopsisSource: tmdb | wikipedia | archive | ...`). A writer that
  cannot name its source is writing the uploader's text and must say so.
  Never overwrite a checked source with a weaker one (AW Decision 124:
  22,192 of 27,159 synopses had no stamp; 11,229 of those had an
  accurate overview available the whole time).
- Show the source on every record, not only the weak ones. A caption
  that appears only on bad records is a warning nobody reads; one on
  every record is provenance a person can weigh.
- **Review accuracy, not form.** Owner, 2026-09-29: *"I want to make
  sure that info is accurate and not just that our data is well
  categorized."* Check each summary against the item's own facts (year,
  credits, type) and an independent source before calling it reviewed.
  AW's accuracy pass found 44 encyclopedia leads describing a different,
  same-titled work. Decide which side is wrong; sometimes it is the
  catalog field.
- A durable correction goes in a corrections file the build reads
  (`year_corrections.json`, `synopsis_rejects.json`), never only in the
  generated catalog, or the next build reverts it.

## 7. A cleared match scrubs what it filled

When an external match turns out wrong (the upload was matched to a
different work with the same title), clearing the id is not enough: the
year, credits, genres, and art it filled are somebody else's facts.
Remove each one unless something independent vouches for it: the
source item's own metadata, a sibling copy with a live match, a
corrections entry. Record what changed (`scrubbedFields`, `yearWas`).
Check siblings BEFORE the source's own date, because upload dates are
often wrong too (AW Decision 150). Judge a match against the source's
OWN title and signals, never against the catalog's copy of them, which
the match may already have overwritten (AW's title resolver: 2,306 of
3,033 title-only matches were wrong, and each read as an exact title
match in the catalog).

## 8. An alternate edition is a version, never the default

Colorized copies, abridged cuts, re-dubs, and remasters fold into the
work's card when identity agrees, rank below every original, and stay
selectable in a versions picker (AW Decision 158). A different work
with the same title (a remake) stays apart on its own id and year. A
merged-away id forwards to its survivor, so favorites and history never
vanish (AW Decision 085). The source's own classification can be
evidence too: an item in archive.org's own trailer collection is a
trailer, whatever identity it wears (AW Decision 163).

## 9. Judge at the granularity of the unit

When one source item holds many works (a whole series in one upload,
an album, a box set), every judgment that depends on a work's
properties is made per work: its year, its rights, its runtime. Fetch
and cache by item; judge by work. AW keyed a rights audit's year by
item, so the first 1978 episode of a show filed in one upload removed
all 39 episodes, including the 1976 and 1977 ones (AW Decision 168).
Only properties that truly belong to the item (its license, its
collections) are answered at item level. See
`canonical-entity-identity` §sub-item identity for the id scheme.

## 10. The reconcile trap

If a hide flag is recomputed every build (it should be), then setting
the flag by hand does nothing: the next build reverts it unless a rule
returns a hide verdict for that item. When "hidden in the source, still
showing in the app" comes up, check what the rule returns, not the
flag. Two corollaries from AW:

- A DATA fix can un-hide. Correcting a year moves an item between
  rules; if it lands in a "needs confirming" state, it must stay hidden
  until confirmed, never shown in the meantime.
- Before publishing a change that moves years or titles, run the audit
  on a COPY and diff visibility both ways. And because pipeline passes
  write their catalog as a side effect, point a scratch test at a temp
  path first (one simulation overwrote a 143 MB local catalog with 348
  bytes).

## 11. Content calls are the owner's

Hiding a class of material (an era, a genre, a rights band, a source)
is a product decision, not a bug fix. Measure the class first (how many
items, which famous ones, sampled by hand), show the owner the numbers
and the named examples, then apply what they choose, verbatim, in a
decision entry. Everything below that line (a plainly wrong year, a
broken link, a duplicate) an audit loop fixes without asking.

## The shape in code

- One reversible flag (`excluded` plus `excludedReason`) that every
  output skips; never a delete. A tool that hides registers its marker,
  so the reconcile knows whose hide it is.
- Every hide bucket is a rule with a paired test: hidden without
  evidence, kept with it, and a control that should produce the
  opposite verdict.
- Evidence and corrections live in committed editorial JSON files the
  networkless build reads; network lookups are cached into them.
- Publish nothing that shrank unexpectedly (see `ci-fleet-engineering`).

The cost: strict evidence hides true things too. AW's scrub removed a
few correct directors that nothing in the record vouched for, and the
rule accepts that, because a wrong fact presented as checked is worse
than a missing one. Bring back what you lose with evidence.
