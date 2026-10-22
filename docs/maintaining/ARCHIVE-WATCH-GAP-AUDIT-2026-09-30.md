# Archive Watch gap audit (2026-09-30)

This file is the work queue for the restructure loop. Each tick takes items from it, and PROVENANCE is updated as they land.

This audit was read-only: nothing was edited in either repo. AW = /Users/bhwilkoff/Documents/GitHub/Archive-Watch. T = /Users/bhwilkoff/Documents/GitHub/UniversalAppTemplate.

**Method.**
- I diffed skills and tools myself.
- Five parallel research agents covered: decisions 096–126, decisions 127–158, real-device testing, docs (floor/ceiling, parity, contract), and tools/workflows/memory.
- I re-checked the load-bearing claims in T directly: `asc_submit.py` is iOS-only, the auditor still returns 1, the gate checker lacks the reporter check, the Dynamic Type text is stale, `atv_scenario` uses /tmp, the Android `versionName` is a literal, the "owner hits Submit" text is still there, and the 120 KB ceiling is unchanged. All confirmed.
- AW has had about 2,180 commits since 09-01. About 1,280 are non-catalog, with ~220 on Watch Together alone.

---

## 0. Scope facts

**Decisions.**
- T's PROVENANCE says the last full AW audit covered **decisions through 095** (2026-08-24).
- The 09-01..09 ports cited no decision numbers. By content they covered 097, 098, 108, 109, 110, 111, and parts of 101.
- **Not audited: AW decisions 096–158** (63 entries).
  - 096–115: `docs/decisions/DECISIONS-081-115.md`
  - 116–122: `DECISIONS-116-122.md`
  - 123–126: `DECISIONS-123-126.md`
  - 127–158: `DECISIONS.md`, in full
- Status tally: 096–126 is 9 covered, 11 partial, 9 missing, 2 app-specific. 127–158: nothing ported.

**AW's own skills are not newer than T's.** The six in `.claude/skills` differ only by T's genericization (placeholders and "REFERENCE IMPLEMENTATION" headers). `macos-creation-studio-engine` is a deliberate exclusion.

**Global `~/.claude/skills` is ahead of T in two places:**
- `store-submission-playbook` (global, 09-08) has a section T lacks: "Driving a store console in a browser (Roku)".
  - Upload through `<input type=file>` by ref, never by clicking it.
  - A button can return 200 and show nothing, so read the network log.
  - The gating email can differ from the developer email.
  - Required fields can sit below the fold.
  - Repo checklists drift into fiction.
  - Pick the demo title on rights clarity, then playability, then recognisability.
  - No test residue in screenshots: delete and reinstall.
  - Record the reason for any deliberately surviving certification warning in the manifest.
- `social-video-teaser-craft` exists only globally and is not vendored in T.
- Every other global/T difference is T being newer.

**The harness T ships came from Tidbits-Trivia, not AW.** AW has its own separate harness family. Tidbits has since moved on too: mac_run.py has 16 commits since 09-01, macapp.py 6, plus winbox/win_run/devharness. A Tidbits re-sync is out of scope here but is real drift.

---

## 1. Defects and contradictions inside T (fix first)

1. **Platform floors contradict AW 141/148/154/155.**
   - T `CLAUDE.md` says iOS/tvOS 26 is the floor, "no @available guards, don't write iOS 17/18 workarounds", and `minSdk = 29`. T Decision 004 says the same.
   - AW now uses:
     - iOS 18, with iOS 26 features behind `#available`, because 26 dropped the XS/XR.
     - tvOS held at 26, below 27, because 27 drops the Apple TV HD and 4K 1st gen.
     - Android minSdk 23 on every store, with ISRG roots bundled and lint NewApi clean per flavor.
     - Fire TV must be ≤28 (Fire OS 7). minSdk 29 hid the app from most sticks: 38 of 98 devices.
   - AW guards the floors with `tools/test_ios_floor.py` and `test_tvos_floor.py` inside `appstore-build.yml`.
   - The generic rule: choose a floor by the hardware it buys, measured by test-building at each candidate floor, not by adoption share. Hold it with a CI test. "The floor is not a ceiling": gate by capability.
   - `TV-DESIGN-template` §6.4 ("ours is 29") and `docs/TV-PLATFORMS.md` carry the same error.
2. **`tools/asc_submit.py` hardcodes `filter[platform]=IOS`** (lines 91, 136, 281). That is the trap AW 101 paid for: three platforms need three versions and three reviewSubmissions. AW's `tools/asc_release.py` is the fix and T lacks it.
3. **T contradicts itself on Apple submission.** `apple-app-store-cli-submission` SKILL.md lines 25 and 42, and the tail of `submit-appstore.sh`, still say "the OWNER … hits Submit". CLAUDE.md says never ask the owner to. AW's `appstore-build.yml` waits for the build to become VALID and then submits, with `submit: true` by default.
4. **`tools/audit_workflow_health.py` still has the bug AW fixed.**
   - It still does `return 1 if urgent` and still skips `NOT_PRODUCERS` entirely. That skip let AW's "Publish catalog DB" fail hourly for two days unreported.
   - AW replaced it with:
     - `NO_YIELD_LINE`: skip only the yield check; failures still count.
     - `SELF`.
     - `self_cancelling()`, which reads `cancel-in-progress`.
     - Job-granularity displacement detection.
     - "Newest scheduled run that actually ran".
   - Regression test: `tools/test_workflow_health.py`.
   - `docs/CI-FLEET.md` §6 still says the auditor fails on BROKEN/KILLED. AW 107 overturned that: auditors and reporters never fail, a partial success is a warning, and findings go to one self-closing issue.
5. **`tools/check_workflow_gates.py` (34 lines) doesn't do what `product-pulse-dashboard` SKILL.md:123 says it enforces.** AW's 116-line version adds two checks:
   - Reporter workflows may not exit 1 without a `# reporter-may-fail:` marker.
   - Every step that runs `gh` must have `GH_TOKEN` in scope. Publish-db shipped nothing for two days without it.
6. **Android `versionName = "1.0.0"` is a literal** in `android/app/build.gradle.kts`. AW's drifted 88 versions behind before `test_version_contract.py` made it read `AppVersion.xcconfig`.
7. **Stale text.**
   - `docs/TVOS-PLAYBOOK.md` lines 247 and 504, and the CLAUDE.md type table, say Dynamic Type doesn't apply on tvOS. It arrived in tvOS 27 (use `.scaledFont`). T also lacks AW playbook §8.1a on clickpad press priority.
   - DECISIONS roll ceiling is still ~120 KB in `AUTONOMOUS-LOOPS.md:87` and `CLAUDE.md:654`. AW lowered it to ~50 KB.
   - `store-metrics-pipelines` says Roku "exposes nothing". AW 123 found Roku's Looker delivery.
   - `docs/MEDIA-PLAYBACK.md` line 60 points to a generated-captions section "below" that doesn't exist.
   - `web-catalog-data-layer` has web Detail re-deriving from archive.org's metadata API. AW found that path hangs or 404s.
