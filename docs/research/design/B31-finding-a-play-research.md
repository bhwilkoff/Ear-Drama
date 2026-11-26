# B31: Finding a play to perform or record (research, 2026-11-26)

Research only. No app, catalog or publish change. Measurements were made on the checked-in
`catalog/out/plays-library/index.json` (1,194 plays, all Project Gutenberg, 1,190 stage and 4 radio,
every one `script_source_cleared`) joined to `catalog/.cache/gutenberg/pg_catalog.csv.gz` (the
Gutenberg catalog the pipeline already caches), plus a 30-play hand sample (section 3.4).

The owner, 2026-11-26: *"We need to research a FAR BETTER way of searching for and finding a play that
you might like to perform/record. I'd love to see themes and collections for plays and different ways
of finding plays to read or record... Right now there are also no visuals for each play that help
them to distinguish themselves from one another."*

Binding rules this works inside: images are used unless the record marks a restriction (owner
2026-11-21, Decision 040); no AI-written lists or blurbs, so a collection is data or a human editor's
and a title may be composed from data (owner 2026-10-31); only essential words on screen; label art C
is the default art, "nothing on the label is hashed or invented" (Decision 081, WEB-DESIGN 6.4r).

---

## 0. Findings in six lines

1. **What a person choosing a play to perform asks first is cast size, then length, then a form
   (comedy, one-act, tragedy), then audience.** Every performing-rights catalog's first filters are
   cast (total, and women/men), genre, length. We already hold the first two for 100% of plays and
   have never filtered on them.
2. **Our biggest asset is not in the UI: `voices`, `cast` (lines per part), `minutes`, `lines` and
   `sections` exist for all 1,194 plays**, and a Gutenberg `Subjects`/`Bookshelves` row exists for all 1,194
   (every one joined). Subject strings carry form (comedy, tragedy, farce, one-act, Christmas,
   children's), period ("19th century"), translation, place and theme ("Marriage -- Drama").
3. **Form is only named for about a third of plays** (398 of 1,194 carry a form heading), period for 24%
   (287), by an LCSH century. Author years give an era for 89% (1,067). So "genre" cannot be the primary
   facet or the hue key by itself; length, cast and era are the complete facets.
4. **Themes and collections need a human editor.** LCSH "-- Drama" topics (Man-woman relationships 39,
   Ireland 16, Marriage 11, Fathers and daughters 9, World War 1914-1918 7) are real but thin and
   uneven; a shelf like "Plays for two voices" is data, "Plays that argue about money" is an editor's.
   A small versioned JSON file of editor-made collections is enough (section 5.3).
5. **Pictures for plays are the easy case** (R3b measured 88% with any image) and the pipeline to serve
   them already exists (`catalog/tools/play_art.py`, contract 3.3c) but **the checked-in index carries
   none of it** (no `picture`, `titlePage`, `authorArt` field on any row; the `art_v2` cache is absent in
   this checkout). First fact to settle: is the published index also bare, or only this checkout?
6. **For the rest, extend the label to plays**: board hue from form where the record names one, else the
   neutral board; era dial; voices as rim segments; title block. All facts, none invented (section 4).

---

## 1. Taxonomies and what each one gives us

### 1.1 Library vocabularies

- **LCGFT** (Library of Congress Genre/Form Terms) separates *what a thing is* from *what it is about*.
  Under **Drama** the narrower terms include Radio plays, Religious drama, Puppet plays, Screenplays,
  Tragedies (Drama), Tragicomedies; **Radio plays** also sits under **Radio scripts**, itself under
  Discursive works. Pages: https://id.loc.gov/authorities/genreForms/gf2014026297.html (Drama),
  https://id.loc.gov/authorities/genreForms/gf2018026131.html (Radio scripts); a summary of the
  family: https://www.loc.gov/aba/publications/Archived-LCGFT17/GENRE.pdf. (`id.loc.gov` returned 403
  to the fetcher; the hierarchy above is from search extracts, so the list of narrower terms is not
  exhaustive. A human should open the live term pages before we adopt exact labels.)
  Use: a small closed list of **forms** is the right shape, not a free-text genre.
