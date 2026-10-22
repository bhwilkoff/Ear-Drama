# Restructure plan (2026-09-30 loop)

The working plan for the reorganization Ben asked for on 2026-09-30.
Every tick of the loop reads this first, does the next unchecked item,
and records what it did in the log at the bottom. When the plan is done,
this file stays as the record of why the repository is shaped the way
it is.

## The ask, in Ben's words

> Please go through the full Universal App Template to create a much
> more logical flow for all skills and documentation that will allow for
> other projects to proceed quickly from initial prototype to launching
> on multiple platforms. Please take care to explain in readme documents
> what each skill is, what each piece of tooling does, and why we have
> chosen to build in the ways that we have. [...] I will also be using
> this template as the basis of a class that I plan to teach about
> values-based app development with AI, so that is the orientation that
> this repository needs to take.

Three readers, in order of priority:

1. **A learner** in Ben's class, who has never shipped an app and needs
   to know what to do first, and why.
2. **A builder** who found the repository on GitHub and wants to use it
   for their own app this week.
3. **An agent** (Claude Code) working inside a project made from the
   template, who needs the skill triggers and the binding rules.

The current repository serves the third reader well and the first two
poorly. The README is a changelog of generations; the docs are a flat
list of deep references; 156 skills sit in one folder with no map.

## The shape we are building toward

```
README.md                 Front door. What this is, why it exists, where to start.
docs/
  README.md               Map of every doc, grouped by stage.
  path/                   THE PATH: numbered stages, prototype to launch.
    00-why-we-build.md      Values first. The four questions. AI as a
                            collaborator that must not do the learning for you.
    01-first-prototype.md   The low floor: the web app, one screen, today.
    02-shape-of-an-app.md   Data plane / API contract, shared Core,
                            same verb / native idiom, PARITY.md.
    03-going-native.md      Adding Apple (one universal target) and Android,
                            the expansion order, and why native over cross-platform.
    04-seeing-it-work.md    Observation: env hooks, simulators, the real-device
                            fleet, "the agent is never the tester".
    05-shipping.md          Every store from the command line.
    06-keeping-it-running.md  CI fleet, product pulse, autonomous loops.
    07-raising-the-ceiling.md The high ceiling: SharePlay, Top Shelf, widgets,
                            Cast, TV, Windows, added once and mirrored.
    08-working-with-ai.md   Skills, memory, the decision log, the scratchpad,
                            loops, two agents. How the method compounds.
  reference/ (maybe)      The deep docs (CI-FLEET, TVOS-PLAYBOOK, ...) once
                          references are updated. Decide after the inventory.
  maintaining/            For whoever keeps the template itself current:
                          PROVENANCE, this plan, the writing guide.
.claude/skills/README.md  Every skill: what it is, when it fires, where it came from.
tools/README.md           Every tool: what it does, which stage uses it.
```

Each path stage follows Ben's instruction register (BEN.md §12): what
you will make, why it is built this way, numbered actions, and a closing
"Be ready to..." that says what to bring back. That makes each stage a
lesson a class can run as-is, and a checklist a solo builder can follow.

## Decisions made (and why)

- **Skills stay flat in `.claude/skills/`.** Claude Code discovers them
  at one level; nesting would hide them. Organization lives in the
  catalog README, not the folder tree.
- **Tools stay flat in `tools/`.** Workflows and docs call them by path;
  moving ~60 scripts breaks more than it clarifies. `tools/README.md`
  groups them.
- **CLAUDE.md stays the agent's index.** It is rewritten for order
  (by stage) and accuracy, not for voice. Human-facing docs carry the voice.
- **Human-facing prose follows `docs/maintaining/WRITING.md`**, which is
  BEN.md distilled for documentation. Agent-facing skills keep their
  terse register but get accurate descriptions.

## Decisions made while porting

- **The platform floor is a per-app decision made by hardware reach**, not
  a template constant. Archive Watch moved iOS from 26 to 18 because 26
  dropped the iPhone XS/XR, and Android minSdk from 29 to 23 because 29 hid
  the app from 38 of 98 Fire TV devices. The template teaches the method
  (test-build at candidate floors, count errors, hold the floor with a CI
  test) and gates newer APIs by capability.

