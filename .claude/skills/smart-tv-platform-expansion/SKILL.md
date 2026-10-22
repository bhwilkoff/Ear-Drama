---
name: smart-tv-platform-expansion
description: Take an existing app to the living room — Android TV / Google TV / Fire TV, Samsung Tizen, LG webOS, VIDAA, Roku, and the Cast/AirPlay routes. Covers the four-runtime-families map (two builds reach five stores), the ten-foot focus contract, the platform compliance gates that actually bite (TV-ML/MT/LB/BN/PS/G6/G1, TV-NP), the vanilla spatial-navigation engine for web-TV, per-platform key/lifecycle/packaging shims, store economics and the owner-gated steps, the verification recipes (low-RAM headless TV emulator, no-cache dev server, in-browser acceptance suite), and capability tiers for one listing spanning a decade of hardware (named capabilities, gate the affordance, never a silently missing button). Triggers on Android TV, Google TV, Fire TV, leanback, Tizen, webOS, VIDAA, Roku, BrightScript, SceneGraph, Chromecast, Cast receiver, AirPlay, smart TV, 10-foot UI, D-pad, remote control, TV app store, legacy tier, old Roku, capability tier.
---

# Smart-TV platform expansion

Taking an app to TV. Written from shipping a real catalog app to Android TV and
the web-TV family; every rule here cost something to learn.

## 1. There are four runtimes, not seven platforms

Brand names hide the fact that most "platforms" share a runtime. Map yours
before writing anything:

| Platform | Runtime | Reuse vehicle | Fees |
|---|---|---|---|
| Google TV / Android TV | Android TV OS | your **Android app**, TV form factor | $0 extra |
| Amazon Fire TV | Fire OS (Android fork, **no GMS**) | the **same** Android build | $0 |
| Samsung Tizen | HTML5 | your **web app** + a TV layer | $0 |
| LG webOS | HTML5 | the **same** web build | $0 |
| VIDAA / Titan OS / Zeasn | HTML5 | the **same** web build | partnership-gated |
| Roku | BrightScript + SceneGraph | **none — full rewrite** | $0 |
| Vizio | closed | none (no self-serve program) | n/a |

**Two builds reach five stores.** Cast (one-time $5) + AirPlay (free, already
works if you use AVPlayer) cover Chromecast-built-in and AirPlay-2 sets —
including Vizio, which has no other route.

**Sequence by reuse leverage:** Cast/AirPlay (days) → Android TV → Fire TV
(repackage) → webOS → Tizen → Roku last, if ever.

## 2. TV is a runtime branch, never a fork

The single most important structural rule. One `applicationId`, one bundle, one
entry point; the data layer, networking, player engine and routes are shared
**verbatim**. Only the view layer differs.

- **Android:** branch on `UiModeManager.currentModeType == UI_MODE_TYPE_TELEVISION`,
  with a fallback to the `android.software.leanback` / `android.hardware.type.television`
  feature flags — **Fire OS reports `UI_MODE_TYPE_NORMAL` on some devices**.
- **Web:** a `tv` class on `<html>` set by UA match, plus a `?tv=1` escape hatch
  so the TV surface is developable in a desktop browser.

Corollary: when a phone screen builds a non-trivial payload, **extract it and
share it**. Two copies drift. (Ours: the Home shelf assembly with cross-shelf
dedup.)

## 3. The focus contract (this is the whole job)

An unfocusable or ambiguously-focused element is not a cosmetic issue on a TV —
it is an unreachable feature, and it fails certification.

1. **Something is ALWAYS focused.** Claim it imperatively on view entry and
   **retry** — the target is usually inside a lazy list that has not composed on
   the frame the screen appears.
2. **Exactly ONE surface claims initial focus.** Two claims race; we shipped a
   race where the content claim scrolled the hero off-screen while the nav rail
   won the ring. Initial focus belongs to the **content**.
3. **Prefer content over chrome.** Focus landing on the logo is "something is
   focused" and still useless — the first Right/Down then goes somewhere
   unrelated to what the viewer is looking at.
4. **Mark focus with at least TWO of scale / ring / elevation — never colour
   alone.** Colour alone fails colour-blind viewers and washes out on a bright
   panel.
5. **Accept every select keycode:** `DPAD_CENTER`, `ENTER`, **and**
   `NUMPAD_ENTER`. OEM remotes disagree.
