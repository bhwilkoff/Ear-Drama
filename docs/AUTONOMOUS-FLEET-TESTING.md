# Testing on a fleet of real devices

Archive Watch once ran a sweep of twelve steps on an Apple TV, and every
step passed. Every screenshot was black. The TV had gone to sleep, a
sleeping Apple TV hands back a perfectly valid black PNG, and the check
could not tell "the row is missing" from "I cannot see anything." Around
the same time, a run left a film playing unmuted on another Apple TV for
an hour, and because an Apple TV sends its sound to every HomePod in the
house, the music came out of speakers in every room.

Both of those are real-device testing done carelessly. And yet the bench
of real devices is the best thing Archive Watch built.

I want to be able to read "fixed" in a session log and trust it. That
means every "fixed" points at something a person could look at: a
screenshot of the actual screen, a number read off the device, or a run
that could have failed and did not. I also want the bench to behave like
a careful guest in the house it lives in.

**The screen is the evidence. The app's claim is not.**

This page is the method: why we test this way, how the bench is set up,
and the rules for judging what a run tells you. The per-platform commands
and traps (Apple TV pairing, adb settings, Roku's control protocol, the
web-TV tools, Windows over SSH) live in `docs/DEVICE-HARNESSES.md`. The
tools themselves are in `tools/`, and `tools/app_config.py` is the one
file a new app edits to point them at itself.

---

## 1. The doctrine

A test that asserts `viewModel.state == .loaded` proves the view model. It
proves nothing about whether a person sees a question on the screen. So we
drive the real app on real hardware, photograph the glass, read the
photograph with on-device text recognition (OCR), and grade what it says.

Three corollaries, each of which cost real time to learn:

- **An instrument must say when it is blind.** A check that cannot see its
  input has to fail loudly, never report clean. This is the most repeated
  failure in the history of this rig, and it keeps arriving in new
  disguises. Section 8 is the longest on this page for that reason.
- **A green build tells you very little.** The four App Store blockers in
  `docs/APPLE-SUBMISSION-CLI.md` all compiled, archived and signed green,
  then failed at upload. The tvOS write to Application Support that
  crashes on a real device passes on the simulator.
- **Drive to the degenerate outcome, not only the happy path.** The tie,
  the zero score, the empty list, the cold quit, the last question. A
  finished-round screen that only ever showed the last question survived
  a full test suite because nothing in the suite ever finished a round.

The rule that sits over all of this comes from `docs/AUTONOMOUS-LOOPS.md`:
the agent is never the tester. The agent changes the code. The evidence
comes from something outside the agent.

## 2. The ladder and the spine

Evidence comes in rungs, from cheapest to most convincing. Use the
cheapest rung that can actually see the bug, and climb only when a lower
rung can be fooled.

1. **Doors.** Environment-gated entry points that open any screen directly
   and do nothing in production (section 3).
2. **Simulators, emulators and headless browsers.** Fast and free. Fine
   for layout and logic, lenient about the filesystem, entitlements, sync,
   speech models and store billing.
3. **Real devices on a bench.** Screenshots of the glass, read by OCR,
   graded against explicit assertions.
4. **A person.** Whether a transition feels right, whether a caption reads
   from the couch. Those go on a short list for the owner, and the tools
   never pretend to have checked them.

The tools share a spine and keep their hands separate:

```
tools/qa_suite.py        the entry point a loop calls: walks the bench, one lease per device
tools/bench.py           the bench manifest: which devices exist and what each is FOR
tools/devlease.py        cooperative leases between agent sessions
tools/devharness.py      OCR, grading, artifact paths, capture_fresh, the blind guard
   ├── apple_device.py   devicectl + pyatv plumbing shared by the Apple runners
   │     ├── atv_run.py, atv_scenario.py   Apple TV
   │     └── ios_run.py, ios_scenario.py   iPhone and iPad
   ├── adb_run.py, gtv_scenario.py         Android phone, Google TV, Fire TV
   ├── mac_run.py        the Mac, captured by window id (winshot)
   ├── win_run.py ─ winbox.py              a real Windows box over SSH
   └── web_run.py ─ webdrive.py            Chrome over the DevTools Protocol
tools/roku_run.py and friends              Roku, over its External Control Protocol
tools/_tv_cdp.mjs and the tv_*.mjs tools   web TV at a true 1920x1080
```

