# [APP NAME]: TV Platform Implementation Backlog

> **Template.** Copy to `docs/TV-PLATFORM-BACKLOG.md` (you create this) when
> the app commits to TV platforms beyond Apple TV. Replace every `[FILL IN]`
> and mark items done as they land. The phases, the owner/engineering split,
> and the notes under each item are what shipping Archive Watch to Cast,
> AirPlay, Android TV, Fire TV, webOS and Tizen actually cost. Keep the notes.
> They are the traps.

**Status:** [FILL IN]. Strategy: `DECISIONS.md` 028. UI rules:
`docs/TV-DESIGN.md` (you create this from
`docs/templates/TV-DESIGN-template.md`). Platform viability, fees and the store
process: `docs/TV-PLATFORMS.md`, `docs/store/webos-submission.md`,
`docs/store/tizen-submission.md`.

Every item has an ID, an owner (**ENG** = implementable by the agent,
**OWNER** = only a person can do it), a size, dependencies, acceptance criteria,
and the skill to invoke. **Owner-blocked items are also collected in §OWNER at
the bottom.** That section is the answer to "what do I have to do to publish
this?" (See `docs/templates/OWNER-PLAYBOOK-template.md` for the general split.)

Sizes: **S** half a day or less, **M** 1 to 3 days, **L** 1 to 2 weeks, **XL**
more than a month.

---

## The shape of the work

Two builds reach five of the seven native targets, and two zero-app routes cover
the closed platforms:

```
android/ (Kotlin + Compose + Media3, zero GMS)
    +-- TV form factor --+-- Google TV / Android TV   (Play, $0 more)
                         +-- Fire TV                  (Amazon, $0)

/ (vanilla web app, no build step)
    +-- TV focus layer --+-- LG webOS      (Seller Lounge, $0, global)
                         +-- Samsung Tizen (Seller Office, $0, US-only tier)
                         +-- VIDAA / Titan / Zeasn  (partnership-gated)

Cast receiver (HTML) ---- Chromecast, Google TV, Chromecast built-in (about Vizio)
AVPlayer (already ships)  AirPlay 2 TVs (Samsung, LG, Vizio, Sony, TCL, Roku TV)

Roku -------------------- full BrightScript/SceneGraph rewrite. Separate decision.
```

**Sequencing rationale.** Phase 1 (Cast + AirPlay) is days of work and is the
*only* realistic Vizio reach. Phase 2 (Android TV, then Fire TV) is the biggest
device reach for close to 100% engine reuse. Phase 3 (web-TV) reuses the web app
and needs no new runtime. Roku is last because it is the only target with 0%
code reuse.

---

## Phase 0. Foundation (do first; unblocks everything)

| ID | Item | Who | Size | Status |
|---|---|---|---|---|
| **F1** | Read `docs/TV-PLATFORMS.md`; record the platform set in `DECISIONS.md` (amend 028 if the app diverges) | ENG | S | |
| **F2** | `docs/TV-DESIGN.md` binding doc (you create this) | ENG | M | |
| **F3** | This backlog | ENG | S | |
| **F4** | Add **Android TV** + **Web-TV** coverage to `PARITY.md` | ENG | S | |
| **F5** | Read the `androidtv-compose-focus` and `smarttv-web-app` skills | ENG | S | |

**F4 note:** if the parity tables are already six columns wide, add TV coverage
as a dedicated `PARITY.md` section (client table, verb table, a compliance-gate
line) rather than two more columns. Every non-done cell still carries a reason
(`cross-platform-parity-discipline`).

---

## Phase 1. Zero-app reach: Cast + AirPlay

*Highest return in the whole backlog. No store, no review, no certification.*

