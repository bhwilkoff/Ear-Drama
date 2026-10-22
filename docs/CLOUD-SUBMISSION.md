# Cloud build, sign and upload

On 2026-06-30 Archive Watch's builds were refused twice after uploading cleanly: once for an Xcode
below Apple's floor, and once because the dev Mac ran a beta macOS. TestFlight took them. App
Review did not. So the builds moved to a GitHub runner, and they never came back.

I want a release to cost one command and no trips into a console. This page is the first half of
that: turning the commit into signed binaries on the stores' servers. The second half (opening the
App Store version, attaching the build, sending it for review) is
[APPLE-SUBMISSION-CLI.md](APPLE-SUBMISSION-CLI.md). The two halves usually run as one dispatch.

**Build where the store will accept it.**

The pipeline covers the three Apple binaries (macOS, iOS and iPadOS, tvOS) and Android. It lives in
these files:

| File | Role |
|---|---|
| `.github/workflows/appstore-build.yml` | Cloud build, sign and upload of the Apple apps, then submit |
| `tools/submit-appstore.sh` | The Apple archive, sign and upload driver (runs locally OR in CI) |
| `tools/asc_certs.py` | Find or create an Apple signing cert through the App Store Connect API |
| `tools/asc_profiles.py` | Create App Store provisioning profiles per bundle id (registers a new App ID) |
| `tools/ci_make_signing_p12.py` | Mint a CI signing cert as a `.p12`, to seed the GitHub secrets |
| `tools/asc_prune_certs.py` | Revoke the throwaway development certs each runner mints |
| `tools/asc_build_exists.py` | Refuse to rebuild a build number App Store Connect already has |
| `tools/test_ios_floor.py`, `tools/test_tvos_floor.py` | Hold the deployment floors in CI |
| `tools/asc_release.py` | Version, attach, notes and submit (see the review runbook) |
| `.github/workflows/play-release.yml` | Cloud build and publish of the Android app |
| `tools/submit-play.sh`, `tools/play-publish.py`, `tools/play_promote.py` | The Play Developer API path |

> **Before first use:** `chmod +x tools/submit-appstore.sh tools/submit-play.sh` (git keeps the
> bit after you commit it). Fill in the `# FILL IN` and `<PLACEHOLDER>` values, and the app
> identity in `tools/app_config.py`.

Placeholders used throughout: `AppName` (Xcode scheme and product, no spaces), `com.example.appname`
(the shared Apple bundle id AND the Play applicationId), `<TEAM_ID>` (your 10-character Apple Team
ID), `<ORG_NAME>` (the org name exactly as it appears in your signing certs).

---

## 1. Why build in the cloud

Two rejections force this pipeline, and both arrive AFTER the upload succeeds:

- **ITMS-90301.** Apple rejects App Store builds made on a BETA macOS. If your dev Mac runs a beta
  OS (common when you target the newest SDK early), you cannot submit from it.
- **ITMS-90111.** The Xcode and SDK floor. App Review rejects a build made with an Xcode older than
  Apple's current floor, and Apple raises it every few weeks. A build number ending in a lowercase
  letter (for example `27A5194q`) is a beta and is always rejected. You need a GA or RC.

A GitHub-hosted macOS runner always has a released macOS and Xcode, so it clears both. It is free
for a public repo.

TestFlight still accepts a build from a beta box, so testing is never blocked. Only App Review
needs the released toolchain. The cost of this choice is that the runner can be a whole major
version behind your dev Mac, which is what section 6 is about.

> The `runs-on: macos-NN` label and the Xcode glob in `appstore-build.yml` are a moving target.
> Bump both when ITMS-90111 comes back (see the header comment in that file).

---

## 2. The Apple pathway

All three Apple platforms live in **one App Store Connect record** sharing **one bundle id**.
iOS is added as a second platform to the record, macOS as a third. One build number exists once
PER PLATFORM, which matters for every query that follows.

1. **Bump the version and push.** Edit `AppVersion.xcconfig` (`MARKETING_VERSION` and
   `CURRENT_PROJECT_VERSION`, both, every ship), run `python3 tools/stamp_msix_version.py` if
   Windows ships too, commit, push. The runner builds the committed tree.
