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
`EarDrama.xcodeproj`. The agent runs it. You only open Xcode if you
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
   xcodebuild -project EarDrama.xcodeproj -scheme EarDrama \
     -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
   xcodebuild -project EarDrama.xcodeproj -scheme EarDrama \
     -destination 'generic/platform=tvOS Simulator' CODE_SIGNING_ALLOWED=NO build
   xcodebuild -project EarDrama.xcodeproj -scheme EarDrama \
     -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build
   ```

6. Run the Core tests: `xcodebuild test -project EarDrama.xcodeproj
   -scheme EarDrama -destination 'platform=macOS'
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

## The catalog: a bundled seed, then the full download

The apps read the served SQLite projection (`docs/CATALOG-CONTRACT.md`
§3) on disk, read-only, through `Core/Catalog/CatalogDatabase.swift`.
A database is **never committed**. Two files are involved:

- **The seed**, bundled in the app so the first launch works offline.
  The target's "Bundle catalog seed" build phase copies
  `$(CATALOG_SEED_PATH)` into the app as `ear-drama-seed.sqlite`. It
  defaults to `catalog/out/publish-clean/ear-drama.sqlite` (gitignored
  pipeline output, 6.2 MB, the clean pools only). Build it with
  `cd catalog && python3 tools/build_projection.py --clean-only --out
  out/publish-clean`, or point the setting at another copy:
  `xcodebuild ... CATALOG_SEED_PATH=/path/to/ear-drama.sqlite`. With no
  file there the build still succeeds, says so in its log, and the app
  shows "Catalog unavailable" until the download lands. CI must
  provide the file before an archive.
- **The full catalog**, `ear-drama.sqlite.zz` from the `catalog-latest`
  Release. Its address is the one constant `CatalogSource.releaseURL`.
  `CatalogRefreshService` (ported from Archive Watch) fetches it with
  an ETag, inflates raw DEFLATE in 64 KB chunks into Caches (tvOS may
  write nowhere else), refuses anything under a size floor or failing
  `PRAGMA integrity_check` or the schema check, and renames it into
  place as a new generation. While the URL does not answer, the app
  stays on the seed.

The Core tests read the same seed path (or `TEST_RUNNER_CATALOG_SEED_PATH`).

## Layout

```
apple/
├── App/                 ← entry point; #if os branches live here
│   └── EarDramaApp.swift
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
(in `EarDramaApp.swift`) branches EXPLICITLY per platform. A bare
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
  fallback chain (see `EarDramaApp.swift`).
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

## CarPlay and Apple Watch: stubs until the core five are done

Decision 056 makes both of these stubs for 1.0: a target that builds in
CI and launches, with its PARITY.md column marked ⏳. Each grows out of
the core's shared code. Neither one is a second feature set.

### CarPlay (in the iOS slice, `iOS/CarPlay_iOS.swift`)

**What is there.** `AppDelegate_iOS` (connected with
`@UIApplicationDelegateAdaptor`) sends a CarPlay scene session to
`CarPlaySceneDelegate`. Every other scene gets back the configuration
the system already gave it. The car's first screen is a
`CPTabBarTemplate` with the four car tabs (R17): **Continue**,
**Radio**, **Series**, and **Downloads**. Continue lists up to 12
in-progress episodes from the phone's own `ListeningHistory`, most
recent first, with the listened fraction shown on each row. Picking
one plays it through the shared `AudioPlayer` and pushes
`CPNowPlayingTemplate.shared`, which reads the Now Playing info and
remote commands the player already publishes. The other three tabs are
empty lists that say "Not in the car yet". There are no transcripts on
the car screen. CarPlay forbids lyrics, and a transcript counts as
lyrics.

**Why it is dormant.** iOS connects a CarPlay scene only for an app
signed with `com.apple.developer.carplay-audio`. Apple has not granted
that entitlement yet. Until it does, nothing calls this code: the
phone app builds, signs, and runs exactly as before. The scene also
cannot be tried in the CarPlay Simulator or in a car until the
entitlement is granted.

**What the owner does to switch it on** (research 04 §2.6):

1. Request the CarPlay **audio** entitlement for `app.eardrama` at
   developer.apple.com/contact/carplay and agree to the CarPlay
   Entitlement Addendum. Apple grants it per bundle ID. It is a
   calendar item, not code, and only one CarPlay category is allowed
   per app.
2. When Apple grants it, enable "CarPlay Audio App (CarPlay framework)"
   under the App ID's Additional Capabilities, then make a new App
   Store provisioning profile for `app.eardrama`.
3. The agent then adds the entitlement, and only then:
   `apple/Resources/EarDrama_iOS.entitlements` holding
   `com.apple.developer.carplay-audio` = `true`, set in `project.yml`
   as `"CODE_SIGN_ENTITLEMENTS[sdk=iphone*]"` so that tvOS and macOS
   never carry it. The cloud archive signs manually
   (`apple-app-store-cli-submission`), so the new profile has to go
   into that pipeline's secrets. Adding the key before the grant would
   break every signed build: no profile could carry it.
4. Once it is signed, the scene shows up in the CarPlay Simulator and
   in a car. Building out the car screen comes after that: Radio,
   Series paged to stay within 12 rows and 5 screens, Downloads, and
   the sleep timer (R20) as a Now Playing button.

### Apple Watch (target `EarDramaWatch`, `watchOS/`)

**What is there.** A watchOS app whose first screen is a **Continue**
list. It shares Core's `ListeningHistory` and nothing else. The
generated `Design.swift` does not compile on watchOS
(`UIColor(dynamicProvider:)` is unavailable there), so the watch takes
the system tint until `tools/design_tokens.mjs` writes a watchOS branch. There is no catalog, no seed, and no download on the
watch. On the watch, history starts empty, so the list says "Waiting
on the phone" until the build-out hands the phone's history over
(research 04 §2.7: Continue and downloads only). It is not embedded in
the phone app yet. Embedding comes with the build-out, once the watch
has something to show. Build it with
`-scheme EarDramaWatch -destination 'generic/platform=watchOS Simulator'`.

**Floor: watchOS 11.0.** A watch on watchOS 11 pairs with an iPhone on
iOS 18, and iOS 18 is this app's iOS floor. So every phone the app
serves can have a watch the app serves. watchOS 11 and watchOS 26 run
on the same hardware (Series 6 and later, SE 2nd generation, every
Ultra). A higher floor would add no capability the stub uses, and it
would drop watches that have not updated. Below 11 there is no gain
either: watchOS 10 needs an iPhone on iOS 17, which is below the phone
floor. `@Observable` needs watchOS 10, so 11 clears that too.

## What to bring back

Three green builds and a passing test run, from one command line.
