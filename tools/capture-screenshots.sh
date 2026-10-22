#!/usr/bin/env bash
# REFERENCE IMPLEMENTATION (built for a trivia game; the screen list below is
# its listing). The SHAPE is the point: one deep-link/env hook per store
# screenshot, exact store dimensions asserted, and the free-features-only rule
# ENFORCED BY THE TOOL (it refuses to run with a premium flag set). To adopt:
# set the identity in tools/app_config.py, the hook prefixes below, and replace
# the screen list with YOUR app's (docs/store/STORE-SCREENSHOTS.md).
#
#   tools/capture-screenshots.sh <ios|ipad|tvos|macos|android|android-tablet|all>
#
# Every shot is driven by the app's debug env hooks, so nothing here needs a tap. Output:
#   branding/store-screenshots/<platform>/NN-name.png   (numbered in listing order)
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

cfg() { python3 -c "import sys; sys.path.insert(0, 'tools'); import app_config as c; print(c.$1)"; }

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
APP_NAME="${APP_NAME:-$(cfg APPLE_APP_NAME)}"
BUNDLE_APPLE="${APP_BUNDLE:-$(cfg APPLE_BUNDLE_ID)}"
BUNDLE_ANDROID="${ANDROID_PACKAGE:-$(cfg ANDROID_PACKAGE_DEBUG)}"
ANDROID_ACTIVITY="${ANDROID_ACTIVITY:-$(cfg ANDROID_MAIN_ACTIVITY)}"
# Env hooks are <P>_NAME on Apple and <AP>_name intent extras on Android.
P="${HOOK_PREFIX:-APP}"
AP="${ANDROID_EXTRA_PREFIX:-appname}"
# Simulators by NAME (the first available match), never a udid pasted from one Mac.
IPHONE_SIM_NAME="${IPHONE_SIM_NAME:-iPhone 17 Pro Max}"
IPAD_SIM_NAME="${IPAD_SIM_NAME:-iPad Pro 13-inch}"
TV_SIM_NAME="${TV_SIM_NAME:-Apple TV 4K}"
PHONE_AVD="${PHONE_AVD:-Pixel_9_Pro}"
TABLET_AVD="${TABLET_AVD:-Tablet_10}"
ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
ADB="$ANDROID_HOME/platform-tools/adb"
DERIVED="${DERIVED:-$ROOT/build/shots}"

# R-SHOT-1: no premium feature may appear in a store screenshot. Refuse rather than
# silently produce a listing that sells the paywall.
for flag in ${PREMIUM_HOOKS:-${P}_CLUB ${P}_CLUB_HUB ${P}_PAYWALL}; do
  if [ "${!flag:-}" = "1" ]; then
    echo "REFUSING: premium flag $flag is set in the environment. R-SHOT-1: store screenshots show FREE features only."
    exit 1
  fi
done

sim_udid() {  # sim_udid <name-prefix>: the first available simulator whose name starts with it
  xcrun simctl list devices available -j | python3 -c '
import json, sys
want = sys.argv[1]
for devs in json.load(sys.stdin)["devices"].values():
    for d in devs:
        if d["name"].startswith(want):
            print(d["udid"]); sys.exit(0)
sys.exit(1)' "$1" || { echo "  x no available simulator named '$1*' (set the *_SIM_NAME env)" >&2; exit 1; }
}

fail() { echo "  ✗ $*"; FAILED=$((FAILED + 1)); }
FAILED=0

# A frame is only good if it is the exact store size AND actually shows the app. A splash
# screen, a black frame and a covered window all read as one flat colour. Decoding is left
# to sips + ffmpeg — hand-rolling a PNG reader gets the row filters wrong.
verify() {
  local file="$1" want_w="$2" want_h="$3"
  [ -s "$file" ] || { echo "    missing/empty"; return 1; }
  local w h
  w=$(sips -g pixelWidth  "$file" 2>/dev/null | awk '/pixelWidth/{print $2}')
  h=$(sips -g pixelHeight "$file" 2>/dev/null | awk '/pixelHeight/{print $2}')
  if [ "$w" != "$want_w" ] || [ "$h" != "$want_h" ]; then
    echo "    size ${w}x${h}, expected ${want_w}x${want_h}"; return 1
  fi
  ffmpeg -v error -i "$file" -vf "scale=48:48,format=rgb24" -f rawvideo - 2>/dev/null | python3 -c '
import sys
buf = sys.stdin.buffer.read()
px = [buf[i:i+3] for i in range(0, len(buf) - 2, 3)]
if not px:
    print("    could not sample pixels"); sys.exit(1)
counts = {}
for p in px: counts[p] = counts.get(p, 0) + 1
if max(counts.values()) / len(px) > 0.97:
    print("    >97% one colour — splash, blank or covered"); sys.exit(1)
sys.exit(0)'
}

