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
  *D3-4: the transport bar's tile is the grammar's `PictureWindow` (40 pt, the show's picture, else
  its star's, else the title block) and its text is the title over an `EventLine`.*
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
**R11f** Now Playing's people and Voices (D3-9; owner, 2026-10-30: *"It has to look good and use native design and apis on the given platform."*; the shared text, WEB-DESIGN §6.4f). Now Playing draws **On the air** (the credited performers as round faces, portrait else monogram, each opening the person) and **That night on the radio** (`CatalogDatabase.sameDay`, contract §3.3b: at most 12 other surviving broadcasts of the same air date, by network with unknown last, then series, then id; each a grammar row of show and network, Play, and a tap to the episode), each hidden when it has nothing. **Voices** is Browse's second scope (Shows, Voices, Ear dramas) and Home's "Most heard voices" rail with All: `CatalogDatabase.voices` behind a column-exists guard, round faces over the name and the episodes, each opening the person's page; a catalog without the table draws neither. The Mac has no Now Playing sheet: the transport bar's "On the air" button (person.2.wave.2) opens a popover with the two sections; a face or a row closes it and opens the page in the window.
**R11h** An episode opens its show, and a show says what it is (owner, 2026-11-09: episodes felt "totally disconnected from any recurring show"; "an entry point to know whether or not they should listen"). As iOS-DESIGN §4.3 and §4.4 in the Mac's idiom: Detail's head board is the link to the show, its name ending in a chevron; the transport bar's show name is a link (`.link` style) that opens the series page in the window, and the "On the air" popover leads with the show's row. The series page's meta line adds "With" the star; **About** (`series.about_text`) sits under the board at a 720 pt measure, four lines until More, the source line opening `about_url` in the default browser. "Read the script" (`episodes.script_url`, through `ScriptAccess.reading`) opens the source's page in the default browser, the source named under the button. Versions never say "Recording 2", and the unclaimed rights line is not drawn.

**R11e** Browse's A to Z jump (owner, 2026-10-30: *"We are building for each specific platform. It has to look good and use native design and apis on the given platform."*; *"Yes, add a letter jump"*): a row of letter buttons (`LetterRow`) under the decade field scrolls the List to a letter's section; the rest as iOS-DESIGN R11e.   **R11d** series and episode pages in direction D, as iOS-DESIGN R11d
  (WEB-DESIGN §6.4d): the head board, one button row that never wraps
  apart, On the air as round faces that lift on hover, Cast and credits
  folded; the toolbar keeps the series' download menu, the menu bar and
  keyboard commands are unchanged;
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
  whose title is the episode playing, or "Ear Drama" when nothing is. It opens
  at 1180 by 780 and stops at 920 by 560, so the transport bar never crushes
  the split view.
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

- **§3.1 Five sidebar sections, hard set** (Decision 075, owner
  2026-11-14: *"It is entirely unclear what the app is or how to use it
  easily"*): Home, Browse, Record, Search, Library, in `AppTab` order
  (`apple/Core/Store/AppStore.swift`), ⌘1 to ⌘5 in the Go menu (§5.5).
  Home is iOS-DESIGN §4.1 as a `WidePage` (§4.0a): On the air, Continue,
  the three doors as three equal buttons in one row, then the rule rows.
  **Stations** is pushed in Home's stack (On the air's All Stations, the
  Listen door) and **Surprise** by Home's toolbar button (⇧⌘S in the Go
  menu); neither is a sidebar section. **Record** is iOS-DESIGN §4.14 as
  a `WidePage`: Yours, Today's Scene, the plays under the chip bar, Made
  here. "Record This" beside Play on a play's page, or on an episode
  whose `script` is set, opens the production's window; Library still
  lists Ear dramas. A new section amends this rule first.
  - **Today's Scene and Made Here leading** (Decision 079): Home and Record
    take iOS-DESIGN §4.1's Today's Scene card and Made Here rule in the
    `WidePage`; Try a Line opens the production's window on the answering
    voice's first line (§4.5), Read the script's window (§4.7). Signed out,
    a second production asks for an account in a sheet, as iOS.
  - *Pending port* (2026-11-15 design review): the heading and the kicker of
    iOS-DESIGN's pending Home note.
  - *Replaced* (2026-11-14, Decision 075): "Six sidebar sections, hard
    set (Decision 068 ...): Home, Browse, Stations, Surprise, Search,
    Library ... ⌘1 to ⌘6 ... Plays are rows in Browse and Search".
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

