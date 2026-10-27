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
  carry 64 pt portraits in a grid, and owed credits follow as text; **R12** brand is chrome only; **R13** shelves by rule.
- **R14** lean-back is bounded: the sleep timer ends a session, and what
  plays next is Decision 067's: a part of a story arc (contract §3.3) is followed by the arc's next part, automatically; at the arc's last part playback stops and the series' next story is offered as a "Next story" action, never started. Anything the person queued plays after an arc's last part, as after any episode. Outside an arc: one episode, then the queue, then stop. A live slot follows its clock, never an arc. The action row carries
  "Next story" (`NextStoryButton`) on an arc's last part only.
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
- **Downloads are n/a**: the TV has no durable storage for media.
  Library's last line says so, in the muted color and never focused:
  "Downloads are on iPhone, iPad, and Mac."
  (the parity rule: a missing capability is a sentence on screen).

## §2 Information architecture

- **§2.1 Six sidebar entries, hard set** (Decision 068: sections are
  actions, as Archive Watch's tvOS-DESIGN §2.2): Home, Browse, Stations,
  Search, Library, Surprise, in a `TabView` with `.sidebarAdaptable`;
  Search uses `Tab(role: .search)`. Stations is the TV's most natural
  entry ("Tonight in 1942", §4.8). Surprise is the phone's
  (`docs/iOS-DESIGN.md` §4.11) without the play: the TV records nothing
  (PLAYS-DESIGN §6), so Browse, Search, and Surprise show no plays and
  Library no Ear dramas.
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

- **§4.1 Home** (was Listen) is Continue listening as the first shelf (up to ten),
  then the catalog's `meta.listenShelves` in order (contract §5.1;
  `docs/iOS-DESIGN.md` R13): "This day in radio", then a shelf per
  published genre.
- **§4.2 Browse** (was Series) is a `List` of series led by a Genre
  picker and a Sort picker (Popular by default, A to Z, Most episodes,
  Oldest first; Popular as `docs/iOS-DESIGN.md` §4.2). The tab bar names
  the section, so the screen draws no title, as every tvOS tab.
- **§4.3 A series page** is the series name and meta line (not
  focusable), then episodes oldest first in sections by broadcast
  season, "Undated" last.
- **§4.4 Episode detail** (`EpisodeScreen_tvOS`) is the series, the
  title at page-title size, the facts line (date, network, sponsor,
  length), then an action row in one focus section: Play, Series, and
  "Automatic transcript" when the gate passed. Then the offline warning,
  the credits by role (one focus section; every credited name is a focus
  stop that pushes its person, §4.11), Versions when there is more than one copy (R5),
  and the rights line. Versions is its own focus section of buttons, the
  rank 0 copy first and the default; each names its archive.org
  identifier, notes, length, and bit rate, and plays that copy in Now
  Playing. Play on the episode already loaded opens Now Playing where
  it is, never from the start (§5.4).
- **§4.5 Search** is `.searchable` with the prompt "Titles, series,
  people", series first, then People (§4.11), then episodes, with "In the transcript" on a
  row found only by its transcript.
- **§4.6 Library** is In progress. A held Select on a row offers Remove
  from History. Its last row is "Account" (§4.9).
- **§4.9 The account** is the foot of Library, as on iOS
  (`docs/iOS-DESIGN.md` §4.10), never a tab and never at first launch.
  The row pushes `AccountScreen_tvOS`: signed out, Sign in with Apple
  only; signed in, the provider, Last sync, the last error, Sync Now,
  Sign Out, and Delete Account behind a confirmation. Sign in with
  Google is not on the TV yet: `ASWebAuthenticationSession` does not
  exist on tvOS, and the TV's Google path is a phone hand-off (a code on
  screen, approved on the phone) that waits on its own rule.
