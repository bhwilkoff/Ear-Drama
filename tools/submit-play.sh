#!/usr/bin/env bash
# Build a signed Android App Bundle and publish it to Google Play from the command line — no Android
# Studio, no manual upload (the Play analog of tools/submit-appstore.sh). Bumps versionCode, builds
# the release AAB with the existing upload key (~/.gradle/gradle.properties), then uploads + releases
# via tools/play-publish.py (Google Play Developer API v3).
#
#   tools/submit-play.sh [--track production|internal|alpha|beta] [--notes "..." | --notes @file] [--rollout 0.1] [--draft] [--no-bump]
#
# Notes over Play's 500-character limit are refused before the versionCode bump.
#
# NOTE: needs `chmod +x tools/submit-play.sh` once (git preserves the bit thereafter).
#
# One-time setup (the only thing not already in place):
#   A Google Play Developer API service-account JSON key, with release permission for the app granted
#   in Play Console (Users and permissions). Put it at ~/.config/play/PLAY_SERVICE_ACCOUNT.json (or set
#   PLAY_SERVICE_ACCOUNT_JSON). It belongs in NO git repo. See docs/CLOUD-SUBMISSION.md.
set -euo pipefail
cd "$(dirname "$0")/.."

TRACK="production"; NOTES=""; ROLLOUT=""; DRAFT=""; BUMP=1
while [ $# -gt 0 ]; do
  case "$1" in
    --track) TRACK="$2"; shift 2;;
    --notes) NOTES="$2"; shift 2;;
    --rollout) ROLLOUT="$2"; shift 2;;
    --draft) DRAFT="--draft"; shift;;
    --no-bump) BUMP=0; shift;;
    *) echo "unknown arg: $1"; exit 1;;
  esac
done

GRADLE="android/app/build.gradle.kts"

# Play caps release notes at 500 characters and enforces it at COMMIT, the very
# last call, after the bundle is built and uploaded. A 513-character note once
# cost a seven-minute run and burned a versionCode with it. Checked HERE, before
# anything is bumped or built, because that is the only place failing costs
# nothing. (--notes @file reads the file, as play-publish.py does.)
if [ -n "$NOTES" ]; then
  if [ "${NOTES#@}" != "$NOTES" ]; then
    NOTES_FILE="${NOTES#@}"; NOTES_FILE="${NOTES_FILE/#\~/$HOME}"
    [ -f "$NOTES_FILE" ] || { echo "Release notes file not found: $NOTES_FILE"; exit 1; }
    NOTES_TEXT="$(cat "$NOTES_FILE")"
  else
    NOTES_TEXT="$NOTES"
  fi
  N=$(printf '%s' "$NOTES_TEXT" | python3 -c 'import sys; print(len(sys.stdin.read().strip()))')
  if [ "$N" -gt 500 ]; then
    echo "Release notes are $N characters; Play's limit is 500."
    echo "Shorten by $((N - 500)) and re-run. Nothing has been built or bumped yet."
    exit 1
  fi
fi

KEY="${PLAY_SERVICE_ACCOUNT_JSON:-$HOME/.config/play/PLAY_SERVICE_ACCOUNT.json}"
[ -f "$KEY" ] || { echo "Missing service-account JSON at $KEY (see setup notes at top / docs/CLOUD-SUBMISSION.md)"; exit 1; }

# Bump versionCode (+1) — Play rejects any previously-uploaded versionCode, even unreleased ones.
if [ "$BUMP" = 1 ]; then
  CUR="$(grep -E '^\s*versionCode\s*=' "$GRADLE" | head -1 | sed -E 's/[^0-9]//g')"
  NEW=$((CUR + 1))
  /usr/bin/sed -i '' -E "s/(versionCode[[:space:]]*=[[:space:]]*)[0-9]+/\1$NEW/" "$GRADLE"
  echo "versionCode $CUR → $NEW"
fi
# versionName is READ from AppVersion.xcconfig by the Gradle build, so read it there too.
VN="$(grep -E '^MARKETING_VERSION[[:space:]]*=' AppVersion.xcconfig | head -1 | sed -E 's/.*=[[:space:]]*//')"
VC="$(grep -E '^\s*versionCode\s*=' "$GRADLE" | head -1 | sed -E 's/[^0-9]//g')"
echo "Building Android $VN (versionCode $VC) …"

( cd android && ./gradlew --quiet bundleRelease )
AAB="android/app/build/outputs/bundle/release/app-release.aab"
[ -f "$AAB" ] || { echo "AAB not produced at $AAB"; exit 1; }
echo "signed AAB: $AAB ($(du -h "$AAB" | cut -f1))"

# Ensure a local venv with the Google API libs (gitignored; keeps system Python clean).
VENV="tools/.play-venv"
if [ ! -x "$VENV/bin/python" ]; then
  echo "Creating $VENV with google-api-python-client + google-auth …"
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q --upgrade pip google-api-python-client google-auth
fi

ARGS=(--track "$TRACK")
[ -n "$NOTES" ] && ARGS+=(--notes "$NOTES")
[ -n "$ROLLOUT" ] && ARGS+=(--rollout "$ROLLOUT")
[ -n "$DRAFT" ] && ARGS+=("$DRAFT")
PLAY_SERVICE_ACCOUNT_JSON="$KEY" "$VENV/bin/python" tools/play-publish.py "$AAB" "${ARGS[@]}"

echo "✓ Android $VN (versionCode $VC) published to the '$TRACK' track."
