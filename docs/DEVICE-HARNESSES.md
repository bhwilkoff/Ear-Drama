# Device harnesses, platform by platform

Every platform lies to a test in its own way. A sleeping Apple TV hands
back a black screenshot that looks like a dark scene. A Roku answers 200
to a key name it does not know and does nothing. An Android TV screenshot
of a playing film is black, because the video plane is never composited
into it. Each of those cost Archive Watch or a sibling app at least one
wrong conclusion before it was written down.

I want the next person at the bench to start from what we learned, not
from the device's first lie.

**Each platform has its own tools and its own traps.**

This page is the reference catalog: for each platform, the tools in
`tools/`, the exact commands, and the traps. The method behind it (the
ladder, the bench and its roles, leases, leaving the room as you found
it, and how to judge a verdict) is in `docs/AUTONOMOUS-FLEET-TESTING.md`.
Read that first if you are setting up a bench. Every command below assumes
the repository root as the working directory.

| Platform | Runner | Evidence | The trap to know first |
|---|---|---|---|
| Apple TV | `atv_run.py`, `atv_scenario.py` | screenshots + OCR, a diagnostics file, pyatv power state | a sleeping TV returns a valid black PNG |
| iPhone, iPad | `ios_run.py`, `ios_scenario.py` | screenshots + OCR, deep links, XCUITest for taps | a locked phone installs and refuses to launch |
| Mac | `mac_run.py` | one window by id, OCR | never capture a region or the screen |
| Android phone | `adb_run.py` | screenshots + OCR, uiautomator tree | adb trust expires in seven days |
| Google TV, Fire TV | `gtv_scenario.py`, `adb_run.py` | the focus tree, OCR, logcat | `KEYCODE_ENTER` activates, `DPAD_CENTER` does not |
| Roku | `roku_run.py` and friends | ECP queries, the 8085 console, dev-channel screenshots | ECP must be Permissive |
| Web TV, Tizen, webOS | `tv_glass.mjs` and friends | headless Chrome at a true 1920x1080 | a laptop cannot open a TV-sized viewport |
| Web | `web_run.py` | 375px and 1440px captures | test your working tree, not production |
| Windows | `win_run.py`, `winbox.py` | a real box over SSH, CI as the gate | SSH lands in an invisible session |

---

## The shared tools

These work the same on every platform. `docs/AUTONOMOUS-FLEET-TESTING.md`
section 4 walks through setting them up.

| Tool | What it does | Commands |
|---|---|---|
| `tools/bench.py` | Loads the bench manifest and enforces roles | `python3 tools/bench.py`, `check`, `get <name> <field>`, `role <name>` |
| `tools/devlease.py` | Cooperative leases in `~/.device-lease/` | `python3 tools/devlease.py` (status), `release-all` |
| `tools/qa_suite.py` | Walks the bench, one lease per device, one summary | `--devices a,b`, `--full`, `--scenarios x,y`, `--owner-ok`, `--lease-wait N` |
| `tools/devharness.py` | OCR, grading, `capture_fresh()`, `edge_clips()`, `measure()`, `qa_dir()` | imported by every runner |
| `tools/devreset.py` | Stops the app on a device (verified) and labels the glass with what is under test | `reset("pixel")`, `label("pixel", "...")` |
| `tools/hook_coverage.py` | Which surfaces each platform's doors can reach | `python3 tools/hook_coverage.py` |
| `tools/ScreenOCR/main.swift` | Vision OCR: `allText` with `x, y, w, h`, `captionRegion`, `centerLuma {mean, stddev}` | built to `build/bin/screenocr` on first use |
| `tools/mac_window_shot.swift` | `winshot`: one window of one app | built to `build/bin/winshot` on first use |
| `tools/dev_cleanup.sh` | Reports stray local processes; `--stop` ends them; `volume-guard -- <cmd>` restores volume | |

ScreenOCR reports coordinates with a bottom-left origin (Vision's
convention). Flip `y` before comparing against a top-left rectangle, or
you will keep the wrong half of the screen.

---

## Apple TV

The Apple TV is where blind iteration is most expensive. There is no
debugger in the living room, and the device lies in more ways than any
other on the bench.

### Pairing

Pair through Xcode, not the command line.

1. On the TV, open **Settings, General, Remote Devices** and leave that
   screen open.
2. In Xcode 26, open **Xcode, Open Developer Tool, Device Hub**, press
   **+**, choose **Pair Nearby Device**, then the **Apple TV** tab.
3. Select the TV, press Next, and type the six-digit code it shows.

`xcrun devicectl manage pair` cannot start this. It answers "The specified
device was not found" for a TV that is not already on the Remote Devices
screen. TVs advertise as `_remotepairing._tcp`, which is how you confirm
the Mac can see one.

Once paired, a TV reads `available (paired)` with `tunnelState:
disconnected` until something talks to it. **Address a TV by UDID, never
by name** (a name can match "multiple devices"), and allow a long timeout
on the first call, which is what opens the tunnel.

