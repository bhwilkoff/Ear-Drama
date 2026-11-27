# B31: Finding a play (design, 2026-11-26)

Design phase of BACKLOG-LOOP B31. Research: `B31-finding-a-play-research.md`. Frames: `b31-frames/`
(made by `b31-proto/shoot.mjs` from `b31-proto/mock.html`; every title, count, character and line on them
comes from the real library through `b31-proto/make_data.py`, and no list or blurb was written for them).
No product code changed.

The owner, 2026-11-26: *"We need to research a FAR BETTER way of searching for and finding a play that you
might like to perform/record. I'd love to see themes and collections for plays and different ways of finding
plays to read or record ... Right now there are also no visuals for each play that help them to distinguish
themselves from one another. All of the pre-recorded radio dramas now have great visuals, even if we don't have
an image. I'd like to search for both images and design a way to designate the different elements of a play in
a similar way from what we are doing from the pre-recorded performances."*

**Learning orientation (the four questions).** Deepens understanding: the label teaches how a play shares its
lines (a two-hander, a star part, an ensemble) before anyone opens it, which is the first thing a cast has to
understand. Invites participation: scenes for two voices and short plays are a way in for a pair or a class
that cannot do a whole evening. Agency: every shelf is a rule stated as its heading or a named editor's pick;
nothing ranks by engagement and nothing is recommended by a model. Clarity: facets are the four questions a
performer asks (how many of us, how long, what kind, when), in that order.

**Look at these frames first:** `labels-1440-light.png` (the 12 plays, three sizes, with their pictures),
`tiles-375-dark.png`, `find-375-light.png`, `search-375-light.png`, `play-375-light.png`, then the
platform frames `ios-390-light.png`, `android-412-dark.png`, `tv-1920-dark.png`, `ipad-1180-light.png`.

---

## 1. Images: why the library carries none, and what it would carry

### 1.1 Cause (measured)

- The published `plays/library/index.json` (eardrama.org, fetched 2026-11-26, 943,047 bytes) is byte for byte the
  size of the local build and carries no `picture`, `titlePage`, `authorArt` or `production` on any of its 1,194
  rows.
- `play_art.attach` is called by `build_play_library.py`, which `tools/refresh_play_library.sh` runs **on a Mac
  whose `catalog/.cache` has no `art_v2/`**. `play_art.load()` then finds no `plays.json.gz`, and `attach`
  returns the rows untouched **without a word** (`if not ctx["plays"]: return rows`).
- The caches do exist: the dated catalog Release's `harvest-cache.tar.xz` (catalog-2026-11-24) holds
  `art_v2/plays.json.gz` (634 book records), `art_v2/files.json.gz`, `liveness.json.gz`, `people_wd/` and
  `loc/records.json.gz`. Only `catalog-publish.yml` restores that archive; the play library refresh never does.
- So: **never run against the caches, not empty and not filtered.** Second cause: the plays harvest ran when the
  library was smaller; 856 of 1,194 rows (72%) have a book record, 338 have none.

### 1.2 What attach gives with the real caches (dry run, no network, no publish)

`b31-proto/measure_play_art.py` over the published index with the Release's caches restored to a private
directory (nothing written to the shared `catalog/.cache`):

| Field | Rows | Share |
|---|---:|---:|
| any `picture` | 586 | 49.1% |
| `titlePage` | 176 | 14.7% |
| `authorArt` | 504 | 42.2% |
| `production` (Federal Theatre Project) | 8 | 0.7% |
| lead = work image | 84 | 7.0% |
| lead = production | 4 | 0.3% |
| lead = title page | 126 | 10.6% |
| lead = author portrait | 372 | 31.2% |

