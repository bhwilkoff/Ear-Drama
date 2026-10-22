---
name: macos-platform-patterns
description: "Use before any macOS app shell / player / hero / browse / window / document / image work. The macOS umbrella skill — the pointer+keyboard+menu+resizable-multi-window rebuild of a shared app (never the iOS app resized), the NavigationSplitView shell, when to drop to AppKit, player-as-window-root, the no-externalMetadata trap, the full-width hero + fill-image layout trap, the ImagePipeline + grayscale-decode fix, structured-concurrency-not-Combine-timers, NSWorkspace companion deep links, Mac App Store sandbox/TCC requirements, and the Library≠Project frame for a heavy Mac-exclusive feature. Triggers on macOS, Mac app, NavigationSplitView, .commands, WindowGroup, DocumentGroup, NSView, NSCollectionView, AVPlayerView, NSWorkspace, App Sandbox, hardened runtime, macOS hero, \"the player bleeds through\", \"hero doesn't extend\", grayscale poster, \"resized iOS app\", menu bar, truncated button, ViewThatFits, More menu, slider, scrollWheel, .offset hit-test, window close stops playback."
---

# macOS Platform Patterns

A compact reference for building a native **macOS** face of a multi-platform app. Most generic SwiftUI/iOS skill content applies — but the **shell, windowing, menu bar, pointer+keyboard interaction, the player, the hero, the image pipeline, and the AppKit escape hatches** are macOS-specific and have to be learned the hard way otherwise.

If the question is purely SwiftUI state/composition and applies on iOS too, use the generic SwiftUI skills. This is the **macOS-only complement**.

## When to invoke

- Building or debugging any macOS window, scene, document, or shell
- Designing a Home / Browse / Detail / Player / Library screen for the Mac
- The player looks wrong (a previous title / sidebar / toolbar shows through)
- A hero or poster doesn't fill / crops as the window resizes, or renders as a solid white/gray box
- Deep-linking into a companion Mac app
- Preparing App Sandbox / hardened runtime / privacy entitlements for the Mac App Store
- Scoping a heavy Mac-exclusive feature (a document editor / pro tool)

---

## Rule 1 — macOS is full-parity, but a pointer+keyboard+menu+multi-window app, NOT the iOS app resized

Reuse the **shared app Core verbatim** (data layer, models, resilient media loader, sync service — the Mac joins the Apple sync island for free, same CloudKit container as iOS/tvOS). Rebuild ONLY the Mac-native UI shell. **Why**: the Core is already platform-agnostic; the cost of a Mac port is the UI, not the backend. Guard any shared UIKit-only code with `#if os(iOS)` / `#if canImport(UIKit)` — a shared file that imports UIKit or references `UIApplication`/`UIScreen` won't compile for macOS, and the compiler error points at the wrong line.

## Rule 2 — Shell = NavigationSplitView, not the iOS per-tab stack

The Mac shell is a `NavigationSplitView`: a sidebar driven by a `Section` enum + **ONE `NavigationPath` feeding a single detail column** — not five independent per-tab stacks. **Why**: the Mac has one window with a persistent sidebar; tabs are an iOS idiom. Menu-bar `.commands` and keyboard shortcuts are first-class, not afterthoughts — a Mac user reaches for ⌘F / ⌘, / arrow keys before the mouse. Multi-scene composition: `WindowGroup` (main) + optional `DocumentGroup` + a `Settings` scene. **⌘N gotcha**: adding a `DocumentGroup` silently installs a File ▸ New that creates a blank document; if the app's ⌘N should do something else (or nothing), override with `CommandGroup(replacing: .newItem) { … }`.

## Rule 3 — Drop to AppKit only where SwiftUI stutters

SwiftUI is the default; reach for AppKit (`NSViewRepresentable`) at exactly three seams:
- **Magnifiable / hit-tested canvases** (a zoomable timeline, a pannable board) → `NSView` + `CALayer` inside an `NSScrollView`. SwiftUI's gesture + scroll composition can't do programmatic-follow-while-pinching.
- **Large reusable grids** (thousands of cells) → `NSCollectionView` instead of `LazyVGrid`, for real cell recycling.
- **Modeless keyboard** (shortcuts that fire without a focused control) → an `NSEvent` local monitor.

Everywhere else, native SwiftUI wins (`native-platform-first`).

## Rule 4 — Player REPLACES the window root while playing

