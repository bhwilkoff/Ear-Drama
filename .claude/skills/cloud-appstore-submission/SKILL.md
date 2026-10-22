---
name: cloud-appstore-submission
description: "Use when building, signing, uploading or submitting any Apple App Store build (iOS / iPadOS / tvOS / macOS), especially from a dev Mac running a beta OS. The DEFAULT venue is a cloud CI runner (released macOS + GA Xcode) because a beta-OS/beta-Xcode dev box is rejected AFTER upload (ITMS-90301, ITMS-90111) while TestFlight still accepts it. Carries appstore-build.yml (Secrets.xcconfig gate, cert prune/revoke, duplicate-build refusal, floor tests, submit after VALID), manual .p12 signing (cloud/automatic signing fails for a team ASC API key), the CI secret set, the ES256 ASC-API JWT, the two cert gotchas (raw-PEM CSR, -legacy .p12 PBE), the certificate-cap trap, the floor-by-hardware rule, the compile-guard traps on the GA toolchain, and the bump-both-version-numbers rule. Triggers on App Store submission, ITMS-90301, ITMS-90111, appstore-build.yml, ASC API key, .p12 signing, \"maximum number of certificates\", \"beta OS can't submit\", cloud build, deployment target, App Review rejection SDK/Xcode."
---

# Cloud App Store Submission

Build, sign and upload an Apple App Store build **from CI**, then submit it, with no Xcode GUI and no App Store Connect UI. Runbooks: `docs/CLOUD-SUBMISSION.md` (build, sign, upload) and `docs/APPLE-SUBMISSION-CLI.md` (version, release, review). Pairs with `apple-app-store-cli-submission` (the version/review mechanics) and `store-submission-playbook` (listing, screenshots, review prep).

## When to invoke

- Archiving, signing, uploading or submitting any iOS, iPadOS, tvOS or macOS build
- App Review rejected a build for an SDK, Xcode-version or signing reason
- The dev Mac runs a beta macOS or beta Xcode and can't ship a release
- Setting up or debugging `appstore-build.yml` / `appstore-submit.yml`
- Choosing or raising a deployment target

## Rule 1: DEFAULT to the cloud; a beta-OS dev box can't ship a release

A locally built archive from a **beta macOS or beta Xcode** is rejected AFTER upload:
- **ITMS-90301**: "not accepting apps built with this version of the OS."
- **ITMS-90111** (recurring): the Xcode/SDK is below the current App Store floor. A build number ending in a lowercase letter (`27A5194q`) is a beta.

**TestFlight still accepts beta builds**, so testing is never blocked; only App Review is. Build on a GitHub runner with a released macOS + GA Xcode (free for public repos):

```
# bump AppVersion.xcconfig (BOTH numbers) and PUSH first; the runner builds the committed tree
gh workflow run appstore-build.yml -f platform=all -f notes="What's new"   # or ios | tvos | mac
```

**The runner label and Xcode glob are a moving target.** Bump `runs-on: macos-NN` and the `Xcode_NN.*` glob together when ITMS-90111 recurs.

## Rule 2: The workflow uploads AND submits

Upload is not shipping, and finishing the job is not the owner's job. Never tell anyone to open App Store Connect and press Submit. `appstore-build.yml`, in order:

1. Select a released Xcode (skips betas).
2. **Write `Secrets.xcconfig`** from repo secrets when `XCCONFIG_SECRETS` is set; **fail if any listed secret is empty**. Otherwise a missing key resolves to the literal `$(KEY)` and every cloud build silently ships without the feature. Prints lengths, never values.
3. Import the `.p12`s into a temp keychain (`set-key-partition-list`, or codesign hangs).
4. Install the ASC key + `tools/asc-credentials.env`.
5. **Prune** throwaway dev certs: `asc_prune_certs.py --apply --keep 2` (`continue-on-error`).
6. **Refuse a duplicate build number**: `asc_build_exists.py <ver> <build>` exits 1 in seconds instead of after a 30-minute archive (usual cause: dispatched beside a rejected push). Exits 0 when Apple is unreachable.
7. **Floors have not drifted**: `test_ios_floor.py`, `test_tvos_floor.py` (Rule 7).
8. Archive + sign + upload: `tools/submit-appstore.sh <platform>`.
9. **Revoke this run's cert**, `if: always()`: `asc_prune_certs.py --apply --keep 0` (safe only because the concurrency group admits one run).
10. **Submit**: with `submit=true` (the default) and non-blank `notes`, `asc_release.py ship --platform <p> --submit --notes-file <f> --wait-build-minutes 40`. Waits for THIS build to go VALID, then opens/renames the version, attaches, sets What's New, and runs the three-call reviewSubmissions flow, per platform.