reinstall() {  # a clean slate so the SEED_RECORDS hook (empty-store-only) actually applies
  local sim="$1" sdk="$2"
  xcrun simctl uninstall "$sim" "$BUNDLE_APPLE" >/dev/null 2>&1
  local app; app=$(find "$DERIVED/Build/Products/Debug-$sdk" -maxdepth 1 -name "$APP_NAME.app" | head -1)
  xcrun simctl install "$sim" "$app" >/dev/null 2>&1
}

shoot_apple() {  # shoot_apple <sim-udid> <outdir> <NN-name> <w> <h> <settle> [ENV=V ...]
  local sim="$1" out="$2" name="$3" w="$4" h="$5" settle="$6"; shift 6
  xcrun simctl terminate "$sim" "$BUNDLE_APPLE" >/dev/null 2>&1
  local env_args=(SIMCTL_CHILD_${P}_NO_GAMECENTER=1 SIMCTL_CHILD_${P}_SKIP_ONBOARD=1 SIMCTL_CHILD_${P}_SCREENED=1)
  for kv in "$@"; do env_args+=("SIMCTL_CHILD_${kv}"); done
  env "${env_args[@]}" xcrun simctl launch "$sim" "$BUNDLE_APPLE" >/dev/null 2>&1
  sleep "$settle"
  xcrun simctl io "$sim" screenshot --type=png "$out/$name.png" >/dev/null 2>&1
  if verify "$out/$name.png" "$w" "$h"; then echo "  ✓ $name"; else fail "$name"; fi
}

shoot_android() {  # shoot_android <outdir> <NN-name> <w> <h> <settle> [--ez k v | --es k v ...]
  local out="$1" name="$2" w="$3" h="$4" settle="$5"; shift 5
  "$ADB" shell am force-stop "$BUNDLE_ANDROID" >/dev/null 2>&1
  "$ADB" shell am start -n "$BUNDLE_ANDROID/$ANDROID_ACTIVITY" "$@" >/dev/null 2>&1
  sleep "$settle"
  "$ADB" exec-out screencap -p > "$out/$name.png" 2>/dev/null
  if verify "$out/$name.png" "$w" "$h"; then echo "  ✓ $name"; else fail "$name"; fi
}

boot_only() {  # exactly one simulator at a time (AGENTS.md)
  for s in $(xcrun simctl list devices booted -j | python3 -c 'import json,sys; print(" ".join(d["udid"] for v in json.load(sys.stdin)["devices"].values() for d in v))'); do
    [ "$s" = "$1" ] || xcrun simctl shutdown "$s" >/dev/null 2>&1
  done
  xcrun simctl boot "$1" >/dev/null 2>&1
  xcrun simctl bootstatus "$1" -b >/dev/null 2>&1
}

build_install() {  # build_install <sim-udid> <sdk-dir>
  echo "  building…"
  xcodebuild build -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" \
    -destination "id=$1" -configuration Debug -derivedDataPath "$DERIVED" 2>&1 \
    | grep -E "error:|BUILD FAILED" | head -5
  local app; app=$(find "$DERIVED/Build/Products/Debug-$2" -maxdepth 1 -name "$APP_NAME.app" | head -1)
  [ -n "$app" ] || { echo "  ✗ no .app built"; exit 1; }
  xcrun simctl install "$1" "$app" >/dev/null 2>&1
}

capture_apple_phoneish() {  # <sim> <sdkdir> <outdir> <w> <h> <include_create>
  local sim="$1" sdk="$2" out="$3" w="$4" h="$5" create="$6"
  mkdir -p "$out"; boot_only "$sim"; build_install "$sim" "$sdk"
  shoot_apple "$sim" "$out" "01-home"        "$w" "$h" 14
  shoot_apple "$sim" "$out" "02-question"    "$w" "$h" 16 "${P}_AUTOPLAY=classic:mixed"
  shoot_apple "$sim" "$out" "03-reveal"      "$w" "$h" 18 "${P}_AUTOPLAY=classic:mixed" "${P}_AUTOPILOT=1" "${P}_AUTOPILOT_CORRECT=1" "${P}_AUTOPILOT_STEPS=1"
  shoot_apple "$sim" "$out" "04-results"     "$w" "$h" 34 "${P}_AUTOPLAY=daily:mixed" "${P}_AUTOPILOT=1" "${P}_AUTOPILOT_CORRECT=1"
  reinstall "$sim" "$sdk"
  shoot_apple "$sim" "$out" "05-records"     "$w" "$h" 18 "${P}_TAB=records" "${P}_SEED_RECORDS=24"
  shoot_apple "$sim" "$out" "06-trivia-night" "$w" "$h" 15 "${P}_NIGHT_SETUP=1"
  shoot_apple "$sim" "$out" "07-pass-and-play" "$w" "$h" 15 "${P}_PARTY=1"
  [ "$create" = "yes" ] && shoot_apple "$sim" "$out" "08-create" "$w" "$h" 22 "${P}_TAB=create"
  return 0
}


