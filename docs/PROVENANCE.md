# Provenance

Every lesson in this template was paid for in a real app. This page
records which app, where the lesson lives here now, and what was left
behind on purpose, so the next audit knows what "complete" means and
nobody rediscovers an exclusion.

**Audits.**

- **2026-08-24**, the Universal generation: Archive Watch (decisions
  through 095), Tidbits Trivia (56), Quint (27), BOBA Playbook (frozen
  2026-06-30), Bsky Dreams (through 2026-08-24).
- **2026-08-26**, BOBA re-audit: the earlier assumption that BOBA's late
  cycle was already folded in was wrong. Nine skills, the TRADE-DESIGN
  template and Decisions 044 to 052 came out of it.
- **2026-09-30**, Archive Watch decisions 096 to 158, plus everything
  since the September 1 to 9 ports: the real-device harness, Pulse,
  store tooling, floors by hardware, parity practice, and the data
  contract. The full work queue is
  `docs/maintaining/ARCHIVE-WATCH-GAP-AUDIT-2026-09-30.md`, and the
  record of the reorganization it drove is
  `docs/maintaining/RESTRUCTURE-PLAN.md`.
- **2026-10-22**, Archive Watch decisions 159 to 168 and everything since
  the 09-30 audit, before Ear Drama (an audio app on the same source) was
  started from this template. It also built three skills the 09-30 audit
  recommended and never landed. The record is
  `docs/maintaining/ARCHIVE-WATCH-GAP-AUDIT-2026-10-22.md`.

## Coverage: domain → home in this template