Put in the spine only what is truly the same everywhere: OCR, text
grading, thresholds, artifact layout, the stale-capture guard and the
blind-instrument guard. A lesson learned on one device then reaches all of
them.

Keep device plumbing out of it. Waking an Apple TV over its Companion
protocol, keeping a Pixel awake over adb, and giving up on a locked iPad
are different operations. Forcing them into one abstraction produces a
lowest-common-denominator tool that cannot express what any single
platform needs. Shared judgement, separate hands.

The cost of skipping this is visible in a sibling project: three
hand-written runners that shared nothing but an OCR binary. Its iOS runner
had no wake, no alive probe and no relaunch step, because the tvOS
resilience was never carried across.

## 3. Doors make a surface reachable

A surface nothing can drive is untested, and it reads as a pass.

`python3 tools/hook_coverage.py` reads each codebase for the hooks it
honours and prints which surfaces each platform can reach. When it was
first written it found twelve unreachable surfaces, and every one of those
twelve had been counted as fine.

Give the app **doors**: environment-gated entry points that are no-ops in
production.

The starters ship four of them already, honored only in debug builds:
start tab, start item, mute, and door seconds (return home after N
seconds, so a door never leaves a screen open). Apple reads them in
`apple/Core/Store/LaunchDoors.swift` and posts into the `AppStore`
inbox; Android reads intent extras in `navigation/LaunchDoors.kt`;
Windows in `LaunchHooks.cs`; the web takes `?view=`, `?item=`,
`?mute=1` and `?door_seconds=`. Every name comes from
`tools/app_config.py` (`HOOK_*`). On Android the spelling is always
`android_extra(HOOK_...)`: `appname_` plus the hook in lowercase without
`APP_`, so `APP_START_TAB` is `appname_start_tab`.

| Platform | Mechanism |
|---|---|
| iOS, iPadOS, tvOS, macOS | `devicectl ... process launch -e '{"KEY":"VALUE"}'` (JSON), or `SIMCTL_CHILD_*` on a simulator |
| Android, Google TV, Fire TV | `am start --es KEY VALUE` extras, gated on `BuildConfig.DEBUG` |
| Web | query parameters (`?view=`, `?item=`, `?mute=1`, `?door_seconds=`) read at boot |
| Windows | environment variables read at startup |

The hook names live in `tools/app_config.py` (`HOOK_START_TAB`,
`HOOK_START_ITEM`, `HOOK_AUTOPLAY`, `HOOK_SKIP_ONBOARD`, `HOOK_QA_LABEL`,
`HOOK_TYPE_SIZE`, `HOOK_FORCE_OFFLINE`, `HOOK_MUTE`, `HOOK_DOOR_SECONDS`,
`HOOK_DIAG_FILE`). `python3 tools/ios_scenario.py doors` prints the
catalog with what each one does.

Rules for doors, each from a failed run:

- **Quote adb extras.** An unquoted space destroyed every extra after the
  first, and the truncated banner was dismissed as cosmetic for hours.
  `tools/adb_run.py` routes every extra through a quoting helper.
- **Install the debug Android build.** The hooks are `BuildConfig.DEBUG`
  gated, so against a release build they silently do nothing, every
  scenario lands on Home, and every scenario passes.
- **Ship a skip-onboarding door.** A first-run modal blocks every capture,
  and screenshots taken behind it look like the app is being driven.
- **Doors are muted and time-bounded by default.** `DOOR_DEFAULTS` in
  `app_config.py` adds `APP_MUTE=1` and `APP_DOOR_SECONDS=180` to every
  launch. Section 7 explains why.
- **A door that refuses must log.** A refusal that prints nothing looks
  exactly like a door that never fired.
- **Never wait on a permission prompt,** and stop outward actions at the
  confirmation sheet. A door that pressed "Go live" would broadcast from a
  television nobody is standing in front of.
