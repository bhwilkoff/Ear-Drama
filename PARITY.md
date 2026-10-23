# Ear Drama: Cross-Platform Feature Parity

> **Single source of truth** for what's shipping where. Updated in
> the SAME change set as any user-facing feature.
>
> Companion to `AGENTS.md` (project context), `SCRATCHPAD.md` (active
> milestone), `DECISIONS.md` (architecture decisions). Per-platform
> design rules live in `iOS-DESIGN.md` (iOS), `macOS-DESIGN.md` (macOS),
> `tvOS-DESIGN.md` (tvOS), `WEB-DESIGN.md` (web), `ANDROID-DESIGN.md`
> (Android) when those binding docs exist. The full workflow
> (including the periodic parity audit) is the
> `cross-platform-parity-discipline` skill.

Base platforms: **web · iOS/iPadOS · macOS · tvOS · Android.** The three
Apple platforms (iOS · macOS · tvOS) are adjacent in every table because
they share one Swift Core. A Core change usually moves all three columns
at once, so verify each still builds.

Extended surfaces, added as COLUMNS when adopted (each is a form factor
of an existing build, not a new codebase; see Decision 028): **Android TV /
Fire TV** (the Android app's TV form factor) and **Web-TV** (webOS /
Tizen / Cast, the web app's additive TV layer). **Windows** (Decision
029) is an optional sixth full platform with its own column and its own
authoritative parity doc (`docs/windows/` pattern: a WINDOWS-PARITY.md
mirroring this file's rows). A feature that ships on phone/desktop but
not its TV form factor gets ⏳ with a reason, never silence. The
recurring audit finding is parity that lands on new platforms without
returning to the platform it started on.

> **Last audit: 2026-10-22 (loop tick 30)**: sections 4 to 13 still held
> the template's sample rows, and 38 cells claimed ✅ for things Ear Drama
> never built (sign-in, account deletion, share links, Liquid Glass, an
> installable PWA, Mac player-as-window). Rewritten from the code: nothing
> has shipped to a store or the live site with data yet, so no cell reads ✅;
> built-but-unplayed work reads 🚧.

---

## 0. Platform set

**1.0 is the core five at one feature set** (Decision 056): web, iOS/iPadOS,
macOS, tvOS, and Android. The **web leads**: it is the landing twin for every
share link and the fastest to see, and the natives mirror it. tvOS earns its
place because listening is lean-back; macOS shares the Apple Core.

**Stubs at 1.0, built out after the core five** (Decision 056): CarPlay,
Android Auto, Android TV / Fire TV, Roku, webOS / Tizen, watchOS, and Wear OS.
Each is a target that builds and launches, ⏳ in every row until then.
Windows is 🔮: not in the owner's set for 1.0.

---

## Legend

- ✅ **Shipped**: live in production on this platform
- 🚧 **In progress**: being built; some parts may already be in main
- ⏳ **Planned**: committed; targeted for an upcoming milestone
- 🔮 **Future**: agreed direction; no timeline yet
- 🚫 **Out of scope**: explicitly not built on this platform (with reason)
- n/a: platform-inapplicable (e.g., lock-screen controls on tvOS)

n/a and 🚫 are different claims. n/a means the verb does not apply to
this platform at all. 🚫 means it could apply and we chose not to build
it, and the Notes say why.

A ⏳ or 🚫 cell carries its reason in Notes. "Deliberately deferred,
because X" is a healthy cell; a silent blank is drift.

---

## Parity rule

When shipping any user-facing feature:

1. **Confirm the verb is identical across platforms.**
   Find = explore, Profile = identify, etc. Don't let one platform
   own a different verb for the same surface.
2. **Pick the native idiom per platform**: `<dialog showModal>` on
   web, `.sheet` on iOS, `NavigationSplitView` + AppKit on macOS,
   focus-driven full-screen on tvOS, `ModalBottomSheet` on Android.
   *Same verb, native idiom.* An inversion of another platform's rule
   (e.g. `.buttonStyle(.plain)` is wrong on tvOS but correct on
   iOS/macOS) is deliberate. Never harmonize it away.
3. **Update this table** in the SAME PR. Drift here is what causes
   "the web has X but iOS doesn't" complaints six months later.
4. **Cross-link to the binding design doc** for each platform that
   has one.

---

## 1. Top-level navigation

| Verb | Web | iOS | macOS | tvOS | Android | Notes |
|---|---|---|---|---|---|---|
| Listen (Continue, Tonight in 19xx, shelves by rule) | 🚧 Continue, Following, This Day, shelves; no Tonight yet | 🚧 no Tonight | 🚧 no Tonight | 🚧 no Tonight | 🚧 This Day, genre shelves; no Tonight | Decision 058; R13 lists from data |
| Series (genre, network, decade, kind; runs, seasons, episodes) | 🚧 seasons as a scope, oldest first | 🚧 | 🚧 | 🚧 | 🚧 seasons, oldest first | Broadcast seasons (058); oldest first (R1) |
| Radio (evenings and genre channels on one clock) | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | Gaps stated, never filled (R9) |
| Search (titles, people, transcript text, dates) | 🚧 word-prefix titles and people; no transcripts yet | 🚧 FTS5 word-prefix | 🚧 FTS5 word-prefix | 🚧 FTS5 word-prefix | 🚧 FTS5 word-prefix | |
| Library (followed series, queue, downloads, history) | 🚧 device-local; no downloads | 🚧 no downloads | 🚧 no downloads | 🚧 | 🚧 no downloads | Device-local until sync (M5) |
| Plays (record a radio or stage play together) | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | Decision 059; TVs play back only |

---

## 2. Listening

| Feature | Web | iOS | macOS | tvOS | Android | Notes |
|---|---|---|---|---|---|---|
| Episode detail (date, network, sponsor, cast, versions, rights line) | 🚧 no sponsor yet | 🚧 | 🚧 | 🚧 | 🚧 no sponsor | Unclaimed reads "no claim known; removed on request", never public domain |
| Player: background play, system controls, speed, skip | 🚧 Media Session | 🚧 Now Playing, remote commands | 🚧 Controls menu, keyboard | 🚧 full-screen Now Playing | 🚧 Media3 session | iPhone web cannot be relied on for background audio |
| Sleep timer: "end of this episode" first, fades (R20) | 🚧 fade ignored by iPhone Safari (pauses) | 🚧 | 🚧 | 🚧 | 🚧 | |
| Serials stop at the end of an arc (R3) | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | |
| Commercials chaptered, never skipped (R8) | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | |
| Loudness gain applied at playback | 🚧 -21 LUFS by cutting; unmeasured at unity | 🚧 AVPlayer volume | 🚧 | 🚧 | 🚧 ExoPlayer volume, per queued item | Gain from the pipeline; never re-encoded |
| Versions picker; domestic copy by default | 🚧 | 🚧 | 🚧 | 🚧 | 🚧 | catalog Decision 007 |
| Transcripts, labeled automatic | 🚧 closed section, fetched on open | 🚧 sheet, from Detail and the player | 🚧 window, ⌥⌘T | 🚧 focus-scrolling reader | 🚧 route from Detail and the player | Shown only above the measured quality gate (058) |
| Downloads | ⏳ | 🚧 background session; remove, remove all | 🚧 same, Library section | n/a | 🚧 WorkManager, same store | tvOS has no durable storage for media |
| Listen Together | ⏳ | ⏳ SharePlay | ⏳ SharePlay | ⏳ SharePlay | ⏳ | Worker rooms on web and Android |
| Credits, privacy, and take-down pages | 🚧 /credits/, /privacy/, /takedown/; owner placeholders | ⏳ link to the web pages | ⏳ | ⏳ | ⏳ | One set of pages; apps link to them |
| Works offline (what was already loaded) | 🚧 service worker; network-first data, cached shell | ⏳ | ⏳ | n/a | ⏳ | Audio downloads are their own row |

---

## 3. Making plays

| Feature | Web | iOS | macOS | tvOS | Android | Notes |
|---|---|---|---|---|---|---|
| Pass the phone: record role by role on one device | ⏳ | ⏳ | ⏳ | n/a | ⏳ | Web with headphones only; live stand-in voices never stored |
| Invite-link productions | ⏳ | ⏳ | ⏳ | n/a | ⏳ | Sign-in required; report, block, filter |
| Teacher classes (consent for under-13s) | ⏳ | ⏳ | ⏳ | n/a | ⏳ | Behind the privacy policy that covers school consent |
| Play back a finished play | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | |

---

## 3b. Teaching surfaces

Teaching is a parity domain with DELIBERATE asymmetry. Track it so
a future session doesn't "harmonize" a rejection into a port (see
`universal-feature-states`).

