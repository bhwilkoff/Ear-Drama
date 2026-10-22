# Where each rule in AGENTS.md went

On October 3, 2026, `AGENTS.md` was 49,871 bytes, and Antigravity, which
stops reading any rule file at 24,000 bytes, saw only its first half
(`docs/research/gemini-and-other-agents.md`). Ben decided that day that
`AGENTS.md` stays under 24,000 bytes, with the rules and values in it and
the platform playbooks in docs it links to (humanshaped.org
`DECISIONS.md`, "Teaching, agents, and events"). It is now about 21,800
bytes, and `tools/test_agent_files.py` fails if it reaches 24,000 or if
any doc it links to goes missing.

I wanted the cut to lose nothing, so before anything moved, every rule
and instruction in the old file went on the checklist below, and after
the move each one was checked against where it now lives.

**Every rule is in `AGENTS.md` or one link away from it.**

## How it was checked

1. Every non-blank line of the old file was looked for, word for word,
   in the new `AGENTS.md` and in `docs/platforms/`. The platform
   sections, the per-platform skill notes, the full design system, and
   the full shared-data section all matched, because they moved without
   a word changed.
2. The lines that did not match belong to sections shortened in place
   (how we build, debugging, what this app does, binding design docs,
   parity, automation, collaboration, standing instructions, current
   state). Each rule in those sections is listed below with where it
   stands now, and was read against the new text by hand.
3. For the automation bullets, the detail that left `AGENTS.md` was
   found in the doc each bullet links to before it was cut.

"Kept" means the rule is still in `AGENTS.md`, sometimes in fewer
words. "Kept, short" means the rule is in `AGENTS.md` and its full
wording, with the examples, is in the linked page.

## The checklist

### Why we build

| Rule | Now |
|---|---|
| Every feature serves learning; reconsider what makes people passive, prioritize what opens curiosity | Kept, word for word |
| Invoke `learning-orientation-design` before any feature (three questions, then four) | Kept, word for word |
| Human-facing version is `docs/path/00-why-we-build.md` | Kept |
| Human-shaped software; learning three ways; propose, don't decide | Kept, word for word |
| Three moves: write, play, publish (renamed October 5, 2026, from "write it down, prove it, live with it") | Changed with Ben's review |

### How we build

| Rule | Now |
|---|---|
| Skills live in `.claude/skills/`, catalog in its README; invoke, don't re-derive | Kept |
| `AGENTS.md` is the one source; Claude Code and Gemini CLI import it; Antigravity cuts at 24,000 bytes | Kept, plus the new rule that this file stays under 24,000 bytes (Standing instructions) |
| `.agents/skills/` holds the three learner skills and `template-skills` | Kept |
| No skill mechanism: open the SKILL.md and follow it | Kept |
| The skill table, by stage | Kept, every row and every skill. Some trigger cells are shorter; each skill's own description and `.claude/skills/README.md` carry the full trigger |
| iOS / iPadOS: `ios-production-gotchas` first, its symptoms, `ios-share-extension`, the 86 Apple skills | `docs/platforms/apple.md`, "Which skill" |
| macOS: `macos-platform-patterns` before Mac work, and the Mac-only traps | `docs/platforms/apple.md`, "Which skill" |
| tvOS: `tvos-platform-patterns` before tvOS work; adapt `docs/TVOS-PLAYBOOK.md` after about three screens | `docs/platforms/apple.md`, "Which skill" |
| Android: `android-production-gotchas` first; the Android skill stack via `tools/install-android-skills.sh` | `docs/platforms/android.md`, "Which skill" |
| Android TV / Fire TV: `androidtv-compose-focus` and its rules | `docs/platforms/tv.md` |
| Smart-TV web: `smarttv-web-app`, `docs/TV-PLATFORMS.md` | `docs/platforms/tv.md` |
| Windows: `windows-production-gotchas` first; the scaffold; `docs/windows/` | `docs/platforms/windows.md`, "Which skill" |
| Web: `web-platform-patterns` umbrella; `web-content-extraction`; `KUI:<name>`; `frontend-design` | `docs/platforms/web.md`, "Which skill" |

