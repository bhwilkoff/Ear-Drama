#!/usr/bin/env bash
# Capture a FULL Mac App Store screenshot set, driving the app to each screen via the
# APP_START_TAB / APP_START_ITEM launch hooks.
# Each shot: relaunch the app on the target screen, size its window to 16:10, wait for art to load,
# capture the window, and frame it onto a 2880x1800 brand canvas (tools/mac-screenshots.sh logic).
#
# USAGE:  tools/mac-shotset.sh /path/to/<App>.app   [ITEM1=<id> ITEM2=<id> for detail shots]
# Needs macOS Screen Recording permission for the terminal. Output: ~/Desktop/<APP_NAME>-Mac-Screenshots/
# Captures are WINDOW-ID only (tools/mac_window_shot.swift, owner matched exactly). There
# is deliberately no region (-R) or full-screen fallback: both photograph whatever else is
# on the display, which has included a terminal and personal documents.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:?usage: mac-shotset.sh /path/to/<app>.app}"
# Derive the executable name from the bundle (it can differ from the display name).
EXE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist" 2>/dev/null)"
BIN="$APP/Contents/MacOS/$EXE"
[ -x "$BIN" ] || { echo "no binary at $BIN"; exit 1; }
OUTDIR="$HOME/Desktop/${APP_NAME:-AppName}-Mac-Screenshots"
mkdir -p "$OUTDIR"
SIZE="${SIZE:-2880x1800}"; W="${SIZE%x*}"; H="${SIZE#*x}"
BG="${BG:-#0A0A0A}"; MARGIN="${MARGIN:-0.04}"
WINW="${WINW:-1680}"; WINH="${WINH:-1050}"   # 16:10 window so the framed result is crisp + fills the canvas
LOG="build/qa/mac-shotset.log"; mkdir -p build/qa
ART_WAIT="${ART_WAIT:-24}"                    # seconds to let posters/backdrops load over the network
# Python with Pillow for the canvas framing (system python3 may lack PIL; the play venv has it).
PYBIN="tools/.play-venv/bin/python"; [ -x "$PYBIN" ] || PYBIN="python3"

# `|| true`: pkill exits 1 when nothing matches, which under `set -e` would abort the
# whole run at the first quit (when no app is running yet). No-match is not an error here.
quit() { pkill -f "$APP/Contents/MacOS/" 2>/dev/null || true; sleep 1.5; }
# The window OWNER name (display name), matched exactly.
OWNER="${APP_NAME:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$APP/Contents/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$APP/Contents/Info.plist" 2>/dev/null)}"
WINSHOT="$(python3 -c 'import sys; sys.path.insert(0, "tools"); import devharness as d, app_config as c; ok, why = d.ensure_winshot(); print(c.WINSHOT_BIN if ok else "")')"
[ -x "$WINSHOT" ] || { echo "no window-capture tool (swiftc -O tools/mac_window_shot.swift -o build/bin/winshot)"; exit 1; }

size_window() {
  osascript >/dev/null 2>&1 <<OSA || true
tell application "System Events"
  set procs to (every process whose name is "$EXE" and visible is true)
  if procs is {} then return
  set p to item 1 of procs
  set frontmost of p to true
  try
    set position of front window of p to {100, 60}
    set size of front window of p to {$WINW, $WINH}
  end try
end tell
OSA
}

frame_capture() {  # $1 = output name
  local name="$1" raw out bounds bytes
  raw="$(mktemp -t appshot).png"; out="$OUTDIR/$name.png"
  # Window by id, owner matched EXACTLY. No region, no full screen, no guess.
  if ! "$WINSHOT" "$OWNER" "" "$raw" --min-width 600; then
    echo "  !! $name: no on-screen window owned by exactly \"$OWNER\" — skipped (nothing captured)" >&2
    rm -f "$raw"; return 0
  fi
  bytes=$(stat -f%z "$raw" 2>/dev/null || echo 0)
  [ "$bytes" -lt 5000 ] && echo "WARNING: $name capture tiny ($bytes B) — grant Screen Recording permission." >&2
  "$PYBIN" - "$raw" "$out" "$W" "$H" "$BG" "$MARGIN" <<'PY'
import sys
from PIL import Image
raw,out,W,H,bg,margin=sys.argv[1],sys.argv[2],int(sys.argv[3]),int(sys.argv[4]),sys.argv[5],float(sys.argv[6])
def hx(s):s=s.lstrip('#');return tuple(int(s[i:i+2],16) for i in (0,2,4))
c=Image.new("RGB",(W,H),hx(bg)); s=Image.open(raw).convert("RGB")
m=int(min(W,H)*margin); mw,mh=W-2*m,H-2*m; sw,sh=s.size; sc=min(mw/sw,mh/sh)
nw,nh=max(1,int(sw*sc)),max(1,int(sh*sc)); s=s.resize((nw,nh),Image.LANCZOS)
c.paste(s,((W-nw)//2,(H-nh)//2)); c.save(out,"PNG"); print(f"  wrote {out} ({W}x{H})")
PY
  rm -f "$raw"
}

launch() {  # env assignments... ; launches BIN detached with those env vars
  quit
  env "$@" "$BIN" >"$LOG" 2>&1 &
  sleep 6                 # app start + window
  size_window
}

shot() {  # $1 name ; rest = env assignments
  local name="$1"; shift
  echo "→ $name  [$*]"
  launch "$@"
  size_window
  sleep "$ART_WAIT"       # let catalog art load
  size_window
  frame_capture "$name"
}

echo "== warm-up launch (download + cache the full catalog DB + art) =="
quit
"$BIN" >"$LOG" 2>&1 &
sleep "${WARM:-90}"
quit

# Detail shots take item ids from the environment (pick items with real artwork —
# a store shot of a placeholder poster is a store shot of a bug).
ITEM1="${ITEM1:-}"; ITEM2="${ITEM2:-}"

# FILL IN: one line per store screen, using your app's launch doors.
shot 01-home           APP_START_TAB=home
shot 02-search         APP_START_TAB=search
shot 03-settings       APP_START_TAB=settings
[ -n "$ITEM1" ] && shot 04-detail APP_START_ITEM="$ITEM1"
[ -n "$ITEM2" ] && shot 05-detail-2 APP_START_ITEM="$ITEM2"
quit

echo "== done. Set in $OUTDIR =="
ls -la "$OUTDIR"
