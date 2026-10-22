#!/bin/bash
# A device screenshot that CANNOT hand back stale evidence (any devicectl device:
# Apple TV, iPhone, iPad).
#
# Written after reading a PNG from an earlier attempt and reasoning about it as
# though it were current. The capture had failed, the grep for its success line
# found nothing, and the old file was still on disk — so the only tell was the
# clock rendered inside the image. A verification instrument that can silently
# return old evidence is worse than none: it produces confident wrong conclusions.
#
# So: delete the target, capture, and REFUSE unless a new file exists. And for an
# Apple TV with a remote configured, ask the TV whether it is ON first — a sleeping
# Apple TV returns a valid, black PNG, which no pixel test can tell from a dark scene.
#
#   tools/atv_shot.sh <bench-name | udid> <destination.png>
#
# Exit: 0 fresh shot; 1 capture failed or stale; 3 the TV reports Off (not captured).
set -u
DEVARG="${1:?bench name or device udid}"
OUT="${2:?destination png}"
HERE="$(cd "$(dirname "$0")" && pwd)"
[ -n "${DEVELOPER_DIR:-}" ] && export DEVELOPER_DIR

# Resolve a bench name to its UDID; a raw UDID passes through.
DEV="$(python3 "$HERE/bench.py" get "$DEVARG" udid 2>/dev/null || true)"
DEV="${DEV:-$DEVARG}"
ROLE="$(python3 "$HERE/bench.py" role "$DEVARG" 2>/dev/null || echo unknown)"
if [ "$ROLE" = "owner-personal-never-touch" ]; then
  echo "REFUSED: $DEVARG is role owner-personal-never-touch"; exit 1
fi

PLATFORM="$(python3 "$HERE/bench.py" get "$DEVARG" platform 2>/dev/null || true)"
if [ "$PLATFORM" = "tvos" ]; then
  STATE="$(python3 "$HERE/apple_device.py" power --device "$DEVARG" 2>/dev/null | tail -1)"
  case "$STATE" in
    off) echo "SHOT REFUSED — $DEVARG reports power Off; a capture now is a black frame"
         echo "  (wake it with: python3 tools/apple_device.py wake --device $DEVARG — ask first"
         echo "   if it is a TV in someone's room)"; exit 3 ;;
    on) ;;
    *) echo "note: power state unknown (no pyatv id/venv) — the frame alone cannot prove the TV was on" ;;
  esac
fi

rm -f "$OUT"
mkdir -p "$(dirname "$OUT")"
ERR=$(xcrun devicectl device capture screenshot --device "$DEV" --destination "$OUT" 2>&1)
rc=$?

if [ ! -s "$OUT" ]; then
  echo "SHOT FAILED (rc=$rc) — no file written to $OUT"
  # The reason matters: a dead screenshot service and a dead connection need
  # opposite responses (switch device vs. re-pair / restart the Mac).
  echo "$ERR" | grep -iE "error|invalidated|canceled" | head -3
  exit 1
fi

# Freshness, belt and braces: a file that exists but predates this call is the
# exact failure this script was written for.
AGE=$(( $(date +%s) - $(stat -f %m "$OUT") ))
if [ "$AGE" -gt 60 ]; then
  echo "SHOT STALE — $OUT is ${AGE}s old; the capture did not overwrite it"
  exit 1
fi
echo "SHOT OK $OUT ($(( $(stat -f %z "$OUT") / 1024 )) KB, ${AGE}s old)"
