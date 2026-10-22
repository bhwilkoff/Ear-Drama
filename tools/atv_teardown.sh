#!/bin/bash
# LEAVE NOTHING RUNNING. Terminates the app on an Apple device and, for an Apple
# TV, powers the box back off and READS THE STATE BACK.
#
# Written after a film was left playing unmuted on the owner's Apple TV for an
# hour — it routed to speakers across the house. The dev door started the engine
# and polled until told to stop, and nothing told it to stop once the screenshot
# was taken. A rule you intend to follow is not a safeguard: a harness that touches
# someone's living room cleans up as a STEP, with an assertion, not an intention.
#
#   tools/atv_teardown.sh <udid> [pyatv-address pyatv-id]
#   tools/atv_teardown.sh --device <bench-name> [--keep-power]
#
# The executable name comes from APP_EXECUTABLE, else tools/app_config.py.
# (The Python runners call apple_device.teardown(), which is the same procedure
# and restores the power state the run FOUND; this script powers a TV off.)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
[ -n "${DEVELOPER_DIR:-}" ] && export DEVELOPER_DIR
PYATV="${PYATV:-$HOME/.pyatv-venv/bin/atvremote}"
KEEP_POWER=0

if [ "${1:-}" = "--device" ]; then
  NAME="${2:?bench name}"
  [ "${3:-}" = "--keep-power" ] && KEEP_POWER=1
  if [ "$(python3 "$HERE/bench.py" role "$NAME")" = "owner-personal-never-touch" ]; then
    echo "REFUSED: $NAME is role owner-personal-never-touch"; exit 1
  fi
  DEV="$(python3 "$HERE/bench.py" get "$NAME" udid)" || { echo "no udid for $NAME"; exit 1; }
  ADDR="$(python3 "$HERE/bench.py" get "$NAME" address 2>/dev/null || true)"
  PYID="$(python3 "$HERE/bench.py" get "$NAME" pyatv_id 2>/dev/null || true)"
else
  DEV="${1:?device udid (or --device <bench-name>)}"
  ADDR="${2:-}"
  PYID="${3:-}"
fi
EXE="${APP_EXECUTABLE:-$(cd "$HERE" && python3 -c 'import app_config; print(app_config.APPLE_EXECUTABLE)')}"

# 1. Terminate by pid — `process terminate` takes --pid, never a bundle id (a wrong
#    flag prints usage and exits, which reads like success).
#
#    MATCH THE PATH, NOT THE BUNDLE ID. `devicectl device info processes` prints
#    EXECUTABLE PATHS (`1821  /private/var/.../<Exe>.app/<Exe>`); the bundle id
#    appears nowhere in that line, so a grep for it never matches and the script
#    reports "not running" about a live process. AND THE LINE IS COLUMN-PADDED: a
#    match anchored with a bare `$` matches nothing either, because devicectl pads
#    the path with trailing spaces. Two different greps gave the same false
#    all-clear before this one. Hence `[[:space:]]*$`, and the verification below
#    uses this SAME function rather than a second hand-written pattern.
#
#    PlugIns/ is excluded: an app extension (Top Shelf, widget) is launched by the
#    SYSTEM, is not part of a test run, and killing it is not ours to do.
app_pids() {
  xcrun devicectl device info processes --device "$DEV" 2>/dev/null \
    | grep -E "[[:space:]]/.*${EXE}\.app/${EXE}[[:space:]]*$" \
    | grep -v "/PlugIns/" | awk '{print $1}'
}
PIDS="$(app_pids)"
if [ -n "$PIDS" ]; then
  for PID in $PIDS; do
    xcrun devicectl device process terminate --device "$DEV" --pid "$PID" >/dev/null 2>&1
  done
  sleep 3
  # ASK THE DEVICE, never the terminate's own output. A signal sent is not a
  # process gone.
  STILL="$(app_pids | wc -l | tr -d ' ')"
  if [ "$STILL" -eq 0 ]; then
    echo "terminated $EXE (pids $(echo $PIDS)) on $DEV — verified gone"
  else
    echo "FAILED to terminate $EXE on $DEV — STILL RUNNING ($(echo $(app_pids)))"
    exit 1
  fi
else
  echo "$EXE not running on $DEV"
fi

# 2. For an Apple TV, put the box back as it was found: off, and verified off.
if [ "$KEEP_POWER" -eq 0 ] && [ -n "$PYID" ] && [ -x "$PYATV" ]; then
  ARGS=(--id "$PYID" --protocol companion)
  [ -n "$ADDR" ] && ARGS=(--address "$ADDR" "${ARGS[@]}")
  "$PYATV" "${ARGS[@]}" turn_off >/dev/null 2>&1
  sleep 4
  STATE=$("$PYATV" "${ARGS[@]}" power_state 2>&1 | tail -1)
  echo "power now: $STATE"
  case "$STATE" in
    *Off) ;;
    *) echo "WARNING: $DEV did not power off — check it by hand"; exit 1 ;;
  esac
fi
