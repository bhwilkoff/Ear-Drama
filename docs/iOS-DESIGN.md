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
  season is a scope, a transcript is a sheet, the player is a sheet.
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
- **R11** rows and cards are typographic; no art is drawn or invented.
- **R12** brand colors are chrome; a genre's hue is content, drawn only
  as the series row's genre mark (`Color.genre(_:)`, Decision 064).
- **R13** shelves come from `catalog.listenShelves()`, which draws the
  catalog's `meta.listenShelves` in its order (contract §5.1; the same
  list and titles on every platform): "This day in radio", then each
  genre by its `GenreDisplay` name, ids as published. An older catalog
  without the key falls back to the rules run on the device.
- **R15 and Decision 061: loudness by cutting.** `LoudnessLevel.volume`
  (`apple/Core/Player/LoudnessLevel.swift`) sets AVPlayer's volume to
  `-21 - I` dB, clamped so the true peak stays at or below -1 dBTP and
  never above unity, for the default copy only. Silence is never
  trimmed.
- **R16** the transcript is labeled "Automatic transcript"
  (`Transcript.label`), the same words on every platform.
- **R17** the phone's four tabs reduce to the car's four (§9.1).
- **R18** speed, the sleep timer, and skip live on the player.
- **R20** the sleep timer's order is "End of this episode", then 15,
  30, and 45 minutes, then 1 hour (`SleepTimer.options`); it fades, and
  once it fires nothing starts until the person presses Play.
- **R21** every control carries a VoiceOver label (§7.3).
- **The rights line** is the projection's words (`meta.rightsLines`,
  falling back to `RightsDisplay.contract`). An unclaimed recording
  reads "No rights claim known. Removed on request." and is never
  called public domain; a basis with no published words shows no line.
- **R9, R10, R14 on the Radio tab** (§4.9): a gap is drawn as a gap,
  the slot on the air is read from the file's UTC instants on the one
  clock (`RadioClock.onAir`, `apple/Core/Radio/Tonight.swift`, golden
  against `js/api.test.js`), and nothing plays after the evening.
- Not built anywhere yet, because the data plane does not carry them:
  R2 runs, R3 arc ends, R4 gaps, R6 other performances, R7 auditions,
  R8 commercial chapters.

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

- **§3.1 Six tabs, hard set**: Listen, Series, Radio, Plays, Library,
  Search (`AppTab`, `apple/Core/Store/AppStore.swift`). Radio follows
  Series, as on the web (`docs/WEB-DESIGN.md` §3). Search uses
  `Tab(role: .search)`, so the system places it last. Adding any other
  tab amends this rule first. There is no Settings tab or gear.
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

- **§4.1 Listen** is a `List`: Continue listening (the ten most recent
  in progress), then the catalog's published shelves in order (R13). A section draws only
  with rows. Each episode row's context menu offers Play.
- **§4.2 Series browse** is a `List` of series with a toolbar Filter
  `Menu` of three pickers, Genre, Network, and Decade, plus Clear
  Filters. An empty result offers Clear Filters.
- **§4.3 A series page** shows the series' one meta line, then its
  episodes oldest first in sections by broadcast season, "Undated" last.
- **§4.4 Episode detail** is a `List`: the series (a link), the title,
  one facts line (date, network, sponsor, length), Play or Pause, the
  download control, "Automatic transcript" when the gate passed, the
  credits grouped by role, Versions when there is more than one copy,
  and the rights line. A part with no data is absent, never a
  placeholder. Play starts the audio in place; it never opens the
  player (§11.1). The toolbar carries Share: the system share sheet
  (`ShareLink`) with the episode's https twin,
  `https://eardrama.org/episode/{id}` (`SiteLinks.episode`,
  `apple/Core/Store/SiteLinks.swift`; DEEP_LINKS.md), so a person
  without the app lands on the web page. A link is shared, never the
  file (§4.8).
- **§4.5 Search** is `.searchable` with the prompt "Titles, series,
  people", debounced, series first and then episodes. A row found only
  by its transcript says "In the transcript" (`Transcript.searchNote`).
- **§4.6 Library** is In progress, Downloads, and Played, on this
  device. A history row swipes or long-presses to Remove from History;
  a download row to Remove Download; Remove All Downloads asks first.
- **§4.7 The transcript** is a sheet (`TranscriptSheet_iOS`,
  `apple/Shared/TranscriptViews.swift`) from Detail or the player, with
  Done. Plain, selectable text at the body size in a 680 pt measure,
  one sentence a line, fetched from archive.org when opened.
- **§4.8 Downloads** (`apple/Shared/Downloads.swift`) ride a background
  `URLSession` that the system relaunches the app to finish
  (`.backgroundTask(.urlSession)`). A downloaded file is played, never
  exported: no Share or Files action.

