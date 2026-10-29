# Direction C: The Sleeve

*D2 prototype, 2026-10-29. Open `index.html?s=home` (screens are `?s=` ids). Data: `../shared/sample.js`, a small sample of the live projection; the production's cast (Pat, Sam, Ada) is D1c's fixture.*

## Metaphor

A record sleeve and its liner-notes booklet. The front is one large cover;
the back tells the story in a fixed order; the booklet holds the credits
behind one control (Criterion's booklet, Apple Music's View Credits,
Discogs' versions table: D1b §2.2). Each screen leads with **one** thing,
and the story under it is made of chapters that are data rules, never
prose: *The run*, the season as a track listing, *On the air*, the date it
aired, *Cast and credits*, *N copies*. The form is editorial; every word is
a real title, a datum, or a label as short as the app's.

## What it surfaces

- **Home is a few features, not rows of six.** Each is a cover and one
  fact line: a night that survives (October 29, 1939 on WRC: Jack Benny,
  then Bergen and McCarthy with Clark Gable, the gaps between merged into
  one row each), a run (Suspense with its strip, "most in 1944"), a voice
  (William Conrad's print, 1,042 episodes, the two shows he leads), and a
  play to make (Caesar Rodney's Ride, 12 parts, about 26 minutes).
- **The run as the series' story**: a large run strip (episodes per year,
  1930 to 1962), first and last dated broadcast, the busiest year; then the
  season as a track listing, date first, with a guest's face only when
  that face is heard on under a quarter of the season (the regulars are
  not repeated down the list).
- **The broadcast as an event**: the broadcast line ("CBS · Thursday,
  December 2, 1943 · Roma Wines"), length on Play, three faces under *On
  the air*, and the date as its own chapter listing the other surviving
  broadcasts of that night, shows first and single recordings folded into
  a count.
- **Browse as a contents page**: "1,374 shows" set large, then genres in
  their hues with show counts (Unsorted 477 named, not hidden), decades,
  and the most downloaded shows with a word-sized strip.
- **Create as a script you can read before you join**: the cover, the
  script's first page, then the parts with reading time, who has which
  part, and Take part on the open ones; one name field.
- **The finished drama as a premiere sleeve**: a poster of the title and
  the cast's chosen names, the parts as the track list, "Recorded October
  23–29, 2026", Listen through, Listen together, and the script's source
  with Project Gutenberg's own rights claim (recordings are never called
  public domain).

## What it hides

Networks lists, season and log number on Detail, sponsor anywhere but the
broadcast line, every copy's identifier and bit rate (*6 copies* is a closed
disclosure), the full credit list (the booklet), every other part's name
field. Single recordings and small series leave the first screen; they are
counts that open a list. No shelves: the person sees fewer things at once.

## Cost per platform

| Platform | Cost | Native idiom |
|---|---|---|
| Web | M | One `<main>` scroll; cover beside chapters from 768 px (sticky cover); `<details>` for the booklet and copies; inline SVG strip |
| iOS / iPadOS | M | `ScrollView` with a large cover header; `DisclosureGroup` booklet; Swift Charts or `Canvas` strip with a VoiceOver summary; iPad and Mac use a two-column `HStack` (cover, chapters) |
| macOS | S after iOS | Shared Core; the two-column layout is the default window |
| tvOS | M | The cover is the hero beside its chapters; each chapter a focus section; the strip drawn only on the focused item |
| Android | M | `LazyColumn` with a cover item; Compose `Canvas` strip with semantics; `ExpandableCard`-style booklet |

**Pipeline (once, every client reads):** a per-series year histogram and
core years (5th to 95th percentile of dated episodes) in `index/series.json`
(D1a §4.2); the `sameDay(id)` verb with a `show` flag so a night lists shows
first (D1b Pattern 4); display titles ("Masquerade Party", not "(OTR)",
D1b Pattern 3); the role-to-group map behind the booklet's three groups
(D1b Pattern 2); copies named by what differs (D1b Pattern 7). Home's
features are data rules (an anniversary evening, a run, the most-heard
voice with a portrait, a short radio play) that the owner signs off on
under `values-based-feed-ranking`.

## D1 findings it answers

- D1a Verdict 1 and §4.1: shows first, single recordings a count.
- D1a §4.2: the run strip, word-sized in lists and large on the series page.
- D1a §4.3: a voice as a Home feature and faces in the season listing.
- D1a §3.2 Stations: runs of gaps merged into one row.
- D1b Verdict 3 and Pattern 1: the broadcast line, length on Play.
- D1b Patterns 2, 4, 6, 7: three faces then the booklet; that night; Now
  Playing's second page; copies as a count, not a list.
- D1c Patterns 3 and 5: one name field and reading time; the premiere page.

## Risks

- **One thing per screen means less to scan.** A person who knows what
  they want waits on Search; a browsing person sees four features where
  shelves showed thirty rows.
- **The cover is a card for 97.5% of series** (271 portraits in 10,642).
  Large type on a genre hue carries most pages; its small caption line
  needs a contrast check on the lighter hues (comedy, western).
- **Features are rankings.** Which night, which run and which voice lead
  Home are rules the owner must approve, shown the same to everyone, with
  the rule as the heading; no named human editor exists yet, so there is
  no editor's pick.
- Plays carry no genre, so their covers are neutral, which makes Create's
  shelf of covers quieter than the catalog's.

## Screenshots

| Screen | 375 px | 1440 px |
|---|---|---|
| Home | [375](../../img/d2/c/home-375.png) | [1440](../../img/d2/c/home-1440.png) |
| Browse | [375](../../img/d2/c/browse-375.png) | [1440](../../img/d2/c/browse-1440.png) |
| Series, rich (Suspense) | [375](../../img/d2/c/series-rich-375.png) | [1440](../../img/d2/c/series-rich-1440.png) |
| Series, sparse (Stay Tuned For Terror) | [375](../../img/d2/c/series-sparse-375.png) | [1440](../../img/d2/c/series-sparse-1440.png) |
| Episode, rich (The Black Curtain) | [375](../../img/d2/c/episode-rich-375.png) | [1440](../../img/d2/c/episode-rich-1440.png) |
| Episode, bare (1945 Radio News) | [375](../../img/d2/c/episode-bare-375.png) | [1440](../../img/d2/c/episode-bare-1440.png) |
| Now Playing | [375](../../img/d2/c/now-playing-375.png) | [1440](../../img/d2/c/now-playing-1440.png) |
| Create: pick a play | [375](../../img/d2/c/create-pick-375.png) | [1440](../../img/d2/c/create-pick-1440.png) |
| Create: claim a part | [375](../../img/d2/c/create-part-375.png) | [1440](../../img/d2/c/create-part-1440.png) |
| Create: record a line | [375](../../img/d2/c/create-record-375.png) | [1440](../../img/d2/c/create-record-1440.png) |
| Shared production | [375](../../img/d2/c/production-375.png) | [1440](../../img/d2/c/production-1440.png) |