# macOS runs the real app on this Mac (there is no Mac "simulator"). Captures the app's
# WINDOW BY ID via tools/mac_window_id.py, not a screen rectangle — a first attempt used
# `-R` and the Android emulator window landed in several frames. Needs a desktop session.
MAC_APP=""
WINID_PY="$ROOT/build/shots/winid/bin/python"

mac_launch() {  # mac_launch [ENV=V ...]
  osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1
  pkill -f "shots/Build/Products/Debug/$APP_NAME.app" >/dev/null 2>&1
  sleep 2
  env "$@" ${P}_NO_GAMECENTER=1 ${P}_SKIP_ONBOARD=1 ${P}_SCREENED=1 \
    "$MAC_APP/Contents/MacOS/$APP_NAME" >/dev/null 2>&1 &
  sleep 13
  osascript -e "tell application \"System Events\" to tell process \"$APP_NAME\"
      set position of window 1 to {0, 45}
      set size of window 1 to {1280, 800}
    end tell" >/dev/null 2>&1
  osascript -e "tell application \"$APP_NAME\" to activate" >/dev/null 2>&1
  # The ad-hoc signature can't read the keychain item the real signed app created, so macOS
  # raises a "<app> wants to use your confidential information" prompt. Window-id capture
  # excludes it from the frame, but dismiss it so it can't hold focus.
  osascript -e 'tell application "System Events" to if exists (process "SecurityAgent") then keystroke return' >/dev/null 2>&1
  sleep 3
}

mac_shot() {  # mac_shot <outdir> <NN-name> [ENV=V ...]
  local out="$1" name="$2"; shift 2
  mac_launch "$@"
  local wid; wid=$("$WINID_PY" "$ROOT/tools/mac_window_id.py" 2>/dev/null)
  if [ -z "$wid" ]; then fail "$name (no app window found)"; return; fi
  screencapture -x -o -l "$wid" "$out/$name.png"
  if verify "$out/$name.png" 2560 1600; then echo "  ✓ $name"; else fail "$name"; fi
}

run_macos() {
  echo "== Mac =="
  local out="$ROOT/branding/store-screenshots/macos"; mkdir -p "$out"
  # A tiny venv just for the window-id lookup (Quartz isn't in the system python3).
  if [ ! -x "$WINID_PY" ]; then
    python3 -m venv "$ROOT/build/shots/winid" >/dev/null 2>&1
    "$ROOT/build/shots/winid/bin/pip" install -q pyobjc-framework-Quartz >/dev/null 2>&1
  fi
  echo "  building…"
  xcodebuild build -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" \
    -destination 'platform=macOS' -configuration Debug -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO ENABLE_APP_SANDBOX=NO 2>&1 \
    | grep -E "error:|BUILD FAILED" | head -5
  MAC_APP=$(find "$DERIVED/Build/Products/Debug" -maxdepth 1 -name "$APP_NAME.app" | head -1)
  [ -n "$MAC_APP" ] || { echo "  x no Mac .app built"; return 1; }
  # Restricted entitlements (game-center, applesignin) can't be ad-hoc signed, and signing
  # WITH them makes launchd refuse the process. The store screens need neither.
  codesign -s - --force --deep "$MAC_APP" >/dev/null 2>&1

  mac_shot "$out" "01-home"
  mac_shot "$out" "02-question"     ${P}_AUTOPLAY=classic:mixed
  mac_shot "$out" "03-reveal"       ${P}_AUTOPLAY=classic:mixed ${P}_AUTOPILOT=1 ${P}_AUTOPILOT_CORRECT=1 ${P}_AUTOPILOT_STEPS=1
  mac_shot "$out" "04-results"      ${P}_AUTOPLAY=daily:mixed ${P}_AUTOPILOT=1 ${P}_AUTOPILOT_CORRECT=1
  mac_shot "$out" "05-records"      ${P}_TAB=records ${P}_SEED_RECORDS=24
  mac_shot "$out" "06-trivia-night" ${P}_TAB=live
  mac_shot "$out" "08-create"       ${P}_TAB=create
  osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1
}

PLATFORM="${1:?usage: capture-screenshots.sh <ios|ipad|tvos|macos|android|android-tablet|all>}"