8. **T's harness violates its own doctrine.**
   - `tools/atv_scenario.py` defaults to `/tmp/atvrun`, `/tmp/awocr` and `/tmp/pyatv-venv`. AW moved to `build/qa/...` and `~/.pyatv-venv`, pinned to Python 3.12 because 3.14 breaks atvremote.
   - `atv_run.py`'s `frame_is_home_screen` returns False when OCR fails. That is the exact "guard that always returned False" bug AW documented and then guarded with `test_home_screen_probe.py`.
   - `mac_window_id.py` falls back to an AppleScript `-R` region capture. AW forbids that: region and full-screen captures leaked the owner's personal documents.
   - ios_run, atv_run, adb_run and qa_suite take no leases (only win_run does), contrary to the lease skill.
   - No runner has teardown.
   - `atv_see.sh` has no delete-before-capture, an `/tmp/awocr` vs `/tmp/tbocr` mismatch, "not Archive Watch" error text, and a byte-size "TV off" gate. A sleeping TV actually returns a valid black PNG, so check `power_state` first.
   - Comments in `devharness.py` and `app_config.py` are garbled ("called three correctly-rendered this app's headings").
9. **The session-start hook doubles context.** T's `.claude/hooks/session-start.sh` `cat`s CLAUDE.md, which Claude Code already loads. AW's hook prints only one line of live git and version state. AW cut always-loaded context from about 382 KB to about 80 KB (commit cbea6bf29) by:
   - lowering the DECISIONS ceiling to 50 KB;
   - keeping only two session-log entries in SCRATCHPAD and rolling older ones verbatim into `docs/SESSION-LOG.md`;
   - reading ship state from Pulse instead of typing it into the scratchpad;
   - keeping MEMORY.md to one line per entry.
10. **`android/gradle.properties` has no Kotlin-daemon heap or worker cap** (AW 110). The Kotlin daemon is a separate, unbounded JVM.
11. **Android testing stance conflicts.** `android-production-gotchas` says "emulator-verify". AW's owner rule is real devices only when a bench exists, and emulators can't see Play Billing. Present this as a choice.
12. **Determinism doctrine needs an amendment** (AW 144). Four mirrored ports of a seeded channel schedule agreed on 0 of 14 channels. Rule 0: if a pipeline can compute it, publish the result (UTC, held days, in-place repair), and mirror an algorithm only when it must run on-device. This affects `cross-platform-determinism` and T Decision 025.

---

## 2. Real-device testing (focus 1)

**AW's bench** (`docs/DEVICE-TESTING.md` §1 plus memories; already stale in AW):

| Device | OS | Role |
|---|---|---|
| ATV 4K 3rd gen | tvOS 27.2 | pyatv harness unit |
| ATV 4K 2nd gen | tvOS 27 | Owner watches here; speed floor |
| ATV | tvOS 26.6 | OS control |
| Apple TV HD | tvOS 26.6 | Hardware floor |
| iPad Pro 12.9 5th gen | iPadOS 27 | |
| iPhone 12 | iOS 26.6.1 | Different Apple ID, so it is a real SharePlay peer |
| iPhone 15 Pro | iOS 27 | Owner's personal phone; refused by UDID |
| Mac | macOS 27.2 | |
| Roku Streaming Stick 4K | Roku OS 15.3 | |
| Roku 2 XD | Roku OS 9.1 | Legacy floor |
| Google TV Streamer | Android 14 | |
| Fire TV Stick 4K Max | Fire OS 8 | |
| Pixel 8a | Android 17 | |
| Samsung S90C | Tizen 9 | Deploy and launch only |

There is no iOS 18 device, even though the floor is now 18.

The bench config is scattered: hardcoded UDIDs and IPs per tool, per-tool env vars, lease keys only in a docstring, and roles only in prose. The working tvOS/iPad helper scripts lived in an ephemeral /tmp session scratchpad: nav, fnav, knav, tvguard, flaunch, shot, fshot, kshot, taptext, a11y.

**Gap: T's `app_config.DEVICES` (one device per kind) cannot express a bench.**
- Needed: a bench manifest carrying lease name, UDID/serial, address, pyatv id, OS, role (test / floor / os-control / owner-watches / owner-personal-never-touch), Apple ID, capabilities (screenshot, console, press) and capture quirks.
- Home: new `tools/bench.json` or `app_config` section, plus `docs/DEVICE-HARNESSES.md`.

Format below: AW source → lesson → generic or app-specific → home in T.

### A. Leave-as-found hygiene (entirely missing from T)

- **A1. Teardown is a step with an assertion.**
  - AW source: `tools/atv_teardown.sh`, memory `device_teardown_must_be_verified`, `TVOS-STUDIO-RUNBOOK.md` §8.
  - Lesson:
    - `devicectl process terminate` needs `--pid`; the wrong flag prints usage, which looks like success.
    - Grep the padded `info processes` output for the exact executable, excluding PlugIns.
    - Verify a zero count from the device itself.
    - Power the TV off again and read back that it is off.
    - A film left unmuted played through every HomePod for an hour.
  - Generic.
  - Home: `tools/atv_teardown.sh`, a teardown step in atv_run/ios_run, and an AUTONOMOUS-FLEET-TESTING "Leave as found" section.
- **A2. Dev doors are muted and time-bounded.**
  - AW source: memories `ask_before_audible_test`, `mac_bench_captures_owner`; `TVOS-STUDIO-RUNBOOK` §4.
  - Lesson:
    - Doors default to muted and a `*_SECONDS` bound (180).
    - The player mute also silences tapped audio, which produced a false finding.
    - No owner camera or mic on bench runs.
    - Ask before any audible run.
  - Generic. Home: `device-observation-harness`.
- **A3. Restore the room.**
  - AW source: memories `cast_volume_is_tv_volume`, `atv_tcc_prompt_outlives_app`, `never_sleep_test_devices`.
  - Lesson:
    - Record and restore TV volume around a Cast test, and read it back.
    - A TCC prompt outlives a killed app, so check `authorizationStatus`; never press Allow.
    - Never sleep a device (keyevent 223/26).
  - Generic. Home: same section.
