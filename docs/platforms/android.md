# The Android app

Read this before any Kotlin or Compose work, and before choosing or
changing `minSdk`.

These rules lived in `AGENTS.md` until October 3, 2026, when it was cut
below 24,000 bytes so that Antigravity, which stops reading a rule file
at that size, would read all of it. They moved here word for word, and
`AGENTS.md` links to this page with one line saying when to read it. The
rules that hold on every platform stayed in `AGENTS.md`.

## Which skill

- **Android**: `android-production-gotchas` FIRST (data-version
  keying, the contradictory-WHERE empty-grid class, deep-link inbox,
  swap ritual). For framework depth, install the Android skill stack
  into `~/.claude/` (`tools/install-android-skills.sh`), then
  `chrisbanes:<name>`, `rcosteira79:<name>`, etc.

For Android TV and Fire TV, read [tv.md](tv.md) as well.

## Android app

**Stack**: Kotlin 2.4.20 (AGP 9.4.1, Gradle 9.8.0, compileSdk 37) +
Jetpack Compose + Material 3 / **Material 3 Expressive**. `minSdk = 29`
(Android 10) in the scaffold, `targetSdk = 36` (Android 16). Lower it by
measurement, not by default: Archive Watch runs at `minSdk = 23` on
every store (and Fire TV needs 28 or lower), which took `lint NewApi`
clean at the floor and bundled Let's Encrypt roots (Android 6 and 7
don't trust them). Newer features gate on `SDK_INT`. Hilt + Ktor +
Coil 3 + Navigation 3 + Room + DataStore. No XML, no AppCompat, no
legacy ActionBar: **Compose-only**. The scaffold builds out of the box:
`cd android && ./gradlew :app:assembleDebug`.

**Project structure**:

```
android/
├── settings.gradle.kts, build.gradle.kts, gradle.properties
├── gradle/libs.versions.toml             ← version catalog (single source of truth)
├── app/                                  ← composition root (single-module bootstrap)
│   ├── build.gradle.kts
│   ├── proguard-rules.pro
│   └── src/main/
│       ├── AndroidManifest.xml
│       ├── java/com/example/appname/    ← rename to your reverse-DNS package
│       │   ├── MainActivity.kt
│       │   ├── app/AppNameApplication.kt
│       │   ├── navigation/LaunchDoors.kt
│       │   ├── ui/AppRoot.kt
│       │   ├── ui/theme/{Theme.kt, Color.kt, Type.kt}
│       │   └── data/ApiClient.kt
│       └── res/
└── scripts/sync_shared_assets.sh         ← mirror /assets/ → app/src/main/assets/
```

**Critical conventions** (the load-bearing ones; ANDROID-DESIGN.md,
once you create it, and the Android skill stack carry the depth):

- **Material Components first.** Exhaust M3 / M3 Expressive before
  any custom Composable. `SearchBar` before custom search;
  `ModalBottomSheet` before custom drag-from-bottom;
  `NavigationSuiteScaffold` before a hand-rolled width-class switch;
  `SharedTransitionLayout` + `sharedBounds` before a custom hero
  zoom.
- **Single Activity + Compose Navigation.** One `MainActivity`,
  hosts a `NavHost`, no Fragments.
- **UDF / state hoisting**: immutable `data class UiState` per
  screen; sealed-interface `Event`s; ViewModel injected at screen
  Composable only; pass `uiState` + `onEvent` lambda down.
- **All network calls through a shared Ktor client (Hilt
  singleton).** Composables / ViewModels never use `HttpClient`
  or `OkHttpClient` directly.
- **Every Worker / Storage / Edge Function call calls
  `refreshIfNeeded()` first**: same rule as iOS, via an OkHttp
  interceptor on the shared client.
- **Stable keys on every `LazyColumn` / `LazyVerticalGrid`**,
  non-negotiable for large lists.
- **Tink-encrypted DataStore for secrets**, never
  SharedPreferences. EncryptedSharedPreferences is deprecated.
- **`edge-to-edge` mandatory** at `targetSdk >= 35`. Honor
  `WindowInsets` via `Scaffold`.
- **Predictive back gesture** must work. `BackHandler` only for
  unsaved-changes confirmation.
- **Adaptive layouts via `currentWindowAdaptiveInfo()`**: every
  screen declares compact / medium / expanded behavior.
- **Brand theme by default; dynamic color opt-in.**
- **Version bump on every ship.** `versionName` is read from
  `AppVersion.xcconfig` (the same number as every Apple platform;
  `tools/test_version_contract.py` holds it). Only `versionCode` is
  bumped in `app/build.gradle.kts`.
- **Media playback = Media3/ExoPlayer + MediaSession** from day
  one. Lock-screen controls are a parity row, not a polish item.
- **Release signing**: upload keystore lives in `~/keystores/`,
  credentials in `~/.gradle/gradle.properties`, NEVER in git.
- **Declare EVERY deep-link host/path you emit.** A share link or
  App Link route that isn't in the manifest's intent-filter fails
  silently for external opens. Audit the manifest whenever a new
  URL shape ships.