When playback starts, swap the player IN as the window's root view — do NOT present it as an `.overlay` / `.fullScreenCover` over the split view. **Why**: an overlaid player lets the split view's toolbar, sidebar-toggle, and the previously-shown title BLEED THROUGH at the edges. Making the player the root guarantees a clean surface. Use the native `AVPlayerView` with the `.floating` controls HUD and `AVPlaybackSpeed.systemDefaultSpeeds` — never hand-draw a transport (`native-platform-first`).

## Rule 5 — macOS AVPlayerItem has NO externalMetadata

There is no `externalMetadata` on `AVPlayerItem` on macOS (verified against the current SDK). Show the title via the **window title bar** (e.g. `"Title (Year)"`). **NEVER** try to inject title/metadata by wrapping the asset in an `AVMutableComposition` with a metadata track — on a resilient custom-scheme streaming asset (see `resilient-media-streaming`) the composition override **blanks the video** to black while audio plays. This was tried and reverted twice; do not retry it.

## Rule 6 — Hero = full-width 16:9, no maxHeight cap; and the fill-image layout trap

The Home hero is `.aspectRatio(16/9, contentMode: .fit)` spanning the full content width with **NO `maxHeight` cap**. **Why**: a fixed height crops the art as the window widens; a `maxHeight` cap insets and centers it so it "doesn't extend across." Let width drive height via the aspect ratio.

**The fill-image layout trap** (bites hero AND poster tiles): a `scaledToFill` image inside a `frame(maxWidth: .infinity)` reports its oversized COVER dimensions, and the flexible frame ADOPTS them, blowing the layout out — intermittently, depending on which artwork loads. Fix: a **sized shape/rectangle owns the layout**, and the image fills it via `.background` / `.overlay` + `.clipped()` (which cannot influence layout).

## Rule 7 — Route all remote images through an ImagePipeline (and decode odd color spaces to sRGB)

Never use bare `AsyncImage(url:)` for grids/heroes. **Why**: it re-decodes on every identity change and opens unbounded connections, which gets you throttled by archive/CDN hosts and hitches on scroll. Route through one `ImagePipeline`: a decoded-image `NSCache`, a single shared `URLSession` with `httpMaximumConnectionsPerHost = 6`, and in-flight request coalescing (same URL requested twice → one fetch).

**Grayscale/CMYK white-box bug**: `Image(nsImage:)` on the Metal render path draws a **solid white box** for any image that isn't 8-bit RGB (grayscale JPEGs, CMYK, 16-bit). Decode-and-redraw each loaded image into an 8-bit sRGB bitmap context ONCE in the pipeline before caching.

## Rule 8 — Structured concurrency for timers, never Combine Timer.publish

Hero rotation, search debounce, any periodic UI work → `.task(id:)` / `Task.sleep`, torn down automatically when the view disappears. **Why**: a `Timer.publish` (or a bare `Timer`) can fire into an already-deallocated view/executor → an executor fault / crash. The structured-concurrency task is cancelled with the view.

## Rule 9 — Companion-app deep links via NSWorkspace

To open another app by its URL scheme, use `NSWorkspace`: `NSWorkspace.shared.urlForApplication(toOpen: url)` is the install probe (the AppKit analog of iOS `UIApplication.canOpenURL`), and `NSWorkspace.shared.open(url)` routes the link. **Why differs from iOS**: macOS needs **no `LSApplicationQueriesSchemes`** Info.plist entry — that array is an iOS privacy restriction that doesn't exist on the Mac. If the target isn't installed, fall back to opening its App Store page.

## Rule 10 — Mac App Store: sandbox, hardened runtime, privacy manifest, and the microphone TCC gotcha

