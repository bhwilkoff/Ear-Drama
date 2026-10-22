# App Store version, release and review from the CLI

Until 2026-09-01 the Apple build was automated but a person still had to open App Store Connect,
create the version, pick the build and press Submit. That stopped being true the day we found out
why it had seemed necessary: the obvious API endpoint for submitting is deprecated and answers
403, which reads as "you can't do this" rather than "use the other one".

I want shipping to end at the store, not at a console. This page is the second half of a release:
the App Store version, the attached build, What's New, and the review submission, on every Apple
platform the app ships. The first half (building, signing and uploading the binary) is
[CLOUD-SUBMISSION.md](CLOUD-SUBMISSION.md).

**Nobody opens App Store Connect to press Submit.**

---

## The release, end to end

```bash
# 1. Bump the version. BOTH numbers move on every ship.
$EDITOR AppVersion.xcconfig                   # MARKETING_VERSION and CURRENT_PROJECT_VERSION
python3 tools/stamp_msix_version.py           # keeps Windows in lockstep, if it ships
git commit -am "X.Y.Z (N): ..." && git push

# 2. Build, upload, wait for processing, and submit. One dispatch.
gh workflow run appstore-build.yml -f platform=all -f notes="What's new in this version"
```

`appstore-build.yml` ends by running `tools/asc_release.py ship --submit` itself. When the upload
finished without a submit (no notes given, or `submit=false`), finish it here:

```bash
gh workflow run appstore-submit.yml -f mode=ship -f release_notes="What's new..." -f submit=true
```

Then read the state back. The tool's own success message is not evidence:

```bash
gh workflow run appstore-submit.yml -f mode=status              # every platform
gh workflow run appstore-submit.yml -f mode=audit -f platform=ios   # one platform, in depth
```

`status` should show each platform's in-progress version as `WAITING_FOR_REVIEW` with the build
it carries. `audit` should end with `no blockers found`.

---

## `tools/asc_release.py`

The tool that ships. It works across **every** Apple platform in `APP_STORE_PLATFORMS` (default
`tvos,ios,mac`, which Connect calls `TV_OS`, `IOS` and `MAC_OS`).

```bash
python3 tools/asc_release.py status [--build N]
python3 tools/asc_release.py ship [--platform all|ios|tvos|mac] [--version X.Y.Z] [--build N] \
    [--notes TEXT | --notes-file FILE] [--locale en-US] \
    [--release-type AFTER_APPROVAL|MANUAL|SCHEDULED] \
    [--wait-build-minutes 40] [--submit] [--dry-run]
```