- **A forced-offline door fakes the state, never the network.**
  `APP_FORCE_OFFLINE` renders the offline screen for a screenshot. Proving
  the app works offline means denying the network to the process
  (`docs/DEVICE-HARNESSES.md`, Mac section).
- **A door bypasses the real input path.** An input feature is not done
  until it has been pressed through the real remote or keyboard, with a
  log line per press. On Archive Watch, AVKit swallowed presses that every
  door-driven test had routed around.
- **Test deep links on a device with history.** A fresh sideload passes
  every deep-link test, because it has no state for the link to collide
  with.

## 4. Setting up your bench

This walkthrough takes you from an empty checkout to a first run of the
suite. Do it in order. Each step has a check you can run before the next.

### Step 1: Describe the bench

Copy the example manifest:

```bash
cp tools/bench.example.json ~/.device-bench.json    # machine-wide (recommended)
# or
cp tools/bench.example.json tools/bench.json        # this repo only; gitignored
```

`tools/bench.py` looks in three places, in this order: the path in
`$DEVICE_BENCH`, then `tools/bench.json`, then `~/.device-bench.json`. The
machine-wide file is the natural home, because the devices belong to the
desk rather than to a repository, and the lease directory
(`~/.device-lease/`) is machine-wide for the same reason.

Each entry is keyed by its **lease name** (`atv`, `ipad`, `iphone`,
`pixel`, `androidtv`, `firetv`, `roku`, `mac`). Two repositories sharing a
desk must agree on these names. Fill in what each device has:

| Field | What it holds | Where to find it |
|---|---|---|
| `platform` | `ios`, `ipados`, `tvos`, `macos`, `android`, `androidtv`, `firetv`, `roku`, `webos`, `tizen`, `windows`, `web` | |
| `udid` | the devicectl identifier (Apple) | `xcrun devicectl list devices` |
| `serial` | the adb serial (Android) | `adb devices -l` |
| `address` | IP or host for pyatv, Roku, adb over TCP, SSH | the device's network settings |
| `pyatv_id` | the Companion identifier for `atvremote --id` | `~/.pyatv-venv/bin/atvremote scan` |
| `os`, `model` | as last verified | the device |
| `role` | see section 5 | you decide |
| `apple_id` | a label such as "test account A", never the address | |
| `capabilities` | `screenshot`, `console`, `press`, `launch`, `install`, `deeplink`, `power`, `diagfile` | |
| `quirks` | free text a reader must know about capturing or driving it | experience |
| `verified` | the date this row last answered a real query | |

Delete the example devices you do not own. Add your own phone with the
role `owner-personal-never-touch` if it is paired to this Mac.

Check it:

```bash
python3 tools/bench.py check          # validates roles, platforms, required ids
python3 tools/bench.py                # lists the bench with roles
python3 tools/bench.py get atv udid   # one field, for shell scripts
python3 tools/bench.py role iphone    # one device's role
```

If there is no manifest at all, `bench.py` builds one from
`app_config.DEVICES` (one device per kind, role `test`). That is enough
for a first phone and not enough for a real bench.

### Step 2: Tell the tools who your app is

Open `tools/app_config.py` and fill in:

- **Identity:** `APPLE_BUNDLE_ID`, `APPLE_APP_NAME`, `APPLE_EXECUTABLE`
  (what `devicectl device info processes` prints, usually the app name),
  `ANDROID_PACKAGE`, `ANDROID_PACKAGE_DEBUG`, `ANDROID_MAIN_ACTIVITY`,
  `WINDOWS_PROCESS`, `WEB_URL`, `ROKU_CHANNEL_NAME`.
- **The words that prove your app is on screen:** `APP_ANCHOR_RX`. Use
  words your interface actually renders (tab titles, primary actions), not
  the app's name. Get this wrong and every scenario fails as "wrong
  screen."
- **Text that means broken:** `FORBIDDEN`. Keep patterns word-bound. A
  forbid pattern of `Error` once matched inside the word "terrorists" in a
  trivia question and failed a healthy run.
- **Thresholds:** `CLIP_X` and `MIN_OCR_LINES`. Calibrate both against a
  real capture from your own device (section 9), and write down where the
  number came from.