| Domain | Lives in |
|---|---|
| Methodology (learning orientation, shipping discipline, parity, design docs, decision log) | Quint-era skills + `AGENTS.md` (unchanged core) |
| CI fleet engineering (locks, budgets, guards, sweeper, auditor, alert hygiene) | `docs/CI-FLEET.md`, `ci-fleet-engineering` skill, `tools/` guardian cluster, guardian workflows (dormant), split-writer template, Decisions 030–031 |
| Autonomous loop discipline | `docs/AUTONOMOUS-LOOPS.md`, `autonomous-loop-cadence` skill, Decision 032 |
| Device observation harnesses (all platforms) | `docs/DEVICE-HARNESSES.md`, `device-observation-harness` skill, `tools/` harness cluster |
| tvOS (focus, ten-foot, playback surfaces, Top Shelf) | `docs/TVOS-PLAYBOOK.md`, `tvos-platform-patterns` skill, `docs/runbooks/tvos-top-shelf-setup.md`, TVOS-DESIGN template |
| Smart TV beyond Apple (Android TV / Fire TV / webOS / Tizen / Cast / AirPlay) | `docs/TV-PLATFORMS.md`, TV-DESIGN + TV-BACKLOG templates, `smart-tv-platform-expansion` → `androidtv-compose-focus` / `smarttv-web-app` skills, `tv.js`/`tv.css`/`cast/`, `tv/build-tv-packages.sh`, `docs/store/{webos,tizen}-submission.md`, Decision 028 |
| Media streaming + captions (loader invariants, AirPlay/Cast conflicts, HLS shapes, live captions, subtitle judging) | `docs/MEDIA-PLAYBACK.md` (the distillation), `resilient-media-streaming` skill (the core pattern) |
| Windows / MSIX | `docs/windows/`, WINDOWS-DESIGN template, `tools/stamp_msix_version.py`, reference workflows, Decision 029 |
| Store submission (Apple cloud default, Play CLI, screenshots, IAP) | `docs/CLOUD-SUBMISSION.md`, `cloud-appstore-submission` + `play-cli-submission` + `store-submission-playbook` skills, `tools/submit-*` + `asc_*` cluster, `docs/store/` (IAP troubleshooting + choreography, screenshot rules, Play dashboard recommendations, Play API key) |
| Sync (CloudKit query-free pattern, Drive App Data, history-vs-progress) | `per-ecosystem-sync-islands` skill, `docs/runbooks/cloudkit-setup.md`, `docs/runbooks/google-oauth-setup.md`, `docs/research/sync-architecture.md` |
| Shared data plane (SQLite delivery, CORS/Range matrix, additive evolution, forwarding addresses, marker/evidence rules) | `shared-data-plane-contract` + `web-catalog-data-layer` skills, DATA-CONTRACT template, `docs/CI-FLEET.md` §7, Decision 034 |
| Data recovery + git forensics | `docs/runbooks/data-recovery.md` |
| Design research (ten-foot benchmarks, social video specs) | `docs/research/` |
| Icon/branding pipeline | `tools/render-app-icon.py`, `branding/` |
| Algorithmic feeds / discovery ranking (multi-source merge, values pass, seen-dedup + bypass) | `values-based-feed-ranking` skill, Decision 043 |
| Third-party page content (CORS proxy chains, reader-mode extraction, link previews, article-language detection) | `web-content-extraction` skill, cross-ref in `web-platform-patterns` |
| iOS Share Extension (App Group handoff, responder-chain open, rejected-approach table, web Shortcut counterpart) | `ios-share-extension` skill |
| iOS production additions from Bsky Dreams (synchronized-group build gotcha, recycled-cell image loading, NetworkMonitor + SwiftData fallback wiring, UIGestureRecognizer-subclass touch capture, AVKit animation crash, haptics taxonomy) | `ios-production-gotchas` skill (amended), AGENTS.md §Shared design system (haptics), IOS-DESIGN template §4.7–4.8, Decisions 040–042 |
| Provenance-honest market data (signal hierarchy, vanish-inference sold history, match-precision gates, audit-by-pattern, dead-affordance rule) | `provenance-honest-market-data` skill, Decisions 044 + 050 |
| Canonical entity identity (one ID/one asset, single-source composite formula, collision audits, lockstep migration, md5 byte guard) | `canonical-entity-identity` + `image-cdn-discipline` skills, Decision 046 |
| Two-tier image CDN (thumbs/full, helper-per-platform, no images in git, dev-domain-isn't-production, cache sizing) | `image-cdn-discipline` skill |
| Hosted backend split (auth+user-data DB only, static catalog, CDN media, worker fleet, RLS roles, username/handle + banned-words, account deletion, push dispatcher) | `zero-cost-hosted-backend` skill, Decision 047 (reconciles 015) |
| On-device camera recognition (fingerprint-primary/OCR-confirm, silent-wrong principle, evidence aggregation, CLI mirror + pixel parity, capture traps) | `camera-recognition-pipeline` skill, `ios-production-gotchas` §Camera + capture |
| Marketplace-adjacent features (never-touch-money, pure introduction, §1.2 minimum controls, DSA geo-block, risk-acceptance table, ToS clauses) | `marketplace-adjacent-design` skill, `docs/templates/TRADE-DESIGN-template.md`, Decision 049 |
| Third-party dependency revocation (prevention posture + the compliant removal loop, provenance backfill, frozen legacy data) | `third-party-revocation-resilience` skill, Decision 051 |
| Monetizing around IP you don't own (license-then-monetize, the own-engineering line, entitlement architecture, decision gates) | `third-party-ip-monetization` skill |
| Two-agent handoff (single-file channel, directional outboxes, ownership lists, provenance-cited deliveries) | `two-agent-handoff` skill |
| Next-OS additive adoption (dual runtime+compile gates, the SDK-conditional flag, Compat wrapper, beta-Xcode submit trap) | `cloud-appstore-submission` Rule 6 (amended), Decision 048 |
| Android release symbols + ML Kit (embed-in-AAB, zip -D, jarsigner; unbundled-vs-bundled) | `android-production-gotchas` §Release engineering, `play-cli-submission` Rule 9 |
| Display vocabulary as a render-layer contract; word-prefix search; image-first sort; two-phase catalog load | `shared-data-plane-contract` §Client consumption rules, DATA-CONTRACT template §5.5, Decision 052 |
| Teaching-surface platform asymmetry (walkthroughs iOS-only; documented rejections elsewhere) | `universal-feature-states` (amended), PARITY.md §3b |
| Autonomous-loop pre-push checklist (import sweeps, stale call sites, artifact sweeps, deprecation signatures) | `docs/AUTONOMOUS-LOOPS.md` §10 |
| Real-device testing: bench manifest and roles, whole-run leases, leave-as-found teardown, stale-proof and power-aware capture, window-only Mac capture, Roku and web-TV glass tools, verdict doctrine, audit ledgers | `docs/AUTONOMOUS-FLEET-TESTING.md` (method), `docs/DEVICE-HARNESSES.md` (catalog), `tools/bench.py` + runners, `docs/templates/DEVICE-AUDIT-LEDGER-template.md`, `autonomous-fleet-testing` / `device-observation-harness` / `concurrent-agent-device-leases` skills, `docs/maintaining/HARNESS-PORT-2026-09-30.md` |
| Launch doors in every starter (start tab, start item, mute, door seconds; debug-only) | `apple/Core/Store/LaunchDoors.swift`, `android/.../navigation/LaunchDoors.kt`, `windows/AppName.App/LaunchHooks.cs`, `js/app.js`, `tools/app_config.py`, `tools/hook_coverage.py` |
| Product Pulse (collector, charts, look rules, reader honesty, privacy counting, store traps) | `docs/PRODUCT-PULSE.md`, `pulse/`, `tools/pulse_*`, `product-pulse-dashboard` + `store-metrics-pipelines` skills, `docs/maintaining/PULSE-PORT-2026-09-30.md` |
| Platform floors by hardware reach, held by CI tests; capability tiers | `docs/path/03-going-native.md`, `multiplatform-expansion-method` Step 3b, `tools/test_ios_floor.py` / `test_tvos_floor.py`, Decision 004 amendment, PARITY "Oldest hardware served" |
| Apple ship from the CLI across three platforms; Play notes cap and retries | `tools/asc_release.py`, `appstore-build.yml`, `appstore-submit.yml`, `docs/CLOUD-SUBMISSION.md`, `docs/APPLE-SUBMISSION-CLI.md`, `play-cli-submission` |
| One version number everywhere | `AppVersion.xcconfig`, `tools/test_version_contract.py`, `tools/stamp_msix_version.py` |
| Workflow auditor that never fails, gate checker | `tools/audit_workflow_health.py`, `tools/report_workflow_health.py`, `tools/check_workflow_gates.py`, `docs/CI-FLEET.md` §6 and §10 |
| Parity practice (mechanical guards, port ledgers, maintenance protocol, doc-layer parity) | `cross-platform-parity-discipline`, `PARITY.md`, `docs/templates/PORT-PARITY-LEDGER-template.md`, `FEATURE-DESIGN-template.md` |
| Data contract as a test; projection ladder; field tiers; named filters | `shared-data-plane-contract`, `docs/templates/DATA-CONTRACT-template.md` |
| State in the link; the web bridges the sync islands; $0 watch party; one free Worker of adapters | `DEEP_LINKS.md`, `per-ecosystem-sync-islands`, `cross-platform-multiplayer`, `zero-cost-hosted-backend`, `pulse/worker-example/` |
| Engineering disciplines and loop working style | `docs/ENGINEERING-PROCESS.md`, `docs/AUTONOMOUS-LOOPS.md` |
| iPad regular-width rules | `docs/templates/IPAD-DESIGN-template.md` |
| Evidence-gated curation of a catalog you did not author (a claim a reader can open, uploader's word is not evidence, restore by evidence, never recommended always findable, computed date lines, provenance and accuracy, cleared matches scrub, versions never the default, per-work judgment, the reconcile trap) | `evidence-gated-catalog-curation` skill (AW 027, 124, 137, 140, 149-152, 156-159, 163, 168) |
| Reading archive.org (scrape vs search, throttled is not empty, main-host connection limit, honest UA, upload dates, many-works items, private files, derivatives, storage nodes, CORS) | `internet-archive-source` skill |
| Many works in one source item (`<item>@<token>` ids, stored `sourceID`, placement by evidence) and merged ids that keep their public URL | `canonical-entity-identity` (AW 166-168, Search Console fix) |
| On-device capture and live broadcast (own the protocol, prove it locally, capture clocks and per-voice sync, link adaptation, the host in the show) | `live-capture-and-broadcast` skill (AW 127, 129, 132, 138, 160, 161) |
| Vertical social video | `social-video-teaser-craft` skill (vendored from the global skill) |
| Samsung 2022 floor (Chromium 85), the exit question, Tizen player traps, retail-set inspection | `js/compat.js`, `tools/test_tv_compat.py`, `tv.js` `askToExit`, `tools/tv_inspect.mjs` + `tv_press.mjs` + `tv_walk.mjs`, `docs/store/tizen-submission.md` §2b, `docs/DEVICE-HARNESSES.md` "Retail Tizen" (AW 162) |
| iPhone Duo, App Store creative assets, Asset Library API, public-Xcode rule | `ios-production-gotchas`, `store-submission-playbook`, `tools/asc_asset_library.py` + `asc_stage_assets.py` |
| Push races, durable failure memory, ingest gated before publish, fair queues | `docs/CI-FLEET.md` §2-3, `ci-fleet-engineering`, `pulse.yml` and `play-release.yml` retry loops |
| Standing rules on words and AI in the product | `learning-orientation-design`, `mobile-first-density-design`, `AGENTS.md` Standing instructions |

## Deliberate exclusions (do not "rediscover" these)

- **Archive Watch's Watch Together Studio and Creation Studio engines**
  (live broadcast, camera compositing, clip editing): app-specific. The
  generic halves (own a small documented protocol, prove it against a
  local server with a wrong-key control) are noted in
  `docs/ENGINEERING-PROCESS.md`.
- **Archive Watch's rights-audit specifics and its catalog, subtitle and
  poster pipelines** (about forty workflows): inseparable from
  archive.org. The patterns are in `docs/CI-FLEET.md` and the data-plane
  skill.
- **A social posting pipeline**: not ported. The `social-video-teaser-craft`
  skill was vendored on 2026-10-22; the pipeline itself (AW's
  `docs/SOCIAL-PROGRAM.md`, Decision 120) stays with Archive Watch.
- **Archive Watch's catalog pipeline** (~150 tools: discovery, enrichment,
  rights audit, TV spines, covers, subtitles sourcing): inseparable from
  that app's data model. Its archive.org habits and curation rules are now
  skills (`internet-archive-source`, `evidence-gated-catalog-curation`); an
  app on the same source copies tools from Archive Watch by name. The PATTERNS it proved are here
  (CI-FLEET, marker rules, additive merges); the tools are not. Worked
  examples: Archive-Watch `tools/` + `docs/decisions/`.
- **`macos-creation-studio-engine` skill**: a Mac video-editor engine for
  one app. Its two reusable AVFoundation truths (one-model-to-composition;
  the two-pass grade→overlay rule) are noted in the MACOS-DESIGN template
  lineage; build the rest per app from `docs/research/`
  video-clipping material in Archive Watch if ever needed.
- **Tidbits' game/corpus/multiplayer internals**: the generic halves
  already live in `cross-platform-multiplayer` / `-determinism` /
  `content-corpus-derivation` (Quint era).
- **App-specific binding design docs** (tvOS-DESIGN etc. of each app):
  the template ships SEEDS in `docs/templates/`; the filled-in docs stay
  with their apps.
- **Duplicate framework skills.** On 2026-09-30, twelve legacy copies that
  matched their newer twins were deleted. `ios-security` and
  `metrickit-diagnostics` remain because their content differs (see
  `.claude/skills/README.md`).
- **BOBA's uncommitted skill dump + stray store artifacts**: superseded
  as artifacts. (The 2026-08-24 claim that BOBA's committed lessons were
  "already folded in" was wrong, and was corrected by the 2026-08-26 re-audit
  above. What remains deliberately excluded: BOBA's card-catalog
  pipeline itself, the Radish-specific tooling, the practice-battle
  engine, and its filled-in binding design docs, which are app-specific; their
  generic halves now live in the skills listed above.)

## The upstreaming rule

When a session in any app repo produces a template-worthy lesson: (1) fix
it in the app, (2) upstream the GENERIC form here in the same working
session (a doc section, a skill trigger, a tool, or a seed Decision), and
(3) add or update the row above. Lessons trapped in app-local docs are the
drift this file exists to catch: Tidbits wrote 20 docs and zero skills in
its biggest month, and that gap took an audit to find.
