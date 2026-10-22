#!/bin/sh
# Capture one app's window for the course's screenshots, with nothing else
# on the screen in the picture.
#
#   sh tools/shot.sh antigravity plan-review
#   sh tools/shot.sh claude code-tab-manual
#
# The first word is the app (antigravity or claude), the second is the
# screen's name. The picture goes to docs/images/agents/<app>-<name>.png.
# Before each shot, check the window shows no private project, name, or
# number; use a demo project (for example ~/Documents/hs-demo/reading-nook).
set -e
cd "$(dirname "$0")/.."
case "$1" in
  antigravity) owner=Antigravity ;;
  claude) owner=Claude ;;
  *) echo "First word: antigravity or claude."; exit 1 ;;
esac
[ -n "$2" ] || { echo "Second word: the screen's name, like plan-review."; exit 1; }
id=$(swift -e "
import CoreGraphics
let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for w in l where (w[kCGWindowOwnerName as String] as? String) == \"$owner\" && (w[kCGWindowLayer as String] as? Int ?? 1) <= 0 {
  print(w[kCGWindowNumber as String] ?? 0); break
}" 2>/dev/null)
[ -n "$id" ] || { echo "No $owner window is open on screen."; exit 1; }
out="docs/images/agents/$1-$2.png"
screencapture -x -o -l "$id" "$out"
echo "Saved $out"