- **Doors:** the `HOOK_*` names, `DOOR_DEFAULTS`, `ANDROID_DOOR_EXTRAS`,
  and for media apps the diagnostics-file protocol (`HOOK_DIAG_FILE`,
  `DIAG_CONTAINER_PATH`, `DIAG_TAGS`).
- **Tool locations,** each overridable by an environment variable of the
  same idea: `HARNESS_BIN_DIR`, `SCREEN_OCR`, `WINSHOT`, `QA_ROOT`,
  `PYATV`, `ADB`, and `DEVELOPER_DIR` (empty means inherit
  `xcode-select -p`; set it when devicectl must come from a beta Xcode).

The runners' scenario tables (`SCENARIOS` in `atv_run.py`, `ios_run.py`,
`adb_run.py`, `mac_run.py`, `win_run.py`, the `ROUTES` in `web_run.py`)
and the smoke sets in `qa_suite.py` still carry sample surfaces from the
app this rig came from. Replace them with your own.

### Step 3: Build the two Mac instruments

Every runner shares one OCR binary and one window-capture binary, both at
durable paths under `build/bin/`. `devharness.ensure_ocr()` and
`ensure_winshot()` build them on first use, but build them by hand once so
you see any compiler error yourself:

```bash
swiftc -O tools/ScreenOCR/main.swift   -o build/bin/screenocr
swiftc -O tools/mac_window_shot.swift  -o build/bin/winshot
build/bin/screenocr some-screenshot.png     # one JSON line: allText, captionRegion, centerLuma
```

Never put them in `/tmp`. It is wiped on reboot, and two runners once
looked for the OCR tool under two different `/tmp` names, so one of them
quietly skipped its readability check.

### Step 4: Give pyatv its own Python

The Apple TV runners wake, press and read power state through pyatv's
`atvremote`. It lives in its own virtual environment on Python 3.12,
because it does not run on 3.14:

```bash
python3.12 -m venv ~/.pyatv-venv
~/.pyatv-venv/bin/pip install pyatv
~/.pyatv-venv/bin/atvremote scan                                   # find pyatv_id and address
~/.pyatv-venv/bin/atvremote --id <pyatv_id> --protocol companion pair
python3 tools/apple_device.py power --device atv                   # prints on, off or unknown
```

Pair each Apple device with Xcode first. The steps, and what to do when
the TVs vanish, are in `docs/DEVICE-HARNESSES.md`.

### Step 5: Prepare the Android devices once

```bash
adb -s <serial> shell settings put global adb_allowed_connection_time 0
adb -s <serial> shell svc power stayon true
adb -s <serial> shell settings put system screen_off_timeout 1800000
```

Without the first line, adb trust silently expires after seven days and
the device simply stops answering. With the last two, the owner enters
the passcode once and the phone never locks again during testing.

### Step 6: Run the suite on one device

```bash
python3 tools/hook_coverage.py                     # which surfaces can be reached at all
python3 tools/qa_suite.py --devices ipad           # one device first
python3 tools/qa_suite.py                          # then the whole bench
```

Read the output before the summary. Every device that did not run gets a
SKIP line with its reason: its role, "not on the bench", "not online in
adb devices", "leased elsewhere", or a pointer to the Roku tools (which
have their own runners). Each run writes `report.json` and screenshots
under `build/qa/<platform>-<date>/`, and the suite writes
`build/qa/suite-<date>/<tag>/summary.json` so two runs can be compared.

Other useful flags: `--full` runs every scenario each runner knows,
`--scenarios home,settings` overrides the smoke set, `--owner-ok` includes
owner-watches devices (ask first), and `--lease-wait 300` waits for a
device a peer session holds instead of skipping it.

Be ready to open one screenshot from that first run and say which words
in it proved your app was on the screen.

## 5. Roles decide what a run may touch

A working bench is more than one device of each kind. Archive Watch's grew
to fourteen: three Apple TVs on two tvOS versions, an Apple TV HD, two
iPhones on two Apple IDs, an iPad, a Mac, two Rokus, a Google TV, a Fire
TV, a Pixel and a Samsung television. Each device is there for a reason,
and the role says what the reason is.

