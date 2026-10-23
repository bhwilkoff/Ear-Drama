#!/usr/bin/env bash
# Every catalog test suite, each in its own process; exits non-zero when any fails.
#
#     bash catalog/tests/run_all.sh
#
# The publish workflow runs this before it builds a projection: a red suite
# keeps the last good catalog live. A suite that is found but cannot run is a
# failure too, and a folder with no suites is one (a run that tested nothing).
set -uo pipefail
cd "$(dirname "$0")/.."

failed=()
n=0
for t in tests/test_*.py; do
  [ -e "$t" ] || continue
  n=$((n + 1))
  start=$(date +%s)
  out=$(python3 "$t" 2>&1)
  rc=$?
  printf '%-40s rc=%s %4ss  %s\n' "$t" "$rc" "$(( $(date +%s) - start ))" "$(printf '%s\n' "$out" | tail -1)"
  if [ "$rc" -ne 0 ]; then
    printf '%s\n' "$out" | grep -E 'FAIL|Error|error' | head -20
    failed+=("$t")
  fi
done

if [ "$n" -eq 0 ]; then
  echo "no catalog test suites found" >&2
  exit 1
fi
if [ "${#failed[@]}" -gt 0 ]; then
  echo "${#failed[@]} of $n suites failed: ${failed[*]}" >&2
  exit 1
fi
echo "all $n suites passed"
