# [APP NAME]: Cross-Platform Feature Parity

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

> **Last audit: YYYY-MM-DD**: <what was walked + which false cells it
> caught, e.g. "walked every shipped feature; found 3 cells claiming ✅
> that were actually stubs">. Run the periodic audit from the
> `cross-platform-parity-discipline` skill and record the date + findings
> here every time. Day-to-day updates miss silently-false cells; only a
> deliberate sweep catches them.

---

## 0. Platform set

<!-- Pin the platform decision here so it's not re-litigated. Which of
     web / iOS / iPadOS / macOS / tvOS / Android ship, and WHY each earns
     its place (or is 🚫 out of scope), with DECISIONS.md refs. Name the
     LEAD platform (ships first, others mirror). tvOS earns its place when
     content is lean-back; macOS is nearly free once the universal Apple
     target exists; skip a platform whose idiom fights the app. A platform
     not yet reached is ⏳ with a note, never silence. -->

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
| <!-- add verbs here as you ship them --> | | | | | | |

---

## 2. Find / explore

| Feature | Web | iOS | macOS | tvOS | Android | Notes |
|---|---|---|---|---|---|---|

---

## 3. [Next verb]

| Feature | Web | iOS | macOS | tvOS | Android | Notes |
|---|---|---|---|---|---|---|

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

## 4. Authentication + profile

| Feature | Web | iOS | macOS | tvOS | Android | Notes |
|---|---|---|---|---|---|---|
| Sign in with Apple | ✅ | ✅ | ✅ | ✅ | 🚫 | Apple ecosystem; Android uses Sign in with Google instead |
| Sign in with Google | 🔮 | 🔮 | 🔮 | 🚫 | ✅ | Android Credential Manager one-tap; web/desktop GIS when sync ships |
| Email/password | ✅ | ✅ | ✅ | 🚫 | ✅ | Typing a password with a Siri Remote is hostile, so tvOS uses SiwA only |
| Biometric gate for sensitive actions | n/a | ✅ Face ID | ✅ Touch ID | n/a | ✅ BiometricPrompt | macOS uses LocalAuthentication (Touch ID / password) |
| Account deletion | ✅ | ✅ | ✅ | ✅ | ✅ | App Store + Play review requirement when sign-in exists |

Sign-in is **optional and gates only sync**. Every browse/use verb
works signed-out on every platform (see `per-ecosystem-sync-islands`).
macOS joins the **Apple CloudKit sync island** for free (same iCloud
container as iOS/tvOS), with no new sync backend.

---

## 5. Universal Links / App Links / deep linking