| ID | Item | Who | Size | Deps |
|---|---|---|---|---|
| **C1** | Register in the Google Cast SDK Developer Console; pay the one-time **$5**; create a Custom Receiver app ID pointing at `https://[FILL IN: domain]/cast/` | **OWNER** | S | Leave the Android TV package field BLANK. Filling it makes Cast launch the native TV app, which implements a sender, not a receiver |
| **C2** | Build the **Custom Web Receiver** (CAF v3) page, hosted at `/cast/` | ENG | M | C1 |
| **C3** | Cast **sender** in the web app (Cast SDK for Web) | ENG | M | C2 |
| **C4** | Cast **sender** in the Android phone app, **excluded from the Fire variant** | ENG | M | C2, A7 |
| **C5** | **Publish the receiver** in the Cast console | **OWNER** | S | Publishing is BLOCKED until at least one sender is declared (the web origin and the Android package). An Unlisted listing is fine. Propagation can take about 24h. Once published, no test-device registration is needed |
| **A0** | Confirm the **AirPlay** route in the iOS player works | ENG | S | Not "no new code" if playback uses a custom resource loader (see below) |

**C2 notes.** The receiver is HTML/JS and reuses the web player, including
caption conversion and the resilient reconnect. It is hosted static, so it fits
GitHub Pages. Receiver v2 is deprecated; build **CAF v3**.

**C4 notes.** Cast is **GMS-dependent**. It must be compiled out of the Fire TV
variant or the Fire build breaks (TV-DESIGN §6.6). Keep the Cast code in the
Google flavor only, and do not reference Cast-only types from shared code (poll
the session state if you must), or the structural split undoes itself. Do not
offer Cast on a TV: a television is a receiver, not a sender.

**A0 notes (learned in Archive Watch).** "`AVPlayer` already exposes AirPlay"
is **wrong for a player backed by a custom-scheme
`AVAssetResourceLoaderDelegate`** (the `resilient-media-streaming` pattern).
Apple does not support video AirPlay with a custom loader: the delegate that
serves the bytes lives on the *sending* device, so the receiver has nothing it
can fetch. AirPlay fails on every title, and nothing in the build or a
screenshot shows it.

The fix: observe `AVPlayer.isExternalPlaybackActive` and, when a route engages,
swap to a URL the **receiver** can pull itself (published HLS first, which keeps
the WebVTT caption renditions, then plain MP4). When the route disengages,
rebuild the resilient on-device item, preserving position and metadata. Detach
the stall/fallback machinery while external. Losing loader resilience on AirPlay
costs nothing, because the receiver owns the connection either way.

**Owner QA that cannot be verified from the agent:** AirPlay routes do not exist
in the Simulator. On a real iPhone and Apple TV: start playback, pick the AirPlay
route, confirm video appears on the TV (not a black screen), then disengage and
confirm playback resumes on-device at the same position.

AirPlay reach is Apple TV plus AirPlay 2 TVs from Samsung, LG, Vizio, Sony, TCL,
Hisense, Roku TV and Philips, but only in Apple households. It is reach, not
discovery.

**Phase 1 acceptance:** [FILL IN: content] plays on a Chromecast built-in TV from
both the web app and the Android phone app, with captions selectable and resume
written back; AirPlay route confirmed on a real iPhone.

---

## Phase 2. Android TV, then Fire TV

*Close to 100% engine reuse. The work is a 10-foot UI, not a port.*

### 2a. Platform compliance

| ID | Item | Who | Size | Acceptance |
|---|---|---|---|---|
| **A1** | `LEANBACK_LAUNCHER` intent filter (TV-ML) | ENG | S | App appears in the Android TV launcher |
| **A2** | `touchscreen` + TV-absent hardware `required="false"` (TV-MT) | ENG | S | Play accepts the AAB for the TV form factor |
| **A3** | **320x180 in-APK banner containing the app name** + 160x160 or larger xhdpi icon (TV-LB/TV-BN) | ENG | S | Banner renders in the launcher; name legible |
| **A4** | Landscape, no letterboxing, 5% overscan insets (TV-LO/TV-OV) | ENG | S | Nothing clipped on a real panel |
| **A5** | **TV-G6 audit: 64-bit + 16 KB page size** across every bundled native library (`tools/audit_tv_g6.py`) | ENG | M | Every bundled `.so` is 16 KB-aligned |
| **A6** | Confirm TV-PS (`minSdk` 31 or lower; **28 or lower if Fire TV is in scope**) and TV-G1 (AAB) | ENG | S | Assert both in CI |