## Open questions for Ben

- Should the course have its own folder (syllabus, weekly units,
  assignments), or should `docs/path/` *be* the course? Current bet: the
  path is the course spine, and a thin `COURSE.md` maps weeks to stages.

## Checklist

- [x] Read BEN.md, the README, the values skill, PROVENANCE
- [x] Archive Watch gap audit (`ARCHIVE-WATCH-GAP-AUDIT-2026-09-30.md`; AW decisions 096-158 were never audited)
- [x] Skill / tool / doc inventory (`INVENTORY-2026-09-30.md`)
- [x] Writing guide (`docs/maintaining/WRITING.md`)
- [ ] Decide on `docs/reference/` move, from the inventory
- [ ] Port the Archive Watch gaps. Workstreams, section numbers refer to the gap audit:
  - [x] **W1 code landed (tick 6), tests re-run by me:** asc_release.py (all Apple platforms, waits for VALID, refuses no-notes), asc_submit --platform, appstore-build hardening (secrets file gated off by default, cert prune/revoke, duplicate build refusal, floor tests, submit after VALID), auditor never fails + self-closing issue, gate checker (reporter marker, GH_TOKEN), Android versionName from AppVersion.xcconfig, Kotlin daemon cap, floor tests (iOS 18 / tvOS 26 default ceilings), Fire TV manifest audit. **W1 follow-ups:** docs still say `asc_submit --submit` (APPLE-SUBMISSION-CLI, apple-app-store-cli-submission) and "auditor fails" (CI-FLEET §6); CLAUDE.md floor text; play-release.yml writes an AW-only secret; asc_build_exists ignores app_config; asc_prune_certs names Ben; KSP version was unpublished (fixed to 2.1.21-2.0.2) and AGP 9.2 needs Gradle 9.4.1: **Android scaffold did not build on a fresh clone.** Fixed (tick 8), and I re-ran `assembleDebug testDebugUnitTest` green: Gradle 9.8.0, AGP 9.4.1, Kotlin 2.4.20, KSP 2.3.12 (KSP2 no longer pairs with Kotlin), compileSdk 37; four scaffold code bugs no build had ever reached (theme parent, rememberSaveable import, Coil okio Path, inline/private ApiClient). play-release.yml now builds `bundleRelease` and no longer writes an AW-only secret. Lesson for the docs: a scaffold nobody builds is fiction; add an android-build CI run on the template itself.
  - [x] **W1 Contradictions (§1).** Platform floors chosen by hardware reach (AW 141/148/154/155) replace the "iOS 26 floor, no guards" rule; `asc_release.py` replaces iOS-only `asc_submit.py`; drop "owner hits Submit"; auditor never fails (AW 107); gate checker's reporter + GH_TOKEN checks; Android versionName read from AppVersion.xcconfig; tvOS Dynamic Type; DECISIONS ceiling 50 KB; Kotlin daemon cap; real devices vs emulators as a stated choice; determinism Rule 0 (publish the result).
  - [x] **W2 Real-device testing (§2).** Bench manifest; leave-as-found (teardown, muted doors, restore the room, cleanup); capture traps; Apple device recipes; Android/Google TV/Fire TV; Roku tools; web-TV glass tools; verdict doctrine (determinism, instrument faults, skip is not pass, audit ledgers); drifted tools (atv_scenario, ScreenOCR `w`, mac window-only capture, leases in every runner).
  - [x] **W3 Low floor, high ceiling (§3).** Floors by hardware; capability tiers; projection ladder; small JSON for extensions; one free Worker of thin adapters; outbound tier; state in the link; web bridges the sync islands; $0 watch party; the rule is a value; installed-app OAuth; shared quotas; media additions; social pipeline.
  - [x] **W4 Parity and contract (§4).** Mechanical parity guards; port ledgers; PARITY maintenance protocol; FEATURE-DESIGN and IPAD-DESIGN templates; contract tests; field tiers; named filter clauses; pipeline-side policy; AW's standing rules; web traps; TV and macOS idioms.
  - [x] **W5 Process, store, CI, pulse (§5).** ENGINEERING-PROCESS doc; working-style lessons; store tooling; CI workflow fixes; pulse collector and charts.
  - [x] **W6 Pulse dashboard (Ben, 2026-09-30: "Make sure you are also documenting and bringing in all of the work we've done on dashboard development for building Archive Watch Pulse.")** Port agent running: collector (3,101 vs 1,642 lines), charts (514 vs 168), look rules, reader honesty, privacy counting, workflow cadence, both skills. Then: rewrite `docs/PRODUCT-PULSE.md` as a teaching doc, including the story of how Pulse was built, and give it a place in path stage 06.
  - [x] (tick 23) PROVENANCE: 2026-09-30 audit line for AW 096-158; record exclusions (Studio engines, rights-audit specifics, catalog/subtitle/poster pipelines).
