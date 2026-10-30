# Ear Drama macOS design (binding)

**Binding.** Quote the rule number before proposing any new window,
sidebar section, menu command, sheet, or toolbar item on the Mac. If no
rule fits, propose a new rule first, then the feature
(`binding-design-doc-discipline`). Companion to `PARITY.md`,
`docs/CATALOG-CONTRACT.md`, `docs/WEB-DESIGN.md`, `docs/iOS-DESIGN.md`,
`docs/tvOS-DESIGN.md`, and `docs/ANDROID-DESIGN.md`. Where a rule here
inverts a sibling's or the template's, §11 says so.

Seeded 2026-10-22 from `docs/templates/MACOS-DESIGN-template.md`. The
template's Part A (a Mac-exclusive heavy feature) does not apply: Ear
Drama's Mac app is the shared parity face only, so this doc follows the
web doc's numbering and keeps the template's Part B rules where they
fit. It describes what is built in `apple/macOS/ContentView_macOS.swift`,
the screens it shares with iOS in `apple/Shared/`, and `apple/Core/`.
Mechanics live in `macos-platform-patterns`.

## §1 Principles

- **§1.1 The Mac is a pointer, keyboard, menu bar, resizable-window
  app**, never the iPhone app resized. Same verbs as every platform
  (`docs/WEB-DESIGN.md` §4), Mac idioms: a split view, the menu bar with
  key equivalents, tooltips, more than one window.
- **§1.2 One shared data plane.** `CatalogStore` and `APIClient.shared`
  in `apple/Core/`, exactly as on iOS (`docs/iOS-DESIGN.md` §2). Views
  never open the database or call `URLSession`.
- **§1.3 Depth is at most two from a sidebar section.** Section, series,
  episode. A transcript is its own window, not a push.
- **§1.4 Only essential words on screen** (AGENTS.md); no list or blurb
  written by the app (R13).

### §1.5 The shared rules as they bind the Mac

Stated once in `docs/WEB-DESIGN.md` and `docs/iOS-DESIGN.md` §1.7; the
Mac uses the same Core, so the same code holds them:

- **R1** the date leads every episode row, oldest first; **R5** Versions
  on Detail; **R11** typographic rows with served art (Decision 069: the
  shared `ArtTile` on rows that mix series, `FaceFigure` beside the series
  and Detail headings, `CreditFace` on cast lines, the series' tile in the
  transport bar, and the system Now Playing artwork, as iOS-DESIGN R11);
  **R11a** faces lead, as iOS-DESIGN R11a: the series page, Detail, and a
  person's page open with `FaceHero` (the print beside its label inside
  276 x 240 pt, or the plate for a wide picture, at most 320 pt tall; no
  wash or bars (owner, 2026-10-28: *"I think you can find better solutions for different aspect ratios of images, then just blurring and black bars."*; `artwork-presentation-design`)), the Mac's rows keep
  the 40 pt tile, and an evening's aired slot leads with its tile; the
  tile, `CreditFace`, and the system Now Playing square center on the
  published face, as iOS-DESIGN R11a (V4), a wide picture without one
  left uncropped;
  **R11b** one grammar, as iOS-DESIGN R11b (owner, 2026-10-29: *"the design is still not uniform for all different levels of content (some with images, some without, some with more information, some with less). We need to a design approach that evens out all of the inconsistencies and make the app look like one complete thought."*; `catalog-experience-design` rule 11; D3-1): the same
  `apple/Shared/Grammar.swift` components, the pointer's hover lifting a
  tile's board, never a stripe;
  **R11c** Home and Browse as iOS-DESIGN R11c (owner, 2026-10-29: *"Having more shows is better, so 5."* and *"I like the bulky blocks and colors of The Sleeve and I like the data visualization options of the Almanac."*; D3-2): shows are series of five or more episodes, the day board and its years strip, that night's tiles, Most downloaded, and Browse's count line, decade by genre field (beside the grid, always regular width) and tile grid; tiles hover-lift, the grid is reachable by keyboard;
  **R12** brand is chrome only;
  **R13** shelves are the catalog's `meta.listenShelves`, in order
  (`docs/iOS-DESIGN.md` R13).
