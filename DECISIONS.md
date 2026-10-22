# [APP NAME] — Architecture & Technology Decisions

Entries capture the *why* behind choices — not the *what* (the code
already shows that). Each entry should answer: **"what would the next
developer get wrong if they didn't know this?"** Lead with the rule,
follow with `**Why:**` and `**How to apply:**`. Append-only.

When a decision affects people and not just code, add one line:
**Who was in the room, who gains, who pays:** (who took part in the
decision, who benefits, and who bears the cost, in money, effort, or
something lost).

Invoke the `architectural-decision-log` skill when adding a new entry.

---

## 001 — Vanilla HTML/CSS/JS for Web

*Date: YYYY-MM-DD*

No framework, no build step. GitHub Pages serves static files
directly. Framework abstractions cost more than they save at this
scale; adding one would require a build pipeline, a CI step, and a
mental model every future contributor has to carry.

**Why**: reach for complexity only when simplicity has actually
failed, not when it might someday fail. The 2026 web platform
(View Transitions, Container Queries, Popover API, `<dialog>`, CSS
Nesting, `:has()`) is mature enough that the framework value-add
shrinks every year.

**How to apply**: revisit if component count exceeds ~20 OR a
feature genuinely needs reactive state across many components.
Until then, plain DOM + ES2022 + Supabase SDK via CDN.

---

## 002 — Xcode Project at Repository Root

*Date: YYYY-MM-DD*

`.xcodeproj` lives at repo root, no subdirectory, no spaces in
project name.

**Why**: Xcode Cloud requires `.xcodeproj` at the repo root for
auto-discovery. Spaces in paths cause shell-script and CI issues.
Past projects that nested under two levels with spaces lost hours
debugging "Project does not exist at root."

**How to apply**: the project is generated at the repo root from
`project.yml` (`xcodegen generate`) and gitignored. Product name has
no spaces. Sources stay in `apple/`, preserving the Core / iOS /
macOS / tvOS split (Decision 013). See `apple/README.md`.

---

## 003 — Shared Apple Version Config via xcconfig

*Date: YYYY-MM-DD*

`AppVersion.xcconfig` at repo root defines `MARKETING_VERSION` and
`CURRENT_PROJECT_VERSION`. All Apple targets (the universal app +
any extensions) reference it.

**Why**: editing version numbers via Xcode's identity panel creates
per-target overrides in `project.pbxproj` that shadow the xcconfig,
causing targets to drift silently.

**How to apply**: ALWAYS edit `AppVersion.xcconfig` directly. Never
use Xcode UI for version numbers. Bump on every ship as part of the
`feature-shipping-discipline` 7-step sequence.

---

## 004 — SwiftUI + @Observable + SwiftData (Apple) — iOS 26 / tvOS 26 baseline

*Date: YYYY-MM-DD*

SwiftUI for all UI. `@Observable` for state. SwiftData for local
persistence (on tvOS: with the App Group container per Decision
017). UIKit only where SwiftUI lacks a native equivalent.
**`IPHONEOS_DEPLOYMENT_TARGET = 26.0` / `TVOS_DEPLOYMENT_TARGET =
26.0`** as the floor.

**Why**: iOS 26's user base passes 90% by 2026; optimizing for
back-compat costs feature velocity AND prevents using Liquid Glass,
native `Tab(role: .search)`, `scrollEdgeEffectStyle`,
`.matchedTransitionSource`, etc. The DESIGN.md anti-patterns
(custom drawers, custom scroll-edge fades, hand-rolled focus
animations) all came from reaching for custom when native iOS 26
shipped the thing.

**How to apply**: write iOS 26 native APIs directly without
`@available(iOS X, *)` guards. When extending an existing file
with old guards, remove them. When adding new code, never write
iOS 17 / 18 workarounds. For framework-level depth, invoke
`all-ios-skills:<name>` rather than re-deriving.

**Amended 2026-09-30 (from Archive Watch, measured)**: the floor is chosen
by the hardware it reaches, not by adoption share. iOS 26 dropped the
iPhone XS/XR, and moving to iOS 18 cost two files; below 17 SwiftData and
Observation break. tvOS stays at 26 because 27 dropped the Apple TV HD and
4K 1st gen. Newer APIs are used fully behind `#available`, and
`tools/test_ios_floor.py` / `test_tvos_floor.py` hold the floor in CI. The
"no guards, no workarounds" rule above is superseded. See
`docs/path/03-going-native.md`.

---

## 005 — Cross-Platform Feature Parity

*Date: YYYY-MM-DD*

Every platform in the project's platform set (web, iOS/iPadOS, tvOS,
Android — decided in M0, see Decision 014) implements the same core
feature set. Platform-specific implementation is acceptable (Keychain
vs Tink-encrypted DataStore vs localStorage); platform-exclusive
features are the exception, not the rule.

**Why**: users expect the same capabilities regardless of platform.
Implementation details can differ to leverage each platform's
strengths. The animating principle is **feature parity, not design
consistency** — web should feel like the web, iOS like iOS, the TV
app like the living room, Android like Android.

**How to apply**: track parity in `PARITY.md` (single source of
truth). When adding to one platform, mirror to the others in
the same change set where feasible, and update PARITY.md row(s).
Reject PRs that ship a feature without updating PARITY.md. Run the
periodic parity audit (`cross-platform-parity-discipline` skill)
before launch waves.

---

## 006 — Kotlin + Jetpack Compose for Android (NOT KMP / CMP / Flutter / RN)

*Date: YYYY-MM-DD*

Native Kotlin + Compose for the Android client. Separate codebase
from iOS Swift/SwiftUI; same monorepo (`/android/`).

**Why**: KMP works best when both platforms start together — most
new projects can't retrofit it without rewriting iOS. CMP can't
render Liquid Glass natively, which kills it for any iOS-26-shaped
design. Flutter / RN add runtime + bridge overhead for every native
API (CameraX, ML Kit, Credential Manager, biometrics) — strictly
worse than native Android for an Android-only client.

**How to apply**: structure the domain layer as pure Kotlin (no
Android imports) inside `:core:domain` so a future KMP `:shared`
module is the upgrade path if/when needed. Don't preemptively
optimize for that path; keep the door open.

---

## 007 — Material 3 + M3 Expressive; brand theme default, dynamic color opt-in

*Date: YYYY-MM-DD*

Android ships a fixed brand theme by default — NOT Material You
dynamic color. User can opt into "Use system colors" in Settings,
which flips to `dynamicDarkColorScheme(context)` on Android 12+
and overrides `primary` only (semantic / element colors never
change).

**Why**: content semantics (status pills, weapon colors,
designation badges) need stable colors; wallpaper-derived `primary`
fighting brand `#FF5C35` reads muddy. Same rule as
iOS: element / semantic on content, brand on chrome.

**How to apply**: in `ui/theme/Color.kt`, keep brand tokens at the
top and semantic tokens in a separate `AppSemantics` object. Theme
overrides only `colorScheme` brand slots — never the semantic
object.

---

## 008 — Android: Compose-only, no XML / AppCompat / ActionBar

*Date: YYYY-MM-DD*

