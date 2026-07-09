#!/bin/sh
# parity-report.sh — run the CPU/GPU parity suite and report pass/fail/SKIP
# so that "green because everything skipped" is never mistaken for "parity holds".
#
# Usage (from anywhere inside the repo):
#   .claude/skills/framer-diagnostics-and-proof/scripts/parity-report.sh [FilterName]
#
#   FilterName defaults to EffectGPUParityTests. Pass another suite name to
#   report on it instead (e.g. ShaderRendererTests).
#
# How skip detection works: XCTSkip'd tests (no Metal device, missing ASCII
# atlases) do not emit "' passed (" lines. We therefore compute
#   skipped-or-not-run = (tests listed by `swift test --list-tests`) - passed - failed
# which is robust across XCTest output-format changes.
#
# Exit codes:
#   0 = all listed tests passed (0 skipped)
#   1 = at least one failure
#   2 = no failures, but >=1 test skipped  -> parity NOT fully verified
#   3 = suite not found / nothing executed

set -u

FILTER=${1:-EffectGPUParityTests}
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "not inside a git repo" >&2; exit 3; }
cd "$ROOT" || exit 3

TMP=$(mktemp -t parity-report)
trap 'rm -f "$TMP"' EXIT

echo "parity-report: listing tests matching '$FILTER' ..."
EXPECTED=$(swift test --list-tests 2>/dev/null | grep -c "\.$FILTER/")
if [ "$EXPECTED" -eq 0 ]; then
    echo "FAIL  no tests found for filter '$FILTER' — check the suite name" >&2
    exit 3
fi

echo "parity-report: running swift test --filter $FILTER ($EXPECTED tests expected) ..."
swift test --filter "$FILTER" >"$TMP" 2>&1
RUN_STATUS=$?

PASSED=$(grep -c "' passed (" "$TMP")
FAILED=$(grep -c "' failed (" "$TMP")
SKIPPED=$((EXPECTED - PASSED - FAILED))
[ "$SKIPPED" -lt 0 ] && SKIPPED=0

echo "---"
echo "suite:    $FILTER"
echo "expected: $EXPECTED"
echo "passed:   $PASSED"
echo "failed:   $FAILED"
echo "skipped:  $SKIPPED (XCTSkip or not run)"

if [ "$FAILED" -gt 0 ] || { [ "$RUN_STATUS" -ne 0 ] && [ "$PASSED" -eq 0 ]; }; then
    echo "---"
    echo "FAILURES / errors:"
    grep -E "' failed \(|error:" "$TMP" | head -20
fi

if [ "$SKIPPED" -gt 0 ]; then
    echo "---"
    echo "SKIP DETAIL (why tests were skipped):"
    grep -i "skipped" "$TMP" | head -10
    echo "WARNING: $SKIPPED test(s) did not actually verify parity on this host."
    echo "Typical causes: no Metal device (headless/CI container), ASCII LUT"
    echo "atlases missing from TextureFrameProvider.searchPaths."
fi

echo "---"
if [ "$FAILED" -gt 0 ]; then
    echo "RESULT: FAIL — parity broken. See docs/gpu-migration-mac-resume.md interpretation bands before touching tolerances."
    exit 1
elif [ "$SKIPPED" -gt 0 ]; then
    echo "RESULT: INCONCLUSIVE — green output but $SKIPPED skipped. Do NOT report 'parity verified'."
    exit 2
elif [ "$PASSED" -eq "$EXPECTED" ]; then
    echo "RESULT: PASS — all $EXPECTED parity tests executed and passed."
    exit 0
else
    echo "RESULT: INCONCLUSIVE — executed $PASSED of $EXPECTED with no failures reported. Inspect $FILTER output manually."
    exit 3
fi
