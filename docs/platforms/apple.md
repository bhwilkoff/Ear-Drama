# The Apple apps (iOS, iPadOS, macOS, tvOS)

Read this before any Swift work, and before choosing or changing a
deployment floor.

These rules lived in `AGENTS.md` until October 3, 2026, when it was cut
below 24,000 bytes so that Antigravity, which stops reading a rule file
at that size, would read all of it. They moved here word for word, and
`AGENTS.md` links to this page with one line saying when to read it. The
rules that hold on every platform stayed in `AGENTS.md`.

## Which skill

- **iOS / iPadOS**: `ios-production-gotchas` FIRST when a symptom
  matches (presentation races, dark-mode legibility, layout blowups,
  background audio, wrong image in a recycled cell, a new `.swift`
  file that won't compile, "works on simulator"). It carries the
  cross-cutting lessons from four shipped apps. Share-sheet targets:
  `ios-share-extension`. Framework depth
  lives in the 86 vendored Apple skills (swiftui-patterns,
  swiftui-navigation, swiftdata, ios-networking,
  swiftui-liquid-glass, app-intents, widgetkit, etc.).
- **macOS**: `macos-platform-patterns` BEFORE any Mac shell / player /
  hero / browse / window / document work. macOS shares the whole Apple
  Core, so the FEATURE set is free. But the shell is a pointer +
  keyboard + menu-bar + resizable-multi-window app, and the traps are
  Mac-only: player-as-window-root (not an overlay), no
  `externalMetadata` (title via the window title bar), the full-width
  16:9 hero with no height cap, the fill-image layout blowup, the
  `ImagePipeline` (never bare `AsyncImage`), and `NSWorkspace` for
  companion deep links.
- **tvOS**: `tvos-platform-patterns` BEFORE any UI / focus / layout /
  animation / image-pipeline / persistence work. The generic SwiftUI
  skills cover most of tvOS, but the focus engine, ten-foot rules,
  the writable-directory trap, and the shelf/hero/detail recipes are
  tvOS-only and were learned the hard way. Once the tvOS app passes
  ~3 core screens, adapt `docs/TVOS-PLAYBOOK.md` (already in the
  template) into your app's own playbook.

## Apple apps (iOS / iPadOS / macOS / tvOS): one universal target

**Stack**: Swift 6, SwiftUI (`@Observable`), SwiftData for local
persistence, Keychain for credential storage, URLSession direct to API
(no third-party packages).

**The floor is a floor, not a ceiling.** Each app chooses its
deployment targets by the hardware they reach, measured (test-build at
each candidate floor and count the errors), and holds them with
`tools/test_ios_floor.py` / `tools/test_tvos_floor.py` in
`appstore-build.yml`. The measured defaults from Archive Watch: **iOS 18**
(iOS 26 dropped the iPhone XS/XR; below 17 SwiftData and Observation
break), **tvOS 26, held below 27** (27 dropped the Apple TV HD and 4K 1st
gen), **macOS 26**. Newer APIs (Liquid Glass, `Tab(role: .search)`,
`scrollEdgeEffectStyle`, `.navigationTransition(.zoom)`, SpeechTranscriber)
are used fully on devices that have them, behind `#available`, with an
older path or an honest omission below. A stored property can't carry
`@available`: store it untyped behind a gated accessor. Anything older
than the native floor is the website's job. See `docs/path/03-going-native.md`.

**One Xcode target serves iPhone, iPad, Mac, AND Apple TV** (Decision
013, amended by Decision 019). Shared logic lives in `Core/`;
per-platform UI lives in `iOS/`, `macOS/`, and `tvOS/` groups behind
`#if os(iOS)` / `#if os(macOS)` / `#if os(tvOS)` guards. Production
experience: ~60–70% of a media app's Swift is platform-agnostic
(models, networking, query layer, playback-queue logic, sync). The
universal target makes that reuse real instead of aspirational, and
all three Apple platforms ride the same CloudKit private database for
free cross-device sync. macOS is the cheapest platform to add because
it reuses the entire Core.

**Project structure.** The agent generates the project; nobody clicks
through Xcode. `project.yml` (XcodeGen) is the source of truth and
`xcodegen generate` writes the gitignored `AppName.xcodeproj` at the
root. Sources stay in `apple/`. Change targets, settings, and
Info.plist keys in `project.yml`, never in Xcode's panels (the next
generate wipes them). See `apple/README.md`.

```
/                          ← repo root
├── project.yml            ← XcodeGen spec (source of truth)
├── AppName.xcodeproj/     ← generated at root, gitignored
├── apple/
│   ├── App/               ← entry point (#if os branches)
│   ├── Core/              ← platform-agnostic: Models, Networking,
│   │                        Store, query/queue/sync logic
│   ├── iOS/               ← iPhone/iPad views (#if os(iOS))
│   ├── macOS/             ← Mac views (#if os(macOS))
│   ├── tvOS/              ← Apple TV views (#if os(tvOS))
│   ├── Resources/
│   └── Tests/             ← Core tests (macOS test target)
├── AppVersion.xcconfig    ← shared version numbers (all Apple targets)
├── ci_scripts/            ← Xcode Cloud build scripts
├── index.html, css/, js/  ← Web app
└── android/               ← Android module (sibling; different toolchain)
```

