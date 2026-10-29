---
name: catalog-experience-design
description: Use when designing how a LARGE, UNEVENLY DESCRIBED catalog (tens of thousands of items you did not author, most of them sparse) is found, listened to or watched, made from, and shared, on any platform. Carries the rule that the sparse record is the common record and is designed first; the coverage test for what earns a place in a list row versus Detail; drawing the line between the real works and the long tail of uploads; when shelves, timelines and calendars, faces, run strips, and decade-by-genre fields each fit; what to surface and how to rank it (data rules shown as the rule, chance inside a chosen scope, never engagement bait); the event line, liner-notes credits, copies named by what differs; the making flow as a cast sheet and a call sheet; share pages and cards made only of facts; and the anti-patterns the Ear Drama audit found. Triggers on browse, list row, metadata in rows, detail page, "too much metadata", "only lists", shelves vs, carousel, discovery, home screen, catalog overview, facets, timeline, calendar view, people grid, face wall, sparkline, run of a series, sparse records, empty fields, long tail, uploads, single recordings, now playing, credits, versions, copies, share card, link preview, invite page, premiere page.
---

# Catalog experience design

How to present a catalog of tens of thousands of items that someone else
described, unevenly, so that a person can **Find** something worth their
time, **Listen** (or watch, or read) to it, **Create** their own from it,
and **Share** it. The picture rules are `artwork-presentation-design`;
density is `mobile-first-density-design`; ranking values are
`values-based-feed-ranking`; whether an item may be shown at all is
`evidence-gated-catalog-curation`. This skill is the layer between them:
what each surface shows, from which fields, in what order.

Worked example: Ear Drama, 2026-10-29, the design loop's research
(`docs/research/design/D1a-finding.md`, `D1b-listening.md`,
`D1c-making-sharing.md`) and synthesis (`D2-directions.md`).

## Measure the catalog before you draw it

Every rule below is a threshold over coverage, so the first design act is
counting. For each surface, measure on the real published data (all of it
if you can, a stated sample if not):

- how the items are distributed (how many works hold how much of the
  catalog: a long tail of one-item "series" is the usual shape);
- each field's coverage, overall, on the tail, and **on what people
  actually play or open** (the played catalog is usually far richer);
- how many items have a picture, and of what (works, or people);
- which keys every item has (date, length, title) and which few have
  (credits, sponsor, transcript).

Ear Drama: 10,642 "series", but 7,189 (67.6%) hold one episode and the
1,374 with ten or more hold 85.8% of the episodes (D1a §1.1). 65.5% of
episodes carry no credit, network or sponsor, 48.4% are dated, 5.1% carry
all of date, network, sponsor, cast and writer; in the 100 most
downloaded series those numbers jump (76% dated, 65% a network, 56% a
cast) (D1b §1). Only 271 series (2.5%) have a portrait, but 613 of the
1,795 people heard on 20 or more episodes do (D1a §1.3). Without these
numbers every design in the loop would have been drawn for the
Suspense page, which is the rare page.

Why: designers draw the richest record because it is the most fun to
draw. A design that only looks finished when every field is present
looks broken on most of the catalog.

## The rules

### 1. Design the sparse record first; the bare page is the common page

Draw every item surface for the record with only its required fields
(title, length, maybe a date) before you draw the rich one, and make
that page look finished: nothing promised that is absent, no empty
headings, no "Unknown" placeholders, no gray boxes. Then let richness
add sections, never slots. A missing field draws nothing; a missing
picture draws the typographic card (`artwork-presentation-design` §9);
a missing date says "Undated" once, where the date would be.

Never imply a fact from absence. Lux Radio Theater shows 0% sponsor
because of a gap in the dated sponsor runs, not because Lux was
unsponsored (D1b §1): a page must not say "no sponsor".

### 2. Draw the line between the works and the tail, and say where it is