Compose for every screen. `ComponentActivity` (never
`AppCompatActivity`). No XML layouts. No AppCompat. No
`setSupportActionBar()`. M3 SearchBar / ModalBottomSheet /
NavigationSuiteScaffold / SharedTransitionLayout cover the
component catalog.

**Why**: Compose has been Google's recommended UI toolkit since
2021; all new M3 Expressive components ship Compose-first. Mixing
in XML / AppCompat doubles the maintenance surface and forces every
new screen to choose between paradigms. The single-paradigm
discipline keeps reviews tight.

**How to apply**: any time you're about to write a custom
Composable, first check whether M3 / M3 Expressive ships a
component that does 80%. If yes, use it and accept the spec. Same
"native first" failure mode as iOS — reaching for custom when the
platform already shipped the thing.

---

## 009 — Android: edge-to-edge + predictive back are non-negotiable

*Date: YYYY-MM-DD*

`enableEdgeToEdge()` called in every Activity. `Scaffold` /
`safeContentPadding()` / `systemBarsPadding()` for inset handling.
M3 components animate during predictive-back drag without `BackHandler`
intervention — only override `BackHandler` for unsaved-changes
confirmations.

**Why**: Android 16 (`targetSdk >= 36`) ignores
`windowOptOutEdgeToEdgeEnforcement`. Predictive back is the default
in Android 15 and non-opt-out at `targetSdk >= 36`. Fighting either
is fighting the platform.

**How to apply**: never call `WindowCompat.setDecorFitsSystemWindows(window, true)`.
Never lock orientation at >600dp width. Test every screen with
predictive-back drag (3-finger swipe in Android Studio's emulator)
before merging.

---

## 010 — Universal Links / App Links: `/.well-known/` is the contract

*Date: YYYY-MM-DD*

iOS `apple-app-site-association` (no extension) AND Android
`assetlinks.json` BOTH live in `/.well-known/` at the domain root.
Both are JSON. Coexist without conflict.

**Why**: this is the single most-frequently-blown piece of cross-
platform setup. Symptoms (disambiguation chooser on Android; URL
falls back to Safari on iOS) look like the OS is broken; the
actual bug is always the verification file missing, malformed, or
excluded from the static-site build (Jekyll excludes dotdirs by
default).

**How to apply**: see `/.well-known/README.md` for the exact JSON
shapes. Add the file paths to Jekyll's `_config.yml` `include:`
list. For Android, include BOTH the upload-key fingerprint AND the
Play App Signing fingerprint — internal-testing AABs are
upload-signed; production installs are Play-signed.

---

## 011 — Refresh JWT before every Worker / Storage / Edge Function call

*Date: YYYY-MM-DD*

Both iOS and Android wrap their HTTP clients in an interceptor that
calls `refreshIfNeeded()` before forwarding the request. The auth
SDK's auto-refresh only covers its own internal HTTP path; external
endpoints (Cloudflare Workers, Supabase Storage, custom Edge
Functions) bypass it.

**Why**: the silent failure mode is a 401 (or, worse, a 400 with
"exp claim" in the body) on a Worker call that looks like a generic
backend bug. The wasted-debugging cost compounds — every team that
ships this hits it once.

**How to apply**: iOS — `SupabaseClient.refreshIfNeeded()` extension
called at the top of every Worker / Storage method. Android — install
a `SupabaseAuthInterceptor` on the OkHttpClient that's shared
between Coil + Ktor + Supabase. Web — `js/api.js` checks token
expiry before every cross-origin request.

---

## 012 — Brand vs Semantic color split is binding on all platforms

*Date: YYYY-MM-DD*

Two distinct token systems. **Brand** colors (primary / accent /
background / surface) for UI chrome only. **Semantic** colors
(success / warning / error + domain-specific) for content meaning
only. Never use a brand color for content meaning; never use a
semantic color for chrome.

**Why**: tokens drift when one developer uses `--color-primary` to
mean "this is the primary action" and another uses it to mean
"this state is active." Splitting brand from semantic at the token
layer makes drift impossible — the names don't overlap.

**How to apply**: web `:root` separates `--brand-*` from
`--semantic-*`. iOS `Design.swift` has separate `BobaBrand` and
`BobaSemantics` enums. Android `Color.kt` keeps brand tokens at
file scope and semantic tokens inside `object AppSemantics`. Theme
overrides only brand; dynamic color (Material You) opt-in only
affects brand.

---

## 013 — One universal Apple target serves iPhone, iPad, and Apple TV

*Date: YYYY-MM-DD*

iOS, iPadOS, and tvOS ship from a SINGLE Xcode app target. Shared
logic lives in a `Core/` group (models, networking, state, query
layers, playback/queue logic, sync); per-platform UI lives in `iOS/`
and `tvOS/` groups behind `#if os(iOS)` / `#if os(tvOS)` guards.
`Core/` never imports per-platform UI — when Core logic needs app
state, Core defines a protocol and the app store conforms to it.

**Why**: measured in production (Archive Watch): ~60–70% of a media
app's Swift is platform-agnostic. Separate targets (or separate
projects) turn that overlap into copy-drift — the duplicated files
each grow their own bug fixes. The universal target also gives both
platforms the same bundle-adjacent benefits for free: one CloudKit
container (an iPhone and an Apple TV signed into the same iCloud
account sync without extra work), one version number, one Xcode
Cloud workflow. The conversion of a tvOS-only project to universal
was done mid-App-Review without regressing the in-review build —
the `#if os` seam is that clean.

**How to apply**: see `apple/README.md` for the exact setup. New
shared logic goes in `Core/` FIRST; only drop to a platform group
when the code genuinely touches platform UI. A deliberate
per-platform copy (rare) carries a "don't let these drift" comment
and is recorded as unification debt. After touching any `Core/`
file, build BOTH the iOS and tvOS destinations before declaring
done.

---

## 014 — The platform set is a decision, not a default

*Date: YYYY-MM-DD*

In M0, decide which of the four platforms (web, iOS/iPadOS, tvOS,
Android) this app ships on, and record it here with reasons. A
skipped platform stays in PARITY.md as a 🚫 column with the reason —
never silently deleted.

**Why**: tvOS earns its place when the content is lean-back — video,
music, ambient surfaces, photo-driven experiences. It is the wrong
platform for lean-in apps (text entry, productivity, anything
keyboard-shaped: typing on a Siri Remote is hostile). Carrying a
platform that doesn't fit costs every future feature a parity cell;
dropping one silently makes the matrix lie.

**How to apply**: replace this entry's placeholder with the actual
decision ("This app ships on web + iOS + Android; tvOS skipped
because …"). If the set changes later, append a superseding entry.

---

## 015 — Per-ecosystem sync on the user's OWN cloud; no backend to run

*Date: YYYY-MM-DD*

User state (favorites, progress, preferences) syncs per ecosystem,
each through the user's own free cloud: **CloudKit private database**
for Apple devices (iPhone ↔ iPad ↔ Apple TV), **Google Drive App
Data folder** for Android + Web. No cross-ecosystem sync, no
separately-run sync backend. Sign-in is OPTIONAL and gates ONLY
sync — every browse/use verb works signed-out, offline-first, on
every platform.

**Why**: a custom sync backend is a server to provision, pay for,
secure, and operate forever — for data that platform vendors already
host free in the user's own account. CloudKit's private DB and
Drive's App Data folder are exact analogs (hidden, per-app,
user-owned). The privacy story is also strictly better: the
developer never sees the data. Production-verified across
Apple TV ↔ iPhone households.

