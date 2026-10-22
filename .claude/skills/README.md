# The skills

There are 147 folders in this directory. 57 of them I wrote, one lesson
at a time, while building BOBA Playbook, Bsky Dreams, Tidbits Trivia and
Archive Watch. The other 90 came from people who wrote good skills
before I needed them, and they are credited below.

This page says what each one is for, when it fires, and where it came
from.

## What a skill is

A skill is a folder with a file called `SKILL.md` in it. The top of that
file has two lines that matter: a `name` and a `description`. Claude Code
reads every description at the start of a session, and when your request
matches one, it loads the rest of that file and follows it.

So, the description is a trigger, and the body is a method. A skill like
`tvos-platform-patterns` does not teach an agent tvOS in general. It
carries the dozen specific things that went wrong on a real Apple TV
(the button style that destroys focus, the folder a real device will not
let you write to) so that the next app does not learn them again the
expensive way.

## Why they live in the repository

Skills can be installed once, globally, in `~/.claude/skills/`. I vendor
them here instead, inside the template, for three reasons:

1. **Anyone who clones the template gets the whole method.** No setup, no
   marketplace, no second repository to track. A student opens the
   project and the agent already knows how this template builds.
2. **They change with the code.** When a tool in `tools/` changes, the
   skill that explains it changes in the same commit.
3. **They can be read.** A skill is plain text. You can open any of these
   and see exactly what the agent will be told. In a class about building
   with AI, I think that matters a great deal.

The cost is size, and a little drift from upstream. `tools/refresh-skills.sh`
pulls updates for the vendored ones. It treats every skill already in this
folder as the canonical copy, copies in only skills the template does not
have yet, and warns you when a global copy differs, so you can decide by
hand which is newer.

## How the agent finds the right one

`AGENTS.md` (which `CLAUDE.md` imports) has a table ("How we build")
that maps situations to skills: "Adding a list, grid, sheet or shelf" to `universal-feature-states`, and
so on. The descriptions do most of the matching on their own. The table
is there for the cases where a skill should fire *before* the agent would
think to ask, like `learning-orientation-design` before any new feature.

You can always ask for one by name: "use the `native-platform-first`
skill before you build that dropdown."

## The skills I wrote

Grouped by the stage of the path (`docs/path/`) where you will first need
them. "From" names the app where the lesson was learned.

### Stage 00: Why we build

| Skill | What it is for | From |
|---|---|---|
| `learning-orientation-design` | The four questions every feature answers before it is built: does it deepen understanding, invite participation, support agency, and stay clear rather than clever. Also the rule that a bot standing in for a person is labeled as one. | BOBA Playbook; the bot rule from Tidbits Trivia |
| `feature-shipping-discipline` | The order of any change: read the docs, propose with the rule quoted, build, verify, bump the version, commit with the request quoted. | BOBA Playbook |
| `architectural-decision-log` | How to write a `DECISIONS.md` entry: lead with the rule, then why, then how to apply it. Written for the next person who would get it wrong. | BOBA Playbook |
| `binding-design-doc-discipline` | Once a platform has a design doc, quote the rule before proposing UI. If no rule fits, fix the doc first. | BOBA Playbook |

### Stage 01: The first prototype

| Skill | What it is for | From |
|---|---|---|
| `web-platform-patterns` | The vanilla web app: views, URL-driven state, the service worker, IndexedDB, image fallbacks, Safari layout traps, headless checks. | Archive Watch, Bsky Dreams |
| `universal-feature-states` | Every list has loading, empty, error and offline states, and the difference between an empty state, an error banner, a hint and a walkthrough. | BOBA Playbook |
| `mobile-first-density-design` | Density comes from removing chrome, not adding decoration. Six levels of type, tested at phone width first. | BOBA Playbook |
| `native-platform-first` | Use the platform's own control before building a custom one. The most expensive mistake across every app. | BOBA Playbook |
| `learner-experience-design` | What a person sees once they are in: a home that stops pitching, ordered by what needs them now, one page for every role, empty states with one action, teachers' lists of what needs them, account pages for rare jobs, and no scores. It grows a Lessons list each round. | humanshaped.org |

### Stage 02: The shape of an app

