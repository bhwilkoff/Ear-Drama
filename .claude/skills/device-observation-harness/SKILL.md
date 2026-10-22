---
name: device-observation-harness
description: "Use when a fix cannot be verified from the app's own logs or a simulator: Apple TV behavior, iPhone/iPad on real hardware, the Mac app's window, D-pad focus on Google TV / Fire TV, Roku channels, web TV on webOS/Tizen, Windows, playback and caption sync, or any bug reported as still broken after fixes that looked verified. Picks the right tool per platform and names the trap to check first (sleeping Apple TV returns black PNGs, CoreDeviceError 4016, locked iPhone FBS error 7, adb_allowed_connection_time 0, KEYCODE_ENTER not DPAD_CENTER, Roku ECP Permissive, headless Chrome for true 1080p, SSH session 0). Triggers on devicectl, pyatv, paired device, OCR, screenshot verification, adb keyevent, ECP, focus unreachable, throttled network, scenario runner."
---

# Device observation harness

Catalog with exact commands: `docs/DEVICE-HARNESSES.md`. Method and
verdict rules: `docs/AUTONOMOUS-FLEET-TESTING.md`.

## The rule

A change to behavior you cannot directly observe ships only on evidence
from an instrument that does not share the app's assumptions: screen OCR,
a device query, a server recording, a re-downloaded artifact. The
instrument says when it is blind and never perturbs what it measures.

## Pick the tool, check the trap first

| Platform | Tool | Check first |
|---|---|---|
| Apple TV | `atv_run.py`, `atv_scenario.py` (media), `atv_see.sh`, `atv_shot.sh`, `atv_teardown.sh`, `apple_device.py` | power state before every capture; wake is polled; no `--console` with captures; pull the diag file before relaunch; 4016 on every TV = restart the Mac |
| iPhone, iPad | `ios_run.py`, `ios_scenario.py`, XCUITest for taps | passcode off, Auto-Lock never; FBS error 7 = locked; launch env is JSON |
| Mac | `mac_run.py`, `build/bin/winshot` | window id with exact owner match only; offline proof via `sandbox-exec`, never Wi-Fi off |
| Android phone | `adb_run.py`, `testlab-android.sh` | debug build; `adb_allowed_connection_time 0`; stay-on before calling it locked |
| Google TV, Fire TV | `gtv_scenario.py`, `verify_tv_focus.sh` | navigate by focus tree; `KEYCODE_ENTER`; Back at a tab root exits; `screencap` has no video plane; Fire OS `am start -n` |
| Roku | `roku_run.py`, `roku_playback_audit.py`, `roku_sweep.py` | ECP Permissive; closed key set; screenshots only of a dev channel; Home before `/launch`; `/query/media-player` is the playback oracle |
| Web TV | `tv_glass.mjs`, `tv_reachability.mjs` (+ `TV_PLANT=1`), `tv_follow_focus.mjs`, `tv_audit_sizes.mjs`, `test_tv_focus.mjs`, `test_packaged_origin.mjs` | headless at true 1920x1080; real key events; local URL, not production |
| Web | `web_run.py`, `webdrive.py` | 375px and 1440px; hidden tab defers media |
| Windows | `win_run.py`, `winbox.py`, `windows-latest` CI | SSH is session 0; RGBA vs BGRA in pixel diffs |
| Playback | `throttled_range_server.py` | Release build + ~10 Mbps; stock `http.server` ignores Range |

## Habits

- Every capture fresh (`capture_fresh()`), durable (`build/qa/`), and
  checked for your app's words, not just readability.
- Reach screens by door or deep link; navigate closed-loop when presses
  are the thing under test.
- Hold one lease for the whole run (`concurrent-agent-device-leases`).
- Identify the build on the device (`devicectl device info apps`) before
  diagnosing.
- Nondeterministic fault: repeated, paired trials per arm. Survives three
  fixes: build the control experiment.