**Critical conventions** (from production lessons across five
shipped platforms; see the vendored skills for depth):

- **All API calls through a shared singleton**, never URLSession
  directly from views
- **Auth state owned by one manager**; views read via `@Environment`
- **Global nav state in `@Observable` store** with one
  `NavigationPath` per tab; ONE shared destination registry
  (`navigationDestination` declared in a single place all tabs
  apply), never per-view destinations. This is what lets any
  surface push any screen from any tab.
- **Deep links / intents land in an inbox**, consumed by the root
  view once foregrounded. External entry points never mutate the
  router directly.
- **Version numbers via `AppVersion.xcconfig` only.** Never edit
  through the Xcode identity panel (it creates per-target overrides).
- **No third-party Swift packages.** Apple frameworks only.
- **URL routing via `.onOpenURL`** for both Universal Links and
  custom schemes, NOT `.onContinueUserActivity`
- **Refresh JWT before every Worker / Storage / Edge Function call.**
  The auth SDK's auto-refresh only covers its own HTTP path.
- **Core/ never imports per-platform UI.** When Core logic needs
  app state, define a protocol in Core and conform the app store to
  it. This is what keeps Core compiling for every os() target.
- **The rule is a value; the platform is a caller.** Decision rules
  (stall detection, sync correction, capability predicates) are pure
  functions with injected inputs in Core; the platform applies the
  returned value. That is the test seam and the port seam at once. A
  shared type is not a shared path: confirm which platforms run it.
- **Never put a fill-mode image (`scaledToFill`) inside a
  `frame(maxWidth: .infinity)`.** The frame adopts the oversized
  cover dimensions and blows the layout (intermittently, because it
  depends on which artwork loads). Ambient/hero art goes in
  `.background` + `.clipped()`, which cannot influence layout.

### macOS-specific guardrails (read `macos-platform-patterns` first)

- **The player REPLACES the split view as the window root while
  playing**, never an `.overlay`/cover on the split view (its
  toolbar, sidebar toggle, and the previous view's title bleed
  through over the player).
- **macOS `AVPlayerItem` has NO `externalMetadata`.** Show the title
  via the window title bar, never an `AVMutableComposition`
  metadata-override: over a resilient custom-scheme asset it renders
  BLANK video (audio advances, no picture). Tried + reverted twice.
- **A resizable-window hero is full-width `.aspectRatio(16/9, .fit)`
  with NO `maxHeight` cap.** A fixed height crops as the window
  widens; a cap insets/centers ("doesn't extend across"). The same
  fill-image layout blowup as iOS applies: a sized shape owns
  layout, the image fills via `.background`.
- **Never bare `AsyncImage` for browse art.** Route through an
  `ImagePipeline` (decoded `NSCache` + one `URLSession` capped at
  `httpMaximumConnectionsPerHost = 6` + in-flight coalescing), and
  decode non-8-bit-RGB → sRGB once (`Image(nsImage:)`'s Metal path
  renders a grayscale/CMYK image as a solid white box).
- **Structured concurrency (`.task(id:)`), not Combine
  `Timer.publish`** for hero rotation / debounce. A timer can fire
  into a torn-down view and trip an executor fault.
- **Companion-app deep links via `NSWorkspace`**, NOT
  `UIApplication`; and NO `LSApplicationQueriesSchemes` Info.plist
  entry on macOS (that array is an iOS privacy restriction).
- **Guard next-OS-only symbols with `#if compiler(>=X.Y)`, not just
  `#available`.** A runtime `#available` check still needs the
  symbol in the BUILD SDK, so it won't compile on the GA toolchain.
- **Every command is in the menu bar**, wired through `.commands`;
  disable, never hide.
- **A Mac button says what it does at every window width**:
  `ViewThatFits` over designed arrangements, `.fixedSize()`, the rest in
  a native More menu. Never truncation, wrapping, or icon-only.
- **A view being rebuilt is not a window being closed.** A closing
  window stops its playback; a rebuilt view first asks whether something
  longer-lived still uses the resource.

### tvOS-specific guardrails (read `tvos-platform-patterns` first)

- **Never `buttonStyle(.plain)` on tvOS.** It destroys focusability.
  Use `.borderless`, `.card`, or a custom `ButtonStyle`.
- **tvOS can only write to `Library/Caches`, `tmp`, and App Group
  containers.** Application Support writes crash on device (and
  pass on the simulator, so you won't see it until hardware).
  SwiftData's default store location crashes too: build the
  ModelContainer with an explicit App Group `ModelConfiguration`
  and fall back to in-memory so the app always launches.
- **Reset a tab's `NavigationPath` when the user leaves it via the
  sidebar**; otherwise tab state pollutes the next visit.
- **Initial-focus views (heroes, first-tab landings) claim focus
  exactly once** (a `hasClaimedInitialFocus` guard). A bare
  `.task { focused = true }` re-fires when lazy views recycle and
  yanks focus back mid-browse.
- **A held Select is a card's second verb** (`.contextMenu`); after its
  question closes, focus returns to the same card or its neighbor, never
  to the sidebar.
- **SourceKit phantom errors are stale index, not real.** Trust
  `xcodebuild`, not editor squiggles. `@Query` macro views can
  cascade unrelated "Cannot find X in scope" errors across a file.
