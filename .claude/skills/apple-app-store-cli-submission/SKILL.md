---
name: apple-app-store-cli-submission
description: "The version / release / review half of an Apple App Store ship, from the CLI, behind the generic `cloud-appstore-submission` skill (consult that first for build, sign, upload). Covers tools/asc_release.py (status + ship across IOS / TV_OS / MAC_OS; waits for VALID; refuses to submit without What's New; the three-call reviewSubmissions flow), appstore-submit.yml modes, tools/asc_submit.py (screenshot sets, --audit, --platform), the local submit-appstore.sh pathway, the ITMS-90111 / ITMS-90301 checks, per-platform SDK downloads, release type, and Mac screenshots. Invoke when creating an App Store version, attaching a build, submitting or resubmitting for review, auditing a version, uploading screenshot sets, or when App Review rejects a build for SDK/Xcode/signing reasons."
---

# Apple App Store submission (CLI): version, release, review

Runbooks: `docs/APPLE-SUBMISSION-CLI.md` (this half) and `docs/CLOUD-SUBMISSION.md` (build, sign, upload). All Apple platforms share ONE App Store Connect record and ONE bundle id (`APPLE_BUNDLE_ID` in `tools/app_config.py`, or the `APP_BUNDLE` repo variable). Android is a separate path (`play-cli-submission`).

**The full ship is CLI. Nobody opens App Store Connect to press Submit, and you never ask the owner to.**

## The release

```
# bump AppVersion.xcconfig (both numbers), push, then ONE dispatch:
gh workflow run appstore-build.yml -f platform=all -f notes="What's new"
```

`appstore-build.yml` uploads, waits for the build to go VALID, and runs `asc_release.py ship --submit`. When it uploaded without submitting (no notes, or `submit=false`):

```
gh workflow run appstore-submit.yml -f mode=ship -f release_notes="..." -f submit=true
gh workflow run appstore-submit.yml -f mode=status          # verify from Apple, not the tool
gh workflow run appstore-submit.yml -f mode=audit -f platform=ios
```

## tools/asc_release.py

```
asc_release.py status [--build N]
asc_release.py ship [--platform all|ios|tvos|mac] [--version X.Y.Z] [--build N]
                    [--notes T | --notes-file F] [--locale en-US]
                    [--release-type AFTER_APPROVAL|MANUAL|SCHEDULED]
                    [--wait-build-minutes 40] [--submit] [--dry-run]
```

- **Every platform** in `APP_STORE_PLATFORMS` (default `tvos,ios,mac` = `TV_OS`, `IOS`, `MAC_OS`). One version and one reviewSubmission PER platform.
- **status** is read-only and exits 0 whenever it read everything (reporters never fail). "Not uploaded" / "PROCESSING" print as `::warning::`. A build missing from `v1/builds` is looked up on `buildUploads`, which carries Apple's post-upload errors. A version in review is judged by the build it carries.
- **ship**, per platform: reuse an editable version and **rename** it to the target string, or create one `AFTER_APPROVAL`; skip (warning, not failure) a platform already waiting for review; `--wait-build-minutes` polls until THIS build is `VALID` on THIS platform; attach (filtered by `preReleaseVersion.platform`); set What's New; set release type; `--submit` runs the three-call flow. A platform that fails stops before submitting; exit 1 only if one failed.
- **`--submit` with no notes is refused before any network call.** Apple refuses review without whatsNew, but only after versions are created and builds attached.
- Version string and build number come from `AppVersion.xcconfig`. Pass `--build` when a later commit moved the repo's number past the uploaded build.
- Errors print every `meta.associatedErrors` entry; that is where Apple's reason lives.

## appstore-submit.yml modes

Pure REST on `ubuntu-latest`; the three `ASC_KEY_*` secrets only.

| mode | runs | platforms |
|---|---|---|
| `status` (default) | `asc_release.py status` | all |
| `ship` | status, `asc_release.py ship --wait-build-minutes 40`, status into the step summary | all or one |
| `audit` | `asc_submit.py --audit` (exits non-zero on a blocker) | one |
| `list` | `asc_submit.py --list` | one |
| `upload` | `asc_submit.py --set ...` from `sets` (+ `replace`, `dry_run`) | one |

