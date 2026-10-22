# Real-device harness port (2026-09-30)

This is the source material for docs/path/04 and the device-testing docs.

## Scope

This port brought Archive Watch's real-device testing tooling into the Universal App Template.

- Nothing was committed.
- These areas were not touched: `.md` files, CLAUDE.md, skills, `docs/`, `android/`, `.github/workflows`, `asc_*`, `submit-*`, `audit_workflow_health` and `check_workflow_gates`.
- No real device was contacted.
- Three forks did parts of the work: the Roku slice, the web-TV slice and the Android slice. Their files were checked afterwards. They compile and their tests pass.
- Every harness file was grepped for AW names, IPs, UDIDs, the old password, `/tmp/awocr`, `/tmp/tbocr` and `AW_`. None were found.

## Files added

All paths are under `/Users/bhwilkoff/Documents/GitHub/UniversalAppTemplate/`.

### Bench, leases and shared plumbing

- **`tools/bench.py`** loads the bench manifest.
  - It looks in three places, in order: `$DEVICE_BENCH`, then `tools/bench.json` (gitignored), then `~/.device-bench.json` (shared by the whole machine).
  - Each entry is keyed by lease name. It holds platform, udid, serial, address, pyatv_id, os, model, role, apple_id (a label, not an address), capabilities, quirks and verified date.
  - There are five roles: test, floor, os-control, owner-watches and owner-personal-never-touch.
  - `require()` always refuses never-touch devices, including by raw UDID, serial or address. It refuses owner-watches devices unless `--owner-ok` or `BENCH_OWNER_OK=1` is given. It also refuses a device of the wrong platform.
  - If there is no manifest, it builds entries from `app_config.DEVICES`. `atv` and `appletv` are aliases.
  - CLI: list, `check`, `get <name> <field>` and `role <name>`.
- **`tools/bench.example.json`** is a sample 15-device bench covering every role, with capture quirks. One example is the Apple TV HD's 720p top-left crop.
- **`tools/apple_device.py`** holds the shared devicectl and pyatv plumbing.
  - Process handling:
    - `exe_pattern` / `app_pids` match the exact executable, allowing padding and excluding PlugIns.
    - `terminate_verified` terminates by `--pid`, then asks the device whether the process is gone.
    - `teardown()` restores the power state the run found and reads it back.
  - Launch and capture:
    - `launch` sends the environment as JSON.
    - `capture` goes through `capture_fresh`.
    - `pull_file` copies out the diagnostics file.
  - The `ATV` class handles the Apple TV remote:
    - `power_state`
    - a polled `wake`
    - a warmed `press`, refused when the TV is off
    - `launch_app=` to bring an app to the front
    - `turn_off_verified`
  - `launch_guarded()` runs this sequence:
    - wake the TV
    - probe that the app is in front, and bring it forward or relaunch once if not
    - death probes at 0, 15 and 30 seconds
    - on a second death, reboot, but only for devices with role test, floor or os-control
  - `frame_is_home_screen()` returns True, False or None. It never returns a confident False when it could not see.
  - CLI: teardown, power, wake, off and processes.
- **`tools/mac_window_shot.swift`** builds the winshot tool into `build/bin/winshot`.
  - It captures one window, where the owning application matches exactly. The owner is given as an app name or `pid:N`.
  - Options: `--min-width`, `--skip-size WxH` and `--id-only`.
  - It deletes the target first.
  - When it fails, it says which half failed: no such app, or no matching window.
  - It has no region or full-screen fallback.

### Apple TV and iOS tools

- **`tools/atv_shot.sh`** takes a screenshot that cannot return stale evidence.
  - It refuses never-touch devices.
  - If an Apple TV reports Off, it exits 3 without capturing.
  - It deletes the target, captures with `--destination`, and refuses a missing file or one older than 60 seconds.
- **`tools/atv_teardown.sh`** leaves nothing running.
  - It terminates by `--pid` after an exact-executable grep that allows padding and excludes PlugIns.
  - It then confirms a zero count from the device.
  - It powers the TV off and reads the state back.
  - It accepts a UDID or `--device <bench>`.
