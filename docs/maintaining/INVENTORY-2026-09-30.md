# UniversalAppTemplate — inventory for teaching-oriented READMEs

Snapshot of `main` at f670b84 (2026-09-30). Read-only survey. Sections A–E as requested; section 0 is the digest of what matters most.

## 0. Headline findings

1. **No skill actually lacks a description.** All 156 `SKILL.md` files have a `description:` key. The ones that appear description-less in a Claude Code session skill listing (multiplatform-expansion-method, per-ecosystem-sync-islands, shared-data-plane-contract, etc.) are a listing-budget truncation artifact, not a frontmatter gap. The REAL frontmatter defects are:
   - **4 skills have YAML-invalid frontmatter** (unquoted `: ` inside an unquoted description, e.g. "The workflow is: before…"): `binding-design-doc-discipline`, `device-observation-harness`, `ios-share-extension`, `learning-orientation-design`. Strict YAML parsers reject them; Claude Code is lenient today. Fix: wrap description in quotes or use `description: >`.
   - **2 descriptions exceed the 1024-char skill-spec limit**: `ios-production-gotchas` (1543), `android-production-gotchas` (1089).
   - `killer-ui/SKILL.md` has `name: KUI` (does not match its directory name).
2. **14 legacy near-duplicate Apple skills** (README says "~12" and "their bodies differ"). Actually 10 of 14 differ from their upstream twin only in `name:` + H1 title (8–14 diff lines); `live-activities`/`photos-camera-media` differ trivially (24–30 lines). Only `metrickit-diagnostics` (vs `metrickit`) and `ios-security` (vs `swift-security`) are substantively different. They come from an older `swift-ios-skills` vintage that upstream has since renamed — none exist upstream now, so `refresh-skills.sh` will never update them. See A4.
3. **7 hand-authored skills are not discoverable from CLAUDE.md's trigger table**: `apple-app-store-cli-submission`, `macos-native-app-shell`, `web-catalog-data-layer`, `realitykit-3d-card-rendering`, `roku-brightscript-app`, `ten-foot-detail-design` (these 6 are also absent from README), and `concurrent-agent-device-leases` (README only). The most recent commit (8714f2b) added roku + ten-foot without wiring triggers.
4. **App-specific leakage.** Four skills are explicitly "REFERENCE IMPLEMENTATION (Archive Watch)" (`androidtv-compose-focus`, `apple-app-store-cli-submission`, `macos-native-app-shell`, `smarttv-web-app`); `web-catalog-data-layer` is Archive Watch-only (`/watch/`, cites "Decision 029" which in THIS template is the Windows decision). Several docs/templates are un-genericized: `TV-DESIGN-template.md` and `TV-PLATFORM-BACKLOG-template.md` are titled "Archive Watch"; `WINDOWS-DESIGN-template.md` is "Tidbits Trivia"; `OWNER-PLAYBOOK-template.md` is a literal dated launch-status snapshot; `docs/TVOS-PLAYBOOK.md` is "tvOS Playbook — Archive Watch" and says "tvOS 17+" (template floor is tvOS 26); all four `docs/runbooks/*` are Archive Watch runbooks.
5. **Decision-number drift.** Template DECISIONS.md ends at 052, but ported docs/tools cite origin-repo numbers: Decision 055/057/066/081/089/092/093/101/107 (tools, workflows, split-writer template, DECISIONS.md itself), and in-range numbers that now point at the WRONG template decision: TV-PLATFORMS/tizen-submission "Decision 047" (template 047 = backend postures; TV strategy is 028), windows-repl.yml/winbox.py "Decision 045" (template 045 = feature gating; Windows is 029), retry-infra-failures.yml "Decision 048" (template 048 = next-OS APIs), runbooks "Decision 015/018/022/028", web-catalog-data-layer "Decision 029".
6. **SessionStart hook is broken on macOS (two ways).** `.claude/hooks/session-start.sh` greps `/^## Current State/` but SCRATCHPAD.md's heading is `## Current state` (lowercase s), and it pipes to `head -n -1`, which BSD/macOS head rejects ("illegal line count"). Net effect: the "CURRENT STATE" block is always empty. Separately, the hook `cat`s all 753 lines of CLAUDE.md, which Claude Code already loads — duplicate context every session.
7. **Real broken references** (see E): CLAUDE.md's token table points at `Design.swift` in Core (doesn't exist in `apple/Core/`); `appstore-submit.yml` + `docs/APPLE-SUBMISSION-CLI.md` reference `tools/capture-imessage-screenshots.sh` (missing); `roku-brightscript-app` references `tools/roku_design_lint.py` (missing); `tools/atv_run.py` references `tools/atv_install.sh` and `tools/rtdb_join.py` (missing); `tools/pulse_collect.py` references `tools/submit-amazon.py`, `tools/youtube_refresh_token.py` (missing); `tools/_http_fetch.mjs` is a helper for `free_subtitles.py` (missing); CLAUDE.md says "`gh workflow run windows-repl.yml`" but the Windows workflows live in `docs/windows/workflows/` and must be copied into `.github/workflows/` first; CLAUDE.md tells you to create `docs/tvos-playbook.md` but `docs/TVOS-PLAYBOOK.md` already exists — on macOS's case-insensitive FS those are the same file.
8. **`pulse.yml` runs on a live daily cron with `contents: write`** in every clone, running an Archive Watch-branded collector — inconsistent with `workflow-health.yml` / `retry-infra-failures.yml`, which ship DORMANT BY DEFAULT.
9. **Doc overlap clusters** (see D): device testing (DEVICE-HARNESSES + AUTONOMOUS-FLEET-TESTING + 3 skills), Apple submission (CLOUD-SUBMISSION + APPLE-SUBMISSION-CLI + 2 skills + STORE-SCREENSHOTS), tvOS (TVOS-PLAYBOOK + tvos-platform-patterns + its 228-line reference file + TVOS-DESIGN-template), TV (TV-PLATFORMS + smart-tv-platform-expansion + 2 TV templates + tv-design-reference + ten-foot-detail-design), Windows (windows/README + WINDOWS-PLAYBOOK + WINDOWS-STORE-SUBMISSION + windows-production-gotchas).
10. **Tools**: 65 entries in `tools/` (64 files + `ScreenOCR/`; plus an untracked `__pycache__/`). Unreferenced by any doc/skill: `_http_fetch.mjs`, `test_workflow_health_gate.py`, `ffmpeg_limits.py`, `measure_start_times.sh`; referenced only by another tool/workflow: `macapp.py`, `play_promote.py`, `devharness.py`, `ios_run.py`/`mac_run.py`/`web_run.py`/`win_run.py` (these are in AUTONOMOUS-FLEET-TESTING, fine). Many tools hard-code origin apps (`mac-screenshots.sh`, `mac-shotset.sh`, `make_tv_banner.py`, `render-app-icon.py` = Archive Watch/Méliès; `capture-screenshots.sh`, `qa-sweep.sh` = Tidbits; `pulse_collect.py` = Archive Watch). Two parallel Apple TV scenario runners exist (`atv_scenario.py` from Archive Watch, `atv_run.py` a Tidbits adaptation) with different OCR binary paths (`/tmp/awocr` vs `/tmp/tbocr`). `refresh-skills.sh` TEMPLATE_OWNED_SKILLS protects only 10 of 54 hand-authored skills.
11. **Stale command copy**: `/status` reports "Feature parity: any gaps between web and iOS" and `/decision` offers platform tags `[SHARED] / [WEB] / [iOS]` — both predate the 5–6 platform template.
12. CLAUDE.md's project-structure block shows `AppName.xcodeproj/` + `AppName/{App,Core,iOS,macOS,tvOS}` at root, but the repo ships `apple/` (starter files meant to be moved into an Xcode-created project per `apple/README.md`); no .xcodeproj exists. Worth explaining in the teaching README.

## A. Skills (156 directories)

Origin counts: **54 hand-authored** by the template maintainer (from shipped apps: Archive Watch, Tidbits Trivia, BOBA Playbook) · **84 vendored from the `swift-ios-skills` marketplace** (current upstream) · **14 legacy duplicates** from an older `swift-ios-skills` vintage (renamed upstream; still vendored) · **4 other third-party** (ui-ux-pro-max, frontend-design, killer-ui, app-store-screenshots).

Origin determined by: presence in `~/.claude/plugins/marketplaces/swift-ios-skills/skills/` (upstream), `tools/refresh-skills.sh` source lists + TEMPLATE_OWNED_SKILLS, README "Skills bundled" table, and frontmatter. Note: refresh-skills.sh TEMPLATE_OWNED_SKILLS lists only 10 of the 54 hand-authored skills; the other 44 are synced FROM `~/.claude/skills/` and could be clobbered by a stale global copy.

