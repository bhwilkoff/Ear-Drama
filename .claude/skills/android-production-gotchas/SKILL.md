---
name: android-production-gotchas
description: "Use FIRST when building or debugging the Android (Kotlin + Compose + M3) app: production lessons from shipping Compose apps to Google Play that the framework docs don't carry. Data-layer invalidation keying (dbVersion on every produceState), BundledSQLiteDriver for FTS5, the atomic DB swap, the contradictory-WHERE silent-empty class, sealed routes with a deep-link inbox, SF Symbol to Material icon parity, Media3 queue flags, state-from-prop remember trap, ViewModel reset on auth change, native debug symbols in the AAB, ML Kit bundling, device verification. Triggers on Compose, Room, FTS5, produceState, LaunchedEffect key, BackHandler, deep link, assembleDebug, Media3, empty grid, zero items, Play build, debug symbols, ML Kit."
---

# Android Production Gotchas

Cross-cutting lessons from shipping a Kotlin + Compose + Material 3
app to Google Play in parallel with iOS/tvOS/web siblings. The
Android skill stack (install via `tools/install-android-skills.sh`)
carries framework depth; this skill carries the **bugs and rituals
that cost real sessions** on a production parity build.

## Data layer

- **Key every screen's query on a data version.** Screens holding
  query results key their `produceState`/`LaunchedEffect` on a
  `dbVersion` counter (and a `userState.changes` counter where user
  records matter) that bumps on every data swap or filter change.
  Without it, the seed→full-database swap (or a settings toggle)
  silently doesn't propagate — screens show stale data until
  recreated.
- **BundledSQLiteDriver, not framework SQLite**, when you need FTS5
  or schema guarantees — the OS-provided SQLite version varies by
  device/API level; the bundled driver makes search work everywhere.
- **The staged atomic swap ritual** for downloaded databases:
  ETag-conditional GET → stream-inflate (`Inflater(nowrap = true)`
  for raw DEFLATE, 64 KB chunks) to a STAGING file → size floor →
  open-probe a known row → atomic rename → store ETag → bump
  `dbVersion`. Any failure keeps the cached DB; the bundled seed is
  the floor state.
- **Decode only the rows a screen shows** — query on disk; never
  materialize a large catalog into memory.
- One read path: a single `CatalogDatabase`/repository layer owns
  ALL data SQL and applies the universal filter clauses (visibility,
  maturity) in ONE place. Screens never touch SQLite, OkHttp, or
  asset files directly.
- **The shared `OkHttpClient` MUST set a real `User-Agent`.** Many
  image/CDN hosts (e.g. archive.org) rate-limit or block UA-less
  request bursts — without it a Coil image grid gets 403/429/reset
  and falls back to placeholders ("posters not loading"), while the
  data refresh may look fine. Use ONE shared client (with the UA
  interceptor) for BOTH Coil (images) and data refresh, so the
  header can't be set in one path and forgotten in the other.

## The contradictory-WHERE bug class

A query builder that unconditionally excludes a type AND a filter
that requires that same type compose into `WHERE type != 'x' AND
type = 'x'` → **0 rows, no error**. On a real app this made an
entire category invisible on two platforms for weeks (the
count-gate then hid the dead tile, masking it further).

Defenses: when a filter explicitly requests an excluded-by-default
type, the request wins (an explicit branch); **verify category
counts with direct SQL** against the live DB whenever a surface
looks inexplicably empty; treat "shows zero items" as a query bug
until proven otherwise.

## Navigation + entry points

- v1: **manual DI (`AppContainer` in `Application`) + a sealed
  `Route` back stack + `BackHandler`** — Hilt/Navigation3 arrive
  when module count or route complexity demands them, not before.
- Every pushable destination is a case of the sealed `Route`,
  handled in one `AppRoot` — never per-screen ad-hoc overlays.
- **Deep links land in a pending-inbox** (`DeepLinks.pendingItem`),
  parsed in `MainActivity` (`onCreate` + `onNewIntent`), consumed
  ONCE by `AppRoot` — never push routes from outside the
  composition.
