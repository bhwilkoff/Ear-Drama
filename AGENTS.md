# [APP NAME]: Agent Project Context

## Why we build

Every feature in this app is built in service of human learning and
growth, not to replace thinking, but to deepen it. At each decision
point, ask: does this design invite the user to engage more fully,
think more critically, or connect more meaningfully? If a feature
makes a person more passive, reconsider it. If it opens a door to
curiosity or collaboration, prioritize it. The goal is never a slick
product. It is a tool that makes someone more human.

**Before implementing any feature**, invoke the
`learning-orientation-design` skill: the four-question test that
operationalizes this paragraph, after its three questions of the idea
(should it exist, who does it touch, what will people learn or stop
learning). The human-facing version of this section is
`docs/path/00-why-we-build.md`.

This template builds **human-shaped software**: it takes the mechanical
work off people's hands and leaves them the learning. Learning is the
frame three ways: the people who use the app, the owner as builder
(deciding, judging and using stay theirs; propose, don't decide), and
the owner as student of the method. Every round makes three moves:
**write** (values, features, and feedback live here, where you read
them), **play** (the owner uses and probes what you built on real
devices; you are never the tester), **publish** (it goes out for other
people to play with, and their feedback drives the next round).

---

## How we build

The method lives in **skills** in `.claude/skills/` (catalog:
`.claude/skills/README.md`). Don't re-derive a pattern; invoke the skill
when its trigger matches. This file is every agent's one source: Claude
Code imports it in `CLAUDE.md`, Gemini CLI in `GEMINI.md`, and
Antigravity reads it directly but cuts at 24,000 bytes, so rules and
values stay here and platform detail lives in the docs linked below.
`.agents/skills/` (Gemini CLI, Antigravity) holds the three skills a
learner asks for by name and a pointer skill, `template-skills`. With no
skill mechanism, open `.claude/skills/<name>/SKILL.md` and follow it.
Sources: `docs/research/gemini-and-other-agents.md`. Rows follow the
`docs/path/` stages.

| When | Skill |
|---|---|
| **00 Why we build** | |
| Proposing or reviewing ANY feature, especially AI or automation | `learning-orientation-design` |
| Starting any feature change | `feature-shipping-discipline` |
| Logging an architecture decision | `architectural-decision-log` |
| UI / IA work once a platform has a design doc | `binding-design-doc-discipline` |
| **01 First prototype** | |
| Any web UI, routing, data, offline or image work | `web-platform-patterns` |
| Designing any view (any platform) | `mobile-first-density-design` + `native-platform-first` |
| Adding a list / grid / sheet / shelf | `universal-feature-states` |
| A signed-in home, dashboard, account page, or role-based view | `learner-experience-design` |
| **02 Shape of an app** | |
| Shipping a feature on ANY platform, auditing a port, mirroring a rule across languages | `cross-platform-parity-discipline` |
| Shared data the clients consume | `shared-data-plane-contract` (worked example: `web-catalog-data-layer`) |
| Stable entity IDs, or an ID formula/migration | `canonical-entity-identity` |
| Serving a catalog's images/media | `image-cdn-discipline` |
| Sync, sign-in, progress across devices | `per-ecosystem-sync-islands` |
| Users see EACH OTHER'S data (profiles, roles, moderation) | `zero-cost-hosted-backend` (vs `per-ecosystem-sync-islands`, Decision 047) |
| Deriving a shipped corpus from a messy source | `content-corpus-derivation` |
| Deciding what a catalog you did not author may show, hide, recommend, or say (rights, provenance, wrong matches, versions) | `evidence-gated-catalog-curation` |
| Reading archive.org (enumerating, metadata, picking files, streaming) | `internet-archive-source` |
| **03 Going native** | |
| Planning a new platform, or choosing a deployment floor | `multiplatform-expansion-method` |
| The app still wears the template's placeholder look | `make-it-look-like-itself` |
| iOS / iPadOS symptom (see `docs/platforms/apple.md`) | `ios-production-gotchas` |
| Any Mac shell / window / player work | `macos-platform-patterns` (worked example: `macos-native-app-shell`) |
| Any tvOS UI / focus / persistence work | `tvos-platform-patterns` |
| Any Android work | `android-production-gotchas` |
| Android TV / Fire TV / webOS / Tizen / Cast / Roku | `smart-tv-platform-expansion`, then `androidtv-compose-focus` / `smarttv-web-app` / `roku-brightscript-app` |
| A TV Detail / Series / Search screen on any ten-foot platform | `ten-foot-detail-design` |
| An iOS share-sheet target (Share Extension) | `ios-share-extension` |
| Any Windows work | `windows-production-gotchas` |
| **04 Seeing it work** | |
| A fix that can't be verified from logs or a simulator | `device-observation-harness` |
| Real-device test automation, or a bench | `autonomous-fleet-testing` + `docs/AUTONOMOUS-FLEET-TESTING.md` |
| More than one agent session drives the same devices | `concurrent-agent-device-leases` |
| User pushback after 3+ iterations of "still broken" | `3d-feature-debug-loop` |
| A visual / 3D feature you cannot observe directly | `3d-feature-sim-validation` |
| **05 Shipping** | |
| Any store submission | `store-submission-playbook` |
| Building/signing/uploading an Apple build (default: cloud) | `cloud-appstore-submission` |
| Submitting for App Store review (the FULL ship is CLI; never ask the owner to press Submit) | `apple-app-store-cli-submission` + `docs/APPLE-SUBMISSION-CLI.md` |
| Publishing an Android build to Play | `play-cli-submission` |
| Publishing a Windows MSIX to the Microsoft Store | `windows-production-gotchas` + `docs/windows/WINDOWS-STORE-SUBMISSION.md` |
| In-app purchases on any store | `store-submission-playbook` + `docs/store/IAP-RELEASE-CHOREOGRAPHY.md` |
| **06 Keeping it running** | |
| A product-health dashboard, or a Pulse reading looks wrong | `product-pulse-dashboard` |
| Store downloads, installs, reviews, crashes | `store-metrics-pipelines` |
| Adding/editing ANY scheduled workflow, or CI failures / alert noise | `ci-fleet-engineering` |
| Running an unattended multi-tick development loop | `autonomous-loop-cadence` |
| **07 Raising the ceiling** | |
| Video/audio streaming from hosts you don't control | `resilient-media-streaming` |
| SharePlay / Group Activities | `shareplay-activities` |
| Capturing camera, mic, or another app's audio, mixing sources, or publishing live (RTMP) | `live-capture-and-broadcast` |
| Vertical social video (Reels, Shorts, TikTok), burned captions, posting cadence | `social-video-teaser-craft` |
| Real-time multiplayer, or a $0 watch party | `cross-platform-multiplayer` + `zero-cost-hosted-backend` |
| A value identical on every platform (daily pick, hash) | `cross-platform-determinism` |
| Any algorithmic feed / discovery / "for you" surface | `values-based-feed-ranking` |
| Reader mode or link-preview cards | `web-content-extraction` |
| Third-party sign-in from an installed app, or a per-app API quota | `authentication` + `third-party-revocation-resilience` |
| Identifying physical objects with the live camera | `camera-recognition-pipeline` |
| 3D card rendering in RealityKit | `realitykit-3d-card-rendering` |
| **08 Working with AI, and hard choices** | |
| Feedback on how human-shaped the app is, or filling in HUMAN-SHAPED.md | `human-shaped-review` |
| Coordinating with a second AI agent surface | `two-agent-handoff` |
| Adding a third-party data dependency, or a partner revokes one | `third-party-revocation-resilience` |
| Monetizing an app built around IP/content you don't own | `third-party-ip-monetization` |
| Prices or market data from third-party listings | `provenance-honest-market-data` |
| User-to-user trading / selling / matching | `marketplace-adjacent-design` + `docs/templates/TRADE-DESIGN-template.md` |

### Where each platform's rules live

Read the page BEFORE touching that platform: stack, layout, critical
conventions, and which skill fires first.

- `docs/platforms/web.md`: any web work (views, routing, CSS, data,
  offline, deploys); the Safari layout rule and the web APIs to reach for.
- `docs/platforms/apple.md`: any Swift work, or choosing a floor; the
  universal target, `project.yml`, and the macOS and tvOS guardrails.
- `docs/platforms/android.md`: any Kotlin / Compose work, or choosing `minSdk`.
- `docs/platforms/windows.md`: any Windows work (optional platform); then
  `docs/windows/WINDOWS-PLAYBOOK.md`.
- `docs/platforms/tv.md`: Android TV, Fire TV, webOS, Tizen, Cast, Roku;
  then `docs/TV-PLATFORMS.md`. Apple TV is in `apple.md` and
  `docs/TVOS-PLAYBOOK.md`.
- `docs/platforms/design-system.md`: changing the look, a color, type,
  haptics, or icons on any platform.
- `docs/platforms/shared-data.md`: a second client reads your data, a
  value must match on every platform, or anything multiplayer.

### Hard rules on every platform

- **All API calls through one shared client** (`js/api.js`, a Swift
  singleton, a Hilt Ktor client, the Core client on Windows); views never
  call the network directly.
- **Refresh the JWT before every Worker / Storage / Edge Function call.**
  The auth SDK's auto-refresh only covers its own HTTP path.
- **Deep links and intents land in an inbox** the root consumes; every
  `appname://item/x` has an `https://…/item/x` twin (DEEP_LINKS.md).
- **One version everywhere, bumped on every ship**, from
  `AppVersion.xcconfig` (`tools/test_version_contract.py`).
- **One identity everywhere**, set once with
  `tools/set_app_identity.py`; never leave `com.example.appname` in a copy.
- **Native components first**; no third-party Swift packages.
- **Secrets never in git**, and never in cleartext on disk.

---

## Debugging philosophy

**Do not iterate blindly on behavior you cannot observe.** When the root
cause is not clear from reading the code, the first move is diagnostics,
not another implementation attempt.

1. **Add observability before another implementation.** Write what you
   *expect* to see vs. what would *indicate* the bug.
2. **Isolate layers.** Verify each independently before changing any.
   The bug is in the layer whose actual output diverges from its
   expected output.
3. **Use `print` (or `console.log` / `Log.d`), not `os.Logger`**: it
   lands in the console immediately with zero setup.
4. **For invisible UI bugs, add a temporary visual overlay** so the
   numbers appear on the screenshot (a real device, a TV across the
   room). Doubly important on tvOS, where focus, animation, and video
   bugs can't be reported any other way.
5. **For visual / 3D bugs you cannot observe, build an offline sim.**
   Render to PNG and open it before shipping (`3d-feature-sim-validation`).
   Android: Compose `@Preview` + Roborazzi. Web: run the real JS in a
   Node DOM shim and pixel-measure; headless Chrome's virtual-time budget
   distorts timers and AbortSignal.
6. **Make diagnostics permanent but env-gated when the bug class
   recurs** (`APP_PLAYBACK_DIAG=1`). One-off diagnostics are removed
   before declaring a fix complete.
7. **Drive the app to a known state for screenshots.** DEBUG-only launch
   doors (`APP_START_TAB`, `APP_START_ITEM`, mute, door seconds: Apple
   `Core/Store/LaunchDoors.swift`, Android `navigation/LaunchDoors.kt`,
   Windows `LaunchHooks.cs`, web `?view=`/`?item=`/`?mute=1`; names from
   `tools/app_config.py`) let `simctl launch` / `adb shell am start` open
   any screen. No-ops in production.

After 3+ iterations of "still broken," invoke `3d-feature-debug-loop`
and reset to research agents and observable evidence. Stop trying fixes;
start measuring.

**Simulator/emulator discipline:** boot ONE at a time; parallel-booting
wedges both. The simulator is *lenient* where hardware is not (tvOS lets
Application Support writes through; devices crash with EPERM), so
anything touching the filesystem, entitlements, or sync needs a
real-device check before "done."

---

## What this app does

<!-- FILL IN: One paragraph on what your app does and who it's for -->

Available as a **web app**, a **native iOS/iPadOS app**, a **native
macOS app**, a **native Apple TV (tvOS) app**, and a **native Android
app**: five core platforms, one feature set. Optional: **Windows**
(`windows/`), **smart-TV web** (webOS / Tizen / Cast, via
`tv.js`/`tv.css`), **Android TV / Fire TV** (the same Android app), and
**Roku** (`roku-brightscript-app`). When adding to one platform, note the
equivalent work in SCRATCHPAD.md and update PARITY.md.

**Feature parity, not design consistency.** Web feels like the web, iOS
like iOS, macOS like a Mac (pointer + keyboard + menu bar + resizable
windows), tvOS like the living room, Android like Android. The verbs are
identical; the idioms aren't.

Not every app needs all five. Decide the platform set in M0 and record it
in DECISIONS.md. tvOS earns its place when the content is lean-back
(video, music, ambient, photos); macOS when the app wants a
desktop-class or document/pro surface, and it is the cheapest port (it
shares the whole Apple Core). A skipped platform is a 🚫 column in
PARITY.md with a reason, not a deletion.

---

## Shared design system

**One source: `design-tokens.json`.** `node tools/design_tokens.mjs`
writes every platform's tokens; `node tools/test_design_tokens.mjs` fails
on drift or a text pair below WCAG AA. To change the look: **edit the
JSON, run the generator, then build and look at every platform**, light
and dark. Never hand-edit a generated file or a `BEGIN design-tokens`
block. Per-platform names: `docs/platforms/design-system.md`.

- **Brand colors are UI chrome only; semantic colors (success, warning,
  error) carry content meaning only** (Decision 012). Add a domain
  semantic color to `color.semantic` in the JSON.
- **Three weights × two sizes = six levels.** Refuse a seventh; refactor.
  System tokens only, never hardcoded sizes; 29pt is tvOS's body floor.
- **Density comes from removing chrome**, not adding decoration. Test at
  375px before 1440px. On tvOS, focus does the work: only the focused
  card is bright.
- **Haptics: one semantic taxonomy** (`selection`, `light`/`medium`/`heavy`,
  `success`/`warning`/`error`), mapped in one place. `error` always
  accompanies a surfaced error banner; `selection` always accompanies a
  page/segment change.
- **R-ICON-1: UI icons come from the platform icon system** (SF Symbols,
  Material Symbols, inline SVG). Emoji are content, never chrome.

---

## Binding design docs

Past ~5 views on a platform, add its binding design doc
(`tvOS-`/`iOS-`/`macOS-`/`WEB-`/`ANDROID-DESIGN.md`), seeded from
`docs/templates/` (start with `PLATFORM-DESIGN-template.md`). Not on day
1; once created, binding. Quote the rule before proposing UI work; fix
the doc, then the feature (`binding-design-doc-discipline`). Principles
are shared, idioms diverge, and a rule that deliberately inverts another
doc's (tvOS auto-focuses Play on Detail; iOS never steals focus) says so,
or a later session will "harmonize" it into a bug. An iPad that outgrows
iOS-DESIGN gets `docs/IPAD-DESIGN.md`; a feature whose capability differs
by OS or hardware gets one from `FEATURE-DESIGN-template.md`. A rule the
owner approves for all platforms is stamped into every platform doc the
same day.

---

## Cross-platform feature parity

**`PARITY.md` is the single source of truth**: a row per user-facing
feature, a cell per platform, a Notes column for deltas. Run the
**periodic parity audit** (`cross-platform-parity-discipline`): is every
shipped feature a row, and is every cell honest? Mirror a feature on the
other platforms in the same change set where feasible: **same verb,
native idiom**. A port keeps a three-level ledger
(`docs/templates/PORT-PARITY-LEDGER-template.md`): reachable is not
parity. A rule mirrored in several languages gets a mechanical parity
guard with a negative control. Floors go in the "Oldest hardware served"
row; a capability a device can never have is `n/a` with the reason, and
one it lacks for now gets a sentence on screen.

---

## Shared data

Detail: `docs/platforms/shared-data.md`.

- **Build shared content ONCE as a published data plane**; every client
  consumes it, and none re-implements, re-derives, or re-hosts it.
  Write `docs/DATA-CONTRACT.md` when the second client exists, and test
  the documented shape over the real published artifact. Thin clients
  read projections from one gatekeeper index; every builder imports the
  same policy predicates.
- **Publish a computed value rather than mirror its algorithm.** A value
  that must match on every platform is one algorithm per language, proven
  by a golden test on every stack. Never a seeded shuffle.
- **Multiplayer rides a transport seam**: protocol and arbiter in `Core/`
  with no networking import, each transport a thin adapter.

---

## Automation, CI, and verification

Binding docs for everything unattended. Read the doc before re-deriving.

- **`docs/CI-FLEET.md`**: a green run must have done something, a red run
  must mean something, and no run may destroy work; a red X is reserved
  for broken. Enable `workflow-health.yml` + `retry-infra-failures.yml`
  once there are scheduled workflows; start any new writer from
  `docs/templates/split-writer-workflow-template.yml`.
- **`docs/AUTONOMOUS-LOOPS.md`**: the agent is never the tester; ship only
  on external observation; verified vs merely-fixed is a load-bearing
  distinction in every session log; DECISIONS.md stays context-sized.
- **`docs/ENGINEERING-PROCESS.md`**: thirteen disciplines, each with its
  incident (absence is not evidence; a test is not a test until seen to
  fail).
- **`docs/MEDIA-PLAYBACK.md`**: media apps only, streaming and captions.
- **`docs/PROVENANCE.md`**: when you learn something template-worthy in an
  app repo, upstream the generic form here in the same session and
  update the map. App-local docs are where lessons go to be lost.
- **`docs/DEVICE-HARNESSES.md`**: per-platform observation harnesses; an
  instrument says when it is blind, never perturbs what it measures, and
  identifies its own configuration.
- **`docs/CLOUD-SUBMISSION.md`**: the cloud build and submit pipeline.

---

## How we collaborate

**The memory ratchet.** Your agent keeps a persistent memory (Claude
Code's auto memory, a Gemini memory file, or a notes file). Use it. When
the user **corrects an approach** ("don't do X"), save it as a feedback
memory with a `**Why:**` line. When the user **validates a non-obvious
choice** ("yes, exactly that"), save it too; quiet confirmations matter as
much as corrections. Save **project state** as a project memory with the
date. Keep an index of those memories as your at-a-glance map.

**Fix the doc first, then the feature.** When a binding design doc and a
proposal conflict, **the bug is in the doc**. Update the rule, get
alignment, then ship.

**Trust but verify.** Subagent summaries describe what the agent
*intended*, not what it *did*. Check the actual diff before reporting
work as done.

**Auto-pace decisiveness.** When the direction is reasonably inferable,
make the call and keep going. Reserve questions for decisions only the
user can make.

**Verify before declaring done.** If you can run the app, run it. If you
can't observe the result, build an offline sim that produces a PNG and
look at it. Type checks and tests confirm code, not features; "compiles"
is not "works." **After touching any shared file, re-build every platform
that consumes it**: the tvOS build going green after an iOS change is
part of "done." **Show the evidence, not the claim:** the command you
ran and what it returned, or a screenshot of the result.

**Capture the ratchet.** When a recurring failure mode surfaces, the fix
lands in DECISIONS.md or a memory, not just the code. The lesson is the
deliverable.

**Session log discipline.** Each SCRATCHPAD.md entry is state found, work
done, state left. The scratchpad keeps the two most recent entries; older
ones roll word for word into `docs/SESSION-LOG.md` (create it on the first
roll). When the scratchpad has drifted behind the code, fix its Current
State section first, then work.

---

## Standing instructions

- **Read the relevant skill before re-deriving a pattern.** Invoke by
  name; don't paraphrase.
- **Commit messages quote the user's request verbatim** when applicable
  (`feature-shipping-discipline`).
- **DECISIONS.md leads with WHY, not WHAT**: the rule, then `**Why:**`,
  then `**How to apply:**` (`architectural-decision-log`).
- **Don't add features beyond what's requested.** Fix only the bug.
- **Don't refactor surrounding code.** Scoped diffs.
- **Default to writing no comments.** Only when the WHY is non-obvious: a
  hidden constraint, a subtle invariant, a workaround for a specific bug.
- **No emojis in code or commits** unless explicitly requested.
- **Value rules say what holds them.** A value climbs from a reason (Why
  we build) to a rule (here, dated, in the owner's words) to a check (a
  test or hook that fails when the line is crossed). Each value rule
  below names its check, or "no check yet". When one becomes testable,
  write the check and update the mark.
- **Only essential words on screen.** A caption must be a refusal, a
  warning, or a fact the person cannot discover by looking
  (`mobile-first-density-design` rule 7). *No check yet.*
- **No AI-written lists or copy in the product.** Lists and blurbs come
  from data or a human editor (`learning-orientation-design`). *No check
  yet.*
- **Side doors (feeds, MCP) are findable on the website, never featured
  in the apps.** *No check yet.*
- **One spelling locale, linted.** *Check: `tools/test_us_english.py`.*
- **Always ensure cross-platform parity.** Mirror on the other platforms
  in the same change set where feasible AND update PARITY.md. Don't ship
  one and wait to be asked. A platform you can't reach right now gets ⏳
  with a note, never silence.
- **Update SCRATCHPAD.md "Out of scope" when rejecting an idea**, so it
  is not re-litigated next session.
- **AGENTS.md stays under 24,000 bytes.** A new platform rule goes in its
  `docs/platforms/` page. *Check: `tools/test_agent_files.py`.*

---

## Current state

`SCRATCHPAD.md`: active milestone and open questions. `DECISIONS.md`:
architecture decisions. `PARITY.md`: what exists on which platform.
`docs/maintaining/AGENTS-MD-MAP.md`: where each rule that left this file
went.

This file is for the agent. Humans start at `docs/path/` (the stages,
beginning with `00-why-we-build.md`) and `COURSE.md` (the course built
on those stages).