- **R15 and Decision 067**: volume leveled on the device by the shared
  `VolumeLeveler` tap (iOS-DESIGN §1.7); "Level volume" sits beside the
  sleep timer in the player bar.
- **R16**: "Automatic transcript" is the label on the menu item, the
  toolbar button's tooltip, and the transcript window's subtitle.
- **R18**: speed, the sleep timer, and skip are on the transport bar and
  in the Controls menu.
- **R20**: the sleep timer's order is "End of this episode", 15, 30, 45
  minutes, 1 hour; it fades, and once fired nothing starts until Play.
- **R21**: every control has an accessibility label and a `.help`
  tooltip.
- **The rights line** is the projection's words; unclaimed reads "No
  rights claim known. Removed on request." and is never public domain.

## §2 Scenes and windows

- **§2.1 The main window** is one `WindowGroup` (`apple/App/EarDramaApp.swift`)
  whose title is the episode playing, or "Ear Drama" when nothing is.
- **§2.2 The transcript window** is a second `WindowGroup`, id
  `transcript`, opened with a `TranscriptRef` (title and URL), default
  560 by 680, at least 360 by 320, titled with the episode and
  subtitled "Automatic transcript" (`TranscriptWindow_macOS`,
  `apple/Shared/TranscriptViews.swift`). It sits beside the main window
  while the episode plays, which is why it is a window.
- **§2.3 No Settings scene.** Nothing in 1.0 is a preference: speed and
  the sleep timer live on the player (R18).
- **§2.4 Closing the main window keeps playing**, as Music does. The
  episode belongs to the app's one `AudioPlayer`, not to the window, so
  the red button closes the browse window and the sound goes on, driven
  from the Controls menu, the media keys, and the system's Now Playing
  item, all of which work with no window open. Reopening from the Dock
  shows the transport bar on the episode still playing, never a second
  copy. Stop is the person's: Pause, or quitting the app. This inverts
  template §B13 on purpose (§11.6).

## §3 Navigation shell

- **§3.1 Six sidebar sections, hard set** (Decision 068: sections are
  actions, as Archive Watch's macOS sidebar): Home, Browse, Stations,
  Surprise, Search, Library, in `AppTab` order
  (`apple/Core/Store/AppStore.swift`), ⌘1 to ⌘6 in the Go menu (§5.5).
  Plays are rows in Browse and Search; "Start an ear drama" on a play's
  page, or on an episode whose `script` is set, opens the production's
  window; Library lists Ear dramas. Surprise
  is `docs/iOS-DESIGN.md` §4.11 in the detail column. A new section
  amends this rule first.
  - *Replaced*: "Six sidebar sections, hard set: Listen, Series, Radio,
    Plays, Search, Library ... Radio follows Series as on the web and is
    ⌘3."
- **§3.2 One `NavigationSplitView`.** The sidebar is a selectable `List`
  of the sections (180 to 210 pt); the detail column is one
  `NavigationStack` bound to the selected section's path and re-created
  per section (`.id(store.selectedTab)`), so each section keeps its own
  path. Every stack applies the shared `routeDestinations()` registry.
- **§3.3 Search lives in the toolbar** (`.searchable(placement:
  .toolbar)`), over the shared `SearchResultsList`, so its sections are
  iOS's (iOS-DESIGN §4.5: Aired, Episodes, Automatic transcript).
- **§3.4 Everything external lands in the inbox**, drained by `RootView`
  (the same rule as iOS §3.5).

## §4 Surfaces

The four screens are iOS's (`apple/Shared/ListScreens.swift`); a List on
the Mac is already a Mac list, with context menus on right-click. What
each holds is `docs/iOS-DESIGN.md` §4.1 to §4.6, and the Mac differs
only here:

- **§4.0 Browse** is iOS's (`docs/iOS-DESIGN.md` §4.2): the same chips,
  "Sort: Popular" by default, in a `safeAreaBar` under the toolbar.
- **§4.1 The transcript opens a window** from Detail, the transport bar,
  or the Controls menu (§2.2), never a sheet.
- **§4.2 Downloads** are the same background `URLSession`, the same
  series Download menu (in the toolbar), and the same Downloads place
  pushed from Library's row as iOS (`docs/iOS-DESIGN.md` §4.3, §4.6,
  §4.8); a row's Remove is on right-click. A download is played, never
  exported.