2. **Dispatch with What's New.**
   ```bash
   gh workflow run appstore-build.yml -f platform=all -f notes="What's new in this version"
   gh run watch $(gh run list --workflow=appstore-build.yml -L1 --json databaseId -q '.[0].databaseId')
   ```
3. **Read the step summary.** It ends with `asc_release.py status`: per platform, the live version,
   the one in review, and the build it carries.

That is the whole release. Nobody opens App Store Connect to press Submit.

### What `appstore-build.yml` does, step by step

| Step | What it does, and why |
|---|---|
| Select a released Xcode | Picks the newest GA Xcode on the runner, skipping betas (ITMS-90111). |
| Write `Secrets.xcconfig` | Only when `XCCONFIG_SECRETS` is set. Writes the app's build-time keys from repo secrets and **fails if any listed secret is empty**. Without this a missing key is silent: the setting resolves to the literal `$(KEY)`, the app reads that as absent, and every cloud build ships without the feature. It prints each key's length, never its value. |
| Import signing certs | The Distribution and Mac Installer `.p12`s go into a temporary keychain, with `set-key-partition-list` so codesign does not hang on a prompt. |
| Install the API key | Writes the `.p8` and `tools/asc-credentials.env` for the tools that follow. |
| Prune throwaway certs | `asc_prune_certs.py --apply --keep 2`, catching what a force-killed earlier run left. `continue-on-error`: a pruning hiccup must never block a build. |
| Refuse a duplicate build | `asc_build_exists.py <version> <build>` exits 1 in seconds if App Store Connect already has that build number, rather than at the end of a 30-minute archive. The usual cause is a dispatch that went out beside a rejected push. It exits 0 if it cannot reach Apple: a guard that blocks shipping because it could not check is worse than no guard. |
| Floors have not drifted | `test_ios_floor.py` and `test_tvos_floor.py` (section 6). |
| Archive, sign, upload | `tools/submit-appstore.sh <platform>` with manual signing (section 3). |
| Revoke this run's cert | `if: always()`. The development cert this run minted is useless once the runner is gone, so `asc_prune_certs.py --apply --keep 0` revokes it, even on a failed or cancelled build. Safe only because the workflow's concurrency group admits one run at a time. |
| Submit for review | When `submit` is true and `notes` is not blank: `asc_release.py ship --platform <p> --submit --notes-file <file> --wait-build-minutes 40`. It waits for THIS build to go VALID, then opens, attaches and submits (the review runbook has the details). |

Two dispatches do less, and each says so with a warning rather than a red X:

- **No notes.** Apple refuses review without What's New, so the build uploads and the submit step
  is skipped with `::warning::`. Finish it with `appstore-submit.yml` (mode `ship`).
- **`submit=false`.** Upload only. Use it when a version is already in review and must not be
  disturbed.

The inputs and settings:

| Input or setting | Meaning |
|---|---|
| `platform` | `all`, `mac`, `ios` or `tvos` |
| `submit` | Default `true`. Submit once the build finishes processing. |
| `notes` | What's New. Required to submit. |
| repo variable `APP_BUNDLE` | The app record's bundle id (else `APPLE_BUNDLE_ID` in `tools/app_config.py`) |
| repo variable `APP_STORE_PLATFORMS` | What `all` means to `asc_release.py`, for example `ios,mac` (else all three) |
| workflow env `XCCONFIG_SECRETS` | Space-separated `SECRET_NAME` or `XCCONFIG_KEY=SECRET_NAME` entries. Empty means no build-time secrets. |

Inputs reach every script as **environment**, never pasted into the shell line. A What's New with
a double quote in it would otherwise close the shell string, and free text pasted into a shell
line is an injection route.

### The same build, locally

