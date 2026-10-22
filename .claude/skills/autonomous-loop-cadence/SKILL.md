---
name: autonomous-loop-cadence
description: "Use when running an autonomous /loop on a multi-platform codebase, or picking one up after compaction. Governs what goes IN each tick: platform rotation with an opt tick every fifth, mining real user requests before inventing work, audit-before-ship, one version convention (commits bump PATCH; MINOR only when a release carries something new), verified vs fixed vs shipped, announcing the next tick in the owner's local time BEFORE scheduling it, the owner/agent split (the whole store ship is CLI; accounts, payments, agreements, privacy answers, console-only declarations and demo videos stay human), working-style rules (read the runbook first, audits fix what they find, warnings are defects, commit -F with a quoted heredoc), context hygiene (two scratchpad entries, ship state from Pulse, DECISIONS rolls at ~50 KB), and stop conditions. Triggers on /loop with no interval, 'keep iterating', 'loop all night', AUTONOMOUS_PROGRESS.md, resuming a loop. Depth: docs/AUTONOMOUS-LOOPS.md and docs/ENGINEERING-PROCESS.md."
---

# Autonomous loop cadence (multi-platform)

The `/loop` skill schedules the next tick. This skill governs what goes
in each tick. Read `docs/AUTONOMOUS-LOOPS.md` (verification, the
owner/agent split, working style, context hygiene) and
`docs/ENGINEERING-PROCESS.md` (the engineering disciplines, each with
its incident) before the first tick of a session.

Single-platform project: use `feature-shipping-discipline` instead.

## Every tick

1. **Read the runbook first.** Before any operational step (store ship,
   device run, demo recording), grep `docs/`, `tools/`, and the memory
   folder for it. The owner, 2026-09-24: "Please stop trying to reinvent
   things you already know how to do."
2. **Diagnose, fix, verify, log.** One unit per tick. Never stack an
   unverified fix on another.
3. **Verify by external observation** (glass, audio meter, re-downloaded
   artifact, store API). The agent is never the tester.
4. **Commit and push the verified unit.** `git commit -F` with a quoted
   heredoc (`<<'EOF'`), never `-m` with backticks. Quote the owner's
   request verbatim.
5. **Log** in the session entry: verified vs merely fixed vs shipped.
6. **Announce, then schedule.** The last line of the turn is
   `Next tick: <clock time>` in the owner's local time, computed from
   the delay you are about to pass. Then call the scheduler (it ends the
   turn; text after it is never seen). Stopping instead? Say so.

## The rotation

```
tick % 5  ->  what
  0       ->  opt (net-remove lines)
  1, 4    ->  least mature platform
  2       ->  platform #2
  3       ->  platform #3
```

- The least mature platform gets 2 of 5 ticks, so parity catches up.
- Every fifth tick is opt, or the codebase only grows.
- Pick the ratio per project. The discipline is a fixed rotation plus
  opt every fifth.

## Source of work, in priority order

1. User requests mined from research, support, or handoff folders.
2. The deferred-work list (SCRATCHPAD.md, roadmap, milestone docs).
3. Parity gaps (PARITY.md cells marked pending).
4. Out-of-band asks the owner dropped into the loop.

