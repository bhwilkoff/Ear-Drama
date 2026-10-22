# The docs

`docs/path/` is where you start. Everything else in this folder is
reference: the detail a stage points to when you need it, and not
before. This page lists every doc by the stage that sends you there.

## The stages

`path/00-why-we-build.md` through `path/08-working-with-ai.md`. Read them
in order the first time. `path/talking-to-your-agent.md` is the companion
to all of them: how to ask, correct, and decide, in real prompts.
`path/showing-your-work.md` is the other: how to bring each stage's work
back and get feedback on it, in a cohort or on your own.

## Teaching

`../COURSE.md` maps the stages onto a five-week cohort, and
`teaching/README.md` is the guide for each of its live sessions: the
minutes, the teacher's words, the check question, and what to look for
in the bring-backs.

## When you are stuck

`stuck/README.md` is the library for the moments when the work stops:
stuck writing, stuck playing, and stuck publishing, one page per stuck
moment, each starting with a question to ask yourself and ending with
who to ask. It also holds the ladder to climb when none of the pages
fits.

## By stage

**00. Why we build**

- `research/values-based-approaches.md`: Value Based Engineering (IEEE 7000) and other values-based traditions, set beside how this template works, with proposed changes. The sourced notes behind it are in `research/notes/`.

**02. The shape of an app**

- `templates/DATA-CONTRACT-template.md`: seed for your data contract, written the day a second app reads your data.
- `templates/PLATFORM-DESIGN-template.md`: how the per-platform design docs fit together; start here before seeding one.
- `templates/FEATURE-DESIGN-template.md`: a binding doc for one feature whose capability differs by OS or hardware.
- `research/sync-architecture.md`: the research behind syncing watch state on each person's own cloud.

**03. Going native**

- `platforms/`: each platform's rules for the agent (`web.md`, `apple.md`, `android.md`, `windows.md`, `tv.md`), plus `design-system.md` and `shared-data.md` in full. They moved out of `AGENTS.md` so that it fits under the 24,000 bytes Antigravity reads, and `AGENTS.md` says when to read each one.
- `templates/IOS-DESIGN-template.md`, `MACOS-DESIGN-template.md`, `TVOS-DESIGN-template.md`, `ANDROID-DESIGN-template.md`, `WEB-DESIGN-template.md`, `WINDOWS-DESIGN-template.md`: seeds for each platform's binding design doc, once it passes about five screens.
- `templates/IPAD-DESIGN-template.md`: the regular-width iPad rules that extend the iOS design doc.
- `templates/PORT-PARITY-LEDGER-template.md`: the three-level ledger for a platform that ports another.
- `TVOS-PLAYBOOK.md`: the long-form Apple TV playbook (focus, ten-foot type, playback).
- `TV-PLATFORMS.md`: the smart-TV landscape beyond Apple, store by store.
- `templates/TV-DESIGN-template.md`, `templates/TV-PLATFORM-BACKLOG-template.md`: seeds for a TV design doc and a TV porting backlog.
- `research/tv-design-reference.md`: a design study of well-made ten-foot apps.
- `windows/WINDOWS-PLAYBOOK.md`: Windows from a Mac, with CI as the Windows machine.
- `runbooks/cloudkit-setup.md`, `runbooks/google-oauth-setup.md`: one-time setup for sync on Apple and on Android and web.

**04. Seeing it work**

- `AUTONOMOUS-FLEET-TESTING.md`: the method. The ladder, the bench and its roles, leases, leaving the room as you found it, honest verdicts.
- `DEVICE-HARNESSES.md`: the catalog. Every platform's tools, commands and traps.
- `templates/DEVICE-AUDIT-LEDGER-template.md`: seed for a device audit.

**05. Shipping**

- `CLOUD-SUBMISSION.md`: build, sign and upload every Apple platform from a GitHub runner.
- `APPLE-SUBMISSION-CLI.md`: create the version, attach the build, submit for review.
- `store/STORE-SCREENSHOTS.md`: the screenshot rules each store enforces.
- `store/play-api-key-setup.md`, `store/PLAY-DASHBOARD-RECOMMENDATIONS.md`: Google Play API access, and what Play's dashboard warnings actually mean.
- `store/IAP-TROUBLESHOOTING.md`, `store/IAP-RELEASE-CHOREOGRAPHY.md`: in-app purchases across stores, and the order to launch them in.
- `store/webos-submission.md`, `store/tizen-submission.md`: LG and Samsung television stores.
- `windows/WINDOWS-STORE-SUBMISSION.md`, `windows/APPLE-SIGNIN-WINDOWS.md`: the Microsoft Store, and Sign in with Apple on Windows.
- `windows/workflows/`: the Windows workflows, to copy into `.github/workflows/` when you adopt Windows.
- `templates/OWNER-PLAYBOOK-template.md`: splitting launch work between the owner and the agent.

**06. Keeping it running**

- `PRODUCT-PULSE.md`: the dashboard, its rules, and how it was built.
- `CI-FLEET.md`: scheduled workflows that never lose work and never cry wolf.
- `templates/split-writer-workflow-template.yml`: start any data-writing workflow from this.
- `AUTONOMOUS-LOOPS.md`: running an agent in timed ticks, safely, and what stays human.
- `ENGINEERING-PROCESS.md`: thirteen disciplines, each with the incident that taught it.
- `runbooks/data-recovery.md`: recovering a published data file that a workflow overwrote, from releases and git history.

**07. Raising the ceiling**

- `MEDIA-PLAYBACK.md`: streaming and captions, for media apps.
- `runbooks/tvos-top-shelf-setup.md`: the Apple TV Top Shelf.
- `research/social-clip-creation.md`: research on making short social clips from archival film.
- `templates/TRADE-DESIGN-template.md`: seed for any feature where people trade with one another.

**08. Working with AI**

- `PROVENANCE.md`: where every lesson in this template came from, and what was left out on purpose.
- `research/gemini-and-other-agents.md`: what Gemini CLI, Antigravity, and Claude Code each read in this template (instructions, skills, commands, MCP), tested where it could be, and the Gemini equivalent of each Claude-only step in the path.

## For whoever maintains the template

`maintaining/` holds the writing guide (`WRITING.md`), the plan and
record of the September 2026 reorganization, the audits it was built
from, and `AGENTS-MD-MAP.md`, which says where each rule went when
`AGENTS.md` was cut below 24,000 bytes.
