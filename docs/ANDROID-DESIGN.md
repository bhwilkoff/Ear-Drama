# Ear Drama Android design (binding)

**Binding.** Quote the rule number before proposing any new screen,
route, sheet, tab, or car or TV surface on Android. If no rule fits,
propose a new rule first, then the feature
(`binding-design-doc-discipline`). Companion to `PARITY.md`,
`docs/CATALOG-CONTRACT.md`, `docs/WEB-DESIGN.md`, `docs/iOS-DESIGN.md`,
`docs/macOS-DESIGN.md`, and `docs/tvOS-DESIGN.md`. Where a rule here
inverts a sibling's, §11 says so.

Seeded 2026-10-22 from `docs/templates/ANDROID-DESIGN-template.md`. It
describes what is built in `android/app/src/main/java/com/example/appname/`
(`ui/`, `playback/`, `navigation/`, `data/`) and `android/wear/`. The
production lessons this doc does not restate live in
`android-production-gotchas`; the TV focus mechanics in
`androidtv-compose-focus`.

## §1 Principles

- **§1.1 Android feels like Material 3.** The web's verbs
  (`docs/WEB-DESIGN.md` §4) in Material's own components:
  `NavigationSuiteScaffold`, `TopAppBar`, `ListItem`, `FilterChip`,
  `DockedSearchBar`, `ModalBottomSheet`, `DropdownMenu`, and system and
  predictive back. Never port iOS chrome.
- **§1.2 Compose only, one Activity.** `MainActivity` hosts `AppRoot`;
  no Fragments, no AppCompat.
- **§1.3 One shared data plane.** Screens read the served projection
  through `CatalogDatabase` via `rememberCatalogQuery` (`ui/Components.kt`)
  and the network through `ApiClient`; a screen never opens SQLite or
  OkHttp itself.
- **§1.4 Depth is at most two from a tab**: tab, series, episode. A
  season is a scope; the player is a sheet.
- **§1.5 Only essential words on screen** (AGENTS.md); no list or blurb
  written by the app (R13).

### §1.6 The shared rules as they bind Android

The common text is in `docs/WEB-DESIGN.md` §4.5, §5, and §8 and
`docs/research/05-design-research.md` §9. On Android:

- **R1** the date leads every episode row (the `ListItem` overline in
  `EpisodeListItem`) and every card; episodes run oldest first.
- **R5** copies are Versions on Detail, each with its own Play, the rank
  0 copy the default.
- **R11** cards are typographic `OutlinedCard`s (date, title, series);
  no node, card, or notification carries invented art.
- **R12** brand colors are chrome; dynamic color is off by default.
- **R13** shelves are rules over data: This day in radio and one shelf
  per genre the catalog names.
- **R15 and Decision 061: loudness by cutting.** `LoudnessLevel.volume`
  (`playback/LoudnessLevel.kt`) gives each queued item `-21 - I` dB,
  peak-clamped at -1 dBTP and never above unity, for the default copy
  only; the sleep fade multiplies it.
- **R16** "Automatic transcript" (`Transcript.LABEL`) on Detail, the
  player, and the transcript screen's title.
- **R17** the car's four roots are the phone's tabs reduced (§9.1).
- **R18** speed, sleep, and skip live on the player sheet.
- **R20** the sleep menu lists "End of this episode" first, then 15, 30,
  45, and 60 minutes (`SleepTimer`); it fades, and once fired the queue
  stops.
- **R21** every icon button has a `contentDescription`; §7.3.
- **The rights line** reads "No rights claim known. Removed on
  request." for an unclaimed recording, never public domain; a clean
  basis with no words shows no line (`DisplayVocabulary.rightsLine`).
- Not built anywhere yet (data plane first): R2, R3 arc ends, R4, R6,
  R7, R8, R9, R10.

## §2 Data plane

- **§2.1 One read path.** `CatalogDatabase` over the bundled SQLite
  driver; `rememberCatalogQuery` re-runs on `dbVersion`, on its keys,
  and, with `watchUser`, on the listener's own records.
- **§2.2 The projection decides.** Rights, rank, the transcript gate,
  and loudness numbers arrive in the served database; the client adds no
  filter beyond the contract's `recommendAnd` on shelves and the queue.
- **§2.3 A person's listening stays on the device** (`UserStore`,
  `DownloadStore`) until sign-in (Decision 057, M5).

## §3 Navigation shell

- **§3.1 Four tabs, hard set**: Listen, Series, Search, Library (`Tab`,
  `navigation/Routes.kt`), with Material icons Headphones, Radio, Search,
  and Bookmarks. `NavigationSuiteScaffold` draws a bar, a rail, or a
  drawer by window size. Radio joins with the evenings.