- **LCSH** is what Gutenberg's `Subjects` carries: `English drama -- 19th century`, `Comedy plays`,
  `Tragedies (Drama)`, `One-act plays`, `Christmas plays`, `Children's plays`, `Farces`,
  `Tragicomedy`, `Historical drama`, `Operas -- Librettos`, `German drama -- Translations into
  English`, and topic strings `X -- Drama` (`Man-woman relationships -- Drama`, `Ireland -- Drama`).
  Counted over our 1,194: Comedy plays 153 books, Tragedies 75, English drama 68, One-act plays 18
  (plus 96 plays whose subject or bookshelf says one-act), Christmas plays 21, Historical drama 18, Farces 12.
- **Gutenberg bookshelves** (https://www.gutenberg.org/ebooks/bookshelf/, 503 during research): ours
  carry `Category: Plays/Films/Dramas` (840 books), `Category: British Literature` (353), `Category:
  Humour` (246), `Nobel Prizes in Literature` (72), `One Act Plays` (39), `Children & Young Adult
  Reading` (32), `Opera` (19), `Harvard Classics` (23), `Banned Books from Anne Haight's list` (10),
  `Classical Antiquity` (12). Useful as ready-made shelves: One Act Plays, Children & Young Adult,
  Nobel Prizes, Classical Antiquity, Mythology, Banned Books. 848 of 869 source books have one.
- **LoCC** (class number, e.g. PR, PT, PQ) is on all 1,194 rows and tells national literature (PR English,
  PS American, PT German, PQ French/Spanish/Italian, PG Russian): a cheap, complete "original
  language / country" signal when the subject lacks it.

### 1.2 Open data

- **Wikidata** for a play (WikiProject Theatre's table,
  https://www.wikidata.org/wiki/Wikidata:WikiProject_Theatre/Properties): genre **P136**, main subject
  **P921**, characters **P674**, language of work **P407**, based on **P144**, author **P50**, librettist
  P87, and from the production section date of first performance **P1191** and location **P4647**. No
  "number of acts" property is listed; the nearest is number of parts (P2635). Genre guidance:
  https://www.wikidata.org/wiki/Property:P136. Coverage for obscure Gutenberg plays is poor
  (R3b: a work item found for 32% of 50 sampled), but strong for the famous few hundred, and the
  data is CC0. Use for: first-performance year (the period facet that LCSH lacks), genre, and a work
  image pointer (section 3).
- **Our own scripts** are richer than any outside record for the facets people filter on: per role
  `lines` and `words`, `sections` (act or scene headings), `lines[].kind` (speech, direction, cue). No
  library or publisher records speaking-part balance.

### 1.3 Publisher and teacher facets (what people filter on)

| Source | Facets seen | URL |
|---|---|---|
| Concord Theatricals (Perform catalog) | total cast size 1 to 50+, roles for women and men (17 and over), category (full-length play, comedy), year, awards | https://www.concordtheatricals.co.uk/perform/catalog |
| Dramatists Play Service Playfinder | author, title, cast size, gender, length, genre, keyword | https://researchguides.library.syr.edu/c.php?g=258180&p=8459836 and https://guides.lib.virginia.edu/c.php?g=637479&p=4462080 |
| Dramatic Publishing | one-act or full-length with run time, "Recommended for" (high school, college) | https://www.dramaticpublishing.com/browse/full-length-plays |
| Playwright.co (an aggregator) | cast size, genre, world region, age suitability | https://playwright.co/plays |
| Doollee (modern English plays since 1956) | exact male-by-female cast (0m5f ... 9+f), synopsis, first performance date and place | https://www.doollee.com/Main-Pages/1Characters.php |
| School Play Scripts guides (a publisher's marketing, so weak evidence for facts, fair evidence for how teachers talk) | start from cast size; look for "character absorption/expansion", chorus, gender-flexible casting; 5-15 minutes for a class piece, 45-75 for a school play; a big class does a set of short scenes | https://www.schoolplayscripts.org/how-do-i-choose-the-right-script-for-a-school-play/ |
| Radio drama strands (BBC): Saturday Drama, The Classic Serial (one-hour adaptations of works of classic status), The Afternoon Play | **by strand and slot length, not by genre**; "classic" is a facet | https://en.wikipedia.org/wiki/Saturday_Drama, https://en.wikipedia.org/wiki/Classic_Serial |
| Old-time radio fan sites | Adventure, Comedy, Crime/Detective, Drama and Soaps, Mystery, Science Fiction, Suspense, Western | https://oldtimeradiolegends.com/ |

Not found despite searching: an official OTRR or RadioGOLDINdex category list online (the shows' own
genre keys in `catalog/tools/genres.py` already serve radio); Doollee and Concord's own advanced
search pages (only third-party descriptions); any monologue/duologue filter on DPS. Teachers' real
need there ("scenes for two") is something we can derive better than a publisher: a *scene* of a play
with two speaking parts (section 2).

**Reading across them:** the order people use is *cast, length, form, audience, then topic or
author*. Two things a performing person needs that no catalog states and we can: **how the lines are
shared** (a lead who carries half the play versus an ensemble) and **how many times a person must
re-voice** (parts that can be doubled). Gender is a facet publishers use; our parts carry no stated
gender (B30 casts by reported voice register; `unknown when unsure`) so we do not publish a
women/men split, and "flexible" is the honest default.

---

## 2. Facets: what we can derive, and from what

Coverage is over the 1,194 library plays. "Now" means a field already in the index row.

| Facet | Source | Coverage | Reliability | Needs a human |
|---|---|---|---|---|
| **Voices** (speaking parts) | index `voices` | 100% | exact (distinct filter: 1-2: 27, 3-4: 89, 5-6: 110, 7-10: 234, 11-20: 398, 21+: 336) | no |
| **Length in minutes** | index `minutes` (words over the app's wordsPerMinute) | 100% | an estimate; show "About M min" (as the tile does). Buckets: up to 10: 69, 11-20: 117, 21-40: 199, 41-90: 284, 91-180: 478, over 180: 47 | no |
| **Balance** (lead share, ensemble) | index `cast` (lines per part) | 100% | exact. 484 plays have no part over 25% of lines (an ensemble); 45 have a part over 50% (a star vehicle) | no |
| **Lines, words** | index | 100% | exact | no |
| **Acts and scenes** | script `sections` (heading text) | to measure; present where the printed play has headings | parse headings: "Act", "Scene"; one-act is also in Subjects (96 plays) | no |
| **One-act / full-length** | Subjects "One-act plays", bookshelf "One Act Plays", else length rule | 96 named; length fills the rest | the rule must be shown as the rule ("under 45 min") | a threshold choice |
| **Form** (comedy, tragedy, farce, history, tragicomedy, Christmas, children's, opera libretto) | LCSH `Subjects` | **398 (33%)** name a form | high where present | for the other 67% only a human (no AI-written label) |
| **Period** (century) | LCSH "-- 19th century" | 287 (24%) | high | no |
| **Era of the author** | `authors[].born/died` and the catalog `Authors` field ("Barrie, J. M., 1860-1937") | 1,067 (89%) with years | high; a translator's years are not the playwright's | no |
| **Year first performed or published** | Wikidata P1191 / P577; Gutenberg "Issued" is the e-text date, not the work's | to measure; famous plays well, others none | only with a work item matched on title and author (evidence-gated) | no |
| **Original language / country** | LoCC (all 1,194), `Subjects` "German drama -- Translations into English" (254 translations) | ~100% | high | no |
| **Translation** (and translator) | Subjects "Translations into English"; Authors field "[Translator]" | 254 named | high | no |
| **Verse or prose** | line-break shape in the script (our reader already keeps verse breaks) | derivable for all | a measured rule (share of speech lines that are short and break mid-sentence), golden-tested | no |
| **Setting, topic** | LCSH "X -- Drama" | partial, uneven | medium | an editor curates what is shown |
| **Occasion** (Christmas, patriotic, Halloween, Mother's Day, Thanksgiving) | Subjects ("Christmas plays" 21, "Patriotic" in collection titles), collection titles ("Christmas Candles", "Patriotic Plays and Pageants for Young People") | small | high where present | an editor builds the rest |
| **Audience** (children, young people, classroom) | Bookshelf "Children & Young Adult Reading" (32), Subjects "Children's plays" (11) | small | medium | an editor |
| **Collection / volume** | index `collection` (521 of 1,194) | 44% | exact | no |
| **Author** | `authors` | 99% | exact | name cleaning only |
| **Characters, famous lines** (search) | script `roles`, `lines` | 100% | exact | no |
| **Similar plays** | overlap of authors, subjects, bookshelves, era, cast shape | 100% | data, not generated | no |
| **Gender of parts** | none | n/a | not stated in sources | refuse (Section 1.3) |

Data defects that finding would expose (read from the 30-play sample): **three of 30 are not a play
by the title shown**: "Edited by Havelock Ellis" (a volume's editor line used as the title, Otway),
"Politics" (a very short 9-minute piece among a collection), and "The Glebe 1913/12 (Vol. 1, No. 3)"
(a magazine issue, with Charles Demuth as author). Titles are the primary key of a search and a tile,
so a title audit belongs in front of any browse UI (the display-text ruling of 2026-10-31 applies: composed from data).

---

## 3. Images for plays

### 3.1 What exists already (do not re-research)

`R3b-image-sources.md` section 4.2 measured 50 plays: scanned edition on archive.org dated 1930 or
earlier **70%**, work-level image of any kind 76%, author portrait with evidence 56%, any image **88%**.
`play_art.py` builds `titlePage`, `authorArt`, `picture` (lead order: production photograph, then
work image, title page, author portrait; Federal Theatre Project photographs only on an exact title and
author) under `art_policy`, to be attached by `build_play_library.attach`. In this checkout none of
those fields are present on any of the 1,194 rows and `catalog/.cache/art_v2` does not exist, so the
art harvest has not run here. That is a pipeline run, not a research question.

### 3.2 Sources and rights evidence

| Source | What it holds for plays | Rights evidence | Match method | Notes |
|---|---|---|---|---|
| **The book itself** (Gutenberg HTML: frontispiece, plates, title page images) | Illustrations of the exact edition the script came from | The HTML edition's own date: a pre-1931 publication is public domain in the US by age; the e-text is cleared (our rights bucket) | Exact: same book id, no matching | Highest precision. Gutenberg's HTML images ship in the zip (`pg<id>-images.html`). Not yet harvested; coverage unknown until the HTML is scanned. Reuses the file we already have |
| **archive.org first-edition scans** | Title pages, covers, frontispieces, playbill pages | item `date` of 1930 or earlier (R3b, `edition_served`) | title plus author surname against a creator field | 70% of sample; **about 8 in 35 are collected editions** (a play inside a volume) so a title page of the volume fits only with the volume named; page images via `https://archive.org/download/{id}/page/n{leaf}_w800.jpg` |
| **Wikimedia Commons** (via Wikidata P18, P996, enwiki lead image) | Production photographs, scans of editions, posters, playbills | per-file license template and categories (`extmetadata`) | Wikidata work item with title and P50 author match | 5 of 50 had a work P18; 7 of 50 a free enwiki lead image. Highest quality for the famous plays (Chantecler 1911 production photo, Major Barbara, Timon of Athens) |
| **Library of Congress** (Prints and Photographs, Theatrical posters, Federal Theatre Project) | Posters, production photographs | "No known restrictions on publication" is a statement, not a license; closed by owner question V2 | exact production title plus author | FTP reaches only 2 of the 803-play library (R3b/catalog 041) |
| **NYPL Digital Collections** (Billy Rose Theatre Division) | Playbills, production photos, scripts | per-item rights statement and public-domain flag | needs an API token (owner question V6) | Not measured |
| **Folger Shakespeare Library** (LUNA) | Quarto and folio title pages, playbills for early modern drama | per-image statement, much CC BY-SA, credit required | Shakespeare plays (43 here) and early modern | Not measured |
| **HathiTrust** | First editions where archive.org has none | rights code `pd`/`pdus` | bibliographic API | Not measured |
| **V&A** | Theatre and Performance collections, playbills, posters | per-record terms; many are not open | by title | Not measured; do not plan on it |
| **Author portrait** (Wikidata P18, dated person match) | The playwright's face | as for radio people (Decision 069, V4 face box) | dated match to a human | 56%. Honest fallback, but an author on thirty plays (Shaw 30, Ibsen 30, Strindberg 25) makes every one of them look the same, which is the opposite of the owner's ask |

### 3.3 What image is useful for telling plays apart

An author's portrait does not distinguish plays; a title page does only by its lettering; **a work-level
picture does** (production photograph, frontispiece, poster, playbill). Order for a play window, taking
the artwork rules (`artwork-presentation-design`: the slot takes the picture's shape; no blur and bars):
**production or poster, then the edition's frontispiece or plate, then the title page, then the author
only on a play page header (not in a rail of thirty by one writer), then the label.** A title page
read at 90 px is lettering; it is worth showing larger on the play page and in the hero, and in tiles
only when it passes the size floor of `uniform-imagery-design`.

### 3.4 Hand sample: 30 plays, what is findable (2026-11-26)

Method: 30 plays drawn at random (seed 31) from the index; per play, archive.org advanced search on
title and creator surname with date up to 1931, English Wikipedia search and page summary, Wikidata
author search and P18 claim; then read by eye. Scripted lookups are loose (first search hit), so
the numbers below are by-eye corrections of the raw counts, in the same direction as R3b.

| Route | Raw | By-eye estimate |
|---|---|---|
| archive.org scan dated 1930 or earlier found for title and surname | 24 of 30 | about 18 of 30 name the play itself (Candida, Deirdre of the Sorrows, Alladine and Palomides, Don Carlos, Nathan the Wise, The Count of Narbonne 1781, Phormio, Pariah, Tristan and Isolda...), the other six are collected volumes or a different work (The Bear and The Anniversary in a Chekhov volume; "Good Friday" is a poem) |
| English Wikipedia article for the work (a play article, not the author or an unrelated page) | 11 of 30 | 11 (Trifles, Candida, How He Lied to Her Husband, Tristan und Isolde, Don Carlos, Phormio, Pariah, Nathan the Wise, The Bear, The Count of Narbonne, El mágico prodigioso) |
| An image on that article | 8 of 30 | not all free: each must pass the Commons license check |
| Author with a Wikidata portrait | 18 of 30 | about 15 (the search takes the first hit, which for "Politics" and "Robin Hood and the Sad Knight" is a wrong person) |
| No image of any kind from the above | 6 of 30 | the obscure and the not-plays: Bill Porter (Upton Sinclair), The Glebe issue, Edited by Havelock Ellis, Politics, Robin Hood and the Sad Knight, To Florence Farr |

Reading: **roughly 60% of plays have a plausible edition scan, a third have a work page, and a fifth
have nothing** (the not-plays and the obscure). This matches R3b's 88% only if author portraits are
counted, which section 3.3 argues should not be the lead. So expect work-level images for
about 60% and the label for the rest. The picture will not carry the distinction on its own, which is
why section 4 matters most.

### 3.5 Matching rules (carry the 2026-11-21 image rule)

An image is used unless its record marks a restriction. A match needs the title plus the author on the
candidate's own record (R3b: a title alone is no identity); a collected-edition scan is a title page
of the volume, labeled as the volume or not used as the play's lead; a date after 1930 passes only on
the record's own license evidence (Commons, NYPL's PD flag); CC BY and BY-SA carry credit wherever
shown at header size. The Gutenberg book's own HTML illustrations need no matching and should be
tried first.

---

## 4. Visual designation without an image: the label for plays

### 4.1 What shows have now

Decision 081 and WEB-DESIGN 6.4r: a flat **transcription disc** drawn from the item's own fields on its
**genre board** (`color.board`, one OKLCH lightness and chroma per mode, so a grid reads as one set), a
**run arc** on a fixed 1930-1962 dial, the monogram on the center label, a rim "NETWORK · 1940s" at tier L
(320 px and up), tiers S (under 96), M, L, geometry in `design-tokens.json` `art.label`, one pure
`labelSpec` with golden cases on three stacks. A finished ear drama already shows one rim segment per
speaking part in the part hues, sized by share of lines. Stage plays today (6.4r) are the exception:
the script page with 1-4 voice rules at its foot, or cast bars on the drama board when no opening
exists. **Every play therefore wears the same drama board**, which is exactly the owner's "no visuals
that help them distinguish themselves".

### 4.2 Proposal: the play's label

Keep the disc, the tiers, the mount, the edge and the golden-test discipline; change what the data
drives. All fields are published or derivable now; nothing is hashed.

| Element | Drives it | Coverage | Rule |
|---|---|---|---|
| **Board hue** | **form**, only where the record names one: comedy (and farce) to the `comedy` hue; tragedy and history to `drama`; one-act and opera libretto and others to their nearest existing genre key; **no form: the neutral board** | 33% named | A hue means something or it is neutral. We do not guess. A play with an unnamed form and no hue is honest, and "nothing on the label is invented" holds |
| **Era on the dial** | author's years (89%) or LCSH century (24%); a **bucketed dial**, because 2,500 years do not fit a linear one: Antiquity, Medieval, 1500s, 1600s, 1700s, 1800s, 1900-1930 | ~89% | the arc's slot is the author's life span within the bucket; none when undated, as the shows' |
| **Rim segments** | one per speaking part, **largest first, from the top, widths by share of lines** (the ear-drama grammar) in the **board's one color** (not part hues; part hues are the reader's and a finished drama's, and 12 hues on a dozen discs would shout) | 100% | at S, three marks for 1-2, 3-4, 5-8, 9+ voices (as the page's rules do); at M and L, every part up to seven, "+N" after |
| **Label (center)** | the play's **monogram** (first letters of title words; first title letter as the shows') on the center disc, sized by tier | 100% | what `API.monogram` already does |
| **Rim text (tier L)** | "SHAW · 1890s" (author surname and decade of the author's active years or the century), else "ONE ACT · 18 MIN" | 100% for the second form | sourced facts only |
| **Length** | **disc radius is fixed**; length is a short tick scale on the foot ("under 20", "about an hour", "evening") or the existing "About M min" fact line, not a size | 100% | do not encode length as area: a 558-minute volume would swallow a grid |

This shows three independent signals at a glance (hue = form where known, rim = how many voices and
how they share, dial = when) plus the title block. A grid of thirty Shaw plays will differ by cast
rim and length, which is exactly what a performer compares. The page-window with the opening speeches
remains the **Detail and tile** art where the opening exists ("scripts you could speak", the
2026-11-15 review); the label is the art where there is no picture, at the same slot, so it replaces
neither. The label sits in the `uniform-imagery-design` slot: same crop rule, same hairline edge, same
size floor, nothing drawn beside or over a served picture of the same object.

Typography: title in Big Shoulders Bold on the board, four lines at most (as the play tile now),
author in Public Sans, three weights by two sizes only; do not add a seventh level (AGENTS.md).

### 4.3 What this costs and what to test

A new `play` branch in `labelSpec` (and its golden cases, three stacks), an era-bucket dial in
`design-tokens.json`, a published `form` field on the library row (see 5.1), and `web_fit_label.py`
cases for plays. Test: 40 plays at S, M, L in light and dark; every pair among 30 Shaw plays and 30
Gutenberg short farces is told apart without reading the title; the neutral board is not read as an
error. Per the owner's rule, a picture where there is one wins (3.3), and the label is the default.

---

## 5. Ways of finding

### 5.1 Facet browse (data, complete)

The "Find a play" surface leads with the three complete facets, as chips with counts:

- **Voices**: 1-2, 3-4, 5-6, 7-10, 11+ (counts above). "Plays for four voices" is a direct filter and a
  share URL. Do not offer gender.
- **Length**: under 10, 10-20, 20-40, an hour, a full evening. The 186 plays of 20 minutes or less are
  the starting shelf for a class or a first recording.
- **Form**: only the forms we hold (comedy, tragedy, farce, history, one-act, children's, Christmas, verse
  from the line-shape measure), with an honest "Unlabeled" bucket.
- **Era**, **Country / language** (LoCC, translations), **Author** (A to Z), **Collection** (the book it
  came from, 521 plays), **Subject** (the top LCSH topics, only those with at least five plays).

Facets must follow `universal-feature-states` (empty, loading, error) and counts must come from the
data, not a list written by hand. "Sort": shortest, A to Z (as the grid has now), and **fewest voices
first**.

### 5.2 Collections that are data

Each is computed, named from the record, and costs nothing to keep true:

- Gutenberg bookshelves: One Act Plays (39), Children and Young Adult Reading (32), Nobel Prizes in
  Literature (72), Classical Antiquity (12), Mythology, Banned Books (10).
- LCSH forms and topics: Christmas plays (21), Farces, Historical drama, Ireland, Marriage, World War.
- Authors with five or more plays; a volume's plays together (the existing `collection`).
- By cast shape: "Two-handers" (voices 2), "Ensemble pieces" (no part over 25% of lines), "A star and a
  supporting cast" (a part over 50%).
- By length: "Ten minutes or less", "Under half an hour".
- **Similar plays** on a play's page: same author, same subject, same cast shape and length; a rule
  shown as the rule ("Same voices and length"), never a recommendation engine (`values-based-feed-ranking`).

### 5.3 Collections and themes that need an editor

A theme ("plays about a marriage that is a negotiation", "good first ear dramas for a class of ten",
"plays that need a chorus") is a judgment. Per the owner's rule, **lists come from a human editor or
the data, never written by an agent**. The lightest file that supports it:

`catalog/plays/collections.json`, one entry per collection, in the same diffable style as
`plays/phoneme-corrections.json`:

```
{ "id": "...", "title": "...", "by": "editor name or source",
  "note": "one sentence in the editor's words (optional)",
  "plays": ["gut-4023", "gut-3544"], "added": "2026-11-26" }
```

Rules: a play id that stops resolving fails a test (as `tests_never_pin_catalog_contents` allows only
shape tests: no fixed counts); `by` is shown as the credit; a collection with fewer than three
playable plays is not published; no generated text. A teacher or a person in the app could contribute
a collection through the same file in a later round (an owner decision, see section 7). The same
file serves "Plays for the Fourth of July" and "Shaw in an hour" by hand.

### 5.4 Occasion and season

From data where it exists (Christmas plays 21, Patriotic collections), from the editor file otherwise.
Today's date can lead a shelf ("For Christmas", in December) from the file, with no calendar logic in
three clients: one published field `season` on a collection, read by all.

### 5.5 Classroom

Classroom need is cast size and length plus honest reading difficulty. Offer the filters (voices, length)
and a `Children and Young Adult Reading` shelf; let a teacher's **class bundle** (the existing feature,
owner 2026-11-19) be the place a class picks. Do not publish an age rating (no source; a wrong one is a
claim). The ability to **double parts** (a large class on a small cast, or the reverse) is a casting
feature in the studio, not a catalog field, and "character absorption/expansion" is exactly what B30's
casting already does.

### 5.6 Search inside plays

Characters (`roles`) and lines (`lines[].parts[].say`) are in every script. Search should return a play
by a **character's name** ("Candida", "Shylock", "Hedda") and by **a spoken line**, showing the matched
line as the transcript hit does for shows (the owner's 2026-10-28 ruling: "search names spoken words").
This is the cheapest large gain: a person who remembers a scene or a speech finds it without knowing
the title.

### 5.7 Scenes: monologues and duologues

The need teachers state is a scene for two. Our scripts' `sections` plus `lines` let us compute, for
each scene, its speaking parts and length: "Scenes for two voices, under five minutes". Derivable for
every play with headings, golden-testable, and not offered by any publisher. Largest practical gain
for a class that cannot do a whole play; needs an owner check that recording a scene is in scope.

---

## 6. Recommendations (in build order)

1. **Run the play art harvest and publish** (`play_art.attach`); confirm the published index carries
   `picture`/`titlePage`/`authorArt`; try the book's own HTML illustrations first (exact, no matching).
2. **Audit titles**: repair or hold the not-a-play rows (volume editor lines as titles, magazine issues);
   one rule, one test.
3. **Facet browse on voices, length and form** over the existing index, with counts, share URLs, and
   fewest-voices and shortest sorts; add `form`, `era`, `country`, `verse` to the row (published once
   in the catalog, three clients read them, per `shared-data-plane-contract`).
4. **The play label** (4.2) as the default window art; golden cases on three stacks.
5. **Data collections** (5.2), then the **editor collections file** (5.3) with the first ten written by
   the owner or a named editor.
6. **Search over characters and lines** (5.6), then **scenes for N voices** (5.7).
7. Wikidata enrichment (first-performance year, genre) for famous plays only, evidence-gated,
   after the above.

Parity: all of this is a client read of published fields; web first, then Apple and Android in the
same change set (PARITY.md rows: Find a play facets, Play label, Collections). tvOS records nothing
(WEB-DESIGN 6.4f: the TV records nothing), so it takes the label and shelves but not the record door.

---

## 7. Questions for the owner (kept minimal)

1. **Who writes themes and collections?** You alone, a named editor, or also teachers and
   players through the app (changes whether the file is repo-only or a Worker feature)?
2. **Scenes**: is recording one scene of a play (a two-handed scene under five minutes) in scope, or
   whole plays only?
3. **Unlabeled form on the neutral board** (4.2): acceptable that two thirds of plays have no hue
   until an editor or a source names the form, or would you rather every play have a hue by era instead?

Everything else here is decided by the rules already on file.

---

## Sources

- LC Drama term: https://id.loc.gov/authorities/genreForms/gf2014026297.html
- LC Radio scripts term: https://id.loc.gov/authorities/genreForms/gf2018026131.html
- LCGFT overview PDF: https://www.loc.gov/aba/publications/Archived-LCGFT17/GENRE.pdf
- Gutenberg bookshelves: https://www.gutenberg.org/ebooks/bookshelf/ (and the pipeline's `pg_catalog.csv.gz`)
- Wikidata WikiProject Theatre properties: https://www.wikidata.org/wiki/Wikidata:WikiProject_Theatre/Properties
- Wikidata genre P136: https://www.wikidata.org/wiki/Property:P136
- Concord Theatricals Perform catalog: https://www.concordtheatricals.co.uk/perform/catalog
- Dramatists Play Service (via library guides): https://researchguides.library.syr.edu/c.php?g=258180&p=8459836 ; https://guides.lib.virginia.edu/c.php?g=637479&p=4462080
- Dramatic Publishing: https://www.dramaticpublishing.com/browse/full-length-plays
- Playwright.co: https://playwright.co/plays
- Doollee: https://www.doollee.com/Main-Pages/1Characters.php ; https://www.doollee.com/Characters/More-info.php
- School Play Scripts (marketing guides): https://www.schoolplayscripts.org/how-do-i-choose-the-right-script-for-a-school-play/ ; https://www.schoolplayscripts.org/where-can-i-find-short-drama-scripts-with-a-small-cast-for-my-schools-theater-club/
- BBC strands: https://en.wikipedia.org/wiki/Saturday_Drama ; https://en.wikipedia.org/wiki/Classic_Serial
- Old-time radio categories: https://oldtimeradiolegends.com/
- In-repo: `docs/research/design/R3b-image-sources.md` (4.2), `docs/research/design/R3a-visual-cohesion.md`,
  `docs/WEB-DESIGN.md` 6.4r, `DECISIONS.md` 069 and 081, `catalog/tools/play_art.py`.