- **§4.3 Stations** is iOS's `RadioScreen` (`docs/iOS-DESIGN.md` §4.9) in
  the detail column: the same stations row (Tonight, then each genre
  station, each with what is on now and Listen live), slots, times, gaps,
  and Listen live on the one `LiveRadio`. A slot's Play is a borderless button the pointer
  reaches without opening the episode; the listing's credit is a link
  the default browser opens. Space pauses as anywhere (§5.3), and a
  pause ends listening live.
- **§4.4 The account is Library's last row**, as on iOS
  (`docs/iOS-DESIGN.md` §4.10), pushed in the detail column: not a
  Settings scene (§2.3 holds; an account is not a preference) and not a
  menu item. Sign in with Google opens the system's web authentication
  sheet (`ASWebAuthenticationSession`, PKCE, no third-party package).
- **§4.6 A person** is iOS's `PersonScreen` (`docs/iOS-DESIGN.md`
  §4.13) pushed in the detail column from a credit on Detail or from
  Search's People; the order Menu is in the toolbar, and a row's Play is
  on right-click.
- **§4.5 An ear drama** is `docs/iOS-DESIGN.md` §4.12 in the
  production's window: any open part can be taken, the suggested one
  prominent; Start Recording needs an account and offers the same
  sign-in buttons in the window; Listen Through runs live at any time;
  Export appears whenever the play is complete.
- **§4.5a A shared ear drama** is `docs/iOS-DESIGN.md` §4.12a (PLAYS-DESIGN
  §11.7, binding: the same verbs and words on every platform) in the
  production's window: Share, Invite, Upload, and People sit in the cast
  sheet's sidebar above the parts (Publish joins them only when the consent
  screen ships, Decision 072); a part's Done with This Part, Release, and
  Open Part are in its row's menu and on right-click; People is a sheet on
  the window. Coming back to the app re-reads the record. The invitation shows in
  Library's Ear dramas in the main window, and Open or Take Part opens
  the production's own window.

## §5 The player

- **§5.1 One engine,** the shared `AudioPlayer`. The Mac has no audio
  session, so it sets `MPNowPlayingInfoCenter.playbackState` itself and
  the system's Now Playing menu-bar item and media keys follow.
- **§5.2 The transport is a bar along the window's bottom edge**
  (`TransportBar_macOS`), shown while an episode is loaded: title,
  series and date, back 15 s, Play, forward 30 s, the scrubber with
  elapsed and remaining time, speed, the sleep timer, Listen Together,
  AirPlay's own `AVRoutePickerView` (`RoutePicker_macOS`, given the
  player to route, since the Mac has no audio session), and the
  transcript button. Errors, or the offline warning, sit under it. The
  Controls menu has no AirPlay item: AVKit opens its picker only from its
  own button.
  Controls are `.borderless`, and speed and sleep are `.fixedSize()` so
  their labels never truncate (template §B11).