- **`tools/ios_scenario.py`** runs door-driven layout sweeps.
  - `doors` lists the door catalog, including the mute, door-seconds, type-size and force-offline doors.
  - `shot`, `link` and `item` capture one surface; `sweep [--type-size]` captures them all.
  - `pip` tests picture-in-picture without a tap: autoplay muted, open Preferences, relaunch, then diff two frames.
  - `judge` checks clipping. A cut at the left edge is a defect; a cut at the right edge is a scroll peek.
  - `measure` checks that prose lines are no more than 80 characters.
  - It holds a lease and tears down at the end.
- **`tools/test_home_screen_probe.py`** has 7 cases, including every way the OCR can be blind. Each blind case must return None. The test was confirmed to fail against the old `atv_run` probe from HEAD, where "OCR printed nothing" returned False.

### Local machine hygiene

- **`tools/dev_cleanup.sh`** reports stray processes: http.server, the Gradle and Kotlin daemons, the repo's ffmpeg, glass-tool Chrome or node, hung atvremote and console streams.
  - `--stop` ends them.
  - `volume-guard -- <cmd>` saves the volume and mute state, runs the command, restores both through an EXIT/INT/TERM trap, and reads them back.

### Android (fork)

- **`tools/gtv_scenario.py`** drives Google TV and Fire TV.
  - It connects using the cached serial, then port 5555, then the mDNS TLS port.
  - It reads the UI with uiautomator. Each dump deletes the old file first and retries once. It reads both text and content-desc.
  - Navigation is closed-loop, through `go`, `goto_tab` and `type_text`.
  - It activates with `KEYCODE_ENTER`.
  - The rail, pushed routes and safe band are FILL IN placeholders.
  - It holds a lease, and captures go through `capture_fresh`.
- **`tools/test_gtv_scenario.py`** is an offline parser test. Result: 12/12.

### Roku (fork)

- **`tools/roku_run.py`** is a port of AW's `roku.py`.
  - Verbs: info, deploy (with `--extra SRC:DEST`), zip, keys, type, shot, log, launch and playstate.
  - The password comes only from `ROKU_DEV_PASS`. There is no default.
  - The installer uses digest auth, and its verdict is read from the typed JSON messages.
  - It checks that ECP is Permissive and refuses key names outside Roku's closed set.
  - It presses Home before `/launch`.
- **`tools/roku_playback_audit.py`** uses ECP `/query/media-player` as the playback oracle: the position has to advance.
  - Content IDs come from `--ids` or `--ids-file`.
  - Console markers are FILL IN. A check whose marker is unset, or whose console can't be read, reports SKIP.
  - PASS, FAIL and SKIP are counted separately.
  - It holds a lease and presses Home at the end.
- **`tools/roku_sweep.py`** is the Select sweep. `--deeper` goes a second level down.
  - The console reader reconnects on EOF.
  - An empty `SURFACES` list fails.
- **`tools/roku_design_lint.py`** is the lint the Roku skill refers to.
  - It has eight rules and ignores comments.
  - `ALLOW` starts empty, and its format is documented.
  - A missing root fails unless `--allow-missing` is given.
- **`tools/test_roku_run.py`** runs offline tests, including one planted violation for every lint rule. Result: ALL PASS.

### Web TV (fork)

- **`tools/_tv_cdp.mjs`** is the shared CDP harness.
  - It refuses to run if the DevTools port is already in use.
  - It uses a fresh profile each run, under `build/qa`.
  - It renders at a true 1920x1080 at device scale factor 1.
  - It presses keys with real `Input.dispatchKeyEvent` events.
  - It kills Chrome on every exit path.
- **`tools/tv_glass.mjs`, `tools/tv_reachability.mjs`, `tools/tv_follow_focus.mjs` and `tools/tv_audit_sizes.mjs`** were ported onto `_tv_cdp.mjs`.
  - They are configured with `TV_*` environment variables.
  - The default URL is `http://127.0.0.1:8080/?tv=1`.
  - They print a NOTE when the URL is not local.