- **§4.0a Pages are pages, lists are lists (R11h).** Home, a series, a person,
  and an episode are `WidePage`s on the Mac, never a `List` (Mac audit,
  2026-11-04: Home's tile grids drew one point tall). A macOS `List` row keeps the
  height of its first measure, so anything that learns its width after layout
  (`ShowGrid`) stays collapsed; a `ReadableColumn` around a `List` also clipped the
  toolbar's hairline and the scroller to the column. The head board and the rows
  share one left edge. Rows run two across at 700 pt and three at 1320 pt, each a
  phone's measure (iOS-DESIGN R11g); an episode's page keeps a 960 pt measure.
  Search is a `WidePage` too, its sections two across. Stations is a `WidePage` of
  two panes, the stations beside tonight's listing, stacked when narrow; Surprise's
  picks stand side by side as the window allows. Library stays a List.
  Automatic transcript is a page button in the episode's button row, and a
  recording is a row, not a button shape.
- **§4.0 Browse** is iOS's (`docs/iOS-DESIGN.md` §4.2): the same chips,
  "Sort: Popular" by default, in a `safeAreaBar` under the toolbar.
- **§4.1 The transcript opens a window** from Detail, the transport bar,
  or the Controls menu (§2.2), never a sheet.
- **§4.1r Home reads as one thing** (Decision 081, owner 2026-11-19: *"the home screen ... still reads like a long list of items that feel unrelated ... The goal is to have the home view feel more cohesive and inviting from the moment that you open the app."*; rulings: "Home: all of R3a §4.1", "label art C on every platform"). The shared rules are WEB-DESIGN §4.2r 1-8 and
  iOS-DESIGN §4.1r; the Mac differs only in being a `WidePage` (§4.0a): the hero spans the page's
  first column at tier L with the dial of genre stations under it, and rails keep the show tile's
  one window size at every window width (more tiles, never bigger ones). Built in Round 3 V6.
- **§4.2 Downloads** are the same background `URLSession`, the same
  series Download menu (in the toolbar), and the same Downloads place
  pushed from Library's row as iOS (`docs/iOS-DESIGN.md` §4.3, §4.6,
  §4.8); a row's Remove is on right-click. Library is iOS's list (§4.6, direction B, owner 2026-11-23): the same `List` with a `Picker(.segmented)`, Listening | Making, remembered (`ed.library.side`), the same Up next, Shows you follow (right-click a tile for Unfollow), History and Downloads lines, Productions grouped by play (a production opens in its own window), Classes, and the foot "Account and preferences" (Account, Voices disclosed in place, Export my data, About Ear Drama, whose Credits, Privacy and Take-down requests are `Link`s here as well as in the Help menu); an empty part is absent, with no header or caption. A download is played, never
  exported.
- **D3-8** (D3-8, 2026-10-30) Stations, Surprise, Search's people and a person's page follow WEB-DESIGN §6.4f in this platform's idiom: the same views as iOS-DESIGN's D3-8 note, in the detail column at the readable measure; hover and the pointer are the platform's own.
- **§4.3g Item pages wear Home's hero** (Decision 081, Round 3 V7; owner, 2026-11-19: *"We need to continue making the app more visually appealing, both from the home screen perspective ... and the individual item perspective."*). As iOS-DESIGN §4.3g in the Mac's idiom: the same
  `ItemHeadBoard` heads a series, episode, person, play and ear drama page inside the `WidePage`, always at the 320 pt
  beside-the-words column (a window is never narrower than 560 pt) or, for a wide picture, as a plate; the buttons sit under the
  board, not on it; the gallery row is 200 pt tall and scrolls with the trackpad; a caption's credit opens the evidence in the
  default browser.
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
  prominent; recording needs no account (Decision 079; *replaced*
  2026-11-15: "Start Recording needs an account and offers the same
  sign-in buttons in the window"), and a production left with no take is
  deleted when its window closes (PLAYS-DESIGN §2.3 rule 3a); Listen Through runs live at any time;
  Export appears whenever the play is complete.
- **§4.5b Making a part** is `docs/iOS-DESIGN.md` §4.12b (D3-6; owner ruling 4,
  quoted there) in the production's window: the same head board, part cards,
  three modes and native segmented control. The window is wide, so the scene
  stands between the left rail "In this scene" and the right rail with this
  line's aids and the keys. Keys (the Recording menu, kept as `.commands` and
  `FocusedValues`): Space records, stops or pauses a run; Return keeps (Keep N
  takes in a run's review); R records again; up and down arrows (left and right
  in the dock) move by line, and in Line by line the selection. Run-up keeps
  Shift-Command-R. Nothing opens the microphone at launch.