- **A4. Clean up local processes.**
  - AW source: `tools/dev_cleanup.sh`; SESSION-LOG 8.21, where volume was left at 100.
  - Lesson: stray http.server, Gradle/Kotlin, ffmpeg and render-loop processes run for days. Audible suites save and restore system volume with an EXIT/INT/TERM trap.
  - Generic. Home: the tool plus a machine-resource policy section in AUTONOMOUS-LOOPS. T ported only `ffmpeg_limits.py`, with no doc.

### B. Capture and screenshot traps

- **B5. Stale-file guard.**
  - AW source: `tools/atv_shot.sh`.
  - Lesson: delete the target, capture with `--destination`, refuse a missing file, refuse an mtime older than 60 s. A stale PNG was once reasoned about as current, and only the on-screen clock gave it away.
  - Generic. Home: new tool, plus the same rule in devharness and atv_see.
- **B6. Check the TV is awake first.**
  - AW source: memory `check_tv_is_on_first`, commit df272af0c.
  - Lesson:
    - A sleeping ATV returns a valid black PNG.
    - `Mercury.error 1001` means the capture fails while the app is rendering.
    - Check `power_state` before every launch, press or capture (`tvguard`).
    - Ask before waking a TV in someone's room.
  - Generic. Home: `device-observation-harness` and atv_run.
- **B7. Apple TV capture recipes.**
  - AW source: `TVOS-STUDIO-RUNBOOK` §5.
  - Lesson:
    - `--console` and capture are mutually exclusive, and killing the console kills the app, so do two runs.
    - One pyatv press blocks captures for 45–60 s; use a door for multi-press navigation.
    - When capture fails with CoreDeviceError 3 on one box, switch devices.
    - Pull the diag file before relaunching, because launch truncates it.
  - Generic. Home: DEVICE-HARNESSES Apple TV section.
- **B8. Apple TV HD crop.**
  - AW source: memory `atv_hd_720p_capture_crop`.
  - Lesson: the Apple TV HD sometimes captures at 1280×720, which is the top-left crop of 1080p. It looks like a layout blowup. Check the width first.
  - Generic. Home: bench manifest capture quirks.
- **B9. Mac window-only capture.**
  - AW source: `tools/mac_window_shot.swift`, `demo_window_record.swift`, memory `mac_screenshot_window_only`.
  - Lesson: capture by window id, with the owning app matched exactly. Full-screen and `-R` region captures leaked personal documents three times.
  - Generic. Home: replace T's `mac_window_id.py` fallback.
- **B10. Hidden browser tabs.**
  - AW source: memory `chrome_hidden_tab_defers_media`.
  - Lesson: a tool-driven Chrome tab is hidden, so media `readyState` stays 0. Check `visibilityState`.
  - Generic. Home: web-platform-patterns and DEVICE-HARNESSES.

### C. Apple device recipes

- **C11. Pairing and launching.**
  - AW source: DEVICE-TESTING §1, §3; memory `apple_tv_pairing_xcode26`.
  - Lesson:
    - Pair through Xcode 26 Device Hub → Pair Nearby; `devicectl manage pair` cannot start pairing.
    - Discover TVs with `_remotepairing._tcp`.
    - Address by UDID with a long first timeout; by name fails with "multiple devices".
    - Launch env must be JSON.
    - Use `--payload-url` to open URLs.
    - A locked iPhone installs but refuses to launch (FBS error 7), which produces vacuous passes.
  - Generic. Home: DEVICE-HARNESSES, or a new `docs/APPLE-DEVICE-RECIPES.md`.
- **C12. When TVs vanish.**
  - AW source: DEVICE-TESTING (09-24).
  - Lesson:
    - CoreDeviceError 4016 on every TV means the Mac has lost the TVs; restart the Mac rather than re-pairing.
    - After a macOS update, run `-downloadComponent MetalToolchain`.
    - For MIInstaller 13, rebuild once with `-allowProvisioningDeviceRegistration`.
  - Generic. Home: same.
- **C13. iOS scenario catalog.**
  - AW source: `tools/ios_scenario.py`, DEVICE-TESTING §8a.
  - Lesson:
    - Keep a catalog of launch doors, including `AW_MUTE` and `AW_TYPE_SIZE`.
    - Test PiP without a tap: autoplay muted, open Preferences, relaunch, diff frames.
    - When judging clipping, a left-edge cut is always a defect; a right-edge cut is a scroll peek.
    - Measure the longest prose line (≤80 characters).
  - Generic. Home: devharness `clipped_lines` and `measure()`, plus a door table.
- **C14. XCUITest on a real device is the tap tier.**
  - AW source: `IPHONE-12-AUDIT.md` "Harness lessons", `AuditUITests.swift` (872 lines), `IPadInputUITests.swift`.
  - Lesson:
    - `isHittable` lies at the bottom edge.
    - A Toggle is exposed as its whole row; tap at dx 0.92.
    - The iOS 26 search tab replaces the tab bar, so visit it last.
    - Scroll lazy Forms before waiting.
    - Collect labels, then act.
    - Judge by effect, never by existence.
    - A Mac keyboard and trackpad attached to the iPad can drive input.
    - PiP restore cannot be driven.
  - Generic. Home: AUTONOMOUS-FLEET-TESTING, which currently only says "XCUITest drives only your own app".
- **C15. Press the keys yourself.**
  - AW source: memory `press_the_keys_yourself`, AW tvos-playbook §8.1a.
  - Lesson: an input feature isn't done until it has been pressed through pyatv with a log line per press. A door bypasses the real input path; AVKit swallowed presses.
  - Generic. Home: `device-observation-harness` and T's TVOS-PLAYBOOK.
- **C16. Force the foreground.**
  - AW source: scratchpad `flaunch.sh`.
  - Lesson: after a devicectl launch, pyatv `launch_app=` forces the app to the foreground.
  - Generic. Home: atv_run `launch()`.
- **C17. Prove offline safely.**
  - AW source: DEVICE-TESTING §9.
  - Lesson: deny the network to one process with `sandbox-exec (deny network*)` on a re-signed, unsandboxed copy, with a negative control. Never turn off Wi-Fi, because that cuts the agent's own session.
  - Generic. Home: DEVICE-HARNESSES and universal-feature-states.
- **C18. Deep links need history.**
  - AW source: AW Decision 126.
  - Lesson: test deep links on a device with history; a fresh sideload always passes.
  - Generic. Home: autonomous-fleet-testing.

### D. Android, Google TV and Fire TV