| Feature | Web | iOS | macOS | tvOS | Android | Notes |
|---|---|---|---|---|---|---|
| Universal Links / App Links (HTTPS) | n/a | ⏳ | ⏳ | n/a | ⏳ | `/.well-known/` files; tvOS has no Safari hand-off (custom scheme only) |
| Custom scheme | n/a | ⏳ | ⏳ | ⏳ | ⏳ | `appname://`; tvOS needs it for Top Shelf + Siri deep links |
| URL params reflect filter state | ✅ | n/a | n/a | n/a | n/a | Web-specific affordance |
| Canonical share URLs (`https://…/item/{id}`) | ✅ renders | ✅ emits | ✅ emits | ✅ emits (QR code, since a TV can't "send" a link) | ✅ emits | Web is the landing twin for every native share (DEEP_LINKS.md) |
| Companion-app deep link | n/a | ✅ `canOpenURL`/`open` | ✅ `NSWorkspace` | n/a | ✅ `Intent` | macOS probes install via `NSWorkspace.urlForApplication(toOpen:)`; NO `LSApplicationQueriesSchemes` entry needed |

---

## 6. Notifications

| Feature | Web | iOS | macOS | tvOS | Android | Notes |
|---|---|---|---|---|---|---|
| Push notifications | 🚫 | 🔮 APNs | 🔮 APNs | 🚫 | 🔮 FCM | Web push too inconsistent; TV notifications are hostile in a living room |
| Cross-platform dispatcher | n/a | 🔮 | 🔮 | n/a | 🔮 | One Worker, two transports (APNs + FCM), symmetric payload |
| Notification permission request | n/a | 🔮 | 🔮 | n/a | 🔮 | At opt-in moment, NOT app launch |

---

## 7. Payments / subscription

| Feature | Web | iOS | macOS | tvOS | Android | Notes |
|---|---|---|---|---|---|---|
| In-app purchase | n/a | 🔮 IAP | 🔮 IAP (same StoreKit) | 🔮 IAP (same StoreKit) | 🔮 Play Billing | |
| Web subscription | 🔮 | n/a | n/a | n/a | n/a | Stripe / Paddle when scoped |
| Cross-platform subscription state sync | 🔮 | 🔮 | 🔮 | 🔮 | 🔮 | Webhooks → `user_subscriptions` table |

---

## 7b. Platform reach

I want the oldest device someone still owns to be served, not
abandoned. This row says how far back each platform reaches, so a floor
change is a visible decision rather than a side effect of a new API.
Choose floors with `multiplatform-expansion-method`.

| Feature | Web | iOS | macOS | tvOS | Android | Notes |
|---|---|---|---|---|---|---|
| Oldest hardware served | <!-- e.g. any evergreen browser --> | <!-- iOS NN floor = oldest iPhone it runs on --> | <!-- macOS NN floor --> | <!-- tvOS NN floor = e.g. Apple TV HD (2015) --> | <!-- minSdk NN = Android N --> | Name the test or CI step that holds each floor, and the DECISIONS entry that chose it |

---

## 7c. Capability definitions

<!-- Add one table per feature whose name covers several modes, where
     which modes a device gets is decided by hardware or OS, not by how
     much we have built. Delete this section if no feature needs it. -->

One name can mean different things on different devices. This table is
the canonical answer to "what does [FEATURE] mean here". The rows
elsewhere in this file carry the engineering detail.

A capability a device can never have (no camera, no API on that OS) is
🚫 here with the reason, and the app omits the entry. A capability a
device could have and currently lacks (not signed in, permission not
granted) stays visible in the app with one sentence saying why.

| Platform | [Mode A] | [Mode B] | Host | Join | Reason for each 🚫 |
|---|---|---|---|---|---|
| iOS / iPadOS | | | | | |
| macOS | | | | | |
| tvOS | | | | | |
| Android phone | | | | | |
| Android TV / Fire TV | | | | | |
| Web | | | | | |

Keep Host and Join as separate columns when they differ: a television
with no camera may be unable to host and still be the best device to
join from.

---

## 7d. Ported platforms (one row each)

When a platform is a port with its own ledger
(`docs/templates/PORT-PARITY-LEDGER-template.md`), this file holds ONE
summary row for it. The per-surface detail lives in the ledger, and
only there, so the two cannot disagree.

| Port | Reference platform | Ledger | Feature ledger | Owner feedback ledger | Status in one sentence |
|---|---|---|---|---|---|
| <!-- e.g. Roku --> | <!-- tvOS --> | `docs/<PLATFORM>-PARITY.md` | `docs/<PLATFORM>-FEATURE-PARITY.md` | `docs/<PLATFORM>-FEEDBACK-LEDGER.md` | |

---

## 8. Backend services / shared data plane

All clients consume the same backend / published data. List the
canonical services and assets here so references stay aligned.
If the app has a content data plane, the full contract lives in
`docs/DATA-CONTRACT.md`. This table just indexes it. All five
clients are **consumers only**: none re-implements or re-hosts the
pipeline (see `shared-data-plane-contract`).

| Service / asset | Purpose | Where | Consumed by |
|---|---|---|---|
| <!-- e.g. catalog.sqlite.zz | full content DB, query-on-disk | GitHub Release (rolling) | iOS, macOS, tvOS, Android download+inflate; web via index --> | | | |

---

## 9. Web-specific affordances

These are web-only by design; other platforms handle the same
need natively.

| Feature | Web | Why |
|---|---|---|
| URL params reflect filter state | ✅ | Shareable deep links; native apps use in-memory state |
| Web Share API + clipboard fallback | ✅ | iOS/macOS/Android use the system share sheet; tvOS shows a QR code |
| View Transitions API (cross-view) | ✅ | iOS uses `.navigationTransition(.zoom)`; Android `sharedBounds` |
| Container queries on components | ✅ | Native platforms use size-class branching |
| Installable PWA + offline shell | ✅ | The zero-install reach play; stores cover the rest |

---

## 10. iOS-specific affordances

| Feature | iOS | Why |
|---|---|---|
| Liquid Glass tab bar / toolbar | ✅ | Web uses `backdrop-filter`; Android M3 tonal elevation |
| Live Activities / Dynamic Island | 🔮 | No equivalent elsewhere; accept the asymmetry |
| WidgetKit home-screen widgets | 🔮 | tvOS analog is Top Shelf; Android analog is Glance widgets |
| Hardware-keyboard shortcuts | ✅ | Web n/a (browser conflicts); macOS uses menu-bar `.commands`; Android Ctrl+1..5 on tablets |
| Picture-in-Picture + background audio | 🔮 | macOS PiP + background audio native; tvOS apps suspend in background |

---

## 11. macOS-specific affordances

macOS is a pointer + keyboard + menu-bar + resizable-multi-window app.
It is NOT the iOS app resized. See `macos-platform-patterns`.

| Feature | macOS | Why |
|---|---|---|
| Menu-bar commands + full keyboard scheme | ✅ | `.commands { }`; iOS uses hardware-shortcut chords, tvOS/web have none |
| `NavigationSplitView` sidebar + detail | ✅ | iOS uses a tab bar, tvOS a focus sidebar: same verbs, Mac idiom |
| Multi-window / document scenes | 🔮 | `WindowGroup` + optional `DocumentGroup`; a heavy pro/creation surface belongs ONLY here (filesystem + subprocess + long compute) |
| Player replaces window root while playing | ✅ | Not an overlay. The split view's toolbar/sidebar/prev-title would bleed through |
| Title via window title bar (no `externalMetadata`) | ✅ | macOS `AVPlayerItem` has no `externalMetadata`; iOS/tvOS set it, web/Android use their own player chrome |

---

## 12. tvOS-specific affordances

These are ten-foot / lean-back idioms by design. The general rule:
**idle/ambient surfaces belong to lean-back devices** (TV first,
iPad/tablet/desktop second, phones rarely).

| Feature | tvOS | Why |
|---|---|---|
| Top Shelf extension | ⏳ | The marquee surface when your icon is focused on the TV home screen; reads an App Group snapshot the app refreshes via `BGAppRefreshTask` |
| Siri "Up Next" via NSUserActivity | ⏳ | System watchlist integration; tiny code surface |
| App Intents voice launches ("surprise me") | ⏳ | Pairs with any random/serendipity verb |
| Focus-driven UI (no pointer, no touch) | ✅ | The defining constraint (see `tvos-platform-patterns`) |
| Idle screensaver / ambient mode | 🔮 | Lean-back idiom; opt-in, never over playback |
| Layered parallax app icon (imagestack) | ⏳ | tvOS icons are layered; see `branding/README.md` |

---

## 13. Android-specific affordances

| Feature | Android | Why |
|---|---|---|
| Predictive back gesture | ⏳ | iOS swipe-back is fixed-animation; Android is user-driven (`enableOnBackInvokedCallback`) |
| Adaptive icon (foreground / background / monochrome) | ⏳ | iOS uses static; tvOS uses layered imagestack |
| App Shortcuts (long-press app icon) | ⏳ | iOS has AppIntents; tvOS has Top Shelf |
| Material You dynamic color (opt-in) | ⏳ | Other platforms have brand-only theming |
| Google Cast sender | 🔮 | AirPlay analog; needs Cast SDK + device-tested receiver |
| 16 KB page size support | ⏳ | Mandatory for new releases targeting Android 15+ |

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