| Skill | What it is for | From |
|---|---|---|
| `cross-platform-parity-discipline` | Running `PARITY.md`: same verb, native idiom; honest cells; the periodic audit that catches rows that quietly became false. | BOBA Playbook, Archive Watch |
| `shared-data-plane-contract` | Build the data once, publish it, and make every app a consumer. What a browser can and cannot fetch. Contract tests. | Archive Watch |
| `canonical-entity-identity` | One stable ID and one image per thing, the same on every platform, and how to migrate IDs without breaking anyone. | BOBA Playbook |
| `per-ecosystem-sync-islands` | Sync each person's data on their own cloud (CloudKit on Apple, Google Drive on Android and web), with no server to run. | Archive Watch |
| `zero-cost-hosted-backend` | When people need to see one another's data: a hosted database for accounts and user data only, and everything else static. | BOBA Playbook |
| `image-cdn-discipline` | Two sizes of every image on a CDN, never in git, and never a box that reshapes art you did not make. | BOBA Playbook, Archive Watch |
| `content-corpus-derivation` | Deriving a shipped set of facts or questions from a messy source, at build time. | Tidbits Trivia |
| `evidence-gated-catalog-curation` | Deciding what a catalog you did not make may show, hide, recommend, or say: a claim a reader can open, an uploader's word is not evidence, restore by evidence, never recommended but always findable, provenance on every field. | Archive Watch |
| `internet-archive-source` | Reading archive.org honestly: scrape vs search, throttled is not empty, the connection limit, upload dates, items that hold many works, private files, storage nodes. | Archive Watch |
| `web-catalog-data-layer` | A worked example: how Archive Watch's web app reads the shared catalog. Read `shared-data-plane-contract` first. | Archive Watch |

### Stage 03: Going native

| Skill | What it is for | From |
|---|---|---|
| `make-it-look-like-itself` | Replace the template's placeholder look with one drawn from the app's own why: real references first, three directions on the real core screen, then the chosen one on every platform at once. Keeps a cohort's apps from looking like siblings and keeps the stores from rejecting look-alikes. | Ben's vision for humanshaped.org, and two rounds of designing the hub |
| `multiplatform-expansion-method` | Find the seam between data and views, then add platforms in order of how much they reuse. | Archive Watch |
| `ios-production-gotchas` | The iPhone and iPad lessons no framework skill carries: presentation races, dark-mode legibility, layout blowups from fill images, background audio. Read it first when a symptom matches. | four shipped apps |
| `ios-share-extension` | Receiving things from the share sheet, and the one pattern that reliably opens the app afterward. | Bsky Dreams |
| `macos-platform-patterns` | The Mac is a pointer, keyboard, menu bar and resizable-window app, never the iPad app stretched out. | Archive Watch |
| `macos-native-app-shell` | A worked example of the above: Archive Watch's Mac shell. | Archive Watch |
| `tvos-platform-patterns` | The Apple TV: the focus engine, ten-foot type, the folders a real device forbids, hero and shelf recipes. | Archive Watch |
| `android-production-gotchas` | Compose and Room lessons from shipping to Google Play: the query that silently returns nothing, the database swap, deep links. | BOBA Playbook, Archive Watch |
| `smart-tv-platform-expansion` | Taking an app to Google TV, Fire TV, Samsung, LG, Roku and Cast: two builds, not six apps. | Archive Watch |
| `androidtv-compose-focus` | A worked example: Archive Watch on Google TV and Fire TV, including Google's TV quality gates. | Archive Watch |
| `smarttv-web-app` | A worked example: the web app on Samsung and LG televisions, with a spatial-navigation layer. | Archive Watch |
| `roku-brightscript-app` | A real Roku channel in BrightScript, and how to drive one over the network for testing. | Archive Watch |
| `ten-foot-detail-design` | The detail, series and search screens on a television, which came out the same on Roku and Android TV. | Archive Watch |
| `windows-production-gotchas` | Shipping a Windows app to the Microsoft Store from a Mac with no Windows hardware: CI is the Windows machine. | Tidbits Trivia |

### Stage 04: Seeing it work