**How to apply**: see the `per-ecosystem-sync-islands` skill for the
full pattern — including the CloudKit trap that cost a real project
weeks (never `CKQuery` by recordName; use fixed-ID records fetched
directly), tombstones + last-writer-wins merge, and the rule that
sync status must be user-visible (a "Last sync / Sync Now" row),
never silent.

---

## 016 — Shared data plane: published once, every client a consumer

*Date: YYYY-MM-DD*

If multiple clients consume the same content/data (a catalog, feed,
or corpus), it is compiled by ONE pipeline into ONE published
artifact set, and every client is a consumer only. No client
re-implements pipeline logic, re-derives content flags, or re-hosts
the data. The contract (schemas, asset URLs, query verbs, refresh
protocol) lives in `docs/DATA-CONTRACT.md`, authored the moment the
second client exists.

**Why**: per-client data logic is parity drift at the data layer —
five implementations of "what is visible" diverge silently and the
bugs are invisible until a user compares two devices. Baking flags
(visibility, maturity, rights) into the published artifact at build
time means every client filters with a `WHERE` clause and inherits
policy fixes for free.

**How to apply**: see the `shared-data-plane-contract` skill — it
carries the publishing patterns (Releases vs Pages vs git), the
verified browser CORS/Range matrix, ETag-conditional refresh,
additive schema evolution, and the merge-guard rule (a rebuild may
never replace the accumulated artifact; mutations are additive and
reversible).

---

## 017 — tvOS persistence: Caches + App Group only

*Date: YYYY-MM-DD*

On tvOS, the app writes ONLY to `Library/Caches`, `tmp`, and an App
Group container. Anything that must survive (user state, snapshots
shared with a Top Shelf extension) lives in the App Group; anything
re-fetchable lives in Caches. SwiftData/Core Data containers are
built with an explicit App Group `ModelConfiguration`, with a
fallback chain down to in-memory so the app always launches.

**Why**: tvOS apps cannot write to Application Support or Documents
— but the SIMULATOR allows it, so the bug passes every simulator
test and crashes only on real hardware (`NSCocoaErrorDomain 513`,
EPERM). SwiftData's default store location is Application Support,
so the default `.modelContainer(for:)` crashes on a real Apple TV.
Found the hard way on a first device install.

**How to apply**: never `FileManager.url(for:
.applicationSupportDirectory, …, create: true)` on tvOS. Never
`try!` a file/directory creation. Treat Caches as purgeable. The
`tvos-platform-patterns` skill has the full container-fallback
recipe.

---

## 018 — Debug/state env hooks ship in the app, as production no-ops

*Date: YYYY-MM-DD*

The app honors environment-variable hooks — `APP_START_TAB`,
`APP_START_ITEM`, `APP_DIAG=1`, `APP_AUTOPLAY=1` — that drive it to
a known screen/state at launch or enable structured diagnostic
logging. All are no-ops in production builds.

**Why**: two recurring needs share one mechanism. (1) Store
screenshots: `SIMCTL_CHILD_APP_START_ITEM=… simctl launch` opens
exactly the screen to capture, per locale, scriptable. (2) Debugging
behavior you can't attach to (a TV across the room, playback
stalls): env-gated diagnostics turn on without a code change and
cost nothing when off. Re-deriving either ad hoc wastes a session
each time.

**How to apply**: wire hooks in the root view once per platform
(launch-env on iOS/tvOS; `adb shell am start` extras on Android;
query params on web — which already has them for free). Screenshot
IDs/state must come from LIVE data, not stale seeds. Remove one-off
diagnostics after a fix; keep env-gated ones.

---

<!-- Add new entries below this line. Lead with the rule. Number
     sequentially. Don't rewrite existing entries — append a new
     one that supersedes or amends. -->

## 019 — macOS joins the universal Apple target (amends 013)

*Date: YYYY-MM-DD*

The ONE Xcode target from Decision 013 also builds **macOS** — the
Apple app is iPhone + iPad + Mac + Apple TV from a single target and
a single shared `Core/`. macOS UI lives in an `apple/macOS/` group
behind `#if os(macOS)`; `RootView` gets an explicit `#elseif
os(macOS)` branch (a bare `#else` silently hands macOS the iOS view).

**Why**: macOS is the cheapest platform to add — it reuses the entire
Apple Core (models, networking, the resilient loader, query layer,
sync) and joins the same CloudKit private database, so cross-device
sync is free the moment the container is shared. What's genuinely new
is only the Mac-native shell. macOS is NOT the iOS app resized: it is
a pointer + keyboard + menu-bar + resizable-multi-window app, and its
traps are Mac-only (player-as-window-root, no `externalMetadata`,
the full-width-hero + fill-image layout blowups, the `ImagePipeline`,
`NSWorkspace` deep links).

**How to apply**: add Mac to the target's Supported Destinations; add
the `macOS/` folder + `_macOS.swift` suffix convention + the explicit
`RootView` branch. Read `macos-platform-patterns` before any Mac
shell / player / hero / window work. Shared Core files that use
UIKit-only APIs (e.g. `AVPlayerItem.externalMetadata`, which is
iOS/tvOS-only) must be `#if os()`-guarded when first compiled for
macOS. A Core change now moves three Apple platforms — verify each
builds.

---

## 020 — Default Apple submission is a cloud build on a GitHub runner

*Date: YYYY-MM-DD*

App Store builds are produced, signed, and uploaded by
`.github/workflows/appstore-build.yml` on a GitHub-hosted
released-macOS runner (a `macos-<n>` image with a GA Xcode), NOT from
the developer's Mac. Signing is **manual** via `.p12` certs held as
CI secrets (the ASC API key creates certs/profiles via REST but
cloud/automatic signing fails for a team key). The default ship flow
is: bump `AppVersion.xcconfig` → push → `gh workflow run
appstore-build.yml -f platform=all` → select the build in App Store
Connect → Submit. Full runbook: `docs/CLOUD-SUBMISSION.md`; details
in the `cloud-appstore-submission` skill.

