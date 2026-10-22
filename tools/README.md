# The tools

The docstring at the top of `apple_device.py` says: "Every function here
exists because the obvious one-liner lied at least once." That is true
of most of this folder. `devicectl` printed its usage text, which looked
like success. A screenshot of a sleeping Apple TV came back as a valid
black image. A workflow stayed green while publishing nothing for two
days. Each tool here is the one-liner, plus the check that would have
caught the lie.

This page says what each tool does, and which stage
(`docs/path/`) you will first reach for it in.

## Four habits every tool shares

- **Your app's identity lives in one file.** Bundle IDs, package names,
  the words that prove your app is on screen: all of it is in
  `app_config.py`, and every tool reads it from there. Adopting the
  tooling in a new app means editing that one file.
- **Nothing touches a device it was not given.** Real devices are listed
  in a bench file with roles, and the runners refuse the ones marked as
  somebody's own.
- **A tool that cannot see says so.** Pass, fail and skip are separate
  counts. A tool that could not read something reports that, instead of
  a zero or a pass.
- **Python standard library, plain shell, and Node with no packages**,
  wherever possible. Nothing to install before the first run. The
  exceptions (PyJWT for App Store Connect, pyatv for the Apple TV, Pillow
  for images) say so when they are missing.

Run any Python tool with `--help` to see its options.

## Start here

| Tool | What it does |
|---|---|
| `app_config.py` | The one file to edit: your app's IDs, launch doors, on-screen vocabulary, and tool paths. |
| `bench.example.json` | A sample device bench. Copy it to `bench.json` (ignored by git) or `~/.device-bench.json`. |
| `bench.py` | Loads the bench and enforces device roles. `python3 tools/bench.py check` validates yours. |

## Stage 04: Seeing it work

The method is in `docs/AUTONOMOUS-FLEET-TESTING.md`; the per-platform
recipes are in `docs/DEVICE-HARNESSES.md`.

**The shared spine**

| Tool | What it does |
|---|---|
| `qa_suite.py` | Runs the whole fleet: walks the bench, holds each device's lease, calls each platform's runner, and prints pass, fail and skip. |
| `devharness.py` | What every runner shares: fresh-file screenshot capture, OCR, clipping checks, and the report format. |
| `devlease.py` | One agent session holds a device for a whole run, so two sessions never drive the same TV. |
| `devreset.py` | Puts devices back the way the run found them, and checks that it did. |
| `hook_coverage.py` | Reports which screens each app can be opened to directly by a launch door. A screen without one cannot be tested. |
| `apple_device.py` | Apple device plumbing: verified app termination, TV power, wake, warmed remote presses, guarded launch. |
| `dev_cleanup.sh` | Finds development processes left running on your Mac; `volume-guard` restores the system volume after an audible run. |
| `ScreenOCR/main.swift` | Reads the text on a screenshot with Apple's Vision framework. Built once into `build/bin/`. |
| `mac_window_shot.swift` | Captures exactly one window of exactly your app. Never the whole screen. |
| `throttled_range_server.py` | A local file server with a bandwidth cap, for testing playback on a slow network. |

**Per platform**