`ship` takes `version`, `build`, `release_notes`, `release_type`, `submit` (default **false** here: a bare ship only prepares), `dry_run`. Inputs reach scripts as env; optional flags are `if ... fi`.

## tools/asc_submit.py

Screenshot sets and the audit, for ONE `--platform ios|tvos|mac` (default ios). `--set DISPLAY_TYPE=DIR` (+ `--replace`; without it a non-empty set is skipped); `--audit` (attached build, localisation fields, every screenshot set's delivery state and per-asset errors, age rating, review contact, export compliance, whether an open review submission has items); `--list`, `--status`; `--release-type` alone is legal on a version already in review. Its `--create-version` / `--attach-build` / `--submit` remain for a one-platform fix-up; ship with `asc_release.py`.

## Why submitting looked impossible

`POST /v1/appStoreVersionSubmissions` answers `403 ... does not allow 'CREATE'. Allowed operation is: DELETE`. Deprecated, and the message never says so. Submitting is:

1. `POST /v1/reviewSubmissions` (platform + app)
2. `POST /v1/reviewSubmissionItems` (the appStoreVersion as an item)
3. `PATCH /v1/reviewSubmissions/{id}` with `submitted: true`

## The traps (all build and archive GREEN)

1. **A TestFlight upload does not create an App Store version.** Separate records. `ship` opens one.
2. **Hardcoding `filter[platform]=IOS` ships one app of three** and reports success.
3. **Builds must be filtered by `preReleaseVersion.platform`.** One number exists once per platform; unfiltered, a random platform's build is attached and Connect says "different platform than the version".
4. **A wrong version string can't be deleted** (`409 Only the first version of any platform can be deleted`), and Connect accepts a string lower than the live one. Rename it while `PREPARE_FOR_SUBMISSION`.
5. **A new extension/app target needs its App ID registered.** `asc_profiles.py` registers it. Apple rejects `.` and `_` in a bundle id's *name*.
6. **An iMessage icon set needs `"platform": "ios"`** on its `universal` and `ios-marketing` entries, or actool silently drops them and emits no `MSMessagesExtensionStoreIconName`.
7. **`ASC_KEY_P8` is base64**, not raw PEM (`MalformedFraming`).
8. **An IAP product rides exactly ONE review submission.** Concurrent platform submissions starve each other; ship the product-carrying platform first.

## Release type

Versions are created **`AFTER_APPROVAL`**: an approved build waiting on a button is a silent stall. Release type is logistics, not reviewable content, so it changes even in `WAITING_FOR_REVIEW`: `asc_submit.py --platform ios --release-type MANUAL`.

## The local pathway (only on a RELEASED-macOS machine)

```
DEVELOPER_DIR=<released-Xcode>/Contents/Developer tools/submit-appstore.sh <mac|ios|tvos|all>
tools/asc_release.py ship --platform <p> --submit --notes-file whats-new.txt --wait-build-minutes 40
```

Before a local build, check both post-upload rejections:
- **ITMS-90111 (Xcode floor, recurring).** Compare the latest released/RC Xcode on developer.apple.com/news/releases with `xcodebuild -version`. A build ending in a lowercase letter is a beta.
- **ITMS-90301 (the build MACHINE is on a beta macOS).** A GA Xcode does not help. Check `sw_vers` or `BuildMachineOSBuild` in the archive's Info.plist. You cannot fix it by rebuilding on a beta box; use the cloud.

A fresh Xcode may need `xcodebuild -downloadComponent MetalToolchain` (apps with `.metal` shaders) and `xcodebuild -downloadPlatform iOS` / `tvOS` when "Any iOS Device" shows "not installed". Free ~25-30 GB first (DerivedData, old archives); never delete an Xcode app without the owner's OK.

## Mac screenshots

16:10, EXACTLY 1280x800 / 1440x900 / 2560x1600 / 2880x1800. Drive the app with the `APP_START_TAB` / `APP_START_ITEM` env hooks, capture the app's WINDOW by id (`tools/mac_window_shot.swift`, built to `build/bin/winshot`), never a screen region or full screen (both photograph whatever else is on screen), then frame to the exact size (`tools/mac-shotset.sh <app>`). Needs Screen Recording permission. Any build may produce screenshots.