| Surface | Web | iOS | macOS | tvOS | Android | Notes |
|---|---|---|---|---|---|---|
| EmptyState (productive next action) | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | Required everywhere from the first list/grid |
| ErrorBanner / OfflinePill | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | Required everywhere |
| HintBanner (one-shot tip) | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | Persisted dismissals + a global reset in Settings |
| Multi-step anchored walkthroughs | 🚫 | ⏳ | 🚫 | 🚫 | 🚫 | iOS-only where its idioms are novel; other platforms use EmptyState + hints + a `?` explainer. Record the rejection in each platform's design doc |

---

## 3c. Stubs (Decision 056)

A stub builds in CI and opens to its first screen; it grows from the core's
shared code only after the core five are complete.

| Platform | State | First screen | Notes |
|---|---|---|---|
| CarPlay | 🚧 builds | Continue, Radio, Series, Downloads tabs (R17); Continue plays | Runs only once Apple grants the carplay-audio entitlement (Needs Ben) |
| watchOS | 🚧 builds | Continue, "Waiting on the phone" | watchOS 11 floor (pairs with iOS 18); not embedded in the phone app yet |
| Android Auto | 🚧 builds | Continue, Radio, Series, Downloads (R17); Continue plays through the phone's queue | Every release with car support waits on Google's car review: internal or closed track only; Assistant voice (VC-1) not done |
| Android TV / Fire TV | 🚧 builds | Listen, D-pad focus on the first row; Now Playing card in the background (TV-NP) | Banner art is a placeholder for the owner |
| Wear OS | 🚧 builds | Continue, "Waiting on the phone" | minSdk 30 (Wear OS 3); needs its own versionCode before upload |
| webOS / Tizen | ⏳ | | M9, in progress |
| Roku | ⏳ | | M9, in progress |