**Why**: a dev Mac running a **beta macOS** has its App Store builds
**rejected after upload** (ITMS-90301, "not accepting applications
built with this version of the OS") — and a GA Xcode does not fix it,
because the build MACHINE's OS is the problem. Apple also keeps
raising the Xcode/SDK floor (ITMS-90111). A GitHub runner on a
released OS + GA Xcode clears both, free for a public repo, with no
Xcode Cloud compute budget and no SIP spoof. TestFlight still accepts
beta-OS/beta-Xcode builds, so testing is never blocked — only App
Store review is gated.

**How to apply**: set the 7 CI secrets once (`APPLE_DIST_P12`,
`APPLE_INSTALLER_P12`, `APPLE_P12_PASSWORD`, `APPLE_DIST_CERT_ID`,
`ASC_KEY_P8`, `ASC_KEY_ID`, `ASC_ISSUER_ID`) with
`tools/ci_make_signing_p12.py` + `gh secret set`. Two cert gotchas
are load-bearing: (1) `csrContent` in the ASC API must be the RAW PEM
string, not base64 (else `409 ENTITY_ERROR`); (2) the `.p12` must use
`openssl pkcs12 -export -legacy` or macOS `security import` fails
"MAC verification failed". Bump BOTH `MARKETING_VERSION` +
`CURRENT_PROJECT_VERSION` every build (review burns a build number
even on rejection). The `macos-<n>` runner label + Xcode version are
a moving target — track the current release.

---

## 021 — Android publishes to Play via the Developer API from the CLI

*Date: YYYY-MM-DD*

Android releases go out with `tools/submit-play.sh` (builds the
signed AAB) + `tools/play-publish.py` (Google Play Developer API v3
"edits" transaction: insert → upload → set track + notes → commit),
authenticated by a service-account JSON key. No manual Play Console
upload. See the `play-cli-submission` skill.

**Why**: the Play analog of Decision 020 — one command from bump to
published, scriptable and repeatable. Play rejects any
previously-uploaded `versionCode` (even unreleased), so the script
bumps it every run.

**How to apply**: the Play `applicationId` (the store package) may
differ from the Kotlin `namespace` — set both deliberately. Keep the
SA JSON outside git (`~/.config/play/…`, chmod 600). If creating the
SA key hits an IAM org-policy block (common under a Workspace/org),
create the GCP project + service account under a **personal gmail**
via `gcloud`, and retry the key-create (eventual consistency 404s the
first attempt). Staged rollout via the release status
(`draft`/`inProgress` fraction/`completed`).

---

## 022 — Player title/metadata uses each platform's native chrome hook

*Date: YYYY-MM-DD*

A title/description that appears with the playback controls uses each
platform's BEST NATIVE hook, never a custom synced overlay where the
player owns its own chrome: iOS/tvOS = `AVPlayerItem.externalMetadata`
(AVKit syncs it to the transport for free); **macOS = the window
title bar** (macOS `AVPlayerItem` has no `externalMetadata`); Android
Media3 = `PlayerView.setControllerVisibilityListener`; web `<video>` =
a non-interactive overlay mirroring the browser's user-activity timer.

**Why**: a custom `contentOverlayView` + tap/timer was tried on Apple
and failed (showed before load, faded on its own timer, and AVKit's
gestures swallowed the tap). When the player already owns its chrome,
feed metadata INTO that chrome instead of racing it. This is the
`native-platform-first` discipline applied to one recurring surface.

**How to apply**: never build a parallel transport or a custom
synced overlay on a platform whose native player exposes a metadata
or controls-visibility hook. On macOS specifically, do NOT wrap the
asset in an `AVMutableComposition` to inject a title — over a
resilient custom-scheme asset it renders blank video. Fix embedded
metadata at the source, never at the player layer.

## 023 — Cross-platform multiplayer rides a transport seam; the protocol + arbiter live in Core

*Date: 2026-07-03*

Real-time multiplayer that spans native + web puts the wire types and the
authoritative logic (who wins, whose turn, when to advance) in the shared `Core/`
layer with **no platform-networking import**. Every transport — Bonjour+TCP,
Wi-Fi Aware, GameKit, a backend WebSocket — conforms to one small seam
(`PeerLink`: advertise/discover/connect/send-frame/on-frame). The host/client
state machines are written once against the seam. Play is **host-paced,
everyone-plays**: the host ships the shared plan once and each device runs its OWN
deterministic engine over the identical list, self-reporting its score
(friendly-game trust model). A peer match with no host elects the lowest stable id
as leader.

**Why**: Core with no networking import compiles for every target (incl. tvOS +
the Kotlin/JS mirrors) AND is unit-testable offline — a whole match runs in a test
with no radio or server. The seam is what makes "local same-room" and "online" the
SAME feature with a different adapter, instead of two codebases. Self-reported
scores keep the wire tiny and are correct for people in a room together.

**How to apply**: build the local same-room path first (**mDNS discovery + plain
TCP + app-layer AES-256-GCM keyed by `SHA256("<ns>:"+ROOMCODE)`** — the only
cross-platform LAN path; TLS-PSK fails because Android's Conscrypt can't do
GCM-PSK, and a wrong code → GCM tag fails → frame dropped = the pairing gate). Ship
IDs not payloads when both clients bundle the same corpus (~100× smaller frames, with
a full-object fallback). Pin the wire with a canonical schema + a golden test that
encodes on one stack and decodes on the other, both directions, plus an id-parity
check. See `cross-platform-multiplayer`.

## 024 — Online play is per-ecosystem native + a neutral backend; bot-first with honest labels

*Date: 2026-07-03*

Online (across-the-internet) play rides each ecosystem's native path where one
exists and a neutral backend where none does — behind the SAME `PeerLink` seam as
local play (Decision 023). **Apple = GameKit** (free matchmaking + transport).
**Android + web = a neutral backend** because **Google killed Play Games real-time
multiplayer in 2020** — the cheapest that works is **Firebase Realtime Database**
(anonymous-auth-gated ephemeral rooms, a transaction-claimed matchmaking queue,
Security-Rules-only, hard-stop free tier). Launch matchmaking is empty, so ship a
**believable CPU opponent** first (clamped correct-rate that varies by
category/difficulty, log-normal timing, ~5% freeze).

**Why**: there is no native Android real-time transport, so cross-platform online
REQUIRES a backend for the non-Apple clients; forcing Apple through the same
backend would waste GameKit's free matchmaking. A labeled bot makes multiplayer
feel alive from day one with zero connectivity.

**How to apply**: reuse the local coordinator verbatim online (leader = lowest
stable id runs the host role). **NON-NEGOTIABLE: a bot is ALWAYS visibly labeled
CPU, never presented as a human** (a disguised bot is a dark pattern —
`learning-orientation-design`). The friendly-game trust model does NOT hold between
strangers: if you matchmake strangers, add a server-authoritative spine (server owns
the clock; split public prompt from private answer key; reject late answers). RTDB
security rules only ever BROADEN — a blanket parent `.write` overrides a per-uid
child rule; gate each child. See `cross-platform-multiplayer`.

## 025 — Cross-platform-identical values use order-independent hash-rank + golden-parity tests

*Date: 2026-07-03*

Any value that must be identical on every platform — a "daily" content pick, a
shared shuffle, a match plan, a hash key — is produced by an **order-independent
hash-rank** (hash a canonical string per candidate with FNV-1a64, take the N
smallest), NEVER a seeded shuffle. One algorithm, N language mirrors, changed in
lockstep, proven by a golden test that runs the REAL code on every stack and diffs.

**Why**: a seeded shuffle diverges across languages (different PRNGs, different sort
stability). Hash-rank is order-independent and trivially identical *if* the hash is
identical — and a golden test is the only thing that proves the mirrors haven't
drifted.

**How to apply**: mirror the ~15-line selection in each stack + a Python copy if the
build needs one; treat a drifted mirror as a P0 bug. Watch the gotchas: Kotlin
signed-`Byte` sign-extends non-ASCII bytes (mask `and 0xFF`); JS needs BigInt for a
full 64-bit hash; compute `dateKey` in ONE agreed timezone; hash UTF-8 bytes not
UTF-16. See `cross-platform-determinism`.

**Amended 2026-09-30**: mirroring is the last resort, not the default.
If a pipeline or server can compute the value, publish the result as
data and have every client read it (`cross-platform-determinism` Rule
0). **Why:** Archive Watch computed channel schedules on device from a
shared seed in four ports, each with a slightly different shuffle and
a local-time day anchor; two viewers agreed on 0 of 14 channels
(Archive Watch Decision 144). Publishing the timeline made agreement a
property of the file. **How to apply:** hash-rank plus golden tests
still govern any value that must be computed on device (offline or
local state, before any download, peer wire protocols); everything
else ships as a published artifact, and a client with no file shows an
error with Retry rather than a guessed local value.

## 026 — Persist per-event detail, not just aggregates

*Date: 2026-07-03*

Records/history persist per-EVENT detail (e.g. each answer: id, prompt, outcome,
correct value), not only the aggregate (score, count). Add the detail as an
OPTIONAL field so the store migrates automatically and old detail-less records
degrade gracefully.

**Why**: aggregate-only records are a dead end — you can't later add a history
drill-in, a per-item review, or attempt comparison without the detail on disk, and
by then the old records will never have it. Storing it from the start is nearly free
and unlocks a whole class of later features.

**How to apply**: keep the detail spoiler-safe (it's the user's own history) so it
can persist in the clear. Keep ALL N platform stores (SwiftData / Room-or-prefs /
localStorage) in lockstep — adding a field means all N writers + readers in one
change set. Old records with no detail show totals only — never crash, never
fabricate.

## 027 — Cloud Apple builds self-revoke stale auto-created Development certs

*Date: 2026-07-03*

The cloud App Store workflow revokes stale API-created Development certs (keeping
the newest 1–2) in a step BEFORE the archive.

**Why**: `xcodebuild archive -allowProvisioningUpdates` on a fresh runner
auto-creates a new Development signing cert every build; they accumulate until
Apple's per-account cert cap blocks the archive ("maximum number of certificates").
The app compiles fine — it's a pure account-state failure that recurs every few days
of builds without a cleanup.

**How to apply**: `asc_certs.py cleanup [--keep N]` lists `/v1/certificates`, filters
to `DEVELOPMENT`-type certs named "Created via API" (sparing named + all Distribution
certs), and DELETEs the surplus via the ASC-API JWT the build already has. Wire it as
`python tools/asc_certs.py cleanup --keep 2 || true` before the archive so it never
fails the build and the cap can never block one again. Never hand-delete in the
portal. See `cloud-appstore-submission`.

---

## 028 — Smart TVs are two builds plus two zero-app routes, never six apps
*Date: 2026-08-24 (from Archive Watch Decision 047, shipped to five stores)*

The non-Apple living room is reached through exactly two reuse vehicles:
the Android app gains a TV form factor (same applicationId, `leanback`/
`touchscreen` `required="false"` → Google TV AND Fire TV), and the web app
gains an additive TV input/focus layer (`tv.js`/`tv.css`, no fork, no
framework → LG webOS AND Samsung Tizen). Google Cast (one $5 registration +
one hosted receiver) covers Chromecast and is the ONLY realistic Vizio path;
AirPlay is free via AVPlayer. Roku is deferred to its own funded decision —
0% reuse, and its `Video` node owns networking so streaming resilience
cannot be reproduced.

**Why**: the brand names hide that there are only four runtime families, and
two are already owned. Total cash to reach five new stores: $5.

**How to apply**: never fork the Android app or web app for TV — TV is a
runtime branch (`UiModeManager` on Android; a class on `<html>` on web).
Cast is GMS-dependent and must be excluded from the Fire TV flavor. See
`docs/TV-PLATFORMS.md` (store landscape), `docs/templates/TV-DESIGN-template.md`
(binding rules), `androidtv-compose-focus` + `smarttv-web-app` skills, and
`tv/build-tv-packages.sh`. Samsung's self-serve tier is US-only; LG first.

## 029 — Windows is an optional first-class platform, and CI is the Windows machine
*Date: 2026-08-24 (from Tidbits Trivia Decisions 045/046/055/056, shipped to the Microsoft Store)*

When a desktop app earns a Windows column, it ships native Avalonia +
FluentAvalonia + .NET as an MSIX to the Microsoft Store — with NO Windows
hardware in the loop. `windows-latest` on a public repo is the only Windows
compute needed: Avalonia.Headless renders real Skia pixels in-process, visual
baselines are captured ON Windows and enforced only there, and the whole
ship is `gh workflow run`.

**Why**: no free Windows box exists (researched exhaustively), and none is
needed — headless CI gives strictly more than an RDP session, reproducibly,
at $0 forever.

**How to apply**: `docs/windows/WINDOWS-PLAYBOOK.md` +
`docs/windows/WINDOWS-STORE-SUBMISSION.md` (written as the runbook for the
NEXT app). Isolate any platform TFM in its own reflection-loaded library —
one feature's `net10.0-windows` TFM on the app project takes the whole
pipeline hostage. Sign in with Apple on Windows needs an HTTPS bounce (a $0
Cloudflare Worker) because Apple forbids localhost redirect URIs.

## 030 — The CI fleet runs on the split-lock / budget / guard / sweeper / auditor doctrine
*Date: 2026-08-24 (from Archive Watch Decisions 018/020/048/057/066/089–095, ~35 workflows)*

Every scheduled workflow follows `docs/CI-FLEET.md`: writers split into
unlocked compute + a ~2-minute locked apply merging a field-level delta;
long tools take budgets that PUBLISH (measured from process start, able to
fire inside one item) with step timeouts only as continue-on-error
backstops; restores never swallow (only a non-existent release is a first
run) and shared-index publishes are shrink-guarded; a 30-minute sweeper
re-runs never-started and queue-displaced work on a zero-steps-ran proof;
and a daily auditor judges what each workflow's last scheduled run PRODUCED,
each against its own cadence.

**Why**: every rule is a paid-for incident — 702k rows destroyed by a green
run, 24.2 hours of daily lock demand against a 24-hour day, 15 consecutive
runs whose work was computed and discarded at a timeout.

**How to apply**: start any new writer from
`docs/templates/split-writer-workflow-template.yml`; run
`tools/check_workflow_gates.py` after touching an apply job; enable the two
guardian workflows once the repo has scheduled work. The
`ci-fleet-engineering` skill fires on the triggers.

## 031 — A red X is reserved for broken
*Date: 2026-08-24 (from Archive Watch Decision 093)*

GitHub emails on failed runs, so a run fails ONLY when it has nothing to
show. A backstop timeout on a run whose work still published leaves a
`::warning::` via a verdict step; a legitimately-empty run is a printed
no-op; best-effort steps never `|| true` silently; and the health auditor
fails only for findings nothing else alerts (green-but-produced-nothing,
killed-with-publish-skipped) — a FAILED run already sent its own email.

**Why**: an alert channel that cries wolf daily is one the owner mutes, and
then a real break goes unread. The week this rule landed, ~12 failure emails
would have become zero, with every real failure still surfaced.

**How to apply**: the verdict-step shape is in the split-writer template.
Never widen the auditor's urgent set to a severity whose underlying event
already emails.

## 032 — The agent is never the tester: changes ship on external observation
*Date: 2026-08-24 (from Archive Watch builds 890–906 and the harness that ended them)*

A change to behavior that cannot be directly observed ships only on evidence
from an instrument that does not share the app's assumptions — screen
OCR of the actual glass, tap-audio metering, the re-downloaded published
artifact, the store's own console. Sixteen consecutive builds once
"verified" a fix on circular self-reports while the actual television kept
failing. Ship gates for playback-class features run on RELEASE builds
through a throttled network.

**Why + How to apply**: `docs/DEVICE-HARNESSES.md` (the per-platform harness
catalog and the instrument-honesty rules) and `docs/AUTONOMOUS-LOOPS.md`
(the loop discipline it anchors). The `device-observation-harness` skill
fires on the triggers. Instruments must say when they are blind, never
perturb what they measure, and identify their own configuration.

## 033 — DECISIONS.md stays context-sized: index + recent entries; archives are verbatim
*Date: 2026-08-24 (from Archive Watch Decision 092, at 95 entries / 262 KB)*

This file is loaded into every session's context. When it grows past
~120 KB, roll the oldest full entries VERBATIM into
`docs/decisions/DECISIONS-<range>.md` archives and keep a complete one-line
index here. **Amended 2026-09-30**: roll at ~50 KB, not 120; Archive Watch
lowered it after measuring that always-loaded files cost about 382 KB of
every session. Append-only binds everywhere: a whole-entry move is the only
permitted operation; never trim, edit, or summarize an entry in place.

**Why**: at 262 KB the decision log had become the largest fixed cost of
every session, crowding out the code being worked on — while its titles,
written as one-line summaries, already made a perfect index.

## 034 — Markers carry their source, their timestamp, and their evidence
*Date: 2026-08-24 (from Archive Watch Decisions 055/056/084/088)*

Any pipeline marker that records work done or facts checked follows three
rules: an "already attempted" marker records WHICH source attempted (a bare
boolean starves every later source); a "verified" marker records WHEN, with
a re-check TTL proportional to how visible the claim is; and a judgement
stores its MEASUREMENT beside the verdict, so downstream consumers can
abstain on weak evidence instead of acting on a coin-flip. Transient
failures (429/5xx) never mark; only definitive ones (404/410) do. A tool
that drops records users may reference leaves a forwarding address.

**Why**: each rule is a silent multi-week failure — a plateau that reported
"drained" in 94 seconds, dead links headlining a home screen with
`verified: true`, and a destructive merge acting on saturation readings that
were statistical coin-flips.

## 035 — Account deletion is a launch requirement, and the anonymous account is an account
*Date: 2026-08-24 (from Tidbits Trivia Decision 048 + the 2026-07-28 App Review rejections)*

Every platform that ships sign-in ships in-app account deletion in the same
release — and the deletion path must cover the ANONYMOUS account too. An
anonymous/guest identity that accumulates state (records, progress, an Elo)
IS an account in every store's review rubric, even though your UI never
called it one.

**Why**: Apple rejected a build for exactly this — the reviewer never signed
in, tapped Delete Account as an anonymous user, and the app had no path.
Both Apple and Play now require in-app deletion for any app with account
creation; retrofitting it under review pressure is the most expensive time
to build it.

**How to apply**: the Settings surface on every platform gets a Delete
Account row that works for BOTH signed-in and anonymous identities (wipe
local state + the backend record). Watch the backend semantics: a naive
"delete" that writes `null` into a shared tree can be a no-op or a
tombstone-clobber — verify the record is actually gone by reading it back.

## 036 — Bundled content is queried, never loaded: RAM is a shipping constraint
*Date: 2026-08-24 (from Tidbits Trivia Decision 049 + the vc75/vc85 Play rejections)*

A large bundled corpus (questions, cards, entries — anything in the tens of
MB as JSON) is accessed through a query layer (SQLite/FTS) or per-mode lazy
slices, never eagerly deserialized into the object heap at boot. Emulators
and dev phones hide this class entirely.

**Why**: Play rejected a release twice for an unreproducible-locally crash;
MEASUREMENT (not iteration) found a 299MB heap peak from eagerly decoding
the bundled corpus — and a later "fix" re-created it by building per-mode
shape sets at boot. The corpus grows with every content pass, so the failure
arrives silently in a release that changed no code.

**How to apply**: bundle a database, not a blob; open it memory-mapped and
query. If JSON is unavoidable, load per-mode/per-screen slices on demand and
measure the heap on the LOWEST-RAM device the stores will install to. Add a
CI check that fails when the eager-loaded bytes at boot exceed a budget.

## 037 — A generator's output is not the shipped artifact; re-running one must be additive
*Date: 2026-08-24 (from Tidbits Trivia Decision 051, the genguard + tombstones fix)*

When generated content is later hand-edited (authored fixes, curated
deletions), the generator's raw output becomes an INPUT to the shipped
artifact, not the artifact itself. Re-running a `gen_*.py` must merge over
authored changes and honor tombstones for authored deletions — a plain
regenerate silently reverts every hand fix and resurrects every removed row.

**Why**: authored quality fixes were silently reverted for weeks because a
generator rewrote its output file wholesale; nothing failed, the diff just
quietly undid human work.

**How to apply**: every generator writes through a merge guard: authored
rows win by key, deletions live in a tombstone list the generator respects,
and CI diffs regenerated output against the shipped artifact to catch a
guard bypass. Never let "regenerate" be a synonym for "overwrite".

## 038 — Randomness lives outside the selection pipeline
*Date: 2026-08-24 (from Tidbits Trivia Decision 052; companion to Decision 025)*

A shuffle INSIDE a selection pipeline (shuffle → filter → truncate) chooses
CONTENT, not presentation, the moment anything downstream truncates — and it
does so differently per platform and per run. Selection must be
deterministic end to end (hash-rank per Decision 025); randomness is applied
only to the final presentation of an already-chosen set (option order,
display shuffle), seeded where cross-platform agreement matters.

**Why**: a "random for variety" shuffle ahead of a truncation step meant
different platforms — and different runs — silently played different
content while every layer looked correct in isolation.

**How to apply**: audit any pipeline containing both a shuffle and a limit.
Move the shuffle after the cut, or replace it with hash-rank. Golden-test
the selected SET, not just the first item.

## 039 — Store billing APIs disagree in shape; port the intent, never the code
*Date: 2026-08-24 (from Tidbits Trivia Decision 055 + the Windows Club IAP build)*

Each store's billing API has a load-bearing shape of its own, and the shapes
are OPPOSITES: Play Billing requires one query PER product type (a mixed
INAPP+SUBS list throws — on the main thread, at startup, only on a real
Play-provisioned device), while the Microsoft Store requires ONE query for
everything (a subscription is a `Durable` add-on; filtering by a
"subscription" kind silently returns nothing). Harmonizing them into one
cross-platform abstraction ships a crash on one platform and an empty
paywall on the other.

**Why**: the mixed-list throw shipped two consecutive crashing Android
releases — invisible on emulators (no Play Billing) and in every local
test; the Windows kind-filter mistake produced an empty paywall with no
error anywhere. Both were "the other platform's pattern, applied here".

**How to apply**: the entitlement MODEL is shared (products, entitlement
state, fail-open gating); each platform's QUERY layer is written from that
store's own docs, verified on that store's real provisioning path (Firebase
Test Lab / the certified Store install), never translated from a sibling.
Verify configured product ids by reading them back from the store's own API.

## 040 — Local persistence must never block launch: open in do/catch, fall back to in-memory
*Date: 2026-08-24 (from Bsky Dreams, the SwiftData corrupt-store fix)*

The local store (SwiftData `ModelContainer`, Room database, IndexedDB
open) is created inside a failure handler; if the on-disk store fails to
open, the app falls back to an in-memory store and launches anyway.

**Why**: a corrupt or migration-incompatible store previously crashed the
app on every launch with no recovery path — the user's only fix was
delete-and-reinstall. One session without persistence is a nuisance; a
launch-blocking trap is a lost user. (Same family as the SwiftData
lightweight-migration trap: a property added to an existing model needs an
inline default at the declaration, or existing stores crash on open.)

**How to apply**: wrap container/DB creation in do/catch (or the platform
equivalent), fall back to in-memory, and let the next clean launch rebuild
the on-disk store. Surface degraded persistence to the user only if a
user-visible feature depends on it. Never let "the store is the app's
foundation" justify trapping on it.

## 041 — When the native project can't live at the repo root, a root workspace shim satisfies the CI host
*Date: 2026-08-24 (from Bsky Dreams, the Xcode Cloud onboarding fight)*

Decision 002 puts the Xcode project at the repo root. When a repo's
history makes that impossible (the root belongs to another platform and
the project is nested), do NOT move the project — add a **root
`.xcworkspace`** whose `FileRef` points at the nested `.xcodeproj`, and
target the workspace from CI.

**Why**: Xcode Cloud (and similar hosts) hard-require the
project/workspace at the repository root and silently revert a configured
subdirectory path. Relocating a live App Store project mixes platform
sources and churns every path; the workspace shim is three small files.

**How to apply**: (1) root `NameApp.xcworkspace` referencing the nested
project; (2) a **workspace-level shared scheme**
(`.xcworkspace/xcshareddata/xcschemes/`) copied from the project scheme
with container paths rewritten relative to the root — CI validates the
scheme at the workspace's shared-data path, not the project's; (3)
`ci_scripts/` beside the workspace (the repo root), because the CI host
only runs scripts beside whatever the workflow targets. Quote paths —
nested projects often carry spaces. Note per Decision 020 the GitHub-runner
pipeline remains the default; this shim is for whichever host imposes the
root requirement.

## 042 — Platform-free logic gets a sidecar SPM package so `swift test` runs without a simulator
*Date: 2026-08-24 (from Bsky Dreams, the gesture-router test package)*

Pure logic that a UI feature depends on (gesture routing math, ranking
functions, parsers) is extracted into a small standalone SwiftPM package
in the repo — `platforms: [.macOS(...)]`, no app-target dependency — with
its tests, runnable via bare `swift test`.

**Why**: logic embedded in the app target can only be tested through
xcodebuild + a booted simulator — slow enough that tests don't get run in
tight loops, and unavailable to CI shells without simulator setup. The
sidecar package gave a 43-test suite on the exact code that had burned 16
debugging iterations, at second-scale runtimes. It also forces the
platform seam: code in the package provably imports no UIKit/SwiftUI.

**How to apply**: when a bug-prone feature has a computable core, extract
that core into a repo-local SPM package (source + testTarget), have the
app target include the same source, and run `swift test` in the loop and
in CI. This complements Decision 032 — external observation still gates
UI behavior; the package gates the math.

## 043 — Algorithmic surfaces honor the user's own moderation and explain every ranked item
*Date: 2026-08-24 (from Bsky Dreams, the Discover feed rebuild)*

Any surface this template's apps rank algorithmically (feeds, discovery,
recommendations) must (a) apply the user's OWN existing moderation
settings — platform mutes/blocks, muted words, content-label
preferences — rather than an app-invented blocklist, (b) personalize only
from signals the user can see and change by acting in the app, and (c)
attach a one-line "why you're seeing this" reason to every ranked item.

