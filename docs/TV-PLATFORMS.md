# Smart-TV Platform Expansion: Viability and Process

**What this is.** The research behind `DECISIONS.md` 028 (smart TVs are two
builds plus two zero-app routes, never six apps). It was compiled in Archive
Watch in August 2026 from live vendor docs and re-verified against them, then
generalized here. Vendor rules drift, so re-read the live checklist for any
platform before you submit to it.

**Scope:** getting [APP NAME] onto the smart-TV and streaming-device app stores
beyond Apple: Roku, Samsung (Tizen), LG (webOS), Vizio (SmartCast), Google TV /
Android TV, Amazon Fire TV, plus the white-label OS aggregators and the
Cast/AirPlay routes.

**Companions.** The binding UI rules go in `docs/TV-DESIGN.md` and the ordered
work list in `docs/TV-PLATFORM-BACKLOG.md` (you create both, from
`docs/templates/TV-DESIGN-template.md` and
`docs/templates/TV-PLATFORM-BACKLOG-template.md`). Store steps live in
`docs/store/webos-submission.md` and `docs/store/tizen-submission.md`. The
skills are `smart-tv-platform-expansion`, `androidtv-compose-focus`,
`smarttv-web-app` and `roku-brightscript-app`. This doc extends the same
"feature parity, native per platform, one shared data plane" thesis
(Decisions 005, 014, 016) to the living-room TV stores. Log a DECISIONS.md
entry before starting a platform.

---

## Corrections from the re-verification pass

Seven corrections came from re-reading the live vendor docs. The strategy held;
four were new hard requirements and one was a shipped-code conflict.

1. **`TvLazyRow` / `tv-foundation` no longer exist.** Their functionality moved
   into `compose-foundation` 1.7.0-beta02. Use the standard `LazyRow` /
   `LazyColumn` / `LazyVerticalGrid` and depend only on
   **`androidx.tv:tv-material`** (1.1.0 as of 2026-07). Any tutorial showing
   `TvLazy*` or `rememberTvLazyListState` is stale.
2. **TV-G6 (live since 2026-08-01):** TV apps must support 32-bit *and*
   64-bit architectures **and comply with 16 KB page sizes**. Any app that ships
   native `.so` files (through `sqlite-bundled`, Media3, Coil or similar) needs an
   actual verification pass (`tools/audit_tv_g6.py`). It is not automatically
   satisfied.
3. **TV-PS (since Dec 2025):** `minSdkVersion` must be **31 or lower**. The
   template default (29, per `docs/platforms/android.md`) complies with Google TV. **Fire TV is
   stricter:** Fire OS 7 is API 28, so an app that targets Fire TV must drop
   `minSdk` to **28 or lower**. Archive Watch runs `minSdk` 23 on every Android
   surface for this reason.
4. **TV-G1:** Android App Bundles are mandatory for TV.
5. **TV-NP conflicts with shipped phone code.** The rule: *"Video apps must NOT
   use [Now Playing / background media] controls; video must pause when
   switching out."* A phone build that ships a `media3-session` `MediaSession`
   for lock-screen controls **must gate it off on TV**, or it is a
   quality-review failure.
6. **Audit for GMS early.** If the version catalog has **zero** Google Play
   Services / Firebase dependencies, the Fire TV port carries no GMS removal
   work (Archive Watch's did: OkHttp, kotlinx-serialization, Coil, Media3,
   androidx.sqlite only). The rule to preserve: Cast is GMS-dependent and must be
   excluded from the Fire variant (`tools/audit_fire_tv_gms.py`).
7. **Roku's 2026 mandates reach only large apps.** The Continue Watching /
   Instant Resume requirements (effective 2026-10-01) apply only to apps
   streaming **more than 5M hours/month (US)** or **1M (non-US)**. Deep linking
   and the performance thresholds apply from day one.

Two smaller notes. **Norigin Spatial Navigation is React-only**, so it cannot be
used in a vanilla no-build web app. The focus engine is ours to write, and it is
small. And Amazon now tells Fire OS 14+ developers to **move from ExoPlayer to
Media3**, which confirms the "do not adopt the stale `amzn` port" call below.

---

## The short version

The platforms split into **four technology families**, and the template's
existing codebases already cover two of them. Brand names matter less than the
runtime underneath.