If a TV was never in your provisioning profile, installs fail with
`MIInstallerErrorDomain 13`. Build once against it and the profile is
regenerated:

```bash
xcodebuild ... -destination id=<UDID> -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration build
```

### When the TVs vanish

**`CoreDeviceError 4016` on every TV means the Mac has lost the TVs.** The symptom is `tunnel unavailable, transport
None` while the TVs are awake and still advertising. Re-pairing, rebooting
the TV through devicectl and restarting CoreDeviceService did not help.
Restarting the Mac did, first time. After a macOS update, the first tvOS
build may fail until you run
`xcodebuild -downloadComponent MetalToolchain`.

If captures fail with `CoreDeviceError 3` on one box while others work,
switch to another TV and come back to that one later.

### devicectl recipes

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer   # only for a beta Xcode
xcrun devicectl list devices
xcrun devicectl device install app --device <UDID> path/to/App.app
xcrun devicectl device info apps --device <UDID>                       # read the version back
xcrun devicectl device process launch --device <UDID> --terminate-existing \
  -e '{"APP_START_TAB":"home","APP_MUTE":"1"}' <bundle-id>
xcrun devicectl device process launch --device <UDID> --payload-url '<url>' <bundle-id>
xcrun devicectl device capture screenshot --device <UDID> --destination out.png
xcrun devicectl device info processes --device <UDID>
xcrun devicectl device process terminate --device <UDID> --pid <pid>
```

Every one of these has a trap:

- **Launch environment is JSON.** The `KEY=VALUE` form fails with
  `NSCocoaErrorDomain 3840`.
- **`DEVELOPER_DIR` must be passed into each subprocess.** A plain copy of
  `os.environ` does not carry it if the parent shell never exported it.
  `app_config.DEVELOPER_DIR` handles this.
- **The screenshot verb is `capture screenshot` and the path goes after
  `--destination`.** A bare path prints usage and saves nothing.
- **`process terminate` takes `--pid`.** Given a bundle id it prints its
  usage text and exits, which looks like output and is not success.
- **`info processes` prints executable paths, padded with trailing
  spaces.** A grep for the bundle id never matches, and a grep anchored
  with `$` never matches either. Both gave a false all-clear, including in
  this template's own `devreset.py` before the port. Match the exact
  executable, allow the padding, and exclude `PlugIns/` (a Top Shelf or
  widget extension is launched by the system and is not yours to kill).
  `apple_device.app_pids()` does this.

### Wake, power and presses

**`devicectl` has no wake verb.** Installs work while the TV sleeps;
launches fail with "System is asleep, foreground app launch forbidden."
Wake goes through pyatv's Companion protocol (`~/.pyatv-venv`, Python
3.12; see the setup walkthrough).

- **Ask for power state before every launch, press and capture.** Never
  infer it from pixels. `atv_shot.sh` exits 3 without capturing when the
  TV reports Off.
- **Wake by polling.** `turn_on` only sends a request. A launch during the
  doze window comes up backgrounded: alive, and not in front.
- **If the launch works but every capture is black,** the television
  itself is off or on another input. The Apple TV cannot fix that; pyatv
  can only send a CEC request.
- **Warm every press.** A fresh single-command Companion connection drops
  its press. Read `power_state` on the same connection first, and never
  press while the TV is asleep. Presses do not reset the TV's sleep timer.
- **One press can block captures for 45 to 60 seconds.** The failed
  capture prints a connection blob and no error line. Reach a surface
  that needs several presses with a door instead.
- **Ask before waking a television in someone's room,** and never wake an
  `owner-watches` device without `--owner-ok`.

```bash
python3 tools/apple_device.py power --device atv       # on, off or unknown
python3 tools/apple_device.py wake --device atv        # polled
python3 tools/apple_device.py processes --device atv
python3 tools/apple_device.py teardown --device atv    # leave it as found
python3 tools/apple_device.py off --device atv
```

### Alive is not frontmost

`apple_device.launch_guarded()` runs this sequence on every launch:

1. Wake, polled.
2. Probe one frame. If it shows the tvOS home screen (`TVOS_HOME_RX`),
   bring the app forward with pyatv `launch_app=`, which keeps its launch
   environment. Only if that fails, relaunch once. An unknown probe is
   recorded as unknown, never as fine.
3. Death probes at 0, 15 and 30 seconds. About 2 launches in 10 die
   silently in the first seconds, around the screenshot daemon being
   killed by the system for memory. One relaunch keeps the scenario about
   the app. A second death reboots the device, and only on a device with
   role `test`, `floor` or `os-control`.

A whole "this category is broken" finding once dissolved into a
backgrounded launch.

### Console or screenshots, never both

Two devicectl sessions kill the console stream, and killing the console
kills the app. So:

- **With `--console`** you get NSLog, exception text and the crash tail,
  and no screenshots. Use it to hunt a crash.
- **Without it** you capture the screen, and diagnostics come from a
  file. With `APP_DIAG_FILE=1` the app appends `<epoch.millis> <message>`
  lines to `Library/Caches/appdiag.log` in its container
  (`app_config.DIAG_CONTAINER_PATH`).

**Pull the diagnostics file before any relaunch,** because launching
truncates it. An exception never reaches that file, so a crash still needs
a console run.

A capture that succeeds can still be a lie: on one box, `capture
screenshot` failed with `com.apple.Mercury.error 1001` while the app was
rendering and succeeded, with a black frame, while the panel slept.

### Capture quirks

- **The Apple TV HD sometimes captures at 1280x720,** which is the
  top-left crop of 1080p and looks like a layout blowup. Check the width
  before you call it one. Record quirks like this in the bench manifest.
- **4K captures pressure the screenshot daemon.** `atv_run.py` shoots
  every 4 seconds rather than faster. After roughly 80 capture runs the
  daemon degrades (timeouts, then thin frames). Reboot the device between
  long days.

### The Apple TV tools

```bash
python3 tools/atv_run.py --list
python3 tools/atv_run.py --scenario home
python3 tools/atv_run.py --device atv-control --scenario home      # the OS-control TV
python3 tools/atv_run.py --env APP_AUTOPLAY=1 --minutes 2 --expect "Home" --name adhoc
python3 tools/atv_run.py --scenario home --luma 28:2               # image gate: stddev 28 on 2 frames
python3 tools/atv_scenario.py --item <content-id> --minutes 6      # media playback
python3 tools/atv_scenario.py --item <id> --vtt path/or/url/en.vtt
python3 tools/atv_scenario.py --item <id> --expect-captions no     # the silent-film control
bash tools/atv_see.sh out.png [min_ocr_lines]                      # one checked frame
bash tools/atv_shot.sh atv out.png                                 # one fresh capture
bash tools/atv_teardown.sh --device atv [--keep-power]
python3 tools/atv_report.py [YYYY-MM-DD] [--md]                    # a day's runs in one table
```

- `atv_run.py` flags: `--device`, `--scenario`, `--list`, `--minutes`,
  `--env K=V`, `--expect`, `--luma`, `--name`, `--outdir`, `--owner-ok`,
  `--audible`, `--leave-running`, `--lease-wait`. A device leased
  elsewhere gives SKIP and exit 2.
- `atv_scenario.py` flags: `--device`, `--item`, `--title` (fill in
  `resolve_item()` first), `--minutes`, `--vtt`, `--expect-captions
  auto|yes|no`, `--env`, `--name`, `--outdir`, `--owner-ok`, `--audible`,
  `--no-reboot`, `--lease-wait`. It grades the app staying alive, the
  playhead advancing, no stalls, captions on the glass matching the
  caption file, a monotonic caption schedule, and blanks that are genuine
  gaps. Continuous audio is graded only with `--audible`.
- `atv_see.sh` checks, in order: power (through `atv_shot.sh`), freshness,
  OCR line count, and whether the frame is your app (`ATV_EXPECT`,
  default `APP_ANCHOR_RX`; `ATV_EXPECT=-` skips it). Exit 1 is blind, 2 is
  the wrong screen, 3 is a missing instrument.

### Depth audits on the Apple TV

Beyond one scenario per feature, these patterns found real bugs at scale
on a sibling trivia app:

- **Content-region luma gate.** OCR cannot see a missing image. A flat
  `centerLuma.stddev` where a photo belongs fails the scenario (`--luma`).
  Drive date-seeded random rows through the real loader, because one
  scenario proves the code path and random batches prove the content.
- **Tail-match legibility.** Render the longest prompts, options and
  explanations one at a time and assert the tail of the text reaches the
  glass. Character counts cannot see truncation; the tail is the tell.
- **Press storms.** Directional storms plus select and back on every
  surface, asserting the app stays alive on that surface and back
  dismisses correctly. A screenshot cannot show a focus strand.
- **Liveness audits report 429 and 5xx as UNVERIFIED,** with their own
  exit code, never dead. The first corpus-image sweep called 3,333
  rate-limited URLs dead. Use few workers, long backoff, and a
  content-type check (an HTML error page answers 200).
- **Chunk long background work** into slices of about eight minutes, each
  writing its own result file.

---

## Apple devices in general

### Compile the shipped file

For Apple-framework behavior no simulator can prove (asset shapes, HLS
loading, rotation logic that must survive a restart), write a standalone
`swiftc` harness that compiles the **shipped source file** plus a small
`main`, not a copy of it, and runs it against the real frameworks and
network. Archive Watch ran about 22 of these. They caught a `file://` HLS
master that never plays (only a real AVPlayer shows it) and a Top Shelf
rotation that could fill a shelf with filler while every assertion passed.

