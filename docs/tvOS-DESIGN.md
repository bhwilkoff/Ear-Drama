# Ear Drama tvOS design (binding)

**Binding.** Quote the rule number before proposing any new tab, shelf,
screen, overlay, or focus behavior on Apple TV. If no rule fits, propose
a new rule first, then the feature (`binding-design-doc-discipline`).
Companion to `PARITY.md`, `docs/CATALOG-CONTRACT.md`,
`docs/WEB-DESIGN.md`, `docs/iOS-DESIGN.md`, `docs/macOS-DESIGN.md`, and
`docs/ANDROID-DESIGN.md`. Several rules here invert the phone's on
purpose; §11 names each one.

Seeded 2026-10-22 from `docs/templates/TVOS-DESIGN-template.md`. It
describes what is built in `apple/tvOS/ContentView_tvOS.swift`, the
tvOS branch of `apple/Shared/TranscriptViews.swift`, and `apple/Core/`.
Mechanics live in `tvos-platform-patterns`; the shape of a ten-foot
Detail page in `ten-foot-detail-design`.

## §1 Principles

- **§1.1 Ten-foot first.** The app is used from a couch with the Siri
  Remote. Nothing depends on precise aim or hover.
- **§1.2 Focus does the work.** Only the focused card is bright; the
  rest stays quiet. Density comes from removing chrome.
- **§1.3 The TV is lean-back listening for a room.** It is where a
  family hears a broadcast evening, so Now Playing fills the screen with
  type: in radio, the people are the picture.
- **§1.4 Depth is at most two from a tab**: tab, series, episode. Now
  Playing and the transcript are full-screen covers, not pushes.
- **§1.5 Back is sacred.** Menu dismisses a cover and pops a stack; the
  app never intercepts it outside a cover.
- **§1.6 One shared data plane**: the same `CatalogStore` and
  `AudioPlayer` as iOS and the Mac (`docs/iOS-DESIGN.md` §2).
- **§1.7 Only essential words on screen** (AGENTS.md); no list or blurb
  written by the app (R13).

### §1.8 The shared rules as they bind the TV

The common text is in `docs/WEB-DESIGN.md` and `docs/iOS-DESIGN.md`
§1.7; the TV runs the same Core:

- **R1** every card and row leads with the date, oldest first; **R11**
  cards are typographic (date, title, series), with no placeholder; as
  amended by Decision 069, a card's series line leads with its 64 pt
  `ArtTile` (the series' star, else its letter), Detail and the series
  page put a `FaceFigure` (240 / 200 pt) beside the title, cast lines
  carry 64 pt portraits in a grid, and owed credits follow as text;
  **R11a** (owner, 2026-10-28: *"Portraits should show wherever they are useful or joyful (overall the visuals are not highlighted yet on the app)."* and *"The visual pass should be for all artwork. We want the app to be as visual as possible."*): the TV keeps its 64 pt card tiles; `FaceFigure` beside
  the title is the print at its own aspect, 300 pt tall on Detail and 250 pt
  on a series or person page (a wide picture up to 1.5 times as wide), and
  Now Playing's 400 pt bound draws a portrait whole at its own aspect, its
  box shrunk to it, its owed credit under it; nothing is drawn behind a
  picture (owner, 2026-10-28: *"I think you can find better solutions for different aspect ratios of images, then just blurring and black bars."*; `artwork-presentation-design`); the 64 pt tiles, cast
  portraits, and the system Now Playing square center on the published
  face, as iOS-DESIGN R11a (V4), a wide picture without one left
  uncropped; the Top Shelf carries faces (§9.3), handed over as a URL that
  tvOS crops itself, so a wide face there is not yet anchored; **R11b** one grammar, as iOS-DESIGN R11b (owner, 2026-10-29: *"the design is still not uniform for all different levels of content (some with images, some without, some with more information, some with less). We need to a design approach that evens out all of the inconsistencies and make the app look like one complete thought."*; `catalog-experience-design` rule 11; D3-1): the same
  `apple/Shared/Grammar.swift` components at the ten-foot sizes (a 300 pt
  tile window, 29 pt floor for the facts), and focus scales the whole
  tile (`.buttonStyle(.card)`'s lift), never the window alone; **R11f** Now Playing's people and Voices (D3-9; owner, 2026-10-30: *"It has to look good and use native design and apis on the given platform."*; the shared text, WEB-DESIGN §6.4f). Now Playing draws **On the air** (the credited performers as round faces, portrait else monogram, each opening the person) and **That night on the radio** (`CatalogDatabase.sameDay`, contract §3.3b: at most 12 other surviving broadcasts of the same air date, by network with unknown last, then series, then id; each a grammar row of show and network, Play, and a tap to the episode), each hidden when it has nothing. **Voices** is Browse's second scope (Shows, Voices, Ear dramas) and Home's "Most heard voices" rail with All: `CatalogDatabase.voices` behind a column-exists guard, round faces over the name and the episodes, each opening the person's page; a catalog without the table draws neither. Now Playing scrolls: the controls fill the first screen, the faces (`.card`) and rows follow, reached by moving focus down; Voices faces are 160 pt on `.card`. **R11c** Home and Browse as iOS-DESIGN R11c (owner, 2026-10-29: *"Having more shows is better, so 5."* and *"I like the bulky blocks and colors of The Sleeve and I like the data visualization options of the Almanac."*; D3-2): shows are series of five or more episodes; the day board's strip is not focusable and shows the peak year, and its genre legend never truncates at ten-foot size (D3-fix2: columns 270 pt wide, marks 20 pt, a name may wrap to two lines; a name is never cut to "Science..."); that night's tiles and Most downloaded are shelves of `.card` tiles; Browse keeps its Genre and Sort pickers (no new menus) and adds the count line, the field (a cell sets genre and decade, Clear resets) and the tile grid, where only the focused tile is bright; **R11d** series and episode pages in direction D, as iOS-DESIGN R11d (WEB-DESIGN §6.4d): the head board, one button row, On the air as round faces (each a focus stop), Cast and credits a focusable row that opens the list; Follow stays the series page's first focus stop and Play takes default focus on the episode page (the documented inversion), only the focused control is bright; **R12** brand is chrome only; **R13** shelves by rule.
- **R11e Browse's A to Z jump** (owner, 2026-10-30: *"We are building for each specific platform. It has to look good and use native design and apis on the given platform."*; *"Yes, add a letter jump"*): sorted A to Z, a row of letters focus can reach (`LetterRow`, its own focus section) heads the results, which are one lazy section per letter; Select scrolls to the letter. The run strip draws the histogram, 96 pt on the head board; the series page's genre is a focusable link to Browse. No recording on a TV.
- **R14** lean-back is bounded: the sleep timer ends a session, and what
  plays next is Decision 067's: a part of a story arc (contract §3.3) is followed by the arc's next part, automatically; at the arc's last part playback stops and the series' next story is offered as a "Next story" action, never started. Anything the person queued plays after an arc's last part, as after any episode. Outside an arc: one episode, then the queue, then stop. A live slot follows its clock, never an arc. The action row carries
  "Next story" (`NextStoryButton`) on an arc's last part only.
- **Queue verbs** (iOS-DESIGN §12): long-press (the context menu) an
  episode card for "Add to queue" or "Remove from queue"; Detail's
  action row carries "Add to queue" / "In queue"; Library lists the
  "Queue" first, its context menu has Move up, Move down, Remove. There
  is no drag on the TV. They only order what the person chose.
- **R15 and Decision 067**: volume leveled on the device by the shared
  `VolumeLeveler` tap (iOS-DESIGN §1.7); "Level volume" is a toggle in
  Now Playing's action row. Radio's action row carries a "Year" menu when
  the date offers other published years (Decision 067).
- **R16**: the reader's caption and every button say "Automatic
  transcript".
- **R18**: speed, sleep, and skip are on Now Playing.
- **R20**: "End of this episode" first, then 15, 30, 45 minutes, 1 hour;
  it fades, and once fired nothing starts until Play.
- **The rights line** is the projection's words; unclaimed reads "No
  rights claim known. Removed on request."
- **Downloads are n/a**: the TV has no durable storage for media, and
  Library says nothing about it (owner 2026-10-28: "No need for downloads
  on tv"). A sentence on screen is for a capability a device lacks for now;
  one it can never have is n/a and silent.

## §2 Information architecture

- **§2.1 Four sidebar entries, hard set** (Decision 075, owner
  2026-11-14; Decision 075's five less Record): Home, Browse, Search,
  Library, in a `TabView` with `.sidebarAdaptable`; Search uses
  `Tab(role: .search)`. **Record is n/a on the TV**: it has no microphone
  and records nothing (PLAYS-DESIGN §6, §11.7 rule 12), so there is no
  Record entry, no Record a Play door or row, no Today's play, no Try a
  Line, and no Record This (Today's Scene is on Home, to hear); Browse, Search, and Surprise show no plays. Library keeps
  the shared Ear dramas this person is in, to listen to (§4.12): that is
  all "making" means on a TV. **Home opens on what is on the air**: its
  hero is On the air (tonight's slot on now, else the first genre station
  with a playable slot), with **Listen Live** as the default focus, then
  **All Stations** (pushes Stations, §4.8, the TV's most natural place
  to lean back) and **Surprise** (pushes §4.10) in the same action row;
  then Continue, two doors as wide cards (Listen, Find a Show; the third,
  Record a Play, is absent), Start a Show, **Today's Scene**, By Length,
  This Day in Radio, and Most Heard Voices as shelves (the web's §4.2
  rules, the TV's idiom). Neither Stations nor Surprise is a sidebar entry.
  - **Today's Scene on the TV** (Decision 079: "Today's scene ... replaces
    Today's play on every platform"; the TV never had Today's play): the
    same pick as every platform (`PlayScript.todaysScene`, golden
    `todays_play.json` `scene`), one wide card in its own focus section:
    the kicker, the title, author · N voices · About M min, and the opening
    as a page (the first four speeches, the role name in the part's hue
    over the said words, 29 pt or larger, two lines each at most), then
    **Hear It** alone: the opening read live by the device's voices through
    the play's one cast, lighting the speech being read, becoming Stop,
    pausing the player first, stopping when Home leaves, keeping nothing.
    No **Try a Line** (the TV has no microphone and records nothing,
    PLAYS-DESIGN §6) and no **Read** (§4.13, Decision 076: no Read door on
    a TV). The card is a listening invitation; focus lands on Hear It.
  - *Replaced* (2026-11-14, Decision 075): "Six sidebar entries, hard set
    (Decision 068 ...): Home, Browse, Stations, Search, Library, Surprise
    ... Stations is the TV's most natural entry ("Tonight in 1942", §4.8)".
  - *Replaced*: "... and Library no Ear dramas."
  - *Replaced*: "Five tabs, hard set: Listen, Series, Radio, Library,
    Search ... No Plays tab."
- **§2.2 Leaving a tab resets its stack** (`AppStore.selectResettingPrevious`):
  stale push state must not greet the next visit (§11.4).
- **§2.3 Its own destination registry.** `RouteDestinations_tvOS`
  resolves `Route.series` and `Route.episode` to the TV's own screens;
  the phone's list screens are never shown here.
- **§2.4 Everything external lands in the inbox**, drained by `RootView`.

## §3 Surface taxonomy

The only shapes; a new one needs a new rule.

**§3.0 The living room, not a resized iPad** (owner, 2026-11-04: the Apple TV app "has many glaring design issues"; two audits passed them because they checked function, not design). Binding on every screen, and it replaces any older line below that disagrees. Judge a frame as a person on a sofa: hierarchy at ten feet, pictures leading, one margin, no truncation of what matters.

- **One margin.** The system's safe area (80 pt on the set) is the only left and right margin: no screen adds padding of its own, and a `List` (which adds 20 more) never draws a page. Shelves scroll to the screen's edge past it.
- **No `List`, no chevron, no full-width bar.** Pages are a `ScrollView` of a hero and shelves (`apple/tvOS/TenFoot_tvOS.swift`). Buttons are the system's, at their natural width.
- **The hero (`TVHero`) heads Home, a series, an episode, a person, Surprise and Now Playing:** a board in the genre hue, edge to edge and up to the top of the screen, the words at the margin (kicker, name at L1, what it is, event line, one row of actions), the picture at the right. It replaces `HeadBoard` on the TV. The window takes the largest side its picture holds up at (`Grammar.windowFill`'s floor), up to 460 pt, so a picture is never lost to a slot too big for it. A window of 300 pt or more with no picture is a tonal letter, filled, never a hairline outline.
- **Two cards.** The wide card (`TVWideCard`, 640 by 236, `.card`): the window, then a line, the title, a line, on its board. It carries Continue, Queue, stations, an evening's slots, search hits. The date card (`TVDateCard`, 420 by 236, `.card`): the date in display type, the title, the length, on the show's board, for a list of one show, where the window would repeat. A row of cards is one height, always.
- **A person is a round face (`TVFace`) with no plate:** focus lifts the circle and rings it; the name holds two lines and the count one, so every face sits on one grid. `.card` is for rectangles.
- **Color.** The TV takes no tint (`.tint(nil)` on the tab view and the player): a tint colors a focused button's label too, so a light one is white on the system's white plate, which is how Play, Resume and Pause first reached the set. At rest the system's quiet plate, focused the system's plate, which is glass and takes a little of the board behind it. A button's label carries no `foregroundStyle` of its own, or it cannot invert on focus. Blue is for nothing on this screen but the tab bar's selection (the remote has no links), so §7.2 no longer tints labels. Ink plays; a hue is a board.
- **Focus always shows.** `.borderless` lights only an image, so text or shapes under it take focus with nothing on screen. Anything with no plate of its own (a field's cell, a letter) wears `TVFocusRing` under `TVBareButtonStyle`.
- **Page order: pictures before charts.** A chart (the day strip, the field) never opens a page. Home's strip follows the shows of that night; Browse's field opens from "By decade" and its tiles are the first thing under the filters.

- *Replaced* §3.2's 420 by 236 typographic card with date, title, series as the only card; §3.3's native `List`s; §4.3's series page; §4.6's Library as a list; R11c's day board at the head of Home; R11d's "Follow stays the series page's first focus stop".

- **§3.1 Shelf**: a section title over a horizontal `LazyHStack` of
  cards, in a `.focusSection()`, with `scrollClipDisabled()` so the
  focused card's lift is not clipped (`ShelfRow_tvOS`).
- **§3.2 Card**: `EpisodeCard_tvOS`, 420 by 236, `.buttonStyle(.card)`,
  date, title (up to three lines), and series.
- **§3.3 List**: series browse, a series page, search, and Library are
  native `List`s, whose rows the focus engine already lights.
- **§3.4 Detail**: a scroll view of the header, an action row, the
  credits, and the rights line (§4.4).
- **§3.5 Full-screen cover**: Now Playing and the transcript reader only.

## §4 Surfaces

- **§4.1 Home** (was Listen) opens on the hero, filled by a stated rule: the episode the person
  is partway through, Resume first, else this day in radio's busiest year, its first show with a
  picture, Play first. Under it the rest of Continue listening (up to nine), Following, that night's
  shows as tiles, the day strip with its legend on one line, Most downloaded, Most heard voices, New
  ear dramas. A shelf of nothing draws nothing, so one episode in progress is the hero, not a lone
  card beside an empty screen.
- **§4.1r Home reads as one thing at ten feet** (Decision 081, owner 2026-11-19: *"the home screen ... still reads like a long list of items that feel unrelated ... The goal is to have the home view feel more cohesive and inviting from the moment that you open the app."*; rulings: "Home: all of R3a §4.1", "label art C on every platform"). The shared rules are WEB-DESIGN §4.2r
  1-8. This doc keeps its own idiom and states the **deliberate differences**: focus does the work,
  so only the focused object is bright and the label never gains a ring, shadow or lift a picture
  would not; the hero is the ten-foot scene (`ten-foot-detail-design` §1): when something is on the
  air it leads, its picture or its tier-L label filling the art area on a full-bleed dark board,
  the title in its own slot at the left, Listen live the first focus stop (otherwise §4.1's hero
  rule stands); the dial of genre stations is one focus row of S-tier labels directly under the
  hero; there are no doors (the tab bar navigates and the TV records nothing). A show at most once
  per Home and one window size per row hold as on every platform; the rim (network · decade) reads
  at the hero's size. Built in Round 3 V6.
- **§4.2 Browse** (was Series) is Shows, Voices and Ear dramas at natural width, then one line: the
  count, then Genre and Sort as menus (Popular by default, A to Z, Most episodes, Oldest first;
  Popular as `docs/iOS-DESIGN.md` §4.2), By decade and the singles switch; then the tiles. The tab
  bar names the section, so the screen draws no title, as every tvOS tab. In A to Z a letter starts
  the list at that letter and the row marks which: scroll on the TV follows focus, so a `scrollTo`
  is undone at once, and a letter's tiles may not be drawn to take focus.
- **§4.3g Item pages wear Home's hero at ten feet** (Decision 081, Round 3 V7; owner, 2026-11-19: *"We need to continue making the app more visually appealing, both from the home screen perspective ... and the individual item perspective."* Shared rules: WEB-DESIGN §6.4g). `TVHero`
  already heads Home, a series, an episode and a person; V7 changes what its window holds: a picture at its own shape, never
  cropped (460 pt tall, up to 760 wide, so a wide photo is a plate that fills its window, not a small print inside a square), the
  label otherwise (round for a person, the show's run and network for a series), and an episode's own dated label with the show's
  year at full ink on the strip, the show card under the buttons carrying the show's picture. Focus does the work: the hero's
  buttons are in the first screen (window 460 plus the margin is under 1080 pt), so focus moving to them scrolls nothing; no
  picture, credit or label takes focus. A series' gallery and a play's page are not drawn on the TV (no Read door on a TV).
- **§4.3 A series page** is the hero (genre and at most two networks, the name, the years and
  count and "With" the show's star, the run strip on the show's own years), then Play (the first focus stop: the episode in
  progress as Resume, else the first episode), Follow / Following (`FollowedSeries`, synced) and the
  genre, a link to Browse; then **About** when the catalog publishes `series.about_text` (owner,
  2026-11-09): one focusable card of its first three lines that opens the whole text full screen,
  each paragraph a focus stop as in the transcript reader (§4.7), Menu to close; under the card the
  source as words ("From Wikipedia", required by CC BY-SA 4.0), never a link (no browser). No text,
  no card. Then a shelf of date cards per broadcast season, oldest first, "Undated"
  last, so down moves season to season and across moves through one.
- **§4.4 Episode detail** (`EpisodeScreen_tvOS`) is the series name as the kicker, the
  title at page-title size, the facts line (date, network, sponsor,
  length), then an action row in one focus section: Play, Add to queue, and
  "Automatic transcript" when the gate passed. Under the hero, its own focus section, **the
  show**: a wide card with the show's picture, genre and network, name, years, episode count and
  star, opening the series page (owner, 2026-11-09: episodes felt "totally disconnected from any
  recurring show"; it replaced a "Show" button that named nothing). Then the offline warning,
  the credits by role (one focus section; every credited name is a focus
  stop that pushes its person, §4.11), Versions when there is more than one copy (R5),
  and the rights line, except unclaimed, every show's default, which is not drawn (owner,
  2026-11-09). "Read the script" is not on the TV: there is no browser, and a script is read
  on the phone (PARITY n/a). Versions is its own focus section of buttons, the
  rank 0 copy first and the default; each is named by `recordings.label`, else by its notes,
  bit rate and length (never "Recording 2", never the identifier), and plays that copy in Now
  Playing. Play on the episode already loaded opens Now Playing where
  it is, never from the start (§5.4).
- **§4.5 Search** is `.searchable` with the prompt "Titles, series,
  people", series first, then People (§4.11), then "Aired {date}" when
  the query names an air date, then episodes, then **Automatic
  transcript**: each row the episode row plus the line where the words
  are said, verbatim (iOS-DESIGN §4.5).
- **§4.6 Library** (direction B, owner 2026-11-23: *"Most people we exclusively use this app for listening, so let's do option B ..."*; replaces D3-5 and its rule that every section keeps its header and caption) is **Listening only** on a TV, as focus shelves: **Up next** (the started episodes, then the queue in order, each once; a held Select offers Remove from History or the queue menu) and **Shows you follow** (the grammar's show tiles through `.card`), then, signed in and only when there are some, **Ear dramas** (the shared productions this person is in, newest first, to listen to: §4.12), then the foot headed "Account and preferences": **Account** (§4.9), **Show a Reading** (§4.13), **About Ear Drama** (the site's pages as addresses, §4.9a). There is no Making side, no Voices, no Export, no History or Downloads on a TV. Shared ear dramas stay listed (restored 2026-11-23, owner: they are listening content; Decision 087 item 4 stands); the TV still records and edits nothing. An empty shelf is absent, no header and no caption; a Library with nothing heads with "Nothing played yet" and Browse (§7.3a). Not yet seen on a TV.
- **§4.9 The account** is the foot of Library, as on iOS
  (`docs/iOS-DESIGN.md` §4.10), never a tab and never at first launch.
  The row pushes `AccountScreen_tvOS`: signed out, Sign in with Apple
  only; signed in, the provider, Last sync, the last error, Sync Now,
  Sign Out, and Delete Account behind a confirmation. Sign in with
  Google is not on the TV yet: `ASWebAuthenticationSession` does not
  exist on tvOS, and the TV's Google path is a phone hand-off (a code on
  screen, approved on the phone) that waits on its own rule.
- **§4.9a The site pages** are three plain rows under Library's Account
  row: "Credits", "Privacy", "Take-down requests", each with its
  address (`eardrama.org/credits`) as the value. A TV has no browser, so
  the address is the whole control; the rows are not links.
- **§4.7 The transcript reader** (`TranscriptScreen_tvOS`) is full
  screen: the episode title, the caption "Automatic transcript", then
  the text in paragraphs of four sentences, each a focus stop, so the
  remote scrolls the text a few sentences at a time and only the
  focused paragraph is bright. Menu closes it.

- **D3-8** (D3-8, 2026-10-30) Stations, Surprise, Search's people and a person's page follow WEB-DESIGN §6.4f in this platform's idiom: each station is a `ShowTile` on its genre's board under the card style (a focus stop; "Listening live" is a fact line), slots are `GrammarRow`s with "Now" in ink, Surprise's episode and evening are head boards with Play as the default focus, and its play is a `ShowTile` with the cast fingerprint that takes no focus (the TV records nothing). A person is a head board, a shelf of `ShowTile`s, then rows.
- **§4.8a Stations at ten feet** (2026-11-04; replaces what disagrees in §4.8): stations are wide cards of one height. "Tonight in 19xx" is said once, by the first card; the evening under them is headed by its date, with the network, station and Year menu on that line. The evening is one shelf of wide cards in time order, each slot's time first ("7:00 PM"), the paper's own time in words at its foot ("Aired 9:00 PM ET"). A run of dead slots is one narrow quiet card that opens in place; surviving broadcasts lead the eye. The Year menu names a date where two evenings share a year.
- **§4.8 Stations** (`RadioScreen_tvOS`, `apple/tvOS/RadioScreen_tvOS.swift`)
  is the web's §4.9 at ten feet. It opens on the stations shelf
  (`StationsShelf_tvOS`), one horizontal focus section of `.card` buttons,
  Tonight in 19xx first and then each genre station, the first focused by
  default and only the focused card lifted: each card reads the station's
  name, what is on now (series, then title), and "Listen live" ("Listening
  live" while on; Tonight's says "Starts at" or "Ended at" outside the
  evening). Pressing a card listens live and opens Now Playing; pressing the
  one on the air pauses and stops. Then "Tonight in 1942" at page-title size,
  the evening's date, the network and station, and the Year menu in its own
  focus section when the date offers other years. Then every slot in one focus
  section, each a focus stop so the remote scrolls the whole evening
  and only the focused row is bright: a surviving slot opens its
  episode's Detail (Play lives there, §4.4); a gap is a focusable row
  that reads its time, `known_series` where set, "Not surviving" or
  "Not in the catalog", and its length, never the paper's printed
  text. Each row's time is local, with the Eastern time beside it where
  the two differ. Listen live opens Now Playing full screen (§11.1) and
  plays through the shared `LiveRadio`: a pause, another episode, the
  sleep timer, or the evening's end stops it, and nothing plays after
  (R14). The listing's credit is a caption, not a link: the TV opens no
  web page. The empty and error states are iOS's words
  (`docs/iOS-DESIGN.md` §4.9).

- **§4.10 Surprise** (`SurpriseScreen_tvOS`) is drawn when it opens: an
  episode as the hero with Play (the default focus, as on Detail), Details
  and Shuffle, then one shelf of wide cards: the evening, the play, three
  more episodes (`docs/iOS-DESIGN.md` §4.11), so the row is never one card
  beside an empty screen.

- **§4.12 Shared ear dramas** (PLAYS-DESIGN §11.7 rule 12, binding:
  "Apple TV plays back ... Nothing is claimed, recorded, uploaded, invited,
  or published there"). Signed in, Library gains an **Ear dramas** shelf
  after Shows you follow, above the foot: each shared production by title, newest first
  (`SharedEarDramasSection_tvOS`); loading and empty draw nothing (an empty section is absent, Decision 087), an error or offline is its one line
  with Try Again. Signed out the section is absent. A row pushes
  `SharedPlayScreen_tvOS`, a `List`: the title at page-title size, then
  **Listen Through** (the default focus), which fetches the chosen takes
  into `Caches/SharedPlays/<pid>/` and runs phase 1's listen plan
  (`SharedListen.plan`), the line being heard under it with its speaker and
  "Device voice" when the device reads it; "N takes are hidden from you.";
  then Parts (each with its state and performer) and People ("You" and
  "Director" tags; **Report** with a reason dialog and **Block** after "You
  will no longer hear their takes." for everyone else), each a focus
  section. Returning to the app re-reads the record unless it is playing.

- **§4.11 A person** (`PersonScreen_tvOS`, `withPerson`) is the hero: the
  round portrait, the name, the facts line (the years from the people row,
  the episode count, the shows), the run strip; then one button naming the
  order, Oldest first or Newest first, which flips it (shown only with more
  than one episode). Then the Shows shelf, most episodes first, so the show a
  person is known for leads; then a shelf per series of date cards, each naming
  the roles it credits the person in. Focus lands on the order button or the
  first card, never the heading. No bio is written (R13). Back pops to Detail
  or Search (§1.5).

- **§4.13 Scripts on the TV: a read-along panel only** (Decision 076: "TVs get a
  read-along panel only"; PLAYS-DESIGN §2.7 is the reader everywhere else). No
  Read door, no pages, no contents, no search, no marks, no recording. When a
  production's Listen Through plays (§4.12), and later an episode whose script we
  may show, a panel under the transport shows the current line with one before
  and one after, at 29 pt or larger (the body floor), the speaker's name in the
  part's hue, "Device voice" beside a line the device reads. It follows the
  audio by line id (the same `follow(line)` seam as the readers) and never takes
  focus: focus stays on the transport. No word mark and no speed control on the TV (PLAYS-DESIGN §2.11
  rule 10, 2026-11-23): the listen-through and a drama's files play at the device's remembered read-along speed
  (`ReadAlong.savedSpeed()`, 1× until a speed is chosen on this device, which the TV cannot do yet). Built 2026-11-15 as PLAYS-DESIGN §2.11 rule 10: `ReadAlongPanel` in the Listen Through screen; the line comes from the listen plan, 31 pt body, inside the 5% safe area.
  **No studio** (PLAYS-DESIGN §2.9): the TV records nothing, so the reader's
  studio, take lists and Record never appear here. **No marks** (PLAYS-DESIGN
  §2.10): marks are made where there is a selection, a keyboard or a pencil, and
  are private to the device that made them; the read-along panel draws none.
  A **finished ear drama's** Listen (the shared `FinishedDramaScreen`) shows the same panel
  under the transport while its line files play, the file playing being the line heard
  (PLAYS-DESIGN §2.11 rule 11); a recording with no line timeline plays with no panel.
  The listen-through on the TV reads open parts with the device's cast (PLAYS-DESIGN
  §2.8, Decision 076 S2): the same `VoiceCast` auto-cast from the TV's own voices,
  kept in `UserDefaults` (never Application Support, which tvOS devices refuse); the TV has no picker (the cast is changed on a
  phone, tablet or Mac, and each device keeps its own). Built 2026-11-14: the shared
  play's Listen Through sets `VoiceCast.production(rec.id, script:)` on its speaker
  before the run; build-verified only (no TV pass this round).
  **The shared screen of a read room** (Decision 082, PLAYS-DESIGN §12.2; added
  2026-11-19, not built: Round 3 T4). **Show a reading** (in Library, beside Listen
  together) shows a short pairing code at 76 pt or larger; the teacher or host types it
  on their own device, so the TV never asks for typing (the Jackbox direction of entry).
  Paired, the TV joins the room as its screen and the same panel is driven by the
  **room's cursor** instead of the audio: the current line with one before and two
  after, speaker names in part hues, 29 pt or larger, and in a corner the room code and
  how many are here (a fact). When the leader turns on **Read open parts**, the TV
  speaks an unheld line with the device cast, never during a take. The TV records
  nothing, holds no part, never leads, and takes no focus from the panel but one
  **Leave** button. (T4, 2026-11-19: built as `ReadScreenHost`, joined by `eardrama://read/CODE?screen` or the debug door. **T5, 2026-11-19, built**: **Show a Reading** is a row in Library under the shared ear dramas (`ReadPairHost`). It asks `POST /v1/read/pair` and shows the code at 112 pt (the floor is 76), split 3 + 3, with the one line "On the leader\u2019s device: Reading, then Add a Screen."; it asks `GET /v1/read/pair/{code}` every 2 seconds; an expired code (10 minutes) is replaced at once without a word; when a leader attaches it, the TV adopts the answer (the room's snapshot and the TV's member key) and becomes that room's screen (`ReadScreenBody`), past a lock. The leader's side is the Reading menu's Add a Screen on iPhone, iPad and Mac. When the leader turns on Read Open Parts and the snapshot says nobody holds the cursor's speech line, the screen reads it with the device voice live (`ScreenSpeaker`, never stored) and stops the moment the cursor moves. The TV records nothing and keeps nothing at rest (the pairing code and key live in memory only; no Application Support). **Not built**: a Leave button (Menu returns), and no TV pass this round (build-verified and rendered at 1920 by 1080 on the Mac only).) A dropped socket falls back to polling silently; the panel says
  "Slow connection" only past 2 s (a warning). "Waiting for Ms. Ortiz" appears when a
  class's leader is away (the room holds still).

## §5 The player

- **§5.1 One engine**, the shared `AudioPlayer`, with the `.playback`
  and `.spokenAudio` session and remote commands as on iOS
  (`docs/iOS-DESIGN.md` §5.1, §5.4, §5.5).
- **§5.2a Now Playing at ten feet** (2026-11-04; replaces what disagrees in §5.2): the hero with the show as its kicker and no actions, then the progress line, then one row: back 15, Pause, forward 30, three identical round buttons, and the options at one height to their right. Focus opens on Pause. The output picker is light on the dark page.
- **§5.2 Now Playing is full screen** (`NowPlaying_tvOS`): the episode's
  picture at 400 pt (D3-4: the grammar's `PictureWindow`, the show's
  picture, else its star's, else the title block, Decision 069), then the
  title at page-title size over an `EventLine` (show, date, network); a
  progress bar with elapsed and remaining time; back 15 s, Play,
  forward 30 s, speed, the sleep timer, the system's audio output
  picker (`AVRoutePickerView`, `RoutePicker_tvOS`: the TV's own speakers,
  a HomePod, or another AirPlay speaker), and the transcript, in one
  focus section. Play/Pause on the remote toggles from anywhere on the
  screen (`onPlayPauseCommand`). Menu dismisses it.
- **§5.3 Seeking is by skip.** tvOS has no `Slider`, so the progress bar
  is a readout and the skip buttons move the position.
- **§5.4 No mini player; one way back.** The TV is one thing at a time;
  the shell shows the content and Now Playing is the player. While an
  episode is loaded, every tab's root screen is headed by one Now
  Playing button (`NowPlayingEntry_tvOS`: the word, the title, and the
  series), its own focus section, one press up from the first row. It
  opens Now Playing on the episode as it is, never replaying it. Pushed
  screens do not carry it: Menu returns to the root, where it is. (A
  sidebar footer would hold it in one place, but
  `tabViewSidebarFooter` starts at tvOS 27, above the tvOS 26 floor.)

- **§5.5 Listen Together is SharePlay**, as `docs/iOS-DESIGN.md` §5.8,
  with one difference: tvOS has no `GroupActivitySharingController`, so
  the TV cannot place a call. The SharePlay control appears in Now
  Playing's focus section only while a FaceTime call is live
  (`GroupStateObserver`); outside one there is no control that cannot
  work. A following member's skip and speed are disabled (Play and Pause
  stay theirs, a hold that catches up on play, Decision 067), with "The
  host has the controls." under them.

## §6 Focus contract

- **§6.1 The unbreakable rules**: dark-first, the 29 pt body floor, the
  90 by 60 safe area (every screen pads 90 horizontally and 60
  vertically), Back sacred, everything reachable, **never
  `.buttonStyle(.plain)`** (it destroys focusability; cards are `.card`).
- **§6.2 Detail focuses Play.** `defaultFocus($playFocused, true)` puts
  focus on Play when Detail opens, and Play opens Now Playing full
  screen. This is the deliberate inverse of iOS, which never moves focus
  or opens a surface on its own (`docs/iOS-DESIGN.md` §11.1).
- **§6.3 Each shelf and each action row is a `.focusSection()`**, so
  moving down lands in the next row rather than the nearest frame.
- **§6.4 A held Select is a row's second verb** (`.contextMenu`): Remove
  from History in Library. Android TV spells it a long press, Roku `*`.

## §7 Type, color, and accessibility

- **§7.1 Six levels** (`TypeRamp`, tvOS branch of
  `apple/Core/Design.swift`) over the system's ten-foot text styles
  (the page title and section header in the bundled Big Shoulders Bold
  at those styles' sizes, Decision 060),
  none below the 29 pt body floor: the caption level (L5) maps to the
  tvOS body style there and is set apart by its muted color, so the
  rights line, meta lines, time labels, and the transcript's caption
  are at least 29 pt. `tools/test_design_tokens.mjs` fails on a tvOS
  style under 29 pt.
- **§7.2 Tokens only**, the same generated colors as every Apple
  platform; only the focused element is bright. Roles are
  iOS-DESIGN §6.1a's (Decision 064): ink
  (`brandPrimary`) on the progress line, the buttons the system's (§3.0), red
  only for recording (the TV records nothing, so it shows none), and a
  genre hue only as the
  series row's mark. Focus itself stays the system's lift and
  highlight (§6.1); the tint does not repaint it.
- **§7.3 States.** Loading is a `ProgressView`; empty is `EmptyState`
  (§7.3a; "Nothing to list yet", "Nothing played yet"); a catalog that cannot open is `CatalogUnavailableView` with
  Try Again; the transcript reader has loading, failed, and offline,
  each with Try Again. Offline is iOS §7.2 minus downloads (the TV never
  downloads): `OfflineLine` ("You are offline.", neutral, never
  focusable) heads every tab's root above the Now Playing entry, the
  catalog already on the box keeps working, Detail and Now Playing carry
  the refusal, and a network failure is the player's line "You are
  offline.". The Siri Remote has no haptics.
- **§7.3a One empty state, and the focus lands on its action.** iOS
  §7.4's `EmptyState` (AGENTS.md: "Only essential words on screen. A
  caption must be a refusal, a warning, or a fact the person cannot
  discover by looking."): the fact and at most one action, which takes
  the focus through `.defaultFocus` (`tvos-platform-patterns`: declared,
  never `onAppear`). An empty Library is "Nothing played yet" with
  Browse (it selects Browse and resets Library's stack, §3), heading the
  list, with Account, the three site addresses, and the downloads line
  still under it. Tonight that could not load takes the focus on Try
  Again. No results echo the query and take no focus from the keyboard.
- **§7.3b No hints**, as iOS §7.5: the remote's buttons are the
  system's, and a banner on a ten-foot screen would sit in the focus
  path. No dismissal store, no reset.
- **§7.4 VoiceOver.** Each card reads as one element; the Detail and Now
  Playing headers are combined; every control carries a label.

- **§7.r The label is the default art** (Decision 081; the shared rule is WEB-DESIGN §6.4r, R3a
  §3.4). Wherever this doc names the typographic card, the title block or the initial as the art
  of something without a picture, that art is now **the label**: a flat transcription disc drawn
  natively (SwiftUI `Canvas`) from the same `labelSpec` goldens as the web (`cross-platform-determinism`):
  genre board, a run arc on the 1930-1962 dial, the monogram or the episode's date on the label,
  network · decade on the rim at tier L from `series.network`; a finished ear drama's part-hue rim;
  a person's groove ring; a play's script page with voice-band rules. A picture that passes the
  size floor always wins, and the two never share an object's slot. Networks and sponsors are names
  in our type, never logos; user-made ear dramas never take an uploaded picture. The ten-foot hero draws it at full size; Top Shelf uses the rendered label. Built in
  Round 3 V4.

## §8 Values

The rights line, the transcript label, and volume leveling are as in
§1.8, never reworded. Share on the TV is a QR code when that row lands
(PARITY §5).

## §9 Parity and what is planned here

- **§9.1** Update `PARITY.md` in the same change set; build iOS and the
  Mac after any Core change.
- **§9.2 Planned for the TV**: the layered parallax icon (waits on the
  palette and the icon, M0) and Stations' guide. SharePlay landed (§5.5).
- **§9.3 Top Shelf** (`EarDramaTopShelf`, sectioned): the person's Continue
  items, up to ten in Home's order, one line each (series, then episode),
  Play and select open `eardrama://episode/{id}`. The app writes
  `topshelf.json` into the App Group `group.app.eardrama` (the only place
  besides Caches tvOS can write; §10.1) whenever the history changes; the
  extension reads it and has no catalog or network. Each item wears the
  face its Detail draws (`EpisodeDetail.starFace`), else the series' face.
  The shelf cannot draw a caption, so a portrait whose license asks for a
  credit rides it only as the Detail face: select (and Play) opens that
  Detail, which shows the portrait with its credit on its first screen, one
  select away, the attribution "reasonable to the medium" CC BY and BY-SA
  ask for. A credited series face that Detail does not show stays off: no
  artwork rather than a stand-in. Square shape, the 500 step. Nothing in progress returns nil, so tvOS
  keeps the static image. The App ID needs the App Group capability before a
  device build signs (`docs/runbooks/tvos-top-shelf-setup.md`).

## §10 Traps this codebase has already paid for

- **§10.1 Writable directories are Caches and the App Group only**; the
  simulator lets Application Support writes through and a device does
  not (`tvos-platform-patterns`). This is one reason downloads are n/a.
- **§10.2 `.plain` kills focus** (§6.1).
- **§10.3 A shelf without `scrollClipDisabled()` clips the focused
  card's lift.**

**R14 Dates and recordings never show raw archive text** (owner, 2026-10-31: *"We want to be both unambiguous and well designed. Spelling out the month (or abbreviating it for space) is far better."*; AGENTS.md: raw upload text never shows). `AirDate.medium` is the one formatter for cards and rows ("Sep 17, 1949", "Sep 1949", "1949"); `AirDate.display` the long form for Detail. The Recordings section names each copy with `RecordingLabel` (`recordings.label` behind a column-exists guard, else "Recording N", best copy marked); the archive.org identifier never renders. `AirDateTests` holds both rules.

## §11 Deliberate inversions

- **§11.1 Detail focuses Play and Play opens Now Playing** (§6.2), and
  Stations focuses Listen live, which opens Now Playing (§4.8). iOS, the
  Mac, and Android leave the person where they are.
- **§11.2 `.card`, never `.plain`.** On iOS `.plain` is correct.
- **§11.3 Now Playing fills the screen.** The phone uses a sheet, the
  Mac a transport bar, Android a bottom sheet.
- **§11.4 Leaving a tab resets its stack.** The phone keeps each stack.
- **§11.5 The transcript is a focus-scrolled reader in paragraphs**;
  elsewhere it is selectable text a sentence a line.
- **§11.6 Seeking is by skip only** (§5.3); every other platform has a
  scrubber.

## §12 Open (what the code does not yet meet)

- **Focus is claimed by `defaultFocus` alone**, which the template's §6.2
  calls unreliable on tvOS; pressed on the set 2026-11-04 it held on every page.
- **Series browse has only a Genre facet**, no network or decade
  (`SeriesBrowseScreen_tvOS` passes `network: nil, decade: nil`).
- **Library has no Played section**, and Remove from History does not
  ask first, so focus is left to the engine afterward (§6.4).
- **Search has no loading state** (`SearchScreen_tvOS`).
- **Every shared-Core item in `docs/iOS-DESIGN.md` §12** holds here too:
  the queue rule, the resume and "played" windows, the untitled
  fallback, and seasons as sections. The player's numbers are Decision
  062's, named once in `PlayerNumbers` (`docs/iOS-DESIGN.md` §5.7).
- **Share is not built**: §8's QR code of the https twin
  (`SiteLinks.episode`) waits on its PARITY row.

Closed 2026-10-23: a way back to Now Playing (§5.4), Versions on Detail
(§4.4), and the 29 pt caption floor (§7.1).

**E1 rules (2026-10-30, D4 review).** The player row carries Add to queue (`player-queue`). Share is deliberately absent: tvOS has no share sheet. Export is absent for the same reason (docs/EXPORT.md); the data exports from a phone. Stations after the evening ends: the Tonight card reads "Ended at ..." and "Replay from the start", and pressing it plays the first playable slot and opens Now Playing.

Bring the next change back to a rule here, or bring a new rule first.