Never invent the next feature. When the backlog is two items or fewer,
mine again. (BOBA, tick 178: "these loops are really circling around the
same exact features.")

**Mining:** send a general-purpose Agent at the folder, filtered against
PARITY.md and DECISIONS.md rejections. Ask for 8 to 15 ranked items,
punch-list shape (title, what, platforms, evidence, S/M/L), under 600
words. Write the list into AUTONOMOUS_PROGRESS.md. The agent is wrong
sometimes: at BOBA tick 179 its top item already existed on all three
platforms.

**Audit before shipping:** grep for the feature on the target platform
first. If it exists, fix the matrix; that is the tick. This caught 8
false pending rows at BOBA tick 196.

**An audit loop fixes what it finds without asking.** Ask only for
content or rights calls, product direction no rule settles, and
anything outward-facing.

## Opt ticks

Must net-remove lines unless they are CI fixes: dead code, stale
planning collapsed, needless guards, duplicate narrative, comment trims.
An opt tick that adds lines is the anti-pattern. If nothing is
removable, log a no-op tick. Orphan-symbol greps miss trailing lambdas,
fully qualified references, and function references without `()`; see
`docs/AUTONOMOUS-LOOPS.md` §10.

## Parity sweeps

A multi-platform item ships over consecutive ticks, least mature
platform first, reusing names and identifiers so the implementations
read as parallel. The last tick's commit says "closes the trio."

## Versions (one convention)

- Every commit touching app source: PATCH +1 in `MARKETING_VERSION` and
  build +1, both in `AppVersion.xcconfig`, in the same commit.
- MINOR +1 (PATCH 0) only when a release carries something a person
  would call NEW since the last RELEASED version (a feature, a new
  surface). A fix-only release keeps its minor and ships at its patch,
  and an upload never bumps the minor by itself. Decide on purpose
  before each release, against the last released version.
- Pipeline, CI, and docs-only commits do not bump. Never hand the bump
  to CI.

## Stores

- The whole ship is CLI: `tools/asc_release.py ship` / `status`, the
  Play API via `play-release.yml`. Never ask the owner to press Submit.
- Read what is live (`asc_release.py status`, Pulse), never your notes.
  Verified is not shipped: Archive Watch was once 41 versions behind.
- Batch trivial changes (wording, comments, CI, docs) into the next real
  release.
- No new Play upload while a version is in review.
- A local beta Xcode passing is not the store build passing. Run the
  cloud build with `submit=false` when anything is new.
- Owner-only: accounts, payments, agreements, privacy answers,
  console-only declarations, demo videos, hands-on device QA.

## CI gates

| Pushed | Next-tick delay |
|---|---|
| Android | about 270s (wait for the Gradle result) |
| Apple source | about 270s |
| Web only, docs, data | about 90s |

Warnings are defects: report the warning count from a clean build, aim
for zero. "Unable to type-check in reasonable time" usually means a
wrong or duplicated argument label; check the callee's signature before
splitting the view.

## Out-of-band requests

Acknowledge with "queued for tick N", write it under "Pending
[platform] asks" in AUTONOMOUS_PROGRESS.md, commit that immediately, and
pull it when the rotation reaches that platform. Do it now only when the
owner says now.

## Durable progress and context hygiene

Each tick appends to AUTONOMOUS_PROGRESS.md and is committed:

```markdown
### Tick N, YYYY-MM-DD, [platform]: [one line]
- Context / Implementation / Verification / Lessons / Next
```

- SCRATCHPAD.md keeps two session-log entries; the oldest moves
  verbatim into `docs/SESSION-LOG.md`.
- Ship state comes from Pulse, not typed numbers.
- MEMORY.md: one line per entry.
- DECISIONS.md rolls at about 50 KB, verbatim, into `docs/decisions/`.
- A lesson that burned a CI cycle becomes a memory file with a Why line,
  linked from MEMORY.md.
- Times to the owner are in their local time, never UTC.
- Run `tools/dev_cleanup.sh` before the loop goes quiet.

## Stop conditions

1. The owner says stop. Write a final tick log; do not schedule; no push
   notification (they are here).
2. Backlog empty after a fresh mine. Notify: "loop idle, backlog empty."
3. Three or more ticks in a row broke CI. Stop and surface the pattern.
4. A multi-tick refactor is mid-flight and not shippable.

Never re-schedule after a stop. One tick is one commit is one push, so
reverts stay surgical.

## See also

`binding-design-doc-discipline` (quote the rule inside feature ticks),
`feature-shipping-discipline`, `architectural-decision-log`,
`3d-feature-debug-loop` (three strikes), `ci-fleet-engineering`.