- [x] `.claude/skills/README.md` catalog (tick 14): 54 hand-written by path stage with origin app, 90 third-party credited; checked every folder appears
- [x] `tools/README.md` (tick 15): all 96 files covered, grouped by stage; removed orphan `_http_fetch.mjs` (helper for a tool that was never ported)
- [ ] Path stages 00 through 08, one per tick or so, each revised on a later tick
  - [x] 08 drafted (tick 19), anchored in Ben's 2026-09-24 'stop trying to reinvent' and the Amazon five-week negative-finding story. All nine stages drafted; revision pass still owed.
  - [x] 07 drafted (tick 18), anchored in Ben's 2026-09-12 playlist-sharing ask (fits in the link) and the SHAREPLAY §10 'separate out the calling part' quote; capability-not-effort from AW 131, closed-not-deferred from AW 122.
  - [x] 05 drafted (tick 17), anchored in the 41-versions-behind memory (2026-09-13) and the 88-version Android drift.
  - [x] 06 drafted (tick 11), anchored in Ben's 2026-09-14 Pulse message and the Roku 112-installs zero; CI anchor is the 09-06 publish outage. Promises `docs/PRODUCT-PULSE.md` carries the full commit history (write it next from PULSE-PORT). Also: Pulse used British 'programme'; fixed (AW has a US-English rule; consider porting `test_us_english.py`).
  - [x] 04 drafted (tick 10), anchored in "Stop using the fireplace tv" and the HomePod incident.
  - [x] 03 drafted (tick 9).
  - [x] 01 drafted (tick 7), anchored in AW's first three days and the June 9 expansion. Also fixed `js/api.js` to resolve relative endpoints.
  - [x] 02 drafted (tick 6), anchored in AW Decision 116 (Roku cast crash, 5.4% of films).
  - [x] 00 drafted (tick 5). Revise on a later tick. Its CLAUDE.md quote drops the em dashes; make CLAUDE.md match when it is rewritten.
- [x] `docs/README.md` map (tick 20)
- [x] New README front door (tick 20); COURSE.md (ten-week sketch, stated as untested)
- [x] CLAUDE.md skill table reordered by stage, all 54 hand-written skills have a trigger, Why-we-build em dashes removed (tick 21). Still: other CLAUDE.md sections' em dashes and broken refs (Design.swift, windows workflows location) in the voice pass.
- [ ] Fill missing skill descriptions; resolve duplicate pairs
- [x] (ticks 23-24) Voice pass: zero em dashes in every human-facing and reference doc except DECISIONS.md (append-only record, left as written) and vendored KUI commands (third-party). Reference docs keep some semicolons in rule lists (WRITING.md now says so).
- [x] Session-start hook: broken on macOS (`head -n -1`), wrong heading case, re-printed CLAUDE.md. Fixed.
- [x] Four skills with unparseable YAML frontmatter. Quoted.
- [x] `pulse.yml` ran Archive Watch's collector daily in every clone. Now dormant.
- [x] (tick 21) Wire the 7 hand-authored skills with no CLAUDE.md trigger (roku, ten-foot, macos-native-app-shell, apple-app-store-cli-submission, web-catalog-data-layer, realitykit-3d-card-rendering, concurrent-agent-device-leases)
- [x] Trimmed ios/android-production-gotchas descriptions; killer-ui name fixed (tick 13)
- [x] Deleted 12 legacy duplicate skills (tick 13). Kept metrickit-diagnostics and ios-security: their content differs from metrickit / swift-security; the catalog says so.
- [x] (tick 21) De-brand origin-app content (agent; zero em dashes, provenance-only app names): TV-DESIGN / TV-BACKLOG / WINDOWS-DESIGN / OWNER-PLAYBOOK templates, TVOS-PLAYBOOK (also says tvOS 17+), runbooks, hard-coded tools
- [ ] Decision-number drift: tools and docs cite origin-repo numbers (055..107; 045/047/029 mean different things here). Map or replace with names.
- [ ] Broken refs: Design.swift, windows workflows location, tvos-playbook case, missing tools (capture-imessage-screenshots, roku_design_lint, atv_install, rtdb_join, submit-amazon, youtube_refresh_token, free_subtitles), TV backlog store paths, /status and /decision commands
- [x] `refresh-skills.sh` now treats every skill already in the template as canonical; only new global skills are copied in, differing ones are reported (tick 13)
- [ ] Merge overlap clusters: device testing, Apple submission, tvOS, smart TV, Windows, Play
- [x] (ticks 26-27) Final consistency pass: link/path scan, all tests, Android build, Windows tests, skill frontmatter, workflow gates, private-data scan (room names, store ids and incident details generalized).