**`status`** is read-only. Per platform it prints the live version, the in-progress one and its
state, and the state of the build: `VALID`, `PROCESSING`, or what the upload record says when the
build list does not show it yet (Apple lists a build only after processing, and a build Apple failed
after "Upload succeeded" appears only on the upload record, with Apple's errors). A version already
in review is judged by the build it carries, not the repo's number. `status` exits 0 whenever it
could read everything. "Not uploaded yet" and "still processing" are normal states of a release, so
they print as `::warning::`, never as a red X.

**`ship`**, per platform:

1. **Open the version.** It reuses an editable version (`PREPARE_FOR_SUBMISSION`, or rejected)
   and **renames** it to the target string if it differs, or creates one as `AFTER_APPROVAL`. A
   platform with a version already waiting for review or in review is skipped with a warning.
2. **Wait for the build.** With `--wait-build-minutes`, it polls until THIS build number is
   `VALID` on THIS platform. Apple puts ten to thirty minutes of processing between upload and
   submit, and attaching a build that is not VALID fails with a confusing relationship error.
3. **Attach the build**, found with `filter[preReleaseVersion.platform]`.
4. **Set What's New** for the locale.
5. **Set the release type**, if asked.
6. **Submit** (only with `--submit`) through the three-call review submission.

A platform that fails any step stops before submitting. The run exits 1 only if a platform failed.

The version string comes from `MARKETING_VERSION` and the build from `CURRENT_PROJECT_VERSION` in
`AppVersion.xcconfig`, so the App Store version always matches the binary's own
`CFBundleShortVersionString`. Pass `--build` when a later commit has moved the repo's number past
the build that is actually on Connect.

`ship --submit` **refuses to start without What's New**, before any network call. Apple refuses
review without it, but only after the versions are created and the builds attached, which would
leave half-made versions on every platform.

Configuration (the environment wins over `tools/app_config.py`): `ASC_KEY_ID` and `ASC_ISSUER_ID`
(the `.p8` in `~/.appstoreconnect/private_keys` or at `ASC_KEY_PATH`), `APP_BUNDLE` (default
`APPLE_BUNDLE_ID`), and `APP_STORE_PLATFORMS`.

---

## `appstore-submit.yml` modes

Pure REST on `ubuntu-latest`: no Xcode, no macOS runner. It needs only the three `ASC_KEY_*`
secrets `appstore-build.yml` already uses, plus the optional `APP_BUNDLE` and `APP_STORE_PLATFORMS`
repo variables.

| `-f mode=` | Does | Platforms |
|---|---|---|
| `status` | `asc_release.py status` (default mode) | all |
| `ship` | status before, `asc_release.py ship --wait-build-minutes 40`, status after (into the step summary) | `all` or one |
| `audit` | `asc_submit.py --audit`: what App Review will check. Exits non-zero on a blocker. | one |
| `list` | `asc_submit.py --list`: the platform's versions and states | one |
| `upload` | `asc_submit.py --set ...`: upload screenshot sets from the `sets` input | one |

`ship` inputs: `version`, `build`, `release_notes` (required with `submit`), `release_type`
(`AFTER_APPROVAL` or `MANUAL`), `submit` (default **false** here, so a bare `ship` only prepares),
`dry_run`. `upload` inputs: `sets` (space-separated `DISPLAY_TYPE=DIR`), `replace`, `dry_run`.
`audit`, `list` and `upload` act on one platform and refuse `platform=all`.

Every input reaches the scripts as environment, and every optional flag is an `if ... fi`, never
`[ -n "$X" ] && args+=(...)` (that one-liner returns 1 on an empty input, and as a step's last line
it fails the step).

### `tools/asc_submit.py`

The screenshot and audit tool. `--platform ios|tvos|mac` (default `ios`) picks which platform's
version it acts on.

- `--set DISPLAY_TYPE=DIR` uploads a screenshot set (`--replace` clears it first; otherwise a
  non-empty set is skipped so a re-run cannot duplicate a panel). This is how an iMessage app gets
  its own sets, which Connect requires and nothing else produces.
- `--audit` checks the attached build, required localisation fields, every screenshot set's
  delivery state and per-asset errors, age rating, review contact, the export-compliance answer,
  and whether an open review submission actually has items.
- `--list` and `--status` report.

It still has `--create-version`, `--attach-build`, `--release-notes` and `--submit` for a
one-platform fix-up, and they are platform-aware. Ship with `asc_release.py`.

---

## Release type: it auto-releases

New versions are created **`AFTER_APPROVAL`**: approval puts the version on the store with no
further action. An approved build sitting unreleased is a silent stall, and the Microsoft Store has
already cost this project days in exactly that shape (`docs/windows/WINDOWS-STORE-SUBMISSION.md`).

Release type is release logistics, not reviewable content, so Apple lets it change while the
version sits in `WAITING_FOR_REVIEW`, with no withdrawal. `asc_release.py ship` skips a version
already in review, so change it on that version with the one-platform tool:

```bash
set -a; . tools/asc-credentials.env; set +a
python3 tools/asc_submit.py --platform ios --release-type MANUAL
```

Anything that edits reviewable content (screenshots, notes, the attached build) needs an editable
version.

---

## The traps

Every one of these built and archived **green** and failed only at upload or submit. For App Store
work, a green build tells you almost nothing.

**1. A TestFlight upload does not create an App Store version.** They are separate records. Builds
had been uploaded for weeks with no version record at all, so the first submission attempt could see
only the previous `READY_FOR_SALE` version and refused to continue. `ship` opens one.

**2. `POST /v1/appStoreVersionSubmissions` is deprecated.**

```
403  The resource 'appStoreVersionSubmissions' does not allow 'CREATE'.
     Allowed operation is: DELETE
```

Deprecated, not broken, and the message never says so. Submitting is three calls: create a
`reviewSubmissions`, add the version as a `reviewSubmissionItems`, then PATCH `submitted: true`.
Apple's model is a submission carrying items (the version, in-app purchases and so on), which is
also why a version cannot be sent alone.

**3. Three platforms means three versions and three submissions.** tvOS, iOS and macOS share one
build number from one universal target, but Connect keeps a separate `appStoreVersion` and a
separate `reviewSubmission` per platform. A tool that hardcodes `filter[platform]=IOS` ships one app
and reports success.

**4. Builds must be filtered by platform.** `platform=all` produces three builds sharing one number.
Without `filter[preReleaseVersion.platform]` the first match wins at random, and Connect answers
"The specified build has a different platform than the version", which reads like a build problem
rather than a query problem.

**5. A wrong version string cannot be deleted, only renamed.** Connect ACCEPTS a version string
lower than the live one (the rejection comes later, at review), and DELETE answers
`409 STATE_ERROR Only the first version of any platform can be deleted`. It IS renameable while in
`PREPARE_FOR_SUBMISSION`, which is why `ship` reconciles the string rather than leaving it.

**6. A new extension or app target needs its App ID registered.** Signing dies with `bundle id not
found in App Store Connect ... (register it first)`. `tools/asc_profiles.py` registers it. Apple
rejects `.` and `_` in a bundle id's **name**; the identifier itself is fine.

**7. An iMessage icon set needs `"platform": "ios"`** on its `universal` and `ios-marketing`
entries. Without it actool silently drops them, buries a `5 unassigned children` warning in the
build log, and emits no `MSMessagesExtensionStoreIconName`. Then the upload rejects the build for
missing 54x40, 64x48, 96x72 and 81x60 icons. Pin it with a test that reads the Contents.json.

**8. An in-app purchase rides exactly one review submission.** Concurrent platform submissions
starve each other of it. Ship the product-carrying platform first
(`docs/store/IAP-RELEASE-CHOREOGRAPHY.md`).

---

## Credentials

The submission runs in CI because the credentials live in GitHub secrets and belong in one place:
`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (**base64**, not raw PEM; raw fails with `Unable to
load PEM file ... MalformedFraming`). Running locally works too, with the `.p8` in
`~/.appstoreconnect/private_keys/` and the two ids in the gitignored `tools/asc-credentials.env`.

---

## When something fails

`asc_release.py` prints every Apple error AND every associated error (`meta.associatedErrors`),
which is where the actual reason lives. A 409 that says only "is not in valid state" becomes a
readable list. `asc_submit.py` prints Apple's error body verbatim. Read it. Two of the traps above
were solved by reading the rejection and one by reading Apple's format reference. None was solved by
guessing.

And be suspicious of a probe that reports success. While diagnosing the icon set,
`--stickers-icon-role app` appeared to pass because actool rejected the flag outright, so the warning
being grepped for never appeared. A broken command read as a clean result. Check that a check can
actually fail before you trust it.

Bring back the `status` output, not the tool's word for it.