**Why**: the first build merged globally engagement-ranked sources — every
account saw the same feed, global virality dominated, and the score
structurally rewarded rage-bait. Ranking is an editorial act; unexamined,
it optimizes for exactly what the "Why we build" note rejects. The
transparency chip is the enforcement mechanism: a signal whose reason
can't be stated in one chip is too opaque to use.

**How to apply**: run the `learning-orientation-design` four questions
against the ranking FUNCTION itself, not just the feature proposal; full
pattern (multi-source merge, conversation-weighted scoring, seen-item
bypass, flat-tabs IA) in `values-based-feed-ranking`.

---

## 044 — Every user-visible affordance must control something real
*Date: 2026-08-26 (from BOBA Playbook, the pricing time-window picker removal)*

A control that visually scopes a panel but actually filters an empty or
irrelevant data source is not a "no-op control," it's a trust-erosion
device — the user forms a wrong mental model from its apparent scope.

**Why**: a 7/30/90-day picker appeared to scope an entire pricing panel
but only set one query param on one signal — a signal that was
permanently empty. Worse, the three platforms sent different values for
that param, splitting the server cache so the same entity showed
different data per platform at the same moment. The picker's removal
fixed both the lie and the divergence.

**How to apply**: before shipping any picker/toggle/filter, name exactly
what it changes; if the honest answer is "one sub-signal" scope it
visually to that signal, and if the answer is "nothing real," remove it.
When platforms hit a shared cached endpoint, fix the parameters
server-side or normalize the cache key (`zero-cost-hosted-backend`).

