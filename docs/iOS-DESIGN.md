# Ear Drama iOS and iPadOS design (binding)

**Binding.** Quote the rule number before proposing any new view, tab,
sheet, route, or toolbar item on iPhone or iPad. If no rule fits,
propose a new rule first, then the feature
(`binding-design-doc-discipline`). Companion to `PARITY.md`,
`docs/CATALOG-CONTRACT.md`, and the sibling docs `docs/WEB-DESIGN.md`,
`docs/macOS-DESIGN.md`, `docs/tvOS-DESIGN.md`, and
`docs/ANDROID-DESIGN.md`. The platforms share verbs, never idioms; where
a rule here inverts a sibling's, §11 names the inversion so nobody
harmonizes it away.

Seeded 2026-10-22 from `docs/templates/IOS-DESIGN-template.md`, long
after the phone passed five views (Listen, Series, a series page,
Episode, Search, Library, the player, the transcript). It describes what
is built in `apple/iOS/`, `apple/Shared/`, and `apple/Core/`, and its
§12 lists where that code does not yet meet the rules. Mechanics this
doc does not restate live in `ios-production-gotchas`.

## §1 Principles

- **§1.1 Same verb, native idiom.** The phone has the web's verbs
  (`docs/WEB-DESIGN.md` §4) in iOS's own controls: a tab bar,
  `.searchable`, a toolbar `Menu` of pickers, swipe actions, context
  menus, sheets, and `ContentUnavailableView`. Never port the TV's
  focus layout or invent a control where a native one exists
  (`native-platform-first`).
- **§1.2 Touch replaces focus.** There is no focus engine; the tap is
  the verb and nothing moves focus on its own (§11.1).
- **§1.3 One shared data plane.** The phone reads the served projection
  through `CatalogStore` (`apple/Core/Catalog/`) and the network through
  `APIClient.shared`; views never open the database or call
  `URLSession` (`PlayEpisodeAction` in `apple/Shared/Playback.swift` is
  how a view starts an episode).
- **§1.4 The phone is the bedtime and the car.** It is the device in a
  pocket, on a nightstand, and plugged into a dashboard, so the sleep
  timer, the lock screen, downloads, and CarPlay are first-class here.
- **§1.5 Depth is at most two from a tab.** Tab, series, episode. A
  season is a scope, a transcript is a sheet, the player is a sheet. A
  person (§4.13) stands where a series does: Search, person, episode is
  two. From Detail a credited name is a push, as Detail's series link is
  (§12), so Browse, series, episode, person is the one deeper path, and it
  is the listener's to take.
- **§1.6 Only essential words on screen** (AGENTS.md). A caption is a
  refusal, a warning, or a fact a person cannot discover by looking. No
  list or blurb is written by the app (R13).

### §1.7 The shared rules as they bind the phone

The common text lives in `docs/WEB-DESIGN.md` (§4.5, §5, §8) and
`docs/research/05-design-research.md` §9. On iOS:

- **R1** the date leads every episode row (`EpisodeRowLabel`,
  `apple/Shared/Rows.swift`), in tabular figures, oldest first.
- **R5** copies of one broadcast are Versions on Detail, the rank 0
  copy first and the default.
- **R11, as amended by Decision 069** (2026-10-24): art is a served
  portrait, else the typographic card drawn from data; no stock,
  placeholder, or invented art (`apple/Shared/ArtViews.swift`, contract
  §3.3a). A row that mixes series (`EpisodeRowLabel(showSeries:)`, every
  `SeriesRowLabel`) leads with a 40 pt `ArtTile`: the series' star, else
  its first letter in its genre hue, which replaces the old genre edge.
  A series page's own rows carry none. The series page and Detail put a
  `FaceFigure` (76 pt) beside the heading, captioned with the name and,
  when owed, the CC credit; cast lines carry a 32 pt `CreditFace`, the
  slot kept in a group with any portrait; owed credits follow as one
  section. The player sheet shows `NowPlayingArt` (200 pt), and the lock
  screen (`MPMediaItemArtwork`) the same picture: the portrait at 500 px,
  else the card rendered by `ImageRenderer`. Portraits crop at the
  published face (R11a).
  *Amended by R11a: `FaceHero` replaces `FaceFigure` on the series page,
  Detail, and a person's page; the tile is 56 pt; Now Playing is full width.*
- **R11c Now Playing in design D (D3-4)**: the sheet leads with `NowPlayingArt`, the grammar's
  `PictureWindow` at the largest square the sheet offers (full width, at most 44 % tall): the
  show's picture, else its star's, else the title block, face crop and size floor. The title (L1)
  and the `EventLine` (show, date, network) follow, leading-aligned. The mini player is the
  grammar's `GrammarRow` (window, title, event line) beside the play toggle. The lock screen
  (`MPMediaItemArtwork`) gets the same picture. Every verb stays: transport, speed, sleep, AirPlay
  route picker, level, Listen Together, transcript, next story. A credited picture carries its credit.
- **R11a Faces lead** (owner, 2026-10-28: *"Portraits should show wherever they are useful or joyful (overall the visuals are not highlighted yet on the app)."* and *"The visual pass should be for all artwork. We want the app to be as visual as possible."*) (WEB-DESIGN §6.4a is the shared text).
  The only art served with evidence is a person's portrait; other image
  classes wait on the owner's V2 to V5. **The box takes the picture's
  shape, never the picture the box's** (owner, 2026-10-28: *"I think you can find better solutions for different aspect ratios of images, then just blurring and black bars."*; `artwork-presentation-design`). `Artwork.isWide`
  is width over height past `Artwork.wideAspect` (1.15, the web's and
  Android's number); an unknown size is upright, drawn at 4:5. A series
  page, Detail, and a person's page open with `FaceHero` in its own clear
  List section, the navigation title above it. Upright (a square
  included) is the print: `ShapedArt` at its own aspect inside 150 x 168 pt
  compact, 276 x 240 pt regular and on the Mac, beside its label (the name,
  which a person's page leaves to the title; the credit when owed; and the
  series' or person's facts line, which then has no section of its own).
  Wide is the plate: the column's width at its own aspect, at most 320 pt
  tall, at the leading edge, the label under it. `ShapedArt` draws a
  hairline (`brandBorder`), the control radius, and the genre's 3 pt edge,
  and nothing behind the picture: no wash, bars, or filter; while it
  loads the box is `brandSurfaceAlt` at exactly the picture's size. The
  player sheet's `NowPlayingArt` bound is a square, full width and no
  taller than 44 % of the sheet (`containerRelativeFrame`), so Play stays
  on the first screen: a portrait is drawn whole at its own aspect and its
  box shrinks to it, centered; a card fills the square; an owed credit is
  under it (Decision 069). A row's `ArtTile` is 56 pt on iOS (the Mac
  keeps 40) and a cast line's `CreditFace` 32 pt; an evening's aired
  slot leads with its series' tile. **Small crops center on the published
  face** (V4, WEB-DESIGN §6.4 is the shared text): `ArtTile`,
  `CreditFace` show the square `Artwork.cropRect` picks around
  `Artwork.face` (the contract §3.3a formula: the face about half the
  square, at most 4x zoom), drawn by `CroppedArt` as the image scaled and
  offset inside its clipped frame. The lock screen's square
  (`MPMediaItemArtwork`, the 500 px image cut in Core before it is handed
  over) is the largest square moved onto the face, never zoomed, as the
  system shows it large. Without a face an upright or square picture
  takes its largest square at 50 % across, 20 % down; a wide one is not
  cropped: the tile keeps its letter, the cast line its empty slot, the
  lock screen the whole picture. No client detects faces.
  Sizes: each box asks `Artwork.url(pixels:)` for its drawn width at the
  screen's scale (Commons' 120, 330, 500, 960); every box is sized from the
  published aspect, so nothing shifts when an image lands.
- **R11b One grammar** (owner, 2026-10-29: *"the design is still not uniform for all different levels of content (some with images, some without, some with more information, some with less). We need to a design approach that evens out all of the inconsistencies and make the app look like one complete thought."*; `catalog-experience-design` rule 11; D3-1); WEB-DESIGN §6.4b is the shared text, and
  where it amends R11 and R11a it wins. `apple/Shared/Grammar.swift`
  holds one component per object for iOS, iPadOS, macOS and tvOS:
  `PictureWindow` (the square slot on `Color.printGround` with the
  `printEdge` hairline; the series' `picture` cropped by
  `Artwork.cropRect`, graded at decode in Core by `PictureGrade`,
  `CIColorControls` saturation 0 then `CIColorMatrix` in sRGB, the
  identity levels until the projection publishes `art.grade`; else
  `TitleBlock`, the monogram as an outlined Core Text path in onBoard, cut
  solid on the pale genre-less board, where an outline all but vanishes,
  and filled tonally past 200 pt on iOS and tvOS),
  `ShowTile` (window, name, `RunStrip`, facts, on `Color.board(_:)`;
  names in one shelf share the tallest name's height, so every strip
  sits on one line), `GrammarRow` (64 pt, a 48 pt visual: `DateBlock`
  in a series' own list, the series' window where series mix; title,
  sub, length, Play), `HeadBoard` and `EventLine` (a flow layout that
  keeps each " ·" with the fact before it). Home's shelves draw
  `ShowTile`; Browse and every series list draw `GrammarRow`. The 56 pt
  `ArtTile` and the genre's 3 pt edge on rows retire with them.
- **R11c Home and Browse** (owner, 2026-10-29: *"Having more shows is better, so 5."* and *"I like the bulky blocks and colors of The Sleeve and I like the data visualization options of the Almanac."*; D3-2; WEB-DESIGN §6.4c is the shared text). A show is a series of at least five episodes (`ShowLine.isShow`); tiles in shelves and grids are shows only, and the rest are single recordings, counted and reached by a link that lists them in the same grid. Home, top to bottom, each section only with data: Continue listening, Following, the day board ("This day in radio", the date, the count, a years strip stacked by genre in the mark colors on the fixed axis from 1930, the selected year outlined, default the peak; a tap on the strip selects the year; a legend of the genres seen), that night's show tiles (six, then "All N shows that night" in place; each tile's facts are the episode title and length and it opens the episode; the single recordings counted on the right), and Most downloaded (12 show tiles, "All N shows" opens Browse). Most heard voices and New ear dramas are not built (no published list). Browse keeps every filter and sort and replaces the list with a count line ("N shows", and "N single recordings" as a plain link), the decade by genre field (a square per cell sized by `ShowLine.fieldSide`, the count under it, "N with no genre" only when above zero; a cell applies its genre and decade; counts are over the shows passing the other filters), and a grid of `ShowTile` headed by the sort ("A to Z", "Most downloaded first", "Most episodes", "Oldest first"), paged by 60. The field sits beside the grid at regular width and above it on iPhone. Plays are title-block tiles (author and parts).
- **R11e Browse's A to Z jump and the D3-fix rules** (owner, 2026-10-30: *"We are building for each specific platform. It has to look good and use native design and apis on the given platform."*; *"Yes, add a letter jump"*). Sorted A to Z, Browse is one List section per letter (each tile row its own lazy row) so the system's section index (`sectionIndexLabel`, iOS 26 and later) is the jump; below 26 a drag-along letter rail (`LetterRail`) on the trailing edge, with the selection haptic per letter. The decade headers read '20s. an undated, unnumbered episode leads its row with the series' window, never an empty date block; the run strip draws one bar per year from `series.year_counts` (web: `years`), its height the count over the show's busiest year, and falls back to the first-to-last span where the catalog has none; the head board's strip is taller than the tile's; the series page's genre is a link that opens Browse at its root filtered to that genre; an episode with a `script` offers Start an ear drama (not on a TV). The head strip is 40 pt on a phone, 56 from 600 pt.
- **R11f Now Playing's people and Voices** (D3-9; owner, 2026-10-30: *"It has to look good and use native design and apis on the given platform."*; the shared text, WEB-DESIGN §6.4f). Now Playing draws **On the air** (the credited performers as round faces, portrait else monogram, each opening the person) and **That night on the radio** (`CatalogDatabase.sameDay`, contract §3.3b: at most 12 other surviving broadcasts of the same air date, by network with unknown last, then series, then id; each a grammar row of show and network, Play, and a tap to the episode), each hidden when it has nothing. **Voices** is Browse's second scope (Shows, Voices, Ear dramas) and Home's "Most heard voices" rail with All: `CatalogDatabase.voices` behind a column-exists guard, round faces over the name and the episodes, each opening the person's page; a catalog without the table draws neither. On the iPhone and iPad the player sheet scrolls: the picture, title and controls are the first screen exactly as before (`PlayerUITests`, `SeekUITests`, `SleepTimerUITests` identifiers unchanged), the two sections follow; a face or a row closes the sheet and pushes onto the tab beneath.