- **Audit the manifest against every URL the app emits.** A share
  link or App Link path not declared in an intent-filter fails
  silently for external opens while in-app navigation works. Route
  every declared path to the RIGHT screen — a `/series/{slug}` link
  landing on a generic detail screen reads as "broken app." Test:
  `adb shell am start -a android.intent.action.VIEW -d <url>`.
- Tab taps clear the back stack; system back pops it.
- **Nav state survives process death only with `rememberSaveable`.**
  A plain `remember` loses the current tab + back stack on a
  low-memory kill, dumping the user back to Home when they return.
  Persist a serialized route stack via `rememberSaveable` (custom
  `Saver` for the sealed `Route`) — but do NOT restore a mid-playback
  player route (relaunching straight into a player on resume is
  jarring and may hit a torn-down media session).
- **Predictive back** needs
  `android:enableOnBackInvokedCallback="true"` on `<application>` to
  get the Android 14+ system back animation; without it the modern
  back gesture falls back to the legacy non-animated pop.

## Parity-port specifics

- **Icon parity = Material twins, not copied glyphs.** Map each SF
  Symbol to its closest Material Symbols equivalent
  (theater/mood/bolt/nightlight/landscape/science/brush/newspaper…)
  — same meaning, native family.
- Deterministic shared logic (schedulers, shuffles) ports with
  identical constants — same hash (FNV-1a), same mixer (SplitMix64),
  same local-time anchors — then verify agreement with the other
  platforms on a fixed seed.
- Proportional/timeline layouts (EPG-style) = Compose custom
  `Layout` placing children by minute-offset × px-per-minute, with
  `stickyHeader` for the ruler — don't fake it with weighted rows.
- Media3 queue playback: per-item position persistence; queue
  playback that shouldn't pollute resume state carries an explicit
  `persistProgress=false`-style flag on the play spec.
- Lock-screen/media-key controls = Media3 `MediaSession` from day
  one (a parity row, not polish).
- **Media3 `PlayerView` only draws its fullscreen button when you
  register `setFullscreenButtonClickListener`.** Wire it to toggle
  `SCREEN_ORIENTATION_SENSOR_LANDSCAPE` + immersive system bars
  (`WindowInsetsControllerCompat`), and RESTORE both on dispose — the
  player is a pushed route inside the single Activity, so leaving it
  landscape/immersive leaks that state into the rest of the app.
- **Activity Picture-in-Picture**: `android:supportsPictureInPicture`
  on the Activity + `onUserLeaveHint → enterPictureInPictureMode(params)`
  sized to the REAL video aspect (feed the aspect from a
  `Player.VideoSize` listener), gated by a presence flag so PiP only
  fires during playback (never from a browse screen).

## Compose state traps

- **`var x by remember { mutableStateOf(prop.field) }` captures the
  prop ONCE** and ignores every later prop change — the classic
  edit-sheet-shows-stale-values bug. Bind directly to the prop, or
  key the remember: `remember(prop.field) { … }`.
- **ViewModels caching per-user state must wipe their cache when
  `authState.userId` transitions.** Hilt-scoped VMs outlive sign-out;
  without the reset, the previous user's data leaks into the next
  session. Observe the userId and clear on change.
- **`"%.2f".format(x)` honors the device locale** — a USD price
  renders `1,99` on a German device. All fixed-currency displays go
  through one helper pinned to the currency's locale
  (`String.format(Locale.US, …)`).
- **Centroid-aware `rememberTransformableState` lambda parameter
  order is `(centroid, zoom, pan, rotation)`** — centroid FIRST;
  the wrong order compiles (positional aliases) and breaks at use.

- **Lazy keys must be UNIQUE, not merely stable.** A key built from a
  display field (a file name, a title) collides the day two rows share it
  and crashes with `Key "…" was already used`. Archive Watch's TV copy
  picker did, read from Play's own stack trace. Key by a stable id, and
  dedupe the list before it reaches the container.

## Release engineering: native debug symbols + ML Kit

