#!/usr/bin/env bash
# Every web test in one command: the API layer, the TV focus engine, the
# packaged-TV origin rules, Pulse's charts and page, the design tokens (every
# platform's token file matches design-tokens.json), the service worker's
# routing and shell, plays phase 1 (relay, takes, timeline, mix, no stored
# device voice), plays phase 2 against a stubbed Worker (the uploads switch,
# no consent on upload, Publish shut, no flagged upload, any open part, invite links), sign-in and sync against a stubbed Worker (refresh, merge,
# last write wins, deletion), Listen Together against a stubbed Worker built
# from worker/src/room-protocol.js (join, leave, drift, handoff, an ended
# room, the core golden-checked against the protocol), and two checks a browser
# will not show you. Each suite runs the SHIPPED files, so a test can never
# drift from what actually runs.
#
# The last line is always one PASS or FAIL, and the exit status is non-zero on
# any failure: a suite that fails, a suite named here that does not exist, a
# script that does not parse, or a stylesheet that does not balance.
# WEB_SUITES (space-separated paths) replaces the suite list, for this script's
# own negative control.
set -uo pipefail
cd "$(dirname "$0")/.."

DEFAULT_SUITES="js/api.test.js
  js/remote-playback.test.js
  js/player.test.js
  js/plays.test.js
  js/plays-share.test.js
  js/account.test.js
  js/together.test.js
  tools/test_tv_focus.mjs
  tools/test_tv_ua.mjs
  tools/test_packaged_origin.mjs
  tools/test_pulse_charts.mjs
  tools/test_pulse_render.mjs
  tools/test_design_tokens.mjs
  tools/test_no_edge_stripes.mjs
  tools/test_sw.mjs
  tools/test_deep_links.mjs"

fail=0
failed=()
n=0
for t in ${WEB_SUITES:-$DEFAULT_SUITES}; do
  n=$((n + 1))
  if [ ! -f "$t" ]; then
    printf '  FAIL  %-32s MISSING: this script names a suite that does not exist\n' "$t"
    fail=1; failed+=("$t"); continue
  fi
  out=$(node "$t" 2>&1); rc=$?
  last=$(printf '%s\n' "$out" | tail -1)
  if [ $rc -ne 0 ] || printf '%s' "$out" | grep -q FAIL; then
    printf '  FAIL  %-32s %s\n' "$(basename "$t")" "$last"
    printf '%s\n' "$out" | grep FAIL | sed 's/^/          /'
    fail=1; failed+=("$t")
  else
    printf '  ok    %-32s %s\n' "$(basename "$t")" "$last"
  fi
done

# Every script must at least parse; a syntax error breaks the whole page.
for f in js/*.js sw.js tv.js pulse/*.js; do
  if node --check "$f" 2>/dev/null; then
    printf '  ok    %-32s parses\n' "$f"
  else
    printf '  FAIL  %-32s SYNTAX ERROR\n' "$f"; fail=1; failed+=("$f")
  fi
done

# Balanced braces catch a truncated CSS append, which silently drops every
# rule after it (the failure mode of appending to a stylesheet with cat >>).
if ! python3 - <<'PY'
import sys, glob
bad = 0
for f in ["css/styles.css", "tv.css"] + glob.glob("pulse/*.css"):
    s = open(f).read()
    ok = s.count('{') == s.count('}')
    bad += not ok
    print(f"  {'ok  ' if ok else 'FAIL'}  {f:<32} braces {s.count('{')}/{s.count('}')}")
sys.exit(1 if bad else 0)
PY
then
  fail=1; failed+=("stylesheet braces")
fi

# The site deploy runs this too; without it here, a .replaceChildren(null) passed every local
# run and failed the deploy (D3-6, 2026-10-30).
if ! python3 tools/test_js_null_children.py; then
  fail=1; failed+=("null children")
fi

if [ "$fail" -ne 0 ]; then
  echo "FAIL: ${#failed[@]} failing (${failed[*]}); $n suites run, then the parse and brace checks"
  exit 1
fi
echo "PASS: $n suites, every script parses, every stylesheet balances"
