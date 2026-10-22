# apple/: the Swift source for one universal Apple target

One Xcode target builds **iPhone, iPad, Mac, and Apple TV**
(Decision 013, amended by Decision 019). I want you to get there
without ever clicking through Xcode's New Project sheet. Every step
of that sheet is a setting, and a setting can be written down.

The project is generated, not created by hand.

`project.yml` at the repo root describes the whole thing: the target,
its four destinations, the deployment floors, Swift 6 settings, the
asset catalog, the generated Info.plist, and a Core unit-test target.
[XcodeGen](https://github.com/yonaskolb/XcodeGen) turns it into
`AppName.xcodeproj`. The agent runs it. You only open Xcode if you
want to look.

## Creating the project (the agent does this at M0)

1. Install the generator once: `brew install xcodegen`.
2. Rename the app in `project.yml`: the `name`, the `AppName` target,
   `PRODUCT_NAME`, the `AppNameTests` references, and
   `INFOPLIST_KEY_CFBundleDisplayName`. No spaces in the name (Xcode
   Cloud and every shell script depend on it).
3. Set your bundle ids: `bundleIdPrefix` and both
   `PRODUCT_BUNDLE_IDENTIFIER` lines. Match `BID_FILTER` and
   `PROJECT` in `tools/submit-appstore.sh`.
4. Generate: `xcodegen generate`. It writes the `.xcodeproj` at the
   repo root.
5. Build all three platforms, unsigned, before the first commit:

   ```sh
   xcodebuild -project AppName.xcodeproj -scheme AppName \
     -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
   xcodebuild -project AppName.xcodeproj -scheme AppName \
     -destination 'generic/platform=tvOS Simulator' CODE_SIGNING_ALLOWED=NO build
   xcodebuild -project AppName.xcodeproj -scheme AppName \
     -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build
   ```

6. Run the Core tests: `xcodebuild test -project AppName.xcodeproj
   -scheme AppName -destination 'platform=macOS'
   CODE_SIGNING_ALLOWED=NO`.
7. Check the floors: `python3 tools/test_ios_floor.py` and
   `python3 tools/test_tvos_floor.py`.

From now on, any change to a `Core/` file means building all three
again.

## project.yml is the source of truth

The `.xcodeproj` is gitignored. CI regenerates it
(`appstore-build.yml`, `ci_scripts/ci_post_clone.sh` for Xcode Cloud,
and `tools/submit-appstore.sh` all run `xcodegen generate` first).

So a change you make inside Xcode's settings panels is wiped on the
next generate. Add a file under `apple/` and regenerate; change a
build setting, a capability, or an Info.plist key in `project.yml`
and regenerate. That is the cost of this choice: one more tool, and
one rule to remember. In exchange, the project is a readable file
the agent can edit and review like any other.

A few things the spec already carries, so nobody has to set them:

- **Versions** come only from `AppVersion.xcconfig`, set on Debug and
  Release. Never edit them through Xcode's identity panel; a
  per-target copy shadows the xcconfig and the targets drift
  (Decision 003).
- **Signing** is automatic with `DEVELOPMENT_TEAM` left empty in the
  template. Simulator builds need no team. For a device build, put
  your Team ID in `project.yml` in your app, or pass
  `DEVELOPMENT_TEAM=...` to `xcodebuild`. The cloud archive passes
  it from `ASC_TEAM_ID`.
- **Floors**: iOS 18.0 (keeps the iPhone XS and XR that iOS 26
  dropped), tvOS 26.0, macOS 26.0. The floor tests hold them in CI.
- **Mac App Store sandbox** comes from build settings
  (`ENABLE_APP_SANDBOX`, outgoing network only). Add a scope only
  when a feature needs it.

## Layout

```
apple/
├── App/                 ← entry point; #if os branches live here
│   └── AppNameApp.swift
├── Core/                ← compiles for EVERY os() destination
│   ├── Models/          ← data models (platform-agnostic)
│   ├── Networking/      ← APIClient singleton
│   └── Store/           ← @Observable global state
├── iOS/                 ← iPhone/iPad views (#if os(iOS))
├── macOS/               ← Mac views (#if os(macOS))
├── tvOS/                ← Apple TV views (#if os(tvOS))
├── Assets.xcassets/     ← iOS icon; tvOS needs its OWN brandassets (below)
├── Resources/Fonts/
└── Tests/               ← Core tests (the AppNameTests target, macOS)
```

The folder stays where it is. The generated project points at it;
nothing gets dragged into an Xcode group.

**The Core rule**: `Core/` never imports per-platform UI and never
contains an `#if os` that selects UI behavior. When Core logic needs
something from the app layer, define a protocol in Core and conform
the app store to it. This rule is what keeps 60 to 70 percent of the
code shared instead of drifting into copies. It is also why the test
target compiles `Core/` directly rather than hosting the app.

**File-suffix convention**: per-platform files end `_iOS.swift`,
`_macOS.swift`, or `_tvOS.swift` and wrap their contents in
`#if os(iOS)`, `#if os(macOS)`, or `#if os(tvOS)`. All three view
trees live in the same target with no exclusion lists. `RootView`
(in `AppNameApp.swift`) branches EXPLICITLY per platform. A bare
`#else` silently hands a new platform the iOS view.

If you are skipping a platform (Decision 014), keep the full split
anyway and drop the destination from `supportedDestinations`. It
costs nothing now and leaves the door open. macOS in particular is
nearly free to add later since it reuses the whole Core.

## tvOS specifics the iOS docs will not tell you

- **App icon**: tvOS uses a **layered imagestack** ("App Icon & Top
  Shelf Image" brandassets), not a flat PNG. Layers are LANDSCAPE
  (400×240 / 800×480 / 1280×768 @1x/@2x). Square renders fail
  actool only on CLEAN builds, so verify with a from-scratch build.
  Until the set exists, `project.yml` names no tvOS icon; point the
  two `[sdk=appletv*]` icon lines at it when it lands. See
  `branding/README.md`.
- **Persistence**: only `Library/Caches`, `tmp`, and App Group
  containers are writable on device. The simulator is lenient and
  will not catch violations (Decision 017). Build your
  ModelContainer with an App Group `ModelConfiguration` and a
  fallback chain (see `AppNameApp.swift`).
- **Focus**: read the `tvos-platform-patterns` skill before writing
  any tvOS view. `ContentView_tvOS.swift` is a focus-correct
  starting shape.
- **Top Shelf** (later): a second target in `project.yml` (a
  `TVTopShelfContentProvider` extension) reading a snapshot JSON from
  the App Group that the main app refreshes via `BGAppRefreshTask`.

## macOS specifics the iOS docs will not tell you

Read the `macos-platform-patterns` skill before writing any Mac view;
`ContentView_macOS.swift` is a correct starting shape.

- **Shell** is a `NavigationSplitView` (a sidebar `Section` enum and
  ONE `NavigationPath` feeding a single detail column), not the iOS
  per-tab stack. Menu-bar `.commands` for a keyboard-first scheme.
- **Player** replaces the window root while playing (not an overlay).
  macOS `AVPlayerItem` has NO `externalMetadata`, so show the title
  in the window title bar. NEVER an `AVMutableComposition`
  metadata override (it blanks video over a resilient asset).
- **Hero** is full-width `.aspectRatio(16/9, .fit)` with NO
  `maxHeight` cap (a resizable window crops with a fixed height and
  insets with a cap). The same fill-image layout blowup as iOS
  applies.
- **Images**: never bare `AsyncImage`. Route through an
  `ImagePipeline` (decoded `NSCache` and one capped `URLSession`);
  decode non-8-bit-RGB to sRGB (Metal renders grayscale as white).
- **App Store**: the sandbox (only the scopes you use), Hardened
  Runtime, `AppIcon.icns`, `PrivacyInfo.xcprivacy`, and
  `LSApplicationCategoryType` (set in `project.yml`; pick yours). A
  sandboxed mic feature needs the `device.microphone` and
  `device.audio-input` entitlements AND the usage string, or TCC
  silently denies.
- **Deep links to companion apps**: `NSWorkspace`, not
  `UIApplication`; no `LSApplicationQueriesSchemes` entry on macOS.

## What to bring back

Three green builds and a passing test run, from one command line.