6. **Keep the focused element on screen**, ideally leaving one tile of context
   rather than snapping flush to the edge.
7. **No dead ends.** From anywhere there is a way back. Stopping at a row edge
   is fine; stranding is not.
8. **Text entry is the last resort.** Every browse path must be complete without
   a keyboard.

### The reachability bug you will hit

Focus search does **not** cross from a lazy row's first item into a sibling
container, so your nav rail becomes unreachable and tabs cannot be changed at
all. On Compose, `focusProperties { exit = … }` is **not delivered through a
lazy list** either (tried, observed failing). Fix deterministically: put the
rail's `FocusRequester` in a CompositionLocal and have the leftmost item handle
Left explicitly — **before** the focusable modifier, so the focused element sees
the key first.

## 4. Layout and type

- **1920×1080 baseline**, **5% overscan inset** (96×54 at 1080p). Nothing
  meaningful — text, controls, *resting focus rings* — crosses that line.
  Artwork may, and must be designed to be cropped.
- **24px minimum body** at 1080p; row headers ~32; hero 48–64.
- **Dark-first.** Living rooms are dark.
- **Rows at the root**, grids only inside a chosen scope.

### ⚠️ The rem trap (web)

Do **not** set `font-size` on `html`. `rem` resolves against the root, so a root
override silently rescales every rem dimension in the app (1.5× at 24px) —
overflowing nav bars and blowing out heroes. Set ten-foot type **per element**;
`body` alone is safe.

## 5. Playback

- **Never build a custom transport** over a platform player. Use the platform
  controls; add a title/description overlay that syncs with them.
- **Key contract:** centre = play/pause toggle, left/right = seek, plus the
  dedicated media keys. Attach the handler to the player **surface**, not just
  the controller, so keys work while the transport is hidden — which is when
  viewers press them.
- **⚠️ Android TV-NP:** a *video* app must **not** surface background /
  Now-Playing media controls and **must pause on switch-away**. If your phone
  build has a `MediaSession` for lock-screen controls, **gate it off on TV** —
  it is a quality-review failure otherwise. Gate PiP-on-leave off too.
- **Back is layered, and the layers matter.** An open overlay is the top layer.
  We shipped a bug where Back ran `history.back()` while the player `<dialog>`
  stayed open and playing — a film over the home page with no way out. Both LG
  and Samsung explicitly test Back behaviour. Close the overlay and stop
  playback **first**, then navigate, then exit at the root.
- Progressive H.264 MP4 over HTTPS plays natively on every one of these
  platforms. No DRM, no transcode.
- Side-load subtitles (`SubtitleConfiguration` on Media3, `<track>` on web —
  convert SRT→VTT client-side). If captions exist they must be selectable.
- **Tizen's player has its own failure modes** (Archive Watch, Samsung
  certification, 2026-10-03):
  - Changing `playbackRate` breaks it (readyState 0, nothing plays). Offer no
    Speed control on Tizen.
  - The end of a file can arrive as `PIPELINE_ERROR_NETWORK` with no `ended`
    event. Treat an error within a few seconds of the duration as the end.
  - `waiting` fires spuriously: give it a grace period before any recovery (10 s
    near a seek), plus a ~12 s watchdog for an element that fires nothing at all.
  - Its subtitle renderer draws huge text in a narrow box and cannot be sized.
    Keep the track `hidden` and draw the active cues yourself at ten-foot size.
  - Pause on going to the background, and resume what YOU paused on return
    (CO-MT-01); turn the screensaver off during playback with
    `webapis.appcommon.setScreenSaver`, and back on at pause and end.
- **The 2022 Samsung floor is Chromium 85.** Fill the gaps in one compat file
  loaded first and gate the CSS in the package build (`js/compat.js`,
  `tools/test_tv_compat.py`, `docs/store/tizen-submission.md` §2b).

### ⚠️ Two silent subtitle/second-screen traps

**A cross-origin `<track>` fails silently.** No error, no console warning — the
element reports `mode: "showing"` while `readyState` is 3 (ERROR) with **zero
cues**. The usual fix, `crossorigin` on `<video>`, may be *unavailable*: if your
media host redirects to storage nodes that send no CORS header, adding it breaks
**playback**, which is far worse. Fetch the VTT yourself and hand `<track>` a
same-origin `blob:` URL instead; the video element stays untouched.