No notes: uploads, then `::warning::` (Apple refuses review without What's New; a red X would read as a failed build). `submit=false`: upload only, with a warning; use it when a version in review must not be disturbed. Finish either with `gh workflow run appstore-submit.yml -f mode=ship -f release_notes=... -f submit=true`.

Inputs reach scripts as **env**, never pasted into the shell line (a quote in What's New closes the string; free text in a shell line is injection). Optional flags are `if ... fi`, never `[ -n x ] && ARGS+=(...)`, which returns 1 on empty input and fails a `bash -e` step when it is the last line.

Repo variables: `APP_BUNDLE` (else `app_config.APPLE_BUNDLE_ID`), `APP_STORE_PLATFORMS` (e.g. `ios,mac`; default all three).

## Rule 3: Manual .p12 signing (cloud/automatic signing fails for a team ASC API key)

Cloud-managed signing fails for a team-scoped ASC API key ("Cloud signing permission error"), but the same key can create certs and profiles over REST. So export is MANUAL: `asc_certs.py` (Apple Distribution + Mac Installer certs) + `asc_profiles.py` (a profile per embedded bundle id; registers a new App ID) + a manual `ExportOptions.plist`. On CI, the `.p12`s from secrets go into a temp keychain and `ASC_DIST_CERT_ID` pins the cert. Don't "simplify" to automatic.

## Rule 4: The CI secret set

Seven required: `APPLE_DIST_P12`, `APPLE_INSTALLER_P12` (base64 `.p12`s), `APPLE_P12_PASSWORD`, `APPLE_DIST_CERT_ID`, `ASC_KEY_P8` (base64 of the `.p8`, NOT raw PEM: raw fails `MalformedFraming`), `ASC_KEY_ID`, `ASC_ISSUER_ID`. Optional: `APPLE_TEAM_ID`, `APPLE_ORG_NAME`, plus whatever `XCCONFIG_SECRETS` names. Seed with `tools/ci_make_signing_p12.py` (mints a DEDICATED CI cert; Apple Distribution is capped at 2). Nothing lands in git.

## Rule 5: The ASC API is an ES256-JWT REST API

A short-lived (under 20 min) **ES256 JWT** signed with the `.p8` (issuer + key id + audience `appstoreconnect-v1`). PyJWT + cryptography; Homebrew python is PEP 668 and lacks them, so `submit-appstore.sh` self-provisions `tools/.asc-venv`.

## Rule 6: The certificate gotchas

- **CSR must be RAW PEM, not base64.** `csrContent` takes the PEM text verbatim, armor included. Base64 again: **409 "Invalid Certificate"**.
- **The .p12 must use legacy PBE** (`openssl pkcs12 -export -legacy`). OpenSSL 3's default AES/PBES2 fails `security import` with **"MAC verification failed"**.
- **The runners fill the certificate cap.** `-allowProvisioningUpdates` on a fresh runner mints a new Apple Development cert ("Created via API") every build, until Apple refuses: *"Your account has reached the maximum number of certificates"*, then "No profiles found", then nothing ships. The app archives fine locally; this is not a code problem. `tools/asc_prune_certs.py` revokes only API-created development certs (never Distribution / Mac Installer, never a person-named cert), keeping the newest `--keep N`. Wired twice: prune before the archive, revoke after with `always()`. Never hand-delete in the portal.

## Rule 7: Floors are chosen by hardware, and held in CI

The floor is a floor, not a ceiling. Choose each deployment target by the HARDWARE it reaches, measured by test-building at each candidate floor, never by adoption share. Raising a floor cuts devices off silently: the store just stops offering the app. Measured defaults (Archive Watch): **iOS 18** (iOS 26 dropped the iPhone XS/XR; below 17 SwiftData and Observation break), **tvOS 26, held below 27** (27 dropped the Apple TV HD and 4K 1st gen), **macOS 26**. `test_ios_floor.py` (`IOS_MAX_FLOOR`, default 18) and `test_tvos_floor.py` (`TVOS_MAX_FLOOR`, default 26) run before every archive. Newer APIs (Liquid Glass, `Tab(role: .search)`, `.navigationTransition(.zoom)`) are used fully behind `#available`, with an older path or an honest omission below. A stored property can't carry `@available`: store it untyped behind a gated accessor.

## Rule 8: Compile-guard traps on the GA toolchain

Code that builds on the beta Xcode can FAIL on the runner's GA Xcode:
- **`#if compiler(>=X.Y)`, not just `#available`.** A symbol only in a beta SDK doesn't resolve on the GA compiler, runtime check or no. Gate the call site at compile time.
- **An SDK-conditional flag scales it.** In the shared xcconfig: `OTHER_SWIFT_FLAGS[sdk=iphoneos27*] = $(inherited) -D IOS27_SDK` (+ the simulator twin); wrap each new-API call `#if IOS27_SDK` around `if #available(iOS 27, *)`, current-OS path in `#else`. Keep `SDKROOT` generic (never pinned to a versioned SDK). Route view-level adoptions through ONE `Compat.swift`. Without the compile-time gate the project silently requires beta Xcode, and the failure surfaces only at submit time.
- **No tuple-sort closures.** `sort { ($0.a, $0.b) < ($1.a, $1.b) }` can time out the GA type-checker. Use explicit comparators or precomputed keys. ("Unable to type-check" also often means a wrong argument label.)

## Rule 9: Bump BOTH version numbers every build

`MARKETING_VERSION` AND `CURRENT_PROJECT_VERSION` in `AppVersion.xcconfig`, every submitted build. App Review burns a build number even on a rejection. One file is the source of truth (never Xcode's identity panel, which creates per-target overrides). `asc_release.py` reads the App Store version string from the same file, so it always equals the binary's `CFBundleShortVersionString`.

## Scaffolding shipped

- `.github/workflows/appstore-build.yml`: build, sign, upload, submit (`-f platform= -f submit= -f notes=`)
- `.github/workflows/appstore-submit.yml`: status / ship / audit / list / upload, no macOS runner
- `tools/submit-appstore.sh`: archive, sign, upload one platform (local or CI); prints the `asc_release.py ship` next step
- `tools/asc_release.py`: status + ship across IOS / TV_OS / MAC_OS
- `tools/asc_submit.py`: screenshot sets + `--audit`, one `--platform`
- `tools/asc_certs.py`, `tools/asc_profiles.py`, `tools/ci_make_signing_p12.py`, `tools/asc_prune_certs.py`, `tools/asc_build_exists.py`
- `tools/test_ios_floor.py`, `tools/test_tvos_floor.py`

## See also

- `apple-app-store-cli-submission`: the version / attach / review traps in depth
- `store-submission-playbook`: listing copy, screenshots, review prep, privacy manifest
- `play-cli-submission`: the Android/Google Play CLI analog
- `ci-fleet-engineering`: the workflow doctrine these workflows follow