- **D19. Navigate by the focus tree.**
  - AW source: `tools/gtv_scenario.py`, `ANDROID-TV-AUDIT.md` §Method, memory `android_tv_overscan_sweep`.
  - Lesson:
    - Read focus bounds after every press; step counts mislabel screens.
    - BACK from a tab root exits the app.
    - `KEYCODE_ENTER`, not `DPAD_CENTER`, activates `tvFocusable`.
    - Merged Compose nodes hide children, so read `content-desc`.
    - Compose overlays are absent from the tree, so use OCR.
    - The SoC doesn't composite video into `screencap`: prove playback by decoder frames, the transport clock and `dumpsys audio`.
    - `scaleWhenFocused` pushes edge rows into the overscan cut.
  - Generic. Home: androidtv-compose-focus and adb_run.
- **D20. Keep devices trusted and awake.**
  - AW source: memories `feedback_real_devices_no_emulators`, `android_one_unlock`; DEVICE-TESTING §7.
  - Lesson:
    - `settings put global adb_allowed_connection_time 0`; otherwise trust is silently revoked after 7 days.
    - Use one adb binary.
    - Check `mWakefulness` and keyguard before any run.
    - The owner unlocks once.
    - No emulators.
  - Generic. Home: android-production-gotchas and DEVICE-HARNESSES.
- **D21. Phone playback.**
  - AW source: `tools/pixel_player_test.py`, scratchpad `taptext.sh`/`a11y.py`.
  - Lesson: tap by label, never by coordinates. Capture the four player states, including PiP. Audit unlabeled clickables.
  - Generic. Home: adb_run and qa_suite.
- **D22. Fire TV negative control.**
  - AW source: ANDROID-TV-AUDIT P2.
  - Lesson: use the Google TV as the negative control for Fire-only faults.
  - Generic pattern. Home: androidtv-compose-focus.

### E. Roku (T has skill prose, no tools)

- **E23. Roku runner.**
  - AW source: `tools/roku.py` (deploy, keys, type, shot, log, launch, info).
  - Lesson:
    - ECP must be set to Permissive; "limited" returns 403 on keypresses while device-info still answers.
    - Screenshots capture only a sideloaded dev channel.
    - The installer uses digest auth.
    - Port 8085 is the log console.
    - `/launch` resumes a running channel, so press Home first.
  - Generic. Home: `tools/roku_run.py`, plus roku-brightscript-app §5, which lacks the Permissive and dev-only-screenshot points.
- **E24. Playback oracle.**
  - AW source: `tools/roku_playback_audit.py`.
  - Lesson: ECP `/query/media-player` with an advancing position is the playback oracle, because a screenshot of video is black. It works as a release gate. T's skill says "console trace" only.
  - Generic. Home: tool plus skill.
- **E25. Select sweeps.**
  - AW source: `tools/roku_sweep.py`, `roku_deep_sweep.py`.
  - Lesson: "Deep links prove a screen renders; a Select sweep proves it is connected." The console reader must reconnect on EOF.
  - Generic. Home: tool plus skill.
- **E26. On-device self-tests.**
  - AW source: `tools/roku_audit.py`.
  - Lesson: `selftest:report`, `:layout` and `:store` self-test doors, which assert floors rather than exact counts and restore the registry.
  - Generic. Home: roku skill §7.
- **E27. Legacy floor device.**
  - AW source: DEVICE-TESTING "Roku 2 XD", `tools/test_roku_legacy_syntax.py`.
  - Lesson:
    - OS 9.1 rejects `continue for`.
    - `GetOSVersion()` itself is too new for 9.1, so probe whether a component exists, never the version.
    - Use `loadWidth`/`loadHeight` for textures.
  - Generic. Home: roku skill plus a "floor device" concept in smart-tv-platform-expansion.
- **E28. Signing and packaging.**
  - AW source: `tools/roku_package.py`, `roku_design_lint.py`, memory `roku_signing_key`.
  - Lesson: never automate `genkey`. Keep credentials where the tool looks (`~/.config/roku/signing.env`).
  - Generic. Home: roku skill and store-submission-playbook.
- **E29. Roku store lessons since 09-11.**
  - AW source: the Roku commits since 09-11.
  - Lesson:
    - "Validated" by the search feed validator does not mean registered.
    - Keep the beta app's package in sync with the store package, or deep-link certification fails.
    - Dashboard upload is automatable via the `input.dzu-input` dropzone.
    - App Behavior Analysis must be started by hand.
    - Ask the device its supported package formats.
  - Generic. Home: roku skill §8.

### F. Web TV and Tizen glass instruments (absent from T)

- **F30. True-1080p driver.**
  - AW source: `tools/tv_glass.mjs`, `TIZEN-GLASS-FINDINGS.md`.
  - Lesson:
    - Desktop Chrome on the Mac cannot open a 1920×1080 viewport; headless Chrome can.
    - Drive with CDP `Input.dispatchKeyEvent`, never `el.focus()`.
    - Shoot every press.
    - Warn when measuring production instead of the working tree.
  - Generic. Home: new tool plus smarttv-web-app.
- **F31. Focus-graph reachability.**
  - AW source: `tools/tv_reachability.mjs`, memory `tv_reachability_control`.
  - Lesson:
    - Build the real focus graph and run BFS from boot focus.
    - The planted control must sit in the selector gap.
    - A capped walk is INCONCLUSIVE, not a defect.
    - Four ways the tool lied, including an empty pool exiting 0.
  - Generic. Home: new tool plus smarttv-web-app.
- **F32. Overscan band.**
  - AW source: `tools/tv_follow_focus.mjs`.
  - Lesson: after each press, assert focus is inside the overscan-safe band. The horizontal band had been 0..1920 since creation, so earlier checks were silent. Assert that the printed band matches the platform's cut, and plant a control.
  - Generic. Home: new tool plus ten-foot-detail-design.
- **F33. Size floors.**
  - AW source: `tools/tv_audit_sizes.mjs`.
  - Lesson: measure every focusable against vendor floors at true 1080p and emit a worklist.
  - Generic. Home: new tool.
- **F34. Retail Tizen is deploy-and-launch only.**
  - AW source: `tools/tizen_deploy.sh`, TIZEN-GLASS-FINDINGS.
  - Lesson:
    - A retail set has no shell, dlog, screenshot or inspector.
    - The app becomes the instrument: a key-sequence diag overlay hosted on the video stage, because an open `<dialog>` is in the top layer.
    - Developer Mode re-entry: Apps → 12345.
  - Generic. Home: smarttv-web-app and TV-PLATFORMS.