- **§5.3 Every playback command is in the menu bar** (template §B10), in
  a Controls menu (`PlaybackCommands_macOS`), disabled rather than hidden
  when nothing is loaded. No item takes a bare key, because a bare key
  in the menu bar is taken from every text field:

  | Command | Key |
  |---|---|
  | Play / Pause | Space, from the main window (not a menu key) |
  | Back 15 Seconds | ⌘← |
  | Forward 30 Seconds | ⌘→ |
  | Speed (submenu) | |
  | Sleep Timer (submenu, with Turn Off Timer) | |
  | Download Episode, or Remove Download | |
  | Automatic transcript | ⌥⌘T |

  Space plays and pauses through the main window's `.onKeyPress`, which
  a focused text field receives first, so typing a space in Search never
  pauses. Play / Pause is disabled while a production window records a
  part (PLAYS-DESIGN), so the microphone never hears the episode.
- **§5.5 The Go menu** (`GoCommands_macOS`, template §B10) comes before
  Controls and carries the sidebar sections in `AppTab` order, ⌘1
  onward; Search ⌘F, which opens the Search section and focuses its
  field; and Back ⌘[, which pops the section's stack and is disabled at
  its root (`AppStore.goBack`).
- **§5.6 The Help menu** (`HelpCommands_macOS`) replaces the system
  placeholder with the website's own pages: Ear Drama Website, Credits,
  Privacy, and Take-Down Requests (`SiteLinks`,
  `apple/Core/Store/SiteLinks.swift`).
- **§5.7 Share** is in Detail's toolbar: the system share sheet with the
  episode's https twin (`SiteLinks.episode`, DEEP_LINKS.md), as on iOS
  (`docs/iOS-DESIGN.md` §4.4).
- **§5.8 Listen Together is SharePlay**, as `docs/iOS-DESIGN.md` §5.8:
  the `shareplay` control in the transport bar after the sleep timer,
  and SharePlay (or Leave SharePlay) in the Controls menu. Outside a call
  the system's sharing sheet opens on the window
  (`GroupActivitySharingController`, `presentAsSheet`). A following
  member's skip and speed are disabled in the bar and the menu, with
  "The host has the controls." under the bar; Play and Pause stay theirs,
  a hold that catches up on play (Decision 067, iOS-DESIGN §5.8).
- **§5.4 Progress** saves every 5 s and on pause (template §B3c); resume
  and "played" follow `docs/iOS-DESIGN.md` §5.6. The numbers are
  Decision 062's, named once in `PlayerNumbers` (`docs/iOS-DESIGN.md`
  §5.7).

## §6 Look

- **§6.1 Tokens only**, through the generated `apple/Core/Design.swift`,
  in light and dark (`NSColor` appearance-matched pairs).