| Role | What the runners do |
|---|---|
| `test` | Drive freely. |
| `floor` | The oldest hardware or OS you support. Drive freely, and treat a failure here as a real finding. |
| `os-control` | Held on a different OS on purpose, so an OS-specific claim can be tested instead of inferred. |
| `owner-watches` | A device somebody actually uses. Refused unless the run passes `--owner-ok` or sets `BENCH_OWNER_OK=1`. Ask before waking a television in someone's room. |
| `owner-personal-never-touch` | Refused by every runner, every time, with no override, even when handed its raw UDID. A personal phone is on the bench because it is paired, not because it is available. |

`bench.require()` enforces this in every runner, and it also refuses a
device of the wrong platform (an Apple TV handed to the iPhone runner).

Three things a bench teaches:

- **An older, narrower device finds bugs.** Archive Watch's Roku 2 XD on
  Roku OS 9.1 found two faults that no modern player showed.
- **Two accounts make a real peer.** SharePlay, CloudKit sync and Sign in
  with Apple behave differently between "two devices, one account" and
  "two accounts." Label which device is on which account.
- **A claim with a date is a fact.** Update `os` and `verified` when a row
  answers a real query. A bench table from memory goes stale quietly.

## 6. One lease, one session, the whole run

Two agent sessions in two repositories, one bench. Each session installs
builds, force-stops apps to reach a clean state, and drives the screen.
Neither knows the other exists. So contention arrives looking like a bug
in your product: your app is not in front, your app died mid-run, a
screenshot shows another app.

`tools/devlease.py` is a cooperative lease. State lives in
`~/.device-lease/<device>.json` with the owner, pid, task and expiry. The
rules are few on purpose:

1. Take a lease before touching a device, and release it after.
2. A lease has a time limit, so a crashed session frees the bench on its
   own. A lease held by a dead process is reclaimed at once.
3. Never take a live lease from a peer. Wait, or skip the device and say
   so. A skipped device reported honestly beats a contended device
   reported as a product failure.
4. Reading a foreign lease tells you who holds it, so the message names a
   peer instead of blaming the app.

**Hold one lease for the whole run, in one process.** Install, launch,
capture, grade and tear down under the same lease. A lease per step
leaves a gap between steps, and a peer session took an Apple TV in exactly
one of those gaps. `devlease.hold()` takes every device a run needs, all
or nothing, renews them in the background, and releases them on any exit.
`qa_suite.py` holds each device's lease for its whole block of scenarios
and hands it down to the runners it starts through
`DEVICE_LEASE_HOLDER_PID` (`devlease.child_env()`).

When a device is leased elsewhere, the run is a SKIP (the Apple TV runner
exits 2), and a SKIP covers nothing. `python3 tools/devlease.py` shows who
holds what. Copy `devlease.py` unchanged into every repository that shares
the bench, because the value is that both sides speak it identically.

## 7. Leave the room as you found it

A bench lives in somebody's home. Every run follows the same manners, and
each one is a step with an assertion, not an intention.

- **Teardown is verified by the device.** The runners terminate the app by
  pid, then ask the device whether the process is gone, then restore the
  power state they found and read it back (`apple_device.teardown()`,
  `tools/atv_teardown.sh`, `pidof` on Android). The Apple TV, iPhone and
  Android reports all grade it as `left_as_found`. `--leave-running` exists for the rare run that needs
  it.
- **Doors are muted and time-bounded.** An audible run is opt-in
  (`--audible`), and you ask the owner first. A player-level mute can also
  silence the audio a tap reads, so audio is graded only on audible runs.
  A playback door's time bound must outlast the capture.
- **No camera or microphone of the owner's on a bench run.**
- **Restore the room.** Record the television's volume around a Cast test
  and put it back. A permission prompt (macOS or tvOS privacy consent,
  TCC) outlives a killed app, so check the authorization status in code
  and never press Allow for someone. Never put a test device to sleep.
- **Check that a television is ON before any command.** A sleeping box
  returns black captures that read as "nothing drawn," and a refused
  launch can look like a crash. Ask before waking a television in a room
  where someone may be sleeping or watching.