**A5 is the sleeper risk.** It is not automatically satisfied and it blocks the
TV form factor. Do it early. The fix may be a dependency bump, which has lead
time.

### 2b. The 10-foot UI (the real work)

| ID | Item | Who | Size | Deps |
|---|---|---|---|---|
| **A7** | Add `androidx.tv:tv-material`; runtime TV branch via `UiModeManager` (TV-DESIGN §6.5) | ENG | S | |
| **A8** | Focus primitives: focusable card with scale + ring + lift, initial-focus claim, row/grid containers on standard `LazyRow`/`LazyColumn` | ENG | M | A7 |
| **A9** | TV **Home**: hero + editorial rows + browse rows | ENG | M | A8 |
| **A10** | TV **Browse** grids with facets | ENG | M | A8 |
| **A11** | TV **Detail**: hero, metadata, primary actions, related items | ENG | M | A8 |
| **A12** | TV **Search**: D-pad-operable, with the no-typing browse escape (TV-DESIGN §3.6) | ENG | M | A8 |
| **A13** | TV **Library** + **Settings** | ENG | S | A8 |
| **A14** | TV **Player**: Media3 `PlayerView` TV controls, D-pad center/left/right (TV-PC), `KEYCODE_MEDIA_PLAY_PAUSE` (TV-PP), title + description overlay (Decision 022) | ENG | M | A8 |
| **A15** | **Gate `media3-session` MediaSession OFF on TV; pause video on switch-away (TV-NP)** | ENG | S | A14 |
| **A16** | Back returns to launcher from root, never mid-playback (TV-DB) | ENG | S | A8 |
| **A17** | Subtitles via Media3 `SubtitleConfiguration` | ENG | S | Verify rendering on the TV emulator |
| **A18** | v1.1 surfaces (TV-DESIGN §2) | ENG | L | A9 |

**A15 is a shipped-code conflict, not a new feature.** A MediaSession added for
phone lock-screen controls violates TV-NP for a video app. Gate it by device
type.

**Skill:** `androidtv-compose-focus` plus `android-production-gotchas` for the
data-layer and `produceState` discipline, which is unchanged on TV.

### 2c. Ship

| ID | Item | Who | Size | Notes |
|---|---|---|---|---|
| **A19** | Emulator verification (Android TV emulator image) on every surface, by remote (`tools/verify_tv_focus.sh`) | ENG | M | If the emulator refuses to boot, read its log for `Available Memory ... Required` before blaming disk. On an 8 GB Mac it is RAM. Boot headless with `-no-window -gpu swiftshader_indirect -memory 2048` |
| **A20** | **Buy an Android TV / Google TV device** for real-remote QA | **OWNER** | S | |
| **A21** | Play Console: *Setup, Advanced settings, Form factors, Add Android TV*; accept the TV policy | **OWNER** | S | |
| **A22** | TV screenshots (1 to 8, 1920x1080) + the **1280x720 store TV banner** + a TV section in the description | ENG (via API) / **OWNER** if the console refuses | S | Generate with `tools/tv_screenshots.sh`; banners with `tools/make_tv_banner.py` |
| **A23** | Submit; pass the **separate Android TV app-quality review** | ENG (`play-cli-submission`) | S | |

**The two "TV banners" are different assets.** Play's STORE `tvBanner` field is
**1280x720**; uploading the 320x180 returns `Invalid dimensions - expected
width: [1280], expected height: [720]`. The 320x180 is the in-APK
`android:banner` the launcher draws (TV-BN). Render both from one master so they
never drift apart.