## Files changed

### Shared config and helpers

- **`tools/app_config.py`**
  - New identity fields: `APPLE_EXECUTABLE` and `ROKU_CHANNEL_NAME`.
  - Durable tool paths:
    - `OCR_BIN` and `WINSHOT_BIN`, both in `build/bin`
    - `QA_ROOT`
    - `PYATV`, in `~/.pyatv-venv`, pinned to Python 3.12
    - `ADB`
    - `DEVELOPER_DIR`, where empty means inherit
  - New hooks: `HOOK_AUTOPLAY`, `HOOK_QA_LABEL`, `HOOK_TYPE_SIZE` and `HOOK_FORCE_OFFLINE`.
  - Door defaults: `DOOR_DEFAULTS` (`APP_MUTE=1`, `APP_DOOR_SECONDS=180`) and `ANDROID_DOOR_EXTRAS`.
  - The diagnostics-file protocol: `HOOK_DIAG_FILE`, `DIAG_CONTAINER_PATH` and `DIAG_TAGS`.
  - `TVOS_HOME_RX`.
- **`tools/devharness.py`**
  - Garbled comments are fixed.
  - There is one OCR path, from app_config. `ensure_tool`, `ensure_ocr` and `ensure_winshot` build the tools into `build/bin` on first use.
  - `capture_fresh()` refuses a missing file, an empty file, or one older than 60 seconds.
  - `qa_dir` is anchored at the repo, not the current directory.
  - New `edge_clips()` uses `w`. A left-edge cut is a defect; a right-edge cut or an ellipsis is a peek.
  - New `measure()`.
- **`tools/devlease.py`**
  - `hold()` leases several devices, all or nothing, renews them in the background, and always releases them.
  - A parent can hand its lease down through `DEVICE_LEASE_HOLDER_PID` and `child_env()`.
  - The owner defaults to the repo directory name.
  - The docstring now carries the device-key contract table and the rule to hold one lease for the whole run.
- **`tools/ScreenOCR/main.swift`**
  - It now emits `w` (box width) and `centerLuma {mean, stddev}`. Before this, `atv_run`'s `min_center_stddev` assertion read a field the OCR never emitted.
  - An OCR failure is reported on stderr, so it no longer looks like an empty frame.

### Apple TV and iOS runners

- **`tools/atv_run.py`**
  - The device comes from the bench: `--device`, default "atv".
  - One lease covers the whole run. If the lease is held elsewhere, the run is SKIP with exit 2.
  - Power is checked before every launch, press and capture.
  - Captures go through the fresh-file guard. A frame that is nearly all black gets a second opinion as a possible doze.
  - Launches go through `launch_guarded`, and the home-screen probe returns one of three values.
  - Teardown runs in `finally`.
  - New flags: `--owner-ok`, `--audible` and `--leave-running`.
  - The report now includes found_power, launch_events, capture_log and teardown.
  - The duplicated `ocr()` is removed.
- **`tools/atv_scenario.py`** is rewritten as the generic media-playback runner.
  - It takes `--item`. `--title` needs `resolve_item()` to be filled in.
  - What it does:
    - uses the bench and holds a lease
    - its door time bound outlasts the capture
    - wakes the TV with polling, and warms each press
    - re-wakes on a doze signature
    - probes that the app is in front, with one relaunch
    - runs death probes at 0, 15 and 30 seconds, escalating to a reboot
    - writes durable output and uses `--protocol companion`
    - pulls the diagnostics file before any relaunch
    - tears down at the end
  - It keeps the generic grading from the diagnostics tags:
    - the app stayed alive
    - the playhead advances
    - no stalls
    - captions appear on the glass
    - the glass matches the caption file or the engine
    - the caption schedule is monotonic
    - blanks are genuine gaps
    - caption pacing
    - `--expect-captions no`, the negative control
  - `audio_continuous` (with corroborated gaps) is graded only with `--audible`.