### A1. Hand-authored (template maintainer) — 54

#### Values & method

| Skill | Origin | What it is for (first sentence of description) | Flags |
|---|---|---|---|
| `learning-orientation-design` | hand-authored | Use before implementing any new feature — the test is whether the feature serves human learning and growth, not replacement. | YAML-invalid frontmatter (unquoted ": ") |
| `feature-shipping-discipline` | hand-authored | Use as the end-to-end workflow for shipping any feature change. |  |
| `binding-design-doc-discipline` | hand-authored | Use when a project has a binding design doc (DESIGN.md, WEB-DESIGN.md, STYLE_GUIDE.md, etc.) that governs UI/IA decisions. | YAML-invalid frontmatter (unquoted ": " in description) |
| `architectural-decision-log` | hand-authored | Use when a project has a DECISIONS.md (or ADR log) capturing architecture choices. |  |
| `3d-feature-debug-loop` | hand-authored | Use when iterating on a complex visual / 3D feature where user feedback keeps surfacing the same kind of bug after several "fix" attempts. |  |
| `two-agent-handoff` | hand-authored | Use when TWO AI agent surfaces with different capabilities collaborate on one project — a repo-access coding agent paired with a research/data-authoring agent that has no repo access, or any asymmetric pair — and their work must hand off cleanly without silent |  |

#### Design principles (all platforms)

| Skill | Origin | What it is for (first sentence of description) | Flags |
|---|---|---|---|
| `mobile-first-density-design` | hand-authored | Use when designing or reviewing any UI — the principle is that visual density comes from REMOVING chrome, not adding decoration. |  |
| `native-platform-first` | hand-authored | Use before building any custom UI component, animation, gesture, modal, dropdown, or interaction. |  |
| `universal-feature-states` | hand-authored | Use when designing any list, grid, search, sheet, or feature with content that loads. |  |
| `ten-foot-detail-design` | hand-authored | The reusable design of a Detail/hero page and its neighbours (Series, Search) on a ten-foot TV screen, distilled from building the same patterns twice — Roku (SceneGraph) then Android TV (Compose) — where they came out identical because they are platform-agnos | not in CLAUDE.md/README trigger table |

#### Cross-platform architecture

| Skill | Origin | What it is for (first sentence of description) | Flags |
|---|---|---|---|
| `cross-platform-parity-discipline` | hand-authored (template-owned in refresh script) | Use when shipping ANY user-facing feature in a multi-platform repo, when asked to "check parity", "audit features", or before a launch wave on any platform. |  |
| `multiplatform-expansion-method` | hand-authored (template-owned in refresh script) | Use when planning to add a platform to an existing app (iOS app going to web/Android/tvOS, etc.), sequencing a multi-platform buildout, or scoping how much of an existing codebase a new platform can reuse. |  |
| `cross-platform-determinism` | hand-authored | Use whenever a value must come out IDENTICAL on every platform — a "daily" content pick, a shared shuffle, a deterministic match plan, a hash used as a key. |  |
| `cross-platform-multiplayer` | hand-authored | Use when building any real-time multiplayer that must span native (iOS/macOS/tvOS/Android) AND the web — same-room local play over the LAN, or online play across the internet. |  |

#### Data & backend

| Skill | Origin | What it is for (first sentence of description) | Flags |
|---|---|---|---|
| `shared-data-plane-contract` | hand-authored (template-owned in refresh script) | Use when multiple clients consume the same content/data (a catalog, feed, corpus, or library), when designing how published data reaches the apps, when a browser client needs the shared data (CORS/Range realities), or when changing the published schema. |  |
| `canonical-entity-identity` | hand-authored | Use when a catalog/corpus needs stable per-entity identifiers, when designing or evolving a composite ID formula, when two records collide on the current ID, when migrating IDs across bundles + databases, or when an asset pipeline must guarantee one-asset-per- |  |
| `image-cdn-discipline` | hand-authored | Use when an app serves a large image catalog (hundreds to tens of thousands of images), when choosing where image bytes live, when grids scroll slowly or detail views load blurry art, or when standing up or migrating an image CDN (R2, Cloudinary, S3+CloudFront |  |
| `per-ecosystem-sync-islands` | hand-authored (template-owned in refresh script) | Use when adding sync of user state (favorites, progress, playlists, preferences) across devices, when adding sign-in, or when tempted to stand up a sync backend. |  |
| `zero-cost-hosted-backend` | hand-authored | Use when an app needs SHARED user data — accounts, public profiles, cross-user features (shared collections, moderation, matching, social rows) — the case per-ecosystem-sync-islands explicitly does not cover. |  |
| `content-corpus-derivation` | hand-authored | Use when the app ships a CORPUS derived from a messy external source — extracting facts, cards, questions, entries, or any structured content from Wikipedia/an API/a dump/scraped text. |  |
| `web-catalog-data-layer` | hand-authored | Use when touching the web viewer's data access (/watch/), adding a web feature that needs catalog data, or considering SQLite-over-HTTP for the browser. | Archive Watch-specific (/watch/, "Decision 029" = template's Windows decision); not in CLAUDE.md/README; refs publish-db.yml (absent) |

#### Domain-specific product patterns

| Skill | Origin | What it is for (first sentence of description) | Flags |
|---|---|---|---|
| `provenance-honest-market-data` | hand-authored | Use when an app displays prices, valuations, comps, or any market signal (collectibles, resale, tickets, real-estate comps, marketplace data), when the sold-data API you wanted doesn't exist or won't grant access, when matching third-party listings to your own |  |
| `marketplace-adjacent-design` | hand-authored | Use when adding ANY user-to-user trading, selling, matching, or classifieds feature to an app — before writing the first table or view. |  |
| `third-party-revocation-resilience` | hand-authored | Use when the app depends on a third party's data, images, or API (a price guide, a metadata provider, a scraping target, a partner feed) — both BEFORE the dependency becomes load-bearing (design the exit path) and the day a partner revokes authorization (execu |  |
| `third-party-ip-monetization` | hand-authored | Use when planning to monetize an app built around IP or content you don't own — a fan app, a companion app, a catalog/collection app for someone else's game, cards, shows, or music — or when choosing between seeking a license, restructuring what's paid, and ac |  |
| `values-based-feed-ranking` | hand-authored | Use when building any algorithmic content surface — a feed, a discovery tab, a "for you" ranking, a multi-source merge — especially over a third-party social/content API. |  |
| `web-content-extraction` | hand-authored | Use when an app needs to fetch and render THIRD-PARTY page content the app doesn't control — a reader mode, article extraction, OG/link-preview cards — from a static-hosted web app (CORS wall) or a native app (no CORS, different traps). |  |
| `camera-recognition-pipeline` | hand-authored | Use when building or debugging any feature that identifies physical objects with a live camera — trading cards, labels, tickets, book spines, receipts, product packaging. |  |
| `resilient-media-streaming` | hand-authored (template-owned in refresh script) | Use when streaming video/audio from hosts you don't control (archives, CDNs with idle-connection resets, redirect-heavy origins), when playback "stalls every minute or two" despite good bandwidth, or when porting playback to a new platform. |  |
| `realitykit-3d-card-rendering` | hand-authored | Use when building or debugging 3D card-rendering features in iOS RealityKit / RealityFoundation — premium card animations, hero-shot videos, trading-card 3D views, etc. | BOBA-derived; not in CLAUDE.md/README |

#### Platform: web

| Skill | Origin | What it is for (first sentence of description) | Flags |
|---|---|---|---|
| `web-platform-patterns` | hand-authored (template-owned in refresh script) | Use before any web (vanilla HTML/CSS/JS, no build step, static hosting) UI / routing / data / offline / image work. |  |

#### Platform: iOS / iPadOS

| Skill | Origin | What it is for (first sentence of description) | Flags |
|---|---|---|---|
| `ios-production-gotchas` | hand-authored (template-owned in refresh script) | Use when building or debugging iOS/iPadOS SwiftUI features — the cross-cutting production lessons from four shipped App Store apps that no single framework skill covers. | description 1543 chars (>1024 spec limit) |
| `ios-share-extension` | hand-authored | Use when adding an iOS Share Extension (share-sheet target) to an app — receiving images/video/URLs/text from other apps, handing the payload to the containing app via an App Group, and the ONE working pattern for opening the containing app from the extension  | YAML-invalid frontmatter (unquoted ": ") |

#### Platform: macOS

| Skill | Origin | What it is for (first sentence of description) | Flags |
|---|---|---|---|
| `macos-platform-patterns` | hand-authored | Use before any macOS app shell / player / hero / browse / window / document / image work. |  |
| `macos-native-app-shell` | hand-authored | REFERENCE IMPLEMENTATION (Archive Watch) behind the generic `macos-platform-patterns` skill — consult AFTER it, for the worked example. | REFERENCE IMPL (Archive Watch); not in CLAUDE.md/README; refs docs/macOS-DESIGN.md |

