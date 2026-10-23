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
  cards are typographic (date, title, series), with no art and no
  placeholder; **R12** brand is chrome only; **R13** shelves by rule.
- **R14** lean-back is bounded: the sleep timer ends a session, and the
  queue holds only this series (see §12 for the open queue rule).
- **R15 and Decision 061**: loudness by cutting, `LoudnessLevel.volume`.
- **R16**: the reader's caption and every button say "Automatic
  transcript".
- **R18**: speed, sleep, and skip are on Now Playing.
- **R20**: "End of this episode" first, then 15, 30, 45 minutes, 1 hour;
  it fades, and once fired nothing starts until Play.
- **The rights line** is the projection's words; unclaimed reads "No
  rights claim known. Removed on request."
- **Downloads are n/a**: the TV has no durable storage for media.

## §2 Information architecture

- **§2.1 Four tabs, hard set**: Listen, Series, Library, Search, in a
  `TabView` with `.sidebarAdaptable`; Search uses `Tab(role: .search)`.
  Radio joins with the evenings, and is the TV's most natural tab ("Tonight
  in 1947") when it does.
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

- **§4.1 Listen** is Continue listening as the first shelf (up to ten),
  then the catalog's shelves by rule.
- **§4.2 Series browse** is a `List` led by a Genre picker.
- **§4.3 A series page** is the series name and meta line (not
  focusable), then episodes oldest first in sections by broadcast
  season, "Undated" last.
- **§4.4 Episode detail** (`EpisodeScreen_tvOS`) is the series, the
  title at page-title size, the facts line (date, network, sponsor,
  length), then an action row in one focus section: Play, Series, and
  "Automatic transcript" when the gate passed. Then the offline warning,
  the credits by role, and the rights line.
- **§4.5 Search** is `.searchable` with the prompt "Titles, series,
  people", series first, then episodes, with "In the transcript" on a
  row found only by its transcript.
- **§4.6 Library** is In progress. A held Select on a row offers Remove
  from History.
- **§4.7 The transcript reader** (`TranscriptScreen_tvOS`) is full
  screen: the episode title, the caption "Automatic transcript", then
  the text in paragraphs of four sentences, each a focus stop, so the
  remote scrolls the text a few sentences at a time and only the
  focused paragraph is bright. Menu closes it.

## §5 The player

- **§5.1 One engine**, the shared `AudioPlayer`, with the `.playback`
  and `.spokenAudio` session and remote commands as on iOS
  (`docs/iOS-DESIGN.md` §5.1, §5.4, §5.5).
- **§5.2 Now Playing is full screen and typographic** (`NowPlaying_tvOS`):
  the series, the title at page-title size, date and network; a
  progress bar with elapsed and remaining time; back 15 s, Play,
  forward 30 s, speed, the sleep timer, and the transcript, in one
  focus section. Play/Pause on the remote toggles from anywhere on the
  screen (`onPlayPauseCommand`). Menu dismisses it.
- **§5.3 Seeking is by skip.** tvOS has no `Slider`, so the progress bar
  is a readout and the skip buttons move the position.
- **§5.4 No mini player.** The TV is one thing at a time; the shell
  shows the content and Now Playing is the player.

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
  `apple/Core/Design.swift`) over the system's ten-foot text styles.
- **§7.2 Tokens only**, the same generated colors as every Apple
  platform; only the focused element is bright.
- **§7.3 States.** Loading is a `ProgressView`; empty is a
  `ContentUnavailableView` ("Nothing to list yet", "Nothing played
  yet"); a catalog that cannot open is `CatalogUnavailableView` with
  Try Again; the transcript reader has loading, failed, and offline,
  each with Try Again.
- **§7.4 VoiceOver.** Each card reads as one element; the Detail and Now
  Playing headers are combined; every control carries a label.

## §8 Values

The rights line, the transcript label, and loudness by cutting are as in
§1.8, never reworded. Share on the TV is a QR code when that row lands
(PARITY §5).

## §9 Parity and what is planned here

- **§9.1** Update `PARITY.md` in the same change set; build iOS and the
  Mac after any Core change.
- **§9.2 Planned for the TV**: Top Shelf (the person's Continue items),
  the layered parallax icon (waits on the palette and the icon, M0),
  the Radio tab's guide, and SharePlay.

## §10 Traps this codebase has already paid for

- **§10.1 Writable directories are Caches and the App Group only**; the
  simulator lets Application Support writes through and a device does
  not (`tvos-platform-patterns`). This is one reason downloads are n/a.
- **§10.2 `.plain` kills focus** (§6.1).
- **§10.3 A shelf without `scrollClipDisabled()` clips the focused
  card's lift.**

## §11 Deliberate inversions

- **§11.1 Detail focuses Play and Play opens Now Playing** (§6.2). iOS,
  the Mac, and Android leave the person where they are.
- **§11.2 `.card`, never `.plain`.** On iOS `.plain` is correct.
- **§11.3 Now Playing fills the screen.** The phone uses a sheet, the
  Mac a transport bar, Android a bottom sheet.
- **§11.4 Leaving a tab resets its stack.** The phone keeps each stack.
- **§11.5 The transcript is a focus-scrolled reader in paragraphs**;
  elsewhere it is selectable text a sentence a line.
- **§11.6 Seeking is by skip only** (§5.3); every other platform has a
  scrubber.

## §12 Open (what the code does not yet meet)

- **Once Now Playing is dismissed there is no way back to it.** There is
  no mini player or Now Playing entry, and `isPlayerPresented` is set
  only by Play on Detail, which plays the episode again
  (`PlayEpisodeAction`). A person who pressed Menu has to find the
  episode to see the player.
- **Now Playing shows no cast**, though its own comment and research
  §6 say the people are the picture (`NowPlaying_tvOS`).
- **Focus is claimed by `defaultFocus` alone**, which the template's §6.2
  calls unreliable on tvOS; Now Playing declares no default focus and no
  restoration target on dismiss.
- **Detail has no Versions** (R5), though PARITY marks the versions
  picker in progress on tvOS (`EpisodeScreen_tvOS`).
- **Series browse has only a Genre facet**, no network or decade
  (`SeriesBrowseScreen_tvOS` passes `network: nil, decade: nil`).
- **Library has no Played section**, and Remove from History does not
  ask first, so focus is left to the engine afterward (§6.4).
- **Search has no loading state** (`SearchScreen_tvOS`).
- **The caption level is `Font.caption`**, below the 29 pt body floor;
  the rights line and meta lines use it.
- **Every shared-Core item in `docs/iOS-DESIGN.md` §12** holds here too:
  the queue rule, the 10 s fade, the speed list, the save and resume
  numbers, the untitled fallback, and seasons as sections.

Bring the next change back to a rule here, or bring a new rule first.