- **§4.9 Radio** is Tonight in 19xx (`RadioScreen`,
  `apple/Shared/RadioScreen.swift`), the web's §4.9 in a `List`: the
  evening `tonight.json` publishes for the device's own calendar date
  (`RadioClock.localDate`, never the UTC date), fetched through
  `APIClient.tonight()` from the catalog's Release (contract §2, §8).
  A header of "Tonight in 1942", the evening's date, and the network
  and station; then one row a slot. Each row shows its local time with
  the paper's Eastern time beside it as a caption ("7:00 PM ET" alone
  where the two agree). The slot on the air says "Now" and takes the
  surface-alt row background, repainted every 15 seconds from the
  file's instants. A surviving slot is a link to its episode with a
  borderless Play that plays it from its start; a gap is muted text:
  `known_series` where the file sets it, then "Not surviving" (or "Not
  in the catalog" for a withheld slot or one the open catalog lacks),
  and its length. The paper's printed text is never drawn. Before the
  evening the header says "Starts at", after it "Ended at"; during it,
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

- **§4.10 The account lives at the foot of Library**, never a tab, a
  gear, or a sheet at launch (§3.1; Decision 057: optional, never at
  first launch). Library's last section is one row, "Account", whose
  value is the state: "Not signed in", "Synced {time}", "Sync failed",
  or, while the build carries placeholder ids (`Accounts.xcconfig`),
  "Not available" with the row disabled and no error. An empty Library
  offers the same row as its empty state's action. The row pushes
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
  speed, the sleep timer, and AirPlay's own `AVRoutePickerView`. Errors
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
  UI carries who is there. A following member's transport, speed, and
  scrubber are disabled, and the one caption is the refusal "The host has
  the controls." The control is chrome, so it takes the tint, never the
  live red.
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
  same blue. Red (`Color.brandPrimary`) is set with `.tint` only on what
  is live: Play and Pause, Listen live, Start recording, the scrubber,
  and the progress line in a row. Genre hues are content: the series
  row's leading genre mark, never chrome.
- **§6.2 Six type levels** (`TypeRamp`) over the system text styles,
  so Dynamic Type works and nothing truncates a title.
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
  (`SkeletonRows`, hidden from VoiceOver); empty is a
  `ContentUnavailableView`; a catalog that cannot open at all is
  `CatalogUnavailableView` with Try Again; "Series not found" and
  "Episode not found" carry no retry because retrying cannot help.
- **§7.2 Offline is a warning where it matters.** `OfflineNotice`
  ("Offline. Episodes need a connection to play.", the warning color)
  shows on Detail and the player only when the episode is not
  downloaded. The transcript reader says "You are offline." and retries
  on its own when the network returns.
- **§7.3 VoiceOver.** Every transport control, speed, and the sleep timer
  carries a label and a value; the mini player says "Now playing" with
  the hint "Opens the player"; an episode row reads as one element with
  its progress as a value; AirPlay is "Play on another device".

## §8 Values

- **§8.1** The rights line, the "Automatic transcript" label, and
  loudness by cutting are stated in §1.7 and are not reworded here.
- **§8.2** No analytics and no third-party code (AGENTS.md "no
  third-party Swift packages"). The privacy, credits, and take-down
  pages are the website's; the app links to them when that row lands
  (PARITY §2).

## §9 Stubs that live in the iOS target, and parity

- **§9.1 CarPlay** (`apple/iOS/CarPlay_iOS.swift`) is the car's four
  tabs (R17): Continue, Radio, Series, Downloads. Continue lists up to 12
  in-progress episodes with their progress and plays through the one
  `AudioPlayer`, then pushes `CPNowPlayingTemplate.shared`; the other
  three say "Not in the car yet". No transcript in the car. It is
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

- **Six tabs overflow the iPhone tab bar on iOS 18**, which shows four
  and More; iOS 26 sets Search apart. Which tab gives way on an
  iOS 18 phone is the owner's call (§3.1).
- **Listening live drifts at a speed other than 1x**: the offset is
  taken at join, and the player's speed is the listener's.

- **The queue disagrees across platforms.** `PlaybackQueue.following`
  (`apple/Core/Player/PlaybackQueue.swift`) plays on through the rest of
  the series, up to 50; Android plays on through the rest of the
  season; the web plays the next one only when the person queued it
  (`docs/WEB-DESIGN.md` §5.4). R14 needs one rule; the owner picks it.
- **Resume and "played" differ from the web**: past 30 s and played
  within 45 s of the end, against the web's 10 s to 95% window (§5.6).
  Decision 062 settles the fade, speeds, save cadence, and rewind
  (§5.7), not these two.
- **An untitled episode falls back to its date, then the series name**
  (`EpisodeRow.displayTitle`); the web says "Untitled".
- **Series browse facets are not counted against one another**
  (`catalog.browseFacets()` takes no selection), so an offered choice
  can yield zero rows; the web forbids that (`WEB-DESIGN` §10.5). There
  is no sort.
- **Seasons are sections, not a scope** (`SeriesScreen`); the web and
  Android show one season at a time.
- **The series link on Detail is a push**, so Listen, Episode, Series
  is a third level (§1.5), and from there another episode is a fourth.
- **No Queue or Following verbs** on Detail or in Library, which the web
  has (`WEB-DESIGN` §4.5, §4.7). A person-built queue changes what plays
  after an episode, which is the open queue rule above, so it waits on
  the owner; Following has no native rule yet (where the button sits,
  the Listen shelf, the Library section), so it needs one before it is
  built.
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