Two rules: the harness runs the shipped file, and platform-behavior probes
run **one shape per process**. State leaking between probes attributed one
shape's result to another and cost three shipped "fixes." Keep pure logic
in Foundation-only files so a harness can compile them.

### Offline, without cutting yourself off

To prove the Mac app works offline, deny the network to the app's process:

```bash
codesign --force --deep --sign - Copy.app        # ad-hoc copy with the App Sandbox entitlement stripped
sandbox-exec -p '(version 1)(allow default)(deny network*)' "Copy.app/Contents/MacOS/<Exe>"
```

`sandbox-exec` collides with the App Sandbox entitlement, so run a
re-signed copy without it, and prepare and assert in that same
configuration (the container moves). Always carry a negative control: a
fetch that must fail, or "it worked" is equally consistent with the
severing not having happened.

**Never turn off the Mac's Wi-Fi.** The default route is the agent's own
connection, and nothing is left to turn it back on.

On a physical iPhone or iPad there is no airplane mode from the Mac. The
proof there is structural (assert the URL handed to the player is
`file://`) plus `APP_FORCE_OFFLINE=1` for the screenshot of the offline
state.

---

## iPhone and iPad

### The arrangement

There is no remote wake on iOS and no Companion protocol to borrow. The
arrangement is physical: **passcode off, Auto-Lock never, on a charger.**

