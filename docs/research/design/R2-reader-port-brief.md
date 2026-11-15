# R2 reader port brief: the script reader on Apple and Android (Decision 076, S0 + S1)

The web shipped the reader first (2026-11-14). This brief is the exact spec for the Apple
(iOS, iPadOS, macOS; tvOS read-along later) and Android ports. It binds nothing new: the
rules are PLAYS-DESIGN §2.7 (the verbs) and each platform's design doc (iOS-DESIGN §4.15,
macOS-DESIGN §4.7, ANDROID-DESIGN §4.17, tvOS-DESIGN §4.13). Where this brief and a design
doc differ, the doc wins; fix the doc first.

The owner, 2026-11-14: *"You should be able to read a script and turn pages and mark them up
and do all of the things that a good book/script reading experience should contain."* Pages
by default (the owner's ruling over the research's scroll), a slide, never a curl.

**Before you start.** The R2 port (`R2-port-brief.md`: five sections, Record tab, Today's
play) is in flight on both stacks. The reader's doors (Record tiles, Today's play) land on
those screens; if they are not merged, put the Read door on the play's page first and add the
others when Record lands. Real devices only (iPhone 12, iPad, the Duo, a Mac window; Pixel
8a); never a simulator or emulator. Press the keys yourself (pyatv is not needed: a hardware
keyboard on the iPad, `adb shell input keyevent` on the Pixel).

**The web reference** (read it; port behavior, not idiom):
- `js/plays-core.js`: `sectionLevel`, `sectionTitle`, `actKey`, `sectionsOf`, `contentsOf`,
  `placeOf`, `lineText`, `fold`, `searchScript`, `lineIndexesOf`, `nextLineOf`,
  `openSpeakingParts`, and the row-or-script browse helpers `voicesOf`, `minutesOf`,
  `castOf`, `partCountOf` (with `CASTABLE_LINES = 5`).
- `js/reader-core.js`: `normalizePrefs` (`SIZES`, `SPACING`, `SPREAD_MIN = 860`),
  `lineAtPage`, `turn`, `spreadStart`, `swipeTurn`, `tapZone`, `keyTurn`, `pageLabel`,
  `remember`, `runsOf`, `spaceBetween`.
- `js/reader.js`: the view (DOM, CSS columns, input). `js/reader.test.js`: every case below.
- Golden: `catalog/tests/golden/script_sections.json` (level, title, act per heading).

---

## 1. S0: data (both stacks)

1. **Decode `sections`.** A script entry may carry `sections: [{line, source}]` (contract §4.1):
   printed headings the parser set aside, verbatim, at the line they open. Optional; the
   bundled `castable-scripts.json` has none yet. Apple: `var sections: [ScriptSection]?` on
   `PlayScript` (`apple/Core/Plays/PlayScript.swift`), `struct ScriptSection: Codable,
   Sendable { let line: String; let source: String }`. Android: `val sections:
   List<ScriptSection> = emptyList()` on `PlayScript` (`plays/PlayScript.kt`; the decoder already
   has `ignoreUnknownKeys`). Index rows also carry `cast: [Int]` (each named role's speeches,
   largest first).
2. **`sectionLevel(text)`**: the first line of the block, trimmed, against three patterns,
   case-insensitive, in this order (copy the regexes from `js/plays-core.js`, do not re-derive):
   act (`ACT`/`ACTUS` + a number word or roman/arabic numeral, or `[THE] <ordinal> ACT`), scene
   (`SCENE`/`SCENA`/`SCOENA` + number, or `[THE] <ordinal> SCENE`), part (a whole line of
   `PROLOGUE`, `EPILOGUE` or `INDUCTION` with punctuation only). `sectionTitle`: the first line,
   `_` removed, runs of whitespace collapsed. `actKey`: the act's number token, upper-cased.
3. **`sectionsOf(script)`** (cache per script):
   - From `sections` whose `sectionLevel` is not nil and whose `line` exists: `isLine = false`.
   - From every non-speech line whose `source` has a level: `isLine = true`.
   - Sort by line index; at one index, set-aside headings before the line heading, then input order.
   - Walk in order: an `act` whose `actKey` equals the current act's becomes `scene`; an `act`
     sets the current act; a `part` clears it.
   - Drop a section with no speech line between it and the next section of the same or higher
     rank (act and part rank 0, scene 1), or the end: that is a printed list of the acts.
