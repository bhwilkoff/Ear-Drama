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
  `TitleBlock`, the monogram as an outlined Core Text path in onBoard),
  `ShowTile` (window, name, `RunStrip`, facts, on `Color.board(_:)`;
  names in one shelf share the tallest name's height, so every strip
  sits on one line), `GrammarRow` (64 pt, a 48 pt visual: `DateBlock`
  in a series' own list, the series' window where series mix; title,
  sub, length, Play), `HeadBoard` and `EventLine` (a flow layout that
  keeps each " ·" with the fact before it). Home's shelves draw
  `ShowTile`; Browse and every series list draw `GrammarRow`. The 56 pt
  `ArtTile` and the genre's 3 pt edge on rows retire with them.
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

- **§3.1 Sections are actions** (Decision 068, owner 2026-10-24: *"we
  should focus on actions and not content type ... we should mimic the
  items from Archive Watch"*). **iPhone: five tabs, hard set, Home,
  Browse, Stations, Search, Library**, as Archive Watch's iOS-DESIGN
  §2.1 (Stations in Channels' place), with Search's
  `Tab(role: .search)` so the system places it. **Surprise** is a push
  from a toolbar button on Home (`Route.surprise`, the shuffle symbol),
  as Archive Watch's §2.6: modes are pushes on the phone. At regular
  width (iPad, the open Duo) the sidebar also lists Surprise, a `Tab`
  hidden from the tab bar (`.defaultVisibility(.hidden, for: .tabBar)`)
  and added only at regular width, so the phone's bar never grows a More
  tab; narrowing to compact width hands a selected Surprise back to Home.
  Each section owns one verb (Archive Watch §12.2): Home chosen for you,
  Browse everything by facet, Stations lean back on one clock, Search
  find, Library yours. No section is named for a content type: plays sit
  in Browse and Search beside the series, and recording is "Start an ear
  drama" on a play's page. `AppTab` (`apple/Core/Store/AppStore.swift`)
  holds the six; adding any other amends this rule first. There is no
  Settings tab or gear.
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

## §4 Surfaces

- **§4.1 Home** (was Listen) is a `List`: Continue listening (the ten most recent
  in progress), then Following (the series the person follows, newest
  follow first as the web lists them, each a `SeriesRowLabel` pushing its
  page), then the catalog's published shelves in order (R13). A section draws only
  with rows. Each episode row's context menu offers Play. The toolbar's
  one item is Surprise (a `Label` with the shuffle symbol), pushing
  §4.11.
- **§4.2 Browse** (was Series) is a `List` of radio series and stage
  plays together, under a horizontally scrolling row of capsule chips,
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
- **§4.3 A series page** carries Follow / Following as the toolbar's
  primary action (the web's verb and words; a plus, then a checkmark once
  followed), with the selection haptic on change. It writes
  `FollowedSeries`, the store the account sync carries; an unfollow is a
  marker. It shows the series' one meta line, then its
  episodes oldest first in sections by broadcast season, "Undated" last.
  The toolbar's Download menu (iPhone, iPad, Mac; never the TV) offers
  Download All Episodes, then one Download item per season when there
  is more than one, then Remove Downloads once any of the series is on
  the device. A download asks first, naming the count and, from each
  copy's bitrate and length, about how much space it takes ("Download
  52 episodes?", "About 640 MB."); an item whose episodes are all
  downloaded or downloading is disabled. Removing a series' downloads
  asks first (R17, the car and bedtime: a whole run before the trip).
- **§4.4 Episode detail** is a `List`: the series (a link), the title,
  one facts line (date, network, sponsor, length), Play or Pause, the
  download control, "Start an ear drama" when the episode's `script`
  names a bundled script (Decision 068), "Automatic transcript" when the
  gate passed, the
  credits grouped by role (each name a push to its person, §4.13), Versions when there is more than one copy,
  and the rights line. A part with no data is absent, never a
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
- **§4.6 Library** (D3-5, one grammar) is **Continue**, **Queue**, **Following**, **History**,
  Downloads, and **Ear dramas**, then the account row and the site pages. Every section keeps its
  header, so a section with rows and one without read as one set. Continue, Queue and History are
  grammar rows (`EpisodeRowLabel`, the series' window leading); **Following is show tiles** in one
  horizontal shelf (`FollowingShelf`, `ShowTile`, names sharing a height), newest follow first as
  Home's, with Unfollow on a long press; an Ear dramas row leads with its title's tile
  (`ArtTile`, as a play's row) over the production's progress line. Queue reorders (Edit,
  `onMove`), swipes to remove, and keeps its long-press menu; a Continue or History row swipes or
  long-presses to Remove from History. Downloads is one row, "Downloads" with the episode count and
  the storage held, that pushes the Downloads place (§4.8): a bulk download is hundreds of rows,
  which would bury the rest of Library. The four states: loading is the skeleton rows; an
  unreadable catalog is `CatalogUnavailableView` heading the list; offline is the app-wide
  "You are offline." line (what is on the device keeps listing); an empty section is a header and
  one caption (`SectionCaption`) that says what it would hold, never an invitation: "Episodes you stop partway through wait here." (Continue), "Episodes you add play in this order, after the one that is playing." (Queue), "Series you follow appear here." (Following), "Episodes you finish appear here, newest first." (History), "Downloaded episodes play with no network." (Downloads), "Ear dramas you record or join appear here." (Ear dramas). A
  Library with nothing in any section also heads with "Nothing played yet" and Browse (§7.4). Not
  yet seen on a device.
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
  An evening shows whenever any of its programs survives. Each row shows its local time with
  the paper's Eastern time beside it as a caption ("7:00 PM ET" alone
  where the two agree). The slot on the air says "Now" and takes the
  surface-alt row background, repainted every 15 seconds from the
  file's instants. A surviving slot is a link to its episode with a
  borderless Play that plays it from its start; a gap is muted text:
  `known_series` where the file sets it, then "Not surviving" (or "Not
  in the catalog" for a withheld slot or one the open catalog lacks),
  and its length. The newspaper's printed text is never drawn (Decision
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
  its title and author, with "Start an ear drama". Each plays or starts
  in one tap. The draw is the platform's own random: nothing needs to
  match another device. No copy is written; a pick with no data is
  absent.
- **§4.10a The site pages are Library's last section**, under the
  account: "Credits", "Privacy", "Take-down requests", each a `Link` to
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
- **§4.12 An ear drama** (`apple/Shared/PlaysScreens.swift`,
  `RecordingScreen.swift`; PLAYS-DESIGN §2, Decision 067). The play's
  page is a `List`: its title, the author with their years when the
  record has them, the record's year when present, its length as
  "N parts · N lines" (speaking parts, every line), the rights
  line, and "Start an ear drama"; nothing else marks it. The cast sheet
  lists the parts largest first; every open part has Take Part, in any
  order, and the suggested one (`Relay.next`) is `.borderedProminent`,
  the rest `.bordered`, with no caption saying why. One part records at
  a time; taking another while one records shows the refusal. At Start
  Recording a signed-out person sees "Recording needs an account." and
  the account sign-in buttons (§4.10's) in its place; taking a part,
  reading along, and listening need none. Listen Through is always
  offered: a complete play plays its rendered mix (the end marks it
  Finished); an incomplete one runs `Relay.listenPlan` live, takes from
  their files and the other speaking lines read by `AVSpeechSynthesizer`
  `speak`, the current line's speaker and words on screen, "Device
  voice" on a read line, and Stop. When Personal Voice is offered
  (authorized, or "Use my Personal Voice" asks), it reads those lines
  through `speak` only, never `write`. Export (a `ShareLink`) is there
  whenever the play is complete, and renders the mix first if it is
  missing or stale.
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

## §5 The player

- **§5.1 One engine.** `AudioPlayer` (`apple/Core/Player/AudioPlayer.swift`)
  is shared by every Apple platform: AVPlayer, the `.playback` /
  `.spokenAudio` / `.longFormAudio` session, Now Playing, and remote
  commands. Views draw it and never touch AVFoundation.
- **§5.2 The mini player** sits in each tab stack's bottom safe-area
  inset while an episode is loaded (`MiniPlayer_iOS`,
  `apple/iOS/PlayerViews_iOS.swift`): title, series, Play or Pause; a
  tap opens the player.
- **§5.3 The player is a sheet** with its drag indicator
  (`PlayerSheet_iOS`): series, title, date and network, the scrubber,
  elapsed and remaining time, back 15 s, Play, forward 30 s, then
  speed, the sleep timer, and AirPlay's own `AVRoutePickerView`
  (`RoutePicker_iOS`, labeled "AirPlay"; the `.longFormAudio` session
  routes the whole player, and Now Playing follows it). Errors
  and the offline warning sit under them, and "Next:" names what the
  queue holds. The toolbar carries Close and, when there is one, the
  transcript.
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
- **§11.5 The player is a sheet, not a full-screen cover.** Audio has no
  picture to give the whole screen, and the sheet keeps the tab behind
  it in view; the TV is the platform where Now Playing fills the screen.

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

Bring the next change back to a rule here, or bring a new rule first.