A locked device installs fine and refuses to launch
(`FBSOpenApplicationErrorDomain` error 7, "Locked"). That arrives as an
empty console and a black screenshot, which reads as several unrelated
failures and a couple of passes that tested nothing. `ios_run.py` names
the lock once. Opening the Device Hub screen viewer
(`open "devices://device/open?id=<UDID>"`) wakes an iPad to its passcode
prompt, which is as far as automation goes. The passcode is the owner's
step.

There is no press verb either. Scenarios reach a surface through doors or
a deep link (`--url`), never by pressing blind.

### The tools

```bash
python3 tools/ios_run.py --list
python3 tools/ios_run.py --device ipad --scenario home
python3 tools/ios_run.py --device iphone --env APP_START_TAB=search --expect "Search" --name adhoc
python3 tools/ios_run.py --device iphone --url 'appname://item/x' --expect "..."
python3 tools/ios_scenario.py doors                      # the door catalog
python3 tools/ios_scenario.py shot home                  # one surface, one frame
python3 tools/ios_scenario.py link item/<id>             # a deep link
python3 tools/ios_scenario.py sweep [--type-size accessibility3]
python3 tools/ios_scenario.py pip <item-id>              # picture-in-picture without a tap
python3 tools/ios_scenario.py judge build/qa/ios-...     # who clips, and where
python3 tools/ios_scenario.py measure build/qa/ios-... --width-pt 1366
```

- `ios_run.py` flags: `--device` (bench name or raw UDID, default `ipad`),
  `--scenario`, `--list`, `--minutes`, `--env`, `--url`, `--expect`,
  `--name`, `--owner-ok`, `--audible`, `--leave-running`, `--lease-wait`.
- `ios_scenario.py` takes `--device` (default `iphone`), `--type-size
  xxxLarge|accessibility2|accessibility3`, `--max-chars` (default 80),
  `--audible`, `--owner-ok`, `--lease-wait`. Fill in `SURFACES` and
  `SCHEME` at the top of the file.
- **Picture-in-picture without a tap:** autoplay muted, launch
  `com.apple.Preferences` so PiP starts, relaunch your app without
  `--terminate-existing`, and difference two frames of the PiP window.
  Restoring PiP needs a tap and is not automated.
- **Judging clipping:** a left-edge cut is a defect, a right-edge cut is a
  scroll peek. `measure` holds prose to 80 characters a line.

### XCUITest is the tap tier

When a flow needs real taps, XCUITest on the real device is the tool. The
lessons from Archive Watch's iPhone audit:

- `isHittable` lies at the bottom edge of the screen.
- A Toggle is exposed as its whole row. Tap at about `dx 0.92`.
- The iOS 26 search tab replaces the tab bar, so visit it last.
- Scroll a lazy Form before waiting for an element in it.
- Collect labels first, then act on them.
- Judge by effect, never by existence.
- A Mac keyboard and trackpad attached to the iPad can drive input tests.

### The simulator QA sweep

`tools/qa-sweep.sh` is a reference implementation from a sibling trivia
app. The shape is the point: doors drive about 47 captures per platform,
crashes are detected by checking the pid `simctl` returned, captures go to
a durable path, and findings go into a rounds table. Replace its debug
hooks and screen list with your own. Keep the QA sweep separate from the
store-screenshot script (`tools/capture-screenshots.sh`): QA draws real
data, and store capture enforces its own rules.

The simulator is lenient about the filesystem, entitlements, sync,
AirPlay routes, speech models and store billing. Boot one simulator at a
time. `tools/test_ios_floor.py` and `tools/test_tvos_floor.py` hold the
deployment floors in CI.

---

## Mac

The Mac is the only platform where the app is not alone on the display,
so the capture is the app's own window, by window id, owned by exactly
the process under test.

```bash
python3 tools/mac_run.py --only home,search
python3 tools/mac_window_id.py                    # prints a window id, or exits 1 and says why
build/bin/winshot "<App Name>" "" out.png --min-width 600
build/bin/winshot pid:12345 "" out.png --skip-size 800x600 --id-only
```