- **Pointer automation only when the owner is away from the Mac**, and aim
  from the element's accessibility frame, never a guessed coordinate: a
  guessed click once landed on a second display.
- **Close what a door opened.** Bench doors leave debug instances running;
  seven copies of one app piled up in a day. Close each after its run, and
  quit a live session only after it has ended (a quit mid-session raises a
  confirmation that blocks automation).
- **Say what is under test.** `tools/devreset.py` stops the app on each
  device before a run, and its `label()` sets `APP_QA_LABEL`, which every
  client draws as a small banner. A photograph of the bench then says what
  each screen is testing.
- **Clean up the Mac.** `tools/dev_cleanup.sh` reports stray
  `http.server` previews, Gradle and Kotlin daemons, ffmpeg, glass-tool
  Chrome or node, hung `atvremote` and console streams; `--stop` ends
  them. A machine that "slowed down" was once two render processes at 98%
  CPU for three and a half days.
- **Restore the volume.** Run an audible suite as
  `tools/dev_cleanup.sh volume-guard -- <command>`. It saves the system
  volume and mute state, restores both on exit, error, Ctrl-C or kill, and
  reads them back. An audible suite once finished with the volume at 100.
- **Capture the Mac one window at a time.** Region and full-screen
  captures on the owner's Mac picked up other windows that were open, including personal documents. `winshot` captures one window,
  owned by exactly your app, with no fallback of any kind.

## 8. Instruments that tell the truth

An instrument that cannot see must say so. A null result from a blind
instrument looks exactly like a real absence, and that is why this failure
keeps coming back.

Real instances, all one bug wearing different clothes:

| What happened | What it looked like |
|---|---|
| `xcode-select` pointed at CommandLineTools, so `xcodebuild -showBuildSettings` errored with stderr suppressed | "`DEBUG` is defined in neither configuration" |
| `actool` rejected a flag outright, so the warning being grepped for never appeared | "that role accepts the icon" |
| A test file created after project generation was not in the target | A suite passed having run zero tests |
| A gate grepped for text that also appeared in its own explanatory comment | It passed on the warning about the thing it was warning about |
| An OCR crop used bottom-left origin against a top-left window rectangle | It kept the wrong half of the screen, silently |
| The home-screen probe swallowed a TypeError when OCR printed nothing | "Not the home screen" for weeks, so the guard never ran once |
| An assertion read `centerLuma`, a field the OCR tool never emitted | A check that could never pass, however correct the screen |

The rules the tools now follow:

- **A capture never returns stale evidence.** Delete the target, capture,
  then refuse a missing file, an empty file, or one older than 60 seconds
  (`devharness.capture_fresh()`, `tools/atv_shot.sh`). A stale PNG was
  once reasoned about as current, and only the clock drawn inside it gave
  it away.
- **Ask the device, never the pixels.** A sleeping Apple TV returns a
  valid black PNG, so power state is read before every launch, press and
  capture.
- **Count lines, not bytes.** A frame with fewer than `MIN_OCR_LINES` OCR
  lines is unreadable. Byte size depends on resolution and content.
- **A readable frame of the wrong app is worse than a blank one.** Check
  for your app's own words (`APP_ANCHOR_RX`) and for the tvOS home-screen
  signature (`TVOS_HOME_RX`). The home screen once survived every other
  check while a sweep reported missing shelves.
- **"Could not tell" is its own answer.** An OCR failure is `OCR_FAILED` or
  `None`, never "screen off" and never "not home."
  `frame_is_home_screen()` returns True, False or None.
  `tools/test_home_screen_probe.py` has a case for every way OCR can be
  blind.
- **An assertion needs a field the instrument actually emits.** ScreenOCR
  now emits `w` (box width, so clipping can be judged) and `centerLuma`
  (so a missing image can be judged).
- **Never perturb what you measure.** An audio watchdog that revived its
  dead tap by replacing the player's audio mix manufactured the dropouts
  it then reported. Screenshot capture itself can push a device into
  killing the app to free memory. Treat a death during capture as a
  harness artifact until a crash report names the app.
- **Identify your own configuration.** Every run records the build, flags
  and device it ran against, or one day you will validate the old binary.