| Platform | Runtime | Reuse vehicle | Code reuse | Platform fees | Verdict |
|---|---|---|---|---|---|
| **Google TV / Android TV** | Android TV OS | Kotlin/Compose/**Media3 app** (`android/`) | about 100% engine + new TV UI | $0 (same $25 account) | **Do first** |
| **Amazon Fire TV** | Fire OS (Android fork) | Same TV build, minus Google Play Services | Same as above | **$0** | **Do second** |
| **Samsung Tizen** | HTML5 web | **Vanilla-JS web app** (site root) | 70 to 80% + TV input layer | $0 | **Do third** |
| **LG webOS** | HTML5 web | **Vanilla-JS web app** | 70 to 80% + TV input layer | $0 | **Do third (pair with Samsung)** |
| **Roku** | BrightScript + SceneGraph (proprietary) | **None: full rewrite** | 0% | $0 | High reach, high cost. Separate decision |
| **Vizio SmartCast** | Curated/partner HTML5 | none (no open program) | n/a | n/a | **Not viable natively. Reach it through Cast** |

Two "free reach" routes that are **not app stores**:

- **Google Cast ($5 one-time):** add a Cast *sender* to the web and Android apps
  and host one HTML *receiver* page. Reaches Chromecast, Android TV/Google TV,
  **and Chromecast built-in TVs, which includes most Vizio sets.** This is the
  de facto Vizio path.
- **AirPlay (close to free):** `AVPlayer` exposes an AirPlay route to Apple TV
  and AirPlay 2 TVs (Samsung, LG, Vizio, Sony, TCL, Hisense, Roku TV, Philips).
  No extra program or cost. But see the custom-loader caveat under Family 4.

### Two builds reach five of the seven native targets

- **Build 1: one Android TV app ships to BOTH Google TV/Android TV AND Fire TV.**
  The engine (data layer, HTTPS networking, Media3) carries over almost entirely;
  the real work is a 10-foot D-pad focus UI.
- **Build 2: one shared Tizen + webOS web app ships to BOTH Samsung AND LG.**
  Both are HTML5 web runtimes, so the web app is the right shape. The real work
  is a TV input, focus and layout layer.
- **Roku** stands alone (proprietary rewrite). **Vizio** has no open path (use
  Cast).

### Recommended order

1. **Google Cast ($5) + confirm AirPlay.** Highest return, days of work, reuses
   existing code, and the only realistic Vizio reach.
2. **Android TV build to Google TV, then Fire TV.** Biggest device reach, close
   to full engine reuse, $0 incremental fees.
3. **Shared web build to LG webOS first, then Samsung.** Reuses the web app; LG
   first because Samsung is US-only without a business entity.
4. **Roku**, only if funding a multi-month BrightScript rewrite for the largest
   US living-room audience is worth it. Genuinely a separate decision.

### Facts that apply everywhere

- A **no-login, no-ads, no-IAP** posture lightens every certification a great
  deal: no billing flow, no auth, minimal data-safety disclosures. (On Roku it
  removes the Roku Pay requirement; on Google and Amazon it makes the Data
  Safety form close to empty.) Every one of those you add brings its review
  burden back.
- **Content rights must stay enforced in the data pipeline.** A reviewer
  spot-checking a problematic title on the home screen is a rejection and
  removal risk on every platform, exactly as on Apple. [FILL IN: the app's
  content-rights rule, if it serves third-party content.]
- **Physical test hardware is required or strongly expected** on every family:
  a Fire TV Stick (about $30), one Samsung and one LG TV in Developer Mode, a
  Roku device ($30 to $100). Emulators and simulators exist but do not satisfy
  certification.
- A **side-loaded WebVTT captions model** (`docs/MEDIA-PLAYBACK.md`) is directly
  usable on every platform (HTML5 `<track>`, Media3 `SubtitleConfiguration`, Roku
  `Video` node WebVTT) and satisfies the "if captions are present, they must be
  user-selectable" rules.
- **Progressive H.264 MP4 over HTTPS plays natively everywhere.** No DRM, no
  re-encode. Note the one regression risk (Roku) below.

---

## Family 1. Android-based (Google TV / Android TV, Amazon Fire TV)

**Reuse vehicle: the native Android app** (`android/`, Kotlin + Jetpack Compose,
Media3/ExoPlayer). The data layer, HTTPS networking, and Media3 playback carry
over essentially unchanged. The genuine work is a **10-foot D-pad focus UI**.
The phone touch layouts cannot ship as they are.

### Shared TV adaptation work (applies to both)

- **Leanback launcher intent filter.** A launcher activity declaring
  `android.intent.category.LEANBACK_LAUNCHER` (it can sit on the same activity
  as the phone `LAUNCHER`). Without it the app is invisible on TV devices.
- **`<uses-feature android:name="android.hardware.touchscreen" android:required="false"/>`**
  is mandatory to qualify as a TV app.
- **`<uses-feature android:name="android.software.leanback" android:required="false"/>`**:
  `required="false"` keeps the *same* app shipping to phones and tablets too.
- **Home-screen banner.** `android:banner`, **320x180 px**, must contain the app
  name as text, localized. (The Play *store* TV banner is a different 1280x720
  asset.)
- **Verify no permission implies required hardware** (camera, telephony) that
  would exclude TV; force landscape; overscan-safe margins.
- **TV UI + D-pad focus (the real work).** Every function reachable by remote
  with visible focus states. Use **Compose for TV**, a natural fit since the app
  is already Compose. Depend on **`androidx.tv:tv-material` only**;
  `tv-foundation` and the `TvLazy*` composables were removed once their behavior
  landed in `compose-foundation`, so lists and grids use the standard
  `LazyRow` / `LazyColumn`. This is a dedicated navigation and layout pass, not
  an engine port (`androidtv-compose-focus`).
- **Playback key handling (TV-PC / TV-PP).** D-pad center toggles play/pause,
  left/right seek, and `KEYCODE_MEDIA_PLAY_PAUSE` must toggle during playback.
- **TV-NP.** A *video* app must **pause on switch-away** and must **not** put
  background media controls in the system UI. Gate any phone `MediaSession` off
  for TV.
- **TV-G6.** 64-bit plus **16 KB page size** compliance across every bundled
  native library. Verify; do not assume.
- **`minSdk`.** 31 or lower for Google TV; **28 or lower** if Fire TV is in scope
  (Fire OS 7).

**Reuse estimate:** data layer, networking and Media3 playback close to 100%;
UI and navigation are the adaptation cost.

### Google TV / Android TV

- **Same runtime.** "Google TV" is the launcher skin over Android TV OS; one
  TV-capable AAB serves both. Media3/ExoPlayer is the recommended playback stack.
- **Account and cost:** the **same Google Play Developer account and the same
  package name.** TV is added as another **form factor of the same listing**, not
  a new app. Cost is the one-time **$25** already paid. No TV surcharge.
- **Submit:** Play Console, *Setup > Advanced settings > Form factors > Add
  Android TV*, accept the TV review policy. Upload the AAB with TV support; add
  the TV banner; at least one Android TV screenshot (up to 8); mention "Android
  TV" in the description. (`play-cli-submission` covers the API path.)
- **Review:** a **separate Android TV app-quality review** against the
  [TV app quality guidelines](https://developer.android.com/docs/quality-guidelines/tv-app-quality)
  (D-pad reachability, no dead ends, playback and back behavior, banner,
  touchscreen-not-required), on top of standard Play policy review. No published
  SLA; expect longer than a mobile update (days, occasionally 1 to 2 weeks).
- **Reach:** Google's own metric, **about 270M active devices (Sept 2024) to
  300M (2025)**; the largest smart-TV OS ecosystem by device count. ("Active
  devices" mixes TVs, boxes and operator set-tops.)

### Amazon Fire TV

- **Fire OS is an Android fork**, so the APK/AAB most likely runs with little or
  no change; the same leanback, banner and touchscreen declarations make it
  Fire-friendly, and the Fire remote maps to standard Android D-pad events (the
  Android TV focus work carries over directly).
- **`minSdk` 28 or lower.** Fire OS 7 devices are API 28 and are still a large
  part of the installed base. The template default of 29 excludes them.
- **The GMS risk.** Any GMS dependency (Google sign-in, Maps, FCM, Play Billing,
  **Cast**) fails on Fire OS. Audit the version catalog before starting. **The
  standing rule:** Cast is GMS-dependent, so when the Cast sender lands it must
  be excluded from the Fire variant (and any Google Drive sync likewise).
- **Playback:** modern Media3 works on Fire TV for progressive HTTP MP4, and
  Amazon now directs **Fire OS 14+ developers to migrate from ExoPlayer to
  Media3**. **Do not adopt Amazon's old ExoPlayer port**
  (github.com/amzn/exoplayer-amazon-port, stale at ExoPlayer 2.18.7, pre-Media3,
  effectively unmaintained). **Test on real Fire hardware** (a Fire TV Stick,
  about $30). Amazon requires physical-device QA anyway.
- **Account and cost:** a **separate Amazon Developer account**, **$0** to
  register and **$0** to submit; no per-app fee.
- **Submit:** Amazon Developer Console, upload the APK/AAB, icon, screenshots and
  description, target Fire TV form factors; pass Amazon's App Testing criteria.
  Deeper launcher and universal-search integration needs Amazon's catalog
  manifest (`com.amazon.device.REQUEST_CAPABILITIES`), which is not required to
  publish.
- **Review:** roughly **3 to 5 business days** (not a contractual SLA).
- **Reach:** **250M+ Fire TV devices sold** (late 2024); active users from about
  50M (Amazon, 2022) to about 118M (third-party 2025 estimates). Treat 50M to
  120M active as the realistic reach. Consistently first or second US connected-TV
  device platform with Roku.

### Sequencing within the family

Build the TV UI and focus layer once (Compose for TV). Ship to **Google TV /
Android TV first** (same account and listing, biggest reach, and the quality
review surfaces 10-foot UI gaps), then repackage the same build for **Fire TV**
(free) after the GMS audit and on-device Media3 validation.

---

## Family 2. Web-based (Samsung Tizen, LG webOS)

**Reuse vehicle: the vanilla HTML/JS/CSS web app** (site root; no framework, no
build step, Decision 001). Both platforms are HTML5 web runtimes, so the web app
is the right shape. **Keep the HTML5 `<video>` element.** Progressive H.264 MP4
over HTTPS is exactly its sweet spot; neither Samsung AVPlay, nor a webOS media
API, nor any DRM is needed for baseline playback.

Client-side data logic, networking, artwork and most view code port directly.
**Reuse is roughly 70 to 80%.**

### Shared new work: a TV input, focus and layout layer

- **Remote-key handling.** Arrows, Enter, Back/Return, media keys. (Samsung:
  `tizen.tvinputdevice.registerKey()` plus keydown listeners. webOS: `keydown`,
  including Back = keyCode 461, plus the Magic Remote **pointer** mode layered on
  top of the D-pad, so handle both pointer events and arrow-key focus.)
- **Focus and spatial navigation.** A web app built for pointer and touch needs a
  focus engine (roving `tabindex`, spatial resolution, and manual management) so
  the D-pad moves between cards and shelves.
- **App lifecycle.** Back must exit or navigate back per policy; pause video on
  suspend. (Samsung `visibilitychange` / `tizenhwkey`; webOS `webOSLaunch` /
  `webOSRelaunch`.)
- **TV-safe layout.** 1920x1080 baseline, 10-foot legibility, overscan-safe
  margins; the mobile-first CSS needs a TV breakpoint.

Build this layer **once** (`smarttv-web-app`: an additive `tv.js` / `tv.css`)
and share it across Samsung and LG, with small per-platform shims for key codes,
lifecycle events and packaging. A single Tizen + webOS build is realistic if the
app stays vanilla (skipping LG's optional Enact framework).

### Samsung Tizen

- **Package:** `.wgt` widget (signed zip: `config.xml` plus signature files),
  built with **Tizen Studio** or the **Tizen CLI** (`tizen build-web` /
  `tizen package`).
- **Account and cost:** **the Samsung TV Seller Office account is free; no
  submission fee.**
- **The biggest single constraint is the seller tier:**
  - **Public Seller** (default on signup) can **only launch apps in the US.**
  - **Partner Seller** can launch in any country but requires registering
    **business information** and Content Manager approval (an offline contract).
  - For a free solo app, **US-only Public Seller may be acceptable**; **global
    distribution effectively requires a business entity.**
- **Submit and certify:** upload the `.wgt` in Seller Office, then metadata,
  screenshots and rating, then Samsung **manual QA** against the Launch and
  Development checklists (mandatory features, Back-button behavior, playback,
  stability, policy). **Keep the signing certificate.** Updates must reuse it.
  Steps: `docs/store/tizen-submission.md`.
- **Timeline:** about 1 to 2 weeks, variable (multi-week rejection loops are
  reported).
- **Device test:** strongly expected. Side-load the `.wgt` through the TV's
  Developer Mode (keyed to the TV's IP). No Samsung-issued test TV.
- **Reach:** Tizen is consistently the **first or second smart-TV OS globally
  (about 20%, give or take several points)**, on **200M+ TVs across about 190
  countries.**

### LG webOS

- **Package:** `.ipk`, built with the **webOS TV SDK / webOS CLI**
  (`ares-generate`, `ares-package`, `ares-install` / `ares-launch` /
  `ares-inspect`) or **webOS Studio** (VS Code extension) plus the **webOS TV
  Simulator**. Current tooling (2025): SDK v10.x, CLI v3.2.x, Simulator v1.4.1;
  the old CLI and extension were deprecated in 2024. Pass `ares-package -n`
  (no-minify): the bundled uglify-js cannot parse modern syntax. LG's **Enact**
  (React-based) framework is **optional**. Plain web apps are fully supported.
- **Account and cost:** **the LG Seller Lounge account is free; no submission
  fee.** Individual sellers (18+) can register and **publish globally**, with no
  company required to start (friendlier than Samsung). A separate LG Developer
  account is needed for Developer Mode and device testing.
- **Submit and certify:** Seller Lounge, then the `.ipk` plus metadata
  (screenshots **1280x720**, description, rating), then LG technical review =
  **pretest + function test + content test**, plus supporting docs (a **UX
  scenario** and a **self-checklist**). Steps: `docs/store/webos-submission.md`.
- **Timeline:** about 5 to 10 business days, and it can repeat 2 to 3 cycles.
- **Device test:** **required.** Install the "Developer Mode" app from the LG
  Content Store, enable dev mode, side-load the `.ipk`. No LG-issued test TV.
- **Reach:** webOS is **second globally, about 25% installed base / about 12%
  of quarterly shipments (Q4 2024)**, on **130M+ TVs.** (Installed base and
  shipment share are different metrics; both are cited.)

### LG first, then Samsung

LG lets an individual publish globally with less friction; Samsung's default
tier is US-only without a business entity. Build the shared web and focus layer,
ship LG webOS to validate it globally, then package the same app as a Samsung
`.wgt`.

---

## Family 3. Roku (proprietary; full rewrite)

**Reuse vehicle: none.** Roku runs a proprietary two-language stack:
**SceneGraph** (XML UI framework: scenes, nodes, the focus and remote model, the
`Video` node) and **BrightScript** (BASIC-like scripting for logic). There is no
Swift/Kotlin/Java runtime and no general WebView app model, so **none of the
tvOS, Android, macOS or web code ports.** What carries over is architecture and
backend design, not code. The `roku-brightscript-app` skill carries the build.

- **The no-code escape hatch is gone.** Roku's feed-based **Direct Publisher**
  was disabled for new channels in **July 2023** and **sunset Jan 12, 2024**. Its
  legacy path also had a feed ceiling of about 500 KB, which never fit a catalog
  of tens of thousands of items. Today "no-code" means paying a third-party OTT
  SaaS (recurring cost, you do not own the code, limited to their UI). The
  realistic path is a **custom SceneGraph/BrightScript channel** (optionally
  accelerated by **SGDEX** templates for stock list, grid and detail screens,
  which will not cover bespoke surfaces).
- **Fees: $0.** No enrollment, annual, publishing or listing fee. Cost is a test
  device ($30 to $100) plus engineering time.
- **Process:** Roku account, enroll in the developer program, side-load to a
  test device, automated pre-cert tests (Static Analysis + Channel Behavior),
  create the listing, submit deep-link test params, Roku QA, rollout. First
  review about 24 to 48h; full cert about 3 to 5 business days; plus 1 to 2 days
  to appear. Roku advises submitting about a month ahead of a launch.
- **Certification specifics that bite:**
  - **Deep linking is mandatory** for public video apps (and feeds **Roku
    Search**). Real, non-trivial new work.
  - **Performance thresholds:** home screen fully rendered **within 15s**,
    content playing **within 8s** of initiation. Redirect latency on the media
    host is the most likely cert friction point. (In Archive Watch the
    archive.org `/download` 302 measured 0.5 to 1.0s to first byte.) **Measure
    early.**
  - **Roku Pay does NOT apply** to a free, no-login app, which removes the
    billing, auth and trial certification burden entirely.
  - Captions: Roku's `Video` node supports **WebVTT** and 608/708, so WebVTT
    captions satisfy the "if present, must be selectable" rule.
- **Playback regression risk.** Roku's `Video` node **owns networking**. There
  is no equivalent of a custom resource loader, so byte-range resume and node
  failover (`resilient-media-streaming`) cannot be reproduced. Prefer HLS/DASH
  derivatives where available (Roku documents these as the preferred formats),
  else accept `Video`-node defaults on progressive MP4.
- **Effort:** about **2 to 4 months** for one experienced Roku developer
  (longer learning BrightScript cold), driven up by a large data plane, faceted
  browse and search, drill-in, resume, deep linking and Roku Search, and ongoing
  maintenance as Roku revises certification.
- **The case for it is reach.** Roku is **first in US connected TV: about 37 to
  38% of devices, about 44% of viewing hours** (Pixalate Q1 2025), with **100M+
  global active households**, and it skews toward the value-seeking free-content
  viewer.
- **Verify before committing:** Roku ships periodic certification updates. Read
  the live checklist on developer.roku.com directly.

---

## Family 4. Closed, curated, and the cast routes (Vizio, aggregators, Cast, AirPlay)

### Vizio SmartCast is effectively closed to independent developers

- **No public self-serve developer program or open SDK.** Apps are hosted HTML5,
  but onboarding is **business-development and content-partnership driven**,
  routed through Vizio-designated preferred development partners. Submission
  needs a **username and password Vizio issues during registration**. You cannot
  sign up and ship. The documented APIs lean toward account and subscription
  monetization.
- **After the Walmart acquisition (closed Dec 2024, about $2.3B):** Vizio is
  primarily an **ad-monetization vehicle** (Walmart Connect). Gatekeeping is
  likely to get more commercial, not more open. A free, no-ads app is
  strategically uninteresting to them.
- **The realistic path is not a native Vizio app.** SmartCast carries
  **Chromecast built-in and AirPlay 2**, so reach Vizio TVs through **Google
  Cast** (below) and AirPlay without Vizio's approval.

### Google Cast is the pragmatic winner

- **Fully open to independent developers.** Register in the **Google Cast SDK
  Developer Console**, pay a **one-time, non-refundable $5**, register the app
  for an application ID, and point it at a hosted **HTML5 Custom Web Receiver**
  page (it fits static hosting). Publishing is self-serve, but the console
  refuses to publish until at least one sender is declared.
- **Reach:** Chromecast dongles, **Android TV / Google TV, and Chromecast
  built-in TVs (many Vizio and others)**, with no per-platform native TV app.
- **Code reuse:** the receiver is HTML/JS (reuse the web player); *sender* SDKs
  bolt onto the **web and Android** apps. (iOS Cast sender paths are more
  limited.) Cast depends on Google Play Services, so the sender is **not**
  available in the Fire TV build.

### AirPlay: a public API, with one trap

- **AirPlay 2 is a public API**; standard `AVPlayer` playback exposes an AirPlay
  route with no special entitlement, reaching Apple TV and AirPlay 2 TVs
  (Samsung, LG, Sony, Vizio, TCL, Hisense, Roku TV, Philips). It is not a
  discovery channel of its own (Apple-household TVs only).
- **The trap (learned in Archive Watch):** video AirPlay is **unsupported when
  the player item is served by a custom `AVAssetResourceLoaderDelegate`**. The
  delegate lives on the sending device, so the receiver has nothing to fetch, and
  AirPlay fails on every title with no build error. Observe
  `AVPlayer.isExternalPlaybackActive` and swap to a URL the receiver can pull
  itself (HLS first, then plain MP4) while a route is active. Verify on a real
  iPhone and Apple TV; the Simulator has no AirPlay routes.

### VIDAA (Hisense): same web build, no self-serve door

- **HTML5 runtime** (standard HTML5/CSS/JS plus some VIDAA system APIs), so the
  **Family 2 web build and focus layer cover it technically.**
- **40M+ connected devices** globally, projected toward about 8% of global TV OS
  share by 2029.
- **No public self-serve developer program surfaced** (as of 2026-08).
  Onboarding appears partnership-driven, like Vizio. Treat it as "the build is
  free, the door is closed": worth a partner inquiry once the web-TV build exists
  and can be demoed, not worth pre-building for.

### White-label OS aggregators are the most indie-accessible native TV OSes

- **Titan OS** (all Philips TVs from 2026, JVC and others; strong in Europe) has
  a **Partner Portal** where you create an account, submit a hosted HTML5 test URL
  and assets, and pass intake plus QA (about 2 to 4 weeks). Existing HTML5 apps
  mostly need remote-key mapping and User-Agent work. The closest thing to
  self-serve HTML5 onboarding among TV OSes. **Cost not published.**
- **Zeasn / Whale OS + Foxxum** (Zeasn acquired Foxxum in 2023) are HTML5
  app-store **aggregators** syndicated across many mid-tier TV brands, onboarded
  through their partner portal and historically open to smaller apps. Cost and
  terms are not clearly public.
- The web app is directly reusable for all of these (same hosted-HTML5 model;
  the main work is remote keys, UA strings and TV-safe focus and layout, the same
  Family 2 layer). One caution: a web-TV layout built for a 1920 CSS-px viewport
  (which webOS and Tizen present) is unverified on these.

### Operator- and partner-gated (not worth solo pursuit)

- **Comcast/Sky (RDK):** a public **Firebolt SDK** (JS/OpenRPC, HTML5, optional
  Lightning) across Xfinity X1/Flex and Sky Glass/Q, but **distribution is
  partner- and certification-gated**, not a self-serve store. Build-possible,
  ship-unlikely for a solo free app.
- **TiVo OS (Xperi):** HTML5, but no public self-serve indie program surfaced.

---

## Questions to answer before committing to any platform

- **Roku's current certification criteria.** Read the live checklist directly;
  criteria change.
- **Roku's 8-second play-start rule against the media host's redirect latency.**
  Needs a real on-device measurement.
- **Fire TV GMS audit and `minSdk`.** Zero GMS dependencies and `minSdk` 28 or
  lower, then Media3 validated on real Fire hardware.
- **Samsung global distribution.** Is US-only Public Seller acceptable, or will
  the owner sign an offline contract with Samsung HQ or a local subsidiary for
  Partner status? This is an owner business decision, not an engineering one.
- **TV-G6 16 KB page-size compliance** for every bundled native library.
- **VIDAA / Titan OS / Zeasn onboarding.** All run the same HTML5 build; none
  has a documented self-serve indie door. Inquire once the web-TV build is
  demoable, and get quotes if a native aggregator presence is wanted.
- **Which TV surfaces are in scope or deferred per platform**, recorded in
  `PARITY.md` (Decision 005) once a platform is actually started.

---

## Source notes

Compiled in August 2026 from official developer documentation and 2024 to 2026
industry reporting across four parallel research passes (Roku; Samsung + LG;
Google TV + Fire TV; Vizio + cast/aggregator routes). Market-share figures vary
by source and by metric (installed base, quarterly shipments, vendor "active
device" counts) and are given as ranges, not false precision. Key official
references:

- **Google TV / Fire TV:** developer.android.com/tv (Create a TV app, TV
  checklists, TV app quality, Distribute to Android TV); developer.amazon.com
  (Fire TV submission, differences from Android TV, app porting, media players).
- **Samsung / LG:** developer.samsung.com/smarttv and TV Seller Office (develop,
  AVPlay, membership, launch checklist); webostv.developer.lge.com (CLI guide,
  app ecosystem, Developer Mode app).
- **Roku:** developer.roku.com (SceneGraph/BrightScript overview, certification
  criteria and testing, deep linking, closed caption, media and streaming specs,
  channel publishing guide); Direct Publisher sunset notices.
- **Cast / Vizio / aggregators:** developers.google.com/cast (registration,
  custom web receiver); Vizio Preferred Developer Program and content-partner
  pages; the Walmart acquisition release; Titan OS, Zeasn and Foxxum
  partner-portal write-ups.
- **Market share:** Pixalate Q1 2025 CTV device report; smart-TV OS statistics
  aggregators (Amra & Elma, ElectroIQ); Google and Amazon device-count
  announcements.
