# [APP NAME] macOS Design (BINDING)

<!-- Seed for docs/macOS-DESIGN.md (you create this). Invoke
     `binding-design-doc-discipline` for the workflow and
     `macos-platform-patterns` for the mechanics this doc does NOT restate.

     STRUCTURE: two parts.
       - PART A: a Mac-EXCLUSIVE heavy feature (a document-based
         workspace / editor / analysis tool the touch/TV/web platforms
         structurally cannot host). DELETE Part A entirely if the Mac
         app is parity-only.
       - PART B: the shared parity face. KEEP Part B. Its rules are
         macOS PLATFORM TRUTHS, true for ANY Mac app on a shared Core:
         the scene/window model, sidebar nav, the fill-image trap, the
         grayscale→white decode bug, the one image pipeline,
         structured-concurrency-not-Combine-timers, sandbox/capabilities.
     Shipping/submission lives in `docs/CLOUD-SUBMISSION.md` +
     `cloud-appstore-submission`. Reference it; don't duplicate it.

     Sections marked "(optional module)" apply only if the app has that
     surface (e.g. B3 media/player). Replace every [BRACKET]; delete the
     <!-- FILL --> notes. -->

**Status: binding.** Quote the relevant rule before proposing any new
window, scene, view, sheet, or feature. Amendments are append-only. Never
silently contradict a rule; amend it with a dated note and a reason.

Division of labor: **this doc** is the binding macOS contract.
**`macos-platform-patterns` skill** holds the mechanics + failure modes.
**`PARITY.md`** says what ships where (same change set). **`DECISIONS.md`**
holds the why. The Mac app is **NOT the iOS app resized**. Build
Mac-native (windows, inspectors, menu commands, pointer+keyboard).

---

# PART A: [The Mac-exclusive heavy feature]

<!-- DELETE PART A if the Mac app is parity-only. Otherwise this is the
     app-agnostic frame for ANY heavy, document-based, Mac-only feature:
     an editor, a workspace, a batch/analysis tool. -->

## A1. Scope & the Mac-only thesis

The Mac app is two things: (1) a **parity face** on the shared Core
(Part B), and (2) **[the exclusive feature]**, a
[document-based / heavy-compute] workspace.

**The Mac-only thesis (binding):** [the feature] belongs only on macOS
because it structurally requires things the touch/TV/web platforms
cannot host: [a full filesystem + document model / subprocess CLI
tools / heavy long-running background compute / a
pointer+keyboard+menu+multi-window workspace]. Do not port touch idioms
(full-screen modal editors, one-pane navigation, drag-handle-only
interaction).

## A2. App & scene architecture

One macOS target, multiple SwiftUI scenes:
- `WindowGroup "[Main]"`: the parity face (Part B).
- `DocumentGroup` bound to the `.[ext]` document: the workspace.
- `Window "[long-running queue]"`: single-instance background work.
- `Settings`: accounts, storage, defaults.

- **Rule A2a: app-global library ≠ document.** State that is global to
  the app (SwiftData + iCloud) is NOT a document; the document is the
  document. (This is the Final Cut Pro split between the event browser
  and the project.) Never store the global library inside a document;
  never make a document carry copied source data.
- **Rule A2b: the document is a REFERENCE package.** A
  `UTType(exportedAs:)` `.package` holding the model + references +
  local imports, never large source bytes. Budget an `NSDocument`
  backbone for URL access, atomic/async save, and security-scoped
  bookmarks (de-risk this seam FIRST, because it is the weakest).
- **Rule A2c: reuse the Core, rebuild only the shell.** Reuse the data
  layer, models, networking, sync verbatim. New code goes in the Core
  only if all platforms could use it.

## A3. The engine *(if the feature has a compute/render engine)*

- **Rule A3a: one model, one output, preview == result.** The working
  model compiles to a single artifact that feeds BOTH the live preview
  and the final output. The user must get exactly what they previewed.
- **Rule A3b: rebuild-and-swap, never mutate live.** Each edit
  recompiles and swaps; never mutate an object attached to a running
  preview/engine.