- `winshot` takes an app name or `pid:N`, a title substring (`""` for the
  frontmost qualifying window), an output path, and `--min-width`,
  `--skip-size WxH`, `--id-only`. When it fails it says which half failed:
  no such app, or no matching window.
- **There is no fallback,** not to a region, not to the full screen, not
  to an interactive picker. A title-substring match once captured a
  terminal tab whose title held the same words as the app window.
- `mac_run.py` prefers the locally built app in `build/dd-mac/` over the
  copy in `/Applications`, so it grades what is about to ship. It holds
  the `mac` lease and quits the app when it is done.
- `tools/macapp.py`, `tools/mac-shotset.sh` and `tools/mac-screenshots.sh`
  all capture through `winshot` with an exact owner match. The shot list
  in `mac-shotset.sh` is yours to fill in.

---

## Android phone

```bash
python3 tools/adb_run.py --list
python3 tools/adb_run.py --device pixel --scenario home
python3 tools/adb_run.py --device pixel --extra appname_start_tab=search --expect "Settings" --name adhoc
python3 tools/adb_run.py --device pixel --link 'appname://item/x'
```

Flags: `--device` (bench name or raw serial, default `pixel`),
`--scenario`, `--list`, `--minutes`, `--extra k=v` (use `k:ez=true` for a
boolean), `--link`, `--expect`, `--name`, `--owner-ok`, `--audible`.

Before each run `adb_run.py` reads `mWakefulness`, the keyguard, stay-on
and the screen timeout, and warns when `adb_allowed_connection_time` is
not 0. At the end it force-stops the app and confirms with `pidof`.

The rules:

- **Connect before every adb call.** A network device's TLS debugging port
  rotates after sleep, and the connection drops between commands.
- **Use one adb binary** (`app_config.ADB`). Two adb servers of different
  versions fight over the same devices.
- **Keep trust alive:** `settings put global adb_allowed_connection_time
  0`, or trust silently lapses after seven days and the device looks
  switched off.
- **The owner enters the passcode once.** `svc power stayon true` and a
  long `screen_off_timeout` keep a secure keyguard from coming back. Check
  both settings before telling anyone the phone is locked. Asking twice
  for something the tools can prevent is a tool bug, and the agent never
  draws the pattern or types the passcode.
- **Install the debug build,** so the doors work.
- **Delete before every dump or capture,** and retry an empty tree once.
  A failed `uiautomator dump` otherwise serves a stale tree from an
  earlier session.
- **Tap by label, never by coordinates.** Capture all four player states,
  picture-in-picture included, and audit clickable elements that carry no
  label.
- **Real devices for verdicts.** An emulator has no Play Store, so it
  cannot see Play Billing, Play Integrity or a vendor skin. Before a
  release, run Firebase Test Lab Robo on physical devices:
  `tools/testlab-android.sh` (`--quick` for one device, `--apk <path>` to
  skip the build; needs `FIREBASE_PROJECT`). Two release builds that
  passed every local test were rejected for crashing; one physical Robo
  run produced the stack in four minutes.

---

## Google TV and Fire TV

On a TV, focus is the interaction model, and focus is invisible to a
screenshot. A screenshot once showed a perfectly rendered program guide
that could not be reached by remote at all. So the TV tools navigate by
the focus tree and assert where focus lands.

```bash
python3 tools/gtv_scenario.py rail_walk               # capture and OCR-assert every tab
python3 tools/gtv_scenario.py shot NAME
python3 tools/gtv_scenario.py focus                   # print the focused node
python3 tools/gtv_scenario.py keys DPAD_DOWN ENTER
python3 tools/gtv_scenario.py go "Settings"           # closed-loop focus walk
python3 tools/gtv_scenario.py --device firetv tab search
```

Verbs: `rail_walk`, `shot`, `focus`, `press`, `keys`, `longpress`,
`tree`, `launch`, `link`, `type`, `log`, `tab`, `go`, `select`, `ocr`.
Flags: `--device` (default `androidtv`), `--owner-ok`, `--audible`. Fill
in `RAIL_ORDER`, `RAIL_LABELS`, `PUSHED_ROUTES`, `TAB_EXPECT` and
`SAFE_BAND` at the top of the file. For a TLS-port device, add an
`mdns_prefix` to its bench entry so `gtv_scenario.py` can find the rotated
port through `adb mdns services`.

The rules:

- **Navigate by reading focus after every press.** Focus enters a nav rail
  at the vertically nearest item, so step counts mislabel screenshots.
- **Activate with `KEYCODE_ENTER`, not `KEYCODE_DPAD_CENTER`.** A Compose
  `tvFocusable` responds to Enter. Center looks exactly like a dead
  control, and it is the tool's fault.
- **`input tap` does nothing on the TV profile.** The D-pad is the only
  input.
- **Back from a tab root exits the app.** Press Back only after a pushed
  route.
