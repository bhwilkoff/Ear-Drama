#!/usr/bin/env bash
# REFERENCE IMPLEMENTATION (built for a trivia game; the modes and screens
# below are its own). The SHAPE is the point: env-hook-driven captures per
# screen, crash detection from a crash report newer than the launch, durable
# capture paths, findings in a rounds table. To adopt: set the identity in
# tools/app_config.py, HOOK_PREFIX to your hooks' prefix, and replace the
# screen list with YOUR app's debug-hook vocabulary (docs/DEVICE-HARNESSES.md,
# "the QA sweep").
# qa-sweep.sh — drive EVERY game mode and feature screen on a simulator and capture a PNG
# of each, so playability and feature completeness can be reviewed from the images rather
# than by clicking through 40 surfaces by hand.
#
#   tools/qa-sweep.sh ios   [outdir]     # iPhone
#   tools/qa-sweep.sh ipad  [outdir]
#   tools/qa-sweep.sh tvos  [outdir]
#
# This is a TEST pass, not the store capture (tools/capture-screenshots.sh) — it draws real
# questions rather than the screened set, because the point is to catch a mode that renders
# wrong, not to produce a listing.
#
# Every launch is independent: the app is terminated between cases so one mode's crash or
# stuck state cannot silently colour the next one's screenshot.
set -uo pipefail
cd "$(dirname "$0")/.."

PLATFORM="${1:-ios}"
# Default to build/qa/ (gitignored, but SURVIVES) rather than /tmp. Round 1's 47
# captures were written to /tmp, and by the time anyone came back to finish reviewing
# them they were gone — so the review was re-run from scratch. A capture you cannot
# return to is a capture you have to take twice.
OUT="${2:-build/qa/$(date +%F)-$PLATFORM}"
mkdir -p "$OUT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cfg() { python3 -c "import sys; sys.path.insert(0, 'tools'); import app_config as c; print(c.$1)"; }
BUNDLE="${APP_BUNDLE:-$(cfg APPLE_BUNDLE_ID)}"
EXECUTABLE="${APP_EXECUTABLE:-$(cfg APPLE_EXECUTABLE)}"
# Env hooks are <P>_NAME.
P="${HOOK_PREFIX:-APP}"

case "$PLATFORM" in
  ios)  DEVICE_MATCH="iPhone 17 Pro" ;;
  ipad) DEVICE_MATCH="iPad Pro" ;;
  tvos) DEVICE_MATCH="Apple TV" ;;
  *) echo "unknown platform: $PLATFORM"; exit 1 ;;
esac