**But then a `blob:` URL cannot be cast.** It is scoped to the sender's
document, so a Cast receiver handed one can never fetch it — casting silently
loses subtitles. Keep **both**: the blob for the local element, the original
https URL (stash it in a data attribute) for the receiver. Neither failure is
visible on screen, so assert both in tests, and make the test **hunt for a
captioned title** rather than testing whatever the home screen focused — ours
silently never ran, because popular titles have no captions.

### ⚠️ AirPlay is incompatible with a custom resource loader (Apple)

If your iOS player streams through an `AVAssetResourceLoaderDelegate` on a
custom scheme — the standard trick for byte-range resume and host failover —
**video AirPlay does not work**. The delegate serving those bytes lives on the
*sending* device, so a receiver has nothing to fetch. Observe
`AVPlayer.isExternalPlaybackActive` and swap to a URL the **receiver** can pull
itself (prefer an HLS rendition — it also keeps caption tracks), then rebuild the
resilient item when the route disengages. You lose nothing: on AirPlay the
receiver owns the connection, so your resilience layer is inert there anyway.
AirPlay routes don't exist in the Simulator, so this needs device QA.

## 6. Android compliance gates that actually bite

| ID | Requirement | Trap |
|---|---|---|
| TV-ML | `LEANBACK_LAUNCHER` category | Without it the app is **invisible** in the launcher even when installed |
| TV-MT | `touchscreen` + every TV-absent feature `required="false"` | Any one implicitly-required excludes you from the TV form factor; `required="false"` is also what keeps ONE bundle shipping to phones |
| TV-LB/BN | 320×180 banner **containing the app name as text** | The name-as-text part is easy to miss |
| TV-PS | `minSdk` ≤ 31 | |
| TV-G6 | 64-bit **and 16 KB page sizes** (live 2026-08-01) | NOT automatic — depends how each bundled native lib was linked. **Measure it**; the fix is a dependency bump, which has lead time |
| TV-G1 | App Bundles mandatory | |
| TV-DB | Back returns to launcher from the root | Don't consume Back at the root |

Verify against the **merged** manifest, not your source one — merger rules can
drop or alter `uses-feature` entries.

**Compose for TV:** depend on `androidx.tv:tv-material` **only**. `tv-foundation`
and every `TvLazy*` composable were **removed** once their behaviour merged into
`compose-foundation` — use standard `LazyRow`/`LazyColumn`. Most tutorials online
are stale on this.

**Fire TV:** same build, no GMS. Anything GMS-dependent — **Cast above all** —
must be excluded from the Fire variant. Gate it in CI by scanning both declared
coordinates and the compiled DEX (a transitive pull names no coordinate). Use
Media3, not the stale `amzn` ExoPlayer port.

## 7. Web-TV: shims only

The differences between Tizen, webOS and VIDAA are **key codes, lifecycle events
and packaging — nothing else**. No view code may branch on platform.

| Concern | webOS | Tizen |
|---|---|---|
| Back | keyCode **461** | `tizenhwkey` event (+ **10009**) |
| Media keys | standard `keydown` | **must** `tizen.tvinputdevice.registerKey()` first |
| Lifecycle | `webOSLaunch` / `webOSRelaunch` | `visibilitychange` |
| Exit | `webOS.platformBack()` | `tizen.application.…exit()` |
| Pointer | Magic Remote cursor — **must coexist** with D-pad | none |
| Package | `.ipk` via `ares-package` | signed `.wgt` via `tizen package` |

Also accept **Escape (27)** and **Backspace (8)** as Back — aggregator remotes
use them. **Magic Remote coexistence is not optional:** hover moves focus, so
the D-pad continues from where the pointer left it. Two input models, one focus
state.

**Spatial navigation, vanilla:** every mature library (Norigin et al.) is
React-based. If your app isn't React, write ~200 lines: a registry of
focusables, a nearest-in-direction resolver over `getBoundingClientRect()`,
roving `tabindex`, `scrollIntoView` on move, one `keydown` listener.
Score = `distanceAlongAxis + misalignmentAcross * 3` — the weight is what makes
a grid feel like a grid. Compare **edges, not centres**, for the
"is it in this direction" test. Filter out anything inside a `[hidden]`
container or the D-pad walks into the previous screen.