**306 plays would share their lead picture with another play** (Strindberg's portrait leads 25, Ibsen's 14,
Galsworthy's 12). An author's face is what the owner asked us not to show: it makes thirty plays look alike.

### 1.3 The Gutenberg book's own illustrations (a new source)

- Measured over the cached plain texts: **287 of 869 source books (33%) carry at least one `[Illustration`
  marker, 439 library rows (37%) come from them, and 256 rows with no picture at all come from an illustrated
  book.**
- A 10-book sample of those 256 (seed 31; HTML from the PGLAF mirror, since www.gutenberg.org answered 503 with
  Retry-After 21600): **7 of 10 hold a picture of the play itself**: Poor Jack's cover and title page,
  Chushingura's Kuniyoshi woodblock frontispiece, The White Christmas's frontispiece and costume plates, the
  1906 Pride and Prejudice frontispiece, It Pays to Advertise's set plans, The Schoolmistress's 1886 Royal
  Court playbill with its first cast, and the Moses dramatization's plates. The other three are a publisher's
  series mark, a page of music, and plates about school theatres rather than the play.
- Rights: the plate is part of the e-text we already hold as cleared, from an edition the record dates; the 2026-11-21
  rule (used unless the record marks a restriction) admits it, with no matching step, so no identity risk.
- Estimate, from the sample and labeled as one: about 180 more rows with a picture of the play.

### 1.4 The lead rule for a play's window (binding words for WEB-DESIGN 6.4r)

> **A play's window** holds a picture **of the play** (a work image, a production photograph, or a plate from
> the book it came from, in that order) wherever a window is drawn. A **title page** and an **author portrait**
> lead only on the play's own page header, where they are read large; in tiles, rows, rails and the TV, the
> play's label stands in. A plate needs at least 240 px on its short side, else the label. The picture takes
> the window's grade and mount (6.4b); nothing is drawn over it.

Coverage, measured plus the estimate: about 88 work and production images plus about 180 book plates, so about
22% of plays wear a picture in a grid and about 64% on their own page; the label carries the rest, so the label has to
be good, and it is section 2.

---

## 2. The play's label

### 2.1 What it is (binding words for WEB-DESIGN 6.4r, replacing "stage play: the script page plus voice rules")

> **Stage play**: the play's label, a printed page and not a disc (a stage play was never broadcast; the disc is
> what it becomes when it is recorded, and its cast columns become that ear drama's rim of part hues). On the
> page: the **board** is the play's form where the record names one (comedy and farce: `comedy`; tragedy and
> tragicomedy: `drama`; history: `documentary`; fairy and fantasy: `scifi`; religious: `serial`; melodrama:
> `mystery`; libretto: `news`), else the neutral board (`surfaceAlt`, the page's text color), as a show with no
> genre; the **monogram** (`API.monogram`) in Big Shoulders Bold, solid, from the left at 9 in the top half,
> because the name is never drawn twice; **the cast**: a column per speaking part from the left, largest first,
> its height that part's lines over the largest part's (at least 8%), equal widths up to a cap, so a two-hander is
> two slabs and a star part one tall column; past 10 columns (6 at S, 12 at L) one dimmer column stands for the
> rest; **the era ruler** at the foot (M and L): seven fixed cells, Antiquity, Medieval, 1500s, 1600s, 1700s,
> 1800s, 1900-1930, the playwright's cell lit, the baseline alone when undated; at L the rim line
> "SURNAME · LIFE YEARS" from the record (SHAW · 1856-1950; SOPHOCLES · 496-407 BCE). The top right corner stays
> clear for Read. Nothing on it is hashed or invented.

The tile keeps its horizontal cast fingerprint in the strip slot (WEB-DESIGN 4.15), so the window's columns and
the strip never draw the same mark the same way.

### 2.2 How it was decided on the frames

- **First version** (`b31-proto` history): the cast as a thin horizontal segmented strip and a full-title type
  block. Read on the frames: the strip repeated the tile's strip slot 20 px below it and the full title broke
  6.4b's "the name is never drawn twice". The era ruler at the top ran under the Read button.
- **Second version, kept**: columns. Every pair of the twelve is told apart without reading the title: Pariah is
  two equal slabs, Oedipus the King one column over eight short ones, Peter Pan two equal leads and a crowd, Henry
  V one column and forty-seven, Trifles five steps. The three Shaw plays differ in hue and cast (How He Lied: amber,
  three columns; Candida and Major Barbara: neutral, 8 against 18 columns).
- **The neutral board is fine** (the brief said decide on frames): 62% of plays sit on it, and in a grid of them
  (`find-375-light.png`, `find-1440-light.png`) the monogram and the columns still differ tile to tile. A hue by
  era for the unnamed would make hue mean two things on one screen.
- Light and dark were both read; onBoard on every board holds the shipped APCA contrast (the boards and onBoard
  are the existing tokens; no new color).

### 2.3 Form, from the record (dry run, `b31-proto/derive_facets.py`)

Rule: the first form heading in the book's LCSH **Subjects**, else in the **Gutenberg title** ("...: A Comedy",
"The Tragedies of Seneca"). Never from Bookshelves (Gutenberg's "Opera" shelf holds Riders to the Sea and
"Humour" is a reading list). A title that names two forms names none ("Comprising Drama, Comedy, and Farce"). A
play cut from a volume never takes the volume's title (it names the contents: "Plays: Comrades; Facing Death;
Pariah; Easter" made Pariah "religious" in the first pass).

