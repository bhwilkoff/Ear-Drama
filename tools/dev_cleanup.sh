#!/usr/bin/env bash
# dev_cleanup.sh — find, and optionally stop, development processes this repo's
# tools leave running on the machine; and run an AUDIBLE suite without leaving the
# machine's volume changed.
#
# WHY. A machine that "slowed down" turned out, once, to be two render processes
# spinning at 98% CPU for three and a half days; another time a Gradle release
# build; another, three `python -m http.server` previews, two of them older than
# two days. None was noticed by whoever started it, because a process that is
# merely IDLE is invisible until something else needs the machine. And an audible
# test suite once finished with the system volume left at 100.
#
#   tools/dev_cleanup.sh                  # report only
#   tools/dev_cleanup.sh --stop           # stop what it finds
#   tools/dev_cleanup.sh volume-guard -- <cmd> [args...]
#       run <cmd>, then restore the system output volume and mute state exactly as
#       found — on normal exit, error, Ctrl-C or kill (EXIT/INT/TERM trap) — and
#       read the restored value back.
set -uo pipefail

if [ "${1:-}" = "volume-guard" ]; then
  shift
  [ "${1:-}" = "--" ] && shift
  [ $# -gt 0 ] || { echo "usage: dev_cleanup.sh volume-guard -- <cmd> [args...]"; exit 2; }
  VOL="$(osascript -e 'output volume of (get volume settings)' 2>/dev/null || echo "")"
  MUTED="$(osascript -e 'output muted of (get volume settings)' 2>/dev/null || echo "")"
  echo "[volume-guard] found: volume ${VOL:-?}, muted ${MUTED:-?}"
  restore() {
    trap - EXIT INT TERM
    if [ -n "$VOL" ]; then
      osascript -e "set volume output volume $VOL" >/dev/null 2>&1
      [ -n "$MUTED" ] && osascript -e "set volume output muted $MUTED" >/dev/null 2>&1
      NOW="$(osascript -e 'output volume of (get volume settings)' 2>/dev/null)"
      NOWM="$(osascript -e 'output muted of (get volume settings)' 2>/dev/null)"
      if [ "$NOW" = "$VOL" ] && [ "$NOWM" = "$MUTED" ]; then
        echo "[volume-guard] restored: volume $NOW, muted $NOWM (read back)"
      else
        echo "[volume-guard] WARNING: volume is $NOW/muted $NOWM, found $VOL/$MUTED — check by hand"
      fi
    fi
  }
  trap 'restore; exit 130' INT
  trap 'restore; exit 143' TERM
  trap restore EXIT
  "$@"
  exit $?
fi

STOP=0
[ "${1:-}" = "--stop" ] && STOP=1
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Patterns this repo is responsible for. Deliberately narrow: never match a process
# the owner might be using for something else (their own Chrome, their own server).
PATTERNS=(
  "python.* -m http\.server"                        # local previews of the web app
  "GradleDaemon"
  "KotlinCompileDaemon"
  "[f]fmpeg .*${ROOT}"                              # a transcode started by our tools
  "--remote-debugging-port=9[0-9]{3}.*(tv-glass|appname-cdp-profile|build/qa)"  # headless Chrome from the glass tools
  "node .*tools/(tv_[a-z_]+|test_[a-z_]+)\.mjs"     # a glass tool left waiting
  "atvremote .*--protocol companion"                # a pyatv call that never returned
  "xcrun devicectl device process launch .*--console"  # a console stream holding a device
)

found=0
for pat in "${PATTERNS[@]}"; do
  while read -r pid etime pcpu rss cmd; do
    [ -z "${pid:-}" ] && continue
    [ "$pid" = "$$" ] && continue
    # A shell whose command LINE mentions a pattern is not the process itself.
    case "$cmd" in /bin/zsh\ -c*|/bin/bash\ -c*|zsh\ -c*|bash\ -c*|sh\ -c*) continue ;; esac
    found=$((found + 1))
    printf "  %-8s %-12s %5s%% %6sMB  %s\n" "$pid" "$etime" "$pcpu" \
      "$((rss / 1024))" "$(echo "$cmd" | cut -c1-70)"
    [ "$STOP" -eq 1 ] && kill "$pid" 2>/dev/null
  done < <(ps -axo pid=,etime=,pcpu=,rss=,command= | grep -E -- "$pat" | grep -v -E "grep|dev_cleanup\.sh")
done

if [ "$found" -eq 0 ]; then
  echo "nothing of this repo's is running."
else
  echo
  if [ "$STOP" -eq 1 ]; then
    echo "stopped $found process(es)."
  else
    echo "$found process(es) — run with --stop to end them."
  fi
fi

# Gradle's daemons need their own goodbye or they linger with their heap held.
if [ "$STOP" -eq 1 ] && [ -x "$ROOT/android/gradlew" ]; then
  ( cd "$ROOT/android" && ./gradlew --stop >/dev/null 2>&1 ) && echo "gradle daemons stopped."
fi