- **Read `content-desc` as well as text.** A merged Compose node carries
  one joined label in `content-desc` and hides its children. Treat a low
  node count as a warning. Compose overlays drawn in their own window can
  be missing from the dump entirely; OCR the screenshot for those.
- **Judge overscan by the text, not the box.** A focused element is scaled
  about its center, so its bounds move outward, and `scaleWhenFocused`
  pushes edge rows into the overscan cut. The safe band at 1080p is about
  96 to 1824 by 54 to 1026 (5% a side).
- **`screencap` does not capture the video plane** on these chips. Prove
  playback by decoder frames, the transport clock, `dumpsys
  media_session` and `dumpsys audio`, never by pixels.
- **On Fire OS, launch with `am start -n`.** `monkey` reports success and
  never brings the app to the front.
- **Use the Google TV as the negative control for Fire-only faults.** If
  it fails on both, it is not about Fire OS.

More TV tools:

- `tools/verify_tv_focus.sh [surface...]` drives real surfaces with remote
  keycodes and asserts focus lands on real content (`TV_PKG`, `TV_ACT`,
  `SERIAL`).
- `tools/tv_screenshots.sh [outdir]` takes 1920x1080 store screenshots and
  checks the size with a real PNG parse.
- `tools/audit_fire_tv_gms.py` asserts the Amazon build has no Google Play
  Services, with a negative control that must fail.
- `tools/audit_fire_tv_manifest.py` asserts the Fire TV build still
  reaches Fire OS 7 (API 28).
- `tools/audit_tv_g6.py` checks 64-bit support and 16 KB page alignment.

---

## Roku

Roku gives four channels of evidence, and `tools/roku_run.py` wraps all of
them. The device comes from the bench (`--device`, default `roku`) or
`ROKU_HOST`. The developer password comes only from `ROKU_DEV_PASS` (user
`ROKU_DEV_USER`, default `rokudev`); there is no default password.

```bash
python3 tools/roku_run.py info                         # device-info, active app, ECP mode
python3 tools/roku_run.py zip                          # write the sideload zip
python3 tools/roku_run.py deploy --extra SRC:DEST      # sideload through the dev installer
python3 tools/roku_run.py launch --params 'contentId=x'
python3 tools/roku_run.py keys Down Down Select
python3 tools/roku_run.py type "search text"
python3 tools/roku_run.py shot NAME
python3 tools/roku_run.py log 30                       # the 8085 console for 30 s
python3 tools/roku_run.py playstate                    # /query/media-player, sampled 3 times
python3 tools/roku_playback_audit.py --ids ID1 ID2 [--watch 20] [--soak 300]
python3 tools/roku_playback_audit.py --ids-file build/qa/roku-sample.txt
python3 tools/roku_sweep.py [--only Home,Search] [--deeper]
python3 tools/roku_design_lint.py [--root roku/components] [--allow-missing]
```

The External Control Protocol (ECP, HTTP on port 8060) has its own rules:

- **ECP must be Permissive.** In limited mode `/keypress` returns 403
  while `/query/device-info` still answers, so a reachability check passes
  and every input is refused. On the device: Settings, System, Advanced
  system settings, Control by mobile apps, Network access, Permissive.
  `info` prints the mode.
- **Key names are a closed set.** Roku returns 200 for a name it does not
  know and does nothing. `roku_run.py` refuses unknown names.
- **The installer uses digest auth,** and its verdict is read only from
  its typed JSON messages. An empty or unparseable reply is UNVERIFIED.
- **If the installer refuses an "identical" package,** delete the channel
  and install fresh.
- **Screenshots capture only a sideloaded dev channel.** "Screenshot not
  ok" means nothing of yours is on screen. The video plane is always
  black.
- **The 8085 console only pushes.** It replays its backlog when you
  connect and drops on relaunch, so reconnect and mark where new output
  starts.
- **Press Home before `/launch`.** `/launch` on a running channel resumes
  it, so a data check would not be a cold start. Use `/input` for deep
  links into a running channel.
- **`/query/media-player` with an advancing position is the playback
  oracle.** Its values carry units ("ms"), and its error attribute is
  sticky. `roku_playback_audit.py` exits non-zero on any required failure,
  so it can gate a release. Pick a varied sample of content.
- **A deep link proves a screen renders; a Select sweep proves it is
  connected.** `roku_sweep.py` deep-links to each surface, presses its
  keys and reads the channel's trace lines. No trace is a finding. Fill in
  `SURFACES` and `TRACE_PREFIXES` first; an empty `SURFACES` fails.
- **Console markers unset means SKIP.** `roku_playback_audit.py` reports
  PASS, FAIL and SKIP separately.