- **`tools/ios_run.py`**
  - Hardcoded UDIDs are gone; the device comes from the bench.
  - It holds a lease and launches with muted doors.
  - Launches are guarded. A locked device is named as such (FBS error 7).
  - Captures are fresh.
  - Teardown is verified and graded as `left_as_found`.
- **`tools/atv_see.sh`** checks four things, in this order:
  - power, via `atv_shot`
  - freshness
  - OCR line count, which replaces the old byte-size gate
  - wrong screen
  - Other changes:
    - There is one OCR path, built on demand.
    - The expected screen comes from `APP_ANCHOR_RX`.
    - The wording is generic.
    - Pattern matching uses Python regex, because ERE has no `\d`.
    - Exit codes: 1 means blind, 2 means wrong screen, 3 means the instrument is missing.

### Android (fork)

- **`tools/adb_run.py`**
  - The device comes from the bench, a lease is held, and door extras are sent. `--audible` is available.
  - Before the run it checks mWakefulness, the keyguard, stay-on and the screen timeout.
  - It warns if `adb_allowed_connection_time` is not 0.
  - Captures go through `capture_fresh`.
  - At the end it force-stops the app and verifies with `pidof`.

### Mac

- **`tools/mac_window_id.py`** prints only a window ID, from Quartz or winshot `--id-only`, with an exact owner match. The AppleScript `-R` bounds fallback is removed.
- **`tools/macapp.py`** captures by window ID, by pid, through winshot. It skips windows the size of the projector. There is no `-R` and no need to raise the window.
- **`tools/mac_run.py`**
  - App, binary and process names come from app_config.
  - It launches with muted doors.
  - It holds the "mac" lease.
  - It quits the app in `finally`.
- **`tools/mac-shotset.sh`**
  - Removed an `-R` region capture that fell back to the full screen. It now uses winshot with an exact owner match.
  - The AW catalog SQL and the `AW_CS_TEST` shots are gone. The shot list is FILL IN.
- **`tools/mac-screenshots.sh`** uses winshot with an exact owner match. The name-contains lookup and the interactive `-W` fallback are gone.

### Suite and other runners

- **`tools/qa_suite.py`**
  - It walks the bench. Each skipped device gets a SKIP line with its reason:
    - never-touch
    - owner-watches without `--owner-ok`
    - unreachable
    - Roku, with a pointer to the Roku tools
  - It holds one lease per device for that device's whole block of runs and hands it down to the runners.
  - There is a new windows row.
  - The summary shows pass, fail and skip.
- **`tools/devreset.py`**
  - It now uses the bench.
  - It fixed the same bundle-ID grep bug, which gave a false "not running". It now uses the verified terminate.
  - Android stops are verified with `pidof`.
  - Never-touch devices are refused.
- **`tools/web_run.py`**: `BASE` is now `WEB_URL` rather than a live trivia site. The target file is deleted before each shot.
- **`tools/win_run.py`**: door defaults are added and garbled comments are fixed.
- **`tools/hook_coverage.py`**: new rows for mute and door-seconds. The broken `windows/the app.App` paths are fixed and now come from app_config.
- **`tools/measure_start_times.sh`**: the AW UDID default is gone. The device comes from the bench.

### Web TV (fork)

- **`tools/test_tv_focus.mjs`**
  - It resolves paths from the repo root, so it also works when run from `tools/`.
  - Shim fixes: `:not()`, `getElementById`, `focusin` and `hashchange`.
  - New tests:
    - `tabindex="-1"`, checked both ways
    - a focused select owns Up/Down
    - every dvh/cq value has a fallback
- **`tools/test_packaged_origin.mjs`**
  - It uses the template layout.
  - If there is no PAGES_ROOT block, it reports an explicit SKIP; before, it failed.
  - A stale stage is reported as SKIP.
  - Every `js/` script that `index.html` loads must be in the package.
  - The service-worker, Cast and beacon checks run only when those features exist.
- **`tv.js`** has two minimal engine fixes:
  - `:not([tabindex="-1"])` on every row of FOCUSABLE
  - a focused select gets Up/Down