- **Rule A3c: Apple frameworks in-app; heavy CLI as subprocess** for
  what the frameworks can't do cleanly. That is the Mac advantage, not a
  workaround. **If the app is sandboxed for the App Store, a subprocess
  CLI can't run inside the sandbox** (and its license may be
  store-hostile), so prefer the Apple-native path.

## A4. Remote sources & caches *(if the feature works on remote data)*

- **Rule A4a: references, never copies.**
- **Rule A4b: cache-then-process, NEVER stream-into-process.**
  Long-running sessions are unreliable against remote URLs. Pre-fetch
  only the needed range to a local file → process from local files.
  (Usually the single biggest reliability risk.)
- **Rule A4c: probe the container/index before any byte math.**
- **Rule A4d: cache is disposable, references are truth.** LRU
  eviction, pin what open documents need; caches in `Library/Caches`,
  never synced.

## A5. The learning gate *(if the app is a learning/creation tool)*

- **Rule A5a: the no-auto-do-it-all gate.** Any "automatic" feature
  MUST produce an **editable set of candidates**, never a one-tap
  finished output. Automate the mechanical; preserve the meaningful
  choices (AGENTS.md "Why we build" + `learning-orientation-design`).
- **Rule A5b: [provenance/attribution stance]**, if the app produces
  shareable output.
- **Rule A5c: [eligibility gate].** Only eligible inputs enter the
  workspace, if the app has content-rights or similar constraints.

## A6. Data planes (no backend, binding)

Three planes, never a server: (1) shared read-only indices on a
Release/Pages (`shared-data-plane-contract`); (2) a user annotation
layer (SwiftData + iCloud, references only); (3) device-local,
never-synced, re-derivable caches. If you allow "not third-party
packages" like a SQLite extension or a Core ML model, state that rule;
heavy tooling stays subprocess/CI.

## A7. UI contract (SwiftUI shell, AppKit where it must)

- **Rule A7a: SwiftUI shell.** `NavigationSplitView`, `.inspector()`,
  `.toolbar(id:)`, `.contextMenu(forSelectionType:)`, menu-bar
  `.commands`, `Transferable` drag-drop.
- **Rule A7b: AppKit bridges only where SwiftUI stutters.** A
  canvas/timeline as `NSView`+`CALayer` in `NSScrollView` (magnification
  + hit-testing); a large collection migrates `LazyVGrid` →
  `NSCollectionView` (reuse/prefetch/reliable hover); modeless keys via
  an `NSEvent` local monitor.
- **Rule A7c: keyboard-first, one coherent scheme** wired to the menu
  bar for discoverability.

## A8. De-risk spikes (before Phase 1 commits)

1. The `NSDocument` save + URL + security-scoped-bookmark seam.
2. The AppKit canvas/collection scroll/zoom/hit-test prototype.
3. One real cache-then-process round trip end-to-end (Rule A4b).

<!-- Keep an append-only "Phase N progress log" per phase. The real doc
     grows a log of what each phase learned. -->

---

# PART B: The shared parity face (browse / detail / library)

*The native-Mac window on the shared Core, NOT the iOS app resized
(A1). Each rule below is a macOS platform truth; quote it before
changing a surface.*

## §B1: Scene graph & navigation

Scenes in order: `WindowGroup("[App]")` (root, `minWidth [960] ×
minHeight [600]`) → [`DocumentGroup`] → `Settings`.

- **Rule B1a: ⌘N semantics are explicit.** A WindowGroup-first app
  with a DocumentGroup binds ⌘N to a new main window; if ⌘N should
  create a DOCUMENT instead, re-point it with `CommandGroup(replacing:
  .newItem)` → `NSDocumentController.shared.newDocument(nil)`. Bind your
  primary create command deliberately.
- **Rule B1b: navigation = a sidebar `Section` + ONE `NavigationPath`,**
  NOT the iOS per-tab stack. A `section` enum + one path feed a single
  `NavigationSplitView` detail column.
- **Rule B1c: `ModelConfiguration(cloudKitDatabase: .none)`.** Sync is
  MANUAL (not SwiftData auto-mirroring); it fires on sign-in +
  `scenePhase == .active`. App `init` sets `URLCache.shared` (the image
  pipeline depends on it, §B4b).