---

## 4. Accounts (Decision 057)

Signing in is optional: every listening verb works signed out. It syncs
history, queue, and follows, and it is required to make a play with others.

| Feature | Web | iOS | macOS | tvOS | Android | Notes |
|---|---|---|---|---|---|---|
| Sign in with Apple | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | M5; verified at the Worker |
| Sign in with Google | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | M5; tvOS by a phone hand-off |
| Email and password | 🚫 | 🚫 | 🚫 | 🚫 | 🚫 | Decision 057 names Apple and Google only |
| Sync of history, queue, follows | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | One store on the Worker + D1, never two |
| Account deletion | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | Ships with sign-in (Decision 035) |

---

## 5. Links

| Feature | Web | iOS | macOS | tvOS | Android | Notes |
|---|---|---|---|---|---|---|
| Routes for series, episode, search | 🚧 + 404 forwarder | ⏳ | ⏳ | ⏳ | ⏳ | DEEP_LINKS.md |
| Universal Links / App Links | n/a | ⏳ | ⏳ | n/a | ⏳ | Wait on the App Store record and Play's signing fingerprint |
| `eardrama://` scheme | n/a | ⏳ | ⏳ | ⏳ | ⏳ | OAuth callbacks and Top Shelf |
| Share an episode | 🚧 Web Share | ⏳ | ⏳ | ⏳ QR code | ⏳ | The web page is every share's landing twin |
| Archive Watch film cross-links | 🚫 | 🚫 | 🚫 | 🚫 | 🚫 | Out of 1.0 (Decision 058) |

---

## 6. Not in 1.0

| Feature | Why |
|---|---|
| Push notifications | Nothing in 1.0 needs to reach a listener outside the app |
| Payments, subscriptions, in-app purchase | Free, no ads (AGENTS.md); no paid tier |

---

## 7. Oldest hardware served

| Web | iOS | macOS | tvOS | Android | Notes |
|---|---|---|---|---|---|
| Evergreen browsers | iOS 18 (iPhone XS / XR) | macOS 26 | tvOS 26 (Apple TV HD) | minSdk 29 (Android 10) | project.yml and android/app/build.gradle.kts; tools/test_ios_floor.py and test_tvos_floor.py hold the Apple floors |

---

## 8. The shared data plane

Every client is a consumer only (`shared-data-plane-contract`); the
contract is `docs/CATALOG-CONTRACT.md`.