4. **`contentsOf`**: acts and parts at the top, scenes under the act before them; a scene with no
   act before it (or after a part) stands alone. **`placeOf(lineIndex)`**: `(act, scene)`.
5. **`lineText(line)`**: a speech's pieces' texts joined by one space; else `source`. This is the
   string marks will anchor to (S5): never change its definition.
6. **`searchScript(script, query, limit = 100, span = 40)`**: fold case, diacritics (NFD, drop
   combining marks), curly quotes to straight, and runs of whitespace to one space, keeping a map
   from folded to original offsets; queries under two folded characters find nothing; return the
   total and the first `limit` hits with `before` / `match` / `after` in original text. Apple:
   `String.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)` per
   character to keep the map; Android: `java.text.Normalizer` NFD per character.
7. **`nextLineOf(part, index, direction)`**, **`openSpeakingParts(record, script?)`** (speaking
   parts with status open; never `directions` or `sound`).
8. **`runsOf(line)`**: a speech's pieces, each split on `_` (a said piece: `say`, toggled `em`,
   both `said`; an aside: `aside`, toggled `plain`), each run with `at` = its offset into
   `lineText`, plus its piece index; a block: `plain` / `em` split the same way.
   `spaceBetween(before, after)`: a space between two pieces unless `after` starts with
   `. , ; : ! ? ) ] ’ ” … — -` or `before` ends with `( [ “ ‘ — -`.
9. **Browse helpers**: `voicesOf` = index `voices`, else roles with ≥ 5 speeches (this changes the
   number the bundled plays show: it now matches the library index); `minutesOf` = index
   `minutes`, else words / 150 rounded, at least 1; `castOf` = index `cast`, else speaking parts'
   line counts largest first; the fingerprint and cast window draw from `castOf`.

