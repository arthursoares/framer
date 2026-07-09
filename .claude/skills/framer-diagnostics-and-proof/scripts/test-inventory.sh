#!/bin/sh
# test-inventory.sh — count SPM tests per suite so coverage drift is measurable.
#
# Usage (from anywhere inside the repo):
#   .claude/skills/framer-diagnostics-and-proof/scripts/test-inventory.sh
#
# Output: per-suite test counts (descending), per-module subtotals, and the
# grand total. Baseline as of 2026-07-09 (commit 48d85a5): 268 tests total —
# 259 FramerCoreTests + 9 FramerCLITests. If today's total is LOWER than the
# last recorded baseline, tests were deleted or a target dropped out of
# Package.swift — investigate before celebrating a green run.
#
# NOTE: this covers ONLY the SPM tier. The 63 FramerAppTests methods live in
# the Xcode-only target (project.yml) and are invisible to swift test; count
# those with:  grep -rc 'func test' Tests/FramerAppTests/*.swift
#
# Exit code: 0 if listing succeeded, 1 otherwise.

set -u

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "not inside a git repo" >&2; exit 1; }
cd "$ROOT" || exit 1

TMP=$(mktemp -t test-inventory)
trap 'rm -f "$TMP"' EXIT

# Format of each line: Module.Suite/testName
if ! swift test --list-tests >"$TMP" 2>/dev/null; then
    echo "swift test --list-tests failed — does the package build?" >&2
    exit 1
fi

TOTAL=$(grep -c '/' "$TMP")
if [ "$TOTAL" -eq 0 ]; then
    echo "no tests listed — something is wrong with the package manifest" >&2
    exit 1
fi

echo "SPM test inventory ($(date +%Y-%m-%d), $(git rev-parse --short HEAD))"
echo "---"
echo "per suite:"
awk -F'/' '{print $1}' "$TMP" | sort | uniq -c | sort -rn | awk '{printf "  %4d  %s\n", $1, $2}'
echo "---"
echo "per module:"
awk -F'[./]' '{print $1}' "$TMP" | sort | uniq -c | sort -rn | awk '{printf "  %4d  %s\n", $1, $2}'
echo "---"
echo "TOTAL: $TOTAL SPM tests (baseline 2026-07-09: 268)"

# Xcode-only tier, counted statically since swift test cannot see it.
if [ -d Tests/FramerAppTests ]; then
    APP=$(grep -rch 'func test' Tests/FramerAppTests/*.swift 2>/dev/null | awk '{s+=$1} END {print s+0}')
    echo "PLUS:  $APP FramerAppTests methods (xcodebuild-only tier, static grep count; baseline 2026-07-09: 63)"
fi
exit 0