### 2d. Fire TV

| ID | Item | Who | Size | Notes |
|---|---|---|---|---|
| **A24** | Fire variant: **exclude Cast and any GMS**; assert zero-GMS in CI (`tools/audit_fire_tv_gms.py`, `tools/audit_fire_tv_manifest.py`) | ENG | S | Keep the dependency set GMS-free |
| **A25** | Validate Media3 playback on **real Fire hardware** | ENG + OWNER | M | Do **not** adopt the stale `amzn` ExoPlayer port |
| **A26** | **Buy a Fire TV Stick (about $30)** | **OWNER** | S | Amazon expects physical-device QA |
| **A27** | **Create a free Amazon Developer account** | **OWNER** | S | $0 registration, $0 submission |
| **A28** | Submit to the Amazon Appstore (APK + assets + Fire TV form factors) | **OWNER** | S | Reuse the 1920x1080 screenshots. Review is about 3 to 5 business days. Amazon does not gate submission on owning the device |

**Phase 2 acceptance:** the same AAB installs and is fully D-pad-operable on an
Android TV device and a Fire TV Stick; both pass the TV-DESIGN §9
remote/ten-foot/parity tests; the phone build is unaffected in behavior.

---

## Phase 3. Web-TV: LG webOS, then Samsung Tizen

*Reuses the web app. The work is an input layer, not a rewrite.*

### 3a. Shared TV layer

| ID | Item | Who | Size | Notes |
|---|---|---|---|---|
| **W1** | Vanilla **spatial-navigation focus engine** (about 200 lines): registry, nearest-in-direction resolver, roving `tabindex`, `scrollIntoView`, single `keydown` | ENG | M | Norigin and the rest are React-only, so they are out (TV-DESIGN §7.1) |
| **W2** | Register/unregister focusables when a view shows | ENG | S | |
| **W3** | TV CSS breakpoint: 1920x1080, 5% overscan insets, 24px body floor, dark-first | ENG | M | Additive to the mobile-first CSS |
| **W4** | Player key contract: center = play/pause, left/right = seek, media keys; overlay syncs with controls | ENG | M | |
| **W5** | Subtitles to `<track>` | ENG | S | A cross-origin `<track>` fails **silently** (readyState 3, zero cues), and `crossorigin` on `<video>` breaks playback when the video host sends no CORS header. Fetch the VTT into a same-origin `blob:` instead (TV-DESIGN §5.5) |
| **W6** | Lifecycle: pause on suspend/blur; resume state | ENG | S | |
| **W7** | Bump the service-worker shell version | ENG | S | Or TVs serve a stale app for days |

Permanent browser assertions for the TV layer live in `tools/tv_browser_tests.js`
and `tools/test_tv_focus.mjs`.

### 3b. LG webOS *(first: a single person can publish globally)*

| ID | Item | Who | Size | Notes |
|---|---|---|---|---|
| **L1** | `appinfo.json`; `ares-package` to `.ipk` (`tv/build-tv-packages.sh webos`) | ENG | S | CLI: `npm i -g @webos-tools/cli`. Pass `-n/--no-minify` (undocumented): the bundled uglify-js cannot parse modern syntax and aborts the package. Stamp the version from `AppVersion.xcconfig` at build time |
| **L2** | webOS shim: Back = keyCode **461**; `webOSLaunch`/`webOSRelaunch` | ENG | S | |
| **L3** | **Magic Remote pointer coexistence** with D-pad focus | ENG | M | Not optional (TV-DESIGN §7.4). Assert: hover moves focus, the D-pad continues from the hovered element, inert chrome and hidden views never steal focus, no scroll jump |
| **L4** | **Create a free LG Seller Lounge account** (individual, 18+, global OK) | **OWNER** | S | |
| **L5** | **Create an LG Developer account + enable Developer Mode on an LG TV**; side-load the `.ipk` | **OWNER** | S | Requires an LG TV |
| **L6** | Store assets: **1280x720** screenshots, description, content rating | ENG assets / **OWNER** capture + upload | S | Capture from a REAL LG panel during L5, not a desktop browser (see below) |
| **L7** | UX scenario doc + the mandatory self-checklist | ENG drafts / **OWNER** submits | M | Draft in `docs/store/webos-submission.md` |
| **L8** | Submit; pretest + function test + content test | **OWNER** | S | About 5 to 10 business days, often 2 to 3 cycles |