#### Platform: tvOS

| Skill | Origin | What it is for (first sentence of description) | Flags |
|---|---|---|---|
| `tvos-platform-patterns` | hand-authored (template-owned in refresh script) | Use before any tvOS UI / focus / layout / animation / image-pipeline / persistence work. |  |

#### Platform: Android

| Skill | Origin | What it is for (first sentence of description) | Flags |
|---|---|---|---|
| `android-production-gotchas` | hand-authored (template-owned in refresh script) | Use when building or debugging the Android (Kotlin + Compose + M3) app — the cross-cutting production lessons from shipping Compose apps to Google Play that the framework docs don't carry. | description 1089 chars (>1024 spec limit) |

#### Platform: TV (Android TV / Fire TV / webOS / Tizen / Roku)

| Skill | Origin | What it is for (first sentence of description) | Flags |
|---|---|---|---|
| `smart-tv-platform-expansion` | hand-authored | Take an existing app to the living room — Android TV / Google TV / Fire TV, Samsung Tizen, LG webOS, VIDAA, Roku, and the Cast/AirPlay routes. |  |
| `androidtv-compose-focus` | hand-authored | REFERENCE IMPLEMENTATION (Archive Watch) behind the generic `smart-tv-platform-expansion` skill — consult AFTER it, for the worked example. | REFERENCE IMPL (Archive Watch) — AW-specific worked example |
| `smarttv-web-app` | hand-authored | REFERENCE IMPLEMENTATION (Archive Watch) behind the generic `smart-tv-platform-expansion` skill — consult AFTER it, for the worked example. | REFERENCE IMPL (Archive Watch); refs watch.js/watch.css/docs/TV-DESIGN.md (app files) |
| `roku-brightscript-app` | hand-authored | Build a real Roku channel in BrightScript + SceneGraph and drive it autonomously over the network. | not in CLAUDE.md/README trigger table; refs tools/roku_design_lint.py (missing) |

#### Platform: Windows

| Skill | Origin | What it is for (first sentence of description) | Flags |
|---|---|---|---|
| `windows-production-gotchas` | hand-authored | Use when building or debugging the Windows (Avalonia + FluentAvalonia + .NET) app — the cross-cutting production lessons from shipping an Avalonia MSIX to the Microsoft Store from a Mac with zero Windows hardware. |  |

#### Testing & observation

| Skill | Origin | What it is for (first sentence of description) | Flags |
|---|---|---|---|
| `device-observation-harness` | hand-authored | Use when a fix cannot be verified by reading the app's own logs or a simulator - tvOS/Apple TV behavior, D-pad focus on Android TV / Fire TV, web-TV on webOS/Tizen, playback/caption sync, or any bug the user keeps reporting as "still broken" after fixes that l | YAML-invalid frontmatter (unquoted ": ") |
| `autonomous-fleet-testing` | hand-authored | Build or extend automation that drives REAL devices (iOS, iPadOS, tvOS, macOS, Android, Windows, web) and grades the app from the screen rather than from its own logs. | near-copy of docs/AUTONOMOUS-FLEET-TESTING.md (same section outline) |
| `concurrent-agent-device-leases` | hand-authored | Use when more than one agent session drives the same physical test devices — two Claude Code sessions in different repos sharing a bench of phones/TVs, or any harness that force-stops apps and resets device state. | not in CLAUDE.md trigger table (README only) |
| `3d-feature-sim-validation` | hand-authored | Use when iterating on 3D / RealityKit / video-render features where you cannot directly see the on-device output. |  |

#### CI & automation

| Skill | Origin | What it is for (first sentence of description) | Flags |
|---|---|---|---|
| `ci-fleet-engineering` | hand-authored | Use when adding, editing, or debugging ANY scheduled GitHub Actions workflow that mutates shared data, publishes an artifact, or runs on a cron — and when diagnosing CI failures, cancelled runs, lock contention, lost work, or alert noise. |  |
| `autonomous-loop-cadence` | hand-authored | Use when running an autonomous /loop on a multi-platform codebase (iOS / web / Android, or similar). |  |

#### Store & release

| Skill | Origin | What it is for (first sentence of description) | Flags |
|---|---|---|---|
| `store-submission-playbook` | hand-authored (template-owned in refresh script) | Use when preparing ANY store submission — App Store (iOS/iPadOS/tvOS/macOS), Google Play, or the Microsoft Store — including TestFlight/internal-track setup, store listings, screenshots, signing, review prep, in-app purchase launches, and the post-approval fol |  |
| `cloud-appstore-submission` | hand-authored | Use when submitting any Apple App Store build (iOS / iPadOS / tvOS / macOS), especially from a dev Mac running a beta OS. |  |
| `apple-app-store-cli-submission` | hand-authored | REFERENCE IMPLEMENTATION (Archive Watch) behind the generic `cloud-appstore-submission` skill — consult AFTER it for the local-CLI pathway and its traps. | REFERENCE IMPL (Archive Watch); not referenced in CLAUDE.md/README |
| `play-cli-submission` | hand-authored | Use when shipping an Android build (AAB) to Google Play from the command line — no Play Console GUI. |  |

#### Product ops & metrics

| Skill | Origin | What it is for (first sentence of description) | Flags |
|---|---|---|---|
| `product-pulse-dashboard` | hand-authored | Build a daily product-health dashboard that reads every channel a shipped app has — store submissions and reviews, downloads and installs, crashes, social posts and their engagement, mentions across the open web, CI health. |  |
| `store-metrics-pipelines` | hand-authored | Read downloads, installs, active devices, ratings, reviews and crash clusters out of App Store Connect, Google Play, and the Amazon Appstore. |  |

### A2. Vendored third-party (design tooling / store marketing) — 4

| Skill | Origin | What it is for | Flags |
|---|---|---|---|
| `ui-ux-pro-max` | ui-ux-pro-max-skill marketplace | UI/UX design intelligence for web and mobile. |  |
| `frontend-design` | claude-plugins-official (Anthropic) | Create distinctive, production-grade frontend interfaces with high design quality. |  |
| `killer-ui` | GitHub BigSiggis/Killer-UI | Killer UI — a Claude Code skill set that turns vibe-coded UIs into production-grade, Apple-quality design systems. | frontmatter name "KUI" != directory "killer-ui" |
| `app-store-screenshots` | GitHub ParthJadhav/app-store-screenshots | Use when building App Store or Google Play screenshot pages, generating exportable marketing screenshots for iOS and/or Android apps, or scaffolding a screenshot editor with Next.js. | refs companion skill ios-marketing-capture (not vendored) |

### A3. Apple framework reference — vendored from `swift-ios-skills` marketplace (84)

#### SwiftUI

| Skill | Origin | What it is for | Flags |
|---|---|---|---|
| `swiftui-animation` | swift-ios-skills | Implement, review, or improve SwiftUI animations and transitions. |  |
| `swiftui-gestures` | swift-ios-skills | Implement, review, or improve SwiftUI gesture handling. |  |
| `swiftui-layout-components` | swift-ios-skills | Build SwiftUI layouts using stacks, grids, lists, scroll views, forms, and controls. |  |
| `swiftui-liquid-glass` | swift-ios-skills | Implement, review, or improve SwiftUI Liquid Glass effects for iOS 26+. |  |
| `swiftui-navigation` | swift-ios-skills | Implement SwiftUI navigation patterns including NavigationStack, NavigationSplitView, sheet presentation, tab-based navigation, and deep linking. |  |
| `swiftui-patterns` | swift-ios-skills | Builds SwiftUI views with modern MV architecture, state management, and view composition patterns. |  |
| `swiftui-performance` | swift-ios-skills | Audit and improve SwiftUI runtime performance. |  |
| `swiftui-uikit-interop` | swift-ios-skills | Bridges UIKit and SwiftUI by wrapping UIKit views and view controllers in SwiftUI with UIViewRepresentable and UIViewControllerRepresentable, embedding SwiftUI in UIKit with UIHostingController, and coordinating delegate callbacks. |  |
| `swiftui-webkit` | swift-ios-skills | Embeds and controls web content in SwiftUI with WebKit for SwiftUI, including WebView, WebPage, navigation policies, JavaScript execution, observable page state, link interception, local HTML or data loading, and custom URL schemes. |  |

#### Swift language & tooling