---

## 045 — Feature gating: keep the code, gate the single UI entry point
*Date: 2026-08-26 (from BOBA Playbook)*

When a feature is built but blocked on an external dependency, keep all
implementation code in place and gate at ONE call site
(`if featureEnabled { … }`). Don't delete or hollow out working code
while waiting.

**Why**: building ahead of infrastructure is sometimes unavoidable.
Half-deleted code makes the feature harder to re-enable and the codebase
ambiguous about what works. A one-line gate makes re-enabling a one-line
diff and keeps the implementation compiling (so refactors can't silently
rot it).

**How to apply**: one flag, one entry point, a note in SCRATCHPAD's
deferred list naming the external blocker. The exception is a REVOKED
dependency — that's a removal, not a gate
(`third-party-revocation-resilience`).

---

## 046 — One canonical ID and one canonical asset per entity
*Date: 2026-08-26 (from BOBA Playbook's "One ID per Card, One Image per Card")*

Every entity in a shared catalog gets exactly one canonical identifier
(a composite-ID formula defined in ONE source per language, stored as a
real field, never recomputed at runtime) and exactly one canonical
asset, enforced at the byte layer by an md5-collision guard in the
pipeline.

**Why**: identity drift is the root of the worst catalog bug classes —
wrong-entity merges, duplicate rows, one entity silently wearing
another's image. Each is invisible until a user notices, and each is
enforced only where it can be measured: the ID at the catalog layer, the
asset at the binary layer.

**How to apply**: `canonical-entity-identity` carries the formula
rules, collision audits, and the lockstep migration protocol;
`image-cdn-discipline` carries the asset-side guard.

---

## 047 — Two backend postures: sync islands OR the hosted split — choose in M0
*Date: 2026-08-26 (reconciles 015; from BOBA Playbook)*

Decision 015's sync-islands posture (each ecosystem syncs on the user's
OWN cloud; no backend to run) is the default — but it only serves
per-user data. The moment users must see EACH OTHER'S data (public
profiles, shared collections, moderation, matching), the app takes the
hosted split instead: a hosted Postgres for auth + user data ONLY,
catalog as static published artifacts, media on a zero-egress CDN, and
small serverless workers for the seams. Never both for the same data.