When most rows are single uploads, a catalog's counts, default sort and
first screen belong to the works, and the tail is one counted scope one
tap away: "1,374 shows" with "7,189 single recordings" beside it, never
hidden, never the default (D1a §4.1, the two-tier catalog). The
threshold is a published pipeline rule (one predicate every client
reads), not a client filter. Search ranks works first and the tail after
the episodes. The same rule applies to any list that mixes them: a day's
listings show the shows, then "9 single recordings".

### 3. A field earns a list row only by coverage and by choice

A field goes in a row only if it is present on most rows **of that
surface** and it helps a person choose **between those rows**. Below
about a third coverage, or as a list of more than two values, it moves
to Detail. Anything that repeats the section heading is cut. Ear Drama's
table (D1a §1.5, §5):

| In the row | Only on Detail | Never in a row |
|---|---|---|
| the face if any, title, series (mixed lists only), the date (tabular on a series' log, the year on mixed lists), length, for a series its core years + count + run strip, an arc part ("Part 2 of 5"), at most one guest name when it differs from the series' regulars | networks, sponsor, writer, director, announcer, the full cast, copies and formats, the rights line, transcript, download counts | a field under a third coverage on that surface, a list of more than two values, a value the heading already says |

Derived fields beat raw ones in rows: the **core years** (the 5th to
95th percentile of dated episodes) instead of first-to-last, which made
Inner Sanctum read 1941-1999 because of one rebroadcast (D1a Verdict 4);
a **display title** from the pipeline instead of the file name ("Aud
RobtWPerryCase", "(OTR)") (D1b Pattern 3).

### 4. Pick the overview that matches the strongest key the data has

Shelves show six items of an unknown whole (D1a Verdict 6). Choose the
way in from what the catalog actually carries, measured:

| Way in | Fits when | Ear Drama |
|---|---|---|
| **Calendar / day** | most items are dated and the date is the identity (broadcasts, newspapers, letters) | 49% dated; every calendar day survives (116 to 232 broadcasts); 95% of dated episodes share a night with another broadcast (D1a §1.4, D1b §1). The day was radio's own finding aid (newspaper logs, Radio Times, BBC Genome) |
| **Run strip** (a word-sized sparkline per series) | a series spans years and its gaps matter | per-year counts of dated episodes; Suspense's twenty years vs Dark Fantasy's one (D1a §4.2) |
| **Decade-by-genre field** (counted cells, tap to set both facets) | two facets with few values cover most works | 8 genres by 5 decades; the 1940s mystery boom is visible at a glance (D1a §4.5) |
| **Faces** | people are pictured far more than works | 613 frequently heard people have portraits; 2.5% of series do (D1a §4.3) |
| **Facets with counts** | open browsing over many works | Hearst: 90% of 32 users preferred facets for open tasks; never offer a choice that yields zero |
| **Shelves** | a ranking model or a named human fills them per person | neither exists, and AI-written lists are refused: a rule shelf shows everyone the same six (the firehose tell) |
| **Map or globe** | items are places a person navigates by | refused: networks and call letters are not places (D1a Refused) |

Use several partial overviews (Whitelaw's parallax) rather than one
definitive one, and let each open into the same facet state, so the
calendar, the field and the faces agree with Browse's counts.

### 5. Surface by a stated rule; chance stays inside a chosen scope

Every machine-chosen list is a data rule named in its heading ("Most
heard", "This day in radio", "By the year a show first aired"), the same
for everyone, computed in the pipeline once, carrying any
never-recommend flag (`values-based-feed-ranking` §5). Editorial lists
need a **named human**; without one there are none (no AI-written lists
or blurbs). Surprise draws inside the scope the person chose (a cell, a
decade, a person, a date) and hands back its reason as a fact ("Same
night: October 29, 1944"), because chance alone is barely used (Cooper
Hewitt's random button: 2% of visits; color browsing 49%) and a chance
find needs a reason to become insight (André et al.) (D1a §2.2, §4.6).
Rank by what a person can inspect and change: never by time spent,
streaks, plays-per-hour, or likes; no counts of other people's
attention on making or sharing surfaces (D1c refused).

### 6. One item is an event, then liner notes

On an item's page and its player, the top is the picture, the series,
the title, **one event line of at most three facts** ("CBS · Thursday,
December 2, 1943 · Roma Wines"), and the primary action with the
length on it ("Play · 30 min") (D1b §3, Pattern 1). Season and log
number leave the head (the season is the series' scope; the number is
provenance and the untitled fallback).

Then, in this order and only where data exists: who was on as **up to
three faces** (the measured median of portraits on a credited episode is
3; D1b §1), the item's **neighbors** (the same night, the same voice,
other performances of the same script, the next part of an arc), then
the **booklet**: credits grouped as On the air, Writing, Production,
one line per person with all their roles, behind one closed control
(Apple Music's three groups; D1b Pattern 2). **Copies** are named by
what differs (an Armed Forces rebroadcast, an incomplete copy, a length
that differs), never by archive identifier or bit rate; identical
copies are a count behind a disclosure (D1b Pattern 7). The rights line
stays, in the catalog's own published words.

Whose face leads (data order, or a published billing rule that prefers
the series star then the night's guest) is a ranking: publish it from
the pipeline, never compute it on a device, and get the owner's call
(D1b §3). A guest is "a face not heard on a quarter or more of the
series' episodes" or a similar published rule, so a regular (Hans
Conried on most 1943-44 Suspense broadcasts) does not crowd out Cary
Grant.

### 7. The listening screen is calm above the fold and readable below it

Above the fold: the art, series, title, event line, scrubber, transport,
and one row of the two options people use (speed and the sleep timer;
everything else in More). Below it, one gesture away: who was on, the
transcript when one passes the gate, the neighbors, Up next (D1b §4,
Pattern 6). No animation that says nothing (no fake waveform). What
plays next is the owner's rule, never inferred.

### 8. Making is a cast sheet, a prompter and a call sheet; keep it literal

The metaphor of collaborative making already exists in the domain; make
it lighter, not new (D1c §6). Size every part in the unit people think
in (minutes from words, "about 7 min"; "<1 min" for walk-ons), shown as
a fact, never a "beginner" label; ask the performer's name once, not on
every row; suggest without assigning. The recorder is one red control
with Keep beside it and the cue line, your line, the next line. The
shared state is a **call sheet** grouped Waiting on (with the date a
claim lapses), Open, Done, and the owing person sees "Waiting on you" on
their own list; no nagging, no streaks (D1c Patterns 3, 4). Account
gates go at the first take, not at the door (Duolingo's sign-up move;
D1c §2.2).

### 9. A share is a page of facts, before anyone taps

Every shared link answers a crawler with a real page: title, type, URL,
a representative image (the typographic card rendered from data, a few
large words), and a description made only of the record's fields (date,
network, "12 parts · about 26 minutes") (D1c Pattern 1). One URL shape
everywhere. An invitation says what it invites you to before sign-in:
the play, the part meant for you, who is already in, how long it is open
(D1c Pattern 2). A finished production's page credits people only as
they chose to be named, lists only published work, never ranks it
(D1c Pattern 5). A moment is shared as the script's own line or a
timestamp, never as copy the app wrote (D1c Pattern 6).

### 10. Verify at both ends of the catalog

Render every surface with the richest and the barest real records
(Suspense 1943-12-02 and a 1945 news file with no credits; Suspense and
a two-episode undated series), at 375 px and 1440 px, and look at the
PNGs. Then count: what share of the catalog gets the bare page? That
page is the product.

## Per-platform idiom

Same verbs, native idiom (`cross-platform-parity-discipline`). What
changes per platform is how the overviews are drawn:

- **Web**: the run strip and the field as inline SVG or CSS grid; the
  date as a route with a path twin (`/date/1944-10-29`); `<details>`
  for the booklet and copies; one row component for every log.
- **iOS / iPadOS**: `List` sections with `DisclosureGroup` for the
  booklet; the run strip as Swift Charts or a `Canvas` with an
  accessibility label that says it in words ("aired 1942 to 1962, most
  in 1944"); faces as `LazyVGrid`; a `DatePicker` limited to dates with
  broadcasts; iPad uses the width for Detail's two columns, not a
  stretched phone.
- **macOS**: the same Core and views; the field and the day listing suit
  a sidebar-plus-table window; keyboard moves between years.
- **tvOS**: focus does the work: faces and nights as focus shelves, the
  strip drawn only on the focused card, the field as a focus grid with a
  clear focused cell, no free date entry (a year strip instead), 29 pt
  body floor (`tvos-platform-patterns`, `ten-foot-detail-design`).
  Making stays off the TV; a share is a QR code of the same URL.
- **Android**: `LazyVerticalGrid` for faces, a Compose `Canvas` strip
  with a semantics description, the Material date picker, `ModalBottomSheet`
  for the booklet on a phone.

## Anti-patterns (each seen in the Ear Drama audit)

- **Counting the tail as the catalog**: "10,642 series" when 7,189 are
  one file each; Search putting a Decca record above the eight real
  Suspense performances (D1a §3.1).
- **A shelf that misrepresents its rule**: "Most downloaded" ranking
  series but showing each one's earliest episode, so the most popular
  shows are introduced by their auditions (D1a §3.1).
- **Raw first-to-last years and network lists in rows**: "1941-1999",
  "NBC, NBC Red, Blue, NBC Blue, ABC Blue, AFRTS, Bllue" (D1a §3.2).
- **A facts line of five dot-separated fields** with a season and a log
  number in the item's head (D1b §3).
- **The credits list as the page's body**: nine role headings for nine
  people, a character credited twice, cast-list fragments as people
  (D1b §6.1).
- **Copies as the archivist sees them**: six rows of identifiers and bit
  rates (D1b §6.1).
- **Four equal option buttons on the player**, as heavy as the transport
  (D1b §6.3).
- **Eight primary-colored buttons in one column** ("Listen live" on every
  station): one primary per view; the row tunes (D1a §3.2).
- **Season chips past the fourth** in a sideways rail hiding the run's
  shape (27 for Jack Benny) (D1a §3.1, D1b §6.2).
- **A name field on every row** of a cast sheet; a part named by its
  printed abbreviation ("HAM") (D1c §3.2).
- **An invitation that asks for an account before it says what it is**
  (D1c §3.2).
- **Links that preview as nothing** (404 to every crawler) (D1c §3.1).
- **Offering a choice that yields zero rows** ("Has a script (0)").

## Worked example: Ear Drama's three directions (2026-10-29)

D2 built three whole-app prototypes from these rules on the same data
sample (`docs/research/design/directions/`): **A, The Almanac** (the
date leads: the day's listings, the run strip, the decade field, That
night on every dated episode), **B, The Company** (people lead: a wall
of the most-heard voices, guest faces in an anthology's log, the cast as
a playbill), **C, The Sleeve** (one cover per screen, then the item's
story in chapters of data: the run, the night, who was on, the
booklet). All three keep the same row rules, event line, booklet,
copies and share rules above; they differ in which overview leads. The
comparison and the owner's open questions are in
`docs/research/design/D2-directions.md`.

## See also

- `artwork-presentation-design`: the slot takes the picture's shape;
  faces at the published face box; the typographic card as default art.
- `mobile-first-density-design`: density by removing chrome; only
  essential words on screen.
- `values-based-feed-ranking`: any ranking is a values decision;
  never recommended, always findable.
- `evidence-gated-catalog-curation`: what may be shown or said at all;
  wrong matches; versions.
- `learning-orientation-design`: every overview should teach the
  domain's shape, not hide it behind "for you".
- `make-it-look-like-itself`: the three-directions method this loop
  borrowed for the whole app.
