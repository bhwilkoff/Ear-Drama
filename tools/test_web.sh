#!/usr/bin/env bash
# Every web test in one command: the API layer, the TV focus engine, the
# packaged-TV origin rules, Pulse's charts and page, the design tokens (every
# platform's token file matches design-tokens.json), and two checks a browser
# will not show you. Each suite runs the SHIPPED files, so a test can never
# drift from what actually runs.
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
for t in js/api.test.js \
         tools/test_tv_focus.mjs \
         tools/test_tv_ua.mjs \
         tools/test_packaged_origin.mjs \
         tools/test_pulse_charts.mjs \
         tools/test_pulse_render.mjs \
         tools/test_design_tokens.mjs; do
  out=$(node "$t" 2>&1); rc=$?
  last=$(printf '%s\n' "$out" | tail -1)
  if [ $rc -ne 0 ] || printf '%s' "$out" | grep -q FAIL; then
    printf '  FAIL  %-32s %s\n' "$(basename "$t")" "$last"
    printf '%s\n' "$out" | grep FAIL | sed 's/^/          /'
    fail=1
  else
    printf '  ok    %-32s %s\n' "$(basename "$t")" "$last"
  fi
done

# Every script must at least parse; a syntax error breaks the whole page.
for f in js/*.js tv.js pulse/*.js; do
  if node --check "$f" 2>/dev/null; then
    printf '  ok    %-32s parses\n' "$f"
  else
    printf '  FAIL  %-32s SYNTAX ERROR\n' "$f"; fail=1
  fi
done

# Balanced braces catch a truncated CSS append, which silently drops every
# rule after it (the failure mode of appending to a stylesheet with cat >>).
python3 - <<'PY' || fail=1
import sys, glob
bad = 0
for f in ["css/styles.css", "tv.css"] + glob.glob("pulse/*.css"):
    s = open(f).read()
    ok = s.count('{') == s.count('}')
    bad += not ok
    print(f"  {'ok  ' if ok else 'FAIL'}  {f:<32} braces {s.count('{')}/{s.count('}')}")
sys.exit(1 if bad else 0)
PY

exit $fail