| Platform | Tools |
|---|---|
| Apple TV | `atv_run.py` (scenario runner), `atv_scenario.py` (playback runner for media apps), `atv_shot.sh` (screenshot that refuses stale files and sleeping TVs), `atv_see.sh` (screenshot plus OCR gate), `atv_teardown.sh` (leave nothing running, TV back off), `atv_report.py` (one table for a day of runs), `measure_start_times.sh` (time to first frame) |
| iPhone and iPad | `ios_run.py` (scenario runner), `ios_scenario.py` (screen sweeps through launch doors, clipping and line-length checks) |
| Mac | `mac_run.py` (scenario runner), `macapp.py` (launch and capture the Mac app), `mac_window_id.py` (find your app's window) |
| Android phone | `adb_run.py` (scenario runner), `testlab-android.sh` (Firebase Test Lab on real devices) |
| Google TV and Fire TV | `gtv_scenario.py` (navigates by reading the focus tree after every press), `verify_tv_focus.sh` (focus lands on real content) |
| Roku | `roku_run.py` (deploy, keys, screenshots, console), `roku_playback_audit.py` (does it actually play), `roku_sweep.py` (press Select on every screen), `roku_design_lint.py` (the design rules as a lint) |
| Web | `web_run.py` (every route at 375 and 1440 pixels wide), `webdrive.py` (drives Chrome for interactive flows), `devserve.py` (a no-cache local server) |
| TV web (LG, Samsung) | `tv_glass.mjs` (a true 1920 by 1080 screen with real key presses), `tv_reachability.mjs` (can every control be reached with a remote), `tv_follow_focus.mjs` (does focus stay on screen), `tv_audit_sizes.mjs` (are targets big enough at ten feet), `tv_browser_tests.js` (in-browser focus checks), `_tv_cdp.mjs` (their shared Chrome driver), `test_tv_compat.py` (the TV code stays inside Chromium 85, Samsung's 2022 floor; the package build refuses otherwise). On a retail Samsung set, through the Chii inspector: `tv_inspect.mjs` (read anything in the page), `tv_press.mjs` (press remote keys, report focus), `tv_walk.mjs` (walk every route), `tv_chii.mjs` (their shared connection) |
| Windows | `win_run.py` (scenario runner), `winbox.py` (drives a Windows machine over SSH) |

## Stage 05: Shipping

The runbooks are `docs/CLOUD-SUBMISSION.md` (build, sign, upload) and
`docs/APPLE-SUBMISSION-CLI.md` (version, release, review).

| Tool | What it does |
|---|---|
| `asc_release.py` | Ships every Apple platform: creates or renames the version, waits for the build, and submits for review. Refuses to submit without release notes. |
| `asc_submit.py` | Uploads App Store screenshot sets and audits a version before review. |
| `asc_asset_library.py`, `asc_stage_assets.py` | The Asset Library API, the only route for iPhone Duo screenshots and the product page header and search results assets: upload, then place a batch on a new version in order. |
| `asc.py` | A small App Store Connect API client the other tools share. |
| `asc_build_exists.py` | Refuses to archive a build number that was already uploaded. |
| `asc_certs.py`, `asc_profiles.py`, `ci_make_signing_p12.py` | Signing certificates and provisioning profiles through the API, including the one-time CI signing setup. |
| `asc_prune_certs.py` | Revokes the temporary certificates each cloud build creates, before Apple's limit is reached. |
| `submit-appstore.sh` | Builds and uploads one Apple platform from your own Mac. |
| `test_ios_floor.py`, `test_tvos_floor.py` | Refuse a deployment target above the floor you chose (stage 03). |
| `submit-play.sh`, `play-publish.py`, `play_promote.py` | Build, upload, and promote Android releases on Google Play. |
| `test_version_contract.py` | Holds Android's version name to `AppVersion.xcconfig`, the one version number. |
| `set_app_identity.py`, `test_app_identity.py` | Give the app its own identifier and name on every platform at once (stage 03), and fail the Android build while a copy of the template still says `com.example.appname`. |
| `audit_fire_tv_manifest.py`, `audit_fire_tv_gms.py` | The Fire TV build reaches older Fire OS and has no Google Play Services. |
| `audit_tv_g6.py` | Google's TV requirement for 64-bit and 16 KB page alignment. |
| `stamp_msix_version.py` | Stamps the Windows package version from `AppVersion.xcconfig`. |
| `capture-screenshots.sh`, `qa-sweep.sh`, `mac-screenshots.sh`, `mac-shotset.sh`, `tv_screenshots.sh` | Store screenshots, driven to each screen by launch doors. The first two are worked examples from a trivia game: keep the shape, replace the screen list. |
| `make_tv_banner.py` | Renders the TV launcher banner at both required sizes. |
| `render-app-icon.py` | A worked example that renders a layered tvOS icon and Top Shelf art from one image. Set `APP_ICON_SOURCE`. |

## Stage 06: Keeping it running

| Tool | What it does |
|---|---|
| `pulse_collect.py` | Reads every channel the app has into `ops/pulse.json` (see `docs/PRODUCT-PULSE.md`). |
| `pulse_make_fixture.py` | Writes the synthetic reading `pulse/?fixture` draws. |
| `pulse_play_bucket_probe.py` | Lists what is really in the Play reports bucket, and when each file was written. Run it before calling a Play export broken. |
| `audit_workflow_health.py` | Finds workflows that are broken while reporting success. Never fails itself. |
| `report_workflow_health.py` | Carries the auditor's findings to one GitHub issue that closes itself when they clear. |
| `check_workflow_gates.py` | Static checks on every workflow: gated writers, a token wherever `gh` runs, reporters that cannot fail. |
| `retry_infra_failures.py` | Re-runs workflows that GitHub's runners never actually started. |
| `gh_retry.sh`, `gh_dispatch.sh` | Retry a `gh` command or a workflow dispatch through GitHub's brief outages. |
| `sqlite_publish_guard.py` | Refuses to publish a shared database that lost rows. |
| `catalog_delta.py` | Makes a data-mutating tool safe to run without holding a lock. |
| `ffmpeg_limits.py` | One place that decides how much of the machine ffmpeg may use. |

## Tests

Every `test_*` file runs with no devices and no network. The rule for
adding one: before you trust it, break the code on purpose and watch it
fail.

| Test | Holds |
|---|---|
| `test_workflow_health.py`, `test_workflow_health_gate.py` | The auditor never goes blind to a failure, and never cries wolf. |
| `test_pulse_collect.py`, `test_pulse_charts.mjs`, `test_pulse_render.mjs` | Pulse never draws a zero it did not read, and its charts mean what they show. |
| `test_home_screen_probe.py` | The Apple TV home-screen check says "I cannot tell" when it cannot. |
| `test_gtv_scenario.py`, `test_roku_run.py` | The Google TV and Roku runners parse what devices really return. |
| `test_web.sh` | Every web test in one command, plus a syntax check of every script and a brace count of every stylesheet. |
| `test_tv_focus.mjs`, `test_tv_ua.mjs`, `test_packaged_origin.mjs` | The TV web layer's focus engine, its detection, and its packaged build. |
| `test_us_english.py` | One spelling locale in every string a person reads, on every platform. Exceptions carry their reason. |
| `test_fire_tv_manifest.py`, `test_version_contract.py`, `test_ios_floor.py`, `test_tvos_floor.py` | The store gates above. |

## Maintaining the template

| Tool | What it does |
|---|---|
| `refresh-skills.sh` | Pulls updates for the vendored skills. Skills already in the template are never overwritten. |
| `install-android-skills.sh` | Installs the community Android skills globally. |

When you add a tool, add a row here in the same commit.
