---
name: multiplatform-expansion-method
description: "Use when planning to add a platform to an existing app (iOS app going to web/Android/tvOS, etc.), sequencing a multi-platform buildout, or scoping how much of an existing codebase a new platform can reuse. Carries the find-the-seam analysis (data plane vs platform layer), platform sequencing by reuse leverage, the hard-ports checklist, choosing platform floors by hardware reach (test-build, CI-held floor, capability tiers), per-platform stack table, and when to author design docs and contracts. Triggers on 'port to Android', 'add a web version', 'Apple TV version', multiplatform plan, platform expansion, 'how much can we reuse', buildout sequencing, deployment target, minSdk, 'support older devices', platform floor, capability tiers, pure-function rule seam."
---

# Multiplatform Expansion Method

How to take an app from one platform to several without rewriting it
several times — distilled from expanding a shipped tvOS app to
iOS/iPadOS, macOS, web PWA, and Android, with all five reaching their
stores.

## Step 1 — Find the seam

Every app separates into two layers. The expansion only rebuilds the
second:

**A. The shared plane** (build once, reuse as-is):
- Published content/data + the pipeline that produces it (see
  `shared-data-plane-contract`)
- Editorial/config JSON
- Deterministic domain logic: schedulers, queue engines, selection
  pools, scoring — anything seeded/pure
- Policy flags baked into the data (visibility, maturity, rights)

**B. The platform layer** (rebuilt natively per platform):
- UI, navigation shell, every view
- The query layer binding (same verbs, native data stack)
- Player/media integration
- Local persistence + platform reach (widgets, voice, deep links)

The contract between them — schemas, asset URLs, query verbs — gets
written down (`docs/DATA-CONTRACT.md`) the moment client #2 exists.
Lock the contract; implement against it independently per platform.

**Reality check from production**: ~60–70% of a media app's Swift was
platform-agnostic. If your analysis says 20%, you probably have UI
logic tangled into the domain layer — untangle first (protocols at
the boundary), then port.

## Step 2 — Sequence by reuse leverage

Order platforms so each phase is the cheapest remaining one and
funds lessons for the next:

| Order | Platform | Why this slot |
|---|---|---|
| 1 | The nearest sibling (tvOS↔iOS via one universal target) | Highest reuse (~60–70%), same toolchain, and ecosystem freebies (one CloudKit DB = household sync free) |
| 2 | The small delta (iPad on the iOS work) | Size-class adaptivity, not a new app |
| 3 | macOS (shares the whole Apple Core) | THE highest-reuse port once iOS exists — the entire Swift Core comes along and it joins the Apple CloudKit island for ~free sync; the only new work is the desktop shell (SwiftUI + AppKit where needed) |
| 4 | Web (PWA) | Widest reach, zero install, NO review gate — ships continuously; becomes the canonical share-URL target for every native platform |
| 5 | Android | Most new code (full Kotlin rebuild); benefits from every prior phase's design decisions |

Each phase runs: bootstrap → core verbs (browse/view/play) →
personalization → modes/extras → platform reach (widgets, voice,
links). Create the platform's binding design doc once it passes ~5
views.

## Step 3 — Pick the stack per platform (don't re-litigate)

- **Apple**: ONE universal Xcode target (iOS + iPadOS + tvOS + macOS),
  `Core/` + per-platform view groups behind `#if os` guards. Swift 6,
  SwiftUI, SwiftData, no third-party packages. macOS is a SwiftUI shell
  (AppKit only where SwiftUI lacks the primitive) that shares the whole
  Apple Core and joins the same CloudKit sync container as iOS/tvOS.
- **Web**: vanilla HTML/CSS/JS, no build step, GitHub Pages,
  URL-driven state, installable PWA. The web app is not a port — URL
  shareability is its superpower.
- **Android**: Kotlin + Compose + M3 Expressive, single-module
  bootstrap, Media3 for playback, Room/SQLite for data, manual or
  Hilt DI.