- **Keep captures durable.** `build/qa/`, never `/tmp`. A capture you
  cannot return to is a capture you have to take twice.
- **Reach screens by door or deep link, never by counting presses.**
  Navigation drift turns a runner into a flake generator. Where presses
  are the thing under test, navigate closed-loop: read where focus landed
  after every press.
- **Never suppress stderr on a diagnostic command,** and send your own
  diagnostics to stderr or a file. `print` to a pipe is buffered and lost
  when the process is killed.

## 9. Verdicts

A run produces a verdict, and the verdict has its own rules.

**The harness is deterministic, or it is broken.** An intermittent runner
is a runner defect. Instrument its stages and find the cause. Retries are
allowed for getting the device ready (wake, bring the app to the front,
one relaunch after a death in the first seconds). Retries are never
allowed for a verdict. Retrying until it passes is how a flaky product
ships.

**The instrument is the first suspect.** Before believing a verdict, run
the control that should obviously produce the opposite one. The faults
this catches, from one session at Archive Watch where four of eight
instrument faults gave the opposite of the truth:

- The probe is visible to the system under test (a readiness probe became
  connection 1 of a severing proxy, so the proxy cut the probe).
- The assertion picks its own sample (it judged the last segment, a short
  one written at close, and passed over the one that mattered).
- There is no margin (58.4 versus 58.3 passed as "smaller").
- A bitrate is a ceiling, not a floor (a static frame compresses to
  nothing, so lowering the ceiling changed nothing).
- State is read before it is computed.
- Totals are compared across unequal windows. Compare rates.
- Diagnostics printed to a pipe are lost on kill.
- The runner reports PASS over zero parsed results.

**Pass, fail and skip are three numbers.** A skip is not a pass. A reader
that could not read reports SKIP with its reason, never silence and never
a confident zero. A run over zero results did not pass. When you write a
new runner, give it a `--strict` mode that fails on any skip.

**A test is not a test until you have seen it fail.** Write the check,
break the code on purpose, confirm the check catches it, then restore the
code. Record the failure count in the commit. Where you can, plant a
control that must fail on every run: `TV_PLANT=1` on the reachability
tool, `--expect-captions no` on the playback runner, the negative control
in the Fire TV services audit.

**A rule is proved on the product path.** A control is proved where its
value lands, not where it is set. A shared type is not a shared code path.

**Suite honesty:**

- A case that will not compile counts as FAIL (give it a stub so it can
  run).
- A missing surface file is a FAIL.
- A machine-in-use condition is a SKIP with a reason.
- Kill only the servers you started.

**Grade the wire and the glass separately.** For anything networked,
check the shared backend state and the screenshots. When they disagree,
that is the finding. Correct on the wire and blank on the glass is a
rendering bug. Correct on the glass and absent from the wire means the
client is faking it. A nine-host multiplayer matrix found two genuine
product bugs against eleven harness faults, and six of those faults made a
working app look broken. Budget for that ratio: most of what a new rig
reports at first is the rig.

**Calibrate thresholds; never copy them.** A clipping threshold of 0.010
copied from a sibling app called three correctly rendered headings clipped
on every frame, because this app's gutter sat at x = 0.0099 to 0.0116 on
that iPad. Calibrate against a real capture from the device that will be
judged, and record the calibration next to the constant.

**Layout grading rules** (`devharness.edge_clips()` and `measure()`):

- A cut at the left edge is a defect. A cut at the right edge, or an
  ellipsis, is a scroll peek.
- Large display type is excluded by height.
- Prose lines are held to 80 characters.

**Control experiments beat correlation.** When a symptom survives three
targeted fixes, stop fixing and build the control that halves the
hypothesis space. Serving the same content from localhost through a URL
override exonerates the file, the network and the server in one run. A
nondeterministic fault needs repeated trials per arm, and paired arms,
not one run each.

## 10. Verify the artifact, never the build

A build step reports what the toolchain did. Only the device reports what
a person will run.