- **F35. Engine and shim lessons from AW's `test_tv_focus.mjs` (502 lines vs T's 151).**
  - The DOM shim needs universal methods.
  - `:not()` selector parsing.
  - `tabindex=-1` asserted both ways.
  - The `<select>` exemption is keyed on the element.
  - Per-route focus restore on Back.
  - "Arrival" is separate from `claimFocus`.
  - Container-query fallbacks.
  - Home: T's `test_tv_focus.mjs` and the engine.
- **F36. `test_packaged_origin.mjs` updates.**
  - Every `js/*.js` that index.html loads must be in each TV package; two scripts 404'd for a week.
  - Skip a stale stage rather than fail.
  - Inject the Cast SDK only on http(s).
  - Gate beacons on the http(s) protocol, since a packaged `file://` app broke the privacy promise.

### G. Verdict doctrine (beyond T's "instrument honesty")

- **G37. Harness determinism.** An intermittent harness is a harness defect. Instrument its stages; never retry until pass. AUTONOMOUS-FLEET-TESTING §1's "retry ladder" needs a boundary: retries are allowed for wake and foreground, never for a verdict. (Memory `harness_must_be_deterministic`.)
- **G38. Instrument-fault taxonomy** (ENGINEERING-PROCESS §11, memory `instrument_must_be_invisible`, commit f9d00f988):
  - the probe is visible to the system under test;
  - the assertion picks its own sample;
  - no margin;
  - a bitrate is a ceiling, not a floor;
  - state is read before it is computed;
  - totals are compared across unequal windows;
  - `print` to a pipe is lost on kill, so diagnostics go to stderr or a file (T's CLAUDE.md debugging item 3 says just "use print");
  - the runner reports PASS over zero parsed results.
  - Meta-rule: run the control that should give the opposite verdict.
- **G39. Product path** (AW 130/133). A rule is proved on the product path. A skip is not a pass (pass, skip and fail are three numbers; `--strict`). A control is proved where its value lands. A shared type is not a shared code path.
- **G40. Suite honesty** (`tools/test_studio_all.sh`, `harness_awdiag.swift`, `test_studio_surface_parity.sh`):
  - a case that won't compile counts as FAIL (use a stub diag shim);
  - a missing surface file is a FAIL;
  - machine-in-use conditions SKIP with a reason;
  - kill only the servers you started.
- **G41. Audit ledgers as the work queue** (`TVOS-AUDIT`, `IPHONE-12-AUDIT`, `ANDROID-TV-AUDIT`, `ROKU-FEEDBACK-LEDGER`):
  - tiers T1 device / T2 code / T3 owner;
  - SKIP carries a reason;
  - counts at the end;
  - a separate owner-visual list;
  - an older, narrower device finds bugs.
  - Home: `docs/templates/DEVICE-AUDIT-LEDGER-template.md`.
- **G42. Read the runbook first.** Owner: "stop trying to reinvent". Grep docs, tools and memory before planning device work. Home: top of the fleet skill and CLAUDE.md.
- **G43. Door discipline** (TVOS-STUDIO-RUNBOOK §4, §6–7):
  - a refusal must log;
  - never wait on a permission prompt;
  - outward actions stop at the sheet;
  - judge media from the server recording with ffprobe (never `-v error` with volumedetect);
  - choose test content by measured audio.
- **G44. Media measurement.**
  - `measure_av_sync.py` / `measure_av_drift.py`: flash-plus-tone marker, median of about 20 pairings, and first confirm the recording is the film.
  - `verify_playback_strict.py`, `PlaybackVerifierCLI` and `verify-playback-strict.yml`: verify with the strict consumer (real AVFoundation on a macOS runner), not a lenient byte probe.
  - `rtmp_proxy_record.py`: a tiny recording proxy to diff your publisher against ffmpeg.
  - Home: resilient-media-streaming.
- **G45. Encoders and demos.**
  - `test_share_crossplatform.sh`: encode with the shipped Swift, decode with the shipped JS.
  - AW 119: verify an encoder against an independent reference, never itself; decode the rendered screenshot.
  - `oauth_demo_record.sh`: a scripted, non-driven review demo.

### Ported tools that drifted or are missing pieces

- **`ScreenOCR/main.swift`:** AW adds `w` (box width) so clipping at the frame edge can be judged. T lacks it.
- **`atv_scenario.py` (AW 720 lines vs T 368).** AW adds:
  - polled wake;
  - a press warmed on the same connection (Companion drops single presses, and the decay is cumulative);
  - a doze-signature re-wake;
  - a foreground probe with one relaunch;
  - death probes at 0/15/30 s that escalate to a reboot;
  - durable output;
  - `--protocol companion`.
  - The caption-grading principles are generic (grade what the app reads, apply its shift, a negative control on what the app drew).
- **`devlease.py`:** T is ahead (dead-pid reclaim). AW's device-key table should move into T.
- **Where T is ahead of AW** (back-port candidates): the devharness spine, `hook_coverage`, `devreset`, `qa_suite`, the Windows rig, `testlab-android.sh`.

---

## 3. Low floor, high ceiling (focus 2)

- **Platform floors by hardware reach.** See §1.1.
  - AW sources: `docs/research/IOS-FLOOR.md`, 141/148/154/155/115, PARITY §8 "Oldest hardware served".
  - Method: build at a lower target and count errors, without committing. iOS 18 cost two files; below 17, SwiftData and Observation break.
  - A stored property can't carry `@available`, so store it untyped behind a gated accessor.
  - Pin libraries strictly: a half-pin produced `AbstractMethodError`.
  - Very old OS versions are the website's job.
  - A store's device count is the only visible minSdk regression.
  - Home: CLAUDE.md, `multiplatform-expansion-method` (a new "choose floors" step), android-production-gotchas, cloud-appstore-submission, a PARITY row.
- **Capability tiers, not effort tiers.**
  - AW sources: 122, Roku `AWCan("feature")`, 131/132.
  - Legacy never sets the ceiling: gate the affordance and keep the implementation whole.
  - Gate on a hardware predicate (camera AND mic), not on form factor.
  - A capability a device can never have is omitted, with the reason in PARITY; one it currently lacks gets a sentence on screen.
  - Home: smart-tv-platform-expansion, cross-platform-parity-discipline, universal-feature-states.
- **Projection ladder with one gatekeeper.**
  - AW sources: `build_web_details.py`, `build_mcp_data.py`, `build_roku_search_feed.py`, 105.
  - Natives get the full SQLite; web and Roku get a slim index plus 256 FNV-sharded detail files with positional arrays, append-only; the MCP endpoint and feeds get smaller shards again.
  - The slim index is the gatekeeper for every thin surface.
  - Policy predicates are imported by every builder, never copied.
  - Home: shared-data-plane-contract "Projections", DATA-CONTRACT-template §2b.
- **Small purpose-built JSON for extensions.**
  - AW sources: `topshelf.json`, `tonight.json`.
  - Top Shelf, widgets and heroes read tiny pipeline files keyed by local date, not the DB.
  - Home: `docs/runbooks/tvos-top-shelf-setup.md`, which has only the device-local variant.
- **One free Worker hosting many thin adapters.**
  - AW sources: `worker/src/{index,together,live,xtream,mcp,tally}.js`, `wrangler.toml`, `docs/research/IPTV-FEEDS.md`, 142/145.
  - Adapters: Xtream/M3U/XMLTV; `/live/<ch>` as a 302 with a computed start offset (live TV with no streaming server); a stateless MCP endpoint; watch-party rooms in D1; a privacy-preserving day/shape/count counter.
  - Rules: pass lists through untouched (free-tier CPU is 10 ms); build-stamp cache keys; limiter bindings; a cron sweep.
  - Home: `zero-cost-hosted-backend` "Static-first Worker adapters", or a new `outbound-feeds-and-integrations` skill, plus a `worker/` scaffold. `test_counter_shape.mjs` belongs with it.
- **Outbound surfaces use a stricter tier.**
  - AW sources: 113, 145, 149/156, `ops/social-do-not-promote.json`.
  - Feeds and partner indexes use a stricter tier than in-app display. Feed ids never change.
  - "Never recommended, always findable" is a data flag: machine-chosen surfaces skip it; search, browse and collections keep it.
  - One served index gates every output channel.
  - Home: values-based-feed-ranking, DATA-CONTRACT policy-flags section.
- **State in the link, no backend.**
  - AW sources: `docs/PLAYLIST-SHARING.md`, 119/121/122.
  - A deflated, base64url payload in the URL fragment; about 50 items fit under ~2,000 characters.
  - Path routing (`/list/#blob`), because Android intent filters can't see fragments.
  - A real static page, because Pages' `404.html` serves HTTP 404 and gets no previews.
  - Old link shapes decode forever.
  - Declare an AASA path only after the app that handles it is live. Android is safe immediately.
  - TVs share by QR code.
  - Home: DEEP_LINKS.md, store-submission-playbook, web-platform-patterns, smarttv-web-app.
- **The web bridges the sync islands.**
  - AW sources: `docs/web-apple-sync.md`, 102.
  - CloudKit JS against the same container, plus Google Drive; the same merge function; tombstones both ways.
  - Trap: a CloudKit JS token is per environment, and a Development token fails every request.
  - A feature gated on a credential nobody has is never tested (the dropped consent PendingIntent).
  - Home: per-ecosystem-sync-islands, cloudkit-setup runbook.
- **Cross-platform watch-party sync at $0.**
  - AW sources: `docs/SHAREPLAY.md` §§8–11, `worker/schema-rooms.sql`, 131/143.
  - SharePlay is coordination only, and Apple-only.
  - "The call is not our problem": people use the call they already have.
  - The host publishes `{film, position, atServerTime, rate, paused, generation}`.
  - Cristian's algorithm with the minimum-RTT sample; rate correction first (0.97/1.03), seek only above 2 s.
  - D1 polling (KV is too eventual). Room code ≠ host key.
  - Guests play the host's exact file.
  - Free-tier limits are per account.
  - Correction returns a value the platform applies, so it tests without a player.
  - Home: cross-platform-multiplayer, cross-referenced from shareplay-activities.
- **The rule is a value; the platform is a caller.**
  - AW sources: 133, StudioThermal, CameraStallRecovery.
  - Pure functions with injected inputs make the test seam and the platform seam the same thing. T has this only for Windows.
  - Home: CLAUDE.md Apple conventions, multiplatform-expansion-method.
- **Installed-app OAuth.**
  - AW sources: 128, `docs/ANDROID-YOUTUBE-SIGNIN.md`.
  - PKCE where offered; Device Code where not (Twitch), which also works on TV.
  - Bundle id as the redirect scheme.
  - Prove request shapes with invalid ids plus RFC vectors.
  - Always persist the refreshed token.
  - A missing credential is a state with a sentence.
  - Home: authentication skill or per-ecosystem-sync-islands, plus universal-feature-states.
- **Shared per-app quotas.**
  - AW source: 136.
  - A per-app quota is spent for every user: price each call, never retry quota errors, degrade, and keep a no-API path (a stream key).
  - Home: third-party-revocation-resilience.
- **Live broadcast from the device.**
  - AW sources: 127/129/138, `test_studio_*` (about 80 files), `rtmp_proxy_record.py`.
  - Own a small documented protocol (RTMPS) rather than take a dependency. Prove it against local mediamtx plus ffprobe, with a wrong-key control.
  - Android GLES gotchas: `EGL_RECORDABLE`, Annex-B vs AVCC, `setVideoSurface` is exclusive, AAC priming, start on a keyframe.
  - Home: a new `live-broadcast-studio` skill. The engine itself is app-specific.
- **Media additions.**
  - Downloads (099): background URLSession for progressive MP4; Application Support with backup excluded; the file system is the truth; `.partial` then rename; `taskDescription` identity; none on tvOS; never synced.
  - tvOS 27 non-fragmented MP4 audio loss (106): remux to fMP4 served as HLS locally.
  - Whole-film HLS segments ignore buffer limits on all devices (118).
  - A loopback proxy paced between chunks keeps generated captions (147). Needs the `network.server` sandbox entitlement. AirPlay gets the origin.
  - The player is not a tab (103): full-screen video outside the scaffold; judge chrome in the PiP tile.
  - ExoPlayer `onPlayerError` re-prepare was missing.
  - Home: MEDIA-PLAYBACK, resilient-media-streaming, the ANDROID-DESIGN template.
- **Social and syndication pipeline.**
  - AW sources: `docs/SOCIAL-PROGRAM.md`, `SOCIAL-SETUP`, `SOCIAL-GROWTH`, `social_*` tools and tests, `social-post.yml`, `social-delete.yml`, 120.
  - Per-platform adapters that no-op without credentials.
  - A ledger written after the platform confirms; a deterministic pick so a retry posts the same item.
  - Only two benign skip reasons; any other skip fails. Six green runs had silently skipped Instagram and Threads.
  - Verify media is fetchable before handing it to Meta; Release assets serve octet-stream.
  - A do-not-promote list; every word sourced, no AI copy.
  - Atom/JSON feed from the ledger.
  - Home: vendor `social-video-teaser-craft` plus a new `social-program-pipeline` skill.

---

## 4. Parity practice, data contract, native idioms (focus 3)

- **Mechanical parity guards.**
  - AW tools: `test_hero_rule_parity.py`, `test_search_rank_parity.py`, `test_room_alphabet_parity.py`, `test_studio_rights_parity.py`, `test_studio_surface_parity.sh`, `test_version_contract.py`, `test_web_api_calls.py`, `test_us_english.py`.
  - Regex-extract constants, ORDER BY clauses and refusal sentences from the shipped Swift, Kotlin, JS and index builder, and diff them. One run asks every surface the same gate question; a gate added on one platform only recurred four times.
  - Every `API.x` the JS calls must be exported.
  - Each guard has a negative control.
  - Home: cross-platform-parity-discipline "mechanical parity guards", plus T tool seeds.
- **Port ledgers at three levels.**
  - AW docs: `ROKU-FEATURE-PARITY`, `ROKU-FEEDBACK-LEDGER`, `ANDROID-TV-PARITY`.
  - A screen matrix counts surfaces that exist, not finished ones. Roku claimed 74 ✅; the owner returned 20 defects.
  - Enumerate the reference platform's buttons from source. Tag cells T1/T2/T3. Reachable is not parity.
  - The app self-reports which rows it renders.
  - Home: the skill plus a `PORT-PARITY-LEDGER` template.
- **How AW's PARITY.md actually runs** (830 lines).
  - Works:
    - an n/a symbol separate from 🚫;
    - evidence in cells;
    - parity-test names in Notes;
    - per-section verification-gate tables;
    - a §9 data-plane "consumed by" table;
    - an "Oldest hardware served" row;
    - a per-platform capability definition table, with host and join as separate columns.
  - Rots:
    - journaling inside the matrix (13k-character rows);
    - §8b drifted false once ports got their own ledgers;
    - `split("|")` has a leading empty element, so scripted edits hit the wrong column four times.
  - Home: T PARITY maintenance protocol:
    - cap a cell at a sentence plus a link;
    - one summary row per ledgered port;
    - scripts read columns by header name;
    - a capability-definition-table pattern.
- **Doc-layer parity.**
  - AW stamps one cross-platform rule into every platform DESIGN doc on the same day, each citing the origin rule and the owner's "yes, all platforms".
  - Feature-scoped binding docs (`CAPTIONS.md`, `SHAREPLAY.md`, `PLAYLIST-SHARING.md`, `PULSE.md`) sit beside the platform docs. They carry an OS × platform capability matrix re-derived by an audit tool (`audit_caption_tiers.py`) and a new-platform checklist.
  - Home: binding-design-doc-discipline, plus a `FEATURE-DESIGN` template.
- **iPad form-factor doc.**
  - AW source: `docs/IPAD-DESIGN.md`.
  - Width caps (prose 700, button 480, picker 560 pt: "a control's width is a claim about its importance").
  - Inspectors, not sheets. A sidebar of places. Hover and a context menu everywhere. Draggable items. `.commands`. A per-scene Router. "What the iPad does not do".
  - Home: an `IPAD-DESIGN` template, or a regular-width part of the IOS template.
- **A data contract is a test** (116, `test_details_contract.py`). Assert the documented shape over the real published artifact. The web's tolerance hid a shape defect that crashed Roku on 5.4% of titles. Fixing the producer repairs shipped clients with no review. Home: shared-data-plane-contract, DATA-CONTRACT §9 "Contract tests".
- **Tier fields by use** (`docs/METADATA-EXPANSION.md`). Detail-only fields go in a blob, searchable text in FTS, filterable values in join tables. Budget download size (≤35 MB) and queries (EXPLAIN before and after).
- **Named filter clauses** (`docs/CATALOG-CONTRACT.md` §5). `adultAnd` / `typeAnd` / `homeAnd` / `notCommercial`, with each verb stating which it applies. Advertising surfaces are gated more strictly than lookups. Hero-rule copies drifted, so web and Roku admitted 46–67% more. Home: DATA-CONTRACT §5.
- **Pipeline-side policy.** A guard belongs in the shared selector, not a downstream sweep (104). One predicate function is imported by every artifact (105). Rank once in the pipeline and store the "why" (139).
- **Standing rules AW has and T lacks** (AW CLAUDE.md, owner quote in commit e41c8641b):
  - only essential words on screen (a caption must be a refusal, a warning, or an undiscoverable fact);
  - no AI-written lists or copy in the product;
  - side doors (feeds, MCP) are findable on the website, never featured in the apps;
  - one spelling locale, linted;
  - real devices only;
  - ship state lives in the dashboard.
  - Home: CLAUDE.md Standing instructions, learning-orientation-design, mobile-first-density-design.
- **Web traps** (AW WEB-DESIGN §10–12):
  - `cache:'no-store'` doesn't bypass a service worker;
  - an author `display` rule beats `[hidden]`;
  - a one-shot render must replace before it appends;
  - compute each facet against the other's selection, and never offer a chip that yields zero rows;
  - don't duplicate browser-native PiP or speed controls (`test_native_controls.mjs`, measured per browser);
  - view-transition and sw-bypass tests (`test_view_transition.mjs`, `test_sw_bypass.mjs`; the skill describes the latter but T doesn't ship it);
  - `test_web.sh`: `node --check` plus CSS brace balance.
  - Home: web-platform-patterns, WEB template.
- **TV and macOS idioms.**
  - A held Select is a TV card's second verb; focus returns to the same card or its neighbour.
  - Every Mac command is in the menu bar.
  - A Mac button says what it does at every width: `ViewThatFits`, `.fixedSize()`, a More menu, never truncation (134).
  - Direct manipulation over sliders; `.offset` is render-only; `scrollWheel` needs a local monitor (135).
  - A view being rebuilt is not a window being closed.
  - Redesigned iOS surfaces must hold at accessibility text sizes.
  - Home: tvos/androidtv skills, macos-platform-patterns, the templates.

---

## 5. Process, CI, store and pulse lessons (supporting)

- **Engineering process.**
  - AW `docs/ENGINEERING-PROCESS.md` (created 09-09; 11 disciplines, each with incidents) has no T equivalent.
  - Rules not covered elsewhere in T:
    - absence is not evidence;
    - a test isn't a test until seen to fail, with the count recorded in the commit;
    - a negative finding needs an expiry and a method, never "do NOT re-walk" (Amazon was blocked five weeks by such a note);
    - search the decision log for the mechanism, not the symptom (106);
    - popularity is not editorial judgement;
    - Consequences paragraphs rot within the session (121).
  - Home: a new `docs/ENGINEERING-PROCESS.md`, or merge into AUTONOMOUS-LOOPS.
- **Working-style memories** (AW memory dir):
  - read the runbook first;
  - an audit loop fixes what it finds without asking;
  - report times in local time, not UTC;
  - announce "Next tick" before `ScheduleWakeup`;
  - warnings are defects;
  - the CI Xcode differs from the local beta;
  - batch trivial store releases;
  - no new Play upload while one is in review;
  - store releases bump MINOR and commits bump PATCH;
  - verified is not shipped (Apple was 41 versions behind);
  - commit messages go through `-F` with a quoted heredoc;
  - "unable to type-check" usually means a wrong argument label;
  - credentials go where the tool looks;
  - the Gmail connector rewrites links.
  - Home: AUTONOMOUS-LOOPS §5–6 and CLAUDE.md collaboration.
- **Store tooling.**
  - `asc_release.py`:
    - loops over platforms (iOS, tvOS, macOS);
    - filters builds by `preReleaseVersion.platform`;
    - waits for the build to become VALID;
    - refuses to submit without notes;
    - passes inputs through env, never pasted into bash;
    - a wrong version string can only be renamed, never deleted.
  - `submit-play.sh` / `play-publish.py`:
    - dispatch CI by default;
    - refuse notes over 500 characters before bumping (this burned a versionCode once);
    - retry on 5xx;
    - handle `changesNotSentForReview`;
    - a release-APK smoke test that honours leases.
  - `submit-amazon.py`:
    - reuse the one open edit;
    - on a minSdk conflict, delete then upload.
  - `audit_fire_tv_manifest.py` + `test_fire_tv_manifest.py`: minSdk ≤28, optional features, both ARM ABIs, leanback launcher.
  - Tizen:
    - hide competing-store links;
    - an unanchored `sed` corrupted `<?xml version>`;
    - a space in the .wgt name makes install fail silently;
    - certificate/DUID via the small `+`;
    - password kept apart from the key.
  - Home: tools, play-cli-submission, store-submission-playbook, docs/store.
- **CI workflows.**
  - AW's `appstore-build.yml`:
    - writes `Secrets.xcconfig` from secrets and fails if any are missing (builds had shipped without keys);
    - prunes certificates first and revokes this run's with `always()`;
    - refuses a duplicate build number;
    - runs the floor tests;
    - trap: an `[ -n x ] && ARGS+=` one-liner ends a `bash -e` step when x is empty.
  - `play-release.yml`: platform-tools only; builds the Fire TV APK from the same commit.
  - `pulse.yml`: crons run 4–5 hours late, so schedule for the lag; `workflow_run` after releases.
  - `deploy-pages.yml`: `workflow_run` after `[skip ci]` commits; `paths-ignore`. T ships no deploy workflow.
  - `play-bucket-probe.yml`: `pipefail`, because `| tee` hid a crash.
  - Home: CI-FLEET, cloud-appstore-submission, workflows.
- **Pulse.**
  - `pulse_collect.py` (AW 3,101 vs T 1,642 lines, 37 commits):
    - refuse `--apply` when a third or more of readers are dark;
    - `HEALTH_OWNS` must cover every key, with a test;
    - record unknown product codes (Mac F1/FI1 made macOS read zero);
    - the Apple sales report is vendor-wide, so filter by Apple Identifier;
    - staleness comes from the object's update time; set alarms past the measured Play lag (14 days installs, 8 acquisitions);
    - Amazon installs are $0 `Charge` rows;
    - the Amazon live version is readable only through an edit, and never delete someone else's edit;
    - a Roku Looker webhook drop box on the Worker (gate the ack on `--apply`; Cloudflare 403s the bare urllib UA);
    - a missing column is null, never zero;
    - Search Console and Cloud Monitoring readers (the `x-goog-user-project` header).
  - `pulse/` (charts.js 514 vs 168 lines): run chart, calendar heat, dot plot, pareto, time chart, a shared-scale `spark`, one `VIEWS` list; a code error must not render as a data failure.
  - `docs/PULSE.md` look rules 7–13; a `RULES`-table needs/going-well view; one view per audience.
  - Privacy: count from what servers and vendors already see, never a new client ping (142).
  - Home: tools, `pulse/`, PRODUCT-PULSE, and the two skills.

---

## 6. Recommended new homes in T (consolidated)

**New skills:**
- `evidence-gated-catalog-curation`. Generic kernels of 124, 137, 140, 149–152, 156–158:
  - a claim a reader can open; not knowing is not a claim;
  - never recommended, always findable;
  - restore by adding evidence, never by loosening a rule;
  - a cleared match scrubs what it filled;
  - thresholds computed from the calendar;
  - an alternate edition is a version, never the default;
  - stamp every text field with its provenance.
- `live-broadcast-studio`: 127/129/136/138.
- `outbound-feeds-and-integrations`, or a zero-cost-hosted-backend section: Worker adapters, IPTV, MCP, Roku search feed, Atom.
- `social-program-pipeline`, plus vendoring `social-video-teaser-craft`.

**New docs and templates:**
- `docs/ENGINEERING-PROCESS.md`
- a bench manifest
- `DEVICE-AUDIT-LEDGER`, `PORT-PARITY-LEDGER`, `FEATURE-DESIGN` and `IPAD-DESIGN` templates
- `APPLE-DEVICE-RECIPES`
- a `worker/` scaffold

**New tools:**
- `asc_release.py`
- `atv_shot.sh`, `atv_teardown.sh`, `mac_window_shot.swift`, `dev_cleanup.sh`
- `tv_glass.mjs`, `tv_reachability.mjs`, `tv_follow_focus.mjs`, `tv_audit_sizes.mjs`
- a Roku runner plus sweep, audit and playback-audit tools
- `gtv_scenario.py`, `ios_scenario.py`
- floor tests and `test_version_contract.py`
- Fire TV manifest audit
- `test_workflow_health.py`, `test_sw_bypass.mjs`, `test_web.sh`, `test_us_english.py`
- `rtmp_proxy_record.py`, `measure_av_sync.py`, `play_bucket_probe.py`

**Deliberate exclusions to record in PROVENANCE:**
- the Watch Together Studio engine
- the Creation Studio
- rights-audit specifics (114, 125, 146, 153, 157 details)
- the catalog, subtitle and poster pipelines (about 40 workflows)

**PROVENANCE should add a 2026-09-30 audit line covering AW decisions 096–158.**