- **R11d Series and episode pages in direction D** (owner, 2026-10-29:
  *"an item with a picture, without one, rich or sparse, renders in the
  same structure"*; *"a share button that goes to the next line instead of
  being next to the other buttons"*; D3-3; the shared text is WEB-DESIGN
  §6.4d). It retires `FaceHero` (the print, the plate) and the typographic
  head on these two pages. **The series page** is `HeadBoard` (kicker: the
  genre, then the one primary network, `series.network` (V8, 2026-11-20: never the `networks` list, which put "CBS · NBC · AFRS · NBC RED" over Lux Radio Theater and "CBS, NBC" over Gunsmoke; none when the catalog names none); name; facts: the years or "Undated", then the
  episodes; the run strip), one `ActionRow` (Follow, Share), the picture's
  credit when its license asks and the window shows it, then the seasons
  and episodes as before. **The episode page** is the `HeadBoard` of its
  show (a link to the series; the show's name is the line under the
  page's own title), led by `Grammar.leadPicture`, then the episode's
  title, its event line (`Grammar.episodeFacts`), one `ActionRow` (Play,
  Add to queue, Download while there is nothing to show of it, Share), a
  long action ("Start an ear drama") and the download's progress on their
  own rows, **On the air** (`Grammar.onAirOf`: round 72 pt
  `PictureWindow`s over the name and the character, six at most, a face
  with no picture the title block, a name that has a page opens it), "Cast
  and credits" folded in a `DisclosureGroup`, then the recordings and the
  rights line. A section with nothing in it is not drawn. **A button row
  never wraps apart**: an `HStack` inside `ViewThatFits`; when the labels
  do not fit, the secondary buttons fold to 44 pt icons (the title kept
  as the accessibility label) and the primary takes the room. At regular
  width the episode page keeps a column (`ReadableColumn`, 960 pt on an iPad,
  720 on a Mac) and its board, the link to the show, spans it with the
  strip beside the words at a 176 pt window and the plain name, so the
  episode's own title leads; the series and person pages follow R11g. The rules are
  golden-tested in `PagesRulesTests` with the web's cases.
- **R11g The series and person pages on a tablet** (owner's read of the iPad, 2026-11-04: *"series and person pages sit in a narrow column with wide empty margins"*; `catalog-experience-design`: "iPad uses the width for Detail's two columns, not a stretched phone"). At regular width on iPadOS these pages are `WidePage`, not a `List`: the head board across the page, then each season or show as a `WideSection`, its rows two across in reading order, so each column keeps a phone's measure (one column under 700 pt). The board past 760 pt is composed for the width: a 240 pt window, beside it the words (the name at 1.6 times its step), the run strip and the page's buttons, which stand on the board in its one ink (`actionBoard`: the primary an onBoard fill with the board's color as its label). A person's shows stay a shelf under the board. **The head board's strip takes the show's own years** (`RunStrip.ownSpan`, at three years or more, every platform's page about one show on Apple; tvOS's `TVRunStrip` is the same rule): the page compares the show with nothing, and on the fixed axis Gunsmoke was mostly blank. The own-span axis is at least twelve years long, from the first year (`Grammar.ownSpanAxis`; V8, 2026-11-20: X Minus One's three seasons drew three slabs a third of the board wide). Tiles keep the fixed axis, where shows sit side by side. The Mac keeps its column; the phone its list.
- **R11h Marks that say nothing are left off** (owner, 2026-11-04: *"every Jack Benny row reads Cast"*). A person's row names a role only when it says something: "Cast" alone is dropped, "Cast as Mrs. Stevenson" and "Host" stay (`rolesLine`, the same on the web and Android).
- **R12** brand colors are chrome; a genre's hue is content, drawn only
  as the series row's genre mark (`Color.genre(_:)`, Decision 064).
- **R13** shelves come from `catalog.listenShelves()`, which draws the
  catalog's `meta.listenShelves` in its order (contract §5.1; the same
  list and titles on every platform): "This day in radio", "Most
  downloaded" (archive.org's own counts, Decision 067), then each genre by
  its `GenreDisplay` name, ids as published. An older catalog
  without the key falls back to the rules run on the device.
- **R15 and Decision 067: volume leveled on the device.** No per-file
  measurement is read. Each item's audio track carries an
  `MTAudioProcessingTap` (`VolumeLeveler`, `apple/Core/Player/VolumeLeveler.swift`)
  that runs Apple's DynamicsProcessor unit at the numbers every platform
  shares (`LevelNumbers`: threshold -24 dB, ratio 4 as 6 dB headroom,
  attack 3 ms, release 250 ms, makeup 10.8 dB), holding samples inside full
  scale. On by default; "Level volume" (`LevelToggle`) on the player turns
  it off, kept on the device. An item whose track or tap cannot be made
  plays unleveled. Silence is never trimmed.
- **R16** the transcript is labeled "Automatic transcript"
  (`Transcript.label`), the same words on every platform.
- **R17** the phone's tabs reduce to the car's four (§9.1): Continue,
  Stations, Browse, Downloads.
- **R18** speed, the sleep timer, and skip live on the player.
- **R20** the sleep timer's order is "End of this episode", then 15,
  30, and 45 minutes, then 1 hour (`SleepTimer.options`); it fades, and
  once it fires nothing starts until the person presses Play.
- **R21** every control carries a VoiceOver label (§7.3).
- **The rights line** is the projection's words (`meta.rightsLines`,
  falling back to `RightsDisplay.contract`). An unclaimed recording
  reads "No rights claim known. Removed on request." and is never
  called public domain; a basis with no published words shows no line.
- **R9, R10, R14 on Stations** (§4.9): a gap is drawn as a gap,
  the slot on the air is read from the file's UTC instants on the one
  clock (`RadioClock.onAir`, `apple/Core/Radio/Tonight.swift`, golden
  against `js/api.test.js`), and nothing plays after the evening.
- Not built anywhere yet, because the data plane does not carry them:
  R2 runs, R4 gaps, R6 other performances, R7 auditions (R3 arc ends:
  §12; R8 commercial chapters wait on data, contract §3.2a).

## §2 Data plane

- **§2.1 One catalog store.** `CatalogStore` opens the bundled seed,
  refreshes on launch and on every return to the foreground
  (`RootView` in `apple/App/EarDramaApp.swift`), and bumps `loadKey`
  when the database swaps. Every screen's `.task(id:)` keys on it.
- **§2.2 The projection decides; the client draws.** Rights, copy rank,
  shelves, the transcript gate, and loudness numbers arrive in the
  served database. The phone adds no filter of its own.
- **§2.3 A person's listening stays on the device** until sign-in
  (Decision 057, M5): `ListeningHistory` and `DownloadStore`. Signed in,
  history, the queue, and follows sync through the Worker (Decision 063)
  by `AccountStore` (`apple/Core/Account/AccountStore.swift`), every call
  through `APIClient`; downloads never sync.

## §3 Navigation shell

- **§3.1 Five sections, Record among them** (Decision 075, owner
  2026-11-14: *"It is entirely unclear what the app is or how to use it
  easily"*; *"The ability/functionality for recording new Ear Dramas is
  significantly buried"*). **iPhone, iPad and the Duo: five tabs, hard
  set, Home, Browse, Record, Search, Library**, with Search's
  `Tab(role: .search)` so the system places it. The same five on every
  width: the tab bar on iPhone, the sidebar on iPad, the vertical strip on
  the open Duo. **Stations** is a push from Home (`Route.stations`, from
  On the air's "All Stations" and the Listen door) and **Surprise** a push
  from Home's toolbar button (`Route.surprise`, the shuffle symbol), as
  Archive Watch's §2.6: modes are pushes on the phone. Neither is a tab at
  any width, so the Duo's strip shows nothing twice (the 2026-11-14 Duo
  pass, `build/qa/duo-2026-11-14/01-home.png`).
  Each section owns one verb (Archive Watch §12.2): Home what is on now
  and where to start, Browse every show by facet, Record making an ear
  drama (your productions, then the plays), Search find, Library yours.
  **Record this** sits beside Play on any page with a castable script.
  `AppTab` (`apple/Core/Store/AppStore.swift`) holds the five; adding any
  other amends this rule first. There is no Settings tab or gear.
  - *Replaced* (2026-11-14, Decision 075): "**iPhone: five tabs, hard
    set, Home, Browse, Stations, Search, Library** ... At regular width
    (iPad, the open Duo) the sidebar also lists Surprise ... No section is
    named for a content type: plays sit in Browse and Search beside the
    series, and recording is "Start an ear drama" on a play's page.
    `AppTab` ... holds the six".
  - *Replaced*: "Six tabs, hard set: Listen, Series, Radio, Plays,
    Library, Search. Radio follows Series, as on the web."
- **§3.2 One shell for both form factors.** `TabView(selection:)` with
  `.tabViewStyle(.sidebarAdaptable)` (`apple/iOS/ContentView_iOS.swift`):
  a tab bar on iPhone, a sidebar on iPad. No parallel split-view path.
- **§3.3 One destination registry.** Every tab's `NavigationStack`
  applies `routeDestinations()` (`RouteDestinations`,
  `apple/Shared/ListScreens.swift`), which resolves `Route.series` and
  `Route.episode`, and `Route.account` (§4.10). A new pushable screen is
  a case of `Route`, never a per-view `navigationDestination`.
- **§3.4 The store owns navigation.** `AppStore` keeps the selected tab
  and one `NavigationPath` per tab; `push(_:)` appends to the active
  tab. Each tab keeps its stack when the person leaves it (§11.4).
- **§3.5 Everything external lands in the inbox.** `.onOpenURL` and the
  launch doors post to `AppStore.inbox`; `RootView` drains it once, in
  one place.

### §3.6 Regular width on a phone: the open iPhone Duo

Owner, 2026-11-16, holding the first App Store submission for it: *"let's
fix all of the interface elements for the duo. There is no reason to have
the first version of our app not look as good as possible on one of the
most important devices for new apps"*; of the open display: *"The spacing
between the left column and the regular content is not right. In fact,
most of the interface elements don't seem to be well positioned (they are
practically on top of one another)."* The open Duo's inner display is
regular width, 951 × 669 pt in landscape with the system's vertical strip
(status, toolbar, tabs) down the right edge, 669 × 951 in portrait with
horizontal bars. Apple's guidance (HIG "Designing for iPhone Duo"; the
2026 tech talks): one compact layout and one regular layout cover every
pose; "Build layouts with layout margins and horizontal safe area insets";
the strip arrives as a trailing (or leading) safe-area inset, and every
interactive element stays inside it. These rules hold at **regular width
anywhere** (the open Duo, an iPad, a wide window); nothing reads the
device. Audit frames: `build/qa/duo-audit/` (local).

- **§3.6a One page margin, measured from the safe area.** A page's
  content keeps **24 pt (`Spacing.s6`)** from the display's leading edge
  and from the trailing safe area, where the strip stands: `WidePage`'s
  padding, and `pageMargins()` (`PageMargins`, `apple/Shared/PageParts.swift`)
  on every full-page `List` (`PageBody`, Browse, Library, Account,
  Stations, Downloads). A List spans the horizontal safe area and counts
  its content margins from its own edges, so `PageMargins` adds the
  List's measured safe-area insets to the 24 pt; it changes with the
  strip as the strip collapses on a scroll, and a margin change rebuilds
  nothing. *Why:* the system's own grouped margin hugs the safe area,
  which put every card 13 pt from the strip and 20 pt from the other
  edge (`before/03-record.png`). A bar pinned above a List (Browse's
  scope and chips) takes the same margin (`pageBarPadding()`).