### Debugging philosophy

| Rule | Now |
|---|---|
| Don't iterate blindly; diagnostics first | Kept |
| 1. Observability before another implementation | Kept |
| 2. Isolate layers; the bug is where output diverges | Kept |
| 3. `print` / `console.log` / `Log.d`, not `os.Logger` | Kept |
| 4. Temporary visual overlay for invisible UI bugs, doubly on tvOS | Kept |
| 5. Offline sim for visual and 3D bugs; Roborazzi on Android; Node DOM shim on the web; headless Chrome's timer distortion | Kept |
| 6. Env-gated permanent diagnostics; remove one-offs | Kept |
| 7. Launch doors for known states; their files; names from `tools/app_config.py` | Kept |
| 3+ iterations of "still broken": `3d-feature-debug-loop` | Kept |
| One simulator or emulator at a time; real-device check for filesystem, entitlements, sync | Kept |

### What this app does

| Rule | Now |
|---|---|
| Fill in what the app does | Kept |
| Five core platforms, the optional ones; note equivalent work in SCRATCHPAD.md, update PARITY.md | Kept |
| Feature parity, not design consistency | Kept |
| Decide the platform set in M0, record it; when tvOS and macOS earn their place | Kept |
| A skipped platform is a 🚫 column with a reason | Kept |

### Web app

Every rule moved word for word to `docs/platforms/web.md`: the stack and
hosting, the key directories, running locally and deploying, all API
calls through `js/api.js`, CSS custom properties from the tokens,
`min-width` queries, no inline styles, user-visible errors, URL-driven
state and the `https` twin, lists in the link, `cache:'no-store'` and the
service worker, `[hidden]` against author `display`, every `API.x`
exported, the Safari layout rule, and the modern web APIs to reach for.
The API-client and deep-link rules are also in `AGENTS.md`, "Hard rules
on every platform".

### Apple apps