- **`css/styles.css`**: `height: 100vh` is set before `100dvh` on `body`.

### Other

- **`.gitignore`** now includes `tools/bench.json`.
- Garbled comments are fixed in `macapp` and `win_run`.

## Verification

- **Compile and syntax checks all pass:**
  - `py_compile` on every `tools/*.py`
  - `node --check` on every `tools/*.mjs` and on `tv.js`
  - `bash -n` or `zsh -n` on every `tools/*.sh`
  - `swiftc -parse` on both Swift files, which also build to `build/bin`
- **screenocr** emits `w` and `centerLuma` on a generated image.
- **`--help` works offline** for atv_run, atv_scenario, ios_run, ios_scenario, adb_run, gtv_scenario, the four Roku tools, qa_suite, mac_run, web_run, apple_device and bench.
- **Unit tests:**

| Test | Result |
|---|---|
| test_home_screen_probe | ALL PASS |
| test_roku_run | ALL PASS |
| test_gtv_scenario | 12/12 |
| test_tv_focus | 18 pass, 0 fail, from both the repo root and `tools/` |
| test_packaged_origin | 1 pass, 0 fail, 5 skip |

- **`bench.py check`** is OK on the example file and on the DEVICES fallback.
- **Role refusals were exercised:**
  - ios_run, by name and by raw UDID
  - atv_run, for owner-watches
  - atv_scenario, for the wrong platform
  - atv_shot
  - atv_teardown
- **qa_suite against the example bench** prints SKIP lines that name the role.
- **Lease hand-down works:** the child inherits the lease, a stranger is refused with the holder's name, and the lease is released at the end.
- **The `capture_fresh` guard** refuses both "no file" and a stale file.
- **The padded-grep pid match** was checked in both Python and shell against sample devicectl output that includes a PlugIns line.
- **`dev_cleanup.sh volume-guard`** restored the volume and read it back.
- **Web-TV glass tools** were run against a local http.server with headless Chrome:
  - Reachability with the planted control: 5 focusable, 1 unreachable, and the plant is named. Without the plant: 4 focusable, 0 unreachable.
  - Against the old `tv.js` from HEAD, the four new engine cases fail, as they should.
  - The server and Chrome were killed afterwards.
- **Left running:** three Android Studio JBR Gradle/Kotlin daemons that this work did not start.

## Skipped, and why

- **Parts of AW's `atv_scenario` tied to AW's catalog or app:**
  - `resolve_card`, which depends on AW's catalog-index shape. It is now a FILL IN `resolve_item`.
  - The sqlite subtitle-claim lookup.
  - Truth transcripts in `/tmp/*-out`, and grading caption timing against them.
  - Judge-shift ("subtitles ran Xs late; corrected") and judge-discard ("captioning instead") handling.
  - The rule that the "Preparing automatic captions" notice never shows.
  - The `AW_CAPTION_CHOICE` door.
- **The hardcoded surfaces and URL scheme in AW's `ios_scenario`.** They are now FILL IN `SURFACES` and `SCHEME`.
- **Roku:**
  - `roku_audit.py`, `roku_package.py`, `roku_store_poster.py` and `test_roku_legacy_syntax.py` were not ported.
  - `roku_deep_sweep.py` was folded into `roku_sweep.py --deeper`.
  - The catalog-based sample picking, AW's console marker names, and the "resolved url=true" check.
- **AW `test_tv_focus` checks tied to AW's own UI and engine features:** hero CTA, season chips, store-promo hiding, TV transport readout, diagnostics overlay, arrival focus, per-route Back restore and EPG ordering. The template has none of these. Arrival and Back restore would need an engine port first.
- **`harness_awdiag.swift`, `test_ios_floor.py` and `test_studio_devices.swift`**, which are app-specific or floor-specific. The other agent's area has a `test_ios_floor.py` in progress.
- **The Tidbits scenario vocabulary** in the SCENARIOS tables of atv, ios, adb, mac, win and web was left as it was. It is app content.
- **`capture-screenshots.sh`** is still Tidbits-specific. Its Mac path now gets a window ID only, with no RECT fallback.
- **`web_run` takes no lease.** Its browser uses a private headless profile, so nothing is shared with other runs.

