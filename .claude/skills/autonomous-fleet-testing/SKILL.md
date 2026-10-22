---
name: autonomous-fleet-testing
description: "Build, extend or run automation that drives REAL devices (iOS, iPadOS, tvOS, macOS, Android, Google TV, Fire TV, Roku, web TV, Windows, web) and grades the app from the screen rather than its own logs. Invoke when setting up a device bench (bench.json, roles, app_config.py), writing a runner or scenario, adding launch doors, when a suite passes while the product is visibly broken, when a check might be blind, when a verdict is flaky, when a surface cannot be reached, or when calibrating OCR thresholds. Carries the doctrine, the bench roles, leave-as-found, and the verdict rules (determinism, instrument-fault taxonomy, skip is not pass, see it fail)."
---

# Autonomous testing across a fleet of real devices

**Read the runbook before planning device work.** The method is
`docs/AUTONOMOUS-FLEET-TESTING.md` (section numbers below refer to it). The
per-platform commands and traps are `docs/DEVICE-HARNESSES.md`. Grep both,
`tools/*` docstrings, and memory before inventing anything: most device
problems here were solved once already.

## The doctrine

The app's claim is never evidence; the screen is. Drive the real app,
photograph the glass, OCR it, grade explicit assertions. The agent is
never the tester. Climb the ladder (doors, simulator, real bench, person)
only as far as needed to see the bug.

## Before a run

- Bench: `python3 tools/bench.py check`. Every device has a role.
  `owner-personal-never-touch` is refused always; `owner-watches` needs
  `--owner-ok` AND the owner's say-so. Setup walkthrough: section 4.
- `tools/app_config.py`: identity, `APP_ANCHOR_RX` from words the UI
  really renders, calibrated `CLIP_X` / `MIN_OCR_LINES`.
- Reachability: `python3 tools/hook_coverage.py`. A surface nothing can
  drive reads as a pass (section 3).
- Entry point: `python3 tools/qa_suite.py [--devices a,b]`.

## During a run (sections 6 to 8)

- One lease for the whole run, one process (`devlease.hold()`; children
  inherit via `child_env()`). Leased elsewhere means SKIP, never a pass.
- Doors muted and time-bounded by default (`DOOR_DEFAULTS`). `--audible`
  only after asking.
- Every capture through `capture_fresh()`. Power state asked, never
  inferred from pixels. Readable-but-wrong-app is a failure.
- Android: debug build, quoted extras.
- Teardown is a step with an assertion; restore power state, volume, and
  local processes (`tools/dev_cleanup.sh`).

## Judging the result (section 9)

- Retries are for readiness (wake, foreground, one relaunch), never for a
  verdict. An intermittent runner is a runner defect.
- Suspect the instrument first; run the control that should flip the
  verdict. Check the taxonomy: probe visible to the system, assertion
  picks its own sample, no margin, bitrate as floor, state read too early,
  totals over unequal windows, stdout lost on kill, PASS over zero
  results.
- PASS, FAIL, SKIP are three numbers.
- A test is not a test until seen to fail against the buggy code. Plant
  controls (`TV_PLANT=1`, `--expect-captions no`).
- Grade the wire and the glass separately for networked features.
- Calibrate thresholds on a real capture; never copy one.
- Read the version back off the device after install (section 10).

## When stuck

- Surface cannot be automated: harness app hosting the real views, or an
  in-app self-audit (section 11).
- Same symptom after three fixes: stop, build the control experiment.
- Long campaign: keep an audit ledger (section 13).

See also: `device-observation-harness` (which tool per platform),
`concurrent-agent-device-leases` (sharing the bench).