- Deep links (`.onOpenURL` + `NSUserActivityTypeBrowsingWeb`) resolve
  into the detail column.

## §B2: Full-screen surfaces replace the split view as the window root

- **Rule B2a: an immersive surface [a player, an editor canvas, a
  screensaver] REPLACES the split view as the window root**, not an
  overlay on it. WHY: an overlay leaves the split view owning the window
  toolbar, so its sidebar toggle + the previous view's title bleed
  through over the immersive surface. As root, the surface's own chrome
  (title + close) is the only chrome. Never reintroduce an immersive
  surface as an overlay/cover on the split view.

## §B3: Player *(optional module; delete if no media)*

<!-- KEEP only if the app plays audio/video. macOS platform facts. -->

- **Rule B3a: `AVPlayerView`, `controlsStyle = .floating`** (the native
  macOS HUD: transport, scrubber, PiP, AirPlay, full-screen). Speed is
  the **native HUD** (`v.speeds = AVPlaybackSpeed.systemDefaultSpeeds`).
  Do NOT bolt on a custom Speed menu.
- **Rule B3b: resilient media via a shared loader** (retain it for the
  asset's lifetime); `resilient-media-streaming`.
- **Rule B3c: resume + periodic save every ~5 s** via a periodic time
  observer (macOS saving only on close loses a crashed session).
- **Rule B3d: the on-screen title rides the WINDOW TITLE BAR**
  (`navigationTitle`), NOT player metadata. macOS `AVPlayerItem` has **no
  `externalMetadata`** (iOS/tvOS only). The only way to override a file's
  embedded title is to wrap the asset in an `AVMutableComposition`, which
  over a custom-scheme resilient asset renders BLANK video. Do NOT retry
  the metadata-override.

## §B4: Images (three rules, one pipeline)

<!-- These apply to ANY Mac app that shows remote images (thumbnails,
     avatars, artwork, covers). -->

- **Rule B4a: the fill-image layout trap (one fix, everywhere).** A
  fill-mode image reports oversized "cover" dimensions; a
  `maxWidth:.infinity` frame ADOPTS them → cards overlap / a hero
  overflows. Fix: a SIZED shape owns layout, the image fills via
  `.overlay`/`.background`.
- **Rule B4b: all browse images go through ONE `ImagePipeline`, never
  bare `AsyncImage`.** Bare AsyncImage re-decodes/re-downloads on every
  reveal and bursts unlimited connections (hosts throttle → "images load
  slowly"). The pipeline: an `NSCache` of DECODED images + a single
  `URLSession` capped at `httpMaximumConnectionsPerHost` (reusing the
  URLCache) + in-flight coalescing.
- **Rule B4c: decode non-RGB images to sRGB before SwiftUI (the
  grayscale→white bug).** `Image(nsImage:)`'s Metal path renders a
  1-component grayscale (or CMYK/16-bit) image as a SOLID WHITE box.
  Redraw any non-8-bit-RGB image into sRGB RGBA once, in the pipeline.

## §B5: A full-width hero *(optional; delete if none)*

- **Rule B5a: a full-width banner is full-width AND aspect-locked with
  NO height cap:** `.frame(maxWidth: .infinity).aspectRatio([ratio],
  contentMode: .fit)`. Height tracks width, so the image fills it exactly
  and is never cropped at any window width. Two traps: a FIXED height
  crops as the window widens; a `maxHeight` cap makes the aspect-fit box
  narrower than the window (inset/centered → "doesn't extend across").
  (Mac windows resize; iOS/tvOS use a fixed height because device width
  is fixed.) Rotate via structured concurrency, not a Combine timer
  (§B7).

## §B6: Sync touch-points

Removals propagate via `Tombstone` keys; list merges use recency. All
rely on the foreground/sign-in sync; an immersive surface that mutates
state additionally nudges promptly so devices converge
(`per-ecosystem-sync-islands`).

## §B7: Native-platform-first + structured concurrency

- Binding everywhere: native HUD controls (no hand-drawn transport),
  `.searchable` toolbar field, native `Form` sheets,
  `NSWorkspace.urlForApplication(toOpen:)` for companion-app install
  detection (**NO Info.plist `LSApplicationQueriesSchemes` on macOS;
  that is an iOS restriction**). A document is named by its FILE, never
  by an in-app title field.
- **Replace Combine `Timer.publish` with `.task`-based loops** in any
  view (a rotating hero, a screensaver, a search debounce): a Combine
  timer delivering into a `@MainActor` closure can trip a Swift-runtime
  executor fault and fire into a torn-down view. `.task(id:)` is
  auto-cancelled/restarted by SwiftUI.

## §B8: Launch / test hooks

`[APP]_START_[…]` env vars land on a section / open an item, inert
unless set. Needed because SwiftUI's a11y tree isn't reliably
AppleScript-traversable, so screenshots capture by REGION from AX window
bounds (see `docs/CLOUD-SUBMISSION.md`).

## §B9: Capabilities, identifiers, Info.plist

- **Shared with the other Apple platforms** (one App Store Connect
  record): bundle id, CloudKit container, App Group, Associated Domains.
- **Sandbox** (App Store requirement): app-sandbox + network.client +
  files.user-selected + [device.microphone/audio-input ONLY if you
  record; a sandboxed app needs the mic entitlement or TCC silently
  denies].
- `LSMinimumSystemVersion = [floor]`, `LSApplicationCategoryType`,
  `ITSAppUsesNonExemptEncryption = false`, usage-description strings. If
  the target shares a Core, wire it via `fileSystemSynchronizedGroups`
  pointing at the same folder with `#if os()` guards, never copied.

<!-- Shipping the Mac app (CLI submission; the two post-upload
     rejections ITMS-90111 [Xcode/SDK floor] and ITMS-90301 [built on a
     beta OS]; the cloud build that fixes both) lives in
     docs/CLOUD-SUBMISSION.md + `cloud-appstore-submission`. Reference
     it; don't duplicate it. -->

## §B10: Every command is in the menu bar

A Mac person reaches for the menu bar to learn what an app can do, so
anything the app can do lives there too, even when a button already
does it (HIG). Menus run App, File, Edit, View, then [the app's menus,
general to specific: Go, the item's menu, Controls], then Window, Help.
Go carries the sidebar sections (⌘1 onward), Search ⌘F and Back ⌘[.
No menu item takes a bare key, because a letter in the menu bar is
taken from every text field. A command that belongs to one kind of
window is enabled only while that window is key (`focusedSceneValue`),
and is disabled rather than hidden everywhere else. Help points at a
real page. Verify by reading the menu bar back through Accessibility
and pressing the items. Mechanics: `macos-platform-patterns` Rule 12.

## §B11: A button says what it does at every window width

Never truncated, never wrapped, never reduced to an icon. A row of
actions has a small fixed set of primary buttons, and the rest fold
into one native More menu whose items keep their full names. The
arrangement is picked by `ViewThatFits` over layouts that were each
designed, with `.fixedSize()` on every control and on the row. Each
action is declared once and rendered as either a control or a menu
item. Any label that means something (a name under a portrait) gets two
lines before it gets an ellipsis. Mechanics: `macos-platform-patterns`
Rule 13.

## §B12: Put the control on the thing *(if the app edits a picture, a canvas, or a layout)*

When a control describes something already on screen, the person
manipulates that thing directly: drag to move, a corner to resize, an
edge to reshape, scroll to zoom. A readout and a Reset sit beside it
for precision. Sliders in a separate column are not the design.
[Name the surfaces this applies to.] Mechanics and the two AppKit event
traps (`.offset` is render-only; `scrollWheel` needs a local monitor):
`macos-platform-patterns` Rule 14.

## §B13: Closing a window ends what it was doing

The red button is a close, not a quit. A window that closes stops its
playback, ends any session it owns, and clears now-playing, so
reopening from the Dock lands on the browse root rather than a second
copy of something the person thought they closed. And a view that
SwiftUI rebuilds is not a window closing: before a surface releases a
resource, it asks whether something longer-lived is still using it.
[List each resource a window owns and what ends it.]

---

*Amend, don't contradict. New views/features quote the rule they satisfy
or the amendment they propose.*