On a machine with a RELEASED Xcode (never a beta):
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer tools/submit-appstore.sh all
```
The script refuses a `*beta*` `DEVELOPER_DIR`. It archives, resolves the embedded bundle ids,
ensures the Apple Distribution cert (plus the Mac Installer cert for macOS), creates an App Store
profile per bundle id, writes a manual `ExportOptions.plist`, then exports and uploads. Re-running
is safe. It ends by printing the `asc_release.py ship` command that finishes the release.

---

## 3. Manual signing and the CI secrets

**Why manual, not automatic signing.** Cloud-managed ("Automatically manage signing") signing can
fail for a team's App Store Connect API key with *"Cloud signing permission error"*. But the same
key can create certs and profiles directly through the REST API. So the pipeline signs manually:
it mints or reuses an Apple Distribution cert, builds App Store provisioning profiles, and hands
xcodebuild a manual `ExportOptions.plist`. On CI the cert and key come from a `.p12` in a temporary
keychain, and `ASC_DIST_CERT_ID` tells `submit-appstore.sh` to use that cert directly.

**The seven required GitHub secrets:**

| Secret | What it is |
|---|---|
| `APPLE_DIST_P12` | base64 of the **Apple Distribution** `.p12` (leaf cert and private key) |
| `APPLE_INSTALLER_P12` | base64 of the **3rd Party Mac Developer Installer** `.p12` (macOS `.pkg` signing) |
| `APPLE_P12_PASSWORD` | the password protecting BOTH `.p12`s |
| `APPLE_DIST_CERT_ID` | the Distribution cert **id** (ties the App Store profiles to that cert) |
| `ASC_KEY_P8` | base64 of the App Store Connect API key `AuthKey_<KEYID>.p8` |
| `ASC_KEY_ID` | the API **Key ID** |
| `ASC_ISSUER_ID` | the API **Issuer ID** (a UUID) |

Optional: `APPLE_TEAM_ID` and `APPLE_ORG_NAME` (or hardcode them in `submit-appstore.sh`'s PER-APP
CONFIG block), plus whatever `XCCONFIG_SECRETS` names.

`ASC_KEY_P8` is **base64**, not raw PEM. Passed through raw it fails with `Unable to load PEM file
... MalformedFraming`.

### Seeding the secrets (one time)

First get an **App Store Connect API key**: App Store Connect, *Users and Access, Integrations,
App Store Connect API*, generate a key (role **App Manager** or Admin). Note the **Key ID** and
**Issuer ID**, and download `AuthKey_<KEYID>.p8` (it downloads once) to
`~/.appstoreconnect/private_keys/`.

```bash
export ASC_KEY_ID=<KEYID> ASC_ISSUER_ID=<ISSUER-UUID> ASC_ORG_NAME="<ORG_NAME>"
export ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8
PW="$(openssl rand -hex 16)"

# Mint a DEDICATED CI Apple Distribution cert as a .p12 (no keychain import, no GUI prompt).
# Apple allows 2 Apple Distribution certs; this uses the second slot.
read DIST_ID DIST_P12 < <(python3 tools/ci_make_signing_p12.py distribution build/ci-dist.p12 "$PW")
# And the Mac Installer cert (only needed if you ship a macOS .pkg):
read INST_ID INST_P12 < <(python3 tools/ci_make_signing_p12.py mac_installer build/ci-inst.p12 "$PW")