- **§4.5c The voices on the cast sheet** is `docs/iOS-DESIGN.md` §4.12c (Decision
  076 S2; PLAYS-DESIGN §2.8) in the production's window: the voice is a pop-up
  `Menu` in each part's row (the voices by quality, then "Not read" for directions and
  sound) with "Voice Settings…" opening an inspector popover (Speed and Pitch
  `Stepper`s, each voice's Hear button reading the part's first line). The footer's
  path is System Settings > Accessibility > Read & Speak (or Spoken Content) >
  System Voice > Manage Voices; the footer's **Open Settings** opens
  `x-apple.systempreferences:com.apple.Accessibility-Settings.extension` (the
  Accessibility pane; the pane's own name and an anchor to Spoken Content are
  UNVERIFIED on macOS 26, R2 §2.7). Built 2026-11-14 (PARITY 🚧): the chip is a `Menu`
  in the part card, "Voice Settings..." opens the picker `Form` in a popover.
  **Downloaded** (Kokoro, S6e; `docs/iOS-DESIGN.md` §4.12c's paragraph is the shared
  text): the popover `Form` carries the same "Downloaded" section (Download Voices with its
  size, progress and Cancel, the 28 voices with Hear buttons, Delete Downloaded Voices, the
  attribution footer), and the row's pop-up `Menu` lists the downloaded voices after the
  system ones once they are here. Same engine and flag as iOS; the Mac bench is the same door
  (`APP_KOKORO_BENCH=1` in the launch environment).
- **§4.5a A shared ear drama** is `docs/iOS-DESIGN.md` §4.12a (PLAYS-DESIGN
  §11.7, binding: the same verbs and words on every platform) in the
  production's window: Share, Invite, Upload, and People sit in the cast
  sheet's sidebar above the parts (Publish joins them only when the consent
  screen ships, Decision 072); a part's Done with This Part, Release, and
  Open Part are in its row's menu and on right-click; People is a sheet on
  the window. Coming back to the app re-reads the record. The invitation shows in
  Library's Ear dramas in the main window, and Open or Take Part opens
  the production's own window.