| Skill | Origin | What it is for | Flags |
|---|---|---|---|
| `debugging-instruments` | swift-ios-skills | Debug iOS apps and profile performance using LLDB, Memory Graph Debugger, and Instruments. |  |
| `ios-simulator` | swift-ios-skills | Manages iOS Simulator devices and tests app behavior using xcrun simctl. |  |
| `swift-api-design-guidelines` | swift-ios-skills | Apply Swift API Design Guidelines to name, label, and document Swift APIs. |  |
| `swift-architecture` | swift-ios-skills | Select, implement, or migrate between app architecture patterns for Apple platform apps. |  |
| `swift-charts` | swift-ios-skills | Implement, review, or improve data visualizations using Swift Charts. |  |
| `swift-codable` | swift-ios-skills | Implement Swift Codable models for JSON and property-list encoding and decoding with JSONDecoder, JSONEncoder, CodingKeys, and custom init(from:) or encode(to:). |  |
| `swift-concurrency` | swift-ios-skills | Resolve Swift concurrency compiler errors, adopt approachable concurrency (SE-0466), and write data-race-safe async code. |  |
| `swift-formatstyle` | swift-ios-skills | Format values for display using the FormatStyle protocol and its concrete types. |  |
| `swift-language` | swift-ios-skills | Apply modern Swift language patterns and idioms for non-concurrency, non-SwiftUI code. |  |
| `swift-security` | swift-ios-skills | Use when working with iOS/macOS Keychain Services (SecItem queries, kSecClass, OSStatus errors), biometric authentication (LAContext, Face ID, Touch ID), CryptoKit (AES-GCM, ChaChaPoly, ECDSA, ECDH, HPKE, ML-KEM), Secure Enclave, secure credential storage (OAu | overlaps ios-security (older vintage, substantively different body) |
| `swift-testing` | swift-ios-skills | Writes and migrates tests using the Swift Testing framework with @Test, @Suite, #expect, #require, confirmation, parameterized tests, test tags, traits, withKnownIssue, XCTest UI testing, XCUITest, test plan, mocking, test doubles, testable architecture, snaps |  |
| `swiftlint` | swift-ios-skills | Configures and enforces SwiftLint in Swift projects using build tool plugins, run scripts, and CI. |  |

#### Persistence & sync

| Skill | Origin | What it is for | Flags |
|---|---|---|---|
| `cloudkit` | swift-ios-skills | Implement, review, or improve CloudKit and iCloud sync in iOS/macOS apps. |  |
| `core-data` | swift-ios-skills | Build, review, or improve Core Data persistence in apps that have not adopted SwiftData. |  |
| `swiftdata` | swift-ios-skills | Implement, review, or improve data persistence using SwiftData. |  |

#### System integration (widgets, intents, notifications, background)

| Skill | Origin | What it is for | Flags |
|---|---|---|---|
| `activitykit` | swift-ios-skills | Implement, review, or improve Live Activities and Dynamic Island experiences in iOS apps using ActivityKit. |  |
| `alarmkit` | swift-ios-skills | Implement AlarmKit alarms and countdown timers for iOS and iPadOS with Lock Screen, Dynamic Island, and Apple Watch system UI. |  |
| `app-clips` | swift-ios-skills | Build iOS App Clips with invocation URLs, NFC, QR codes, App Clip Codes, Safari banners, Maps, Messages, and shared App Group data handoff to the full app. |  |
| `app-intents` | swift-ios-skills | Implement App Intents for Siri, Shortcuts, Spotlight, widgets, Control Center, and Apple Intelligence on iOS. |  |
| `appmigrationkit` | swift-ios-skills | Transfer app data between platforms using AppMigrationKit. |  |
| `background-processing` | swift-ios-skills | Schedule and execute background work on iOS using BGTaskScheduler. |  |
| `browserenginekit` | swift-ios-skills | Build alternative browser engines using BrowserEngineKit. |  |
| `carplay` | swift-ios-skills | Build CarPlay-enabled apps using the CarPlay framework. |  |
| `push-notifications` | swift-ios-skills | Implement, review, or debug push notifications in iOS/macOS apps — local notifications, remote (APNs) notifications, rich notifications, notification actions, silent pushes, and notification service/content extensions. |  |
| `relevancekit` | swift-ios-skills | Increase widget visibility on Apple Watch using RelevanceKit. |  |
| `tipkit` | swift-ios-skills | Implement, review, or improve in-app tips and onboarding using Apple's TipKit framework. |  |
| `widgetkit` | swift-ios-skills | Implement, review, or improve widgets, Live Activities, and controls using WidgetKit and ActivityKit. |  |

#### Media, audio & shared experiences

| Skill | Origin | What it is for | Flags |
|---|---|---|---|
| `audioaccessorykit` | swift-ios-skills | Support audio accessory features like automatic switching using AudioAccessoryKit. |  |
| `avkit` | swift-ios-skills | Create media playback experiences using AVKit. |  |
| `callkit` | swift-ios-skills | Implement VoIP calling with CallKit and PushKit. |  |
| `musickit` | swift-ios-skills | Integrate Apple Music playback, catalog search, and Now Playing metadata using MusicKit and MediaPlayer. |  |
| `paperkit` | swift-ios-skills | Add drawings, shapes, and a consistent markup experience using PaperKit. |  |
| `pdfkit` | swift-ios-skills | Display and manipulate PDF documents using PDFKit. |  |
| `pencilkit` | swift-ios-skills | Add Apple Pencil drawing, canvas views, tool pickers, and ink serialization using PencilKit. |  |
| `photokit` | swift-ios-skills | Implement, review, or improve photo picking, camera capture, and media handling in iOS apps using PhotoKit and AVFoundation. |  |
| `shareplay-activities` | swift-ios-skills | Build shared real-time experiences using GroupActivities and SharePlay. |  |
| `speech-recognition` | swift-ios-skills | Transcribe speech to text using the Speech framework. |  |

#### Graphics, AR & games

| Skill | Origin | What it is for | Flags |
|---|---|---|---|
| `focus-engine` | swift-ios-skills | Implements keyboard, directional, and scene-level focus behavior across SwiftUI and UIKit. | overlaps tvos-platform-patterns / androidtv-compose-focus (generic UIKit/SwiftUI focus) |
| `gamekit` | swift-ios-skills | Integrate Game Center features using GameKit. |  |
| `realitykit` | swift-ios-skills | Build augmented reality experiences with RealityKit and ARKit on iOS. |  |
| `scenekit` | swift-ios-skills | Build 3D scenes and visualizations using SceneKit. |  |
| `spritekit` | swift-ios-skills | Build 2D games and animations using SpriteKit. |  |
| `tabletopkit` | swift-ios-skills | Create multiplayer spatial board games using TabletopKit on visionOS. |  |

#### ML & intelligence

| Skill | Origin | What it is for | Flags |
|---|---|---|---|
| `apple-on-device-ai` | swift-ios-skills | Integrate on-device AI using Foundation Models framework, Core ML, and open-source LLM runtimes on Apple Silicon. |  |
| `coreml` | swift-ios-skills | Integrate and optimize Core ML models in iOS apps for on-device machine learning inference. |  |
| `natural-language` | swift-ios-skills | Tokenize, tag, and analyze natural language text using Apple's NaturalLanguage framework and translate between languages with the Translation framework. |  |
| `vision-framework` | swift-ios-skills | Implement computer vision features including text recognition (OCR), face detection, barcode scanning, image segmentation, object tracking, and document scanning in iOS apps. |  |

#### Security, identity & privacy

| Skill | Origin | What it is for | Flags |
|---|---|---|---|
| `authentication` | swift-ios-skills | Implement iOS authentication patterns including Sign in with Apple (ASAuthorizationAppleIDProvider, ASAuthorizationController, ASAuthorizationAppleIDCredential), credential state checking, identity token validation, ASWebAuthenticationSession for OAuth and thi |  |
| `cryptokit` | swift-ios-skills | Perform cryptographic operations using Apple CryptoKit. |  |
| `cryptotokenkit` | swift-ios-skills | Access security tokens and smart cards using CryptoTokenKit. |  |
| `device-integrity` | swift-ios-skills | Verify device legitimacy and app integrity using DeviceCheck (DCDevice per-device bits) and App Attest (DCAppAttestService key generation, attestation, and assertion flows). |  |
| `ios-accessibility` | swift-ios-skills | Implements, reviews, or improves accessibility in iOS/macOS apps with SwiftUI and UIKit. |  |
| `ios-localization` | swift-ios-skills | Implement, review, or improve localization and internationalization in iOS/macOS apps — String Catalogs (.xcstrings), generated localizable symbols, stable key naming, LocalizedStringKey, LocalizedStringResource, pluralization, FormatStyle for numbers/dates/me |  |
| `ios-networking` | swift-ios-skills | Build, review, or improve networking code in iOS/macOS apps using URLSession with async/await, structured concurrency, and modern Swift patterns. |  |
| `permissionkit` | swift-ios-skills | Create child communication safety experiences using PermissionKit to request parental permission for children. |  |

#### Commerce & App Store

| Skill | Origin | What it is for | Flags |
|---|---|---|---|
| `adattributionkit` | swift-ios-skills | Measure ad effectiveness with privacy-preserving attribution using AdAttributionKit. |  |
| `app-store-optimization` | swift-ios-skills | Optimize App Store product pages for search visibility and conversion. |  |
| `app-store-review` | swift-ios-skills | Prepare for App Store review and prevent rejections. |  |
| `financekit` | swift-ios-skills | Access Apple Card, Apple Cash, and Wallet financial data using FinanceKit. |  |
| `passkit` | swift-ios-skills | Integrate Apple Pay payments and Wallet passes using PassKit. |  |
| `storekit` | swift-ios-skills | Implement, review, or improve in-app purchases and subscriptions using StoreKit 2. |  |

#### Hardware, sensors & home

| Skill | Origin | What it is for | Flags |
|---|---|---|---|
| `accessorysetupkit` | swift-ios-skills | Discover and configure Bluetooth and Wi-Fi accessories using AccessorySetupKit. |  |
| `contacts-framework` | swift-ios-skills | Read, create, update, and pick contacts using the Contacts and ContactsUI frameworks. |  |
| `core-bluetooth` | swift-ios-skills | Scan, connect, and communicate with Bluetooth Low Energy peripherals and publish local peripheral services using Core Bluetooth. |  |
| `core-motion` | swift-ios-skills | Access accelerometer, gyroscope, magnetometer, pedometer, and activity-recognition data using CoreMotion. |  |
| `core-nfc` | swift-ios-skills | Read and write NFC tags using CoreNFC. |  |
| `dockkit` | swift-ios-skills | Control motorized camera docks and enable intelligent subject tracking using DockKit. |  |
| `energykit` | swift-ios-skills | Query grid electricity forecasts and submit load events using EnergyKit to help users optimize home electricity usage. |  |
| `eventkit` | swift-ios-skills | Create, read, and manage calendar events and reminders using EventKit and EventKitUI. |  |
| `healthkit` | swift-ios-skills | Read, write, and query Apple Health data using HealthKit. |  |
| `homekit` | swift-ios-skills | Control smart-home accessories and commission Matter devices using HomeKit and MatterSupport. |  |
| `mapkit` | swift-ios-skills | Implement, review, or improve maps and location features in iOS/macOS apps using MapKit and CoreLocation. |  |
| `metrickit` | swift-ios-skills | Collect and analyze on-device performance metrics and crash diagnostics using MetricKit. | pair metrickit-diagnostics differs substantively (479 vs 372 lines) |
| `sensorkit` | swift-ios-skills | Access research-grade sensor data using SensorKit. |  |
| `weatherkit` | swift-ios-skills | Fetch current, hourly, and daily weather forecasts and display required attribution using WeatherKit. |  |

### A4. Legacy near-duplicates (older swift-ios-skills vintage, no longer upstream) — 14

| Legacy skill | Current upstream twin | Diff vs twin | Recommendation |
|---|---|---|---|
| `callkit-voip` | `callkit` | 8 diff lines — name + H1 only (identical body) | delete legacy copy |
| `cloudkit-sync` | `cloudkit` | 14 diff lines — near-identical (minor wording) | delete legacy copy |
| `eventkit-calendar` | `eventkit` | 8 diff lines — name + H1 only (identical body) | delete legacy copy |
| `homekit-matter` | `homekit` | 8 diff lines — name + H1 only (identical body) | delete legacy copy |
| `mapkit-location` | `mapkit` | 12 diff lines — near-identical (minor wording) | delete legacy copy |
| `metrickit-diagnostics` | `metrickit` | 133 diff lines — substantively different | review/merge, then delete one |
| `musickit-audio` | `musickit` | 8 diff lines — name + H1 only (identical body) | delete legacy copy |
| `passkit-wallet` | `passkit` | 8 diff lines — name + H1 only (identical body) | delete legacy copy |
| `pencilkit-drawing` | `pencilkit` | 11 diff lines — near-identical (minor wording) | delete legacy copy |
| `realitykit-ar` | `realitykit` | 8 diff lines — name + H1 only (identical body) | delete legacy copy |
| `live-activities` | `activitykit` | 24 diff lines — near-identical (minor wording) | delete legacy copy |
| `photos-camera-media` | `photokit` | 30 diff lines — near-identical (minor wording) | delete legacy copy |
| `codable-patterns` | `swift-codable` | 8 diff lines — name + H1 only (identical body) | delete legacy copy |
| `ios-security` | `swift-security` | 742 diff lines — substantively different | review/merge, then delete one |


## B. Tools (`tools/`, 65 entries)

"Referenced by" = docs/skills/workflows that name the file (excluding the tool itself). **UNREFERENCED** = no doc or skill names it. "Origin-bound" = hard-codes an origin app (Archive Watch = AW, Tidbits Trivia = TT) and needs adapting.

### B1. Skill + template maintenance
| Tool | What it does | Referenced by |
|---|---|---|
| `refresh-skills.sh` | Re-syncs vendored skills from the swift-ios-skills / ui-ux-pro-max / frontend-design marketplaces, GitHub-tracked repos (app-store-screenshots, killer-ui), and `~/.claude/skills/`; protects 10 template-owned skills | README, settings.json, install-android-skills.sh |
| `install-android-skills.sh` | Clones the recommended Android skill stack into `~/.claude/sources/` for the next refresh to vendor | README, settings.json, android-production-gotchas |
| `app_config.py` | The one file a new app fills in: bundle ids, device ids, names every harness imports | README, AUTONOMOUS-FLEET-TESTING, autonomous-fleet-testing, product-pulse-dashboard, PRODUCT-PULSE |

### B2. Apple store submission (App Store Connect API)
| Tool | What it does | Referenced by |
|---|---|---|
| `submit-appstore.sh` | CLI archive + sign + upload for mac / ios / tvos / all (no Xcode GUI) | README, CLOUD-SUBMISSION, cloud-appstore-submission, apple-app-store-cli-submission, appstore-build.yml |
| `asc_certs.py` | Find or create a distribution / mac-installer cert via ASC API | README, DECISIONS, CLOUD-SUBMISSION, both Apple submission skills |
| `asc_profiles.py` | Create + install App Store provisioning profiles, print bundle→UUID map | README, CLOUD-SUBMISSION, APPLE-SUBMISSION-CLI, ios-share-extension, submission skills |
| `asc_prune_certs.py` | Revoke throwaway Development certs each cloud build mints | README (Decision 027 in DECISIONS covers it) |
| `ci_make_signing_p12.py` | Mint a dedicated CI distribution cert into a .p12 for GitHub secrets | README, DECISIONS, CLOUD-SUBMISSION, apple-app-store-cli-submission, appstore-build.yml |
| `asc_build_exists.py` | Check whether a build number is already on ASC before the expensive archive | README only |
| `asc_submit.py` | Open version, attach build, notes, upload (iMessage) screenshots, submit for review | APPLE-SUBMISSION-CLI, apple-app-store-cli-submission, appstore-submit.yml |
| `asc.py` | Tiny read-only ASC API client for authoritative launch state | OWNER-PLAYBOOK-template only |

### B3. Google Play / Android release
| Tool | What it does | Referenced by |
|---|---|---|
| `submit-play.sh` | Bump versionCode, build signed AAB, publish via play-publish.py | README, DECISIONS, SCRATCHPAD, CLOUD-SUBMISSION, play-cli-submission, play-api-key-setup, play-release.yml |
| `play-publish.py` | Upload AAB + create a track release via Play Developer API v3 | README, DECISIONS, CLOUD-SUBMISSION, play-cli-submission, play-release.yml |
| `play_promote.py` | Promote an existing Play build to another track without rebuilding | play-release.yml only (no doc) |
| `testlab-android.sh` | Run release build through Firebase Test Lab Robo on real devices | README, SCRATCHPAD, DEVICE-HARNESSES, IAP-RELEASE-CHOREOGRAPHY, 3 skills |

### B4. Windows
| Tool | What it does | Referenced by |
|---|---|---|
| `stamp_msix_version.py` | Stamp MSIX manifest version from AppVersion.xcconfig | CLAUDE.md, CONTRIBUTING, windows docs, windows-store.yml, csproj |
| `winbox.py` | Drive a real Windows machine over SSH (deploy, launch, photograph) | AUTONOMOUS-FLEET-TESTING, autonomous-fleet-testing |
| `win_run.py` | Windows real-hardware harness (env hook → capture → OCR → grade) | AUTONOMOUS-FLEET-TESTING |

### B5. Real-device fleet harness (the "grade from the glass" rig)
| Tool | What it does | Referenced by |
|---|---|---|
| `devharness.py` | Shared spine: OCR, grading, artifact paths for all platform runners | AUTONOMOUS-FLEET-TESTING |
| `qa_suite.py` | Entry point: run every per-platform runner, one matrix | README |
| `atv_run.py` | Apple TV scenario runner (TT adaptation of atv_scenario) — refs missing `atv_install.sh`, `rtdb_join.py` | DEVICE-HARNESSES, AUTONOMOUS-FLEET-TESTING |
| `atv_scenario.py` | Apple TV scenario runner (AW original) — OCR + console diagnostics + assertions | README, DEVICE-HARNESSES, device-observation-harness |
| `atv_see.sh` | Capture ATV screen; refuse a frame OCR can't read (blind-instrument guard) | README, DEVICE-HARNESSES, AUTONOMOUS-FLEET-TESTING, device-observation-harness |
| `atv_report.py` | One table summarizing a day of Apple TV runs | DEVICE-HARNESSES |
| `ScreenOCR/main.swift` | Vision OCR CLI for screenshots (build → `/tmp/awocr`; atv_run expects `/tmp/tbocr`) | README, DEVICE-HARNESSES, device-observation-harness |
| `ios_run.py` | Real iPhone/iPad harness | AUTONOMOUS-FLEET-TESTING |
| `adb_run.py` | Real Android / Fire TV harness (with adb hazard handling) | AUTONOMOUS-FLEET-TESTING |
| `mac_run.py` | macOS harness cropping to the app window | AUTONOMOUS-FLEET-TESTING |
| `macapp.py` | Drive the Mac app by process, not by name | winbox.py only (no doc) |
| `web_run.py` | Web harness at 375px + 1440px with clip detection | AUTONOMOUS-FLEET-TESTING |
| `webdrive.py` | Minimal Chrome DevTools Protocol driver (type + click) | AUTONOMOUS-FLEET-TESTING |
| `devlease.py` | Cooperative device leases between agent sessions | README, AUTONOMOUS-FLEET-TESTING, 2 skills |
| `devreset.py` | Reset every device to known state and announce the test | AUTONOMOUS-FLEET-TESTING, autonomous-fleet-testing |
| `hook_coverage.py` | Report which surfaces each platform's env hooks can reach | README, AUTONOMOUS-FLEET-TESTING, autonomous-fleet-testing |
| `qa-sweep.sh` | Simulator QA sweep via env hooks (origin-bound: TT, 30 mentions) | README, DEVICE-HARNESSES, device-observation-harness |
| `throttled_range_server.py` | Range-capable HTTP server with bandwidth cap (adverse-network gate) | README, DEVICE-HARNESSES, device-observation-harness |
| `measure_start_times.sh` | Time-to-first-frame on Apple TV (origin-bound: AW films) | **UNREFERENCED** |

### B6. TV (Android TV / Fire TV / web-TV)
| Tool | What it does | Referenced by |
|---|---|---|
| `verify_tv_focus.sh` | Drive Android TV with remote keys, assert focus lands on content | README, DEVICE-HARNESSES, androidtv-compose-focus, device-observation-harness, TV backlog template |
| `tv_screenshots.sh` | Capture 1920×1080 Android TV store shots | README, DEVICE-HARNESSES, device-observation-harness, TV backlog template |
| `audit_fire_tv_gms.py` | Assert zero GMS/Firebase deps for Fire TV | README, DEVICE-HARNESSES, 2 skills |
| `audit_tv_g6.py` | TV-G6 audit: 64-bit + 16 KB page alignment | README, DEVICE-HARNESSES, 2 skills |
| `test_tv_focus.mjs` | Run real `tv.js` focus engine in a Node DOM shim | README, DEVICE-HARNESSES, 2 skills |
| `test_tv_ua.mjs` | Verify web-TV layer activates only on real TV user agents | README, DEVICE-HARNESSES, device-observation-harness |
| `tv_browser_tests.js` | In-browser web-TV acceptance suite (origin-bound header: AW) | DEVICE-HARNESSES, smarttv-web-app, TV backlog template |
| `test_packaged_origin.mjs` | Integrity checks for file:// packaged .ipk/.wgt | README, DEVICE-HARNESSES, tizen/webos submission docs |
| `devserve.py` | No-cache static server for TV/PWA dev | README, smarttv-web-app |
| `make_tv_banner.py` | Render TV banners at 1280×720 + 320×180 (origin-bound: AW) | TV backlog template only |

### B7. Store screenshots & branding
| Tool | What it does | Referenced by |
|---|---|---|
| `capture-screenshots.sh` | Env-hook-driven store screenshots, enforces free-features rule (REFERENCE IMPL, TT; 47 mentions) | APPLE-SUBMISSION-CLI, STORE-SCREENSHOTS |
| `mac_window_id.py` | CoreGraphics window id for window captures | STORE-SCREENSHOTS |
| `mac-screenshots.sh` | Frame Mac window onto a 16:10 canvas (origin-bound: AW) | README |
| `mac-shotset.sh` | Full Mac App Store screenshot set via launch hooks (origin-bound: AW) | apple-app-store-cli-submission |
| `render-app-icon.py` | tvOS icon + Top Shelf from a Méliès still (origin-bound: AW) | PROVENANCE only |

### B8. CI fleet (scheduled-workflow doctrine)
| Tool | What it does | Referenced by |
|---|---|---|
| `audit_workflow_health.py` | Find workflows broken while green (produced nothing, killed) | README, CI-FLEET, ci-fleet-engineering, workflow-health.yml, pulse_collect.py |
| `check_workflow_gates.py` | Assert split workflows' apply jobs are fully gated | README, DECISIONS, CI-FLEET, ci-fleet-engineering, product-pulse-dashboard, split-writer template, workflow-health.yml |
| `retry_infra_failures.py` | Re-run runs GitHub never started | README, CI-FLEET, ci-fleet-engineering, split-writer template, retry-infra-failures.yml |
| `catalog_delta.py` | Turn a catalog-mutating tool into a lock-free compute/apply split (refs missing `catalog_release.py`) | README, CI-FLEET, split-writer template |
| `sqlite_publish_guard.py` | Refuse to publish a shared SQLite index that lost rows | README, CI-FLEET, ci-fleet-engineering, split-writer template |
| `gh_dispatch.sh` | Retry `gh workflow run` against API 5xx (fire-and-forget) | README, CI-FLEET, ci-fleet-engineering, split-writer template |
| `gh_retry.sh` | Retry a load-bearing command with backoff | README, CI-FLEET, ci-fleet-engineering, split-writer template |
| `test_workflow_health_gate.py` | Test that the health auditor alerts only on unvoiced failure classes | **UNREFERENCED** |
| `ffmpeg_limits.py` | Cap ffmpeg threads on a laptop vs CI | **UNREFERENCED** (origin-bound: AW transcoding) |

### B9. Product pulse
| Tool | What it does | Referenced by |
|---|---|---|
| `pulse_collect.py` | 1642-line collector: stores, reviews, crashes, social, web mentions → `ops/pulse.json` (origin-bound: AW; refs missing `submit-amazon.py`, `youtube_refresh_token.py`) | README, PRODUCT-PULSE, product-pulse-dashboard, pulse.yml, pulse/index.html |
| `test_pulse_collect.py` | Tests readers report "can't read" rather than a confident zero | PRODUCT-PULSE |
| `test_pulse_charts.mjs` | Tests the pulse chart kit's proportionality | PRODUCT-PULSE |

### B10. Orphans
| Tool | What it does | Referenced by |
|---|---|---|
| `_http_fetch.mjs` | Node HTTP helper for `free_subtitles.py` (which is NOT in the repo) | **UNREFERENCED — orphan from AW subtitle pipeline** |

## C. Workflows, commands, hooks

### C1. `.github/workflows/` (active)
| Workflow | Trigger | One line |
|---|---|---|
| `android-build.yml` | PR on `android/**`, push main, tag `v*-android` | Android build + tests; tag → release bundle + Play upload |
| `appstore-build.yml` | manual (platform: all/mac/ios/tvos) | Cloud build/sign/upload Apple binaries on a released-macOS runner |
| `appstore-submit.yml` | manual (status/audit/list/upload/dry-run) | Open version, attach build, notes, screenshots, submit for review (comment refs missing `tools/capture-imessage-screenshots.sh`) |
| `play-release.yml` | manual (track / promote) | CI Android release to Play internal, promote same artifact later |
| `pulse.yml` | **daily cron 13:17 UTC + manual, contents: write** | Runs `pulse_collect.py` → commits `ops/pulse.json` (AW-branded; NOT dormant) |
| `retry-infra-failures.yml` | manual (cron commented: dormant) | Re-run runner-allocation failures |
| `workflow-health.yml` | manual (cron commented: dormant) | Health auditor + gate check |

### C2. Staged workflows (copy into `.github/workflows/` to enable)
| File | One line |
|---|---|
| `docs/windows/workflows/windows-build.yml` | Build Avalonia app + headless PNG snapshots on windows-latest |
| `docs/windows/workflows/windows-repl.yml` | "The remote Windows box": run tests/PowerShell on windows-latest from the CLI |
| `docs/windows/workflows/windows-store.yml` | Package MSIX + submit to Microsoft Store |
| `docs/windows/workflows/windows-store-addons.yml` | Verify Store add-on product ids (TT "Club" specific) |
| `docs/templates/split-writer-workflow-template.yml` | Template for a scheduled data-mutating workflow (compute/apply split) |

### C3. Slash commands (`.claude/commands/`)
| Command | One line |
|---|---|
| `/decision` | Append a numbered DECISIONS.md entry (platform tags `[SHARED]/[WEB]/[iOS]` are stale) |
| `/milestone` | Close the SCRATCHPAD milestone, run learning-orientation test, log session |
| `/status` | Summarize milestone, next actions, latest decision (parity line says "web and iOS" — stale) |
| `/KUI:a11y` | WCAG 2.2 AA audit (vendored from Killer-UI) |
| `/KUI:brand` | Brand identity system |
| `/KUI:code` | Design → accessible frontend code |
| `/KUI:darkmode` | Dark-mode audit + fixes |
| `/KUI:figma` | Figma spec generation |
| `/KUI:review` | Full design critique |
| `/KUI:screen` | Platform-native screen design |
| `/KUI:system` | Design system generation |
| `/KUI:trends` | Design trend research |

### C4. Hooks & settings
| Item | One line |
|---|---|
| `.claude/hooks/session-start.sh` (SessionStart) | Echoes CLAUDE.md + SCRATCHPAD "Current State". **Bugs:** heading case mismatch (`## Current state` in file) and `head -n -1` fails on macOS → state block never prints; re-injects CLAUDE.md that Claude Code already loads |
| `.claude/settings.json` permissions | Allowlist of read-only shell, git read/add/restore, local server, gradle, simctl, xcodebuild build/test, adb, `open`, and the two skill scripts |

## D. Docs (every .md outside `.claude/`)

| Doc | Lines | Purpose | Notes |
|---|---|---|---|
| `README.md` | 613 | Template overview, quick start, structure, skills bundled, what the template encodes | Skills table says "~12" dup pairs (14 actual) |
| `CLAUDE.md` | 753 | Project context + skill trigger table + per-platform conventions | Missing triggers for 7 skills; Design.swift ref broken |
| `CONTRIBUTING.md` | 82 | Contribution rules for the multi-platform template | Overlaps CLAUDE.md "Standing instructions" |
| `DECISIONS.md` | 1209 | 52 ADRs (001–052) | Cites 055/092/093 internally; AUTONOMOUS-LOOPS says roll at ~120 KB |
| `PARITY.md` | 281 | Feature parity matrix template | Refs `WINDOWS-PARITY.md` (not present) |
| `SCRATCHPAD.md` | 172 | Milestones, current state, session log | Heading "Current state" breaks hook; refs ARCHIVE.md (to be created) |
| `DEEP_LINKS.md` | 123 | Cross-platform URL contract | |
| `.well-known/README.md` | 82 | Where AASA / assetlinks go | Folder has no sample files |
| `apple/README.md` | 123 | Universal Apple target setup | |
| `apple/Core/Models/README.md` | 21 | Models vs Store boundary | |
| `apple/iOS/Components/README.md` | 19 | When a view graduates to a component | |
| `apple/iOS/Views/README.md` | 33 | One root view per feature | |
| `apple/Resources/Fonts/README.md` | 20 | Adding brand fonts | |
| `android/README.md` | 102 | Android module setup | |
| `windows/README.md` | 95 | Windows scaffold adoption steps | |
| `windows/AppName.App/Assets/Windows/README.md` | 18 | Required MSIX logo tiles | |
| `assets/README.md` | 55 | Shared static assets convention | Folder otherwise empty |
| `branding/README.md` | 77 | Brand master files convention | |
| `docs/AUTONOMOUS-LOOPS.md` | 175 | Loop discipline: agent is never the tester | Overlaps `autonomous-loop-cadence` skill |
| `docs/AUTONOMOUS-FLEET-TESTING.md` | 264 | Real-device fleet architecture + checklist | Same outline as `autonomous-fleet-testing` skill |
| `docs/DEVICE-HARNESSES.md` | 216 | Per-platform harness catalog + instrument honesty | Overlaps AUTONOMOUS-FLEET-TESTING (Windows, blind instrument, hygiene); doesn't link back to it |
| `docs/CI-FLEET.md` | 226 | Scheduled-workflow doctrine | `ci-fleet-engineering` skill is a 53-line pointer to it (good split) |
| `docs/CLOUD-SUBMISSION.md` | 233 | Cloud build + signing + Play pathway runbook | Overlaps `cloud-appstore-submission` rules 1–8 nearly 1:1 |
| `docs/APPLE-SUBMISSION-CLI.md` | 142 | Last mile: version, screenshots, submit via CLI | Overlaps `apple-app-store-cli-submission` "last mile"; no cross-link with CLOUD-SUBMISSION |
| `docs/MEDIA-PLAYBACK.md` | 141 | Streaming + captions doctrine | Declared split with `resilient-media-streaming` |
| `docs/PRODUCT-PULSE.md` | 97 | Pulse reference | Declared split with `product-pulse-dashboard` |
| `docs/PROVENANCE.md` | 94 | Coverage map of where lessons live / what was excluded | Mentions excluded `macos-creation-studio-engine` (intentional) |
| `docs/TV-PLATFORMS.md` | 488 | Smart-TV viability, fees, store process | Overlaps `smart-tv-platform-expansion` (338 lines); refs `docs/TV-DESIGN.md`, `docs/TV-PLATFORM-BACKLOG.md`, `docs/MULTIPLATFORM-PLAN.md` (none exist); "Decision 047" wrong |
| `docs/TVOS-PLAYBOOK.md` | 665 | Full tvOS playbook | AW-branded, "tvOS 17+"; overlaps `tvos-platform-patterns` + `references/production-deep-dive.md`; collides with CLAUDE.md's `docs/tvos-playbook.md` on case-insensitive FS |
| `docs/research/social-clip-creation.md` | 485 | Research: social clips from archival film | AW port |
| `docs/research/sync-architecture.md` | 85 | Research: watch-state sync | AW port; overlaps per-ecosystem-sync-islands |
| `docs/research/tv-design-reference.md` | 220 | UHF / Channels / Apple TV design study | AW port; overlaps ten-foot-detail-design |
| `docs/runbooks/cloudkit-setup.md` | 90 | CloudKit + Sign in with Apple setup | AW-specific (#11, Decision 022) |
| `docs/runbooks/data-recovery.md` | 86 | Recover clobbered catalog release | AW-specific; refs missing tools + workflows |
| `docs/runbooks/google-oauth-setup.md` | 60 | Google Drive appData sync OAuth | AW-specific; refs missing `js/drivesync.js` |
| `docs/runbooks/tvos-top-shelf-setup.md` | 207 | Top Shelf extension setup | AW-specific paths |
| `docs/store/IAP-RELEASE-CHOREOGRAPHY.md` | 123 | Multi-store IAP launch sequencing | TT-derived; refs `windows-store-addons.yml` (staged) |
| `docs/store/IAP-TROUBLESHOOTING.md` | 64 | Empty-paywall diagnosis | TT-specific |
| `docs/store/play-api-key-setup.md` | 159 | Play service-account key incl. org-policy block | Overlaps CLOUD-SUBMISSION §5 |
| `docs/store/PLAY-DASHBOARD-RECOMMENDATIONS.md` | 45 | Read Play recommendations as one finding | |
| `docs/store/STORE-SCREENSHOTS.md` | 203 | Screenshot set + capture playbook | TT-derived (17 mentions); overlaps store-submission-playbook + app-store-screenshots skill |
| `docs/store/tizen-submission.md` | 96 | Samsung submission pack | "Decision 047 §7.3" wrong |
| `docs/store/webos-submission.md` | 148 | LG submission pack | |
| `docs/templates/PLATFORM-DESIGN-template.md` | 70 | Index + shared shape for binding design docs | |
| `docs/templates/IOS-DESIGN-template.md` | 353 | iOS binding design doc seed | |
| `docs/templates/MACOS-DESIGN-template.md` | 286 | macOS seed | |
| `docs/templates/TVOS-DESIGN-template.md` | 267 | tvOS seed | |
| `docs/templates/WEB-DESIGN-template.md` | 152 | Web seed | |
| `docs/templates/ANDROID-DESIGN-template.md` | 160 | Android seed | |
| `docs/templates/WINDOWS-DESIGN-template.md` | 297 | Windows seed | **Not genericized** ("Tidbits Trivia"); refs WINDOWS-RESEARCH.md, PLAYBOOK.md, run_golden.sh |
| `docs/templates/TV-DESIGN-template.md` | 317 | Non-Apple TV binding doc | **Not genericized** ("Archive Watch") |
| `docs/templates/TV-PLATFORM-BACKLOG-template.md` | 429 | TV implementation backlog | **Not genericized** (AW, dated 2026-08-03) |
| `docs/templates/DATA-CONTRACT-template.md` | 109 | Shared data contract seed | |
| `docs/templates/TRADE-DESIGN-template.md` | 221 | Trading/P2P design seed | |
| `docs/templates/OWNER-PLAYBOOK-template.md` | 421 | Owner launch playbook | **Not a template** — literal TT launch status 2026-08-04; refs ~15 missing files |
| `docs/windows/WINDOWS-PLAYBOOK.md` | 370 | Build/test/ship Windows from a Mac | Overlaps windows/README + windows-production-gotchas |
| `docs/windows/WINDOWS-STORE-SUBMISSION.md` | 441 | Microsoft Store CLI submission | |
| `docs/windows/APPLE-SIGNIN-WINDOWS.md` | 140 | Sign in with Apple on Windows via HTTPS bounce | Status log of one app |

### D1. Overlap clusters (candidates to consolidate or cross-link)
1. **Device testing** — `DEVICE-HARNESSES.md` (per-platform recipes) + `AUTONOMOUS-FLEET-TESTING.md` (architecture) + skills `autonomous-fleet-testing` (same outline as the doc), `device-observation-harness`, `concurrent-agent-device-leases`. Both docs cover Windows, the blind instrument, fleet hygiene. Only one direction is linked.
2. **Apple submission** — `CLOUD-SUBMISSION.md` (build/sign) + `APPLE-SUBMISSION-CLI.md` (submit) + skills `cloud-appstore-submission` (rules ≈ doc sections) + `apple-app-store-cli-submission` (AW ref impl covering both) + `store-submission-playbook` + `STORE-SCREENSHOTS.md`. The two docs don't reference each other.
3. **tvOS** — `TVOS-PLAYBOOK.md` (AW, 665 lines) vs `tvos-platform-patterns` + its `references/production-deep-dive.md` (228 lines, "seed for docs/tvos-playbook.md") vs `TVOS-DESIGN-template.md`. Three sources for the same rules, one stale on OS floor.
4. **Smart TV** — `TV-PLATFORMS.md` vs `smart-tv-platform-expansion` vs `TV-DESIGN-template` / `TV-PLATFORM-BACKLOG-template` vs `ten-foot-detail-design` vs `research/tv-design-reference.md`; plus 3 ref-impl skills.
5. **Windows** — `windows/README.md`, `WINDOWS-PLAYBOOK.md`, `WINDOWS-STORE-SUBMISSION.md`, `windows-production-gotchas`, CLAUDE.md Windows section.
6. **Play** — `CLOUD-SUBMISSION.md` §5 vs `play-api-key-setup.md` vs `play-cli-submission`.
7. **Loops** — `AUTONOMOUS-LOOPS.md` vs `autonomous-loop-cadence`.
8. **Healthy splits (keep as teaching examples)** — CI-FLEET / ci-fleet-engineering; MEDIA-PLAYBACK / resilient-media-streaming; PRODUCT-PULSE / product-pulse-dashboard: each skill states "the reasoning is here, the reference is there".

## E. Broken cross-references

### E1. Real breaks (should be fixed)
| Where | Reference | Status |
|---|---|---|
| CLAUDE.md (design tokens, lines ~498–536) | `Design.swift` in Apple Core | Not in `apple/Core/` (only Networking/APIClient.swift, Store/AppStore.swift, Models/README) |
| CLAUDE.md, CONTRIBUTING, windows docs | `gh workflow run windows-repl.yml` / `windows-store.yml` | Live in `docs/windows/workflows/`, not `.github/workflows/` (windows/README says to copy; CLAUDE.md doesn't) |
| CLAUDE.md tvOS bullet; tvos-platform-patterns | "bootstrap `docs/tvos-playbook.md`" | `docs/TVOS-PLAYBOOK.md` already exists → same path on case-insensitive macOS |
| `.github/workflows/appstore-submit.yml`, `docs/APPLE-SUBMISSION-CLI.md` | `tools/capture-imessage-screenshots.sh` | Missing |
| `roku-brightscript-app` | `tools/roku_design_lint.py` | Missing |
| `tools/atv_run.py` | `tools/atv_install.sh`, `tools/rtdb_join.py` | Missing |
| `tools/pulse_collect.py` | `tools/submit-amazon.py`, `tools/youtube_refresh_token.py` | Missing |
| `tools/catalog_delta.py`, `docs/runbooks/data-recovery.md` | `tools/catalog_release.py`, `tools/remediate_catalog.py`, workflows `publish-db.yml`, `omdb-backfill.yml`, `wikidata-posters.yml`, `wikipedia-synopsis.yml` | Missing (AW pipeline, deliberately excluded per PROVENANCE) |
| `web-catalog-data-layer` | `publish-db.yml`, `catalog-index.json`, `/watch/` | AW-only |
| `tools/_http_fetch.mjs` | `free_subtitles.py` | Missing |
| `docs/runbooks/google-oauth-setup.md` | `js/drivesync.js` | Missing |
| `docs/runbooks/cloudkit-setup.md` | `Services/CloudKitSyncService.swift` | Missing |
| `docs/runbooks/tvos-top-shelf-setup.md` | `AppName/AppName/Services/TopShelfSnapshot.swift` etc. | Missing |
| `docs/templates/TV-PLATFORM-BACKLOG-template.md` | `docs/tizen-submission.md`, `docs/webos-submission.md` | Actually at `docs/store/…` |
| `docs/TV-PLATFORMS.md` | `docs/MULTIPLATFORM-PLAN.md` | Missing, not produced by any template |
| `docs/templates/OWNER-PLAYBOOK-template.md` | `tools/gc_achievements.py`, `tools/publish_daily.py`, `tools/send_reminders.py`, `tools/branding/make_tvos_icon.py`, `docs/CLUB-OWNER-PLAYBOOK.md`, `docs/GAME-CENTER-SETUP.md`, `docs/LEMONSQUEEZY-REVIEW-REPLY.md`, `MONETIZATION.md`, `js/engine.js`, `js/push.js`, `js/store.js`, `.github/workflows/reminders.yml` | Missing (TT files) |
| `docs/templates/WINDOWS-DESIGN-template.md` | `WINDOWS-RESEARCH.md`, `PLAYBOOK.md`, `run_golden.sh`, `firebase.js` | Missing (TT files) |
| `docs/store/STORE-SCREENSHOTS.md` | `Core/Store/ScreenshotQuestions.swift`, `branding/store-screenshots/windows/` | Missing (TT files) |
| `app-store-screenshots` | companion skill `ios-marketing-capture` | Not vendored (external install instruction) |
| `.claude/commands/status.md`, `decision.md` | "web and iOS" / `[SHARED]/[WEB]/[iOS]` | Stale platform set |
| Many docs/tools/workflows | Decision 053–107; Decision 045/047/048/015/018/022/028/029 in wrong sense | Origin-repo numbering (see §0 item 5) |

### E2. Expected-to-be-created (not bugs, but a teaching README should say so)
`docs/DATA-CONTRACT.md`, `docs/{iOS,macOS,tvOS,WEB,ANDROID}-DESIGN.md` (or root-level — CLAUDE.md/CONTRIBUTING/PARITY say root names, templates say `docs/`), `docs/TRADE-DESIGN.md`, `docs/TV-DESIGN.md`, `docs/TV-PLATFORM-BACKLOG.md`, `docs/decisions/` (DECISIONS archive; created at ~120 KB roll), `ARCHIVE.md` (SCRATCHPAD overflow), `WINDOWS-PARITY.md`, `ops/pulse.json` (pulse output), `.well-known/apple-app-site-association` + `assetlinks.json`, the `.xcodeproj` at root, `assets/data/`, `assets/fonts/`. Note the path inconsistency: CLAUDE.md "When to create a binding design doc" names `tvOS-DESIGN.md` etc. without a directory, while every template writes to `docs/<X>-DESIGN.md`.
