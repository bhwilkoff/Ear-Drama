# R2 port brief: the five-section shell, Home and Record on Apple and Android

Written 2026-11-14, after the web build of Decision 075. This is the spec a porting agent works
from. The binding rules are already in the platform docs (changed first, same commit):
`docs/iOS-DESIGN.md` §3.1, §4.1, §4.2, §4.14; `docs/macOS-DESIGN.md` §3.1; `docs/tvOS-DESIGN.md`
§2.1; `docs/ANDROID-DESIGN.md` §3.1, §4.1, §4.2, §4.9, §4.9a; shared rules in
`docs/WEB-DESIGN.md` §4.2 (Home) and §4.15 (Record). Quote the rule before you build; if the rule
and this brief disagree, the rule wins and you say so.

The web reference: `js/app.js` (`renderListen`, `homeRow`, `homeChipRow`, `episodeTile`,
`renderLiveBlock`/`onAirNow`/`paintLiveBlock`, `renderTodaysPlay`, `todaysPlayBoard`,
`castWindow`, `playTile`, `renderRecord`), `js/plays-core.js` (`authorName`, `voicesOf`,
`minutesOf`, `VOICE_BANDS`, `LENGTH_BANDS`, `voiceBand`, `lengthBand`, `fnv1a64`, `todaysPlay`),
`js/plays-ui.js` (`openParts`, `renderMine(..., { onEmpty, classes })`), `js/api.js`
(`homeShelves`, `LENGTH_BANDS`). Frames: `tools/web_fit_home.py --shots DIR`.