- **`| tail` on `xcodebuild` once hid a `BUILD FAILED`.** The pipeline's
  exit status is the tail's. Always grep for the verdict:
  `xcodebuild ... 2>&1 | grep -E "^e: |error: |BUILD SUCCEEDED|BUILD FAILED"`.
- **A stale build on one device explains symptoms it did not cause.** An
  Apple TV sat three builds behind an iPad through an entire SharePlay
  debugging session. After every install, read the version back off the
  device (`xcrun devicectl device info apps`, `adb shell dumpsys package`).
- **A successful install is not a successful launch.** Installs work on a
  sleeping Apple TV and on a locked iPhone. Launches do not.
- **Test the build folks will get.** Play rejected a release because R8
  stripped a constructor that only the minified build lost. Debug never
  minifies, so every debug install looked perfect.

## 11. When a surface cannot be driven

Some surfaces are closed. An iMessage extension lives inside Messages:
`simctl` has no tap primitive, and XCUITest drives only your own app. The
first response was a script that staged a simulator and left four
screenshots to a person. That made the one surface with no automation also
the one surface with no observable output.

**Build a harness app that hosts the real view types.** A debug-only
target compiles the same view files (not copies) and renders any screen
chosen by an environment variable, at exact device size. That gives
repeatable captures, store screenshots and a regression signal from the
real interface. It must not fake the surrounding chrome. A composited fake
conversation is a picture of an app that does not exist: fine as a mock,
unacceptable as evidence.

**Ship an in-app self-audit** for surfaces no outside instrument reaches
cheaply. Archive Watch's tvOS app, launched with an audit door, walks its
own screens and asserts 44 things on the device: each query returns rows,
each button routes somewhere, each filter changes results. Pair it with a
Mac-side twin that runs the same shared-code checks against live data, so
the audit never waits for a device to be awake. It catches create paths
with no inverse (a create with no delete), and parity that never returned
to the platform it started on.

**On a device with no instruments, the app becomes the instrument.** A
retail Samsung television has no shell, no log and no screenshot. The
answer was a diagnostics overlay opened by a key sequence
(`docs/DEVICE-HARNESSES.md`, web TV section).

**Some things stay with a person.** Passcodes and passwords are never
typed by an agent, whoever offers them. System call interfaces between two
Apple IDs, restoring picture-in-picture, and store review outcomes are on
the owner's list, and the run says so. A demo video for a store reviewer is
scripted and recorded, never a live drive of someone's account.

## 12. Look at the output

Rendering real content is a content audit. The store screenshots for a
trivia app rendered five real questions and showed that four shared one
template, two of them word for word. Measuring found the pack was 57.8%
one question shape against 9.5% in the corpus: the selection used
`ORDER BY id LIMIT N`, and ids cluster by the generator that produced
them. Every round was mostly one puzzle, and a screenshot found it.

Look at the output. Not the assertion about the output.

## 13. Audit ledgers are the work queue

Start one from `docs/templates/DEVICE-AUDIT-LEDGER-template.md`.

A long device campaign keeps a ledger per device family (Archive Watch
kept one each for tvOS, the iPhone 12, Android TV and Roku). The shape
that worked:

- Findings in tiers: **T1** needs the device, **T2** is a code fix, **T3**
  needs the owner.
- Every SKIP carries its reason.
- Counts at the end of each pass (pass, fail, skip).
- A separate list of things only the owner can judge by eye.

Before planning any device work, read the ledger, the runbook in
`docs/DEVICE-HARNESSES.md`, and the tools' own docstrings. Most device
problems here have been solved once already, and the fastest fix is the
one someone wrote down.

## 14. Checklist for a new app

1. Doors on every platform from the first screen, including skip
   onboarding, mute and a time bound.
2. `tools/hook_coverage.py` shows every surface reachable.
3. A bench manifest with a role on every device, and your own phone as
   never-touch.
4. `app_config.py` filled in, with anchor words from your real interface.
5. Thresholds calibrated on a real capture from a real device.
6. One lease per run, held for the whole run.
7. Teardown verified by the device.
8. A test that proves each checker can fail.
9. The wire and the glass graded separately for anything networked.
10. Store submission wired the same way (`docs/APPLE-SUBMISSION-CLI.md`).

Start with one door and one device.