- **Explicitly rejected** (and why, so it stays rejected): KMP/CMP
  (can't retrofit without rewriting the shipped iOS app; can't render
  Liquid Glass), Flutter/RN (bridge tax on every native API), a
  "responsive web wrapper" per platform (violates feature parity,
  not design consistency).

## Step 3b: Choose floors by hardware reach

A deployment target is a list of devices, not a style preference.
The template's 26 baseline is a default for a new app; lower it when
the owner wants older hardware served, and measure before promising.

1. **Floor by hardware reach, not by OS novelty.** Map each candidate
   OS to the devices it runs on. Archive Watch (its Decision 155 and
   `docs/research/IOS-FLOOR.md`): iOS 17 and 18 run on the SAME
   iPhones (XS/XR and newer), iOS 26 is what dropped XS/XR, so 18 was
   the floor that bought hardware; 17 bought nothing extra. tvOS 26
   already covers every Apple TV that has an App Store (Decision 148),
   so no lower tvOS floor. Android went 29 -> 23 once measured
   (Decision 141).
2. **Test-build and count errors; never commit the experiment.**
   Build at the lower target from the CLI (`IPHONEOS_DEPLOYMENT_TARGET=`,
   or a throwaway pbxproj edit restored with `git checkout`). AW: iOS
   18 = 17 sites in 2 files; 17 = 55 errors in 6 files; 16 = 428
   errors (SwiftData + Observation, i.e. rewrite the data layer).
   Android: run `lint NewApi` at the candidate `minSdk` and check the
   manifest merge (no dependency needed more than 23).
3. **Check the invisible blockers.** The SDK's own minimum
   (`SDKSettings.json` `MinimumDeploymentTarget`, iOS 15 on the iOS 27
   SDK): nothing native goes below it. TLS roots: Android 6.0-7.0 do
   not trust Let's Encrypt, so bundle ISRG Root X1/X2 in
   `network_security_config.xml` or the app installs and then cannot
   fetch its data.
4. **Hold the floor with a CI test.** A floor nobody enforces drifts
   upward in a "cleanup" and silently drops devices with no error
   anywhere. AW: `test_ios_floor.py` / `test_tvos_floor.py` run before
   archiving and refuse a target above the chosen floor; Android keeps
   `lint NewApi` clean for every flavor before release.
5. **Gate features above the floor; the floor is not a ceiling**
   (Decision 154). New APIs go behind `#available` /
   `Build.VERSION.SDK_INT` with a working floor path, or the feature
   is simply absent below it. Never raise the floor for one feature.
   A stored property cannot carry `@available`: store it untyped and
   expose a gated accessor.
6. **Pin libraries strictly or not at all.** Holding one library for
   the floor while another drags its transitive dependency forward
   compiles cleanly and crashes at runtime (AW: material3 held, Coil
   pulled Compose foundation ahead, `AbstractMethodError` on Google
   TV). Add a strict constraint so skew fails the BUILD, with a
   negative control proving it does.
7. **Very old OS versions are the website's job.** Below the SDK
   minimum, serve the web app, and audit it for that browser (optional
   chaining, `??`, flex `gap`, `dvh`, `aspect-ratio`,
   `DecompressionStream` all have Safari floors).
8. **The store's device count is the only visible minSdk
   regression** (Decision 115). CI green, APK correct, store LIVE, and
   Fire TV still showed 38 of 98 devices because an old high-minSdk
   binary was the live one; after the fix, 91. Read the count after
   every release on stores that publish it.
9. **Record it.** An "Oldest hardware served" row in PARITY.md per
   platform, and a DECISIONS entry naming the floor, the measurement,
   and what is still unverified on real hardware.