- **§6.1a Color roles** are iOS-DESIGN §6.1a's (Decision 064): the
  windows' tint and `AccentColor` are the blue `brandSecondary`, so the
  sidebar selection is blue wherever the person's system accent is
  Multicolor (a chosen system accent wins, as the Mac intends); ink
  (`brandPrimary`) on Play, Listen live, the scrubber, and the progress
  line; red (`brandRecord`) only on recording: Start Recording, the
  record control, and "Your line" (owner, 2026-10-29: *"Red means
  recording."*); genre hues only as the series row's genre mark.
- **§6.2 Six type levels** (`TypeRamp`) over the system text styles;
  the page title and section header set the bundled Big Shoulders Bold
  (Decision 060).
- **§6.3 Icons are SF Symbols**; every icon-only button has a `.help`
  tooltip and an accessibility label.

## §7 States and accessibility

- **§7.1 The four states** are iOS's (`docs/iOS-DESIGN.md` §7.1):
  skeleton rows, `EmptyState` (§7.4), `CatalogUnavailableView`
  with Try Again, and no retry where retrying cannot help.
- **§7.2 Offline** is iOS §7.2: `OfflineLine` ("You are offline.",
  neutral) sits above the transport bar, or alone along the window's
  bottom edge when nothing is loaded; the refusal (`OfflineNotice`)
  shows on Detail and the transport bar only when the episode is not
  downloaded, and a network failure is the player's line "You are
  offline."; the transcript window says "You are offline." and retries
  when the network returns. No haptic (§8).
- **§7.3 VoiceOver and the keyboard.** Labels and values on every
  control; every command reachable from the menu bar, so the app is
  usable without the pointer.
- **§7.4 One empty state** is iOS §7.4, the same `EmptyState` view
  (AGENTS.md: "Only essential words on screen. A caption must be a
  refusal, a warning, or a fact the person cannot discover by
  looking."): the fact and at most one action. An empty Library is
  "Nothing played yet" with Browse, which selects Browse in the sidebar,
  and the Account row stays under it; the site pages are the Help
  menu's (§5.6), so they are not in Library on the Mac.
- **§7.5 No hints**, as iOS §7.5: every command is in the menu bar
  with its key, which is where a Mac person looks, so a tip would
  repeat a menu. No dismissal store, no "Show Tips Again".

## §8 Values

The rights line, the transcript label, and volume leveling are
§1.5's and are not reworded. No analytics, no third-party packages. The
credits, privacy, and take-down pages are the website's; the Help menu
links to them (§5.6).

## §9 Parity

Update `PARITY.md` in the same change set. A Core change moves the iOS,
macOS, and tvOS columns together, so build all three. No stub lives in
the Mac target.

## §10 Traps this codebase has already paid for

- **§10.1 Own the stores in the `App`'s `@State`** (`docs/iOS-DESIGN.md`
  §10.2); the Controls menu receives the same `AudioPlayer`, never a
  second one.
- **§10.2 Re-create the detail stack per section** (`.id`), or a path
  from one section is replayed into another's root.
- **§10.3 macOS `AVPlayerItem` has no `externalMetadata`**; the window
  title carries what is playing (template §B3d).

## §11 Deliberate inversions

- **§11.1 The player never replaces the window root.** The template's
  §B2a makes an immersive surface the root so a video's chrome is the
  only chrome; audio has no picture, so the Mac keeps the split view and
  adds a transport bar, as the Music app does. Do not "fix" this toward
  the template.
- **§11.2 Speed is our own menu, not the `AVPlayerView` HUD** (template
  §B3a), because there is no player view for audio to carry one.
- **§11.3 The transcript is a window**; iOS uses a sheet, tvOS a
  full-screen reader, Android a route, the web a closed section.
- **§11.4 A sidebar, not tabs.** iOS uses a tab bar that becomes a
  sidebar on iPad; tvOS a focus sidebar.
- **§11.5 Play never steals focus or opens a surface**, like iOS and
  unlike tvOS (`docs/tvOS-DESIGN.md` §6.2).
- **§11.6 Closing the main window keeps playing** (§2.4). Template §B13
  stops a window's playback because a video window IS its player; here
  the player is the app's and the window only browses, so the
  longer-lived owner wins, as `macos-platform-patterns` Rule 15 asks.
  Do not "fix" this toward the template.

## §12 Open (what the code does not yet meet)

- **No minimum size on the main window**; the template sets one so the
  transport bar never crushes the split view.
- **Every iOS §12 item that lives in shared code holds here too**: the
  queue and arc rule (the transport bar carries "Next story" on an arc's
  last part), the resume and "played" windows, the untitled fallback,
  uncounted facets, seasons as sections, the Detail series link as a
  third push, and the two explaining empty
  states. The queue verbs (iOS §12) are here as the right-click menu on
  an episode row, the Detail button, Library's Queue section (drag to
  reorder), and the Controls menu's "Add to Queue" / "Remove from Queue"
  for the episode now playing. Haptics are n/a on the Mac (the trackpad's feedback is the
  system's).
- **The Controls menu offers "Remove Download" for a failed download**,
  because it tests only that a record exists
  (`downloads.records[item.episode.id] != nil`).

Closed 2026-10-23: Play / Pause takes no bare key (§5.3), the Go and
Help menus (§5.5, §5.6), the closing rule (§2.4), Share (§5.7), and the
player's numbers named once (§5.4).

Bring the next change back to a rule here, or bring a new rule first.