## Found outside this slice

- **The template's `tv.js` puts boot focus on the off-screen "Skip to content" link.** tv_glass and follow_focus flag this. Adding the link to `CHROME_SEL` would likely fix it.
- **The "Sign in" button is 13px on TV.** It needs a `tv.css` rule.
- **hook_coverage now shows NO for mute and door-seconds on every client.** That is accurate: the clients need to implement those doors.
- **`roku_design_lint` exits 1 until a `roku/` folder exists.** A CI gate should pass `--allow-missing`.
- **`js/api.js` is modified in the working tree.** That change is not from this work.

## Lessons embodied in the code

### The bench and leases

1. **The bench is a manifest, not a dict.** Each device has a lease key, IDs, OS, role, account label, capabilities and quirks, and the manifest lives in one file for the whole machine.
2. **Roles gate every runner.**
   - Never-touch has no override.
   - Owner-watches needs an explicit OK. Ask before waking a TV in someone's room.
   - A raw UDID still has its role checked.
3. **Hold one lease for the whole run, in one process.**
   - A suite holds the lease and hands it down through `DEVICE_LEASE_HOLDER_PID`.
   - The lease renews in the background.
   - Devices are taken all or nothing.
   - If the lease is held elsewhere, the run is SKIP, and a SKIP covers nothing.

### Leaving the room as you found it

4. **Teardown is a step with an assertion.**
   - `devicectl` terminate needs `--pid`. Given the wrong flag, it prints usage, which looks like success.
   - `info processes` prints executable paths, not bundle IDs, padded with trailing spaces. A bundle-ID grep and a `$`-anchored grep both gave a false all-clear. The template's own devreset had this bug.
   - Exclude PlugIns, which the system launches.
   - Verify from the device.
   - Restore the power state you found, and read it back.
5. **Doors are muted and time-bounded by default.**
   - An audible run is opt-in; ask the owner first.
   - Muting the player can also silence the audio tap, so audio is graded only on audible runs.
   - A playback door's time bound must outlast the capture.
6. **Clean up local processes.** Stray processes include http.server, the Gradle and Kotlin daemons, ffmpeg, glass-tool Chrome or node, hung atvremote and console streams. Audible suites restore the system volume through an EXIT/INT/TERM trap and read it back.

### Capturing evidence

7. **A capture must never return stale evidence.** Delete the target, capture, then refuse a missing file, an empty file, or an mtime older than 60 seconds. This applies to devicectl, adb, winshot and headless Chrome.
8. **A sleeping Apple TV returns a valid black PNG.** Ask for `power_state` before every launch, press and capture; never infer power from pixels. If the launch works but captures are black, the television itself is off or on another input.
9. **Use OCR line count as the readability gate, not byte size.** Bytes depend on resolution and content.
10. **An instrument that cannot see has to say so.** An OCR failure is `OCR_FAILED` or `None`, never "screen off" and never "not home". The home-screen probe returned False for weeks because a TypeError was swallowed.
11. **A readable frame of the wrong app is worse than a blank one.** Check for the app's own words and for the tvOS home-screen signature.
12. **Mac captures use a window ID only, with the owner matched exactly.**
    - Region and full-screen captures leaked other windows that were open, including personal documents.
    - A title-substring match once picked up a terminal tab.
    - There is no fallback, not even an interactive one.
13. **All runners share one durable OCR binary**, `build/bin/screenocr`, built on first use. `/tmp` is wiped on reboot, and two runners once looked for two different `/tmp` names.
14. **pyatv lives in `~/.pyatv-venv` on Python 3.12.** Python 3.14 breaks atvremote.
15. **An assertion that reads a field the instrument never emits can never pass, however correct the screen.** `centerLuma` had to be added to ScreenOCR, and `w` makes clipping checks possible.

### Driving Apple devices

