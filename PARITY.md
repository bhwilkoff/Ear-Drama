# Ear Drama: Cross-Platform Feature Parity

> **Single source of truth** for what's shipping where. Updated in
> the SAME change set as any user-facing feature.
>
> Companion to `AGENTS.md` (project context), `SCRATCHPAD.md` (active
> milestone), `DECISIONS.md` (architecture decisions). Per-platform
> design rules live in `iOS-DESIGN.md` (iOS), `macOS-DESIGN.md` (macOS),
> `tvOS-DESIGN.md` (tvOS), `WEB-DESIGN.md` (web), `ANDROID-DESIGN.md`
> (Android) when those binding docs exist. The full workflow
> (including the periodic parity audit) is the
> `cross-platform-parity-discipline` skill.

Base platforms: **web · iOS/iPadOS · macOS · tvOS · Android.** The three
Apple platforms (iOS · macOS · tvOS) are adjacent in every table because
they share one Swift Core. A Core change usually moves all three columns
at once, so verify each still builds.

Extended surfaces, added as COLUMNS when adopted (each is a form factor
of an existing build, not a new codebase; see Decision 028): **Android TV /
Fire TV** (the Android app's TV form factor) and **Web-TV** (webOS /
Tizen / Cast, the web app's additive TV layer). **Windows** (Decision
029) is an optional sixth full platform with its own column and its own
authoritative parity doc (`docs/windows/` pattern: a WINDOWS-PARITY.md
mirroring this file's rows). A feature that ships on phone/desktop but
not its TV form factor gets ⏳ with a reason, never silence. The
recurring audit finding is parity that lands on new platforms without
returning to the platform it started on.

> **Last audit: 2026-10-28 (batch P1)**: every cell checked against the code
> on main and the device evidence in `AUTONOMOUS_PROGRESS.md` (ticks 86 to
> 98). ✅ now means seen working on a device, and the cell names the test and
> date. iOS cells covered by the iPhone 12 tap tier (`apple/UITests`, 17/17 on
> 2026-10-28, tick 97) read ✅; ✅ cells without device evidence (Universal
> Links, the site links, the commercial parts) went back to 🚧. Links were
> ⏳ on the apps though `DeepLink` routes them on Apple and Android. New rows:
> search by air date, search by transcript, sponsor, never recommended,
> follow a series, background and lock-screen play, another speaker.
> Previous audit 2026-10-22 (tick 30) replaced the template's sample rows.

---

## 0. Platform set

**1.0 is the core five at one feature set** (Decision 056): web, iOS/iPadOS,
macOS, tvOS, and Android. The **web leads**: it is the landing twin for every
share link and the fastest to see, and the natives mirror it. tvOS earns its
place because listening is lean-back; macOS shares the Apple Core.

**Stubs at 1.0, built out after the core five** (Decision 056): CarPlay,
Android Auto, Android TV / Fire TV, Roku, webOS / Tizen, watchOS, and Wear OS.
Each is a target that builds and launches, ⏳ in every row until then.
Windows is 🔮: not in the owner's set for 1.0.

---

## Legend

- ✅ **Verified**: seen working on a real device of this platform (or live
  in production), and the cell or Notes name the evidence: a committed
  device test and the date it passed, or a progress-log tick
- 🚧 **Built, not verified**: in main (or being built), not yet seen
  working on a device of this platform
- ⏳ **Planned**: committed; targeted for an upcoming milestone
- 🔮 **Future**: agreed direction; no timeline yet
- 🚫 **Out of scope**: explicitly not built on this platform (with reason)
- n/a: platform-inapplicable (e.g., lock-screen controls on tvOS)

n/a and 🚫 are different claims. n/a means the verb does not apply to
this platform at all. 🚫 means it could apply and we chose not to build
it, and the Notes say why.

A ⏳ or 🚫 cell carries its reason in Notes. "Deliberately deferred,
because X" is a healthy cell; a silent blank is drift.

---

## Parity rule

When shipping any user-facing feature:

1. **Confirm the verb is identical across platforms.**
   Find = explore, Profile = identify, etc. Don't let one platform
   own a different verb for the same surface.
2. **Pick the native idiom per platform**: `<dialog showModal>` on
   web, `.sheet` on iOS, `NavigationSplitView` + AppKit on macOS,
   focus-driven full-screen on tvOS, `ModalBottomSheet` on Android.
   *Same verb, native idiom.* An inversion of another platform's rule
   (e.g. `.buttonStyle(.plain)` is wrong on tvOS but correct on
   iOS/macOS) is deliberate. Never harmonize it away.
3. **Update this table** in the SAME PR. Drift here is what causes
   "the web has X but iOS doesn't" complaints six months later.
4. **Cross-link to the binding design doc** for each platform that
   has one.

---

## 1. Top-level navigation

| Verb | Web | iOS | macOS | tvOS | Android | Notes |
|---|---|---|---|---|---|---|
| Shell: Home · Browse · Stations · Surprise · Search · Library (Decision 068) | 🚧 six in the nav; old `?view=listen/series/radio/plays` rewritten to the new names | ✅ iPhone five tabs, Surprise from Home's toolbar: `TabSmokeUITests` on iPhone 12, 2026-10-28; iPad sidebar not seen on a device | 🚧 six sidebar sections, ⌘1 to ⌘6 | 🚧 six sidebar entries | 🚧 five tabs, Surprise from Home's top bar | Archive Watch's placement per platform; sections are verbs, never content types. Doors take the new names and still read the old |
| Home (Continue, shelves by rule) | 🚧 Continue, Following, the day board (stacked years strip, a radio group: tap or arrow keys pick a year), that night's show tiles, Most downloaded tiles with All N shows (D3-2, WEB-DESIGN §6.4c); Most heard voices not built (no published list); New ear dramas shelf (D3-7); seen in headless Chrome at 375 and 1440 px, light and dark, against the live projection, 2026-10-30 | 🚧 Continue, Following, the day board (years strip, tap a year), that night's show tiles, Most downloaded tiles with All N shows (D3-2, R11c); Most heard voices not built (no published list); New ear dramas shelf (D3-7); builds green and rules golden-tested, not yet seen on screen | 🚧 same on the Mac (hover on tiles); not yet seen on screen | 🚧 same, the strip not focusable (shows the peak year), tile shelves with `.card` focus; not yet seen on screen | 🚧 Continue, Following, the day board (stacked years strip, tap a year), that night's show tiles, Most downloaded tiles with All N shows (D3-2, R11c); Most heard voices not built; New ear dramas shelf (D3-7); Robolectric renders light and dark, not on a device | Was Listen. Decision 058; R13 lists from data. Every client draws the published `listenShelves` in order (contract §5.1). No Most episodes (HUMAN-SHAPED B). Roku still reads `index/listen.json` |
| Never recommended, always findable (`no_recommend`: Nazi-state recordings, racist caricature, archive.org's deemphasize) | 🚧 shelves, days, and Surprise are built with `recommendAnd` | 🚧 `CatalogDatabase` skips the flag on every choosing surface | 🚧 same Core | 🚧 same Core | 🚧 `RECOMMEND_AND` in `CatalogDatabase.kt` | catalog DECISIONS 013 (tick 98). Search and the series page still find them. The 1,137-row rule reaches clients with the next published catalog; no device has shown it |
| Browse (series and plays together; kind, genre, decade, network, has a script; Sort, Popular by default) | 🚧 selects incl. Kind and Has a script (the checkbox is a bordered control like the selects); count line with a single-recordings link, decade by genre field (beside the grid from 1024 px), show-tile grid, sort-named heading (A to Z); plays as title-block tiles; seen in headless Chrome, 2026-10-30 | 🚧 chip row (Has a script is a capsule like the rest); count line with a single-recordings link, decade by genre field (beside the grid at regular width), show-tile grid in pages of 60, sort-named heading (A to Z); plays as title-block tiles (D3-2, R11c); `BrowseUITests` predate the grid and need a rerun; not yet seen on screen | 🚧 same, field beside the grid | 🚧 Genre and Sort pickers, the field (a cell sets genre and decade, Clear resets), count line, tile grid; no plays (TV records nothing), no Decade or Network menus | 🚧 chips incl. Kind and Has a script (a FilterChip like the rest); count line with a single-recordings link, decade by genre field (beside the grid from 840 dp), show-tile grid, sort-named heading (A to Z); plays as title-block tiles (not on TV); Robolectric renders, not on a device | Was Series. Plays have no genre, decade, or network, so those narrow to series; Has a script keeps plays and series with an episode whose `script` is set (contract §3.1); no episode is linked yet. Sort: Popular (`series.downloads`, contract §3.3; uncounted rows and plays after the counted, by name), A to Z, Most episodes, Oldest first, on every platform; the TV's is a picker |
| Stations (evenings and genre stations on one clock) | 🚧 stations row (Tonight, then genre stations from `stations.json`), Listen live | 🚧 stations row; Tonight; Listen live; device-checked on iPhone 12, 2026-10-27 | 🚧 stations row; Tonight | 🚧 stations shelf of cards, first focused; Tonight | 🚧 stations row; Tonight; Listen live; TV focus stops | Was Radio. Gaps stated, never filled (R9); floor 0.25 provisional (owner, SCRATCHPAD 4) |
| Surprise (a random episode, evening, and play; one tap) | 🚧 `?view=surprise` | 🚧 push from Home; iPad sidebar; device-checked on iPhone 12, 2026-10-27 | 🚧 sidebar | 🚧 sidebar; no play | 🚧 Home top bar; no play on TV | Platform random, no cross-platform determinism; an evening plays its first surviving slot from the start, never a queue |
| A person's page (`withPerson`): every served episode crediting them, by series, roles on each row, oldest or newest first; credits on Detail link to it; People in Search | 🚧 `?person=`, `/person/{id}` twin, segmented order, `people/` shards and `search/people/` files | ✅ `PersonScreen`, toolbar order Menu, credit rows push; a Detail credit opens it: `DetailUITests` on iPhone 12, 2026-10-28 | 🚧 same screen in the detail column | 🚧 `PersonScreen_tvOS`, order button, credits a focus section of links | 🚧 `PersonScreen`, segmented order, credit rows open it | Facts only (name, years, episode count, portrait when served); no bio. Web people search reads the projection; Apple and Android scan `people` natively. The order Menu not tapped on a device |
| Search (titles, series, people, plays) | 🚧 word-prefix titles, people, plays | 🚧 FTS5 word-prefix; plays; the screen drawn on iPhone 12 (`TabSmokeUITests`, 2026-10-28), no typed query in a committed test | 🚧 the same `SearchResultsList` | 🚧 FTS5 | 🚧 FTS5 word-prefix; plays (not on TV) | Plays are never searched on a TV (it records nothing) |
| Search by air date ("1954", "August 1954", "8/2/1954"; an Aired section) | 🚧 `search/dates/` | ✅ `SearchUITests`: `eardrama://search?q=gangbusters+august+1954` draws Aired with 1954-08-02, iPhone 12, 2026-10-28 (tick 97) | 🚧 same code | 🚧 same code | 🚧 `DateQuery.kt` | One parse on every platform, held by `catalog/tests/golden/search_text.json` |
| Search by transcript (an Automatic transcript section with a line from archive.org's text) | 🚧 `search/said/`; 375 px frame read 2026-10-27 ("zeppelin", tick 96) | 🚧 `SearchUITests.testTranscriptWordListsTheLineSaid` ("zeppelin") and a typed-title test written, not yet run on a device | 🚧 same code | 🚧 same code | 🚧 not seen on a device | Only transcripts past the gate are searched (catalog DECISIONS 012); the snippet is cut on the device, never shipped |
| Library (followed series, queue, downloads, history, ear dramas) | 🚧 device-local; Continue, Queue, Following (show tiles), History, Ear dramas; each empty section says what it would hold; no downloads (Decision 071); `tools/web_fit_library.py` at 320 to 430 px, light and dark, 2026-10-30 | 🚧 D3-5: Continue, Queue, Following (show tiles; long-press Unfollow), History, Downloads row, Ear dramas, each header with an empty caption; built, not seen on screen; Queue and Downloads were tapped on iPhone 12 before the reorder (`QueueUITests` updated, `DownloadsPlaceUITests`, 2026-10-28) | 🚧 same as iOS | 🚧 Continue, Queue, Following (a tile shelf, `.card` focus), shared Ear dramas; no History or Downloads; built, not seen | 🚧 D3-5: Continue, Queue, Following (tile shelf; long-press Unfollow), History, Downloads, Ear dramas (not on TV), each with an empty caption; `GrammarRenderTest` light and dark; not on a device | Device-local until sync (M5) |
| Follow a series (Follow and Following on the series page; a Following list) | 🚧 series page button; Following on Home and in Library | 🚧 Follow / Following in the series toolbar (`FollowButton`), selection haptic; Following on Home and in Library; `FollowUITests` | 🚧 same toolbar button; Home and Library | 🚧 first focus stop on the series page; Following shelf on Home and in Library | 🚧 series page button (`SeriesScreen.kt`) with the selection haptic; Following on Home and in Library | Device-local until sync (M5); one store sync carries (Decision 057) |
| Start an ear drama (any page whose record carries a script) | 🚧 a play's page; an episode whose `script` is set (fixture-verified) | 🚧 a play's page; a linked episode | 🚧 a play's page or a linked episode, opens its window | n/a | 🚧 a play's page; a linked episode (not on TV) | Decision 068: `episodes.script` links only castable bundled scripts (`episode_scripts.py`). 2026-10-24: 0 linked; 616 served episodes match a Generic Radio Workshop script and wait on GRW's permission, and even then each needs its own work-layer evidence |

---

## 2. Listening

| Feature | Web | iOS | macOS | tvOS | Android | Notes |
|---|---|---|---|---|---|---|
| Show art: star portraits, typographic card, lock-screen artwork; faces lead (R11a, 2026-10-28) | 🚧 56 px tiles on mixed rows, series rows, play rows, Stations' rows and aired slots; the face in a box of its own shape on the series page, Detail and a person's page (an upright one the print beside the heading, a wide one the plate above it; no wash, 2026-10-28 V3); a faceless series page's head drawn as its card; Now Playing's box shrinks to the picture; Media Session. Seen in headless Chrome at 375 and 1440 px, light and dark, tall, square and wide, 2026-10-28 | 🚧 56 pt tiles (mixed rows, play rows, aired slots); `FaceHero` print or plate on series, Detail, person; Now Playing's box shrinks to the picture inside 44 % of the sheet; `MPMediaItemArtwork`. `ShowArtUITests` written, not yet run on a device | 🚧 same print or plate (276 x 240 pt bound); rows keep 40 pt; transport-bar tile. Offline AppKit render of the real views, 2026-10-28 | 🚧 card tiles, Detail and series faces, cast grid, Detail and series faces at their own aspect, 400 pt Now Playing bound; Top Shelf faces | 🚧 56 dp tiles (mixed rows, play rows, aired slots); `FaceHero` print or plate; Now Playing's box shrinks to the picture (44 % of the screen). Not rendered (no Compose preview harness); Media3 `artworkUri` / card PNG | Decision 069, contract §3.3a: dated matches' own P18 portraits are the only served art (LoC, Smithsonian, magazine photos wait on the owner's V2 to V5); CC credits shown with the face or in Detail's credits; the shape is the projection's width and height (contract §3.3); small crops (tiles, cast faces, the Apple lock screen's square) center on the published face box, a wide picture with none left uncropped (V4, 2026-10-28; Top Shelf and Media3 hand the system a URL it crops itself). Commons steps 120, 330, 500, 960. Native series heads stay the system title (no card band); Stations' station rows carry the tile on the web only (the native station row has no series face). No device check yet |
| Episode detail (date, network, cast, versions, rights line) | 🚧 | 🚧 credits and Versions drawn on iPhone 12 (`DetailUITests`, 2026-10-28) | 🚧 | 🚧 | 🚧 | Unclaimed reads "no claim known; removed on request", never public domain |
| Sponsor on Detail (the dated run covering the air date) | 🚧 on the facts line; no served episode has one yet | 🚧 `ListScreens.swift` reads `episodes.sponsor` | 🚧 same | 🚧 `ContentView_tvOS.swift` | 🚧 on the facts line (`Components.kt`) | Computed once in the pipeline (`catalog/tools/sponsors.py`, contract §3.1): never "Sustained"/"Multi"/"Syndicated", nothing when no dated run covers it. The web gate serves clean rows only and none has a run (0 of 15,125 on the 2026-10-22 build), so the web line stays empty until the unclaimed gate opens. Not seen on any device: the clients read the column from the next published catalog (tick 95) |
| One grammar for every level of content (WEB-DESIGN §6.4b, R11b; D3-1, owner 2026-10-29): the window (the series' `picture` cropped, whole, or the outlined title block), the show tile, the 64 px row with its date block or window, the event line, the run strip, the head board | 🚧 `showTile`, `episodeRow`/`seriesRow`/`playRow`, `dateBlock`, `titleBlock`, `runStrip`, `eventLine`, `headBoard` (built, not on a page) in `js/app.js`; Following draws tiles, Browse, Search, Library and every episode list draw rows; seen in headless Chrome at 375 and 1440 px, light and dark, against the live projection, 2026-10-30 | 🚧 `apple/Shared/Grammar.swift`: Following tiles on Home, `GrammarRow` in Browse, Search, Library, series and person lists; built, 219 tests green; not yet seen on screen | 🚧 same components; built; not yet seen on screen | 🚧 same components at ten-foot sizes, `.card` focus on the whole tile; built; not yet seen on screen | 🚧 `ui/Grammar.kt`: Following tiles (`ShowShelf`), `GrammarRow` in every list; Robolectric renders light and dark, phone and TV, 2026-10-30; not on a device | Rules golden-tested in all three languages (monogram, block size, type step, window fill, event line, run span, grade). Two contract follow-ups: the projection does not publish `art.grade`, so every client applies the identity levels after the monochrome; and it carries no per-year episode counts, so the run strip is the first-to-last span. Home's catalog shelves are episode shelves, so tiles show where series are listed (Following). The head board is adopted by the series and episode pages (D3-3, next row). No device check |
| Series and episode pages in direction D (WEB-DESIGN §6.4d, R11d; D3-3, owner 2026-10-29): the head board on both, one button row that never wraps apart, the episode's event line, On the air, Cast and credits folded | 🚧 `renderShow`/`renderEpisode`; seen in headless Chrome at 375 and 1440 px, light and dark, rich and sparse, against the live projection; fit checked at 320, 375, 390, 430 px by `tools/web_fit_actions.py` (control fails), 2026-10-30 | 🚧 `SeriesHead`, `ActionRow`, `OnAirFaces` in `apple/Shared/PageParts.swift`; iPad column 720 pt; builds green, rules golden-tested; not yet seen on screen | 🚧 same; hover on faces; menu bar and shortcuts unchanged; not yet seen on screen | 🚧 same structure; Follow first focus stop, Play default focus on Detail; not yet seen on screen | 🚧 `ui/PageParts.kt`, `SeriesScreen`, `EpisodeScreen`; Robolectric renders light and dark, 320 dp fit test (control fails); not on a device | Rules (`leadPicture`, `onAirOf`, `episodeFacts`) golden-tested in all three languages. Head board's run strip is 18 on web, 56 pt on Apple, until per-year counts are published. Web date block is empty for an undated, unnumbered episode. No device check |
| Browse's A to Z jump and the D3-fix rules (WEB-DESIGN §6.4e, R11e; owner 2026-10-30): a jump to each letter that has shows ("#" for numbers and symbols), short decade headers, a window (not an empty block) on an undated unnumbered episode, the run strip from `year_counts`, the series page's genre as a link to Browse, Start an ear drama on an episode with a `script` | 🚧 letter links that page in to the letter; `years` histogram; genre link; 375 px frames read | 🚧 system section index (iOS 26+), rail below; `LetterRail`; histogram; genre link opens Browse; not run on a device | 🚧 `LetterRow` of buttons; same code | 🚧 focusable `LetterRow`; histogram; genre link; no recording | 🚧 fast-scroll `LetterRail` (TalkBack actions), chips on a TV; long episode date; Robolectric frames read | Each idiom is the platform's own (owner 2026-10-30). Apple episode page already offered Start an ear drama where `script` is set (0 episodes link one today, Decision 068); web and Android verified the same; tvOS records nothing. Apple A to Z in a wide window stacks the field above the grid |
| Player: play and pause, skip, seek, speed | 🚧 | ✅ forward 30, back 15, seek, 1.5×, pause holds and play resumes: `PlayerUITests` and `SeekUITests` on iPhone 12 (muted), 2026-10-28 | 🚧 Controls menu, keyboard | 🚧 full-screen Now Playing | 🚧 seeks at 50 % and 80 % keep the clock moving on a headerless VBR file, Pixel 8a, 2026-10-27 (tick 93); the other verbs not seen | D3-4 (2026-10-30): Now Playing leads with the grammar's window (the show's picture, else its star's, else the title block), then the title and the event line (show, date, network; Android's rows carry no network); the mini player and transport bar tile are the grammar's window and row; the lock screen carries the same picture. Seen offline on web only (headless Chrome, 320 to 430 px, light and dark); native built, not rendered or device-checked. Now Playing's line is the date and the network, on every platform (web 2026-10-29, the card carries `network`). iPhone web cannot be relied on for background audio. Headerless VBR MP3 (no Xing/Info/VBRI; the first frame's bitrate misreads duration and seeks, found 2026-10-27): Apple uses precise duration and resumes from nothing past the catalog length; Android builds a seek map from the catalog length (`Mp3Seeking`) and applies the same resume rule, unit-tested, not device-checked; web measured in headless Chrome 2026-10-27 (not device-checked): Chrome's `duration` for the Gang Busters 1954-08-02 file is 1413.5 s against a catalog 1421.6 s (0.6 %), seeks to 50 % and 80 % advance 5.0 s in 5 s with no stall or error, the constant-bitrate control matches exactly, so only the resume rule is mirrored (`Store.resumeAt(id, length)`: a place at or past 95 % of the catalog length starts over); iPhone Safari unmeasured |
| Background play and system controls (lock screen, Control Center, notification, media keys) | 🚧 Media Session | 🚧 Now Playing, remote commands; not seen on a device | 🚧 Now Playing, media keys | 🚧 audio background mode, system Now Playing; not seen on a TV | 🚧 Media3 session and notification | iPhone web cannot be relied on for background audio. §10 and §13 carry the platform surfaces |
| Sleep timer: "end of this episode" first, fades (R20) | 🚧 fade ignored by iPhone Safari (pauses) | 🚧 15 minutes set and cleared (`PlayerUITests`, iPhone 12, 2026-10-28); end of this episode stopping with nothing next: `SleepTimerUITests` written, not yet run on a device; the fade not in a committed device test | 🚧 | 🚧 | 🚧 | Decision 062: 10 s fade, speeds 0.75 to 2, save every 5 s, 3 s rewind after an interruption; on every core platform |
| Serials play to the end of an arc and stop; the next story is offered (R3, Decision 067) | 🚧 `API.arcOf`, `Player.upNext`/`nextStory`, "Next story" in Now Playing | 🚧 `PlaybackQueue.after`, `NextStoryButton` in Now Playing | 🚧 same; transport bar | 🚧 same; action row | 🚧 playlist is the arc's remaining parts then the queue; "Next story" on the sheet | Arcs from titled parts only (catalog DECISIONS 010): 480 on the native build, 198 whole on the clean-only web. A live slot never follows an arc. No device check; nothing heard |
| Commercials chaptered, never skipped (R8) | ⏳ no data | ⏳ no data | ⏳ no data | ⏳ no data | ⏳ no data | Skip is a fixed interval everywhere; no source marks commercial times yet (contract §3.2a) |
| Volume leveled on the device (Decision 067) | 🚧 DynamicsCompressorNode; not on iPhone/iPad web or TV engines ("Not in this browser") | 🚧 MTAudioProcessingTap + DynamicsProcessor | 🚧 same; beside the sleep timer | 🚧 same; Now Playing toggle | 🚧 DynamicsProcessing on the audio session | Decision 070: one set of numbers, on by default, "Level volume" turns it off; no per-file gain; not yet heard on a device |
| What plays next: an arc's next part, else one episode, then the person's queue, then stop (Decision 067) | 🚧 | ✅ add, remove, reorder (Detail button, row menu, Library Queue): `QueueUITests` on iPhone 12, 2026-10-28; a serial's next part played ahead of the queue (tick 90) | 🚧 same, plus a Controls menu command | 🚧 same, long-press menu, no reorder drag | 🚧 add, remove, reorder built (Detail button, long-press menu, swipe to remove), not device-checked | Arcs: the serial row above. The web queue: `Store` queue verbs, Library Queue |
| Versions picker; domestic copy by default | 🚧 | ✅ Versions lists every copy: `DetailUITests` on iPhone 12, 2026-10-28 | 🚧 | 🚧 Versions section on Detail | 🚧 | catalog Decision 007. The default copy is not asserted by a device test |
| Transcripts, labeled automatic | 🚧 closed section, fetched on open | 🚧 sheet, from Detail and the player | 🚧 window, ⌥⌘T | 🚧 focus-scrolling reader | 🚧 route from Detail and the player | Shown only above the measured quality gate (058) |
| Another speaker (AirPlay, Cast) | 🚧 the browser's own picker in Now Playing (`js/remote-playback.js`): AirPlay in Safari, Cast via the Remote Playback API in Chrome and Edge, shown only while a target is there; not seen on a device | 🚧 AirPlay route picker in the player (`RoutePicker_iOS`, `testRoutePickerOnPlayer`); not seen on a device | 🚧 AirPlay route picker in the transport bar (`RoutePicker_macOS`); not seen with a speaker | 🚧 the system's audio output picker in Now Playing (`RoutePicker_tvOS`: HomePod, AirPlay speakers); not seen on a device | 🚧 Google's Cast button on the player sheet (Media3 `CastPlayer`, Default Media Receiver), shown only while a receiver is on the network; the system output switcher on Android 13+; no button on a TV or without Play services (Fire TV); not seen on a device | The owner, 2026-10-28: native AirPlay or Cast on every platform. The receiver plays the catalog's archive.org copy, never a downloaded file. Listen Together and SharePlay are a separate verb |
| Downloads (an episode, a season, a whole run; a Downloads place by series; storage held; remove a series or all) | n/a: decided, Decision 071 (WEB-DESIGN §7.2a) | 🚧 background session, four at a time; series Download menu asks with count and size; Library row to the place; one episode downloaded, played from the file, listed in the place, removed (`DownloadUITests`, `DownloadsPlaceUITests`, iPhone 12, 2026-10-28); a season or run not downloaded on a device; a two-episode series run through the menu, the place, and Remove: `SeriesDownloadUITests` written, not yet run on a device | 🚧 same; toolbar menu, right-click Remove | n/a: no durable media storage; nothing said (owner 2026-10-28) | 🚧 WorkManager, four at a time; top-bar Download menu; `Route.Downloads` | Decision 071. A finished file plays with no network; a queued, failed, or partial one never plays. Lock screen offline: Apple falls back to the typographic card, Android always shows the card for a downloaded file. No real run downloaded by an agent |
| Listen Together | 🚧 Worker rooms; ?room= link; guests follow, never drive; a guest's pause holds, play catches up | 🚧 SharePlay; capability off until the App ID has it | 🚧 SharePlay | 🚧 SharePlay during a call | 🚧 Worker rooms; ?room= link; guests follow; TV joins by code; a guest's pause holds, play catches up | Worker rooms on web and Android (Decision 065); a guest's own pause on every platform (Decision 067); Apple ports room-protocol.js, golden-checked; not run on devices |
| Credits, privacy, and take-down pages | 🚧 /credits/, /privacy/, /takedown/; owner placeholders | 🚧 three links at Library's foot (`SiteLinkRows`), system browser; present on iPhone 12 (`SiteLinksUITests`, 2026-10-28); Credits tapped to Safari and back: `testCreditsOpensTheSiteAndComesBack` written, not yet run on a device | 🚧 Help menu (`SiteLinks`); not seen on a Mac | 🚧 three rows with the plain address (no browser); built, not seen on a TV | 🚧 three Library rows, Custom Tab (a TV shows the address); built and unit-tested, not seen on a device | One set of pages; apps link to them. Web pages themselves still owner placeholders |
| Works offline (what was already loaded) | 🚧 service worker; network-first data, cached shell; "You are offline." line; `?offline=1` door | 🚧 seed or downloaded catalog, downloads, Library; "You are offline." above the mini player; an undownloaded episode is refused in words; `APP_FORCE_OFFLINE` | 🚧 same; the line above the transport bar | 🚧 same minus downloads; the line heads every tab | 🚧 says "You are offline." above the mini player and on the no-catalog state; `appname_force_offline` door | Audio downloads are their own row. Apple and Android built and unit-tested, not device-checked offline (the iPhone 12 sweep, 2026-10-27, saw Detail's older warning on a build before the line); web screenshot at 375 px with the door |

---

## 3. Making plays

| Feature | Web | iOS | macOS | tvOS | Android | Notes |
|---|---|---|---|---|---|---|
| Pass the phone: record role by role on one device | 🚧 headphones confirmed by the person (a page cannot see the route); IndexedDB; not yet recorded | 🚧 built, tested; not yet recorded on a device | 🚧 own window, Recording menu; not yet recorded | n/a | 🚧 Start an ear drama on a play's page (not on TV), takes as 24-bit WAV; not yet recorded | Web with headphones only; live stand-in voices never stored; 15 scripts bundled (`catalog/plays/castable-scripts.json`): 11 stage plays, 4 radio plays |
| Three recording modes in direction D: Run through, Line by line, Step (owner ruling 4, 2026-10-29; D3-6) | 🚧 a radio group as segments; play page and cast sheet on the drama board with the cast fingerprint and part cards; Run through's review (Keep N takes, Discard the run); Cancel while a Step cue plays (the round control reads Cancel; Space too) and a live level meter (`plays.test.js`, D3-fix2); the mode kept per device in `localStorage` (`ed.recmode`), Run through the first time; `js/plays.test.js` mode tests; rendered muted with fake audio at 320, 375 and 1440 px, light and dark, 2026-10-30 | 🚧 `Picker(.segmented)`; same pages; Cancel during a Step cue and a live level meter; `RecordingModeTests` (244 tests pass on macOS); the mode kept in `UserDefaults` (`recorder.mode`), Run through the first time (`RecorderModeMemoryTests`); ImageRenderer frames at 390 pt, light and dark (the Picker draws as a placeholder there); not on a device | 🚧 same code, the rails and keys in the window, Recording menu; frames at 1100 pt; not run on screen | n/a: records nothing | 🚧 `SingleChoiceSegmentedButtonRow`; same pages; Cancel and a live meter; `RecordingModesTest` (336 JVM tests pass); the mode kept in `SharedPreferences` (`recorder`/`mode`), Run through the first time (`RecorderModeMemoryTest`); Robolectric frames at 412 and 840 dp, light and dark; not on a device | PLAYS-DESIGN §2.4; engine names match on every platform (`runPlan`, `discardRun`, `partHue`, session `mode`/`runThrough`/`pause`/`keepRun`/`discardRun`/`playCue`/`playWithCue`), `partHue` golden on Caesar Rodney's Ride everywhere. Run takes land as they are taken; the review keeps or discards them. No recording heard on any device yet. Cancel and the meter are on every platform that records (the web's ⏳ closed 2026-10-30). The recorder opens in the person's last mode on that device, never synced. |
| Parts in any order, the largest suggested (C7, Decision 067) | 🚧 every open part has Take part, the largest accented | 🚧 same; the largest prominent | 🚧 same | n/a | 🚧 same; the largest filled | One part records at a time on one device; the Worker allows any open part too (`not_open`) |
| Recording needs an account, always (Decision 067) | 🚧 "Recording needs an account." and Sign in at Start recording | 🚧 same, Sign in with Apple / Google buttons | 🚧 same | n/a | 🚧 same, the account row | Taking a part, reading along, and listening need none; sign-in from this step not yet run on a device |
| Listen through any time, open lines read live (C5, Decision 067) | 🚧 `ListenThrough`, `speechSynthesis` local voices | 🚧 `LiveListenThrough`, `AVSpeechSynthesizer.speak` | 🚧 same | n/a | 🚧 `LiveListen`, `TextToSpeech.speak`, local voices only | Labeled "Device voice"; never stored, mixed, exported, or uploaded; a guard test on each platform, broken once; not yet heard on a device |
| Personal Voice in a listen-through (Decision 067) | n/a: no such browser API | 🚧 "Use my Personal Voice", `speak` only | 🚧 same | n/a | n/a: no such Android API | Live only, never a buffer, a file, or a cue; needs a device to verify |
| Export whenever every speaking line is human (Decision 067) | 🚧 Export beside the mix, renders if stale | 🚧 `ShareLink`, renders on demand | 🚧 same | n/a | 🚧 share sheet, renders if stale | No longer waits for a full listen |
| A play's facts: year, author's years, length (Decision 067) | 🚧 | 🚧 | 🚧 | n/a | 🚧 | "1876 · 16 parts · 657 lines"; the year is the record's own (`year` in the bundle, 3 of 15 have one); no age ratings |
| Commercials as their own parts (C10) | 🚧 data plane | 🚧 data plane | 🚧 data plane | n/a | 🚧 data plane | Parser-tested only, nothing to see yet: `script_parse` names a speech inside commercial n "ROLE (COMMERCIAL n)"; no bundled script has a commercial yet |
| A failed load is retried once with jitter, then the next recording in rank order, then the error (`resilient-media-streaming`; an iPad seek test saw `-1008` four times and the player stayed failed, 2026-10-30) | 🚧 `js/player.js` `recover()` (cards carry `alts`); `player.test.js` seen failing first, then passing; not heard in a browser | 🚧 `Core/Player/LoadRecovery.swift` driven from `AudioPlayer.itemFailed`; `LoadRecoveryTests`; not run on a device | 🚧 same code | 🚧 same code | 🚧 `playback/LoadRecovery.kt` driven from `PlaybackEngine.recover`; `LoadRecoveryTest`; not run on a device | A copy that loaded earns its next failure a retry. The error shows only when every recording has failed twice. |
| A load that wants data and gains no bytes and does not move for 30 s is a failed load and goes through the same recovery (stall watchdog; a slow trickle, a pause, and a local file never trigger it; an iPad sat at status 0 for minutes, 2026-10-30) | 🚧 `Player.checkStall`; `player.test.js` seen failing first | 🚧 `Core/Player/StallWatchdog.swift` from `AudioPlayer.tick`; `StallWatchdogTests` seen failing first; not run on a device | 🚧 same code | 🚧 same code | 🚧 `playback/StallWatchdog.kt` from `PlaybackEngine.watchForStall`; `StallWatchdogTest` seen failing first; not run on a device | Fake clock and fake loader on every platform. Signals are native: loadedTimeRanges and access-log bytes, buffered end, Media3 bufferedPosition. |
| Air date in the system's long form at the catalog's precision (R1: a year stays a year, a month a month) | ✅ `fmtLongDate` (full dates) | 🚧 `AirDate.display` (Date.FormatStyle, UTC; stored digits kept for tabular rows by `AirDate.stored`); `AirDateTests` | 🚧 same code | 🚧 same code | ✅ `formatAirDateLong` | Rows keep the stored digits so a column aligns; the event line, Now Playing and Surprise's evening read the long form. |
| Invite-link productions (share, invite, join, claim any open part, upload, report, block; Publish asks the CC0 consent first and is offered when the Worker reports it can reach archive.org, Decisions 059 and 072) | 🚧 `js/plays-share.js`; stub-Worker tests; screenshots at 375 px against a stubbed record; never against a deployed Worker | 🚧 `Core/Plays/PlaysShare.swift`, `SharedPlaysViews.swift`; stub-transport tests; not run on screen | 🚧 same code, Mac idiom; not run on screen | 🚧 plays back only (§11.7 rule 12): Library's Ear dramas, Listen Through from takes in Caches with the device voice live, Report and Block; `SharedPlaysScreen_tvOS`, `SharedListenTests`; never against a deployed Worker; invites ignored | 🚧 `plays/PlaysShare.kt`, `SharedPlaysScreens.kt`; JVM tests; not run on a device. The 10 s OkHttp read timeout may cut a large upload (ANDROID-DESIGN §12); manifest link filters stay off | PLAYS-DESIGN §11.7. Sign-in required. Uploads wait on the owner's R2 switch (P1): the record's `uploads` is false and every client says "Uploads are off." Consent words approved 2026-10-29 (Decision 059). A shared production is re-read on return (web tab shown, Apple foreground, Android resume). Every performer agrees for their own recording (P13, §11.7 rule 6): a complete play asks each performer who is not the director once, the director sees a name and a mark per performer, and Publish waits for them all; tvOS shows neither. Publish opens when both archive.org keys are Worker secrets; the cron's uploader then makes the item (Decision 073). The archive.org job is told truthfully on every client (rule 9, P15): a quiet line while queued or uploading, **On archive.org** as a link, or the Worker's reason with **Publish again** for the director; tvOS shows the line only. Android TV: ⏳, a shared production is not listed there yet |
| Invitation page and finished ear dramas (no account; owner 2026-10-29 rulings 2 and 3; Worker `plays-open.js`, WORKER.md "Open reads"; D3-7): an invite shows the play, parts, who is in, and playable takes signed out, and asks for an account only at Take part; finished ear dramas are a Browse scope (Shows, Ear dramas), a Home "New ear dramas" shelf, and a credited page with Play and Share | 🚧 `?view=invite`, `?drama=`, Browse `scope=dramas`, Home shelf in `js/plays-ui.js`; Play uses the item's archive.org metadata (a whole-play MP3, else the numbered line files in order; "The audio is still being prepared." while none), View on archive.org; static previews `/invite` and `/drama/{id}`; `tools/web_fit_invite.py` at 320 to 430 px, light and dark, signed out and in, stubbed Worker, 2026-10-30; `S.pickAudio` tested | 🚧 `InviteScreen.swift`, `FinishedViews.swift`, Browse picker, Home shelf; Listen plays the item's line files in order in an in-app queue (not Now Playing); macOS tests, three Release builds; not seen on screen; `InviteUITests` widened, not run | 🚧 same code, Mac idiom; not seen on screen | 🚧 finished dramas only (Browse scope, Home shelf, page); no recording, `.invite` ignored; not seen on screen | 🚧 `OpenPlaysScreens.kt`, `ArchivePick`; plays in the app's player (`PlaybackEngine.playFile`); Robolectric renders light and dark; not on a device; Android TV: not listed | A published item holds one file per line, no whole-play mix, so native Listen plays line files in order; the owner may want the Worker to publish a mix. Hidden and reported takes stay hidden from anonymous viewers; a revoked or expired invite is a 410 ("This invitation has ended."). Deep link `/drama/{id}` (DEEP_LINKS.md). Never run against a deployed Worker |
| Replace or remove a published take (P12: a performer replaces or removes their own line on the archive.org item; the director removes any) | 🚧 `js/plays-share.js` `changeableLines`, a "Your lines" disclosure in `js/plays-ui.js`; `js/plays-share.test.js`; 375 px frames read 2026-10-29; never against a deployed Worker | 🚧 `PlaysShare.changeableLines`, `ChangeLinesSection`; `PlaysShareTests`; not run on screen | 🚧 same code; not run on screen | n/a: TVs record nothing (§11.7 rule 12) | 🚧 `PlaysShare.changeableLines`, `ChangeRow`; JVM tests; not run on a device | PLAYS-DESIGN §11.7 rule 13 (P15). Replace opens the recorder on one line, then Upload N takes overwrites it on the item; Remove asks first and takes the error color. The record has no per-line archive state, so a removal reads "Removed" for the visit only |
| Teacher classes (consent for under-13s) | 🚧 Classes in Library's Ear dramas: make, join by code | 🚧 make, join; no roster view yet | 🚧 same | n/a | 🚧 make, join | A roster only (P8). An under-13 class takes no student until the privacy policy covers school consent (P5) |
| Play back a finished play | 🚧 Listen through, Export as WAV | 🚧 Listen Through, Export | 🚧 Listen Through, Export | ⏳ AirPlay from a phone meanwhile | 🚧 Listen through, Export via share sheet | |

---

## 3b. Teaching surfaces

Teaching is a parity domain with DELIBERATE asymmetry. Track it so
a future session doesn't "harmonize" a rejection into a port (see
`universal-feature-states`).

| Surface | Web | iOS | macOS | tvOS | Android | Notes |
|---|---|---|---|---|---|---|
| EmptyState (productive next action) | 🚧 `stateBox('empty')`: the fact and at most one link; Library's Queue, History, and Following offer Browse, Browse offers Clear filters | 🚧 `EmptyState` (`apple/Shared`): a title and at most one action; empty Library is "Nothing played yet" with Browse above Account and the site pages; no results echo the query | 🚧 the same view; Library keeps Account | 🚧 the same view; Browse takes the focus; Library keeps Account and the site pages | 🚧 `EmptyMessage(action =)`: Library's Browse under Account and Listen together (takes the TV's focus), Browse's Clear filters | Required everywhere from the first list/grid. Title only where no action helps (no shelves, nothing to pick, no evening, no downloads). An empty state never replaces navigation (WEB §7.1a, iOS/macOS §7.4, tvOS §7.3a, ANDROID §7.1a). Built, not device-checked; `EmptyStateUITests` for the iPhone |
| ErrorBanner / OfflinePill | 🚧 offline line; the player's line ("You are offline." or "This recording did not load."), announced; no haptics on the web | 🚧 offline line; error haptic with the player's line ("You are offline." for a network failure) and "Download failed" | 🚧 offline line; the player's line and "Download failed"; haptics n/a on the Mac | 🚧 offline line; the player's line; no downloads, no haptics on the TV | 🚧 offline line; error haptic with "Download failed" and the player's problem line | Required everywhere. Built, not device-checked |
| HintBanner (one-shot tip) | 🚫 | 🚫 | 🚫 | 🚫 | 🚫 | Deliberately none (2026-10-28): every candidate tip teaches what a visible control already does (Detail's queue button, Edit, the Mac's menus, the remote), and the one hidden fact, that Search finds words said in an episode, belongs in the search prompt (owner's copy call). No tips, so no dismissal store and no "Show tips again". A future hint needs its platform doc's rule first (iOS/macOS §7.5, tvOS §7.3b, WEB §7.1b, ANDROID §7.1b) |
| Multi-step anchored walkthroughs | 🚫 | ⏳ | 🚫 | 🚫 | 🚫 | iOS-only where its idioms are novel; other platforms use EmptyState + hints + a `?` explainer. Record the rejection in each platform's design doc |

---

## 3c. Stubs (Decision 056)

A stub builds in CI and opens to its first screen; it grows from the core's
shared code only after the core five are complete.

| Platform | State | First screen | Notes |
|---|---|---|---|
| CarPlay | 🚧 builds | Continue, Stations, Browse, Downloads tabs (R17); Continue and Downloads play | Runs only once Apple grants the carplay-audio entitlement (Needs Ben) |
| watchOS | 🚧 builds | Continue, "Waiting on the phone" | watchOS 11 floor (pairs with iOS 18); not embedded in the phone app yet |
| Android Auto | 🚧 builds | Continue, Stations, Browse, Downloads (R17); Continue and Downloads play through the phone's queue | Every release with car support waits on Google's car review: internal or closed track only; Assistant voice (VC-1) not done |
| Android TV / Fire TV | 🚧 builds | Home, D-pad focus on the first row; Now Playing card in the background (TV-NP) | Banner art is a placeholder for the owner |
| Wear OS | 🚧 builds | Continue, "Waiting on the phone" | minSdk 30 (Wear OS 3); needs its own versionCode before upload |
| webOS / Tizen | 🚧 builds (.ipk, .wgt) | Listen, D-pad focus on the first card; remote media keys; Back that walks history | Placeholder art; the .wgt was signed with the Archive Watch Samsung profile until Ear Drama has its own |
| Roku | 🚧 builds (sideload zip) | Listen rows of series tiles from the web projection; loading, empty, error, offline | No Series screen yet; placeholder art |

---

## 4. Accounts (Decision 057)

Signing in is optional: every listening verb works signed out. It syncs
history, queue, and follows, and it is required to make a play with others.

| Feature | Web | iOS | macOS | tvOS | Android | Notes |
|---|---|---|---|---|---|---|
| Sign in with Apple | 🚧 Apple JS, nonce; placeholders until the Worker is deployed | 🚧 placeholders; entitlement off until the App ID capability (WORKER.md 4) | 🚧 placeholders; entitlement off until the App ID capability (WORKER.md 4) | 🚧 placeholders; entitlement off until the App ID capability (WORKER.md 4) | 🚧 Custom Tab, auth/apple/ return page; placeholders | M5; verified at the Worker |
| Sign in with Google | 🚧 Google's own button; placeholders | 🚧 ASWebAuthenticationSession + PKCE, no SDK | 🚧 same as iOS | ⏳ no web auth session on tvOS | 🚧 Credential Manager; needs Android OAuth clients | M5; tvOS by a phone hand-off |
| Email and password | 🚫 | 🚫 | 🚫 | 🚫 | 🚫 | Decision 057 names Apple and Google only |
| Sync of history, queue, follows | 🚧 LWW per row, markers, ?since=; tested against a stubbed Worker | 🚧 stubbed-Worker tests; queue controls (`QueueViews.swift`); the series page Follow button | 🚧 same as iOS | 🚧 same as iOS | 🚧 stubbed-Worker tests; queue controls and a Follow button on the series page | One store on the Worker + D1, never two |
| Account deletion | 🚧 in the account sheet, and the public page delete-account/ | 🚧 Account screen, fresh Apple code | 🚧 Account screen, fresh Apple code | 🚧 Account screen, fresh Apple code | 🚧 account sheet; web path delete-account/ | Ships with sign-in (Decision 035) |

---

## 5. Links

| Feature | Web | iOS | macOS | tvOS | Android | Notes |
|---|---|---|---|---|---|---|
| Routes for series, episode, person, search, library, invite | 🚧 + 404 forwarder; `tools/test_deep_links.mjs` | 🚧 `DeepLink.parse` to the inbox (`DeepLinkTests`); the search route opened on iPhone 12 (`SearchUITests`, 2026-10-28) | 🚧 same code | 🚧 same code; `eardrama://` only; no invite on a TV | 🚧 `DeepLink.kt` (`DeepLinkTest`); `?room=` too | DEEP_LINKS.md. `tools/test_deep_links.mjs` holds the AASA paths, the Android filter, and the 404 forwarder equal |
| Forwarded episode ids: a moved id opens the episode it now is; kept history, positions, queue, downloads, and synced rows rewrite once (contract §3.5) | 🚧 `API.forwarding` + `Store.forward` (`account.test.js`, `api.test.js`) | 🚧 `IDForwarding` in Core (`IDForwardingTests`); history, queue, downloads | 🚧 same Core | 🚧 same Core; no downloads on a TV | 🚧 `IdForwarding.kt`, `UserStore.forward`, `DownloadStore.forward` (`IdForwardingTest`) | catalog DECISIONS 014. Every publish aliases or tombstones each id that left, by recording (C1 measured: 984 left, 899 aliased, 85 tombstoned). Unit-tested on fixtures; no device has opened a moved id from a published catalog yet. Series keys forward in the next row |
| Forwarded series keys: a moved key opens the series it now is; follows and synced follow rows rewrite once (contract §3.5) | 🚧 `API.forwarding().resolveSeries` in `seriesPage` + `Store.forward` (`account.test.js`, `api.test.js`); `Sync.hydrate` draws every stub, in batches of 60 | 🚧 `IDForwarding.resolveSeries`, `CatalogDatabase.series(key:)`, `FollowedSeries.forward` (`IDForwardingTests`, `CatalogQueryTests`) | 🚧 same Core | 🚧 same Core | 🚧 `CatalogDatabase.seriesPage`, `UserStore.forward` follows (`IdForwardingTest`, `CatalogQueriesTest`) | An alias needs more than half of the old series' recordings in one served series, else a tombstone (C1 measured: 46 keys left, 20 aliased, 26 tombstoned). Downloads need no rewrite: their series is read from the episode id, which forwards above. The watch forwards its own history with the forwarding the phone hands it (`IDForwarding.stored`); nothing hands it one yet, as nothing hands it history yet (Decision 056). Fixtures only; no device yet |
| Universal Links / App Links | n/a | 🚧 | 🚧 | n/a | 🚧 | 2026-10-24: AASA + assetlinks.json on eardrama.org; series, episode, person, search, library, invite open the apps (DEEP_LINKS.md). Built and unit-tested; not yet opened on a device from a real link. tvOS takes `eardrama://` only (no Safari) |
| `eardrama://` scheme | n/a | ✅ `CFBundleURLTypes`; `SearchUITests` opened `eardrama://search` on iPhone 12, 2026-10-28 | 🚧 same Info.plist | 🚧 same Info.plist | 🚧 manifest filter | Every route above, the OAuth callbacks, and Android's Sign in with Apple return. Top Shelf would use it; Top Shelf is not built (§12) |
| Share an episode | 🚧 Web Share | 🚧 share sheet, https link | 🚧 share menu, https link | ⏳ QR code | 🚧 share sheet, https link (not on TV) | The web page is every share's landing twin |
| Archive Watch film cross-links | 🚫 | 🚫 | 🚫 | 🚫 | 🚫 | Out of 1.0 (Decision 058) |

---

## 6. Not in 1.0

| Feature | Why |
|---|---|
| Push notifications | Nothing in 1.0 needs to reach a listener outside the app |
| Payments, subscriptions, in-app purchase | Free, no ads (AGENTS.md); no paid tier |

---

## 7. Oldest hardware served

| Web | iOS | macOS | tvOS | Android | Notes |
|---|---|---|---|---|---|
| Evergreen browsers | iOS 18 (iPhone XS / XR) | macOS 26 | tvOS 26 (Apple TV HD) | minSdk 29 (Android 10) | project.yml and android/app/build.gradle.kts; tools/test_ios_floor.py and test_tvos_floor.py hold the Apple floors |

---

## 8. The shared data plane

Every client is a consumer only (`shared-data-plane-contract`); the
contract is `docs/CATALOG-CONTRACT.md`.

| Asset | Purpose | Where | Consumed by |
|---|---|---|---|
| `ear-drama.sqlite.zz` + `manifest.json` | the served projection, queried on disk | Release `catalog-latest` | iOS, macOS, tvOS, Android (validate, then swap) |
| `ear-drama-seed.sqlite` | first launch offline (clean only) | bundled at build time from `catalog/out/publish-clean` | iOS, macOS, tvOS, Android |
| `/data/` (index, series, shards, days) | the web projection | GitHub Pages, deployed by `catalog-publish.yml` | web |
| `loudness-latest` | loudness measurements | Release asset, `catalog-loudness.yml` | the projection build only |
| Worker + D1 | accounts, sync, shared plays | 🚧 built and tested locally (Decision 063); not deployed; no client signs in yet | every client |

---

## 9. Web-specific affordances

| Feature | Web | Why |
|---|---|---|
| URL reflects the view | 🚧 | Shareable links; native apps keep state in memory |
| Web Share with a copy fallback | 🚧 | Native apps use the system share sheet |
| Offline shell (service worker) | 🚧 | Network-first data, cached shell; audio downloads are the apps' |

---

## 10. iOS-specific affordances

| Feature | iOS | Why |
|---|---|---|
| System tab bar (Liquid Glass on iOS 26) | 🚧 | The floor is iOS 18, so the system draws what each version has |
| Lock Screen and Control Center controls | 🚧 | Now Playing and remote commands; device check pending |
| Dark and tinted app icons | 🚧 | The mark in the dark-mode red on a clear ground; a grayscale one for tinting (`tools/render-app-icon.py`); not yet seen on a device |
| Live Activities, widgets | 🔮 | After 1.0 |

---

## 11. macOS-specific affordances

macOS is a pointer, keyboard, menu bar, resizable-window app, never the
iOS app resized (`macos-platform-patterns`).

| Feature | macOS | Why |
|---|---|---|
| Controls menu with keyboard equivalents | 🚧 | Play/Pause, skip, speed, sleep timer, Download Episode |
| `NavigationSplitView` sidebar and detail | 🚧 | iOS uses tabs, tvOS a focus sidebar |
| A transport bar along the window's bottom | 🚧 | Audio has no picture, so the player never replaces the window |

---

## 12. tvOS-specific affordances

| Feature | tvOS | Why |
|---|---|---|
| Focus-driven layout, Play focused on Detail | 🚧 | The ten-foot constraint (`tvos-platform-patterns`) |
| Full-screen Now Playing | 🚧 | Typographic, no artwork required |
| Top Shelf | 🚧 | The listener's Continue items (up to ten, Home's order) from an App Group snapshot; opens `eardrama://episode/{id}`. App Group `group.app.eardrama` registered and assigned 2026-10-28; signed tvOS build carries it in the app and the extension. Not yet seen on a device. Each item wears its Detail face (credited ones too: select opens that Detail, which shows the credit), else an uncredited series face (tvOS-DESIGN §9.3) |
| Layered parallax icon | 🚧 | Back (red), ring, microphone layers (`branding/tvos-icon-layers/`); not yet seen on a device |

---

## 13. Android-specific affordances

| Feature | Android | Why |
|---|---|---|
| Predictive back | 🚧 enabled in the manifest | iOS swipe-back is fixed-animation |
| Media3 notification and lock-screen controls | 🚧 | The MediaSession service |
| Adaptive icon with a monochrome layer | 🚧 | The ring microphone on the icon red, with its own monochrome silhouette (`tools/render-app-icon.py`); not yet seen on a device |
| Android Auto library tree | ⏳ | M9 stub |

---

## Maintenance protocol

When you ship a feature:

1. Find the row in this table. Add new rows under the right section
   if needed.
2. Update each platform's status with one of the legend symbols.
3. Link to the relevant section of the platform's binding design doc.
4. Note any platform-specific deltas in the Notes column.
5. A shared-Core change usually moves all THREE Apple columns (iOS ·
   macOS · tvOS). Verify each still builds before you tick them.

When a feature ships on one platform but is meaningfully different
elsewhere, add an entry to §9 / §10 / §11 / §12 / §13.

When a platform explicitly rejects a feature, add an "Out of scope"
row in the relevant design doc and link from this table.

Keep the matrix readable, or it stops being true:

- **A cell is one sentence plus a link.** Put the evidence in the cell
  ("✅ verified on iPhone 12, YYYY-MM-DD"). Put the story in the ledger,
  design doc or DECISIONS entry the cell links to. A matrix that
  becomes a journal stops being read.
- **Name the parity test** in Notes for every row a mechanical guard
  enforces (for example `tools/test_<rule>_parity.py`).
- **One summary row per ported platform** (§7d). Never keep a second
  per-surface copy here once the port has its own ledger.
- **Scripts read columns by header name.** `line.split("|")` returns a
  leading empty element, so a fixed index lands in the wrong column
  and the table still renders. Build the index from the header row.
- **Keep §7b and §7c current** when a floor moves or a capability
  changes.

**Run a parity audit** (the `cross-platform-parity-discipline` skill,
"audit" mode) before any launch wave and roughly once per milestone:
walk the shipped feature list per platform and verify every cell is
honest. Real audits on shipped apps have found both missing rows
(features nobody recorded) AND false cells (a "synced" claim that
never actually synced). The audit is what keeps this file true.
