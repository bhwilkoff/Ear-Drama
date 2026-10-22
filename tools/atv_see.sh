#!/usr/bin/env bash
# Capture the Apple TV screen and REFUSE to return a frame nobody can read.
#
# A sweep that returns "row not found" is worthless if the screenshots were
# blank. That happened: twelve steps, no hits, and every frame was a black screen
# — the device had slept. A null result from a blind instrument is
# indistinguishable from a real absence, so the instrument has to say when it
# cannot see.
#
# Three gates, in order, each answering a different question:
#   1. Is the Apple TV ON? Asked of the TV (pyatv power_state), never inferred from
#      the pixels: a sleeping Apple TV returns a valid, black PNG. (If the launch
#      SUCCEEDS but every capture is black, the TELEVISION is off or on another
#      input — the Apple TV cannot fix that; pyatv turn_on only sends CEC.)
#   2. Is the frame FRESH? The target is deleted first and a file older than 60 s
#      is refused — an old PNG reasoned about as current is a confident wrong answer.
#   3. Is it READABLE, and is it OUR app? OCR line count, not byte size (bytes
#      depend on resolution and content; a text-light screen of ours can be small
#      and a busy black one large). A READABLE frame of the WRONG APP is worse than
#      a blank one: the tvOS home screen once survived every check and a sweep
#      reported missing shelves while driving the system UI.
#
# Usage: bash tools/atv_see.sh <out.png> [min_ocr_lines]
#   ATV_DEVICE   bench name or UDID (default: bench entry "atv")
#   ATV_EXPECT   regex of words YOUR app's chrome shows (default: app_config
#                APP_ANCHOR_RX); ATV_EXPECT=- skips the wrong-screen check
# Exit: 0 ok · 1 blind (off/stale/unreadable) · 2 wrong screen · 3 instrument missing
set -uo pipefail
OUT="${1:?usage: atv_see.sh <out.png> [min_ocr_lines]}"
MIN_LINES="${2:-4}"
HERE="$(cd "$(dirname "$0")" && pwd)"
NAME="${ATV_DEVICE:-atv}"

# One OCR binary for every runner (app_config.OCR_BIN), built on first use.
OCR="$(cd "$HERE" && python3 -c 'import devharness as d, app_config as c; ok, why = d.ensure_ocr(); print(c.OCR_BIN if ok else "")')"
if [ -z "$OCR" ] || [ ! -x "$OCR" ]; then
  echo "BLIND: the OCR instrument is unavailable (swiftc -O tools/ScreenOCR/main.swift -o build/bin/screenocr)" >&2
  exit 3
fi

bash "$HERE/atv_shot.sh" "$NAME" "$OUT" >&2
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "BLIND: no fresh capture of $NAME (atv_shot exit $rc)" >&2
  exit 1
fi

txt=$("$OCR" "$OUT" 2>/dev/null)
n=$(printf '%s' "$txt" | python3 -c 'import json,sys
try: print(len(json.loads(sys.stdin.readline()).get("allText", [])))
except Exception: print(-1)')
if [ "$n" -lt 0 ]; then
  echo "BLIND: OCR could not read $OUT — the instrument failed, not the screen" >&2
  exit 3
fi
if [ "$n" -lt "$MIN_LINES" ]; then
  echo "BLIND: $OUT has $n OCR lines (<$MIN_LINES) — dark scene, sleeping TV, or TV off/other input" >&2
  exit 1
fi

EXPECT="${ATV_EXPECT:-$(cd "$HERE" && python3 -c 'import app_config; print(app_config.APP_ANCHOR_RX)')}"
if [ "$EXPECT" != "-" ] && ! printf '%s' "$txt" | EXPECT="$EXPECT" python3 -c 'import os, re, sys
sys.exit(0 if re.search(os.environ["EXPECT"], sys.stdin.read(), re.I) else 1)'; then
  # Python regex, not grep -E: the home-screen pattern uses \d, which ERE lacks.
  if printf '%s' "$txt" | (cd "$HERE" && python3 -c 'import re, sys, app_config
sys.exit(0 if re.search(app_config.TVOS_HOME_RX, sys.stdin.read(), re.I) else 1)'); then
    echo "WRONG SCREEN: $OUT is the tvOS home screen, not this app" >&2
  else
    echo "WRONG SCREEN: $OUT does not match ATV_EXPECT ($EXPECT)" >&2
  fi
  exit 2
fi
exit 0