**Why**: the two postures were sitting unreconciled in this log — 015
assumed no backend while 011's JWT-refresh rule assumed one. The real
rule is a fork on ONE question: is any user's data read by another user?
No → sync islands (zero infrastructure). Yes → the hosted split, kept
free-tier-viable by putting only genuinely shared state in the database.

**How to apply**: record the choice as an M0 decision.
`per-ecosystem-sync-islands` for the first path;
`zero-cost-hosted-backend` for the second (roles + RLS, worker fleet,
username/handle rules, account deletion).

---

## 048 — Next-OS APIs are adopted additively behind BOTH a runtime and a compile-time gate
*Date: 2026-08-26 (from BOBA Playbook, the iOS 27 adoption + the un-submittable build)*

While the deployment floor stays on OS N, every OS N+1 API is adopted
behind `if #available(OS N+1, *)` (runtime) wrapped in a compilation
condition that only exists when building against the N+1 SDK
(`OTHER_SWIFT_FLAGS[sdk=iphoneosN+1*] = -D OSNPLUS1_SDK`), with the OS-N
path in `#else` — and the gates live in ONE Compat wrapper file.

**Why**: `#available` alone still requires the symbol in the build SDK,
so the project silently compiles ONLY under beta Xcode — and App Store
Connect rejects every beta-Xcode build. The failure surfaces at submit
time, long after the build "worked" locally. The compile-time gate keeps
the GA toolchain shippable and the beta toolchain testable from the same
source. Never bump the floor as a shortcut, and never adopt an N+1 API
that regresses an existing affordance or has no real problem behind it.