Every rule moved word for word to `docs/platforms/apple.md`: the stack,
the floor is a floor (measured floors, `tools/test_ios_floor.py`,
`tools/test_tvos_floor.py`, the Archive Watch defaults, `#available`,
the untyped stored property, older devices are the website's job), one
universal target, `project.yml` as the source of truth, the folder tree,
all eleven critical conventions, the ten macOS guardrails, and the six tvOS
guardrails. The shared client, JWT refresh, deep-link inbox,
`AppVersion.xcconfig`, and no-packages rules are also in "Hard rules on
every platform".

### Android app

Every rule moved word for word to `docs/platforms/android.md`: the stack
and floors (and Fire TV's 28), the project tree, and all fifteen critical
conventions. The shared client, JWT refresh, version bump, and secrets
rules are also in "Hard rules on every platform".

### Windows app

Every rule moved word for word to `docs/platforms/windows.md`: the stack
and why Avalonia, the four-project scaffold and the TFM trap, the parked
workflows, CI as the loop, and all eight critical conventions, including
the full ship command.

### Shared design system

| Rule | Now |
|---|---|
| `design-tokens.json` is the one source; generator, test, change process, never hand-edit | Kept, short |
| Which file each platform generates, and the names each reads | `docs/platforms/design-system.md` |
| Brand colors for chrome, semantic colors for meaning; add domain colors to the JSON | Kept |
| Six levels; refuse a seventh | Kept |
| The type ramp table; Apple keeps system styles; tvOS's ramp, 29pt floor, and tvOS 27 Dynamic Type | `docs/platforms/design-system.md` (the 29pt floor and "system tokens only" also kept) |
| Density from removing chrome; 375px first; focus does the work on tvOS | Kept |
| Haptics taxonomy and its two binding pairings, one mapping place | Kept, short |
| R-ICON-1: icons from the platform system, emoji are content | Kept, short |

### Binding design docs

| Rule | Now |
|---|---|
| Past about five views, add the platform's design doc from `docs/templates/` | Kept |
| Quote the rule first; fix the doc, then the feature | Kept |
| Shared principles, divergent idioms; say so when a rule inverts another | Kept |
| Not on day one; binding once created | Kept |
| iPad design doc; feature design doc; a rule for all platforms stamped everywhere the same day | Kept |

### Cross-platform feature parity

| Rule | Now |
|---|---|
| `PARITY.md` is the source of truth; the periodic audit | Kept |
| Mirror in the same change set; same verb, native idiom | Kept |
| Port ledger; mechanical guard with a negative control; floors row; `n/a` vs a sentence on screen | Kept |

### Shared data plane

| Rule | Now |
|---|---|
| Build the data plane once; data contract at the second client; the contract is a test; projections and shared predicates | Kept, short, and word for word in `docs/platforms/shared-data.md` |
| Determinism: publish the result; one algorithm per language with a golden test; no seeded shuffle; hash-rank; the Kotlin `Byte` gotcha | Kept, short, and word for word in `docs/platforms/shared-data.md` |
| Multiplayer rides a transport seam | Kept, short, and word for word in `docs/platforms/shared-data.md` |

### Automation, CI, and verification

| Rule | Now |
|---|---|
| `docs/CI-FLEET.md`: green did something, red means something, nothing destroys work; a red X is for broken; enable the two guardian workflows; start writers from the template | Kept, short; the lock split, publishing budgets, guarded restores, sweeper, and auditor are in `docs/CI-FLEET.md` |
| `docs/AUTONOMOUS-LOOPS.md`: never the tester; external observation; verified vs merely fixed; DECISIONS.md context-sized | Kept, short; the archive at about 50 KB is in the doc |
| `docs/ENGINEERING-PROCESS.md`: thirteen disciplines | Kept, short; all thirteen are in the doc |
| `docs/MEDIA-PLAYBACK.md` for media apps | Kept, short |
| `docs/PROVENANCE.md`: upstream the generic form in the same session, update the map | Kept |
| `docs/DEVICE-HARNESSES.md` and the instrument-honesty rules | Kept; the per-platform catalog is in the doc |

### How we collaborate

| Rule | Now |
|---|---|
| The memory ratchet: corrections and confirmations with a Why line, project state with a date, an index | Kept |
| Fix the doc first, then the feature | Kept |
| Trust but verify subagent summaries | Kept |
| Auto-pace decisiveness | Kept |
| Verify before declaring done; rebuild every platform after a shared file changes | Kept |
| Show the evidence, not the claim (the command and what it returned, or a screenshot) | Added October 7, 2026, from both tools' docs (`docs/research/curriculum/03-claude-code-and-antigravity.md`) |
| Capture the ratchet in DECISIONS.md or memory | Kept |
| Session log: two entries, roll to `docs/SESSION-LOG.md`, fix drift first | Kept |

### Standing instructions

All fourteen kept: read the skill first, quote the request in commits,
DECISIONS.md leads with why, nothing beyond the request, scoped diffs, no
comments by default, no emojis, value rules name their check, only
essential words on screen, no AI-written copy in the product, side doors
on the website only, one spelling locale, cross-platform parity, and
"Out of scope" on rejection. One was added: `AGENTS.md` stays under
24,000 bytes.

### Current state

| Rule | Now |
|---|---|
| `SCRATCHPAD.md`, `DECISIONS.md`, `PARITY.md` | Kept |
| Cloud submission, CI, loops, harnesses, TV stores, Windows docs | Under "Automation, CI, and verification" and "Where each platform's rules live" |
| Humans start at `docs/path/` and `COURSE.md` | Kept |

## The short version, for small models

`AGENTS-SHORT.md` is a few hundred words for agents running a small
local model, where all of `AGENTS.md` would fill most of an 8,000-token
context before the student says a word
(`docs/research/curriculum/04-open-pathway.md`). It holds the why, the
three moves, the few rules that matter most, and where the rest lives.
It is not a second source: when a rule in it changes, `AGENTS.md`
changes first, and `tools/test_agent_files.py` fails if the short file
grows past 4,000 bytes or stops pointing to `AGENTS.md`.

## When you add a rule

Ask whether it holds on every platform. If it does, it belongs in
`AGENTS.md`, and the byte count is the cost to weigh. If it holds on one
platform, it belongs in that platform's page in `docs/platforms/`, and
`AGENTS.md` already points there.