Rules every port keeps: no sentence explaining the app; every heading is a verb or the name of
its data rule; no AI-written copy; a row whose rule yields nothing is absent; each row has its
own loading, error (Try again), and offline state; nothing personal on Home but Continue (and
Open parts, the person's own productions); the TV records nothing. Real devices only for
verification (memory: never a simulator).

---

## 1. The shell

| Platform | Sections | Stations | Surprise |
|---|---|---|---|
| iOS / iPadOS / Duo | Home, Browse, Record, Search (`Tab(role: .search)`), Library; the same five at every width | push `Route.stations` from Home (On the air's All Stations, the Listen door) | Home toolbar push `Route.surprise` (unchanged on iPhone); the iPad/Duo Surprise tab and its `showsSurpriseTab` gate are deleted |
| macOS | five sidebar sections, ⌘1 to ⌘5 (Go menu order = `AppTab.allCases`) | push in Home's stack | Home toolbar push; Go menu item ⇧⌘S |
| tvOS | four entries: Home, Browse, Search, Library | Home hero's All Stations | Home hero's Surprise button |
| Android phone | five tabs (icons Home, Explore, Mic, Search, Bookmarks) | push `Route.Radio` from Home | Home top bar Shuffle (unchanged) |
| Android TV | four: Home, Browse, Search, Library (`isTelevision()` drops Record) | push from Home | Home top bar (unchanged) |

Old door names keep opening: `stations`, `radio` → Home then push Stations; `surprise` → Home
then push Surprise; `plays` → Record.

### Files

**Apple**
- `apple/Core/Store/AppStore.swift`: `enum AppTab` → `home, browse, record, search, library`
  (`title` "Record", `symbol` "mic"); `init?(door:)` maps `radio`/`stations` and `surprise` to
  `.home` plus a pending push (add `pendingPush: Route?` drained by Home, or push in
  `drainInbox`), `plays` → `.record`. `enum Route` gains `.stations`. Remove the
  `pendingBrowse…` path only if nothing else uses it (Home's "All voices" and "All" still do).
- `apple/iOS/ContentView_iOS.swift`: tabs Home → `ListenScreen`, Browse →
  `SeriesBrowseScreen`, Record → new `RecordScreen`, Search, Library. Delete the Surprise tab,
  `showsSurpriseTab`, the compact-width `onChange` hand-back, and `SidebarAvailabilityProbe` if
  unused.
- `apple/macOS/ContentView_macOS.swift`: detail `switch` gains `.record` → `RecordScreen`
  (`WidePage`), loses `.stations`/`.surprise`; `GoCommands_macOS` adds Surprise ⇧⌘S.
- `apple/tvOS/ContentView_tvOS.swift`: TabView loses Stations and Surprise;
  `RouteDestinations_tvOS` gains `.stations` → `RadioScreen_tvOS`.
- `apple/Shared/ListScreens.swift` `RouteDestinations`: `.stations` → `RadioScreen`.
- `apple/Core/Store/LaunchDoors.swift`: `APP_START_TAB` accepts `record`; doc comment.
- `apple/macOS/DoorFile_macOS.swift`: `tab` command accepts `record`.

**Android**
- `android/.../navigation/Routes.kt`: `enum class Tab` → Home, Browse, Record (root a new
  `Route.Record`), Search, Library; `named()` maps `plays` → Record, `radio`/`stations` → Home
  (+ push `Route.Radio`), `surprise` → Home (+ push `Route.Surprise`, as the inbox already does).
- `android/.../ui/AppRoot.kt`: `Tab.icon()` Mic for Record; `NavigationSuiteScaffold` over
  `Tab.entries.filter { !(isTelevision && it == Tab.Record) }`; `entryProvider` gains
  `entry<Route.Record> { RecordScreen(...) }`; `ListenScreen(onOpenStations = { stack.navigateTo(Route.Radio) }, onOpenRecord = { selected = Tab.Record }, onOpenBrowse = { selected = Tab.Browse }, …)`.
- `android/.../navigation/LaunchDoors.kt`, `MainActivity.kt`: `record` start tab.

### Tests and tools to update in the same change
- Apple: `apple/Tests/DesignRulesTests.swift:96` (tab titles), door asserts ~97-105;
  `apple/UITests/TabSmokeUITests.swift`, `LayoutSweepUITests.swift` (stations, surprise, and
  `testCreate`, which goes Browse → Kind → Plays: rewrite as Record → a play → Record This),
  `IPadAuditUITests.swift`, `NavigationUITests.swift`, `FollowUITests.swift:21` ("Continue
  listening" is now "Continue"), `UITestSupport.openTab`, `LayoutSweepSupport`;
  `apple/Tests/Render/DiscoveryRenderTests.swift`, `PlaysRenderTests.swift`.
- `tools/test_apple_design_rules.py` (`phone_shell_is_five_verbs`, ~56-66 and its mutation
  checks ~151-153): new order `home, browse, record, search, library`, no `showsSurpriseTab`,
  `store.push(Route.surprise)` still in Home.
- `tools/app_config.py:180` `APP_ANCHOR_RX` and `:187` `IOS_ANCHOR_RX` require "Stations":
  change to Record, or every harness scenario reads "wrong app". `tools/ios_run.py:56-73`
  (stations, surprise scenarios become pushes), `tools/test_ios_overlay.py`,
  `tools/test_ios_anchor.py` (OCR fixtures), `tools/mac_run.py:45`, `tools/atv_run.py:66`,
  `tools/atv_scenario.py`.
- Android: `LaunchDoorsTest.kt:32-38` (labels and `named`), `DeepLinkTest.kt`,
  `DiscoveryRenderTest.kt` (stations, surprise), `PlaysRenderTest.kt:~180` ("Start an ear
  drama" → "Record this").

---

## 2. Home, top to bottom

Data sources on each platform:
- Live: Apple `LiveRadio` (`apple/Core/Radio/LiveListening.swift`, `@Environment(LiveRadio.self)`),
  `RadioLoad.load` / `StationsLoad.load` (`apple/Core/Radio/RadioLoad.swift`),
  `RadioClock.onAir`, `StationClock.onNow`; tune-in code to reuse is
  `StationsSection.tonight(_:)` / `station(for:)` in `apple/Shared/RadioScreen.swift`. Android
  `container.live` (`radio/LiveRadio.kt`), `RadioLoad.load`, `ApiClient.tonight()/stations()`,
  `RadioClock.onAir`, `StationClock.onNow/ahead/details`; tune-in in `RadioScreen.kt`
  `stationRows` (~314-373).
- Shelves: Apple `CatalogStore.listenShelves(today:)` and `PublishedShelf`
  (`apple/Core/Catalog/CatalogModels.swift` ~517-570, `CatalogDatabase.listenShelves` ~624);
  Android `PublishedShelf.parse` (`data/Models.kt` ~372), `CatalogDatabase.listenShelves`
  (~751). **No Home screen reads these today**; Home's current rows are its own queries.

| # | Section | Rule (data) | States | Apple (`apple/Shared/ListScreens.swift` `ListenScreen` ~61-229, tvOS `ListenScreen_tvOS` in `ContentView_tvOS.swift` ~126-296) | Android (`ui/screens/ListenScreen.kt`) |
|---|---|---|---|---|---|
| 0 | Heading | "Home" + Surprise | none | large title; toolbar `Label("Surprise", systemImage: "shuffle")` (exists) | TopAppBar Shuffle (exists) |
| 1 | **On the air** | `onAirNow` (below) | spinner; nothing on → absent; tonight.json error → problem line + Try again; stations.json error alone → treated as no stations | new `OnAirSection` | new `OnAirCard` |
| 2 | **Continue** | `Store.inProgress` 10, only when non-empty; heading "Continue" | local, none | existing `continuingRows`, retitled, moved under On the air | existing, retitled |
| 3 | **Three doors** | navigation only | none | `Grid` row of three equal buttons; tvOS two cards (no Record) | `Row` of three `OutlinedCard`s, weight 1f each; TV two |
| 4 | **Start a show** | chips = `mostDownloaded` ("Most downloaded") then each `genreFirsts` in manifest order, label = published genre name; tiles = that shelf's ids in order | per chip: spinner, error + Try again, offline line; no shelves → absent; one shelf → heading "Start a show: {label}", no chips | segmented `Picker` or capsule chips over a horizontal `ShowGrid` rail; tile = series window + name + episode title + length, Play button on the window's corner | `FilterChip` row over `LazyRow` of 220 dp tiles with a Play `IconButton` |
| 5 | **By length** | `byLength` shelves in `under15, about30, hour` order; labels "Under 15 min", "About 30 min", "An hour" | as 4; absent while the manifest has none (true until the next catalog publish) | same component as 4 | same as 4 |
| 6 | **Record a play** (not on TV) | Today's play = `todaysPlay(scripts, localDateKey)`; Open parts = this device's productions with any part `status == open`, newest first, at most 5 | scripts fail → problem line; no scripts → absent; Open parts absent when none | `PlayHead` board with the cast window (§3) + "Record This" (`StartEarDramaButton`, `.borderedProminent`) + "Parts" (pushes `PlayRoute.script`); rows via `ProductionLink` | `PlayHeadBoard` + Record this + Parts; rows via `ProductionRow` |
| 7 | **This day in radio** | existing day board + night | existing | existing `DayBoard` + `nightSection`, moved down | existing `DayBoard`, moved down |
| 8 | **Most heard voices** | `voices` 12, "All voices" | existing | existing `VoicesShelf` | existing |
| 9 | **Made here** | finished ear dramas, newest first, "All"; heading renamed from "New ear dramas" | existing; absent when none | existing `FinishedTile` shelf | existing `NewEarDramas` (`OpenPlaysScreens.kt:485`) |

Removed from Home: Following (still in Library), the "Most downloaded" series grid (its rule
now feeds Start a show's first chip), the footer/site links (Apple's Library keeps them).

**`onAirNow(day, stations, now)`** (web `js/app.js`):
1. If tonight's evening exists and `onAir(day.slots, now)` has a slot with an episode that is
   not withheld → kicker "Tonight in {year}", that slot, tune-in = the evening's.
2. Else, for each station in file order, the first whose `onNow` slot has an episode and is not
   withheld → kicker = station name, that slot, tune-in = the station's. If the evening has not
   started, add the caption "Tonight in {year} · Starts at {local time}".
3. Else → no block.

The block: kicker; a grammar row (series window keyed by `episode.id` before `|`, 64 pt/dp; the
series name; event line "{episode title} · {N} min in", N = whole minutes since `utc_start`);
**Listen live** (ink, primary; while this source is live: pressed, "Listening live", and a press
pauses and stops) and **All stations** (secondary). Repaint every 15 s and on player changes.
Listen live on the evening fetches the evening's details then `tuneIn(day, details)`; on a station
it is the station tune-in Stations already uses. tvOS: this is the hero, Listen Live the default
focus, All Stations and Surprise in its action row.

---

## 3. Record

Apple: new `apple/Shared/RecordScreen.swift` (iOS `List`, Mac `WidePage`), not compiled for tvOS.
Android: new `ui/screens/RecordScreen.kt` (`LazyColumn`), absent on a TV.

| # | Section | Rule | States |
|---|---|---|---|
| 1 | **Yours** | `PlaysShare.libraryRows` (local + shared not yet opened), as Library's Ear dramas draws them (Apple `EarDramasSection` minus its caption; Android `earDramasSection`) | absent when empty (no sentence); local, no loading |
| 2 | **Today's play** | same board as Home §2 row 6 | as Home |
| 3 | **Plays** | the castable library, three facets + sort (below), a count line "{N} plays · {sort name}", a grid of play tiles | loading, error + Try again, offline; no match → "Nothing matches these filters." + Clear filters |
| 4 | **Made here** | as Home row 9 | as Home |

Facets (each count computed with the other two applied; an option with 0 is hidden unless
selected):
- **Voices** `voicesOf` = `roles.count` (else speaking `castParts`): `1-2`, `3-5`, `6-10`,
  `11+`, labels "1 or 2 voices", "3 to 5 voices", "6 to 10 voices", "11 or more voices"; all =
  "Any number".
- **Length** `minutesOf` = max(1, round(sum(roles.words) / 150)): `short` ≤ 29 "Under 30 min",
  `mid` 30-60 "30 to 60 min", `long` ≥ 61 "Over an hour"; all = "Any length".
- **Kind** `kind`: `radio` "Radio play", `stage` "Stage play"; all = "Any kind".
- **Sort**: `voices` "Fewest voices first" (default; ties A to Z), `short` "Shortest first"
  (ties A to Z), `name` "A to Z" (by `sort_name`, else title).

The **play tile** (show tile grammar): window = **cast window**; name in the tile type; the
existing `CastFingerprint` in the strip slot; facts "{N} voices" and "About {M} min". The **cast
window** (web `castWindow`): the window on the drama board; one horizontal bar per speaking part
(largest first, up to seven) stacked top to bottom, each as wide as its lines over the largest
part's (minimum 6 %), the first bar thicker, all in the board's one on-board color (as the
fingerprint is inside a tile); "+N" bottom right when there are more than seven. Today's play
board uses the same window in place of the monogram.

Author lines everywhere use each author's `display` (the record carries it for all 15), else
`displayName(name)`: change `PlayScript.authorLine` / `authorLineWithYears` (Apple ~162-168) and
`authorLine` / `authorWithYears` (Android ~133) and add a test with
`{"name":"Baker, George M. (George Melville)","display":"George Melville Baker"}`.

**Record This**: rename `StartEarDramaButton`'s label (Apple `PlaysScreens.swift` ~43, Android
`PlaysScreens.kt` ~175) to "Record This" (Apple title case) / "Record this" (Android). It stays on
a play's page, Surprise's play, Today's play, and an episode whose `script` names a castable
script (Apple `EpisodeScreen` ~947, Android `EpisodeScreen.kt` ~137), beside Play where the row
fits, else its own row under it.

Browse: drop plays (`BrowseKind`, `shownPlays`, `itemsOf`'s play branch, the Kind chip; Apple
`ListScreens.swift` ~251-640, Android `SeriesBrowseScreen.kt` ~95-265). Keep "Has a script".

---

## 4. New shared code, with goldens

1. **`todaysPlay`** (Apple `PlayScript.todaysPlay(_ scripts:, dateKey:)` in
   `apple/Core/Plays/PlayScript.swift`; Android `todaysPlay` in `plays/PlayScript.kt`):
   FNV-1a 64 over the UTF-8 bytes of `"play:\(dateKey):\(id)"`, offset `0xcbf29ce484222325`,
   prime `0x100000001b3`, wrapping multiply (Swift `&*`; Kotlin `ULong`/`Long` with each byte
   `toLong() and 0xFF`), pick the smallest hash, ties by id; nil for an empty list. `dateKey` is
   the person's local calendar date `yyyy-MM-dd` (Apple `RadioClock.localDate`, Android the
   same as tonight's). Test: read `catalog/tests/golden/todays_play.json` and check `hashes`
   (hex, 16 digits) and every case (`ids` defaults to the file's `ids`). One id is non-ASCII on
   purpose. Reference: `catalog/tools/todays_play.py`; web: `js/plays.test.js`.
2. **`voicesOf`, `minutesOf`, bands**: as §3, with the web's test values (roles of 3000, 1500,
   10 words → 3 voices, 30 min, bands `3-5`/`mid`; 100 words → `short`; 11 roles → `11+`).
3. **`byLength` shelf decode**: Apple `ShelfRule`/`PublishedShelf` gain
   `byLength(band: String, episodes: [String])` (bands `under15`, `about30`, `hour`; any other
   band dropped), with branches in `CatalogDatabase.listenShelves` and `shelf(_:)`; Android
   `PublishedShelf.ByLength(band, ids)` with its `when` branches. Update
   `ListenShelvesTests.parseKeepsOnlyKnownRules` and `ListenShelvesTest` "parse keeps only known
   rules" to include a `byLength` entry and an unknown band that is dropped. Contract:
   `docs/CATALOG-CONTRACT.md` §5.1.

---

## 5. Verification per platform

- Apple: `xcodegen` first; build iOS, macOS, tvOS Release clean (zero warnings); tests; then
  real devices (iPhone 12, the iPad, the Duo when connected, the Mac, Ben Bedroom Apple TV) with
  the launch doors `APP_START_TAB=home|record`. Read each frame: Home at the top (On the air,
  doors on one row), Home scrolled to Record a play, Record with a facet set. On the TV: four
  entries, Listen Live focused.
- Android: unit tests, Robolectric renders light and dark at 412 and 840 dp, then the Pixel 8a
  and an Android TV over adb. Do not upload a Play build while one is in review.
- Update PARITY.md's ⏳ cells (rows: Shell, Home, Browse, Surprise, Record this, Record section,
  Today's play, By length) to what was seen, with the date.