**Packaging:** stage the SAME source files into each vendor layout from a build
script; never maintain a TV copy of the app. **Exclude the service worker** from
the package (a packaged app stores resources locally; a stale SW inside shadows
them) and skip its registration. **Keep the Tizen signing certificate** —
updates must reuse it.

### ⚠️ The packaged-origin trap (this one is silent and total)

A packaged `.ipk` / `.wgt` runs its document from **`file://`**, not `https://`.
Any URL you resolve *relative to the document* therefore points at a local path
that is not in the package. We shipped `new URL('.', location.href)` as the data
root; in the browser it is correct, and in the package **every** catalog fetch
would have 404'd — the app would have launched to an empty screen on every LG
and Samsung TV. Nothing catches this: it builds, and the browser build is fine.

Resolve remote data against a **canonical origin** whenever the protocol is not
`http(s)`:

```js
const PAGES_ROOT = /^https?:$/.test(location.protocol)
  ? new URL('.', location.href)
  : new URL('https://your-origin.example/');
```

Then check the rest of the `file://` consequences:

- **Every data host must send `Access-Control-Allow-Origin`** — the packaged app
  is now a cross-origin client (origin `null`). Verify each endpoint, don't
  assume; GitHub Pages does send `*`.
- **Guard `serviceWorker.register()` by protocol** too, or every launch produces
  a rejected promise for a file you deliberately excluded.
- Anything else keyed to origin — storage, cookies, absolute-path assets.

Chrome extensions cannot open `file://`, so you often cannot test this by
loading the package directly. Make the resolution a **pure function and unit-test
it against both origins**, and assert package integrity (staged files match
source, no packaged SW) in the same test.

## 8. Verification recipes

**Android TV emulator on a small Mac.** The default AVD wants 5 GB free and
simply hangs if it can't get it. Use
`system-images;android-<N>;android-tv;arm64-v8a`, set `hw.ramSize=2048` in the
AVD's `config.ini`, and launch:

```
emulator -avd <name> -no-window -no-metrics -no-audio -no-snapshot \
         -gpu swiftshader_indirect -memory 2048
```

`-no-window` still supports `adb exec-out screencap -p` and
`adb shell input keyevent`. **Read the emulator's own log before diagnosing** —
it prints which compatibility check failed; a "hangs before opening its console
ports" symptom looked like disk but was RAM.

Drive it like a remote:
`adb shell input keyevent KEYCODE_DPAD_DOWN|DPAD_LEFT|DPAD_CENTER`, and launch
the way a TV launcher does:
`adb shell am start -c android.intent.category.LEANBACK_LAUNCHER -a android.intent.action.MAIN -n <pkg>/<activity>`.

**Build a focus harness before hand-verifying surfaces.** Route directly to each
surface via intent extras (never count D-pad presses — Left lands on the nearest
item, not a fixed one), tag every focusable so focus emits an identity trace, and
script the assertions. Focus is invisible to screenshots, which mislead in both
directions; a trace is the only consistently trustworthy signal. Also: **"it
renders" is not "it works"** — verify where a navigation LANDS.

**Web-TV needs a real browser.** A Node DOM shim proves the focus *algorithm*
and is worth having (fast, no browser), but it does no layout, has no `<dialog>`
semantics and no media element — every CSS/geometry/overlay bug will slip past
it. Run an in-browser acceptance suite too.

Three caching traps will waste an hour each:
1. **Service workers are scoped by origin including PORT** — a leftover SW from
   a *different* local project on the same port hijacks your app. Unregister and
   clear caches, or use a fresh port.
2. `python3 -m http.server` sends **no cache headers**; Chrome holds stale JS/CSS
   across reloads. Serve with `Cache-Control: no-store` and withhold `sw.js`.
3. **A hash-only navigation does NOT re-fetch the document.** A hash-router app
   keeps running the OLD JS while you believe you're testing the fix. Change the
   **query string** between edits.

And: `fetch()` returning the fixed file proves the FILE is fresh, not that the
RUNNING script is. Check `performance.getEntriesByType('resource')` and compare
`encodedBodySize` against the file on disk.

## 9. Economics and the owner-gated steps

Reaching five new stores costs **$5** (Cast) plus test hardware. Play TV is a
form factor of an existing account; Amazon, LG and Samsung charge nothing to
register or submit.

