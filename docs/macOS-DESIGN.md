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
  on Detail; **R11** typographic rows; **R12** brand is chrome only;
  **R13** shelves by rule from the catalog.
- **R15 and Decision 061**: `LoudnessLevel.volume` cuts to -21 LUFS,
  peak-clamped, never boosted, default copy only.
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

- **§3.1 Six sidebar sections, hard set**: Listen, Series, Radio,
  Plays, Search, Library, in `AppTab` order
  (`apple/Core/Store/AppStore.swift`), so Radio follows Series as on the
  web and is ⌘3 in the Go menu (§5.5). A new section amends this rule
  first.
- **§3.2 One `NavigationSplitView`.** The sidebar is a selectable `List`
  of the sections (180 to 210 pt); the detail column is one
  `NavigationStack` bound to the selected section's path and re-created
  per section (`.id(store.selectedTab)`), so each section keeps its own
  path. Every stack applies the shared `routeDestinations()` registry.
- **§3.3 Search lives in the toolbar** (`.searchable(placement:
  .toolbar)`), over the shared `SearchResultsList`.
- **§3.4 Everything external lands in the inbox**, drained by `RootView`
  (the same rule as iOS §3.5).

## §4 Surfaces

The four screens are iOS's (`apple/Shared/ListScreens.swift`); a List on
the Mac is already a Mac list, with context menus on right-click. What
each holds is `docs/iOS-DESIGN.md` §4.1 to §4.6, and the Mac differs
only here:

- **§4.1 The transcript opens a window** from Detail, the transport bar,
  or the Controls menu (§2.2), never a sheet.
- **§4.2 Downloads** are the same background `URLSession` and the same
  Library section as iOS; a download is played, never exported.
- **§4.3 Radio** is iOS's `RadioScreen` (`docs/iOS-DESIGN.md` §4.9) in
  the detail column: the same slots, times, gaps, and Listen live on the
  one `LiveRadio`. A slot's Play is a borderless button the pointer
  reaches without opening the episode; the listing's credit is a link
  the default browser opens. Space pauses as anywhere (§5.3), and a
  pause ends listening live.
- **§4.4 The account is Library's last row**, as on iOS
  (`docs/iOS-DESIGN.md` §4.10), pushed in the detail column: not a
  Settings scene (§2.3 holds; an account is not a preference) and not a
  menu item. Sign in with Google opens the system's web authentication
  sheet (`ASWebAuthenticationSession`, PKCE, no third-party package).

## §5 The player

- **§5.1 One engine,** the shared `AudioPlayer`. The Mac has no audio
  session, so it sets `MPNowPlayingInfoCenter.playbackState` itself and
  the system's Now Playing menu-bar item and media keys follow.
- **§5.2 The transport is a bar along the window's bottom edge**
  (`TransportBar_macOS`), shown while an episode is loaded: title,
  series and date, back 15 s, Play, forward 30 s, the scrubber with
  elapsed and remaining time, speed, the sleep timer, and the
  transcript button. Errors, or the offline warning, sit under it.
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
  Multicolor (a chosen system accent wins, as the Mac intends); red
  only on Play, Listen live, Start recording, the scrubber, and the
  progress line; genre hues only as the series row's genre mark.
- **§6.2 Six type levels** (`TypeRamp`) over the system text styles.
- **§6.3 Icons are SF Symbols**; every icon-only button has a `.help`
  tooltip and an accessibility label.

## §7 States and accessibility

- **§7.1 The four states** are iOS's (`docs/iOS-DESIGN.md` §7.1):
  skeleton rows, `ContentUnavailableView`, `CatalogUnavailableView`
  with Try Again, and no retry where retrying cannot help.
- **§7.2 Offline** shows on Detail and the transport bar only when the
  episode is not downloaded; the transcript window says "You are
  offline." and retries when the network returns.
- **§7.3 VoiceOver and the keyboard.** Labels and values on every
  control; every command reachable from the menu bar, so the app is
  usable without the pointer.

## §8 Values

The rights line, the transcript label, and loudness by cutting are
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
  queue rule, the resume and "played" windows, the untitled fallback,
  uncounted facets, seasons as sections, the Detail series link as a
  third push, no Queue or Following, and the two explaining empty
  states. Haptics are n/a on the Mac (the trackpad's feedback is the
  system's).
- **The Controls menu offers "Remove Download" for a failed download**,
  because it tests only that a record exists
  (`downloads.records[item.episode.id] != nil`).

Closed 2026-10-23: Play / Pause takes no bare key (§5.3), the Go and
Help menus (§5.5, §5.6), the closing rule (§2.4), Share (§5.7), and the
player's numbers named once (§5.4).

Bring the next change back to a rule here, or bring a new rule first.