The legacy floor teaches its own lessons. Archive Watch's Roku 2 XD on
Roku OS 9.1 rejected `continue for`, and `GetOSVersion()` itself is too
new for 9.1, so the guard written to protect old players was what broke
them. Ask whether a component exists, never the firmware version. Bound
texture decodes with `loadWidth` and `loadHeight`. On-device self-test
doors (a report, a layout check, a store check) should assert floors
rather than exact counts and put the registry back as they found it.
Never automate the signing key's `genkey`, and keep signing credentials
where the packaging tool looks for them. `roku_design_lint.py` exits 1
until a `roku/` folder exists, so a CI gate should pass `--allow-missing`.

---

## Web TV, Tizen and webOS

A laptop display is about 1512 CSS pixels wide, so a desktop Chrome window
cannot open a true 1920x1080 viewport. Every TV reading taken that way was
taken at three quarters of TV width. Headless Chrome has no display and
renders a real 1920x1080.

The four glass tools share `tools/_tv_cdp.mjs`, which uses the Chrome
DevTools Protocol (CDP): a fresh profile under `build/qa` each run,
device scale factor 1, real `Input.dispatchKeyEvent` presses, and Chrome
killed on every exit path. It refuses to run if something is already on
the DevTools port, because an old browser answers with its old page.

```bash
python3 -m http.server 8080                          # or python3 tools/devserve.py (no-cache, port 8099)
node tools/tv_glass.mjs '#/browse' 24                # a screenshot of every press
TV_PLANT=1 node tools/tv_reachability.mjs            # the planted control: must report 1 unreachable
node tools/tv_reachability.mjs                       # then the real run
node tools/tv_follow_focus.mjs                       # focus inside the overscan band after every press
TV_STRICT=1 node tools/tv_audit_sizes.mjs            # type and target floors
node tools/test_tv_focus.mjs                         # the real engine in a Node DOM shim
node tools/test_packaged_origin.mjs                  # the packaged file:// app
node tools/test_tv_ua.mjs                            # platform detection per vendor UA
```

Every glass tool reads `TV_URL` (default `http://127.0.0.1:8080/?tv=1`),
`TV_BASE`, `TV_PORT`, `TV_CHROME` and `TV_OUT`. Most also read
`TV_ROUTES` (a comma list of hash routes) and `TV_KEYS` (a comma list of
presses). The tools print a NOTE when the URL is not local, because
measuring production while you believe you are testing your edit is a
silent wrong answer. `devserve.py` exists because `http.server` sends no
cache headers and a service worker can shadow your edit for a whole
session.

The rules:

- **Press real keys.** Never call `focus()` or `click()` to navigate. A
  mouse can reach anything; a remote reaches only what the focus engine
  finds.
- **Reachability walks the real focus graph,** with nodes keyed by
  content. If nodes disappear during the walk, the route is NOT
  MEASURABLE. An unfinished walk proves reachability, never
  unreachability. An empty pool means the probe is broken. Every run needs
  the planted control, and the plant must sit in the gap between what the
  tool counts and what the engine can reach.
- **Check overscan on all four sides, and print the band.** The horizontal
  half of the band was once 0 to 1920 from the day it was written, so
  every earlier "0 outside" only covered top and bottom. Measure the text
  a focused element draws, not its container.
- **Size floors apply to the node that draws the text.** Every exemption
  in `tv_audit_sizes.mjs` needs a written reason.
- **Every `dvh` or container-query value needs a fallback.**
- **A focused `<select>` owns Up and Down,** and `tabindex="-1"` is
  honored on every focusable row.
- **A packaged app must contain everything it loads.** Two scripts once
  returned 404 on every television for a week.
  `test_packaged_origin.mjs` requires every `js/` script `index.html`
  loads to be in the package, and reports a stale build stage as SKIP
  rather than judging it.
- **A `file://` origin needs a canonical data root,** and gates for
  anything that assumes http(s): inject the Cast SDK and send beacons only
  on http(s).
- **A tool-driven browser tab can be hidden,** and a hidden tab defers
  media, so `readyState` stays 0. Check `document.visibilityState` before
  calling playback broken.
- **The DOM shim needs universal methods.** `test_tv_focus.mjs` runs the
  real `tv.js` inside a hand-written Node DOM, because headless Chrome's
  virtual time distorts timers and `AbortSignal`. When the shim lacks a
  method, fix the shim (`:not()`, `getElementById`, `focusin` and
  `hashchange` were all added this way), and assert `tabindex="-1"` both
  ways.

`tools/tv_browser_tests.js` is the real-Chrome suite for what a shim
cannot prove: computed CSS, layout geometry, `<dialog>` semantics and
media elements. It reports progress per assertion and time-boxes the
player block, so an autoplay-blocked tab fails by name instead of hanging.

### Retail Tizen

A retail Samsung set closes `sdb shell` entirely: no shell, no log, no
screenshot. It CAN be inspected, which this section said otherwise until
Archive Watch proved it on 2026-10-03:

- **See inside the app with Chii.** Run `chii start -p 8080` on the Mac,
  build with `APP_TV_INSPECT=<mac-ip>:8080 bash tv/build-tv-packages.sh
  tizen`, install the `-debug.wgt`, launch it, then `node
  tools/tv_inspect.mjs "<js>"` reads anything in the page,
  `tools/tv_press.mjs down ok back` dispatches remote keys and prints what
  is focused and whether it sits inside the 5% overscan band, and
  `tools/tv_walk.mjs` walks every route by key presses. The debug package
  must declare its own `<tizen:content-security-policy>` naming the
  inspector host: a widget without one runs only its own scripts, and the
  set silently never requested the inspector. Keys dispatched this way
  prove the APP's handling; the platform's own key delivery is a separate
  fact a physical remote confirms.
- **Turn the set on over HDMI-CEC** from another box on the same chain
  (`atvremote ... --protocol companion turn_on` on an Apple TV). Wake-on-LAN
  did nothing from standby. Read power state from
  `http://<tv>:8001/api/v2/` (`"PowerState":"on"`).
- **The network remote** (ports 8001/8002) never answered on Archive
  Watch's set, even with IP Remote on. Do not spend time on it; drive keys
  through the inspector.
- Without the inspector, the app is the instrument: a diagnostics overlay
  opened by a key sequence, hosted on the video stage, because an open
  `<dialog>` sits in the top layer above everything else.

To re-enter Developer Mode, open Apps and type 1 2 3 4 5. The developer
certificate is tied to the TV's DUID, so a second test set means
re-issuing it. Store and SDK details are in `docs/TV-PLATFORMS.md` and
`docs/store/tizen-submission.md`.

---

## Web

```bash
python3 tools/web_run.py --only home,search
python3 tools/web_run.py --base https://example.com     # a deployed site, on purpose
```

`web_run.py` captures every route at 375px and 1440px, because a layout
that is fine wide and clipped narrow is the failure the density rule
exists to catch. It defaults to `WEB_URL` (your local server) and deletes
each target file before the shot. It takes no lease: the browser is a
private headless instance. `tools/webdrive.py` is a stdlib-only CDP
driver for typing and clicking when a flow needs input.

---

## Windows

There is no free Windows VM, and the development machine is an arm64 Mac.
Two rigs cover that, and both are needed.

1. **Headless Skia on the Mac.** `Avalonia.Headless` renders the real
   interface to PNG in-process on any OS. That is what makes a $0 pipeline
   real.
2. **`windows-latest` CI is the actual box.** Mica, window chrome, DPAPI,
   Win32 interop and native media libraries are Windows-only. Gate on CI,
   and capture visual baselines on Windows. The full doctrine is in
   `docs/windows/WINDOWS-PLAYBOOK.md`.

A real Windows machine on the network speeds up iteration. CI stays the
gate.

```bash
export APP_WIN_HOST=user@<host>        # key auth only; APP_WIN_KEY defaults to ~/.ssh/app_win
python3 tools/winbox.py --keygen
python3 tools/winbox.py --check
python3 tools/winbox.py --deploy       # publish self-contained on the Mac, copy it over
python3 tools/winbox.py --shot out.png
python3 tools/win_run.py --only home,library
```

- **SSH lands in session 0,** the services session: a phantom 1024x768
  desktop, `MainWindowHandle == 0`, and nothing you launch appears on the
  real screen. `winbox.py` launches through a scheduled task with an
  `Interactive` principal, which runs in the signed-in person's session.
- **The app is self-contained,** so the box needs no .NET SDK. The Windows
  machine is a device, not a build server.
- **A dark frame is a measurement,** reported as percent black and mean
  luma, never as "the screen was off."
- **`CopyPixels` returns each bitmap's native format.** A captured frame is
  RGBA, a decoded PNG is BGRA. Normalize both through one decode path, or
  the visual gate reports drift that does not exist.

---

## Media and playback

`docs/MEDIA-PLAYBACK.md` holds the streaming doctrine. The instruments:

- **Ship gates run under adverse conditions:** a Release build and a
  throttled network. `python3 tools/throttled_range_server.py --port 8899
  --mbps 10 --dir <folder>` serves a local copy at 10 Mbps. Python's stock
  `http.server` ignores Range requests and feeds players garbage.
- **Judge a broadcast from the server's recording, not the app's report.**
  Record, then `ffprobe` the streams and pull a frame to look at. Run
  `ffmpeg -i rec.mp4 -af volumedetect -f null -` without `-v error`,
  because `volumedetect` prints at info level and `-v error` hides the
  answer.
- **Choose test content by measured audio.** A silent film cannot tell you
  whether audio works, and a metadata flag is not a measurement.
- **Measure A/V sync with a marker:** a flash plus a tone, the median of
  about 20 pairings, after first confirming the recording is the content
  you meant.
- **Verify with the strict consumer.** Real AVFoundation on a macOS runner
  catches what a lenient byte probe passes.
- **Diff your publisher against a reference** through a tiny recording
  proxy.
- **Encode with the shipped code of one platform and decode with another's**
  (shipped Swift, shipped JavaScript). Verify an encoder against an
  independent reference, never against itself, and decode the rendered
  screenshot.

Start with the platform your people use most.
