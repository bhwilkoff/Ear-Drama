# Direction A: The Almanac

*D2, 2026-10-29. Prototype: `index.html?s=home` in this folder. Skill:
`catalog-experience-design`. Data: `../shared/sample.js`, a 150 KB sample
of the live projection generated 2026-10-29T16:30Z.*

## Metaphor

The newspaper radio log and the collector's series log. In 1944 a listener
found a program by **when**: a page of the day's listings by station and
hour, with gaps where nothing was printed (D1a §2.4). BBC Genome, the
Library of Congress's "Jukebox Day by Day" and the OTRR logs all keep that
unit (D1a §2.3, D1b §2.4). The Almanac makes the date the way in, the way
along (a series is its run of dates), and the way out (every dated
broadcast sits in the night it aired). The look is a typeset page: heavy
rules over sections, a tabular left column (time, date, size of a part),
hairlines between rows, no tiles in the logs. The picture is the date
itself, set large like the typographic card.

## What it surfaces

- **Home**: today's date as the card ("October 29", 138 surviving
  broadcasts in 28 years), a strip of the years that date survives in with
  the busiest marked, that year's night as a log (shows first, then "N
  single recordings"), and Tonight on Stations with runs of gaps merged
  into one row ("Not surviving until 11:00").
- **Browse**: one chip row; the decade-by-genre field (counted cells in
  the genre hues, "By the year a show first aired", the 477 shows with no
  genre said as a count); then "1,374 shows" with "7,189 single
  recordings" beside it, each show a row of name, core years, count and a
  run strip on one shared 1930-1962 axis.
- **A series**: the typographic card, then the run strip large as the
  season scope (tap a year), then the log: date, title, the night's guests
  (faces not heard on a quarter of the season, so Hans Conried, a regular,
  never crowds out Cary Grant), length, play. On a phone the date stacks
  above the title (WEB-DESIGN §6.4).
- **An episode**: the event line ("CBS · Thursday, December 2, 1943 · Roma
  Wines"), Play with the length, three faces, the booklet, the transcript
  and copies closed; then **That night**, the other surviving broadcasts of
  that date, beside the episode from 768 px.
- **Now Playing**: the date in the top bar, the face whole, the event line,
  the transport, two options; That night below the fold.
- **Create**: the plays listed by reading time like a program listing
  (radio plays, then stage plays); the cast sheet as a log of parts by size
  ("7 min", "<1 min") with one name field; the prompter; the finished
  production as a listing with its recording dates.

## What it hides

Networks, sponsor, writers and copies leave every row; seasons as chips;
the log number (provenance); the tail's single recordings from the first
screen (one tap away, counted). Undated episodes (51%) are absent from the
day views by definition and stay on their series pages and in Search, which
is the direction's main cost: half the catalog has no place in its
signature view.

## The sparse record

Stay Tuned For Terror (two undated episodes, Syndicated): the card, a
two-row log led by "No. 31" and "No. 32", nothing promised. The 1945 news
file: title, the date line, Play, the rights line, and That night, which
gives a bare record six real neighbors. That is the Almanac's best answer
to D1b Verdict 1: the date makes a bare page a place.

## Cost per platform

| Layer | Size | Work |
|---|---|---|
| Pipeline | M | Per-series year histogram and core years in `index/series.json`; the show tier (10+ episodes) as one published predicate; a `sameDay(id)` contract verb with shows first; display titles; the decade-by-genre matrix as published facet counts; the role-to-group map for the booklet |
| Web | M | Inline SVG strips and the field as a CSS grid; a date route `?date=1944-10-29` with its `/date/` path twin; `<details>` booklet |
| iOS / iPadOS | M | `List` logs; Swift Charts or `Canvas` strips with a spoken summary; a `DatePicker` limited to dates with broadcasts; That night as a section; iPad puts it in a second column |
| macOS | S after iOS | Shared Core; the day as a table; arrow keys move between years |
| tvOS | M | Years as a focusable strip (no free date entry); the night and That night as focus shelves; the strip drawn only on the focused show |
| Android | M | Compose `Canvas` strips with semantics; the Material date picker; `LazyColumn` logs |

Every platform adds one deep link (the date).

## Which D1 findings it answers

- D1a Verdict 3 and §4.4 (the date is the strongest key; a calendar into
  the archive), §4.1 (two tiers), §4.2 (run strip), §4.5 (the field), §3.2
  Stations (merge gaps; one primary per view).
- D1b Verdict 3 and Pattern 1 (the event line), Pattern 4 (That night, the
  strongest learning case of the eight), Pattern 2 (three faces, then the
  booklet), Pattern 7 (copies by count).
- D1c Patterns 3 (time not lines; one name field) and 5 (a page for the
  finished production).

## Risks

- Undated work (51% of episodes, most of the tail) never reaches Home.
- Dates come mostly from file names (D1a §1.2); a misdated copy lands on
  the wrong night, so That night needs `evidence-gated-catalog-curation`'s
  wrong-match care (Escape's "1921" first episode).
- The date card at 64-112 px is a seventh size unless it is treated, as
  here, as the day's typographic card (art, not a type level).
- It is the least visual direction: faces appear only on Detail and Now
  Playing.

## Screenshots

| Screen | 375 px | 1440 px |
|---|---|---|
| Home | ../../img/d2/a/home-375.png | ../../img/d2/a/home-1440.png |
| Browse | ../../img/d2/a/browse-375.png | ../../img/d2/a/browse-1440.png |
| Series, rich (Suspense) | ../../img/d2/a/series-rich-375.png | ../../img/d2/a/series-rich-1440.png |
| Series, sparse (Stay Tuned For Terror) | ../../img/d2/a/series-sparse-375.png | ../../img/d2/a/series-sparse-1440.png |
| Episode, rich (The Black Curtain) | ../../img/d2/a/episode-rich-375.png | ../../img/d2/a/episode-rich-1440.png |
| Episode, bare (1945 Radio News) | ../../img/d2/a/episode-bare-375.png | ../../img/d2/a/episode-bare-1440.png |
| Now Playing | ../../img/d2/a/now-playing-375.png | ../../img/d2/a/now-playing-1440.png |
| Create: pick a play | ../../img/d2/a/create-pick-375.png | ../../img/d2/a/create-pick-1440.png |
| Create: claim a part | ../../img/d2/a/create-part-375.png | ../../img/d2/a/create-part-1440.png |
| Create: record a line | ../../img/d2/a/create-record-375.png | ../../img/d2/a/create-record-1440.png |
| Shared production | ../../img/d2/a/production-375.png | ../../img/d2/a/production-1440.png |
