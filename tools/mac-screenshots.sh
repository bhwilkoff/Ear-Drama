#!/usr/bin/env bash
# Mac App Store screenshot helper.
#
# App Store requires Mac screenshots at EXACTLY one 16:10 size: 1280x800, 1440x900,
# 2560x1600, or 2880x1800 (PNG/JPEG, 1-10 shots). A raw window grab is never exactly that
# size (title bar, rounded corners, shadow), so this captures the app's frontmost
# window (by window id) and FRAMES it — scaled to fit, centered on a solid brand canvas — at the exact size.
#
# USAGE (run once per screen, with the app already showing that screen):
#   1. Launch the RELEASE build of the app and navigate to the screen you want.
#      Do NOT set any APP_* launch-door env vars — the store build must look like the real app.
#   2. Run:  tools/mac-screenshots.sh 01-home
#      It captures the app's frontmost window by id and writes
#      ~/Desktop/<APP_NAME>-Mac-Screenshots/01-home.png at the target size.
#   3. Repeat for each screen.
#
# REQUIREMENT: the terminal/app you run this from needs macOS **Screen Recording** permission
# (System Settings ▸ Privacy & Security ▸ Screen Recording) or the grab is blank. The script
# checks and tells you if it looks empty.
#
# Tunables via env: SIZE=2880x1800 (default) | 2560x1600 | 1440x900 | 1280x800
#                   BG=#0A0A0A (canvas) ; MARGIN=0.06 (fraction of the long edge)
set -euo pipefail

NAME="${1:?usage: mac-screenshots.sh <output-name-without-extension>}"
SIZE="${SIZE:-2880x1800}"
BG="${BG:-#0A0A0A}"
MARGIN="${MARGIN:-0.06}"
# The window OWNER name, matched exactly (APP_NAME env, else tools/app_config.py).
APP="${APP_NAME:-$(cd "$(dirname "$0")" && python3 -c 'import app_config; print(app_config.APPLE_APP_NAME)')}"
OUTDIR="$HOME/Desktop/${APP_NAME:-AppName}-Mac-Screenshots"
mkdir -p "$OUTDIR"
RAW="$(mktemp -t appshot).png"
OUT="$OUTDIR/$NAME.png"

W="${SIZE%x*}"; H="${SIZE#*x}"

# Capture the app's WINDOW by id, owner matched EXACTLY — never a region, never the
# full screen, and no interactive fallback. A region grab photographs whatever is at
# those coordinates (a terminal, somebody's documents); an owner match by "contains"
# picks up any process whose name shares a word. tools/mac_window_shot.swift does the
# exact-owner lookup and refuses rather than guessing.
WINSHOT="$(cd "$(dirname "$0")" && python3 -c 'import devharness as d, app_config as c; ok, why = d.ensure_winshot(); print(c.WINSHOT_BIN if ok else "")')"
[ -x "$WINSHOT" ] || { echo "no window-capture tool (swiftc -O tools/mac_window_shot.swift -o build/bin/winshot)" >&2; exit 1; }
if ! "$WINSHOT" "$APP" "" "$RAW" --min-width 600; then
  echo "no on-screen window owned by exactly \"$APP\" — launch it (and set APP_NAME if its display name differs)" >&2
  exit 1
fi

# Sanity: a blank/black grab usually means Screen Recording permission is missing.
BYTES=$(stat -f%z "$RAW" 2>/dev/null || echo 0)
if [[ "$BYTES" -lt 5000 ]]; then
  echo "WARNING: the capture is tiny ($BYTES bytes) — grant Screen Recording permission to your terminal/Xcode and retry." >&2
fi

# Frame onto an exact-size brand canvas (Pillow — already used by the cover pipeline).
python3 - "$RAW" "$OUT" "$W" "$H" "$BG" "$MARGIN" <<'PY'
import sys
from PIL import Image
raw, out, W, H, bg, margin = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5], float(sys.argv[6])
def hex2rgb(s):
    s = s.lstrip('#')
    return tuple(int(s[i:i+2], 16) for i in (0, 2, 4))
canvas = Image.new("RGB", (W, H), hex2rgb(bg))
shot = Image.open(raw).convert("RGB")
m = int(min(W, H) * margin)
maxw, maxh = W - 2*m, H - 2*m
sw, sh = shot.size
scale = min(maxw / sw, maxh / sh)
nw, nh = max(1, int(sw*scale)), max(1, int(sh*scale))
shot = shot.resize((nw, nh), Image.LANCZOS)
canvas.paste(shot, ((W - nw)//2, (H - nh)//2))
canvas.save(out, "PNG")
print(f"wrote {out} ({W}x{H})")
PY
rm -f "$RAW"