Ship with **App Sandbox** enabled with the narrowest scopes the app truly needs (`network.client` for streaming, `files.user-selected.read-write` for a document app, `security-scoped-bookmarks` to keep access across launches), the **hardened runtime**, a full app-icon set, and a `PrivacyInfo.xcprivacy`. **Microphone TCC gotcha**: capturing audio needs BOTH the `com.apple.security.device.microphone` (or `device.audio-input`) sandbox entitlement AND an `NSMicrophoneUsageDescription` string — miss either and the capture is **silently denied** with no prompt. See `cloud-appstore-submission` for building/signing/uploading the Mac build (a beta dev-OS Mac can't ship a release build locally).

## Rule 11 — A heavy Mac-exclusive feature: Library ≠ Project, cache-then-export, no-auto-edit gate

If the Mac earns a feature the touch/TV/web platforms can't host (a document editor, a pro/authoring tool — it needs a filesystem, subprocess tools, long-running compute, and a pointer+menu+multi-window editor), fix these load-bearing frames up front:

- **Library ≠ Project.** The app-global library (the user's saved building blocks) is SwiftData + iCloud and holds **references only, never bytes**. A project is a `.package`-style reference document that also holds only references. Neither embeds media.
- **Cache-then-export, never stream-remote-into-export.** Pre-fetch each needed remote byte range to a local faststart file first; an exporter fed a remote URL fails. (Uses the same resilient loader — `resilient-media-streaming`.)
- **No-auto-edit learning gate.** Any "automatic" assist must yield an EDITABLE result the user shapes, never a one-tap finished artifact — automate the mechanical, preserve the meaningful (`learning-orientation-design`).

Cross-link a project `macos-native-app-shell` skill if one exists.

## Rule 12: Every command is in the menu bar

HIG: *"Even when commands are available elsewhere in your app, it's important to list them in the menu bar."* AW's Mac app shipped with three custom menu items; sidebar sections, Search, Back and every Detail action had no item and no key. Build it through `.commands`:

- **Order**: App, File, Edit, View, then the app's own menus general to specific (Go, the item's menu, player Controls, editor menus), then Window, Help.
- **Go** carries the sidebar sections (⌘1…⌘9), Search ⌘F (focuses the field), Back ⌘[.
- **No menu item takes a bare key** (a letter or arrow in the menu bar steals it from text fields); a canvas keeps its own bare keys while it has focus.
- **One key, one live meaning**: a command that belongs to a kind of window is enabled only while that window is key, via `focusedSceneValue`. **Disable, never hide**: menus keep their shape in every window.
- Help ▸ App Help ⌘? points somewhere real (a support page), never the system placeholder.
- Verify by reading the menu bar back through Accessibility and pressing items there, not by pointer clicks.

## Rule 13: A button says what it does at every window width

No truncation ("Add to Pl…"), no wrapping (a flow layout reflows seven buttons into ragged rows), no icon-only fallback (an icon with a tooltip is an abbreviation with extra steps). A row of actions keeps a SMALL FIXED SET of primaries and folds the rest into one native **More** menu whose items keep their full names. Choose the arrangement with `ViewThatFits(in: .horizontal)` over arrangements each DESIGNED, and put `.fixedSize()` on every control AND the row: without it the first arrangement always "fits" by squeezing and `ViewThatFits` never chooses. Declare each action ONCE (an enum rendered as a control or as a menu item); two parallel lists drift. The rule reaches past buttons: names under portraits get two lines with `reservesSpace: true`, never an ellipsis. (AW Decision 134.)

## Rule 14: Direct manipulation over sliders; the two AppKit event facts

When a control describes something already on screen, put the control ON the thing: drag inside to move, a corner to resize, an edge to reshape, scroll to zoom, ⌥-drag to pan (OBS's canvas pattern). Sliders in another column are a second description of a picture the person is already looking at. Keep a readout and a Reset beside it for precision. Publish the geometry the renderer actually uses rather than re-deriving it in the view. (AW Decision 135.)

- **`.offset` is a RENDER transform.** The `NSView` behind an offset SwiftUI view stays where it was laid out, so a representable backing an offset view reports the wrong frame. Move with layout (`.position`, frames), not `.offset`, when AppKit must hit-test it.
- **`scrollWheel` needs a local `NSEvent` monitor.** AppKit sends it to `hitTest`'s view and up THAT responder chain; a representable in `.background` is a sibling of the hosting view and never on it (`.overlay` just trades it for a dead drag). A local monitor sees the event first and can check whether the pointer is over the target.

## Rule 15: Closing a window ends what it was doing; a view being rebuilt is not a window being closed

On macOS the red button is a close, not a quit. A player surface that goes away pauses, drops its item, releases its player, and tells every singleton holding it to let go; otherwise sound plays with no transport left to stop it and the next open starts a second copy. But SwiftUI also tears views down for reasons that have nothing to do with the window. Before releasing a resource a surface owns, ask whether something longer-lived is using it (an engine, a broadcast, a shared session). When the view's lifetime and the longer one disagree, the longer one wins and whatever ends it cleans up. AW's version of the bug: an unconditional teardown on rebuild blacked out a live broadcast in 2 of 8 runs while every log line read healthy, so guard it with a source-invariant test, not a run. (AW macOS-DESIGN §D12, §D12a.)

## See also

- `native-platform-first` — exhaust AppKit/SwiftUI primitives before any custom control
- `resilient-media-streaming` — the shared streaming loader the Mac player and any export reuse
- `per-ecosystem-sync-islands` — the CloudKit island the Mac joins for free
- `cloud-appstore-submission` — building/signing/uploading the Mac App Store build