- **§4.7a Read along** (PLAYS-DESIGN §2.11, rewritten 2026-11-23; iOS-DESIGN §4.15a is the same view and
  model): the production window's Read along is the reader reading along at once; the word heard is marked in
  the speaker's hue and the pages turn themselves; the transport is the reader's bottom bar with words (the
  speaker, Previous Line, Play or Pause, Next Line, the Speed menu, Stop, the page count). **Keys**: Space plays
  and pauses (the Reader menu's Turn Page gives Space up while a read-along transport shows), Option-Left and
  Option-Right step a line; the arrows still turn pages, which stops the turning, and **Back to the Line** (in the
  bar's place above the transport) returns. A finished ear drama's page opens the same window on the library's
  script (`StudioTarget.drama`), the item's line files as the transport (PLAYS-DESIGN §2.11 rule 11).
- **§4.7 The script reader** (Decision 076 S1; PLAYS-DESIGN §2.7 binding on
  the verbs; `docs/iOS-DESIGN.md` §4.15 for the shared SwiftUI view; port spec
  `docs/research/design/R2-reader-port-brief.md`). **Read** on a play's page,
  Today's Scene and each Record tile opens the script in **its own window**
  (`WindowGroup(for: ScriptReaderID.self)`, one per script, restored with the
  window), never a sheet: a Mac reads in a resizable window. A `NavigationSplitView`
  with **Contents** as the sidebar (acts with their scenes, the one holding the
  position selected; toggle with the standard sidebar button) and the pages as
  the detail; the toolbar carries **I'm Playing** (a `Picker`), Next Line, Hide
  My Lines, Search (`.searchable` in the toolbar, results as a popover list) and
  Text (a popover: size, spacing, Pages / Scroll).
  - **Pages by default**, two facing pages once the detail is 860 pt wide or
    more (most windows), one when narrower; a slide on turn. Keys through a
    **Reader** menu (`.commands`, `FocusedValues`): → ← ↓ ↑, Page Down/Up,
    Space and Shift-Space, Home and End, J and K for my next and previous line,
    ⌘F Search, ⌘+ and ⌘− text size, ⌘0 the default size; a trackpad two-finger
    swipe turns; a click on the outer fifth of a page turns. **Scroll** is a
    setting.
  - The position is a line id per script in `UserDefaults`, kept through
    window resizes and text size changes (re-paginate, return to the line).
  - The studio (S3) becomes the window's `.inspector`; the reader is the same.
    Specified 2026-11-14 (PLAYS-DESIGN §2.9; port spec
    `docs/research/design/R2-studio-port-brief.md`): a production's part opens
    the reader window with the studio attached; the **inspector** (`.inspector`,
    toggle ⌥⌘I, 320-380 pt) holds the mode `Picker(.segmented)`, the transport
    (Previous, record, Next, Listen From Here; 2026-11-15) with the status line
    (Again in Run Through for a line holding a take) and level meter, the dashed
    device-voice ring and voice name after each other part's name on the page (a
    click opens that part's voice picker; PLAYS-DESIGN §2.9 rule 3a), the current
    line's take list (a `List`: play, With Cue, choose, Delete on unchosen takes,
    Record Again), the cast with voices, Listen Through From Here, Delete Unused
    Takes (confirmation with the count) and Done With This Part. A **Recording**
    menu carries every key (Space record / stop, J / K my lines, R again,
    Return keep, ⌥⌘I the inspector). Each of my lines shows its take state after
    the name, clickable. A window too narrow for inspector and page shows the
    inspector over the page (the system's own behavior).
  - **The page is the Ear Drama page** (PLAYS-DESIGN §2.7 rule 10; iOS-DESIGN
    §4.15 for the shared TextKit set-up). Most Mac windows give a page of 30 em
    or more, so the speaker's name sits in the right-aligned gutter; a narrow
    window stacks it over the words. Text size changes (⌘+ ⌘−) re-evaluate the
    gutter with the re-pagination.
  - **Marks** (Decision 076 S5; PLAYS-DESIGN §2.10 binding; the shared Core and
    drawing are iOS-DESIGN §4.15 "Marks"; port spec
    `docs/research/design/R2-marks-port-brief.md`). A drag selects words with the
    pointer; a **Marks** menu (`.commands`) carries Highlight ⌘⇧H, Underline ⌘U,
    Breath ⌘/, Pause ⌘⇧/, Beat ⌘⇧B, Note ⌘⇧N and Show Marks ⌘⇧M (a Mac takes no
    bare letter keys in a document window: they would type), and the same six sit
    in the selection's context menu (right-click), with the four hues as a
    submenu of Highlight. A click on a mark opens a small popover (`.popover`) with
    the hues or the label or the note, and Delete; ⌘Z undoes a delete
    (`UndoManager`). The notebook is a second sidebar section under Contents
    (**Marks**, in script order, a click going to the line; **Not Placed** after
    it), so it sits beside the pages instead of over them. Pencil ink from an
    iPad draws read-only at its line; the Mac makes no ink (ink is ⏳ on every Apple
    platform for now). As shipped: a drag selects by characters and is grown to whole
    words when let go, a double-click selects a word, the notebook sits under the
    Contents in the sidebar, the same `MarkSelecting` / `MarkPopover` as iOS-DESIGN
    §4.15's "As shipped" bullet.

- **§4.9 Reading together** (T4, 2026-11-19; the same views as iOS-DESIGN §4.19, "native look per platform"). Binding rule: PLAYS-DESIGN §12 and Decision 082. The verbs are the web's (WEB-DESIGN §4.17 to §4.19): join a room by code (`eardrama://read/CODE`, its https twin, or the code typed); a class room asks for the class code, then lists the names (a seat's key is held in memory for the app run only, owner 2026-11-19: a shared device keeps nothing at rest); the reader follows the lit line (my lines tinted, "Next: you, in N lines", "Back to the Line" after a scroll, "Hide My Lines" in Rehearse, no sound on a reader device); the leader moves it with Back, Next and Again (arrow keys on a keyboard) and a Reading menu: mode, Lock Joining, Read Open Parts (a message to the room that the screen obeys), Open the Screen, End. A waiting room says "Waiting for <the leader's name>" (the name travels in the snapshot). The teacher's class page: the code behind Show Code, Start a Reading, seats (paste a list, Release, Remove), plays with per-seat counts, and the casting board (parts largest first with lines, words, scenes, longest; Fill Evenly, Split by Scene, Clear, Save). Refusals and warnings use `ReadCore.refusal`'s words, one line, never an explanation. A Mac keeps the class page in the window it opened in; **Open the Screen** opens a second window (`ReadScreenWindow_macOS`) meant for the projector. Arrow keys move the cursor for the leader; the Reading menu's items live in the toolbar, and menu-bar commands for them are NOT built yet (SCRATCHPAD).
- **§4.10 Your Parts and Relay across time** (T6, 2026-11-19; the same views as iOS-DESIGN §4.20, "native look per platform"). The Mac's Your Parts is a pushed page in the Library's stack with the same rows; the class page in its window holds the pickup while it is open, so a teacher's Mac receives at-home takes with the window open. No menu-bar command is built (SCRATCHPAD). Free plan (2026-11-23, PLAYS-DESIGN §12.11 item 4): the class page's pickup runs only while the scene is active, stops after 30 minutes with no take and shows **Keep receiving takes** (a `Button` in the list's first section); a backgrounded app makes no retry ask.
- **§4.9a The room inside the reader, Record in the room, Add a Screen (T5, 2026-11-19; same views as iOS-DESIGN §4.19a).** The room is the reader (`ScriptReaderView(room:)`) in the window it was opened in, without the Contents sidebar; the room bar sits under the page with the Reading menu in it (T4's plain list is gone). The Record row, the Takes sheet (a 460 by 560 sheet), Publish Under My Name and the leader's **Add a Screen** (a small sheet that takes the code a TV shows, any case, spaces allowed) are iOS's, with the arrow keys still moving the cursor for the leader. **Open the Screen** still opens the second window for a projector. **Menu-bar commands for the Reading menu are NOT added** (the Reading menu stays in the room bar; a Reading command menu is listed in SCRATCHPAD). The microphone is asked for at Start Recording; the Mac needs no headphones gate.

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

- **§6.r The label is the default art** (Decision 081; the shared rule is WEB-DESIGN §6.4r, R3a
  §3.4). Wherever this doc names the typographic card, the title block or the initial as the art
  of something without a picture, that art is now **the label**: a flat transcription disc drawn
  natively (SwiftUI `Canvas`) from the same `labelSpec` goldens as the web (`cross-platform-determinism`):
  genre board, a run arc on the 1930-1962 dial, the monogram or the episode's date on the label,
  network · decade on the rim at tier L from `series.network`; a finished ear drama's part-hue rim;
  a person's groove ring; a play's script page with voice-band rules. A picture that passes the
  size floor always wins, and the two never share an object's slot. Networks and sponsors are names
  in our type, never logos; user-made ear dramas never take an uploaded picture. Now Playing in Control Center shows the episode's label. Built in
  Round 3 V4.

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

**R14 Dates and recordings never show raw archive text** (owner, 2026-10-31: *"We want to be both unambiguous and well designed. Spelling out the month (or abbreviating it for space) is far better."*; AGENTS.md: raw upload text never shows). `AirDate.medium` is the one formatter for rows and event lines ("Sep 17, 1949", "Sep 1949", "1949"); `AirDate.display` the long form for Detail. Recordings are named by `RecordingLabel` (`recordings.label` behind a column-exists guard, else "Recording N", best copy marked); the archive.org identifier never renders. Shared with iOS; `AirDateTests` holds both rules.

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

**E1 rules (2026-10-30, D4 review).** The transport bar carries Add to queue and Share as borderless icon buttons before "On the air"; the Controls menu carries Share Episode beside Add to Queue. Stations after the evening ends: Tonight's button reads Replay. Account carries the Export section (docs/EXPORT.md), shared with iOS.

Bring the next change back to a rule here, or bring a new rule first.

- **Student privacy on the class page** (Decision 084, 2026-11-21; PLAYS-DESIGN §12.12, binding; `apple/Shared/ClassPrivacyViews.swift`). The class page closes with a **Class** section: **Ends {date}**, a compact date picker (today to 400 days) with **Change date**, **Export class** (the save panel), and **Delete class** (destructive confirmation). An under-13 class without school consent opens with **School approval**. The age question is a sheet with a year picker and no default before a first Share, Invite, Take Part or Publish; only the boolean is kept (`UserDefaults` `ed.over13`).