**Tests (S0), each seen to fail first** (mutate, run, restore, note it in the test's doc comment):
- Golden: every case in `script_sections.json` for level, title and act.
  Apple `ScriptReadingTests.swift` (Swift Testing, `@Test(arguments:)` over the decoded file,
  added to the test target via `project.yml`; run `xcodegen` first and compare the test count);
  Android `plays/ScriptReadingTest.kt` (JUnit, reads `catalog/tests/golden/` like
  `TodaysPlayTest.kt` does).
- The grouping fixture and the printed-list fixture from `js/reader.test.js` ("contents: an act
  heading that repeats the act ...", "a printed list of the acts ... is left out"), copied case
  for case.
- Real scripts, picked from the data (never a pinned title): every bundled script plus a spread
  of the built library when `catalog/out/plays-library/` exists: every section lands on a line,
  in order, no speech line is a heading, scenes sit inside their act, every section appears in
  the contents once.
- Search: the fold fixture (quotes, accents, line break, limit, total, words around).
- Runs: every run of every line of the real scripts reads back from `lineText` at `at`.
- Library rows: for each bundled play present in the built library, `voicesOf(bundle) ==
  row.voices` and `castOf(bundle) == row.cast`.

## 2. S0: the library (both stacks)

Lists read the published play library (`<site>/data/plays/library/index.json`, contract §4.1)
when it loads, the bundle otherwise; a script opens from `scripts/<id>.json`, else the bundle.
- Apple: `PlaysLibrary` (`apple/Core/Plays/PlaysLibrary.swift`) gains `rows: [PlayRow]` (a
  `Codable` index row) fetched through the one `APIClient` (refresh-free: public data), cached in
  `Caches/PlayLibrary/` (never Application Support on tvOS), and `func script(id:) async throws
  -> PlayScript?` (library file, else bundle). Record, Today's Play, Search and Surprise read
  `rows`; the cast sheet and the reader read `script(id:)`.
- Android: `PlaysLibrary.kt` the same, through the Ktor client, `cacheDir/PlayLibrary/`.
- Today's play is computed over the rows (the golden is id-only, so it is unchanged); every
  platform reading the same library shows the same play.
- Home's **Open parts**: only shared productions someone else directs with
  `openSpeakingParts` non-empty, signed in, at most five (WEB-DESIGN §4.2 item 7). The person's
  own productions are never in that row (today both stacks list this device's productions:
  `HomeSections.kt` `OpenPartsRows`, and Apple's equivalent once R2 lands).
- Tests: a stubbed fetch returns the index (rows read, bundle not read for the list), a missing
  index (bundle rows), a library script file, a script only in the bundle, an offline library
  script not bundled (the error surfaces). Mirror `api.test.js` "the play library".

## 3. S1: the reader on Apple (iOS, iPadOS, Duo, macOS)

**Files**
- `apple/Core/Plays/ScriptReading.swift` (new; Core, no SwiftUI): §1's functions plus
  `ReaderMath` (the `reader-core.js` arithmetic: `lineAtPage`, `turn`, `spreadStart`,
  `swipeTurn`, `tapZone`, `pageLabel`, `normalizePrefs`) and `ReaderPrefs: Codable` (layout
  `.pages`/`.scroll`, size index 0-6 over `[0.875, 0.9375, 1, 1.125, 1.25, 1.5, 1.75]`, spacing
  `.tight 1.35 / .normal 1.55 / .loose 1.8` as line-height multiples).
- `apple/Shared/ScriptReader.swift` (new; iOS and macOS): `ScriptReaderView(script:startLine:)`,
  `ReaderPager`, `ReaderLineView`, the three sheets.
- `apple/Shared/PlaysScreens.swift`: **Read** (`Button("Read", systemImage: "book")`,
  `.bordered`) beside Record This on the play's page; the Record tile's corner button and Today's
  Play's Read where R2 put them.
- `apple/iOS/...` root: `fullScreenCover(item: $readerScript)` (never `isPresented`); the Mac:
  `WindowGroup(id: "reader", for: String.self)` opened with `openWindow(id:value:)`.
- `project.yml`: add the new files and `ScriptReadingTests.swift`; run `xcodegen`.

**Pagination (the hard part)**
- Paginate the script into pages with **TextKit 2** off the main actor: one `NSTextContentStorage`
  holding the whole script as an `NSAttributedString` built from `runsOf` (speaker name run in,
  semibold, 0.8125 em, the part hue; said text body; asides italic secondary; directions italic
  secondary indented 1.25 em; headings in the section-header face; a custom attribute
  `.scriptLine = lineID` and `.scriptOffset = at` on every run), one `NSTextLayoutManager`, and a
  chain of `NSTextContainer`s of the page size (iOS 18 floor: TextKit 2 is available). Each page
  is the text range its container holds; record for every line its first and last page (the
  `starts` / `ends` arrays) from the `.scriptLine` attribute at each fragment.
- Page size: the reader's content area minus 24 pt margins; text size = Dynamic Type body ×
  the reader step (use `UIFontMetrics(forTextStyle: .body).scaledFont`; on the Mac the system
  body size). Per screen: two pages when the content width ≥ 860 pt (`ReaderMath.perSpread`),
  else one; the measure is capped at 36 em per page and centered.
- Re-paginate on: size class or width change (`onGeometryChange`), Dynamic Type
  (`@Environment(\.dynamicTypeSize)`), a prefs change. Keep the **position line**: after
  re-paginating go to `starts[positionIndex]` and do not recompute the position from the new
  page (the web drifted backward through repeated size steps until it kept the line; see
  `layout(st, keep)` in `js/reader.js`).
- Draw each page with a `Text`-free renderer: a `UIViewRepresentable` / `NSViewRepresentable`
  wrapping a lightweight view that draws its page's text range (`NSTextLayoutFragment.draw`), so
  what is drawn is what was measured. Do not lay pages out with SwiftUI `Text`: its line
  breaking differs from TextKit's and pages would overflow.

**Turning**
- iOS/iPadOS: `ScrollView(.horizontal) { LazyHStack(spacing: 0) { ForEach(spreads) } }` with
  `.scrollTargetLayout()`, `.scrollTargetBehavior(.paging)`, `.scrollPosition(id: $spread)`,
  `.scrollIndicators(.hidden)`; this is the native slide. (A `TabView` with `.page` style also
  slides but rebuilds pages poorly at 500+ pages; prefer the paging `ScrollView`.) A tap on the
  outer fifth (`ReaderMath.tapZone`) animates `spread ± 1` (`withAnimation(.snappy)`, none
  under Reduce Motion). Keys: `.focusable()` + `.focusEffectDisabled()` on the pager,
  `.onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .pageUp, .pageDown,
  .space, .home, .end])` through `ReaderMath.keyTurn` (Shift-Space back), and J / K for my
  next and previous line; the pager holds focus when the reader opens so a pedal's arrow turns
  the page (iOS 15.1+ would otherwise move focus).
- macOS: the same pager in the window's detail; plus the **Reader** menu (`.commands`,
  `FocusedValue(\.reader)`) with every key in macOS-DESIGN §4.7; a trackpad two-finger swipe
  is the scroll view's own.
- **Scroll** setting: `ScrollView { LazyVStack(alignment: .leading) { ForEach(lines, id: \.id) } }`
  with `.scrollPosition(id: $topLine, anchor: .top)`; the position is `topLine`.

**The rest**
- Top: Close, title over `placeOf` (act · scene, one line, `.subtitle` on iOS 26+), Contents,
  Search, Text as `ToolbarItem`s with `Label`s (the Duo's vertical strip needs symbol + title).
  Bottom: `Picker("I'm Playing", selection:)` in a `Menu` (Nobody, then speaking parts largest
  first with line counts), Next Line (`arrow.down.to.line`), Hide My Lines (`eye.slash`,
  a toggle), the page label (`ReaderMath.pageLabel`, `.monospacedDigit()`); Scroll shows a
  percentage.
- Contents: a `List` of `contentsOf` (acts, scenes indented), the current one checked; a row
  goes to its line. "This script prints no acts or scenes." when empty.
- Search: `.searchable` on a `List` over `searchScript`, rows of speaker + the words with the
  match in `.bold()` and a tint; "N lines · M more"; "No line has these words."
- Text: a sheet with `.presentationDetents([.medium])` (iOS) or a popover (Mac): `Stepper`-like
  A− / A+ with the percentage, a segmented `Picker` for spacing, another for Pages / Scroll.
  Stored in `UserDefaults` (`ed.reader.prefs`, the same JSON keys as the web).
- I'm Playing: the part's line backgrounds get a 9% tint and a 3 pt leading rule in the hue;
  Hide draws the said runs as rounded rects in the hue at 30% (draw over the text's fragment
  rects; never remove the text, so pages stay put); a tap on a hidden line peeks it until the
  next tap or turn. VoiceOver: a hidden line reads "Show line" and is a button.
- Position: `UserDefaults` `ed.reader.pos` (script id → `{line, part}`, newest 60), saved on turn
  (debounced) and restored on open; a deep link `eardrama://read/<id>?line=` is out of scope here
  (no path twin yet).
- Seams for later phases: `ScriptReaderView` takes an optional `dock: AnyView` slot (S3 studio)
  and exposes `follow(lineID)` through a small `@Observable ReaderController` (S1 read-along on
  the listen-through can call it; tvOS's panel shares `placeOf` and `lineText` only).
- iPad and the open Duo: the same view; two facing pages at ≥ 860 pt. No `ArrangementView` in
  S1 (that is S4's studio split). Closed Duo: one page.

**Apple tests**
- `ScriptReadingTests.swift`: §1's tests and the `ReaderMath` cases of `js/reader.test.js`
  (settings defaults, carried-over line, turns and spreads, swipe, tap zones, keys, labels, the
  re-layout keeping the line, `remember`).
- A pagination test over a real script picked from the data: paginate at two sizes, check
  every line has `starts <= ends`, pages are contiguous, and the line at the top of page N at
  size A is on its page at size B and back again (the web's re-layout case on real text).
- `apple/UITests`: open a play, tap Read, swipe twice, the page label changes; turn the device
  (iPad) and the top line is still on the page; Hide My Lines then tap a hidden line. Run the
  tap tier on the iPhone 12 and the iPad (`tools/ios_uitest.py`), read every frame.
- Builds: iOS, macOS and tvOS all build clean (tvOS compiles Core; the reader view is
  `#if os(iOS) || os(macOS)`), zero warnings.

## 4. S1: the reader on Android

**Files**
- `plays/ScriptReading.kt` (new; pure Kotlin): §1's functions and `ReaderMath`, `ReaderPrefs`
  (kotlinx-serialization, the same JSON keys as the web).
- `ui/screens/ReaderScreen.kt` (new): `ReaderScreen(scriptId, startLine)`, the pager, the
  sheets.
- `navigation/Routes.kt` (the sealed `Route : NavKey`): `Route.Reader(scriptId: String, lineId: String? = null)`; the reader
  hides the bottom bar (full screen, like the recorder).
- `ui/screens/PlaysScreens.kt`: Read (`TextButton`) beside Record this; `RecordScreen.kt` tiles
  a book `IconButton` in the window's corner; `HomeSections.kt` Today's play gets Read.

**Pagination**
- Measure with `rememberTextMeasurer()` on `Dispatchers.Default`: build one `AnnotatedString` of
  the whole script from `runsOf` (speaker `SpanStyle` semibold 0.8125 em in the hue; asides
  italic `onSurfaceVariant`; directions as `ParagraphStyle(textIndent)`; headings in the display
  family; a `StringAnnotation("line", lineId)` per line), then cut it into pages: measure with
  `constraints = Constraints(maxWidth = pageWidth)`, walk `getLineBottom` until the page height,
  start the next page at that line's start offset (`getLineStart`). Record `starts` / `ends` per
  line id from the annotations. Font scale: `LocalDensity.current.fontScale` × the reader step.
- Pages per screen: two when `currentWindowAdaptiveInfo().windowSizeClass` is expanded width and
  the reader has ≥ 860 dp, else one. Re-measure on size, font scale, fold posture and prefs;
  keep the position line exactly as Apple does (no backward drift).

**Turning**
- `HorizontalPager(state = rememberPagerState { spreadCount }, beyondViewportPageCount = 1,
  key = { it })`, each page a `Text(pageString)` drawn from the same measured layout (or a
  `Canvas` with `drawText(textLayoutResult)` so drawing equals measuring). Native fling slide.
- Taps on the outer fifth: `pointerInput { detectTapGestures }` → `animateScrollToPage(±1)`
  (`snap` under the system's animator scale 0 / Remove animations).
- Keys and pedals: `Modifier.onPreviewKeyEvent` for DPAD_LEFT/RIGHT/UP/DOWN, PAGE_UP/PAGE_DOWN,
  SPACE (+ shift), MOVE_HOME/MOVE_END, J/K; a `FocusRequester` on the pager when the screen
  opens. **Volume keys turn pages**: opt-in in Text, `KEYCODE_VOLUME_UP/DOWN` consumed only while
  the reader is shown and the switch is on.
- Scroll setting: `LazyColumn(state = rememberLazyListState())` keyed by line id;
  `firstVisibleItemIndex` is the position.

**The rest**
- `TopAppBar` (Close, title over `placeOf`, Contents, Search, Text icons with content
  descriptions); a bottom bar with `ExposedDropdownMenuBox` "I'm playing", Next line
  (`Icons.Outlined.VerticalAlignBottom` or the closest Material Symbol), Hide my lines
  (`IconToggleButton`, `VisibilityOff`), the page label (tabular figures).
- Contents, Search, Text: `ModalBottomSheet`s mirroring §3's words exactly.
- Hide: draw the said runs' bounding boxes (from `getPathForRange`) as rounded rects in the hue at
  30% over transparent text color for those spans; layout unchanged. TalkBack: a hidden line is a
  button labeled "Show line".
- Position and prefs: `SharedPreferences` (`ed.reader.pos`, `ed.reader.prefs`), JSON like the web.
- Not on a TV (`UiModeManager` TV branch hides Read).

**Android tests**
- `plays/ScriptReadingTest.kt`: §1's tests and the `ReaderMath` cases.
- `ui/ReaderPaginationTest.kt` (Robolectric + Compose test rule, or a pure test over a fake
  measurer): real-script pagination at two font scales, the position line kept and returned.
- Roborazzi frames of the reader at 360 dp and 840 dp, light and dark (pages, contents,
  rehearse), read before merging; then the Pixel 8a: open, swipe, DPAD keys via `adb shell input
  keyevent 22`, rotate, hide and peek. Android release waits for the version in review (memory).

## 5. tvOS (later; S1 only as a panel)

No reader. tvOS-DESIGN §4.13's read-along panel shares `placeOf`, `lineText` and the part hues;
it is built with the listen-through follow, not in this port.

## 6. PARITY and docs when each port lands

Flip the four PARITY rows (Script reader; I'm playing; Plays from the published library; Home's
Open parts) from ⏳ to 🚧 with what was seen on which device and date; quote the frames read.
SCRATCHPAD state, version bump per the memory rule, commit message quoting the owner.