run_ios() {
  echo "== iPhone 6.9\" =="
  local sim; sim=$(sim_udid "$IPHONE_SIM_NAME") || return 1
  capture_apple_phoneish "$sim" iphonesimulator \
    "$ROOT/branding/store-screenshots/ios-iphone-6.9" 1320 2868 yes
}
run_ipad() {
  echo "== iPad 13\" =="
  local sim; sim=$(sim_udid "$IPAD_SIM_NAME") || return 1
  capture_apple_phoneish "$sim" iphonesimulator \
    "$ROOT/branding/store-screenshots/ios-ipad-13" 2064 2752 yes
}
run_tvos() {
  echo "== Apple TV =="
  local sim; sim=$(sim_udid "$TV_SIM_NAME") || return 1
  local out="$ROOT/branding/store-screenshots/tvos"
  mkdir -p "$out"; boot_only "$sim"; build_install "$sim" appletvsimulator
  shoot_apple "$sim" "$out" "01-home"         3840 2160 16
  shoot_apple "$sim" "$out" "02-question"     3840 2160 18 "${P}_AUTOPLAY=classic:mixed"
  shoot_apple "$sim" "$out" "03-reveal"       3840 2160 20 "${P}_AUTOPLAY=classic:mixed" "${P}_AUTOPILOT=1" "${P}_AUTOPILOT_CORRECT=1" "${P}_AUTOPILOT_STEPS=1"
  shoot_apple "$sim" "$out" "04-results"      3840 2160 34 "${P}_AUTOPLAY=daily:mixed" "${P}_AUTOPILOT=1" "${P}_AUTOPILOT_CORRECT=1"
  reinstall "$sim" appletvsimulator
  shoot_apple "$sim" "$out" "05-records"      3840 2160 20 "${P}_TAB=records" "${P}_SEED_RECORDS=24"
  shoot_apple "$sim" "$out" "06-trivia-night" 3840 2160 17 "${P}_NIGHT_SETUP=1"
}
run_android() {  # run_android <avd> <outdir> <w> <h>
  echo "== Android: $1 =="
  local out="$2"; mkdir -p "$out"
  "$ADB" emu kill >/dev/null 2>&1; sleep 3
  nohup "$ANDROID_HOME/emulator/emulator" -avd "$1" -no-snapshot-load -no-boot-anim >/dev/null 2>&1 &
  "$ADB" wait-for-device
  until [ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do sleep 3; done
  (cd android && ./gradlew installDebug -q >/dev/null 2>&1)
  local SKIP=(--ez ${AP}_skip_onboard true --ez ${AP}_screened true)
  shoot_android "$out" "01-home"          "$3" "$4" 32 "${SKIP[@]}"
  shoot_android "$out" "02-question"      "$3" "$4" 26 "${SKIP[@]}" --es ${AP}_autoplay classic:mixed
  shoot_android "$out" "03-reveal"        "$3" "$4" 28 "${SKIP[@]}" --es ${AP}_autoplay classic:mixed --ez ${AP}_autopilot true --ez ${AP}_autopilot_correct true --ei ${AP}_autopilot_steps 1
  shoot_android "$out" "04-results"       "$3" "$4" 44 "${SKIP[@]}" --es ${AP}_autoplay daily:mixed --ez ${AP}_autopilot true --ez ${AP}_autopilot_correct true
  "$ADB" shell pm clear "$BUNDLE_ANDROID" >/dev/null 2>&1   # the seeder only seeds an EMPTY store
  shoot_android "$out" "05-records"       "$3" "$4" 30 "${SKIP[@]}" --es ${AP}_tab records --ei ${AP}_seed_records 24
  shoot_android "$out" "06-trivia-night"  "$3" "$4" 26 "${SKIP[@]}" --ez ${AP}_night_setup true
  shoot_android "$out" "07-pass-and-play" "$3" "$4" 26 "${SKIP[@]}" --ez ${AP}_party true
  shoot_android "$out" "08-create"        "$3" "$4" 26 "${SKIP[@]}" --es ${AP}_tab create
}

case "$PLATFORM" in
  ios) run_ios ;;
  macos) run_macos ;;
  ipad) run_ipad ;;
  tvos) run_tvos ;;
  android) run_android "$PHONE_AVD" "$ROOT/branding/store-screenshots/android-phone" 1280 2856 ;;
  android-tablet) run_android "$TABLET_AVD" "$ROOT/branding/store-screenshots/android-tablet" 1600 2560 ;;
  all) run_ios; run_ipad; run_tvos;
       run_android "$PHONE_AVD" "$ROOT/branding/store-screenshots/android-phone" 1280 2856
       run_android "$TABLET_AVD" "$ROOT/branding/store-screenshots/android-tablet" 1600 2560 ;;
  *) echo "unknown platform '$PLATFORM'"; exit 1 ;;
esac

echo
if [ "$FAILED" -gt 0 ]; then echo "$FAILED frame(s) FAILED verification — see above."; exit 1; fi
echo "All frames verified."