- **§3.2 One route registry.** Every destination is a case of the sealed
  `Route` (Navigation 3 `NavKey`): the four roots, `Series`, `Episode`,
  and `Transcript`, resolved in one `entryProvider` in `ui/AppRoot.kt`.
- **§3.3 One back stack per tab** (`rememberNavBackStack`). System back
  and predictive back pop within the tab
  (`android:enableOnBackInvokedCallback="true"`); tapping the selected
  tab returns it to its root; another tab keeps its stack.
- **§3.4 Deep links and doors land in the inbox** that `MainActivity`
  posts to and `AppRoot` drains in one `LaunchedEffect`.

## §4 Surfaces

- **§4.1 Listen** is a `LazyColumn` of shelves, each a header over a
  `LazyRow` of 220 dp cards: Continue listening, This day in radio, then
  the genre shelves. A shelf with no rows is not drawn.
- **§4.2 Series browse** is decade and genre `FilterChip`s over a paged
  list of series (200 at a time), each one line of years and count.
- **§4.3 A series page** shows years and count, then its broadcast
  seasons as `FilterChip`s, a segmented scope and never a push, the oldest
  selected first; the episodes of that season run oldest first.
- **§4.4 Episode detail**: the date, the title as a heading, the series
  as a link, one facts line (network, length), Play (or "Resume at"
  the saved position), the download control, "Automatic transcript"
  when the gate passed, Cast and credits, Versions (or the one copy's
  notes), and the rights line. A part with no data is absent.
- **§4.5 Search** is a `DockedSearchBar` ("Titles, series, people"),
  debounced, with Clear, series first and then episodes; "In the
  transcript" marks a transcript-only match.
- **§4.6 Library** is In progress (with "position of length"), Downloads
  (with storage held and Remove All, which asks first), and Finished.
- **§4.7 The transcript is a route** (`ui/screens/TranscriptScreen.kt`):
  the episode title, then plain selectable text, a sentence a line, at
  most 680 dp wide, fetched from archive.org when opened.