- **§4.7 The transcript reader** (`TranscriptScreen_tvOS`) is full
  screen: the episode title, the caption "Automatic transcript", then
  the text in paragraphs of four sentences, each a focus stop, so the
  remote scrolls the text a few sentences at a time and only the
  focused paragraph is bright. Menu closes it.

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

- **§4.10 Surprise** (`SurpriseScreen_tvOS`) is two picks drawn when it
  opens, an episode and an evening (`docs/iOS-DESIGN.md` §4.11), each a
  card-row with Play that opens Now Playing, then Shuffle. Play is the
  default focus, as on Detail.

- **§4.11 A person** (`PersonScreen_tvOS`, `withPerson`) is a List: the
  portrait at 200 pt when one is served, the name at page-title size and
  the facts line (the years from the people row, the episode count), not
  focusable; then one button naming the order, Oldest first or Newest
  first, which flips it (shown only with more than one episode); then a
  section per series of episode rows, each naming the roles it credits
  the person in. Focus lands on the order button or the first row,
  never the heading. No bio is written (R13). Back pops to Detail or
  Search (§1.5).

## §5 The player

- **§5.1 One engine**, the shared `AudioPlayer`, with the `.playback`
  and `.spokenAudio` session and remote commands as on iOS
  (`docs/iOS-DESIGN.md` §5.1, §5.4, §5.5).
- **§5.2 Now Playing is full screen** (`NowPlaying_tvOS`): the episode's
  art at 400 pt (its star, else the series', else the series'
  typographic card, Decision 069), then the series, the title at
  page-title size, date and network; a
  progress bar with elapsed and remaining time; back 15 s, Play,
  forward 30 s, speed, the sleep timer, and the transcript, in one
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
  iOS-DESIGN §6.1a's (Decision 064): the tint is blue, red only on
  Play, Listen live, and the progress line, and a genre hue only as the
  series row's mark. Focus itself stays the system's lift and
  highlight (§6.1); the tint does not repaint it.
- **§7.3 States.** Loading is a `ProgressView`; empty is a
  `ContentUnavailableView` ("Nothing to list yet", "Nothing played
  yet"); a catalog that cannot open is `CatalogUnavailableView` with
  Try Again; the transcript reader has loading, failed, and offline,
  each with Try Again. Offline is iOS §7.2 minus downloads (the TV never
  downloads): `OfflineLine` ("You are offline.", neutral, never
  focusable) heads every tab's root above the Now Playing entry, the
  catalog already on the box keeps working, Detail and Now Playing carry
  the refusal, and a network failure is the player's line "You are
  offline.". The Siri Remote has no haptics.
- **§7.4 VoiceOver.** Each card reads as one element; the Detail and Now
  Playing headers are combined; every control carries a label.

## §8 Values

The rights line, the transcript label, and volume leveling are as in
§1.8, never reworded. Share on the TV is a QR code when that row lands
(PARITY §5).

## §9 Parity and what is planned here

- **§9.1** Update `PARITY.md` in the same change set; build iOS and the
  Mac after any Core change.
- **§9.2 Planned for the TV**: Top Shelf (the person's Continue items),
  the layered parallax icon (waits on the palette and the icon, M0),
  and Stations' guide. SharePlay landed (§5.5).

## §10 Traps this codebase has already paid for

- **§10.1 Writable directories are Caches and the App Group only**; the
  simulator lets Application Support writes through and a device does
  not (`tvos-platform-patterns`). This is one reason downloads are n/a.
- **§10.2 `.plain` kills focus** (§6.1).
- **§10.3 A shelf without `scrollClipDisabled()` clips the focused
  card's lift.**

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

- **Now Playing shows no cast**, though its own comment and research
  §6 say the people are the picture (`NowPlaying_tvOS`).
- **Focus is claimed by `defaultFocus` alone**, which the template's §6.2
  calls unreliable on tvOS; Now Playing declares no default focus and no
  restoration target on dismiss.
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

Bring the next change back to a rule here, or bring a new rule first.