Result: **454 of 1,194 (38.0%) have a form**: comedy 253, tragedy 88, farce 31, libretto 23, fairy and fantasy 21,
history 13, tragicomedy 12, religious 11, melodrama 2; 740 unnamed. Read by eye, 30 random hits: 28 right. Two
classes of error remain and the build batch tests them: a volume's subject heading applied to every play in it
(Gilbert's "Engaged" took "Operas -- Librettos" from its volume), and LCSH's own calls (The Tempest is
"Tragicomedy").

Era: author years from the Gutenberg Authors field, translators and editors skipped, BCE parsed, and LoCC
`PA` (Greek and Latin literature) as Antiquity when undated: **1,126 of 1,194 (94.3%)**.

---

## 3. Finding

### 3.1 Record > Plays (binding words for WEB-DESIGN 4.15 item 3, iOS 4.14, ANDROID 4.9a)

> **Plays**: a search field ("Titles, authors, characters, lines"), then the **facets** as one row (Voices,
> Length, Form, Era, Sort), each a native picker with counts against the others so no choice yields nothing
> (10.5); **Filters** opens the rest (how the lines are shared, subject, country of the original, one act).
> Then the **ways in**, each a rail whose heading is the rule that fills it and its count, with All: editor
> collections first (absent while the file is empty), then **Scenes for two voices**, **Ten minutes or less**,
> **Plays for two voices**, **A star part**, **One Act Plays**, then the grid under the sort's name. A play appears
> once per screen: a rail never repeats a play from a rail above it (081 rule 5).

Facet values and their counts (measured, all 1,194):

| Facet | Values (count) |
|---|---|
| Voices | 1-2 (27), 3-4 (89), 5-6 (110), 7-10 (234), 11+ (734) |
| Length | up to 10 min (69), 10-20 (117), 20-40 (199), 40-90 (284), longer (525) |
| How the lines are shared | ensemble, no part over a quarter (492); mixed (657); a star part, one part half the lines (45) |
| Form | as 2.3, with "Not named" (740) |
| Era of the playwright | Antiquity 65, Medieval 6, 1500s 14, 1600s 141, 1700s 85, 1800s 313, 1900-1930 502, undated 68 |
| Subject (Filters) | the 25 LCSH "-- Drama" topics with five or more plays (Man-woman relationships 39, Ireland 27, Greek mythology 15 ...) |
| Country of the original (Filters) | LoCC on every row (PR 546, PS 236, PT 125, PA 70, PQ 66 ...); 254 translations |

A facet value under five plays is folded into the next (melodrama shows under Not named until it has five).
Gender is never a facet (B30 casts by voice, unknown when unsure).

### 3.2 Collections

- **From data** (computed by the catalog, published with their rule; measured): Plays for two voices 27, Ten
  minutes or less 69, One Act Plays (Gutenberg shelf) 72, Ensemble pieces (up to 10 voices) 65, A star part 45,
  Christmas plays 34, Ireland 27, Nobel Prizes in Literature 84; authors with five or more plays (78 authors).
  Order inside a collection: A to Z, or shortest first for a length rule. No popularity, ever.
- **From an editor**: `catalog/plays/collections.json`, shipped as `{"collections": []}` (empty but ready):
  `{id, title, by, note?, plays[], added, season?}`. `by` is shown as the credit under the heading; `note` only
  in the editor's own words; a collection with fewer than three playable plays is not published; a play id that
  stops resolving fails a test. The owner is the editor. No agent writes an entry.

### 3.3 Search (WEB-DESIGN 4.6, iOS and Android 4.5)

> Plays are searched by **title, author, character and spoken line**. Sections in order: Plays (title and author
> word prefix), Characters (a role's name: the row is the play, its sub line "ROLE · N lines · author"), Lines
> (the words in order before scattered words; the row keeps the matched line, italic, verbatim, as the
> transcript hit does). The client never builds its own index.

On the frame: "candida" finds the play and two characters named Candida (Shaw's, 141 lines; Goldoni's The Fan,
77); "quality of mercy" finds Portia in The Merchant of Venice and Galsworthy's Justice quoting her. The first
pass, all words in any order, ranked Landor and an Oscar Wilde essay first: the order rule is load-bearing.

Data plane cost (measured over 14.6 million words): characters, 12,853 names, 115 KB gzipped as one file; a
word-to-plays index for lines, 107,939 words of three letters or more, 4.5 MB gzipped in all, served in
two-letter shards as `search/said/` is. Line ids are not published (9.6 million postings): the client fetches
the at most six best plays' scripts, which it fetches anyway to open them, and finds the line there.

### 3.4 Scenes for N voices

Printed section headings exist on 747 plays (62.6%). A **scene for N** is a section with N speaking parts (2 to
4) and 1 to 12 minutes: **317 plays hold at least one** (for two voices 224, three 232, four 226). A scene card:
the heading as printed, cut at its first punctuation ("Scene III", never "SCENE III.--_OUTSIDE..."), the minutes,
the play, the two parts' names. It opens the reader at that line and records only that range (Today's scene
already does). Not on a TV.

**Part names (2026-11-26).** A scene's `parts` are the names the print gives, not the speech labels: "DEM" is
Demea when a direction prints "Enter DEMEA" or another role begins with it (`play_facets.full_names`; unique
candidate only, else the label stays). 373 of 1,226 scene cards (101 plays) changed. The cast sheet and the
`roles` list still carry the label (a role's name is the id of its part and of every take, so it is not renamed
for a card); mending the role names themselves belongs to `play_roles`, with a migration for saved productions.

**Recording only a scene's range: the plan (not built).** A production may carry `range: {from, to}`, two line
ids of its script, `to` the last line before the next section (the scene facet has `line` for `from`; add `to`
to `scenes` in the catalog, same build, contract 4.1). Rules to stamp into WEB-/iOS-/macOS-/ANDROID-DESIGN and
PLAYS-DESIGN before code: (1) a range production's cast sheet lists only parts with a speech inside the range, and
its voice count and minutes are the range's; (2) Done means every one of those parts has a chosen take for every
line in the range, never the whole play; (3) Listen Through and export mix only the range, and a range
production's title is the play's with the heading ("Adelphi, Scene II"); (4) a script revision that moves either
bound drops the range and says so. Smallest change per platform: `newProduction(script, {range})` stores the
field and `castParts(script, range)` filters by it; `linesFor` and the Done, Listen Through and export seams read
`p.range` through one `inRange(p, lineID)`; the scene card's Record door passes `{from: scene.line, to: scene.to}`.
Shared proof: `catalog/tests/golden/production_range.json` (a ten-line script, range L0003..L0006: expected cast,
Done before and after the last take, Listen Through line ids, export line ids, a revision-drift case) run by
`js/plays.test.js`, the Apple Core tests and `android` `testDebugUnitTest`. Too large for the same batch as the
names: it touches the production schema, sync (`ProductionShare`), export and three UIs.

### 3.5 A play's page (WEB-DESIGN 4.10, 6.4g)

Head board on the form's board (or neutral) with the window (picture by 1.4, else the label), kicker "STAGE PLAY ·
COMEDY · ONE ACT" (each word only when the record says it), the name, the author with life years, voices and
minutes, the cast strip under both; Record this, Read, Parts; the parts by name with their share; Scenes for two
voices (when any); **Same voices and length** (the rule as the heading: within one voice and 15 minutes); More
by the author.

### 3.6 The four states (universal-feature-states; `states-375-light.png`)

Loading: the spinner in the Plays box and skeleton tiles. Empty: "Nothing matches these filters." with Clear
filters (a search with no hit offers Add a script, 4.6). Error: "This did not load." with Try again. Offline:
"You are offline." Rails with nothing are absent, no header. Words are the shipped ones.

### 3.7 Per platform (same verbs, native idiom)

- **Web**: native selects styled as chips at 375 (horizontal scroll), the sidebar at 1440; rails scroll-snap.
- **iOS/iPadOS**: `.searchable`, pull-down `Menu` buttons for facets, rails as `ScrollView(.horizontal)`; iPad and
  Mac the sidebar and a six-column grid (`ipad-1180-light.png`); Mac facets in the toolbar.
- **Android**: `DockedSearchBar`, `FilterChip` row with dropdown menus, `LazyRow` rails, NavigationBar.
- **tvOS and Google TV**: Browse gains a **Plays** scope beside Shows, Voices and Ear dramas: the data shelves
  as focus shelves at 2.2x the tile grammar (29 pt floor), no facets, no scenes, no record door (the TV records
  nothing); a play opens its page with Read when the reader reaches the TV (B21).

---

## 4. Data contract additions (CATALOG-CONTRACT 4.1, the play library)

Per row, additive, absent when unknown, computed once in the catalog (`catalog/tools/play_facets.py`), never by a
client:

| Field | Shape | Source |
|---|---|---|
| `form` | one of comedy, farce, tragedy, tragicomedy, history, fantasy, religious, melodrama, libretto | 2.3 |
| `formSource` | `subject` or `title` | 2.3 |
| `hue` | the board key the form borrows | 2.1 |
| `era` | one of the seven cells | 2.3 |
| `life` | `{born, died}` years, negative for BCE, of the first playwright not a translator | Gutenberg Authors |
| `oneAct` | true when a subject, shelf or title says one act | |
| `balance` | `ensemble`, `mixed`, `lead` | `cast` |
| `subjects` | the LCSH topics kept for Filters | Gutenberg |
| `locc` | two letters | Gutenberg |
| `scenes` | `[{line, heading, voices, minutes, parts[2..4]}]`, at most 6 | script `sections` |
| `picture`, `titlePage`, `production`, `authorArt` | as 3.3c, plus `kind: "book"` for a plate | `play_art`, new `--phase plates` |

Files beside `index.json`: `collections.json` (data collections with `rule`, `count`, ordered ids, then the editor
file's), `characters.json` (name to play ids), `search/said/<2 letters>.json` (word to play ids).

---

## 5. Batches for build

**C1 Catalog: pictures attach for real.** `refresh_play_library.sh` restores `art_v2`, `people_wd`, `loc` from the
newest dated catalog Release into `catalog/.cache` before the build (as `catalog-publish.yml` does), and
`play_art.attach` **fails the build** when it finds no cache (a silent no-op hid this). Run `harvest_art_v2.py
--phase plays` for the books with no record (869 books, 634 records). Accept: the published index carries `picture` on 49% or more of
rows (measured 49.1%), `check_play_library.py` fails on 0%, a planted empty cache makes the refresh exit 1.

**C2 Catalog: book plates.** `harvest_art_v2.py --phase plates`: for each illustrated book, the HTML edition's
images from the mirror (one session, polite), dropping images under 240 px, music, logos and decorative capitals
(file and alt rules); the first plate inside the play's own section, else the frontispiece or cover; `kind: book`.
Accept: a 30-play hand read of the chosen plates, at least 24 show the play; hosting per question 1.

**C3 Catalog: facets, scenes, collections, search files.** `play_facets.py` from `derive_facets.py` with its rules
and a golden file; `collections.json` (data plus the empty editor file); `characters.json`; the word shards.
Accept: form precision at least 28 of 30 on a fresh random read; a planted volume-title form is refused; a planted
editor id that does not resolve fails; client suites run (`catalog_change_runs_client_suites`).

**C4 Title audit** (research 2.0): not-a-play rows (an editor's line as a title, a magazine issue, an essay such as
Wilde's Intentions) are held by one rule and one test, since titles are the key of every surface here. Poor Jack
lost its author (`authors: []`, Gutenberg says Cabell).

**W1 Web: the label and windows.** `labelSpec` `play` branch per 2.1, `art.label.play` tokens, golden cases in
`catalog/tests/golden/label_spec.json`, the 1.4 lead rule in tiles, rows and the head board; `web_fit_label.py`
cases for plays. Accept: the 12 frames' plays drawn by the product match `labels-1440-*.png` within the fit
tool's tolerance; no window shows an author portrait outside the play page.

**W2 Web: Record > Plays, Search, play page.** 3.1 to 3.6; share URLs `?view=record&voices=&length=&form=&era=&sort=`;
`web_fit_*` at 320 to 430 px and 1440. Accept: no rail repeats a play; Search finds "quality of mercy" at Portia;
the four states seen.

**A1 Apple (iOS, iPadOS, macOS, tvOS)**: the same `labelSpec` goldens in Swift (`Canvas`), 3.1 to 3.7 in native
idiom, tvOS Plays scope. Accept: goldens green on three stacks; frames on the iPhone 12, the Duo, a Mac window and
Ben Bedroom; `test_apple_design_rules.py`.

**D1 Android (phone, Google TV)**: Kotlin goldens (Compose `Canvas`), 3.1 to 3.7, `lintRelease` clean, Roborazzi
frames, the Pixel and the Google TV.

PARITY rows: Play label, Play pictures, Find a play facets, Play collections, Search characters and lines, Scenes
for N voices, TV Plays scope.

---

## 6. Questions only the owner can answer

1. **Where the book plates live.** Pictures we serve come from Commons or archive.org today, and storage is
   archive.org, never Cloudflare (2026-11-19). Gutenberg asks that its site not be used as an image host. Should
   C2 copy each chosen plate (about 180 files, small) into an archive.org item under the project's account and serve
   from there, or hotlink the Gutenberg mirror?
2. **Opera librettos in the record library.** 23 plays are librettos (Gilbert's, O'Keeffe's): spoken without
   their music they are still scripts. Keep them recordable with a "Libretto" form, or hold them?

---

## Files

- `docs/research/design/b31-proto/measure_play_art.py`: the attach dry run (1.2) and the illustration count (1.3).
- `docs/research/design/b31-proto/sample_book_images.py`: the 10-book plate sample.
- `docs/research/design/b31-proto/derive_facets.py`: form, era, balance, scenes, verse share (2.3, 3.1, 3.4).
- `docs/research/design/b31-proto/make_data.py`, `data.js`, `play-label.js`, `mock.html`, `shoot.mjs`,
  `fetch_mock_images.sh`, `img/`: the frames.
- `docs/research/design/b31-frames/*.png`: 18 frames, light and dark, quantized.