**How to apply**: recipe in `cloud-appstore-submission` Rule 6. When the
floor rises to N+1, delete the flag and the `#else` branches, keep the
runtime `#available`.

---

## 049 — Marketplace-adjacent features never touch money
*Date: 2026-08-26 (from BOBA Playbook, TRADE-DESIGN.md)*

If the app introduces users who then trade/sell with each other, the
app processes, holds, escrows, or takes a cut of NOTHING. The
architecture is pure introduction: passive matching on explicit user
inputs, a deep link to an external messaging platform, block +
mailto-report + published contact for store compliance — and the app
steps out of the transaction entirely.

**Why**: the moment funds flow through the app, marketplace-facilitator
laws trigger (multi-state tax collection, 1099-K, money-transmitter
analysis, KYC/AML) — inoperable for a small team. Hosting user-to-user
messaging triggers per-message moderation obligations and creates an
archive of dispute evidence. Subscriptions via store IAP are NOT
touching money (you sell access to your features, not a cut of their
transactions).

**How to apply**: `marketplace-adjacent-design` + seed the binding doc
from `docs/templates/TRADE-DESIGN-template.md` BEFORE building any
trading surface. Kill any proposal with a Pay button, escrow, or
per-trade fee at proposal stage.

---

## 050 — Market data is provenance-honest, and the sold history is generated, not bought
*Date: 2026-08-26 (from BOBA Playbook, the pricing rebuild)*

Every price/valuation states what KIND of data it is; an asking price
or derived estimate is never presented as market value. When no sold
data exists, the honest label ("N active listings · no sales data yet")
IS the feature. When no API will sell you transaction history, snapshot
public active listings and infer sales from vanishings — after ~60 days
you own the history.

**Why**: asking prices run 10–25% above transacted; folding them into a
"market value" silently inflates every number, and a fabricated
"Market Est." teaches users to distrust the whole surface. The
structural insight: pipelines that depend on a third party for the
scarce data are broken by design — the durable asset is the history you
generate and own.

**How to apply**: `provenance-honest-market-data` — the signal
hierarchy, vanish-inference scoring, match-precision gates, the
audit-by-pattern discipline, and the UI rules.

---

## 051 — Every third-party data dependency is presumed revocable
*Date: 2026-08-26 (from BOBA Playbook, a partner's revocation email)*

Operate so that any single external data/image/API partner can revoke
authorization without killing the product: prefer data you generate or
that the community contributes, keep provenance per record, and design
the exit before the dependency is load-bearing.

**Why**: a partner who saw the app as a competitor revoked everything
by email — data, images, mappings, lookup logic, automation — leaving
one permitted use (an outbound link). The removal took a 24-tick
compliant teardown plus a multi-thousand-record provenance backfill.
The cost of independence is paid once; the cost of dependence recurs
with every partner's mood.

**How to apply**: `third-party-revocation-resilience` for both halves —
the prevention posture and the compliant-removal loop (prohibition list
first, replacement table before deletion, frozen legacy data vs live
automation, grep-verified end state). For the monetization side of IP
you don't own: `third-party-ip-monetization`.

---

## 052 — User-facing vocabulary is a render-layer contract over frozen schema names
*Date: 2026-08-26 (from BOBA Playbook, "Weapon" over `element`)*

Schema field names are frozen (renames are migrations); what users see
is a display-vocabulary mapping recorded in the data contract and
applied identically by every client. The community's own terms win over
schema language and over generic industry terms — including deliberate,
documented exceptions where one surface correctly uses a different
word.

**Why**: users learn and own their domain's vocabulary; leaking schema
language ("Element") or conflating two domain concepts under one
borrowed term ("Rarity") robs them of it and makes every platform
translate differently. The mapping table makes the vocabulary
enforceable in review instead of tribal.

**How to apply**: fill the Display Vocabulary section of
`docs/DATA-CONTRACT.md` (template §5.5); reject PRs that render a
schema name the mapping translates.

---

## 053: The look has one source, and every platform's tokens are generated from it
*Date: 2026-10-03*

`design-tokens.json` at the repository root holds the palette (light and
dark), the type ramp, spacing, and radius. `tools/design_tokens.mjs`
writes every platform's token file from it, and
`tools/test_design_tokens.mjs` fails when any of them differs from a
fresh run or a text pair falls below WCAG AA.

**Why**: the lockstep rule was a sentence, and the starter's own
placeholders broke it: the web was white with a blue accent, Android was
dark navy with an orange primary, Windows pinned orange, Apple's
AccentColor was blue, and each type ramp had different sizes. A student
whose agent changed the look in one file would see it on one platform
only. A rule that a test holds cannot drift that way.

**How to apply**: change the look in `design-tokens.json`, run the
generator, run the test, then build and look at every platform. Never
hand-edit a generated file or a `BEGIN design-tokens` block. Each
platform still maps tokens into its own idiom by hand (Android's
`Theme.kt` slots, Windows control styles, Apple views), and Apple keeps
system text styles for Dynamic Type. A deleted platform folder is
skipped, not recreated.