| Asset | Purpose | Where | Consumed by |
|---|---|---|---|
| `ear-drama.sqlite.zz` + `manifest.json` | the served projection, queried on disk | Release `catalog-latest` | iOS, macOS, tvOS, Android (validate, then swap) |
| `ear-drama-seed.sqlite` | first launch offline (clean only) | bundled at build time from `catalog/out/publish-clean` | iOS, macOS, tvOS, Android |
| `/data/` (index, series, shards, days) | the web projection | GitHub Pages, deployed by `catalog-publish.yml` | web |
| `loudness-latest` | loudness measurements | Release asset, `catalog-loudness.yml` | the projection build only |
| Worker + D1 | accounts, sync, shared plays | ⏳ M5 | every client |

---

## 9. Web-specific affordances

| Feature | Web | Why |
|---|---|---|
| URL reflects the view | 🚧 | Shareable links; native apps keep state in memory |
| Web Share with a copy fallback | 🚧 | Native apps use the system share sheet |
| Offline shell (service worker) | 🚧 | Network-first data, cached shell; audio downloads are the apps' |

---

## 10. iOS-specific affordances

| Feature | iOS | Why |
|---|---|---|
| System tab bar (Liquid Glass on iOS 26) | 🚧 | The floor is iOS 18, so the system draws what each version has |
| Lock Screen and Control Center controls | 🚧 | Now Playing and remote commands; device check pending |
| Live Activities, widgets | 🔮 | After 1.0 |

---

## 11. macOS-specific affordances

macOS is a pointer, keyboard, menu bar, resizable-window app, never the
iOS app resized (`macos-platform-patterns`).

| Feature | macOS | Why |
|---|---|---|
| Controls menu with keyboard equivalents | 🚧 | Play/Pause, skip, speed, sleep timer, Download Episode |
| `NavigationSplitView` sidebar and detail | 🚧 | iOS uses tabs, tvOS a focus sidebar |
| A transport bar along the window's bottom | 🚧 | Audio has no picture, so the player never replaces the window |

---

## 12. tvOS-specific affordances

| Feature | tvOS | Why |
|---|---|---|
| Focus-driven layout, Play focused on Detail | 🚧 | The ten-foot constraint (`tvos-platform-patterns`) |
| Full-screen Now Playing | 🚧 | Typographic, no artwork required |
| Top Shelf | ⏳ | The listener's Continue items |
| Layered parallax icon | ⏳ | Waits on the palette pick and the icon (M0) |

---

## 13. Android-specific affordances

| Feature | Android | Why |
|---|---|---|
| Predictive back | 🚧 enabled in the manifest | iOS swipe-back is fixed-animation |
| Media3 notification and lock-screen controls | 🚧 | The MediaSession service |
| Adaptive icon with a monochrome layer | ⏳ | Waits on the icon (M0) |
| Android Auto library tree | ⏳ | M9 stub |

---

## Maintenance protocol

When you ship a feature:

1. Find the row in this table. Add new rows under the right section
   if needed.
2. Update each platform's status with one of the legend symbols.
3. Link to the relevant section of the platform's binding design doc.
4. Note any platform-specific deltas in the Notes column.
5. A shared-Core change usually moves all THREE Apple columns (iOS ·
   macOS · tvOS). Verify each still builds before you tick them.

When a feature ships on one platform but is meaningfully different
elsewhere, add an entry to §9 / §10 / §11 / §12 / §13.

When a platform explicitly rejects a feature, add an "Out of scope"
row in the relevant design doc and link from this table.

Keep the matrix readable, or it stops being true:

- **A cell is one sentence plus a link.** Put the evidence in the cell
  ("✅ verified on iPhone 12, YYYY-MM-DD"). Put the story in the ledger,
  design doc or DECISIONS entry the cell links to. A matrix that
  becomes a journal stops being read.
- **Name the parity test** in Notes for every row a mechanical guard
  enforces (for example `tools/test_<rule>_parity.py`).
- **One summary row per ported platform** (§7d). Never keep a second
  per-surface copy here once the port has its own ledger.
- **Scripts read columns by header name.** `line.split("|")` returns a
  leading empty element, so a fixed index lands in the wrong column
  and the table still renders. Build the index from the header row.
- **Keep §7b and §7c current** when a floor moves or a capability
  changes.

**Run a parity audit** (the `cross-platform-parity-discipline` skill,
"audit" mode) before any launch wave and roughly once per milestone:
walk the shipped feature list per platform and verify every cell is
honest. Real audits on shipped apps have found both missing rows
(features nobody recorded) AND false cells (a "synced" claim that
never actually synced). The audit is what keeps this file true.