**Why the LG screenshots come from the panel.** webOS and Tizen present a 1920
CSS-px viewport regardless of panel resolution, and the web-TV layout targets
it. Captured narrower, the top nav and rails clip. Forcing 1920 with a CSS
transform breaks lazy-load geometry (in Archive Watch, 70 of 363 posters failed
to resolve). Capture on the TV during side-load, or on a display at least 1920
wide. The same assumption is unverified on VIDAA, Titan OS and Zeasn.

### 3c. Samsung Tizen

| ID | Item | Who | Size | Notes |
|---|---|---|---|---|
| **S1** | `config.xml`; `tizen build-web` + `tizen package` to signed `.wgt` (`tv/build-tv-packages.sh tizen`) | ENG | S | **Keep the signing certificate. Every update must reuse it** |
| **S2** | Tizen shim: `tizen.tvinputdevice.registerKey()` for media keys; `tizenhwkey` Back; `visibilitychange` pause | ENG | S | |
| **S3** | **Create a free TV Seller Office account** | **OWNER** | S | |
| **S4** | **Decide: US-only Public Seller, or an offline contract with Samsung HQ for Partner (global)** | **OWNER** | | Business decision, framed in `docs/store/tizen-submission.md` |
| **S5** | Enable Developer Mode on a Samsung TV (keyed to the TV's IP); side-load | **OWNER** | S | Requires a Samsung TV |
| **S6** | Submit; Samsung manual QA against the Launch/Development checklists | **OWNER** | S | About 1 to 2 weeks; multi-cycle rejections are common |

### 3d. Aggregators (opportunistic)

| ID | Item | Who | Size | Notes |
|---|---|---|---|---|
| **G1** | Inquire with the **Titan OS** partner portal (Philips TVs; strong in Europe) | **OWNER** | S | Closest thing to self-serve HTML5 onboarding; cost not published |
| **G2** | Inquire with **VIDAA/Hisense** and **Zeasn/Foxxum** | **OWNER** | S | Same HTML5 build; no public indie door found |

**Phase 3 acceptance:** one shared web build runs fully D-pad-operable on an LG
TV and a Samsung TV, differing only in the shim files; the phone/desktop web app
is unaffected.

---

## Phase 4. Roku (separate funded decision)

**0% code reuse.** BrightScript + SceneGraph is a proprietary stack with no
Swift/Kotlin/JS runtime and no general WebView app model. Budget roughly 2 to 4
months for one experienced Roku developer, more when learning BrightScript cold.
Roku's no-code Direct Publisher was sunset in January 2024. Read the
`roku-brightscript-app` skill before scoping.

**The case for it:** Roku leads US connected-TV share. [FILL IN: why this app's
audience is there.] Fees are **$0**.

**Known blockers to price in before committing:**

- **R-a. Deep linking is mandatory** for public video apps, and feeds Roku
  Search. Real, non-trivial new work.
- **R-b. Performance thresholds:** home fully rendered **within 15s**, content
  playing **within 8s**. Redirect latency on the media host is the most likely
  certification friction point. **Measure on real Roku hardware before
  committing budget.**
- **R-c. Playback resilience regression.** Roku's `Video` node **owns
  networking**; there is no `AVAssetResourceLoaderDelegate` equivalent, so
  byte-range resume and node failover (`resilient-media-streaming`) **cannot be
  reproduced**. Prefer HLS/DASH derivatives where available. Accept the trade
  in writing before starting.
- **R-d. Certification drifts.** Roku ships periodic certification updates.
  Read the live checklist at submission time.

**Recommendation:** do not start Roku until Phases 1 to 3 ship and R-b has been
measured on hardware. Then log it as its own decision with a budget.

---

## Not pursued (with reasons)

| Platform | Why not |
|---|---|
| **Vizio SmartCast** | No public self-serve program or open SDK; onboarding is gated through Vizio-designated partners. **Reach it through Cast + AirPlay instead.** |
| **Comcast/Sky (RDK/Firebolt)** | Public SDK, but distribution is partner- and certification-gated. Build-possible, ship-unlikely for a solo app. |
| **TiVo OS (Xperi)** | HTML5, but no public self-serve indie program. |

---

## §OWNER. Everything only a person can do

Nothing here waits on code. Each item needs an account, a physical device,
money, or a business decision. Order them cheapest-first:

1. **Amazon Fire TV** (free, no hardware needed to submit): A27, A28.
2. **Google Play TV form factor**: A21, then confirm the TV panel shows no
   remaining requirement and the TV quality review is queued. Check the track
   history through the API to confirm a submission actually landed.
3. **LG webOS** (one person can publish globally, so before Samsung): L4, L5, L6,
   L8.
4. **Samsung Tizen** (decision first): S4, S3, S5, S6. Create the Tizen Studio
   signing certificate once and **keep it**.
5. **Device QA no emulator can prove:** an Android TV device (A20), a Fire TV
   Stick (A26), any Cast device once C5 is published, and **AirPlay on a real
   iPhone + Apple TV** (A0).

**Standing decisions:** fund Roku (Phase 4)? Open aggregator conversations (G1,
G2)?

**Standing content obligation:** [FILL IN: any rights, licensing or content
exclusions the catalog must keep enforcing]. A reviewer spot-checking a
problematic title on the home screen is a rejection and takedown risk on every
one of these stores. Keep the enforcement in the data pipeline, not in a
report nobody reads.

### Artifacts staged for the owner

Fill this table in as each build lands, so the owner never has to ask where a
file is.

| Artifact | Path | Rebuild with |
|---|---|---|
| Fire TV APK (signed, zero-GMS, TV-G6) | [FILL IN] | `cd android && ./gradlew assemble[FILL IN: Amazon flavor]Release` |
| LG webOS package | [FILL IN] | `bash tv/build-tv-packages.sh webos` |
| Samsung Tizen payload (unsigned; needs the owner's cert) | [FILL IN] | `bash tv/build-tv-packages.sh tizen` |
| 1920x1080 store screenshots | [FILL IN] | `bash tools/tv_screenshots.sh` (emulator booted) |
| Store TV banner 1280x720 + in-APK banner 320x180 | [FILL IN] | `python3 tools/make_tv_banner.py` |

---

## Skill map

| Work | Skill to invoke |
|---|---|
| Any TV surface | `docs/TV-DESIGN.md` first, then the below |
| Android TV focus/UI | `androidtv-compose-focus` + `android-production-gotchas` |
| Web-TV focus/packaging | `smarttv-web-app` + `web-platform-patterns` |
| Any custom component | `native-platform-first` |
| Layout/type/density | `mobile-first-density-design` |
| Loading/empty/error/offline on every new row + grid | `universal-feature-states` |
| Playback resilience per platform | `resilient-media-streaming` |
| Data layer for a new client | `shared-data-plane-contract` + `docs/DATA-CONTRACT.md` (you create this from `docs/templates/DATA-CONTRACT-template.md`) |
| Parity bookkeeping | `cross-platform-parity-discipline` |
| Before implementing any feature | `learning-orientation-design` |
| New view/row/overlay proposals | `binding-design-doc-discipline` |
| Play submission | `play-cli-submission` + `store-submission-playbook` |
| Roku | `roku-brightscript-app` |
| Logging a decision | `architectural-decision-log` |