# Pick a device on a runtime that actually satisfies the deployment target. Matching the
# first name hit picked an iOS 18.5 iPad against an iOS 26 floor, and the failure surfaced
# as a bare "Invalid parameter not satisfying: installURL" from simctl.
SIM=$(xcrun simctl list devices available \
  | awk -v want="$DEVICE_MATCH" '
      /^-- /   { ver = $0; sub(/^-- [A-Za-z]+ /, "", ver); sub(/ --$/, "", ver); major = int(ver) }
      index($0, want) && major >= 26 { print; exit }' \
  | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -n "$SIM" ] || { echo "no simulator matching '$DEVICE_MATCH' on a runtime >= 26"; exit 1; }
echo "simulator: $DEVICE_MATCH ($SIM)"
xcrun simctl boot "$SIM" 2>/dev/null
xcrun simctl bootstatus "$SIM" -b >/dev/null 2>&1

# Capture one case: name, then KEY=VALUE launch env, then a settle time.
shot() {
  local name="$1"; shift
  local settle="${SETTLE:-7}"
  xcrun simctl terminate "$SIM" "$BUNDLE" >/dev/null 2>&1
  local env_args=()
  for kv in "$@"; do env_args+=("SIMCTL_CHILD_${kv%%=*}=${kv#*=}"); done
  # Onboarding would sit over every single capture. On tvOS the Game Center sign-in
  # overlay ALSO covers the whole screen on launch and ate an entire capture run.
  [ "$PLATFORM" = "tvos" ] && env_args+=("SIMCTL_CHILD_${P}_NO_GAMECENTER=1")
  # Mark the moment, so a crash report written AFTER the launch is unambiguous.
  local stamp; stamp="$OUT/.stamp"; : > "$stamp"
  env "${env_args[@]}" SIMCTL_CHILD_${P}_SKIP_ONBOARD=1 \
    xcrun simctl launch "$SIM" "$BUNDLE" >/dev/null 2>&1
  sleep "$settle"
  xcrun simctl io "$SIM" screenshot "$OUT/$name.png" >/dev/null 2>&1
  # Look for a crash REPORT newer than the launch. Two earlier attempts got this wrong and
  # cried wolf on every healthy screen: `launchctl list` does not list simulator apps, and
  # `simctl spawn kill -0` does not report the app's liveness either. A .ips written after
  # the stamp is the only signal here that means what it says.
  local crash
  crash=$(find ~/Library/Logs/DiagnosticReports -name "$EXECUTABLE*.ips" \
            -newer "$stamp" 2>/dev/null | head -1)
  if [ -n "$crash" ]; then
    echo "  $name  <-- CRASHED ($(basename "$crash"))"
  else
    echo "  $name"
  fi
}

echo "== game modes (mid-question) =="
for mode in classic timeAttack survival stake sweep pictureId thisOrThat closestCall \
            ordering matching typeAnswer oddOneOut ladder enumerate daily; do
  shot "mode-$mode" "${P}_AUTOPLAY=$mode:mixed"
done

echo "== game modes (after answering — reveal + scoring) =="
for mode in classic stake pictureId thisOrThat closestCall ordering matching typeAnswer oddOneOut; do
  shot "reveal-$mode" "${P}_AUTOPLAY=$mode:mixed" "${P}_AUTOPILOT=1" \
       "${P}_AUTOPILOT_STEPS=1" "${P}_AUTOPILOT_CORRECT=1"
done

echo "== end-of-game results =="
for mode in classic survival sweep; do
  SETTLE=30 shot "results-$mode" "${P}_AUTOPLAY=$mode:mixed" "${P}_AUTOPILOT=1" \
       "${P}_AUTOPILOT_CORRECT=1"
done

echo "== feature screens =="
shot home              "${P}_TAB=play"
shot records           "${P}_TAB=records" "${P}_SEED_RECORDS=24"
shot create            "${P}_TAB=create"
shot settings          "${P}_SETTINGS=1"
shot profile           "${P}_PROFILE=1"
shot customize         "${P}_CUSTOMIZE=1"
shot daily-archive     "${P}_DAILY_ARCHIVE=1"
shot night-setup       "${P}_NIGHT_SETUP=1"
shot party             "${P}_PARTY=1"
shot versus            "${P}_VERSUS=1"
shot multiplayer       "${P}_MULTIPLAYER=1"
shot paywall           "${P}_PAYWALL=1"
shot club-hub          "${P}_CLUB_HUB=1" "${P}_CLUB=1"
shot story-archive     "${P}_STORY_ARCHIVE=1" "${P}_CLUB=1" "${P}_SEED_RECORDS=24"
shot atlas             "${P}_ATLAS=1" "${P}_CLUB=1" "${P}_SEED_RECORDS=24"
shot linkwall          "${P}_LINKWALL=1" "${P}_CLUB=1"
shot expedition-map    "${P}_EXPEDITION_MAP=1" "${P}_CLUB=1"
shot marathon          "${P}_MARATHON=1" "${P}_CLUB=1" "${P}_MARATHON_LEN=5"
shot weakspot          "${P}_AUTOPLAY=weakSpot:mixed" "${P}_CLUB=1" "${P}_SEED_RECORDS=24"
shot mix               "${P}_MIX=1"

echo
echo "captured $(ls "$OUT"/*.png 2>/dev/null | wc -l | tr -d ' ') PNGs → $OUT"