## Log

- **Tick 1.** Surveyed. Launched the gap audit and the inventory.
- **Tick 2.** Wrote this plan and the writing guide while the agents run.
- **Tick 27.** Final verification all green (11 Python test files, web suite 0 FAIL, gates clean, 144 skills valid, Android assembleDebug + unit tests, Windows 11/11). A first private-data scan was blind (zsh does not word-split a variable) and reported nothing; re-run with xargs found room names, real store ids and incident details, all generalized. Committed and pushed.

## Second round (Ben, 2026-09-30, after the first push)

> Let's take another couple of passes on the flow of the phases and the
> instructions at the bottom of each markdown file in the "What to do"
> section. [...] The goal is to teach others how to build software in
> the way that I actually build software. Never did I run a localhost
> web server. Never did I manually input data for the apps.

- Mined 612 of Ben's own prompts (Archive Watch and Tidbits transcripts)
  and 1,670 commits that quote him into `HOW-BEN-BUILDS.md`.
- New `docs/path/talking-to-your-agent.md`: the moves he actually uses,
  in his words.
- Every stage now opens with **Where you are** and closes with **When
  you are ready to move on**, so the stages hand off to one another.
- "What to do" became **Working with your agent**: what you say, what
  the agent does, what you look at, what you decide. No local servers,
  hand-typed data, file editing, or commands to run.
- COURSE.md weeks now describe the app growing; class time reads one
  real prompt together.
- Apple project generated from `project.yml` by the agent (XcodeGen),
  so stage 03's "the agent sets up the project" is true. Verified: generate + unsigned build for iOS, tvOS, macOS; floor tests pass (and `test_ios_floor.py` had a bug that made it blind to universal targets, now fixed with a control).

## What is still open