- **§4.8 Episode rows carry two targets**: the row opens Detail ("Open
  episode") and the trailing button plays ("Play" and the title).

## §5 The player

- **§5.1 One engine.** `PlaybackEngine` owns the Media3 player; the
  `PlaybackService` (`MediaLibraryService`, `mediaPlayback`) wraps it so
  the notification, the lock screen, Bluetooth, and the car share one
  session, with back 15 and forward 30 as its media buttons. Nothing
  plays at start: the only path to the player is a request from the
  listener.
- **§5.2 The mini player** sits above the tabs while an episode is
  loaded (`MiniPlayer`, `ui/screens/Player.kt`): a progress line, title,
  series (or the problem, in the error color), and Play or Pause; a tap
  opens the player.
- **§5.3 The player is a `ModalBottomSheet`**: series, title (a link to
  Detail), date, any problem, the position slider with elapsed and
  remaining, back 15, a 72 dp Play, forward 30, then speed, the
  transcript, and the sleep timer as `DropdownMenu`s, and "Up next".
- **§5.4 Progress** saves every 5 s while playing; resume starts 5 s
  early; a finished episode starts over.

## §6 Theme

- **§6.1 Brand first; dynamic color is not the default**
  (`ui/theme/Theme.kt`, `dynamicColor = false`). Light and dark come from
  the generated tokens.
- **§6.2 Six type levels** (`AppTypography`, `ui/theme/Type.kt`):
  `displaySmall`, `headlineSmall`, `titleMedium`, `bodyMedium`,
  `labelMedium`, `bodySmall` with tabular figures, over the system face.
  Refuse a seventh.
- **§6.3 Icons are Material Symbols** (R-ICON-1); the skip icons are
  Media3's own.
- **§6.4 Haptics use the one taxonomy**, mapped in one place. None are
  wired yet (§12).

## §7 States and accessibility

- **§7.1 Every query has four states** (`Loadable`): Loading (a labeled
  spinner), Ready, NoCatalog ("No catalog on this device yet.", Try
  again), and Failed ("The catalog could not be read.", Try again). An
  empty result is an `EmptyMessage` sentence; "This episode is not in
  the catalog." has no retry.
- **§7.2 The transcript has its own states**: loading, "You are
  offline." or "The transcript did not load." with Try again.
- **§7.3 TalkBack.** Section headers and the Detail title are
  `heading()`; rows carry `onClickLabel`s; the slider has a description
  and a state ("m:ss of m:ss"); speed and the sleep timer announce their
  value; font scaling applies because every style is in `sp`.

## §8 Values

The rights line, the transcript label, and loudness by cutting are as in
§1.6 and are not reworded. A downloaded file is played, never exported:
no share or open-with action (`ui/Downloads.kt`). No analytics.

## §9 Stubs that live in the Android build, and parity

- **§9.1 Android Auto** (`playback/CarLibrary.kt`) is the browse tree the
  service serves: four roots, Continue, Radio, Series, Downloads (R17).
  Continue lists this device's in-progress episodes as playable nodes
  (title, series and date) within an 8 s budget; the other three are
  empty. No artwork. Every release with car support waits on Google's
  car review.
- **§9.2 Android TV and Fire TV** are a runtime branch of the one app
  (`ui/Television.kt`, `isTelevision()`), never a flavor. On a TV the
  focused card wears a ring and a 1.06 scale (`tvFocusMark`), never
  color alone, and Listen claims focus on its first card
  (`ClaimTvFocus`). The session stays on so the home screen can show a
  Now Playing card (TV-NP). The banner is a placeholder.
- **§9.3 Wear OS** (`android/wear/`) is Continue, saying "Waiting on the
  phone" until the phone hands its history over; minSdk 30.
- **§9.4** Update `PARITY.md` in the same change set.

## §10 Traps this codebase has already paid for

- **§10.1 Every query keys on `dbVersion`** (`rememberCatalogQuery`), or
  a screen shows yesterday's catalog after a swap.
- **§10.2 A recreated Activity must not reopen the launch doors**
  (`savedInstanceState == null` in `MainActivity`).
- **§10.3 Fire OS can report a normal UI mode on a TV**, so
  `isTelevision()` also checks the launcher's feature flags.
- **§10.4 A credit's position is its key** on Detail: one person can hold
  two roles on one broadcast.

## §11 Deliberate inversions

- **§11.1 Play never opens the player.** Like iOS, Play on Detail
  starts the audio in place; tvOS focuses Play and opens Now Playing
  (`docs/tvOS-DESIGN.md` §6.2).
- **§11.2 The transcript is a pushed route**, where iOS uses a sheet,
  the Mac a window, tvOS a full-screen reader, and the web a closed
  section. Same label everywhere.
- **§11.3 Predictive back pops the stack**; iOS's swipe back is a fixed
  animation.
- **§11.4 The media session stays on on a TV**, the inverse of Archive
  Watch, a video app that turns its session off there.
- **§11.5 Search is the third tab**, as on the web, where Apple's
  `role: .search` lets the system place it last.

## §12 Open (what the code does not yet meet)

- **The queue is the rest of the season** (`followingInSeason`), where
  Apple plays on through the series and the web only what the person
  queued (`docs/WEB-DESIGN.md` §5.4). R14 needs one rule.
- **The sleep fade is 10 s** (`SleepTimer.FADE_MS`); the web fades over
  20 s. **Speeds are 0.75 to 2** (`PlaybackEngine.SPEEDS`); the web's
  are 0.8 to 2. **Saves every 5 s and rewinds 5 s**; Apple rewinds 3 s,
  and the web saves every 10 s.
- **Dates read "Feb 24, 1943"** (`formatAirDate`) and sit in a
  proportional overline; Apple shows the stored `1943-02-24` in tabular
  figures, as R1 and the web's tabular rule ask.
- **Detail has no sponsor**, and its order (date, title, series) differs
  from the web's (series, title, date).
- **The rights words are hard-coded** (`DisplayVocabulary.UNCLAIMED`);
  Apple reads the published `meta.rightsLines` first (contract §5.5).
- **Decades are a client constant** (`DECADES`, 1930 to 1970), not data,
  and no facet is counted against the others, so a chip can yield zero
  rows; there is no network facet or sort.
- **Detail, the series link, and the transcript route stack up**: from
  the Series tab, series, episode, and transcript is a third push
  (§1.4).
- **The transcript text uses `bodyLarge`**, a seventh style outside
  `AppTypography` (§6.2).
- **Library says "Finished"** where Apple says "Played".
- **No offline state** on the catalog screens or Detail; only the player
  reports a problem.
- **Deep links are not routed**: `routeUniversalLink` and
  `routeCustomScheme` are template stubs, and the scheme matched is
  `appname`, not `eardrama` (`MainActivity.kt`).
- **On a TV only Listen claims focus**; the other screens, the player
  bottom sheet, and the transcript are the phone's layouts.
- **No Queue, Following, or Share verbs**, which the web has.
- **No haptics** (§6.4). Tab icons differ from Apple's (Headphones and
  Radio against `play.circle` and `square.stack`).

Bring the next change back to a rule here, or bring a new rule first.