| Skill | What it is for | From |
|---|---|---|
| `device-observation-harness` | Picking the right instrument for a bug the logs cannot show, per platform, and the trap to check first. | Archive Watch |
| `autonomous-fleet-testing` | Driving real devices and grading from the screen: the bench, roles, leases, leaving the room as you found it, and honest verdicts. | Tidbits Trivia, Archive Watch |
| `concurrent-agent-device-leases` | Two agent sessions sharing one bench of devices without mistaking each other for bugs. | Archive Watch, Tidbits Trivia |
| `3d-feature-debug-loop` | When a person keeps reporting "still broken" after three fixes: stop fixing and start measuring. | BOBA Playbook |
| `3d-feature-sim-validation` | Rendering a visual feature to an image offline and reading it before shipping. | BOBA Playbook |

### Stage 05: Shipping

| Skill | What it is for | From |
|---|---|---|
| `store-submission-playbook` | Every store (App Store, Mac App Store, Play, Amazon, Roku, Microsoft), with the expensive mistakes already paid for. | all four apps |
| `cloud-appstore-submission` | Building, signing and uploading every Apple platform from a GitHub runner, so a beta OS on your own Mac never blocks a release. | Archive Watch, Tidbits Trivia |
| `apple-app-store-cli-submission` | Creating the version, attaching the build and submitting for review from the command line. | Archive Watch |
| `play-cli-submission` | Publishing to Google Play from the command line and from CI. | Archive Watch |

### Stage 06: Keeping it running

| Skill | What it is for | From |
|---|---|---|
| `product-pulse-dashboard` | One daily page for how the app is doing, where a reader that cannot read says so. | Archive Watch |
| `store-metrics-pipelines` | Getting downloads, installs, ratings, reviews and crashes out of each store's API, and the traps in each. | Archive Watch |
| `ci-fleet-engineering` | Scheduled workflows that never lose work and never cry wolf. | Archive Watch |
| `autonomous-loop-cadence` | Running an agent in timed ticks across several platforms. | BOBA Playbook |

### Stage 07: Raising the ceiling

| Skill | What it is for | From |
|---|---|---|
| `resilient-media-streaming` | Video from hosts you do not control, without stalls. | Archive Watch |
| `live-capture-and-broadcast` | Capturing and mixing several sources, or publishing live, with every sample on one clock and the bitrate steered by what the link carried. | Archive Watch |
| `social-video-teaser-craft` | Vertical social video: safe areas under platform chrome, burned captions checked against the audio, cadence per platform. | Archive Watch |
| `cross-platform-multiplayer` | Real-time play across native apps and the web, in the same room or online. | Tidbits Trivia |
| `cross-platform-determinism` | A value (a daily pick, a shuffle) that must come out identical on every platform. | Tidbits Trivia |
| `values-based-feed-ranking` | A feed or "for you" surface that passes the four questions as a ranking function. | Bsky Dreams |
| `web-content-extraction` | Reader mode and link previews from pages you do not control. | Bsky Dreams |
| `camera-recognition-pipeline` | Identifying physical objects with the camera. | BOBA Playbook |
| `realitykit-3d-card-rendering` | 3D card rendering on iOS. | BOBA Playbook |

### Stage 08: Working with AI, and hard choices

| Skill | What it is for | From |
|---|---|---|
| `human-shaped-review` | Feedback on your app from your own AI agent, walking the fifteen Human-Shaped Principles as questions with evidence. It never grades, it says what it could not see, it labels itself as AI, and you decide whether to share it. | The Human-Shaped Principles, October 2026 |
| `two-agent-handoff` | Two different AI agents working on one project through a single handoff file. | BOBA Playbook |
| `third-party-revocation-resilience` | Every outside data source can be taken away. Plan the exit before you depend on it. | BOBA Playbook |
| `third-party-ip-monetization` | Charging for an app built around something you do not own. | BOBA Playbook |
| `provenance-honest-market-data` | Prices and valuations that say what kind of number they are. | BOBA Playbook |
| `marketplace-adjacent-design` | Letting people trade with one another without the app ever touching money. | BOBA Playbook |

## Skills from other people

These are vendored as written by their authors, and refreshed from
upstream with `tools/refresh-skills.sh`.