- Ben's call: whether `docs/path/` as the course spine plus the ten-week `COURSE.md` sketch is the shape he wants.
- A social posting pipeline and `social-video-teaser-craft` were not ported (PROVENANCE exclusions).
- The Apple starter now generates from `project.yml` and builds unsigned for iOS, tvOS and macOS, but only on the Xcode 27 beta (no GA Xcode on this Mac); no signed archive or CI run yet; tvOS still needs a layered icon before a store submission.
- DECISIONS.md keeps its historical em dashes (append-only).
- **Tick 26.** Path/link scan over all human-facing docs, CLAUDE.md, templates and hand-written skills: every miss is an adopter-created file except four; fixed. Ported tools/test_us_english.py (2,805 strings, pass) and tools/test_web.sh (all web suites, parse, braces: pass), both cited by skills and never ported. Next: final full verification, then commit + push.
- **Tick 25.** Revision: 03 (two unsourced claims), 04 (unsourced timing), 07 (server contradiction; question attributed to the investigation doc, not the agent). 01, 05, 06, 08 re-read; no changes needed beyond earlier fixes. Next: link/path check across all docs, final test run, then commit + push.
- **Tick 24.** Both voice-pass agents landed. Fixed ANDROID-DESIGN §1.4 (template said manual DI; starter uses Hilt), added TV and Windows rows to the design-doc index, renamed Apple tokens to brandPrimary/brandSurface (Color.primary clashes with SwiftUI), removed three semicolons from path stages.
- **Tick 23.** PROVENANCE rewritten (audit list, 13 new rows, new exclusions, dashes out and hand-fixed). Two voice-pass agents running (root docs + CLAUDE.md; templates/store/windows/research).
- **Tick 22b.** W3+W4 landed (21 skills, PARITY.md, DATA-CONTRACT/WEB/MACOS/TVOS/IOS templates, DEEP_LINKS 'State in the link', new PORT-PARITY-LEDGER, FEATURE-DESIGN, IPAD-DESIGN templates, Decision 025 amended). Applied its CLAUDE.md additions (floors in parity, rule-is-a-value, Mac/tvOS/web guardrails, design-doc and parity paragraphs, data-contract-is-a-test, determinism Rule 0, four standing rules). All six workstreams done. Remaining: PROVENANCE update, revision pass 01/03-08 + README/COURSE, voice pass on CLAUDE.md and other docs, final link check, commit + push.
- **Tick 22.** Revision pass began. 00: removed an 'it's not X, it's Y' line, softened three unsourced claims. 02: Roku as the fourth codebase, double 'so', hedged the agent-cost argument as Ben's guess. Next: 01, 03, 04.
- **Tick 21b.** W5 landed: docs/ENGINEERING-PROCESS.md (13 disciplines), AUTONOMOUS-LOOPS rewritten (owner/agent split corrected, working style, context hygiene), loop skill. Applied wording: CLAUDE session-log rule (two entries + docs/SESSION-LOG.md), SCRATCHPAD header, /milestone, feature-shipping versioning, PROVENANCE §10, docs map, path 08.
- **Tick 21.** CLAUDE.md table by stage. Launched W3+W4 agent (parity/contract/ceiling lessons into skills, PARITY.md, new PORT-PARITY-LEDGER / FEATURE-DESIGN / IPAD-DESIGN templates) and W5 agent (docs/ENGINEERING-PROCESS.md, AUTONOMOUS-LOOPS fixes). De-branding agent still running.
- **Tick 20.** README front door, docs map, COURSE.md. De-branding agent running (TV/Windows/Owner templates, TVOS-PLAYBOOK, TV-PLATFORMS, runbooks, MEDIA-PLAYBACK). Removed stray gates.log.
- **Tick 19.** Drafted stage 08. Next: docs/README map, README front door, COURSE.md, CLAUDE.md reorder, PROVENANCE, then revision pass over all stages.
- **Tick 18b.** Tools-generic agent landed: runner SCENARIOS/qa_suite/hook_coverage now generic FILL IN examples matching the starters; web_run uses ?view=/?item=; atv_run and ios_run grade left_as_found; workflow-health gate step warns instead of failing; reporter skips in-flight fixes; Play notes cap/5xx retry/changesNotSentForReview; asc_build_exists reads app_config; DEVICE-AUDIT-LEDGER template. Doc wording applied.
- **Tick 18.** Drafted stage 07.
- **Tick 17.** Drafted stage 05. Tools-generic agent running.
- **Tick 16.** Doors landed in all four starters (DEBUG-only; web as URL params), runners standardized on app_config names; I re-ran Android unit tests (green) and hook_coverage (start tab/item/mute/door-seconds yes on every platform). Docs updated (CLAUDE item 7, fleet doc §3, harness catalog, path 04, androidtv skill). Follow-ups: web_run.py uses trivia hash routes; runners' SCENARIOS tables and hook_coverage rows are still trivia-specific (make FILL IN).
- **Tick 15.** tools/README written.
- **Tick 14.** Skills catalog written. Doors agent running.
- **Tick 13b.** Submission/CI docs + scrub landed (CLOUD-SUBMISSION = build/sign/upload, APPLE-SUBMISSION-CLI = version/release/review; CI-FLEET §6/§10; five skills; origin identifiers scrubbed from tools and workflows; play-release inputs now env). All 144 skills validate. Fixed stale claims: DECISIONS ceiling 50 KB (CLAUDE, AUTONOMOUS-LOOPS, Decision 033 amended), Android versionName from xcconfig, tvOS 27 Dynamic Type, Decision 004 amended for floors, androidtv skill door names. Doors agent launched. Open gaps from the scrub report: README still shows removed appstore-submit inputs (README rewrite will fix); AUTONOMOUS-LOOPS §5 says store console is owner-only (now CLI); workflow-health's gate step can go red inside a reporter; report_workflow_health doesn't skip in-flight fixes; submit-play.sh / play-publish.py lack the 500-char notes check, 5xx retry, changesNotSentForReview; asc_build_exists ignores app_config.
- **Tick 13.** Skill hygiene: 12 duplicates deleted (144 skills), refresh script can no longer roll back template skills, long descriptions trimmed. Asked the scrub agent to fix frontmatter it broke (play-cli-submission YAML; store-submission-playbook and ci-fleet-engineering over 1024). NEXT: skills catalog README once the scrub agent lands.
- **Tick 12b.** Device-testing docs consolidated (AUTONOMOUS-FLEET-TESTING = method, DEVICE-HARNESSES = per-platform catalog; skills point into them). **Found: no starter (web, Apple, Android, Windows) implements a single door**, while the docs and path stage 04 promise them; runners use `APP_TAB`, app_config says `APP_START_TAB`. NEXT (after the scrub agent finishes, it touches the same tools): door agent to standardize on app_config names and add APP_START_TAB / APP_START_ITEM / APP_MUTE / APP_DOOR_SECONDS to all starters as release no-ops. Other W2 follow-ups: runners' SCENARIOS tables still carry the trivia app's surfaces (make them FILL IN); `mdns_prefix` bench field undocumented in bench.py/example; atv_run doesn't grade left_as_found; DEVICE-AUDIT-LEDGER template missing.
- **Tick 12.** Rewrote docs/PRODUCT-PULSE.md. W6 complete except path-stage polish.
- **Tick 11.** Drafted stage 06.
- **Tick 10 (resumed; Ben: "commit to Github with all results once the loop is completed").** Pulse port (W6) landed: I re-ran 103 + 53 + 39 tests green, leak scan clean, viewed the fixture render. Report saved to `PULSE-PORT-2026-09-30.md`. Drafted stage 04 (seeing it work). Launched two agents: device-testing reference docs consolidation (26 lessons into AUTONOMOUS-FLEET-TESTING / DEVICE-HARNESSES), and submission/CI docs + origin-name scrub of tools. Commit + push only at the end of the loop.
- **Tick 9.** Drafted stage 03 (floors by hardware, AW 141/148/154/155, Ben's quotes). CLAUDE.md floor text updated (iOS 18 / tvOS 26 below 27 / macOS 26; Android minSdk guidance). W2 harness port landed; I re-ran its tests (all pass); report saved to `HARNESS-PORT-2026-09-30.md` (26 lessons, source for stage 04). Follow-ups from W2: grep still finds origin-app names in ~9 older tools (audit_fire_tv_gms, gh_dispatch, retry_infra_failures, make_tv_banner, ffmpeg_limits, measure_start_times, catalog_delta, tv_browser_tests, test_pulse_collect); tv.js boot focus lands on the skip link; Sign in button 13px on TV; roku lint needs --allow-missing in CI. Loop paused here: usage limit reached. Nothing committed yet. NEXT: stage 04 from the harness report, W6 Pulse review, skills catalog README, tools README.
- **Tick 8.** Android P0 closed and verified.
- **Tick 7.** Drafted stage 01. Agents W2, W6 (Pulse), Android P0 still running.
- **Tick 6.** Drafted stage 02. Reviewed and re-ran W1. Found the Android scaffold broken on a fresh clone; P0 agent on it. Pulse agent (W6) and W2 still running.
- **Tick 5.** Drafted `docs/path/00-why-we-build.md`, anchored in Ben's 2026-09-26 no-AI-copy rule and the "Computer-Shaped Problems" page (learningischange.com, 2026-03-04). Port agents W1 and W2 running.
- **Tick 4.** Gap audit landed (63 unaudited AW decisions; 45 device-testing lessons). Split it into workstreams W1-W5.
- **Tick 3.** Inventory landed. Fixed the session-start hook, the four broken frontmatters, and the live pulse cron. Folded the inventory's findings into the checklist.