- **§3.6b Two edges for what stands on a page: boxes and words.** In a
  page List at regular width a **filled block** (a card, a board, a grid
  of tiles, Today's Scene, the doors) stands on the **box edge**, the
  grouped cards' own edge (`gridRow()`, `RowLine.box`: no horizontal
  inset), so every box on the page lines up with the cards. **Unfilled
  content** (text, a row of buttons, a picture with its words, On the air,
  an error and its Try Again) stands on the **words edge**, the List's
  own row margin, where the section headings and the words inside the
  cards begin (`gridRow(.words)`, the system's inset). A strip that
  scrolls sideways (chips, a rail of tiles) starts on the words edge and
  scrolls out to the box edges (`railPadding()`): on the box edge itself
  the section's rounded corner clipped the first chip. A compact phone
  keeps its 16 pt for both, as before. *Why:* the Yours card stood 16 pt
  left of Today's Scene (DESIGN-LOOP N14), and Home's board sat 4 pt off
  its heading.
- **§3.6c A confirmation, menu or popover hangs on the control that asked.**
  At regular width a `confirmationDialog` draws as a popover pointing at
  the view it is attached to, so it is attached to the button that opens
  it, never to a List or a screen (Block and Delete Account, 1.0.134;
  Downloads' Remove and Remove All, Remove a published line, Delete Unused
  Takes, here; the sleep timer and the series Download menu already were).
  A short panel opened from a toolbar button (the reader's Text) is a
  `.popover` on that button with `.presentationCompactAdaptation(.sheet)`,
  so the phone keeps its sheet. Long lists (Contents, Search, Voices,
  Marks, the voice picker) stay medium/large sheets. *Why:* the owner saw
  Block "show from the middle of the screen without an anchor"; the Text
  sheet stood 650 pt wide and two-thirds empty.
- **§3.6d A control keeps a phone's measure.** A full-width button or bar
  in a regular-width card is at most 375 pt wide, leading (the Account
  page's Sign in with Apple and Google), and sign-in buttons share one
  height (44 pt) and corner (`Radius.control`). *Why:* an 800 pt sign-in
  bar reads as a banner, and Google's bordered capsule stood 58 pt tall
  and round beside Apple's 44 pt rectangle.
- **§3.6e A column beside a pane keeps its own margins.** A fixed column
  beside a detail pane (the cast sheet beside a part, `ProductionScreen`,
  375 pt: a phone's width, the view it is on a phone) gives every row
  16 pt from both of its edges (`CastColumnRows`), where its board and
  part cards stand. *Why:* the plain List's rows began 20 pt in and ran to
  the divider, so the Personal Voice switch and the sign-in buttons
  touched it (`before/19-production.png`): the owner's "left column".
- **§3.6f Seeing it.** The open Duo refuses XCUITest until a person
  confirms UI Automation on it, and XCUITest frames come from the dark
  outer display, so frames are taken with `devicectl device capture
  screenshot --display-unique-id <inner>` after a launch door; below the
  first screen, the DEBUG door `APP_SCROLL_Y=<points>` scrolls the page
  (`ScrollDoor_iOS.swift`). Every change under §3.6 is seen on the open
  Duo and on the iPad at regular width before it is called done.
- **§3.6g Now Playing at regular width is two panes** (§5.3, §5.9,
  Decision 080), and **a fold never stops a take** (§4.15, "Folding
  during a take"). *Replaced* (open item): "Now Playing and its queue side
  by side (IPHONE-DUO §5.1, owner Q2) needs §5.3 (the player is a sheet)
  amended first".

## §4 Surfaces

- **§4.1 Home** (Decision 075; the sections and data rules are the web's
  §4.2, shared; this is the iOS idiom). A `ScrollView` of sections, the
  large title "Ear Drama" (the tab and the Mac sidebar say Home), and one toolbar item, Surprise (a `Label` with the
  shuffle symbol), pushing §4.11. Top to bottom: **On the air** (tonight's
  slot on now, else the first genre station with a playable slot; a
  grammar row, then **Listen Live** `.borderedProminent` in ink and **All
  Stations** `.bordered`, pushing `Route.stations`; absent when nothing is
  on); **Continue** (the ten most recent in progress, only with history);
  **three doors** in one `Grid` row of three equal buttons, an SF Symbol
  over a verb (Listen `dot.radiowaves.left.and.right`, Find a Show
  `square.grid.2x2`, Record a Play `mic`), Listen pushing Stations, the
  other two selecting the Browse and Record tabs; **Start a Show** (a
  segmented `Picker` of "Most downloaded" and each published genre, over a
  horizontal rail of first-episode tiles, each with a Play button);
  **By Length** (Under 15 min, About 30 min, An hour; the `byLength`
  shelves; absent while unpublished); **Record a Play** (Today's Scene,
  below, then Open Parts); **This Day in Radio**; **Most Heard Voices**;
  **Made Here**. Each section has its own loading, error (with Try Again)
  and offline state and is absent when its rule yields nothing.
  - **Today's Scene** (Decision 079, owner 2026-11-15; WEB-DESIGN §4.2 item 7
    is the shared rule; port brief `docs/research/design/R2-design-review.md`
    §6): `PlayScript.todaysScene(rows, date)`, the `todaysPlay` hash over the
    scene pool (two voices and at most 20 min; else 2-3 voices and at most 30;
    else every play), golden `catalog/tests/golden/todays_play.json` `scene`.
    One card on the drama board: the kicker "Today's Scene", the title, an
    event line (author · N voices · About M min) linking to the play page; the
    opening as a page on the print ground (the first four speeches, each its
    role name in `.caption.weight(.semibold)` over its said words, three lines
    at most, a 3 pt rule in the part's hue; `PlayScript.opening(n:)`, else the
    index row's `opening`); then one row that never wraps: **Try a Line**
    (`.borderedProminent` in ink, `mic`: the reader's Record path for the
    answering voice, the second speaker of the opening, else the second part,
    opening the studio on that part's first line with its cue underlined),
    **Hear It** (`.bordered`: the opening read live by the play's one cast in
    device voices, `AVSpeechSynthesizer` through `VoiceCast`, lighting the
    speech being read; it becomes Stop, pauses the player first, stops when
    the view goes, keeps nothing; absent with no voice) and **Read**. Record
    a Play moves up between Start a Show and By Length.
  - **Made Here, leading** (Decision 079; WEB-DESIGN §4.2 item 7a): while
    there are one to five finished ear dramas, Made Here is drawn directly
    under the three doors instead of last; at six or more it returns to the
    end.
  - *Replaced* (2026-11-15, Decision 079): "**Record a Play** (Today's play
    board, `PlayScript.todaysPlay`, with Record This and Parts, ...) drawn
    after By Length".
  - *Replaced* (2026-11-14): "a `List`: Continue listening ..., then
    Following ..., then the catalog's published shelves in order (R13)".
  - *Pending port* (2026-11-15 design review, `docs/research/design/R2-design-review.md`
    §6; WEB-DESIGN §4.2 items 1, 2 and 7, §4.15): the navigation title on Home
    is **Ear Drama** (built 2026-11-15; the Mac sidebar keeps "Home"); On the air's kicker reads "On the air · {source}" after
    an ink dot (Today's Scene and the move are built, above, Decision 079), and
    the rest of this note: `todaysScene` (the
    `todaysPlay` hash over two voices and at most 20 min, else 2-3 voices and
    at most 30), the title block on the drama board, the first four speeches
    as a page (role name over said words, three lines at most, a rule in the
    part's hue), then **Try a Line** (borderedProminent, `mic`: the studio on
    the answering voice's first line), **Hear It** (the opening read live by
    the cast's device voices, never kept) and **Read**. Record's second block
    is the same card. Play tiles show the index row's `opening` as a page in
    the window when it is present. Same rules on iPad and Mac.
- **§4.1r Home reads as one thing** (Decision 081, owner 2026-11-19: *"the home screen ... still reads like a long list of items that feel unrelated ... The goal is to have the home view feel more cohesive and inviting from the moment that you open the app."*; rulings: "Home: all of R3a §4.1", "label art C on every platform"). Binding over §4.1 wherever they differ; the shared
  rules are WEB-DESIGN §4.2r 1-8 (one lead object, the dial of genre stations under it, two quiet
  doors, one art system and one window size in every rail, a show at most once per Home, two inks
  per screen, rhythm L S M L M S, framing from data only). The phone's idiom: the hero is the On the
  air board at full width with its window at tier L and **Listen live** as the ink button; the dial
  is a horizontally scrolling row of S-tier labels that tunes in on a tap (`selection` haptic);
  the doors are two borderless buttons with SF Symbols in one row. At regular width (the open
  Duo, an iPad, §3.6) the hero keeps one column's width beside the dial and Continue, never
  stretched past its tier. Built in Round 3 V6.
- **§4.2 Browse** (was Series) is a `List` of radio series (the plays
  moved to Record, §4.14, Decision 075: the Kind chip goes, and so does
  every sentence below about plays in Browse), under a horizontally scrolling row of capsule chips,
  as Archive Watch's iOS-DESIGN §4.2a: Kind, Genre, Decade, Network,
  each a native `Menu` naming its current value, and "Has a script", a
  toggle, then "Sort: Popular", a `Menu` of the orders that is never
  filled and never cleared (an order, not a filter, as Archive Watch's
  "Sort: Popular"). Sort is Popular (the default), A to Z, Most episodes, and Oldest first. Popular is the published `downloads` (contract §3.3): counted series first, most downloaded first, then every row without a count by `sortName`. A play has no count, so under Popular it sorts after every counted series; a catalog published before the field has no counts, so Popular is A to Z. Plays
  follow the series under every order. A chip that narrows the list is
  filled with the brand's blue (Decision 064), and Clear leads the row
  once anything is set. The chips are a bar under the navigation bar
  (`safeAreaBar` on 26, an inset whose material stops at the safe area
  before), over ONE `List` for every state, so the large "Browse" title
  shows as on Home and Library (the title was blank on an iPhone 12,
  2026-10-24, under an inset whose material ran to the top edge over a
  swapped list; the fix awaits that device). A play
  carries no genre, decade, or network, so setting one narrows to
  series; "Has a script" keeps the rows whose record carries a usable
  script: the plays, and the series with an episode whose `script` is
  set (contract §3.1). A play row is its title, then its author and
  part count, and pushes the play's page (`PlayRoute.script`). An empty
  result offers Clear Filters.
- **§4.3g Item pages wear Home's hero** (Decision 081, Round 3 V7; owner, 2026-11-19: *"We need to continue making the app more visually appealing, both from the home screen perspective ... and the individual item perspective."* Shared rules: WEB-DESIGN §6.4g 1-7, binding over
  R11d's head-board sizes on these pages; skills `artwork-presentation-design`, `uniform-imagery-design`). The series, episode,
  person, play and finished ear drama pages open on `ItemHeadBoard`: the window at tier L across the board's top on a phone and a
  320 pt column beside the words from 560 pt (the open Duo and an iPad), the words in Home's order, then the strip. A picture
  keeps its own shape (`ItemLead.window`): a wide one is a plate over the words, an upright or square one stands where the
  label would, never cropped, graded as everywhere, its credit under the board; a series' `lead` is a wide `hero`, else its
  picture, else the label; a person's is the portrait, else the groove-ring label in a round window; a play's is `titlePage`,
  else `authorArt`, else its opening drawn as a page (`PlayOpeningWindow`); a finished ear drama keeps its part-color disc. An
  episode's head is its own dated label with the title as the heading, the show a kicker link, and its year at full ink on the
  show's strip (`markYear`); the show's picture is a grammar row under the actions, opening the series. The copies are one closed
  **Recordings** disclosure (the default copy chosen inside). `series.gallery` draws as one row of whole, ungraded pictures at
  160 pt only from two evidenced pictures (`ItemLead.gallery`), each captioned with its credit or its source's site, linked.
  The board is one `Layout`, measured from its proposal, so it is the same height wherever it is drawn. Built in Round 3 V7.
- **§4.3 A series page** carries Follow / Following as the toolbar's
  primary action (the web's verb and words; a plus, then a checkmark once
  followed), with the selection haptic on change. It writes
  `FollowedSeries`, the store the account sync carries; an unfollow is a
  marker. It shows the series' one meta line (the years, the episode count, and
  "With" the show's star from `series.star`: the entry point a stranger reads first),
  then **About** when the catalog publishes `series.about_text` (owner, 2026-11-09:
  "Most people will have no idea what the shows are about"): the text in its
  paragraphs, four lines until More opens it in place, then the source line ("From
  Wikipedia"), which opens `about_url` in Safari over the app (`SFSafariViewController`;
  the Mac: the default browser). The source line is required (CC BY-SA 4.0) and the
  text is never drawn without it. No text, no About: nothing is written in its place.
  Then its episodes oldest first in sections by broadcast season, "Undated" last.
  The toolbar's Download menu (iPhone, iPad, Mac; never the TV) offers
  Download All Episodes, then one Download item per season when there
  is more than one, then Remove Downloads once any of the series is on
  the device. A download asks first, naming the count and, from each
  copy's bitrate and length, about how much space it takes ("Download
  52 episodes?", "About 640 MB."); an item whose episodes are all
  downloaded or downloading is disabled. Removing a series' downloads
  asks first (R17, the car and bedtime: a whole run before the trip).
- **§4.4 Episode detail** is a `List`: the series (the head board with its
  picture and name, a link whose name ends in a chevron so it reads as one; owner
  2026-11-09: episodes felt "totally disconnected from any recurring show"), the title,
  one facts line (date, network, sponsor, length), Play or Pause, the
  download control, "Start an ear drama" when the episode's `script`
  names a bundled script (Decision 068), "Read the script" with the source named
  under it when the catalog links one (`episodes.script_url`; Safari over the app; it
  opens through `ScriptAccess.reading`, the one seam the coming reader that follows the
  voices will take over), "Automatic transcript" when the
  gate passed, the
  credits grouped by role (each name a push to its person, §4.13), Versions when there is more than one copy
  (each named by `recordings.label`, else by what tells it apart, bit rate and length,
  never "Recording 2"),
  and the rights line, except unclaimed, which is every show's default and is not
  drawn (owner, 2026-11-09). A part with no data is absent, never a
  placeholder. Play starts the audio in place; it never opens the
  player (§11.1). The toolbar carries Share: the system share sheet
  (`ShareLink`) with the episode's https twin,
  `https://eardrama.org/episode/{id}` (`SiteLinks.episode`,
  `apple/Core/Store/SiteLinks.swift`; DEEP_LINKS.md), so a person
  without the app lands on the web page. A link is shared, never the
  file (§4.8).
- **§4.5 Search** is `.searchable` with the prompt "Titles, series,
  people", debounced, series first, then People (§4.13, word-prefix on
  the name, most episodes first, eight), then plays (title and author,
  word-prefix), then "Aired {date}" when the query names an air date
  (`DateQuery`, contract §3.4), then episodes, then **Automatic transcript**
  (`Transcript.label`): episodes whose shown transcript says every query
  word of three letters or more, less those above, each row
  `TranscriptHitLabel`, the episode row plus the line where the words are
  said, italic, verbatim (`Transcript.snippet`), read from the transcript's
  own URL; the row stands alone when the text does not load.
- **§4.13 A person** (`PersonScreen`, `Route.person`; `withPerson`,
  contract §5) is a List: the portrait when one is served
  (`FaceFigure`, Decision 069) beside one caption of facts, the years
  from the people row and the episode count, then a section per series
  whose rows are `EpisodeRowLabel` with the roles as its note ("Cast as
  Mrs. Stevenson, Writer"). Order is a toolbar Menu with a Picker, Oldest
  first or Newest first, shown only with more than one episode; undated
  last either way. Each credit on Detail (§4.4) is a `NavigationLink` to
  its person. No bio is written (R13). The Mac uses the same screen in
  its detail column.
- **§4.6 Library** (direction B, owner 2026-11-23: *"Most people we exclusively use this app for listening, so let's do option B to make it easier for them to use the app that way."*; replaces D3-5's flat list and its rule that every section keeps its header and caption) is a `List` headed by a `Picker(.segmented)`, **Listening | Making**, remembered per device (`@AppStorage("ed.library.side")`, default Listening), then one foot under either side. **Listening**: **Up next** is the started episodes (the history store's in-progress ids, with their progress) then the queue in the person's order, each episode once, shown five rows deep and then "All N", which pushes `UpNextScreen` (`LibraryModel.upNext`; display only, the history and queue stores are unchanged; the queued rows keep `onMove` and swipe to remove, a started row swipes to Remove from History); **Shows you follow** is `FollowingShelf`'s show tiles (Following is not merged into Up next; Unfollow on a long press); **History** and **Downloads** are one line each with a count (Downloads adds the storage held), pushing `HistoryScreen` and the Downloads place (§4.8), never rows inline. **Making**: **Your Parts** (one line, only when this device holds a class seat), **Productions** grouped by play (`LibraryPlayGroup`: one row per play with its production count and the newest one's progress line, never nine identical rows; a play with one production opens it, a play with several pushes `PlayProductionsScreen`), and **Classes** one line per class (signed in). Make a Class and Join a Class are Record's (`ClassDoors`, signed in), not Library's. **An empty part is absent**: no header and no caption (`SectionCaption` is not drawn in Library). A side with nothing at all is one sentence and one button ("Nothing played yet" with Browse; "Nothing recorded yet" with Record a Play). **The foot**, headed "Account and preferences", in this order: **Account** (§4.10), **Voices** (one row stating its state, "Kokoro · 1.0×", whose tap discloses the full Voices controls in place under it, `VoicesSection`; there is no Settings page, owner 2026-11-22; `AppStore.openLibraryVoices` still lands here with Voices disclosed), **Export my data** (`ExportSection`), **About Ear Drama** (pushes `AboutScreen`: Credits, Privacy, Take-down requests, §4.10a). Listen together is a player verb on Apple (SharePlay) and has no foot row. Marks ("In 3 scripts") has no place to open on Apple yet and is not drawn. The four states: loading is the skeleton rows; an unreadable catalog is `CatalogUnavailableView` heading the list; offline is the app-wide "You are offline." line (what is on the device keeps listing). Not yet seen on every device (SCRATCHPAD lists the frames).
- **§4.7 The transcript** is a sheet (`TranscriptSheet_iOS`,
  `apple/Shared/TranscriptViews.swift`) from Detail or the player, with
  Done. Plain, selectable text at the body size in a 680 pt measure,
  one sentence a line, fetched from archive.org when opened.
- **§4.8 Downloads** (`apple/Shared/Downloads.swift`) ride a background
  `URLSession` that the system relaunches the app to finish
  (`.backgroundTask(.urlSession)`), at most four transfers to a host at
  once, following archive.org's redirect to its storage node. A
  downloaded file is played, never exported: no Share or Files action.
  The Downloads place (`DownloadsScreen`) groups downloads by series,
  by name, each in the order it was asked for; a row swipes or
  long-presses to Remove Download (Cancel Download while it runs), a
  series' Remove asks first, and the foot of the list carries the
  storage held on this device and Remove All Downloads, which asks
  first. Empty, it says "No downloads". Playback prefers the finished
  file (`AudioPlayer.localFile`); a queued, running, failed, or partial
  download never plays, and the lock screen's picture is the one Now
  Playing draws, so with no network it is the typographic card.

- **D3-8 Stations, Surprise, People, a person** (D3-8, 2026-10-30) Stations, Surprise, Search's people and a person's page follow WEB-DESIGN §6.4f in this platform's idiom: a `GrammarRow` per station and slot (`StationRow`, `SlotRow`; "Now" in an ink pill), head boards for Surprise's picks in a ScrollView, `PersonRowLabel` as a round-window row, and `PersonScreen` as a head board, a rail of `ShowTile`s, then date-block rows with the roles as the sub line.
- **§4.9a A station row is one action** (owner, 2026-11-04: *"eight heavy black Listen live buttons"*). The whole row tunes in, and its mark is a hollow 36 pt ring in ink: eight stations are equal choices, so none is filled. Ink fills only the one on the air, with "Listening live" beside it at regular width; a tap on that row stops it. Spoken as "Listen live to Drama".
- **§4.9 Stations** (was Radio, Decision 068) opens with the stations row,
  the web's §4.9 as the List's first section (`StationsSection`): Tonight in
  19xx first, then each genre station from `stations.json`
  (`APIClient.stations()`, `StationClock.onNow`), one row each with the
  station's name, what is on now (series, then title), and a trailing
  "Listen live" (bordered prominent; "Listening live" bordered while on,
  which pauses). Tonight's row carries "Starts at" / "Ended at" outside the
  evening, so the evening's header no longer does. A genre station tunes in
  through the same `LiveRadio` (`tuneIn(station:)`) with the slots of the
  next twelve hours, resolved in the open catalog on tap. Then Tonight in
  19xx (`RadioScreen`, `apple/Shared/RadioScreen.swift`), the web's §4.9 in a `List`: the
  evening `tonight.json` publishes for the device's own calendar date
  (`RadioClock.localDate`, never the UTC date), fetched through
  `APIClient.tonight()` from the catalog's Release (contract §2, §8).
  A header of "Tonight in 1942", the evening's date, and the network
  and station; when the date offers other published years (Decision 067),
  a menu Picker "Year" under it loads that year's whole evening on
  tonight's clock (picking stops listening live); then one row a slot.
  An evening shows whenever any of its programs survives. Each row shows one time, the
  listener's own (owner, 2026-10-31: "7:00 PM · 9:00 PM ET" read as two
  shows; the paper's Eastern time is not drawn). The slot on the air says "Now" and takes the
  surface-alt row background, repainted every 15 seconds from the
  file's instants. A surviving slot is a link to its episode with a
  borderless Play that plays it from its start, with no chevron and its
  length on the event line, so the title keeps the row's width at 375 pt;
  a gap is one quiet line with no picture frame: the time, then
  `known_series` where the file sets it, else "Not surviving" (or "Not
  in the catalog" for a withheld slot or one the open catalog lacks). Two or more consecutive gaps
  fold into one quiet line, "7:15\u20139:00 PM \u00b7 5 programs not surviving" (`RadioClock.entries`), that
  opens to the individual lines; a playable slot is always its own row (web, Android and tvOS the same).
  The newspaper's printed text is never drawn (Decision
  067; the file no longer carries it). Before the
  evening Tonight's row says "Starts at", after it "Ended at"; during it,
  "Listen live" (`LiveRadio`, `apple/Core/Radio/LiveListening.swift`)
  joins the slot on the air at the clock's offset, and each later
  surviving slot starts at its own time. A pause, another episode, the
  sleep timer, or the last slot's end stops it, and a live slot queues
  nothing behind it, so nothing autoplays after the evening (R14).
  While live the button reads "Listening live"; pressing it pauses.
  No file, or no evening for today, is the empty state "No evening is
  published for today"; an unreachable file is "Tonight could not
  load" with Try Again. The listing's credit is one caption link,
  "Schedule: {paper}, via {source}".

- **§4.11 Surprise** (`SurpriseScreen`, `apple/Shared/SurpriseScreen.swift`;
  Archive Watch PARITY §5) is a `List` of three picks drawn from the
  data when it opens, and Shuffle in the toolbar to draw again: **an
  episode** (a served, recommendable episode with a recording, at
  random, `CatalogDatabase.randomEpisode`), its series, title, and date,
  with Play; **an evening** (one of `tonight.json`'s evenings), its date
  and network, with Play, which plays its first surviving slot from the
  start, never live and never a queue; **a play** (one castable script),
  its title and author, with "Record This". Each plays or starts
  in one tap. The draw is the platform's own random: nothing needs to
  match another device. No copy is written; a pick with no data is
  absent.
- **§4.10a The site pages are About Ear Drama**, the foot's last row (§4.6), a pushed list: "Credits", "Privacy", "Take-down requests", each a `Link` to
  the website's page (`SiteLinks`), opened in the system browser. An
  empty Library keeps them (§7.4). Names only; the pages carry the words.
- **§4.10 The account lives at the foot of Library**, never a tab, a
  gear, or a sheet at launch (§3.1; Decision 057: optional, never at
  first launch). Library's last section is one row, "Account", whose
  value is the state: "Not signed in", "Synced {time}", "Sync failed",
  or, while the build carries placeholder ids (`Accounts.xcconfig`),
  "Not available" with the row disabled and no error. An empty Library
  keeps the row under its empty state (§7.4). The row pushes
  `Route.account` (`AccountScreen`, `apple/Shared/AccountScreen.swift`):
  signed out, the system `SignInWithAppleButton` first and "Sign in with
  Google" under it (App Review 4.8: Apple wherever Google is); signed
  in, the provider, Last sync, the last error in the error color when
  there is one, Sync Now, then Sign Out and Delete Account. Delete
  Account asks first in a confirmation dialog that says what goes
  (5.1.1(v)); an Apple account then asks Apple once more for a fresh
  authorization code, sent with the deletion so the Worker revokes the
  Apple token. Signing in keeps the device's history: it is sent to the
  account once (`/v1/sync/merge`). Signing out and deleting keep the
  device's listening and forget the account: its tokens leave the
  Keychain and the sync cursor, last sync, and last error leave the
  device. Sync runs on sign-in, on Sync Now, and when the app comes to
  the front or leaves it.
- **§4.14 Record** (Decision 075; the web's §4.15 is the shared rule). A
  tab whose root is a `List`: **Yours** (this device's productions and the
  shared ones not yet opened, each row "N of M lines recorded",
  "Finished" or "Shared"; a production with no take is never a row and is
  deleted when the studio closes without one and whenever the store loads,
  PLAYS-DESIGN §2.3 rule 3a; absent when empty), **Today's Scene** (§4.1's
  card; *replaced* 2026-11-15: "Today's Play (the board with Record This
  and Parts)"), **Plays** (the castable library under a
  chip bar like Browse's: Voices 1-2 / 3-5 / 6-10 / 11+, Length Under 30
  min / 30-60 min / Over an hour from `PlayScript.minutes` at 150 words a
  minute, Kind Radio play / Stage play, and "Sort: Fewest voices", a
  `Menu` of Fewest voices, Shortest, A to Z), each play a tile whose window
  draws its cast (one bar per speaking part, largest first, up to seven,
  in the board's one color, "+N" for the rest; the Today's play board wears the same window) with "N voices · About M min";
  then **Made Here**. The author line is each author's `display` name.
  Pushes `PlayRoute.script` and the cast sheet as before.

- **§4.15a Read along** (PLAYS-DESIGN §2.11 binding, rewritten 2026-11-23; web sibling WEB-DESIGN §4.16a).
  **Doors**: a production's **Read Along** (`ReadAlongButton`, `StudioTarget.along`) and a finished drama's
  **Read Along** (`StudioTarget.drama`) open the reader and start reading at once from the reader's place; the
  reader's **Hear the Cast** makes the same `AlongModel(table:)` over the play's cast. **One model**:
  `AlongModel` (`apple/Shared/AlongModel.swift`) with three kinds (production, drama, table) over
  `LiveListenThrough` or `FinishedListen`; `ReadAlong` (Core) holds the pure parts: the line by plan, the
  follow, `spoken`/`word` (an `AVSpeechSynthesizer` range onto `lineText`), `textWords`, `kokoroWords`, the speed
  steps. **The word**: `SystemListenSpeaker` passes `willSpeakRangeOfSpeechString`; `KokoroLive` schedules each
  piece at a known sample of its `AVAudioPlayerNode` and reads the node's `playerTime` every 40 ms against the
  duration model's word starts (`KokoroReader.renderPieces(onTiming:)`); the page draws it with
  `ReaderLayout.drawWord` (a hue fill and a 2 pt rule), Scroll with an `AttributedString` run. **Turning**:
  `alongHeard` turns to a line, `alongWordHeard` turns when the word reaches a page not in the spread; a drag,
  tap or key stops it and **Back to the Line** returns. **Transport** (`AlongTransport`, the bottom bar): the
  speaker in the part's hue, Previous Line, Play or Pause, Next Line, the Speed menu ("1×", a Picker of the seven
  steps), Stop; icons only at compact width (each with its accessibility label), Play / Pause with its word and
  the page count at regular width (the open Duo, iPad). Speed is `ed.along.speed`; takes play at
  `AVAudioPlayer.rate`, a drama at `AVQueuePlayer.defaultRate` with `.timeDomain` items. Reduce Motion cuts the
  slide (`move(toSpread:)`). Seen on the open iPhone Duo 2026-11-23 (muted, Debug): the word moving in the
  hue on both pages of the spread, a page turning by itself inside a long speech, Kokoro and system voices. **Not built**: VoiceOver landing on the line heard when it moves into the page (rule 5's second half);
  Scroll marks the word in speeches only (a direction read aloud keeps its line tint).
- **§4.15 The script reader** (Decision 076 S1; PLAYS-DESIGN §2.7 is binding
  on the verbs, WEB-DESIGN §4.16 is the sibling; port spec
  `docs/research/design/R2-reader-port-brief.md`). **Read** sits beside
  Record This on a play's page, on Today's Scene, and as a book button on
  each Record tile; it needs no account. The reader is a
  `fullScreenCover(item:)` (never `isPresented`, ios-production-gotchas)
  over the tab, so the tab bar steps aside: a toolbar with Close, the
  title over the act and scene (`.subtitle`), and Contents, Search and
  Text (`Label`s, so the Duo's vertical strip can carry them); a bottom
  bar with **I'm Playing** (a `Picker` in a `Menu`), Next Line and Hide
  My Lines (a `Toggle` styled as a button), and the page count.
  - **Pages by default**: the script laid out into pages by TextKit 2 at
    the current size class and Dynamic Type, shown in a horizontal paging
    `ScrollView` (`.scrollTargetBehavior(.paging)`), a slide, never a
    curl. Two facing pages when the reader has a regular-width area of at
    least 860 pt, measured: the open Duo is 867 to 951 pt beside the strip, an 11-inch iPad in portrait 834 (iPad landscape, the open Duo, a wide window); one
    otherwise. Turns: swipe; a tap on the outer fifth of either side;
    hardware keys ← → ↑ ↓, Page Up/Down, Space and Shift-Space (pedals),
    with the reader holding key focus (`.focusable()`, `.onKeyPress`) so an
    arrow turns the page instead of moving focus. **Scroll** (a setting):
    one `ScrollView` with a `LazyVStack` of lines, `ScrollPosition` by line id.
  - **Position** is a line id per script in `UserDefaults` with the part,
    restored on open; a Dynamic Type, text size, spacing, rotation or
    window change re-paginates and scrolls to the page holding that line.
  - **Text** (a sheet, `.presentationDetents([.medium])`, on a phone; a
    popover on its toolbar button at regular width, §3.6c): size over
    seven steps on top of Dynamic Type, line spacing, Pages / Scroll.
    **Contents** and **Search** are sheets (a `List` of acts with scenes;
    `.searchable` over `PlayScript.search`).
  - **I'm Playing**: the part's lines carry a leading rule and tint in its
    hue; Hide My Lines draws its words as capsules in the hue (the text
    still laid out, so pages stay put); a tap peeks one.
  - **iPad and Duo**: the same reader; at regular width two facing pages.
    On the **open iPhone Duo** the reader is the primary pane of the
    studio's `ArrangementView` (S4, iOS 27.1, gated); in S1 it is the
    reader alone, full width, two facing pages (the inner display is
    regular width). Closed Duo: one page. Nothing branches on the device,
    only on width (`onGeometryChange`).
  - The line is addressable by id (an `id` per line view, `ScrollViewReader`)
    and each printed run keeps its offset into `lineText`, for marks (S5),
    the read-along's `follow(line)`, and the studio dock (S3).
  - **The Ear Drama page** (PLAYS-DESIGN §2.7 rule 10, binding; frames in
    `docs/research/design/R2-play-typography.md`). Port `ReaderCore.layoutOf`,
    `isVerse` and `cueTail` to `PlayScript` in Core with the web's fixtures as
    golden cases (the run-in speaker, emphasis, the sound lane, brackets,
    verse). In TextKit 2: the name is `.headline` in the part's hue on its own
    paragraph with `NSParagraphStyle` keep-with-next; the words `.body`; at
    compact width the name stands over the words, and when a page is 30 em or
    wider (iPad, the open Duo) it moves into a right-aligned 8.5 em gutter
    (`headIndent` for the words, a tab-stop column for the name). Verse is a
    paragraph per printed line with `headIndent` 1.5 em for turnovers; a
    direction inside a speech italic `.secondary` with the parentheses added
    as attributes (never in the stored text); a stage direction an indented
    italic `.secondary` paragraph with a part named in capitals in its hue;
    a cue a row with `speaker.wave.2` and the cue in `.caption` capitals on
    a `.quaternary` fill. The front page (title `.largeTitle`, authors,
    Parts in their hues), an act opening a page, a scene `.title2`; a page
    that opens inside a speech heads with "NAME (cont'd)" in `.caption`. I'm
    Playing tints the part's speeches with a leading rule and underlines the
    cue (`.underlineStyle` in the hue). VoiceOver reads a speech as the name,
    then the words (one accessibility element per speech).
  - **The studio** (Decision 076 S3; PLAYS-DESIGN §2.9 binding; web sibling
    WEB-DESIGN §4.16 item 14; port spec `docs/research/design/R2-studio-port-brief.md`).
    `RecordingScreen`'s one-line stage is replaced by the reader with the studio
    attached: `ScriptReaderView(script:, studio: StudioTarget(production:, part:))`,
    opened by the cast sheet's Take Part / Record / Open Part and by **Record** in
    the reader's bottom bar once a part is chosen. The `RecordingSession` engine,
    take model and three-mode goldens are unchanged; Core gains `Production.deleteTake`
    (refused for the chosen take) and a part-scoped `discardUnused`.
    - **On the page**: each of my lines carries its take state after the name
      (`circle`, `circle.fill` + count in the hue, `exclamationmark.triangle.fill`),
      a `Button` that makes the line current and opens its take list; the current
      line outlined in `.primary`, dashed `record` red while its cue plays, solid
      while the microphone is open. Every other part's line a device voice reads
      carries, after the name, a dashed ring in the part's hue with `waveform` and
      the voice's short name ("Zoe"), a `Button` that opens that part's voice picker;
      none on a line with a usable human take (PLAYS-DESIGN §2.9 rule 3a, 2026-11-15).
    - **Listen From Here and Again** (2026-11-15, PLAYS-DESIGN §2.9 rules 5, 6):
      the transport ends with `play.fill` "Listen From Here" (`stop.fill` "Stop"
      while it plays); in Run Through with no run on, a line holding a take shows
      **Again** in the status line, and that single take's round control reads
      Cancel / Stop.
    - **Compact width** (iPhone, the closed Duo, a narrow iPad window): the
      dock is a `.safeAreaInset(edge: .bottom)` under the pages: the mode
      `Picker(.segmented)`, the status line (line place and takes; speaker and
      "Device voice" during a cue; "Recording 0:03" and the level meter), and the
      transport (Previous, the round record control at thumb height, Next, Hide
      My Lines). Takes, Cast, Listen Through From Here, Delete Unused Takes and
      Done With This Part are one sheet (`.presentationDetents([.medium, .large])`)
      from a Studio button (a `Label`) and from the status line.
    - **Regular width of 860 pt or more** (iPad landscape, the open Duo, a wide
      window): the same studio as a 340-380 pt trailing pane in an `HStack`
      with the reader (`onGeometryChange` on width, never the idiom); the
      reader lays out again in what is left. On the open Duo with iOS 27.1
      this becomes `ArrangementView { reader } secondary: { studio }`
      (`.split.axes(.horizontal)`, S4, behind `if #available(iOS 27.1, *)`); the
      toolbar items stay `Label`s so they move into the Duo's vertical strip.
    - **Folding during a take** (Decision 080; owner 2026-11-16, Q4: *"Keep
      recording"*). Closing the Duo mid-take changes only the width: the reader
      lays out at compact width with the dock (the script, the round record
      control and Stop on the outer display), the take, the run and the cue go
      on, and opening the phone brings back the pane on the same line. Nothing
      that records lives in a view: `StudioModel` belongs to the reader's
      loader (it ends only when the reader closes), `RecordingSession` and the
      `LiveAudio` engine are Core, and no `onDisappear`, `scenePhase` or size
      branch inside the reader stops audio (a cast reading, `table`, stops with
      the loader too). When the hardware reconfigures under a take
      (`AVAudioEngineConfigurationChange`, an interruption's end) the engine
      restarts and puts its tap back on the same capture, so the take file
      holds what came before and after (`FoldContinuityTests`). The 860 pt
      switch never rebuilds the session, only its controls.
    - **Keys** (iPad keyboard; the reader holds focus): Space record / stop /
      cancel, J / K my next and previous line, R record again, Return keep.
    - Delete Unused Takes asks with a `confirmationDialog` naming the count; a
      take's Delete is a swipe action and a context-menu item, absent on the
      chosen take. Headphones, room tone and the microphone prompt are
      §4.12's, shown in the dock; no account line ever stands beside the record
      control (Decision 079, F11). Leaving the studio with no take deletes a
      local, unshared production (PLAYS-DESIGN §2.3 rule 3a).
  - **Marks** (Decision 076 S5; PLAYS-DESIGN §2.10 binding; web sibling WEB-DESIGN
    §4.16 item 15; port spec `docs/research/design/R2-marks-port-brief.md`). Core
    gains `MarksCore` (the anchor, `snapWords`, `pointAfter`, the overlap rules,
    `place` over `catalog/tests/golden/marks_anchor.json`, the notebook order) and a
    `MarkStore` (a JSON file per script in Application Support, `Marks/<script id>.json`,
    the web's shape; never `UserDefaults`, never iCloud until the sync phase).
    - **Selecting**: the Core Text page takes a text selection with the system's own
      handles (`UITextInteraction` over a `UITextInput` adapter of the page, or a
      read-only `UITextView` per page in TextKit 2, whichever keeps the layout): the
      selection maps to (line id, offset) through each drawn run's offset. The edit
      menu (`UIEditMenuInteraction`, iOS 16+) gains **Highlight, Underline, Breath,
      Pause, Beat, Note** as `UIMenu` actions after the system's Copy and Look Up,
      the native mark bar (Books' own place for it). A tap on a mark opens the same
      menu for it: the four hues and Delete for a highlight, Edit and Delete for a
      beat or note; Delete offers Undo through the shake-free `UndoManager` (the
      toolbar's Undo, ⌘Z on a keyboard).
    - **Drawing**: highlights as a fill behind the glyph runs (`Color.mark(_:)`, the
      generated token), underlines as a 2 pt `.primary` rule, a note's words under a
      dotted rule with `note.text` after them; breath `/`, pause `//` and beat `//`
      with its label (`.caption` capitals in a rounded outline) drawn by the layout
      in the space between two words, never inserted into the attributed text.
      A point mark re-paginates; a highlight does not.
    - **Pencil ink** (iPad, Apple Pencil): **Ink** in the reader's toolbar (a
      `Toggle`, `pencil.tip`) turns on a `PKCanvasView` per line block
      (`drawingPolicy = .pencilOnly`: a finger still turns pages and selects),
      sized to the block; its `PKDrawing` is stored with the line's anchor
      (`Marks/<script id>-ink/<line id>.drawing`), so ink moves with its line on
      reflow, a new text size (strokes scaled by the size ratio) and a page turn;
      a line a revision changes keeps its ink only when its text is unchanged,
      else the drawing is listed in the notebook as not placed (never drawn on
      other words). `PKToolPicker` is the system's; Scribble writes into a note's
      field. iPhone and Mac draw the ink read-only at the same anchor.
    - **Notebook**: **Marks** in the toolbar (`bookmark`, a `Label`) opens a sheet
      (`.presentationDetents([.medium, .large])`): a Show Marks `Toggle`, then a
      `List` of every mark in script order (glyph, speaker in `.caption`, the
      words, a beat's label, a note), a tap closing the sheet and going to the
      line; **Not Placed** as a second section with swipe-to-delete. Empty:
      `ContentUnavailableView` "Select words on the page to mark them."
    - **Keys** (iPad keyboard, with a selection): H, U, /, P, B, N; Esc lets go.
      VoiceOver: each mark is an accessibility custom action on its speech
      ("Highlight: first thing"), and the notebook lists them all.
    - Export: `DataExport` adds `marks[]` (docs/EXPORT.md).
    - **As shipped, 2026-11-15** (where the build settled what the paragraphs above
      left open; this bullet wins). The page is a SwiftUI `Canvas`, so selection is
      the reader's own over the Core Text frame, not `UITextInteraction`: a press on a
      word selects it (`MarkSelecting`'s `SelectionLayer`, a `UIViewRepresentable`
      over each spread), dragging grows the selection by words, two handles move its
      edges, the paging scroll stands still meanwhile, and the system's
      `UIEditMenuInteraction` carries the six verbs (Highlight shows the last hue). A tap
      on a mark opens a small popover (`.presentationCompactAdaptation(.popover)`, the
      Mac's too) with the four hues, Edit for a beat or note, and Delete; Delete
      shows "Deleted" with Undo and registers with the `UndoManager`. A point mark's
      room is figure spaces (U+2007, `ed.offset` -1, never a word) set in the page
      string right after its word, so the page re-paginates and the script's text is
      untouched; a kern on the word was tried and Core Text drops it once the whole
      script is one string. Marks draw on the Pages layout; Scroll (one SwiftUI `Text`
      a line) draws none yet. Pencil ink is below.
    - **Pencil ink as shipped, 2026-11-15** (`InkCore.swift`, `ReaderInk.swift`; this bullet wins over the
      per-block-canvas paragraph above). One `PKCanvasView` per page, not per line block, so a circle or arrow in
      the margin is possible; each stroke belongs to the line its first point is in (else the nearest), and is
      stored in that line's block coordinates: origin the block's top-left, units points at the text column's width
      when drawn, a line that runs onto the next page one block of stacked pieces. Drawn scaled by the column's
      width over the stored width, so ink moves with its line on a reflow, a new text size and a page turn.
      **Ink** (`pencil.tip`, a `Toggle` in the toolbar, iPad on Pages only) turns the layer on: the Pencil draws
      (`.pencilOnly`), a finger still turns pages, the system's `PKToolPicker` offers pen, pencil, marker and the
      eraser that takes a whole stroke (no lasso: a moved stroke would have no line). Selection is off while Ink is
      on. Stored per script beside the marks (`Marks/<script id>.ink`, each line's `PKDrawing` data). A revision
      keeps a line's ink when its words are unchanged (or moves it to the one id exactly those words moved to);
      otherwise it is listed under **Not Placed** with a picture, never drawn over other words. iPhone and Mac draw
      the same ink read-only (an image of the strokes in the page's `Canvas`). Show Marks off hides the ink;
      Hide My Lines hides a hidden line's. The notebook lists inked lines (picture, speaker, first words). Scroll
      draws none, like the typed marks. Export: `ink[]` (docs/EXPORT.md). DEBUG doors `APP_READER_INK=1`,
      `APP_READER_INK_FINGER=1` (a finger draws) and `APP_READER_INK_DEMO=1` (three stored strokes).

- **§4.12 An ear drama** (`apple/Shared/PlaysScreens.swift`,
  `RecordingScreen.swift`; PLAYS-DESIGN §2, Decision 067). The play's
  page is a `List`: its title, the author with their years when the
  record has them, the record's year when present, its length as
  "N parts · N lines" (speaking parts, every line), the rights
  line, and "Record This" (Decision 075, was "Start an ear drama");
  nothing else marks it. The cast sheet
  lists the parts largest first; every open part has Take Part, in any
  order, and the suggested one (`Relay.next`) is `.borderedProminent`,
  the rest `.bordered`, with no caption saying why. One part records at
  a time; taking another while one records shows the refusal. At Start
  Recording no account is asked (Decision 079; *replaced* 2026-11-15: "a
  signed-out person sees "Recording needs an account." and the account
  sign-in buttons"). Signed out, beginning a production while another on
  this device holds a take shows "A second production needs an account."
  and §4.10's sign-in buttons in a sheet instead of the studio
  (PLAYS-DESIGN §2.3); Share asks as below. Listen Through is always
  offered: a complete play plays its rendered mix (the end marks it
  Finished); an incomplete one runs `Relay.listenPlan` live, takes from
  their files and the other speaking lines read by `AVSpeechSynthesizer`
  `speak`, the current line's speaker and words on screen, "Device
  voice" on a read line, and Stop. When Personal Voice is offered
  (authorized, or "Use my Personal Voice" asks), it reads those lines
  through `speak` only, never `write`. Export (a `ShareLink`) is there
  whenever the play is complete, and renders the mix first if it is
  missing or stale.
- **§4.12b Making a part in direction D: three recording modes** (D3-6;
  `PlaysGrammar.swift`, `RecordingScreen.swift`, `RecordingSession.swift`;
  binding, and it supersedes §4.12's plain `List` page and single teleprompter
  where they differ). Owner ruling 4 (2026-10-29): *"One option should let you
  record and have the other parts play (either human voices or generated voices
  for parts that haven't been taken yet) and it should play right through with
  your opportunity to record your part as it shows up naturally within the Ear
  Drama script. Another option should allow you to record each line individually
  or re-record any lines again by tapping them and re-recording. Another option
  could be a 'wait for tap' to advance through the script as you are
  describing."* Owner rule 2026-10-30: *"It has to look good and use native
  design and apis on the given platform. There is no reason to degrade one
  platform in order to make sure everything is uniform across all platforms."*
  - **Pages.** A play's page and the cast sheet open on `HeadBoard` on the drama
    board (`PlayScript.boardGenre`; the genre is never named), the kicker "Radio
    play", "Stage play" or "Ear drama", the author facts, the year when the
    record has it, "N parts", "N lines", and the cast fingerprint in the mark slot
    (`CastFingerprint`: one bar, each speaking part a segment as wide as its
    share of the lines, largest first, in the board's ink). Then the actions
    row, then `PartCard`s in a grid: a face (`PartFace`: the mark color with the
    performer's initial; the device voice is the same circle outlined with a
    waveform; a check badge when recorded), the name in the display face, "N
    lines", and a 24-bar presence strip in the part's mark. The cast sheet's
    "who" line is "You · 5 of 76", "Pat · recorded", "Open" or "Left silent".
    Part marks are `PlayScript.partHue` (the seven largest speaking parts take
    mystery, scifi, western, serial, documentary, comedy, news; the rest,
    directions and sound are neutral). No card has a one-sided stripe. Browse's
    play tiles and Search's rows stand on the drama board too.
  - **The recorder** keeps its slots fixed in every mode and state: header (part
    name, play title, "K of N" kept), the strip (one cell per line of the part:
    kept in the part's mark, the current one outlined, red while it records), the
    mode control, the scene, the dock. The mode control is the native
    `Picker(.segmented)` ("Run through", "Line by line", "Step"), disabled
    while busy and during a run (`RecordingSession.setMode` refuses). The
    performer's line sits in a box on their part's board with its one on-board
    color: dashed red edge and "Next" while the cue plays, solid red edge, a red
    "Recording 0:03" pill and the level meter while the microphone is open.
  - **Step**: Previous, the round red Record (Cancel while the cue plays, Stop
    while listening), Next; after a take Again (red dot), With cue (blue), Keep
    (ink). Keep lands on the next line's Ready; it does not play its cue.
  - **Run through**: the round red "From here" starts the run at the current
    line (`runThrough(from:)`): other parts play in their usable takes or the
    device voice live, the microphone opens on each of the part's lines and the
    line-end detector closes it. While it plays the dock is ink Pause (red Stop
    while the microphone is open; both pause) and "N taken". Pausing or finishing
    opens the review: "This run · N takes", each row Line n, its text, play with
    its cue, its length and Again, then Discard the run (blue) and Keep N takes
    (ink). Discard deletes the run's takes and files and puts each line back on
    the take it had.
  - **Line by line**: every line of the part with "Take k" or "Not yet"; a tap
    opens that line in place with its cue above, the line box, Record (red) or
    Stop, and Cue (blue). No dock. The aids row (Run-up, Hear it read, the
    device-voice speed) belongs to Step and Line by line only.
  - **Color** is Decision 064's: ink acts, blue finds the way, red is recording
    only. Captions are a refusal, a warning or a fact a person cannot see.
  - **iPad (regular width)** puts the scene between a left rail "In this scene"
    (the parts near the line and who holds each) and a right rail with this
    line's aids. The stand-in buffers' lifetime is unchanged (§5 of
    PLAYS-DESIGN): held for the bleed check, then released; a run creates no new
    write path. The microphone is asked for at Start Recording, never at launch.
- **§4.12c The voices on the cast sheet** (Decision 076 S2; PLAYS-DESIGN §2.8 is
  binding; owner 2026-11-14: *"The virtual voices who play the different parts should
  also be intuitive."*; the web's WEB-DESIGN §4.10 for the shared words; port spec
  `docs/research/design/R2-voices-port-brief.md`). Built 2026-11-14 (PARITY 🚧; ✅ when
  the owner hears it on a device). Every part no person holds shows its voice as a
  button under the part card's presence strip (the card's face, name and strip are one
  button already, and a button does not nest in a button), `caption` in the link color:
  the voice's `name` ("Ava (Premium)", "Samantha (Enhanced)"), "Not read" for Stage
  directions and Sound effects, and `exclamationmark.triangle` before the name when the
  cast voice is not installed and the auto-cast voice reads instead. Tapping it pushes
  (iPhone) or presents as a `.sheet` with `.presentationDetents([.medium, .large])`
  (iPad) the **voice picker**: a `Form` with Speed and Pitch as `Stepper`s, then a
  section "On this Device" of `AVSpeechSynthesisVoice.speechVoices()` filtered to
  English, not Personal Voice, not `.isNoveltyVoice`, sorted by `quality` (`.premium`,
  `.enhanced`, `.default`), the person's own language, then name; each row a selection
  row (checkmark) with a `play.circle` button that `speak`s **the part's first line**
  in that voice. The section footer is "Add voices in Settings > Accessibility > Spoken
  Content > Voices." with an **Open Settings** button that opens
  `UIApplication.openSettingsURLString` (the app's own page: no API lists, starts a
  voice download or opens the Accessibility pane; R2 §2.7). The Settings path is the
  one the brief states; the iOS 26 pane name could not be confirmed from here (no
  agent drives Settings), so it stays UNVERIFIED until the owner reads it on a device.
  The sort is quality first (the largest part gets the best voice), then the person's
  own language, then name; the web's order, no longer Apple's old language-first one. Auto-cast alternates the voices'
  own `gender` (`.male`, `.female`; `.unspecified` counts as none). Voices are chosen
  by `identifier`, never `AVSpeechSynthesisVoice(language:)`. The cast is a
  `VoiceCast` in `Core/Plays` read by `SystemStandInVoice`, `LiveListen` and the
  reader's Hear the Cast (`VoiceCast.swift`, `VoiceCastModel.swift`, `SpeechSetting`:
  one place builds an utterance's voice, pitch and rate); stored in `UserDefaults`
  (`ed.cast`, keyed `p:<production>` and `s:<script>`, the newest 80), never in
  `production.json`, never synced. Recast All sits with Discard Unused Takes; the
  chips repaint on `AVSpeechSynthesizer.availableVoicesDidChangeNotification`. Debug
  doors (DEBUG only): `APP_PRODUCTION=<script id>` opens a production's cast sheet,
  `APP_PICKER=role:NAME` its picker, `APP_READER_HEAR=1` Hear the Cast; `APP_MUTE=1`
  mutes the synthesizer (volume 0, a line still takes its time). The reader gets a
  Voices toolbar item and Hear the Cast (§4.15). Personal Voice stays the
  listen-through toggle it is (§4.12) and is not in the picker.
  **Downloaded** (Kokoro, Decision 078, S6e; PLAYS-DESIGN §2.8 rule 10; built 2026-11-15,
  PARITY 🚧): a third `Form` section, "Downloaded", under "On this Device": a
  **Download Voices (SIZE)** button; while downloading a `ProgressView(value:total:)` with
  "34 MB of SIZE" in `caption` and a **Cancel** button (`role: .cancel`); a failure is
  `exclamationmark.triangle.fill` "The download failed." in the warning color with **Try
  Again**; once here the 28 Kokoro voices as the same selection rows with `play.circle`
  previews ("Heart (Kokoro)", best grade first, "English (US)" / "English (UK)" under each),
  then **Delete Downloaded Voices (SIZE)** (`role: .destructive`), and the attribution as the
  section footer. A play without published phonemes shows "Not available for this play." in
  place of the voices. The model is our own Core ML conversion (`tools/convert_kokoro_coreml.py`,
  fp32 with uncompressed weights, 532 MB with the voice table; `kokoro-v3-apple-manifest.json` on the
  Release `kokoro-model` since 2026-11-22; every compressed variant failed the check against PyTorch),
  fetched by `KokoroModelStore` through `APIClient.download` (HTTP Range resume, SHA-256 per
  file), kept in Application Support/Kokoro (never Caches; excluded from backup), compiled
  once per version on the device. `KokoroReader` reads the play's `phonemes/<id>.json`, renders
  100-symbol pieces on `CoreMLKokoroRenderer` (fixed-shape functions per bucket, on the CPU:
  the Neural Engine's compiler refuses the decoder and the GPU's buffers tripled the footprint on the Mac), refuses a non-finite or silent render and marks every buffer synthetic;
  `KokoroLive` plays a line once through `AVAudioPlayerNode` (nothing when muted) for Hear the
  Cast, the listen-through and the preview; `KokoroStandInVoice` hands the recorder's cue a
  `StandInAudio`. A Kokoro part's line Kokoro cannot read is read by its auto-cast system
  voice (`VoiceCast.systemFallback`). The group and the engine sit behind `KokoroFlag`: on in
  DEBUG, in a release build only once the S6a gate passes on the iPhone 12 (off: passed on the Mac
  2026-11-16, not yet measured on the iPhone; R2-kokoro-feasibility "S6e on the Mac"). DEBUG door:
  `APP_KOKORO_BENCH=1` (`KokoroBench`, the S6a bench; `APP_KOKORO_BENCH_PLAYS`, `_LINES`,
  `_MINUTES`, `_UNITS`, `_KEEP`, `_ROOT`).
- **§4.12a A shared ear drama** (phase 2; PLAYS-DESIGN §11.7, binding:
  "The same verbs on the web, iPhone, iPad, Mac, and Android ... Words on
  screen are these, on every platform"). Logic in `PlaysShare`
  (`apple/Core/Plays/PlaysShare.swift`, tested against a stub Worker);
  every call through `APIClient.workerResponse`, refreshed first.
  `share.json` (`{ pid, consented }`) sits beside `production.json`.
  On the cast sheet, above the parts: **Share** (signed out, "Sharing
  needs an account." and §4.10's sign-in buttons; an optional name in an
  alert). Shared, the parts are the Worker's: mine and recording,
  **Record**, with **Done with This Part** and **Release** in its
  menu; open while none records, **Take Part** (`next` prominent,
  `.borderedProminent`; the rest `.bordered`) and, for sound and
  directions, **Leave Silent**; finished, mine or I direct, **Open
  Part** in its menu; another's claim reads "Recording" and the name.
  Then one row each: the director's **Invite** (a `ShareLink` of the
  https twin, caption "Works for N days."); **Upload N Takes**, or,
  while the owner's switch is off, the warning "Uploads are off." with
  the button disabled, shown before anyone records; **People** (a
  sheet: display names, "You" and "Director" as tags, **Report** with
  a reason Picker and an optional note, **Block** after "You will no
  longer hear their takes."); the archive.org job as PLAYS-DESIGN rule 9 words it (a quiet line, **On archive.org** as a `Link`, or the reason with **Publish Again**); once published a "Your Lines" (director: "Lines") section whose **Replace** pushes the recorder on that line and whose **Remove** asks with a `confirmationDialog` (rule 13); "N takes are hidden from you." when the Worker hides some.
  **Publish** opens a sheet (`ConsentSheet`) with the Worker's consent
  words and "I agree to publish my recording under CC0." / "Not Now", and
  is offered only while `GET /consent` says `publishes`, else "Publishing
  opens when the Ear Drama archive account is connected." (Decisions 059
  and 072); uploading asks no consent. Opening a shared cast sheet, pulling to
  refresh, and the app returning to the foreground (`scenePhase`) re-read
  the record (PLAYS-DESIGN §11.7 rule 7). Opening a shared cast sheet fetches the other members' chosen takes into
  `takes/` (never overwriting a file), so Listen Through is phase 1's.
  A read-along line voiced by someone else has **Report Take** in its
  context menu. Refusals are `PlaysShare.line`, the web's strings.
  Library's Ear dramas, signed in, also lists the shared productions not
  on this device, then **Classes** (a teacher's code as two groups of
  four, "Waits for the school's consent" on an under-13 class without
  it, **Make a Class** with a name and an "Under 13" toggle, **Join a
  Class** by code). An invite link (`eardrama://invite#TOKEN` or its
  https twin, `DeepLink.parse`) lands in the inbox, selects Library,
  and shows **Invitation** first: the title and parts; signed out "Sign
  in to join"; each open part **Take Part** with an optional name; a
  member **Open**; **Not Now** drops the token. tvOS offers none of it.

- **§4.19 Reading together** (T4, 2026-11-19; `apple/Shared/ReadViews.swift`, `apple/Core/Plays/ReadSession.swift`). Binding rule: PLAYS-DESIGN §12 and Decision 082. The verbs are the web's (WEB-DESIGN §4.17 to §4.19): join a room by code (`eardrama://read/CODE`, its https twin, or the code typed); a class room asks for the class code, then lists the names (a seat's key is held in memory for the app run only, owner 2026-11-19: a shared device keeps nothing at rest); the reader follows the lit line (my lines tinted, "Next: you, in N lines", "Back to the Line" after a scroll, "Hide My Lines" in Rehearse, no sound on a reader device); the leader moves it with Back, Next and Again (arrow keys on a keyboard) and a Reading menu: mode, Lock Joining, Read Open Parts (a message to the room that the screen obeys), Open the Screen, End. A waiting room says "Waiting for <the leader's name>" (the name travels in the snapshot). The teacher's class page: the code behind Show Code, Start a Reading, seats (paste a list, Release, Remove), plays with per-seat counts, and the casting board (parts largest first with lines, words, scenes, longest; Fill Evenly, Split by Scene, Clear, Save). Refusals and warnings use `ReadCore.refusal`'s words, one line, never an explanation. iPhone: a picker per part on the casting board. iPad: the same board, and a seat chip is dragged onto a part (`draggable` and `dropDestination`), with the picker still there. Rotation never rejoins: the session outlives the view. The open iPhone Duo's outer display showing the current line when folded (Decision 080) is NOT built: it needs the device's scene and is waiting on a hardware check (SCRATCHPAD).
- **§4.20 Your Parts and Relay across time** (T6, 2026-11-19; `apple/Shared/RelayViews.swift`, `apple/Core/Plays/RelayAcrossTime.swift`). Binding rule: PLAYS-DESIGN §12.11 and Decision 083. A seat at home: **Your Parts** is a link on the room's join form (`Route.parts`); no seat yet, the class code then the names (no account, nothing typed but the code; the key goes to the Keychain, the class and name to `ed.homeSeats`). With a seat: its name and class, each class production with a part's name and line count and **Record** (the studio opens on a production kept on this device, linked to the seat), and under it every line the seat holds as its first words with the take's state: "On this device · sends when Ms. Ortiz is in Ear Drama", "Sending", "Sent", then the teacher's review ("Approved", or "Again · note" in the error colour). `RelayHub` (one `RelaySender` per linked production) asks `GET .../receiver` first, sends one take at a time, and asks again after 5, 10, 20, 40 s then every 60, on launch, and when the app comes forward. The teacher's class page holds each production's pickup while it is open (`ClassInbox`) and the progress row moves on every arrival ("3 of 43"). A credited maker is listed beside the performers who have not agreed and Publish stays off. NOT built: opening an adult room on a production (the Worker allows it for the director; no client does yet), and the review of an at-home take in the class page (review is in the room's Takes sheet).
- **§4.19a The room inside the reader, Record in the room, pairing (T5, 2026-11-19; `apple/Shared/ReadRoomReader.swift`, `apple/Core/Plays/ReadRecord.swift`, `ReadScreenView.swift`).** Binding rule: PLAYS-DESIGN §12.5 and §12.10. **Fix of T4's defect**: T4 drew a room as its own plain list (`ReadLineRow`), not the reader; that list is gone. A joined room is `ScriptReaderView(scriptID:, room:)`, the studio's seam for a room: the reader's own Core Text pages turn to the room's cursor and light it (the read-along's follow logic: a scroll or a page turn stops it and shows **Back to the Line**), my lines are tinted in their part's hue from the room's claims or a seat's ranges (`Marks.mineLines`, so a class seat's scene ranges tint exactly), my line at the cursor is outlined (ink; solid record red only while the microphone is open, Decision 064), and **Hide My Lines** (Rehearse, not for the leader) hides them like a played part's. The **room bar** under the page is the chrome: one line (a refusal or warning, else "Next: you, in N lines" or "Your line", else "{name} is reading" in Record, else the part, its reader and Open), "N here", the page count, then Parts (an adult room's non-leader), the leader's Back / Again / Next, and the **Reading** menu (Mode: Table Read, Rehearse, Record; Record Every Line Here in Record; Lock Joining; Read Open Parts; **Add a Screen**; Open the Screen; End the Reading; the code). The reader's Close button is absent in a room (the room is a pushed screen); the Mac keeps no Contents sidebar in a room. **The Record row** (Record mode, a reader): **Start Recording** once per room (the microphone permission, then five seconds of "Quiet for N s" room tone; no headphones gate, no cue), **Recording** with **Stop** while a take is open, "Quiet while others record" while another holds the line, "{n} takes on this device" while the outbox waits, and **Takes** on the receiver. The engine is `RecordingSession.recordInRoom` (listen-and-keep, capture `room`, credited to the line's part); `ReadRoomRecorder` keeps one local production per room code (`Production.room`, `roomOutbox`), writes the take first, sends `line-done`, sends `PUT /v1/read/{code}/takes/{id}` and retries every 5 s on `nobody_receiving`, offline, 5xx; the receiver holds `GET .../takes/inbox` only while the room records and imports arrivals as chosen takes (newest wins); One microphone credits the line's part (and seat) and moves the cursor on. **Takes sheet**: counts per reader, each speaking line Recorded (Play, Again), On {name}'s device, Waiting or Open; in a class room with a production Approve and Again, which offers an optional note (500 characters; an empty note sends no review); Listen Through and Export (the production screen's `ListenThrough` over the room production); **Publish Under My Name** only in a 13-and-over class with a production (credit name, the CC0 consent, `publish { credit_name }`, then each line to `archive/files` one at a time, `not_ready` waits and retries, `already_sent` skipped); an under-13 class shows "An under-13 class never publishes." and One microphone is on by default there. **Names**: the join screen takes an optional name (kept on this device as a convenience; the app has no chosen account name), `bad_name` reads "That name is not allowed.", and a room the person opens carries it as `owner_name`. A missing or ended room reads "No reading with that code." / "This reading has ended." on the join screen and in the room (the shared client now reads a refusal by its status when the Worker's body has no code, the cause of T4's "could not be reached"). **Not built**: the Takes sheet's Listen Through / Export / Publish foot is not drawn in the Apple render (it is the production screen's own view and needs the player); Publish and the class review have no UI test on a device; the leader's Record row on an iPad has no regular-width variant beyond the bar; no real-device pass this round (the brief forbids simulators and devices).

## §5 The player

- **§5.1 One engine.** `AudioPlayer` (`apple/Core/Player/AudioPlayer.swift`)
  is shared by every Apple platform: AVPlayer, the `.playback` /
  `.spokenAudio` / `.longFormAudio` session, Now Playing, and remote
  commands. Views draw it and never touch AVFoundation.
- **§5.2 The mini player** sits in each tab stack's bottom safe-area
  inset while an episode is loaded (`MiniPlayer_iOS`,
  `apple/iOS/PlayerViews_iOS.swift`): title, series, Play or Pause; a
  tap opens the player.
- **§5.3 The player is a sheet at compact width, two panes at regular
  width** (Decision 080; owner 2026-11-16, Q2: *"Two panes"*). On a phone,
  the closed Duo and a narrow window it is a sheet with its drag indicator
  (`PlayerSheet_iOS`). At regular width (the open Duo, an iPad, a wide
  window) it is a `fullScreenCover` holding an `ArrangementView` (iOS
  27.1; an `HStack` before it): the player as the primary, what plays next
  (§5.9) as the secondary, side by side in landscape and stacked in
  portrait, the system splitting the two around the fold. The presentation
  is chosen once, by the horizontal size class when the player opens
  (`PlayerPresentation`), so folding or unfolding never dismisses it: a
  cover open when the Duo closes stays open and the split shows the player
  alone; nothing reads the device. Close (`chevron.down`, a `Label`) is the
  first toolbar item in both, so the Duo's strip carries it at the top.
  *Replaced*: "**§5.3 The player is a sheet** with its drag indicator
  (`PlayerSheet_iOS`)". The player itself: series, title, date and network, the scrubber,
  elapsed and remaining time, back 15 s, Play, forward 30 s, then
  speed, the sleep timer, and AirPlay's own `AVRoutePickerView`
  (`RoutePicker_iOS`, labeled "AirPlay"; the `.longFormAudio` session
  routes the whole player, and Now Playing follows it). Errors
  and the offline warning sit under them, and "Next:" names what the
  queue holds. The toolbar carries Close and, when there is one, the
  transcript.
- **§5.9 What plays next, beside the player** (Decision 080; regular
  width only: the phone keeps "Next:" on the sheet). `PlayerQueuePane`
  (`apple/Shared/QueueViews.swift`), a `List` read from the player's own
  queue, never a new data path: **Up Next**, the arc's next part
  (`AudioPlayer.upNext` while `arc.nextPart` is set, "Part N of M"); then
  **Queue**, `ListeningQueue` resolved by `catalog.episodes`, each row
  dragged to reorder in place (no Edit), swiped or right-clicked to remove,
  its context menu `QueueRowMenu` (Move up, Move down, Remove): the queue
  verbs of §12 on Library's own row (its Play plays it now, as in Library),
  nothing more. An empty queue says Library's sentence.
  **Listening live** the pane is the lineup instead (`LiveRadio.lineup`):
  each slot from the one on the air to the evening's end, its time, show
  and episode, "Now" on the slot playing, gaps as `GapLine`; nothing in it
  plays, since the clock decides. A Listen Together guest sees the same
  pane; its verbs change only their own queue.
- **§5.4 The lock screen and Control Center** get title, series, the
  network as artist, position, and rate. Remote commands are skip
  intervals, never next and previous track, because setting both makes
  CarPlay and the lock screen pick one arbitrarily.
- **§5.5 Interruptions are spoken word.** When an interruption ends with
  "should resume", the player backs up 3 s
  (`PlayerNumbers.interruptionRewindSeconds`) and resumes; unplugged
  headphones pause.
- **§5.6 Progress** saves every 5 s while playing
  (`PlayerNumbers.saveEverySeconds`) and on pause; a saved position
  resumes exactly where it was saved, as on Android and the web (only an
  interruption rewinds, §5.5), only past 30 s, and an episode within
  45 s of its end counts as played (`ListeningHistory`).
- **§5.7 The player's numbers are Decision 062's, named once.**
  `PlayerNumbers` (`apple/Core/Player/PlayerNumbers.swift`) holds the
  sleep fade (`sleepFadeSeconds`, 10), the speeds (`speeds`, 0.75, 1,
  1.25, 1.5, 2), the save cadence (`saveEverySeconds`, 5), and the
  interruption rewind (`interruptionRewindSeconds`, 3). Every Apple
  platform reads them from there, and `PlayerNumbersTests` holds them
  to the decision; a literal of one of them anywhere else is a bug.
- **§5.8 Listen Together is SharePlay** (LOOP-PLAN M6, Decisions 065,
  064). One control on the player, after the sleep timer: the
  `shareplay` symbol (`ListenTogetherButton`,
  `apple/Shared/ListenTogetherViews.swift`). In a FaceTime call it
  starts at once; outside one it opens the system's own
  `GroupActivitySharingController`, which picks people and places the
  call. It never plays alone in place of starting. Once a room is live
  the same control is a menu with Leave SharePlay; the system's SharePlay
  UI carries who is there. A following member's skip, speed, and
  scrubber are disabled, and the one caption is the refusal "The host has
  the controls." Play and Pause stay theirs (Decision 067): Pause holds
  their own sound while the room plays on, and Play catches them up to
  where the host is now (`AudioPlayer.isHeld`, `SharePlayRoom.follow`); a
  held member handed the room takes it from where the room is. The control is chrome, so it takes the tint, never the
  primary ink.
  - **The rules are the Worker's, ported, not re-derived.**
    `RoomProtocol` (`apple/Core/ListenTogether/RoomProtocol.swift`, no
    import) ports `worker/src/room-protocol.js`: the arbiter, the host's
    exact copy, the clock, drift corrected by speed before seeking, and
    handoff to the member present longest. `RoomProtocolTests` reads
    golden cases written by the JS itself
    (`apple/Tests/Fixtures/make-listen-together-golden.mjs`; `--check`
    fails when stale). `SharePlayRoom` is the thin transport: the room
    message in the Worker's field names, the host's roster, and clock
    samples over one reliable `GroupSessionMessenger`; the host's device
    is the room's clock. It listens for sessions from launch. Two
    devices that start at once both claim the room; every device keeps
    the claim with the lower participant id (`RoomProtocol.claimWins`,
    no clock in it), and the loser drops its state and follows.
  - **Not AVPlayer's playback coordinator**, on purpose: it lets every
    participant drive, suspends the group for one stalled member, and
    syncs whatever item each player holds. The protocol says the
    opposite on all three.
  - **Owner step**: enable Group Activities (and Sign in with Apple, §4.10)
    on the `app.eardrama` App ID, remake the profiles, then turn on
    `CODE_SIGN_ENTITLEMENTS` in `project.yml`. The key is already in
    `apple/Resources/EarDrama.entitlements`; a signed build naming a
    capability the App ID lacks fails, so it stays off until then.
    Verifying needs two devices on two Apple IDs in a FaceTime call.

## §6 Look

- **§6.1 Every value is a token** from `design-tokens.json`, read
  through the generated `apple/Core/Design.swift`. Never hand-edit it.
- **§6.1a Color roles (Decision 064, On Air).** The root tint is
  `Color.brandSecondary` (blue), so links, the selected tab, toggles,
  and every button that is not Play take it, and `AccentColor` is the
  same blue. Ink (`Color.brandPrimary`) is set with `.tint` on the
  primary action: Play and Pause, Listen Through, Listen live, the
  scrubber, and the progress line in a row; a prominent ink button
  sets its label in `brandOnPrimary`. Red (`Color.brandRecord`) means
  recording and nothing else (owner, 2026-10-29: *"Red means
  recording."*): Start Recording (label in `brandOnRecord`), the record
  control, and "Your line" while the microphone is open;
  `tools/test_apple_design_rules.py` fails on it anywhere else. Genre
  hues are content: the series row's leading genre mark, never chrome.
- **§6.2 Six type levels** (`TypeRamp`) over the system text styles,
  so Dynamic Type works and nothing truncates a title. The page title
  and section header set the bundled Big Shoulders Bold at their
  style's size, scaled `relativeTo:` that style (Decision 060); body
  text is the system face.
- **§6.3 `.buttonStyle(.plain)` is correct here** on a label that should
  not tint as a button (the mini player); rows with two targets use
  `.borderless`. This inverts tvOS (§11.2).
- **§6.4 Icons are SF Symbols** (R-ICON-1). Emoji are never chrome.
- **§6.5 Haptics use the one taxonomy** (`selection`, `light`, `medium`,
  `heavy`, `success`, `warning`, `error`), mapped to the system's
  `SensoryFeedback` in one place, `Haptic` (`apple/Core/Haptics.swift`).
  A view names a `Haptic`, never a `SensoryFeedback` or a feedback
  generator. Wired on the phone (`HapticFeedback_iOS`,
  `apple/iOS/ContentView_iOS.swift`): `selection` when the tab changes,
  `success` when a download finishes, `error` when the player's error
  line or "Download failed" appears. `tools/test_apple_design_rules.py`
  fails on a feedback call that skips the mapping.

- **§6.r The label is the default art** (Decision 081; the shared rule is WEB-DESIGN §6.4r, R3a
  §3.4). Wherever this doc names the typographic card, the title block or the initial as the art
  of something without a picture, that art is now **the label**: a flat transcription disc drawn
  natively (SwiftUI `Canvas`) from the same `labelSpec` goldens as the web (`cross-platform-determinism`):
  genre board, a run arc on the 1930-1962 dial, the monogram or the episode's date on the label,
  network · decade on the rim at tier L from `series.network`; a finished ear drama's part-hue rim;
  a person's groove ring; a play's script page with voice-band rules. A picture that passes the
  size floor always wins, and the two never share an object's slot. Networks and sponsors are names
  in our type, never logos; user-made ear dramas never take an uploaded picture. Now Playing and the lock screen show each episode's own label. Built in
  Round 3 V4.

## §7 States and accessibility

- **§7.1 Every list has four states.** Loading keeps the eventual layout
  (`SkeletonRows`, hidden from VoiceOver); empty is `EmptyState`
  (§7.4); a catalog that cannot open at all is
  `CatalogUnavailableView` with Try Again; "Series not found" and
  "Episode not found" carry no retry because retrying cannot help.
- **§7.2 Offline is a degraded mode, not a failure** (web §7.3, Android
  §7.1). While the device has no network, `OfflineLine` ("You are
  offline.", the neutral color) sits above the mini player on every tab;
  the seed or downloaded catalog, downloads, and Library keep working
  under it. `OfflineNotice` ("Offline. Episodes need a connection to
  play.", the warning color) is the refusal on Detail and the player,
  only when the episode is not downloaded, and an undownloaded episode
  that fails for the network says "You are offline." as the player's
  error line (with the `error` haptic), never a spinner. The transcript
  reader says "You are offline." and retries on its own when the network
  returns. `APP_FORCE_OFFLINE=1` renders the state.
- **§7.3 VoiceOver.** Every transport control, speed, and the sleep timer
  carries a label and a value; the mini player says "Now playing" with
  the hint "Opens the player"; an episode row reads as one element with
  its progress as a value; AirPlay is "Play on another device".
- **§7.4 One empty state: the fact and at most one action** (P4,
  2026-10-28; `universal-feature-states`). The rule it serves (AGENTS.md,
  owner): "Only essential words on screen. A caption must be a refusal, a
  warning, or a fact the person cannot discover by looking." Every empty
  list on iOS, macOS, and tvOS is one view, `EmptyState`
  (`apple/Shared/EmptyState.swift`): a title that states the fact, a
  symbol, and at most one productive action, never a description. It
  heads the screen's own list and never replaces navigation the screen
  carries: an empty Library is "Nothing played yet" with Browse (it opens
  Browse), and Account and the site pages stay under it, signed in or
  out. Browse with nothing matching offers Clear Filters; Tonight that
  could not load offers Try Again. No results echo the query, "No
  matches for “{query}”", and suggest nothing. Where no action helps (no
  shelves, nothing to pick, no evening today, no downloads, no lines in
  a part) it is the title alone. "Not found" pages use the same view
  with no action. `tools/test_apple_design_rules.py` fails on a
  title-only `ContentUnavailableView` outside `EmptyState`, and on a
  Library whose empty state is not inside its list above Account and the
  site pages. `APP_EMPTY_LIBRARY=1` (DEBUG) draws Library as a new
  listener's; `EmptyStateUITests` drives it and an empty search.
- **§7.5 No hints** (one-shot tips; P4, 2026-10-28). Each candidate
  failed `learning-orientation-design`'s test or §7.4's rule: a "press
  and hold to queue" tip teaches what Detail's Queue button already
  shows; Edit is in the toolbar; swipe-to-remove is the system's idiom.
  The one fact a person cannot see, that Search finds words said in an
  episode, belongs in the search field's prompt, not a banner (the
  prompt's words are the owner's call). So there is no HintBanner, no
  dismissal store, and no "Show tips again": a reset with nothing to
  reset is a word without a job. A hint needs a rule here first.

## §8 Values

- **§8.1** The rights line, the "Automatic transcript" label, and
  volume leveling are stated in §1.7 and are not reworded here.
- **§8.2** No analytics and no third-party code (AGENTS.md "no
  third-party Swift packages"). The privacy, credits, and take-down
  pages are the website's; the app links to them when that row lands
  (PARITY §2).

## §9 Stubs that live in the iOS target, and parity

- **§9.1 CarPlay** (`apple/iOS/CarPlay_iOS.swift`) is the car's four
  tabs (R17): Continue, Stations, Browse, Downloads. Continue lists up to 12
  in-progress episodes with their progress and plays through the one
  `AudioPlayer`, then pushes `CPNowPlayingTemplate.shared`. Downloads
  lists the finished downloads, newest first, up to the car's row
  limit, each playing its file the same way ("No downloads" when there
  are none). Stations and Browse say "Not in the car yet". No transcript in the car. It is
  dormant until Apple grants `com.apple.developer.carplay-audio`.
- **§9.2 The Apple Watch** (`apple/watchOS/EarDramaWatchApp.swift`) is
  Continue and, later, downloads only; until the phone hands its history
  over it says "Waiting on the phone". It is not embedded in the phone
  app yet. No browsing on the wrist.
- **§9.3** Update `PARITY.md` in the same change set as any user-facing
  change, and quote these rule numbers in proposals. A Core change moves
  all three Apple columns, so build macOS and tvOS too.

## §10 Traps this codebase has already paid for

- **§10.1 The iOS 26 tab accessory resets every tab's stack.** Putting
  the mini player in the tab view's bottom accessory changes the
  `TabView`'s identity when playback starts, so each stack carries the
  mini player in its own safe-area inset instead.
- **§10.2 Own the stores in the `App`'s `@State`**, never inline in
  `body`, or a re-evaluated scene swaps in fresh stores and drops
  navigation and playback.
- **§10.3 Each platform branch is explicit** (`RootView`): a bare
  `#else` silently gives a new platform the iOS tree.
- **§10.4 `Text(verbatim:)` for dates, counts, and clocks**, so a locale
  never reformats `1943-05-25` or `1,098`.

**R14 Dates and recordings never show raw archive text** (owner, 2026-10-31: *"We want to be both unambiguous and well designed. Spelling out the month (or abbreviating it for space) is far better."*; AGENTS.md: raw upload text never shows). `AirDate.medium` is the one formatter for rows and event lines ("Sep 17, 1949", "Sep 1949", "1949"; the system's abbreviated month); `AirDate.display` is the long form for Detail; `EpisodeRow.displayTitle` uses it too. Recordings are named by `RecordingLabel` (the catalog's `recordings.label` behind a column-exists guard, else "Recording N", best copy marked); the archive.org identifier never renders. `AirDateTests` fails on an ISO shape or an identifier-shaped label.

## §11 Deliberate inversions

- **§11.1 iOS never steals focus or opens a surface on its own.** Play on
  Detail starts the audio and leaves the person where they are. tvOS
  inverts this on purpose: it focuses Play on Detail and opens Now
  Playing full screen (`docs/tvOS-DESIGN.md` §6.2).
- **§11.2 `.plain` is right here and fatal on tvOS**, which uses `.card`.
- **§11.3 The transcript is a sheet.** The Mac opens a window, the TV a
  full-screen reader, Android a route, and the web a closed section; the
  label is the same everywhere.
- **§11.4 A tab keeps its stack.** tvOS resets the stack it leaves.
- **§11.5 The player is a sheet on a phone, not a full-screen cover.**
  Audio has no picture to give the whole screen, and the sheet keeps the
  tab behind it in view. At regular width the cover is earned by the
  second pane (§5.3, Decision 080), as Music's Now Playing on iPad; the TV
  is the other platform where Now Playing fills the screen. *Replaced*:
  "**§11.5 The player is a sheet, not a full-screen cover.**"

## §12 Open (what the code does not yet meet)

Listed, not fixed. Each item names where it is.

- **Listening live drifts at a speed other than 1x**: the offset is
  taken at join, and the player's speed is the listener's.

- **What plays next is the owner's rule** (Decision 067): a part of a story arc (contract §3.3) is followed by the arc's next part, automatically; at the arc's last part playback stops and the series' next story is offered as a "Next story" action, never started. Anything the person queued plays after an arc's last part, as after any episode. Outside an arc: one episode, then the queue, then stop. A live slot follows its clock, never an arc
  (`queue: false`). `PlaybackQueue.after` and `.offer` are the rule;
  `CatalogDatabase.arc(of:)` reads it; Now Playing's "Next:" line names what
  is up next and `NextStoryButton` offers the next story on the last part
  (iOS, iPadOS, macOS's transport bar, tvOS's action row), never for a
  Listen Together guest. The same on every platform.
- **R8 commercial chapters**: no data marks a commercial's start and end
  yet (contract §3.2a), so no chapters are drawn; when it does,
  `AVPlayerItem.navigationMarkerGroups` carries them. Skip stays a fixed
  interval.
- **Resume and "played" differ from the web**: past 30 s and played
  within 45 s of the end, against the web's 10 s to 95% window (§5.6).
  Decision 062 settles the fade, speeds, save cadence, and rewind
  (§5.7), not these two.
- **An untitled episode falls back to its date, then the series name**
  (`EpisodeRow.displayTitle`); the web says "Untitled".
- **Series browse facets are not counted against one another**
  (`catalog.browseFacets()` takes no selection), so an offered choice
  can yield zero rows; the web forbids that (`WEB-DESIGN` §10.5). Plays
  follow the series under every sort; the web interleaves them.
- **Seasons are sections, not a scope** (`SeriesScreen`); the web and
  Android show one season at a time.
- **The series link on Detail is a push**, so Home, Episode, Series
  is a third level (§1.5), and from there another episode is a fourth.
- **The queue verbs are the web's** (`WEB-DESIGN` §4.5, §4.7): add to the
  end (an episode already queued moves to the end), remove, move up or
  down. Detail carries "Add to queue" / "In queue" under Play; every
  episode row's context menu carries "Add to queue" or "Remove from
  queue"; Library's first section, "Queue", swipes to remove, drags to
  reorder (Edit on iPhone), and its context menu has Move up, Move down,
  Remove. `ListeningQueue.onChange` calls `AudioPlayer.refreshUpNext()`,
  so the player's "Next:" line follows the queue. The verbs only order
  what the person chose; what plays next is Decision 067's, untouched.
  Following's rules are §4.1 (Home), §4.3 (the button), and §4.6 (Library).
- **R20's "one step from the lock screen"** is not built: the timer is
  only on the player sheet.
- **Deep links take only the URL's last path component**
  (`.onOpenURL` in `EarDramaApp.swift`), so `/search?q=` and `/library`
  are read as a series key. The twins in `DEEP_LINKS.md` are not routed.
- **The watch stub would show raw episode ids** (`Text(id)` in
  `ContinueView_watchOS`) once history arrives; an id never reaches the
  screen.

Closed 2026-10-23: the player's numbers are named once (§5.7), haptics
go through one mapping (§6.5), and Detail shares the https twin (§4.4). The two empty states that
explained (Listen, Library) lost their descriptions (§1.6).

**E1 rules (2026-10-30, D4 review).** The player sheet's toolbar carries Add to queue (a toggle) and Share (`ShareLink`), icon only, beside the transcript button; the identifiers `player-queue` and `player-share` are the tests' doors. Stations after the evening ends: Tonight keeps "Ended at ..." and its button reads Replay (the first playable slot, played as an episode). Account carries an Export section: "Export my data" (JSON) and "Export history (CSV)" through `ShareLink`; no upload, no sign-in needed (docs/EXPORT.md). The rights fallback computes its year from the calendar; nothing types it.

Bring the next change back to a rule here, or bring a new rule first.

- **Head board name (iPhone 12, 2026-10-31):** a long title filled five lines on Surprise. The name steps down by its length as well as its longest word (`Grammar.headNameStep`: one step past 28 characters, two past 48), holds to three lines with a 0.6 scale floor, so a head board and its Play button fit one 375 pt screen. Web balances the break (`text-wrap: balance`) and clamps to three lines; Android clamps to three.

- **Student privacy on the class page** (Decision 084, 2026-11-21; PLAYS-DESIGN §12.12, binding; `apple/Shared/ClassPrivacyViews.swift`). The class page closes with a **Class** section: **Ends {date}**, a compact date picker (today to 400 days) with **Change date**, **Export class** (the system file exporter), and **Delete class** (destructive confirmation). An under-13 class without school consent opens with **School approval**. The age question is a sheet with a year picker and no default before a first Share, Invite, Take Part or Publish; only the boolean is kept (`UserDefaults` `ed.over13`).