**Capability tiers, not effort tiers.** What a device offers is
decided by what its hardware and OS permit, never by how much we have
built. Legacy never sets the ceiling: gate the AFFORDANCE on the old
tier and keep the implementation whole (AW Roku `AWCan("shareList")`
hides the row; the QR encoder stays complete). Gate on a hardware
predicate (`hasCamera && hasMicrophone`, `FEATURE_CAMERA_ANY`), never
on form factor (`isTelevision()`). A capability a device can NEVER
have is omitted, with the reason in PARITY.md; one it currently lacks
(unconfigured sign-in, permission not granted) gets a sentence on
screen. See `universal-feature-states` and
`smart-tv-platform-expansion`.

## Step 4 — Plan the hard ports explicitly

List the features that are NOT a view rewrite and decide each one's
strategy before the wave starts:

- **Deterministic engines** (schedulers, queues): first ask whether
  the pipeline can compute the result and publish it (Rule 0 in
  `cross-platform-determinism`). Only when it must run on-device,
  port the LOGIC with identical constants/seeds (same hash function,
  same anchor times) and verify cross-platform agreement on a fixed
  seed. Rebuild only the layout natively.
- **Media playback**: each platform binds its native player
  (AVKit / Media3 / `<video>`); resilience strategy per
  `resilient-media-streaming`. Lock-screen/MediaSession integration
  is part of the port, not polish.
- **Sync**: per `per-ecosystem-sync-islands` — decided per ecosystem,
  never a shared custom backend.
- **Lean-back modes** (ambient, screensaver, party): these are
  device-posture idioms, not features to force everywhere — TV
  first, tablet/desktop second, phones rarely. Record the asymmetry
  in PARITY.md.
- **Shaders/visual effects**: per-platform implementations (Metal /
  AGSL / WebGL-CSS) — schedule last, optional.

### The rule is a value; the platform is a caller

Write every decision rule (a stall detector, a thermal step-down, a
sync correction, a capability predicate) as a pure function or value
type with its inputs injected: health ticks in, "re-attach?" out;
offset and rate in, a correction out. The platform owns the camera,
player, or clock and applies the returned value. That one shape is
both the TEST seam (the rule runs in a unit test with no device) and
the PLATFORM seam (each port calls the same rule). AW's
`CameraStallRecovery` is a Swift value type ported to Kotlin
"thresholds and all", and the Kotlin unit test asserts the same
nine cases the spec lists.

Two traps (AW Decision 133):
- **A shared type is not a shared path.** Putting a behavior in a
  shared type does not mean every platform executes it; AW added
  stall recovery to a session type that iOS never started. Before
  adding to a shared type, confirm which platforms run that code.
- **Prove a control where its value lands** (the engine, the wire,
  the recording), never by watching the control move.

## Step 5 — Keep the matrix true while you go

`cross-platform-parity-discipline` governs the wave: PARITY.md
updated per change set, deliberate defers carry reasons, and a full
parity audit closes each phase.

## Anti-patterns

- **Making the first platform the canonical UI to reskin.** The
  verbs are canonical; no layout is.
- **Re-implementing the data pipeline per client** "because it's
  just a little filtering." That's parity drift at the data layer —
  see `shared-data-plane-contract`.
- **Porting before untangling.** If domain logic imports UI, the
  port forks it. Protocol-decouple first (a `PlaybackSource`
  protocol in Core, conformed by each app store) — it's a day of
  work that saves a fork per platform.
- **Building a platform before measuring the one thing it cannot
  carry.** Archive Watch researched Roblox in nine tracks: the theaters,
  rooms, interface, and tooling all fit, and the films did not (video
  only as hosted 5-minute assets at 2,000 Robux each; the free route plays
  at 256x192 and 12 fps). The owner shelved it: *"I don't think that it is
  worth the time and effort for such a compromised experience"* (AW
  Decision 164). Measure the core payload first, before any account,
  spend, or build. A shelved platform gets its research kept, its
  pathway written down, and named triggers for reopening, so the next
  person neither rediscovers it nor builds it on a whim.
- **Deferring store plumbing.** Deep-link verification files,
  signing, store listings have multi-day external latencies
  (domain DNS, Play review of the developer account) — start them
  at phase start, not phase end. See `store-submission-playbook`.