gh secret set APPLE_DIST_P12      < <(base64 -i "$DIST_P12")
gh secret set APPLE_INSTALLER_P12 < <(base64 -i "$INST_P12")
gh secret set APPLE_P12_PASSWORD  --body "$PW"
gh secret set APPLE_DIST_CERT_ID  --body "$DIST_ID"
gh secret set ASC_KEY_P8          < <(base64 -i "$ASC_KEY_PATH")
gh secret set ASC_KEY_ID          --body "$ASC_KEY_ID"
gh secret set ASC_ISSUER_ID       --body "$ASC_ISSUER_ID"
# optional: gh secret set APPLE_TEAM_ID --body "<TEAM_ID>"; gh secret set APPLE_ORG_NAME --body "<ORG_NAME>"
```
Keep the `.p12`s as a backup outside the repo. **Never commit them** (`build/`, `*.p8` and
`*.p12` stay gitignored).

`ci_make_signing_p12.py` mints a **dedicated** CI cert rather than exporting your existing one,
because an existing cert's private key lives in the login keychain and exporting it raises a GUI
prompt. Minting fresh generates the keypair locally and builds the `.p12` with openssl, no prompt.

---

## 4. The certificate traps

Baked into `asc_certs.py`, `ci_make_signing_p12.py` and `asc_prune_certs.py`. Do not "fix" them
away.

1. **`csrContent` must be RAW PEM, not base64.** `POST /v1/certificates` takes the CSR file's raw
   PEM string, WITH the `-----BEGIN/END CERTIFICATE REQUEST-----` lines. Base64-encoding the PEM
   again is rejected `409 ENTITY_ERROR.ATTRIBUTE.INVALID "Invalid Certificate"`.
2. **The `.p12` must be built with `openssl pkcs12 -export -legacy`.** OpenSSL 3 defaults to
   PBES2 with AES-256, which macOS `security import` cannot read (*"MAC verification failed"*).
   `-legacy` uses the SHA1 and 3DES scheme the keychain accepts.
3. **The runners fill the certificate cap.** The archive runs with `-allowProvisioningUpdates`, and
   every runner is a fresh machine with an empty keychain, so Xcode mints a NEW Apple Development
   certificate on every build. They pile up (all named "Created via API") until Apple refuses:
   *"Your account has reached the maximum number of certificates"*. Then provisioning falls back to
   profiles that do not exist and nothing can ship. The workflow prunes before the archive and
   revokes its own cert with `always()` after it. `asc_prune_certs.py` touches only development
   certs named "Created via API": never Distribution or Mac Installer certs, and never a cert with a
   person's name on it (that is somebody's local Xcode).

The JWT for every App Store Connect call is **ES256** (the `.p8` is an EC P-256 key), signed with
PyJWT and cryptography. Homebrew's `python3` is externally managed (PEP 668) and often lacks PyJWT,
so `submit-appstore.sh` provisions `tools/.asc-venv` (gitignored) when `import jwt` fails.

---

## 5. Google Play pathway

Android builds in CI too, for the same reason in a different shape: a release build is R8 plus a
full Kotlin compile, and on a working laptop that took the machine to 18% free memory while someone
was using it.

```bash
gh workflow run play-release.yml -f notes="What's new"               # build, publish to internal
# install it from Play internal on a real device and use it, then:
gh workflow run play-release.yml -f promote=<versionCode>            # the SAME build to production
gh workflow run play-release.yml -f promote=<versionCode> -f rollout=0.1   # staged
```

`play-release.yml` bumps `versionCode` (the Gradle build READS `versionName` from
`AppVersion.xcconfig`, so only the code moves), builds the signed bundle, refuses an unsigned one,
publishes through `play-publish.py`, and commits the bump back with `[skip ci]`. Promotion builds
nothing: `play_promote.py` moves the artifact that was tested. Secrets: `PLAY_SERVICE_ACCOUNT_JSON`,
`UPLOAD_KEYSTORE_B64`, `UPLOAD_KEYSTORE_PASSWORD`, `UPLOAD_KEY_ALIAS`, `UPLOAD_KEY_PASSWORD`.

The local path is still there:

```bash
tools/submit-play.sh --track production --notes "What's new"          # bump, build, publish
tools/submit-play.sh --track internal --draft                          # internal draft, no rollout
tools/submit-play.sh --track production --rollout 0.1 --notes "..."    # staged 10% rollout
```

Both run the **Play Developer API v3 "edits" transaction**: insert an edit, upload the `.aab`,
point a track at the new versionCode with release notes, commit.

Facts baked in:
- **`versionCode` must be unique and only ever grow.** Play rejects any versionCode it has seen,
  even one never released. `submit-play.sh` bumps it (skip with `--no-bump`).
- **Release notes are capped at 500 characters.** Check the length BEFORE the bump: a refusal
  after the upload has already spent the versionCode.
- **`applicationId` is not `namespace`.** `PLAY_PACKAGE` (default `com.example.appname`) must be the
  Play **applicationId**, which can differ from the Gradle `namespace`.

### The service-account JSON key (one time)

`play-publish.py` needs a **Google Play Developer API service-account JSON key** at
`~/.config/play/PLAY_SERVICE_ACCOUNT.json` (or `PLAY_SERVICE_ACCOUNT_JSON`). To get one:

1. **Google Cloud Console**: new project, enable `androidpublisher.googleapis.com`.
2. **IAM and Admin, Service Accounts, Create** (skip the roles step), then **Keys, Add key, JSON**.
3. Move it: `mkdir -p ~/.config/play && mv ~/Downloads/*.json ~/.config/play/PLAY_SERVICE_ACCOUNT.json && chmod 600 ~/.config/play/PLAY_SERVICE_ACCOUNT.json`
4. **Play Console, Users and permissions, Invite** the service account's email, and grant
   **Release to production** and **Release to testing tracks** for your app. You no longer need to
   link the Play account to a Cloud project, whatever older guides say.

> **The org-policy block.** If key creation is greyed out or errors *"Service account key creation
> is disabled"*, your Google account belongs to a Cloud **organization** that enforces
> `iam.disableServiceAccountKeyCreation` (and its `iam.managed.` twin). Either turn both policies
> off at the org level (needs Organization Policy Administrator), or create the project under a
> **personal Gmail with no organization**. A service account from any project can be invited into
> Play Console. Walkthrough: `docs/store/play-api-key-setup.md`.

A connectivity check before a real release (proves key and permissions, costs nothing):
```bash
python3 -c "
from google.oauth2 import service_account
from googleapiclient.discovery import build
import os
c=service_account.Credentials.from_service_account_file(
  os.path.expanduser('~/.config/play/PLAY_SERVICE_ACCOUNT.json'),
  scopes=['https://www.googleapis.com/auth/androidpublisher'])
s=build('androidpublisher','v3',credentials=c,cache_discovery=False)
print('OK edit id', s.edits().insert(packageName='com.example.appname',body={}).execute()['id'])
"
```

---

## 6. Floors and the GA toolchain

**The floor is chosen by the hardware it reaches.** Each app picks its deployment targets by
test-building at each candidate floor and counting what breaks, never by adoption share. Raising a
floor cuts devices off with no error anywhere: the store simply stops offering the app to them.
`test_ios_floor.py` (default ceiling iOS 18, `IOS_MAX_FLOOR`) and `test_tvos_floor.py` (default
tvOS 26, `TVOS_MAX_FLOOR`) run before every archive and fail if a floor drifted up. Both are no-ops
with a message until the app has an Xcode project. Newer APIs are used fully on devices that have
them, behind `#available`, with an older path or an honest omission below.

The runner uses a **released** Xcode, which may be a whole major behind your beta dev box. Two
things break a GA compile that a beta compile hides:

- **`#if compiler(>=X.Y)`, not just `#available`.** A symbol that exists only in a newer SDK does
  not **compile** on the older GA SDK, runtime check or no. Wrap such sites in
  `#if compiler(>=X.Y)` (the newer toolchain's Swift version) with the older path in `#else`. For
  more than a few sites, an SDK-conditional flag scales better: in the shared xcconfig,
  `OTHER_SWIFT_FLAGS[sdk=iphoneos27*] = $(inherited) -D IOS27_SDK` (plus the simulator twin), then
  `#if IOS27_SDK` around `if #available(iOS 27, *)`. Keep `SDKROOT` generic.
- **No tuple-sort closures in a type-checked hot path.** Sorting by a multi-field tuple inside
  `.sorted { ... }` can blow the GA type-checker's budget ("unable to type-check this expression in
  reasonable time") when the beta compiles it fine. Use an explicit comparator or a precomputed key.

Diagnose an ITMS-90111 rejection by comparing the latest **released or RC** Xcode on
<https://developer.apple.com/news/releases> with the build's `xcodebuild -version`. Then bump the
runner and the Xcode glob in `appstore-build.yml` and rebuild every Apple platform at a fresh build
number.

---

The binary is on the store's servers. Now send it for review:
[APPLE-SUBMISSION-CLI.md](APPLE-SUBMISSION-CLI.md).