- **Embed native debug symbols IN the AAB; don't upload a zip.**
  Play's "missing debug symbols" warning fires when dependencies ship
  pre-stripped `.so` files (ML Kit, other Google libs) so AGP's
  symbol task produces nothing. The standalone
  `native-debug-symbols.zip` can only be ingested via the Play
  Developer API (`edits.deobfuscationfiles.upload`), which some
  accounts can't reach, and the manual UI upload doesn't reliably
  take. Fix: a Gradle task (`finalizedBy bundleRelease`) injects each
  `.so` as
  `BUNDLE-METADATA/com.android.tools.build.debugsymbols/<abi>/<lib>.so.dbg`
  (path + `.dbg` suffix per AGP's `ExtractNativeDebugMetadataTask`)
  and re-signs with the upload key (`jarsigner`). BuildID-only
  stripped symbols are accepted.
- **When injecting, use `zip -D`** — AABs forbid directory zip
  entries, and Play reports the violation as a misleading "invalid
  signature" rejection. Verify with `bundletool validate`.
- **ML Kit: prefer the unbundled (Play-Services) artifact** over
  bundled — the bundled `.so` ships pre-stripped (triggers the
  debug-symbols warning), adds ~11 MB to the AAB, and its "works
  offline" advantage is illusory (install requires being online
  either way). Unbundled needs manifest meta-data
  (`com.google.mlkit.vision.DEPENDENCIES`) for install-time model
  download; the API surface is identical.

## Theme + surfaces

- Brand theme default; **dynamic color is opt-in, never the
  default** when the product has a strong canvas (a cinema app is
  not a settings app).
- M3 typography styles only, six hierarchy levels, refuse a seventh.
- Tiles: image + two text lines, nothing else; stable `key`s on
  every Lazy container; explicit empty-state sentences
  (`universal-feature-states`).
- **Edge-to-edge insets via `statusBarsPadding()` /
  `windowInsetsPadding(...)`, NEVER a magic `padding(top = N.dp)`.**
  A hardcoded top pad mis-sits on tall status bars, notches, and
  display cutouts — the system inset is the only value that's right
  on every device.
- **Image composables must fail to a DESIGNED placeholder on
  `onError`** — a gradient / monogram / title-card, never a blank
  box. Track a failed state keyed on the URL so a retry with a new
  URL re-attempts. (An empty tile reads as "broken app"; a designed
  fallback reads as "no art yet.")
- **The Cast chooser needs an AppCompat `colorPrimary`.** mediarouter's
  dialog crashes on Android 11 and 12 ("background can not be translucent:
  #0") when the activity theme does not set it. A Material 3-only theme is
  not enough.
- **RTL**: use `Icons.AutoMirrored.*` for directional (back/forward)
  arrows when `supportsRtl="true"` — a non-mirrored back arrow points
  the wrong way in RTL locales.

## Crash triage from the store

- Read crash clusters with their full stack traces from Play's Reporting
  API before guessing (`store-metrics-pipelines`), filtered to the build
  that is live.
- A cluster credited as fixed that recurs on the fixing build comes OUT of
  `ops/fixed-in.json`; and the entry names the versionCode CI actually
  assigned (a refused upload once shifted 67 to 68).
- TV ANRs on budget GPUs (Mali): Perfetto-trace the store build on the
  device before you "fix" one by guesswork.

## Verification recipes

- `./gradlew :app:assembleDebug` is the gate; emulator-verify
  user-facing claims (a green build is not a working feature).
- Boot ONE emulator at a time, and never alongside an iOS simulator
  — parallel boots wedge both.
- Screenshots: SystemUI demo mode for a clean status bar; drive
  screens via deep links (`adb shell am start -d appname://…`);
  screenshot IDs must come from LIVE data, not stale seeds.
- Release signing: keystore in `~/keystores/`, creds in
  `~/.gradle/gradle.properties`, NEVER in git; verify the AAB's
  signer fingerprint against assetlinks before upload. Play-specific
  process in `store-submission-playbook`.
- `versionName` stays in lockstep with the iOS marketing version;
  bump `versionCode` every ship.
