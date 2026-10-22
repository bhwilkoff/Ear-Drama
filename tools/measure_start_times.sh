#!/bin/zsh
# How long does an item take to reach its first frame ON THE APPLE TV?
#
# The start-time promise (from Archive Watch, whose owner set it): "Films should
# start within 30 seconds. Waiting longer than that will lose users almost every
# time." That promise had never been
# measured across a sample — only asserted. The first three titles measured
# gave 3.7s, >75s and >75s, so the spread is the whole story and a single
# title tells you nothing.
#
# Measures setupPlayer -> itemReady from the app's own diag, which is the
# frame the viewer waits for, not a curl of the URL.
#
# Usage: tools/measure_start_times.sh <itemID> [itemID...]
#
# The app must honour the env hooks below (APP_START_ITEM, APP_AUTOPLAY, ...),
# write its diag file to APP_DIAG_PATH in its container, and log a launch marker
# plus `setupPlayer item=<id>` / `itemReady` / `itemFailed` lines.
set -u
# The device comes from the bench (tools/bench.py), never a hardcoded UDID.
DEV=${APP_DEVICE:-$(python3 "$(dirname "$0")/bench.py" get "${ATV_DEVICE:-atv}" udid 2>/dev/null)}
[ -n "$DEV" ] || { echo "no Apple TV udid: set APP_DEVICE or add an 'atv' entry to the bench manifest"; exit 1; }
WAIT=${APP_START_WAIT:-80}
ATV=${APP_ATV:-/tmp/atv.sh}
DIAG=${APP_DIAG_PATH:-Library/Caches/appdiag.log}
LAUNCH_MARK=${APP_LAUNCH_MARK:-APPLIFE LAUNCH}
BUNDLE=${APP_BUNDLE:-$(python3 -c "import sys; sys.path.insert(0, '$(dirname "$0")'); import app_config; print(app_config.APPLE_BUNDLE_ID)" 2>/dev/null || echo com.example.appname)}

# Interleaving alternates the hedged-probe arm title by title, so both arms
# meet the SAME archive.org weather. Comparing two sequential blocks does not
# work here and the numbers proved it: one film went from no-frame-in-75s to
# 5.8s within an hour, so a block-vs-block delta measures the hour. This is a
# stronger requirement than the repeated-trials rule — the arms must be
# interleaved, not merely repeated.
# APP_PAIRED=1 measures EACH film under BOTH arms, back to back, alternating
# which goes first. Alternating the arm per TITLE was the first attempt and it
# is wrong for the same reason block-vs-block was: it compares different films.
# Pairing controls for the film AND keeps the two readings within a minute of
# each other, which is the only way to hold node weather roughly constant.
PAIRED=${APP_PAIRED:-0}
film_index=0
printf '%-46s %10s %s\n' "film" "to first frame" "arm"
for id in "$@"; do
  film_index=$((film_index+1))
  if [ "$PAIRED" = "1" ]; then
    if [ $((film_index % 2)) -eq 0 ]; then ARMS="1 0"; else ARMS="0 1"; fi
  else
    ARMS=${APP_HEDGE_PROBE:-0}
  fi
  for HEDGE in ${=ARMS}; do
  "$ATV" turn_on >/dev/null 2>&1; sleep 2; "$ATV" menu >/dev/null 2>&1; sleep 2
  xcrun devicectl device process launch --terminate-existing --device "$DEV" \
    -e "{\"APP_START_ITEM\":\"$id\",\"APP_AUTOPLAY\":\"1\",\"APP_DIAG_FILE\":\"1\",\"APP_PLAYBACK_DIAG\":\"1\",\"APP_NO_RESUME\":\"1\",\"APP_NO_CAPTIONS\":\"1\",\"APP_HEDGE_PROBE\":\"$HEDGE\"}" \
    "$BUNDLE" >/dev/null 2>&1
  sleep "$WAIT"
  log=$(mktemp)
  xcrun devicectl device copy from --device "$DEV" --domain-type appDataContainer \
    --domain-identifier "$BUNDLE" --source "$DIAG" \
    --destination "$log" >/dev/null 2>&1
  # Only THIS launch's lines: the diag file accumulates across runs and an
  # older session's itemReady would score the current one as instant.
  awk -v mark="$LAUNCH_MARK" 'index($0, mark){n=NR} {l[NR]=$0} END{for(i=n;i<=NR;i++) print l[i]}' "$log" > "$log.s"
  python3 - "$id" "$log.s" "$HEDGE" <<'PY'
import re, sys
film, path, arm = sys.argv[1], sys.argv[2], ("hedged" if sys.argv[3] == "1" else "single")
t = open(path, errors="ignore").read()
setup = re.search(r"^(\d+\.\d+) .*setupPlayer item=" + re.escape(film), t, re.M)
ready = re.search(r"^(\d+\.\d+) .*itemReady", t, re.M)
fail  = re.search(r"^(\d+\.\d+) .*itemFailed", t, re.M)
fb    = "fallback" if "FALLBACK to lower-quality" in t else ""
if setup and ready:
    print(f"{film[:46]:46} {float(ready.group(1))-float(setup.group(1)):9.1f}s {arm} {fb}")
elif setup and fail:
    print(f"{film[:46]:46} {'FAILED':>10} at {float(fail.group(1))-float(setup.group(1)):.0f}s {arm} {fb}")
else:
    print(f"{film[:46]:46} {'NO FRAME':>10} {arm} (setup seen: " + ("yes" if setup else "NO") + ")")
PY
  rm -f "$log" "$log.s"
  done
done