### Design and store marketing

| Skill | What it is for | Source |
|---|---|---|
| `frontend-design` | Distinctive, production-quality web interfaces. | Anthropic, `claude-plugins-official` |
| `ui-ux-pro-max` | A large library of styles, palettes and UX guidelines. | `ui-ux-pro-max-skill` |
| `killer-ui` | Design systems, critique and accessibility, plus the `/KUI:*` commands. | [BigSiggis/Killer-UI](https://github.com/BigSiggis/Killer-UI) |
| `app-store-screenshots` | Marketing screenshot pages for the App Store and Google Play. | [ParthJadhav/app-store-screenshots](https://github.com/ParthJadhav/app-store-screenshots) |

### Apple frameworks

86 skills from the `swift-ios-skills` collection, one per Apple framework
or topic. Reach for them when the work touches that framework directly.
My own skills above say *what went wrong in practice*; these say *how the
framework works*.

| Area | Skills |
|---|---|
| SwiftUI | `swiftui-patterns`, `swiftui-navigation`, `swiftui-layout-components`, `swiftui-animation`, `swiftui-gestures`, `swiftui-liquid-glass`, `swiftui-performance`, `swiftui-uikit-interop`, `swiftui-webkit` |
| Swift and tooling | `swift-language`, `swift-concurrency`, `swift-architecture`, `swift-api-design-guidelines`, `swift-codable`, `swift-formatstyle`, `swift-charts`, `swift-testing`, `swiftlint`, `debugging-instruments`, `ios-simulator` |
| Data and sync | `swiftdata`, `core-data`, `cloudkit` |
| System features | `app-intents`, `widgetkit`, `activitykit`, `alarmkit`, `app-clips`, `background-processing`, `push-notifications`, `tipkit`, `relevancekit`, `appmigrationkit`, `browserenginekit`, `carplay`, `focus-engine` |
| Media and shared experiences | `avkit`, `musickit`, `shareplay-activities`, `speech-recognition`, `callkit`, `audioaccessorykit`, `photokit`, `pdfkit`, `pencilkit`, `paperkit` |
| Graphics, AR and games | `realitykit`, `scenekit`, `spritekit`, `gamekit`, `tabletopkit` |
| On-device intelligence | `apple-on-device-ai`, `coreml`, `natural-language`, `vision-framework` |
| Security, identity, access | `authentication`, `swift-security`, `ios-security`, `cryptokit`, `cryptotokenkit`, `device-integrity`, `permissionkit`, `ios-accessibility`, `ios-localization`, `ios-networking` |
| Commerce and the App Store | `storekit`, `passkit`, `financekit`, `adattributionkit`, `app-store-review`, `app-store-optimization` |
| Hardware, sensors, home | `core-bluetooth`, `core-motion`, `core-nfc`, `accessorysetupkit`, `dockkit`, `healthkit`, `homekit`, `mapkit`, `weatherkit`, `eventkit`, `contacts-framework`, `sensorkit`, `energykit`, `metrickit`, `metrickit-diagnostics` |

Two pairs overlap on purpose. `ios-security` and `metrickit-diagnostics`
are from an older release of the same collection, and their content
still differs from `swift-security` and `metrickit`. Twelve other older
copies were identical to their newer twins and were removed on
2026-09-30.

`shareplay-activities` is vendored from the collection and then amended
with what shipping SharePlay across tvOS, iOS and macOS actually taught
Archive Watch.

### Android

Android skills from the wider community are not vendored, because they
would roughly double the size of this folder. `tools/install-android-skills.sh`
installs them globally when you start the Android app.

## Adding your own

When your app teaches you something the next app should not have to
learn again, write it down as a skill:

1. Make a folder here named for the lesson, in lowercase words joined by
   hyphens.
2. Write `SKILL.md` with a `name` that matches the folder and a
   `description` under 1024 characters that says *when* to use it. Put
   the description in quotes.
3. In the body, lead with the rule, then the story of how you learned
   it, then how to apply it.
4. Add a row to the "How we build" table in `AGENTS.md` if it should
   fire before anyone thinks to ask.

The first one you write will feel small. Write it anyway.