What a human must do — surface these early, they have lead time:

- Cast: register + pay $5; register a physical Cast device for testing.
- Play: *Setup › Advanced settings › Form factors › Add Android TV*, accept the
  TV policy; there is a **separate TV app-quality review**.
- Amazon: free developer account; expects physical-device QA.
- LG: Seller Lounge account; a **UX scenario doc + a mandatory self-checklist**
  (thin submissions are auto-rejected); Developer Mode on a real LG TV.
- Samsung: Seller Office account. **The default Public Seller tier is US-ONLY** —
  global distribution requires a signed offline contract with Samsung HQ, i.e. a
  business entity. **So ship LG first**: individuals can publish globally there.
- Hardware: certification expects physical devices; emulators don't satisfy it.

## 10. Roku — decide, don't drift

**If you have decided to build it, the whole body of Roku knowledge is in
`roku-brightscript-app`** (the language traps, the SceneGraph focus/render
model, the from-scratch design system, the ECP harness and its silent
failures, deep-linking, and the cert limits). This section is only the
go/no-go.

0% code reuse (BrightScript + SceneGraph), ~2–4 months for one experienced dev
(a full catalog app is buildable in a focused multi-week loop with a device on
the network). Before committing budget, price two things:

- Its **performance thresholds** (home rendered within 15s, playback within 8s)
  against your origin's real latency — measure on hardware.
- Its `Video` node **owns networking**, so any custom streaming resilience you
  rely on (byte-range resume, node failover) **cannot be reproduced**. That is a
  genuine quality regression to accept in writing.

Deep linking is mandatory and feeds Roku Search. The no-code Direct Publisher
path was sunset in 2024.

### Capability tiers when one store spans a decade of hardware

Roku, Fire TV and Android TV ship one listing to boxes from 2014 and
2026. Tier by CAPABILITY, never by effort, and never let legacy set
the ceiling (Archive Watch Roku, owner 2026-09-11: "There is no reason
to do a bunch of work pushing the platform on for modern Roku users if
it is going to be hamstrung by the older devices").

- **One file decides the tier** (AW `roku/components/Capability.brs`):
  `AWTier()` returns modern/legacy from a hardware proxy, and call
  sites ask a NAMED capability, `AWCan("shareList")`, so the code reads
  as what it needs, not which devices it distrusts. Each named
  capability carries a comment: why it is off, what it cost, measured
  on which box.
- **Modern is built at full quality; legacy gets a working app, not
  the same app.** Legacy keeps browse, Detail, playback; it loses
  decoration and features that cost it frames.
- **Gate the affordance, keep the implementation whole.** The row is
  simply not offered on the legacy tier; the encoder behind it stays
  complete, because a correct implementation is not conditional on a
  product decision (AW Decision 122).
- **Gate on a hardware predicate, not form factor.** Ask
  `hasCamera && hasMicrophone` (`FEATURE_CAMERA_ANY`), never
  `isTelevision()`: a TV with a camera should pass and a cameraless
  tablet should fail (AW Decision 132).
- **Never a silently missing button.** A capability the device could
  have but currently lacks (sign-in not configured, permission not
  granted) is a state with a sentence on screen. A capability the
  hardware can NEVER have is omitted outright, and the reason lives in
  PARITY.md, not as a permanent apology on a Detail screen (AW
  Decisions 131, 132). See `universal-feature-states`.
- **What the tier cannot gate:** a language feature the oldest
  firmware cannot PARSE breaks the install everywhere (BrightScript
  has no conditional compilation). Hold it with a syntax test (AW
  `test_roku_legacy_syntax.py`); if legacy ever starts costing real
  capability, raise the firmware floor instead of spreading
  conditionals.

## See also

- `roku-brightscript-app` — everything about actually building the Roku channel
- `ten-foot-detail-design` — the Detail/Series/Search design shared across TV runtimes
- `cross-platform-parity-discipline` — track TV as clients in the parity matrix
- `multiplatform-expansion-method` (Step 3b): choosing floors by hardware reach and holding them in CI
- `native-platform-first` — exhaust platform primitives before custom widgets
- `resilient-media-streaming` — the streaming layer TV inherits
- `store-submission-playbook` — the cross-store submission checklist