16. **Wake by polling.** `turn_on` only sends a request, and a launch during the doze window comes up backgrounded: alive, but not in front.
17. **Alive is not frontmost.**
    - Probe one frame.
    - If it shows the tvOS home screen, `launch_app=` brings the app forward and keeps its environment.
    - Only if that fails, relaunch once.
18. **About 2 in 10 launches die silently in the first seconds.** This happens around the screenshot daemon's jetsam, meaning iOS killed a process to free memory.
    - Probe at 0, 15 and 30 seconds and retry once.
    - On a second death, reboot, but only on devices with role test, floor or os-control.
19. **pyatv presses must be warmed.**
    - Run `power_state` on the same connection first.
    - Never press while the TV is asleep.
    - Presses do not reset the TV's sleep timer.
20. **Never use `--console` alongside captures.**
    - Two devicectl sessions kill the stream, and killing the console kills the app.
    - Use a diagnostics file instead, and pull it before any relaunch, because launching truncates it.
21. **A locked iPhone installs fine but refuses to launch (FBS error 7).** Name the lock once rather than letting it produce many empty results. Launch environment must be JSON.

### Grading

22. **Grading rules:**
    - A left-edge cut is a defect. A right-edge cut or an ellipsis is a peek.
    - Big type is excluded by height.
    - Prose lines are limited to 80 characters.
    - A regression test is only proven once it has been seen to fail against the buggy code.

### Android

23. **Android rules:**
    - Reconnect before every adb call, because the TLS port rotates.
    - Delete before every dump or capture, and retry an empty tree once.
    - Navigate by reading the focus bounds after every press.
    - Activate with `KEYCODE_ENTER`, not `DPAD_CENTER`.
    - Read `content-desc` too, because merged Compose nodes put their label there.
    - Pressing BACK at a tab root exits the app.
    - On Fire OS, launch with `am start -n`.
    - `screencap` does not capture the video plane.
    - The owner unlocks once. Check stay-on and the screen timeout before calling a device locked.
    - `adb_allowed_connection_time` must be 0, or trust silently expires after 7 days.

### Roku

24. **Roku rules:**
    - ECP must be Permissive. In limited mode, keypresses get 403 while device-info still answers.
    - Key names are a closed set. Roku returns 200 for an unknown name and does nothing.
    - The installer uses digest auth.
    - Read the installer's verdict only from its typed JSON messages. An empty or unparseable reply means UNVERIFIED.
    - If the installer refuses an "identical" package, delete the channel and install fresh.
    - Screenshots only capture a sideloaded dev channel.
    - The 8085 console only pushes. It replays its backlog when you connect and drops on relaunch, so reconnect and mark where new output starts.
    - Press Home before `/launch`. Use `/input` for deep links.
    - `/query/media-player` with an advancing position is the playback oracle. Its values carry units ("ms"), and its error attribute is sticky.
    - A deep link proves a screen renders; a Select sweep proves it is connected.

### Web TV

25. **Web-TV glass rules:**
    - A laptop cannot open a true 1920x1080 viewport. Headless Chrome at scale 1 can.
    - Press real keys; never call `focus()` or `click()`.
    - A browser already on the DevTools port answers with its old page.
    - Use a fresh profile every run, and warn when measuring a live site.
    - Reachability walks the real focus graph, with nodes keyed by content.
      - If nodes disappear during the walk, the result is NOT MEASURABLE.
      - An unfinished walk proves reachability, never unreachability.
      - An empty pool means the probe is broken.
      - Every run needs a planted control.
    - Check overscan on all four sides and print the band. Measure text, not containers.
    - Size floors apply to the node that draws the text. Every exemption needs a reason.
    - Every dvh or cq value needs a fallback.
    - A focused select owns Up/Down. Honour `tabindex="-1"` on every row.
    - A packaged app must contain everything it loads.
    - A `file://` origin needs a canonical data root and gates for anything that assumes http(s).

### Reporting

26. **PASS, FAIL and SKIP are three separate numbers.** A reader that cannot read reports SKIP with a reason. It is never silent and never reports a confident zero.
