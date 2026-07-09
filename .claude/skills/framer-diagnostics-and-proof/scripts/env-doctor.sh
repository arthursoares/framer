#!/bin/sh
# env-doctor.sh — health check for the framer development environment.
#
# Usage (from anywhere inside the repo):
#   .claude/skills/framer-diagnostics-and-proof/scripts/env-doctor.sh
#
# Prints one PASS / WARN / FAIL line per check.
#   FAIL = breaks the SPM tier (swift build / swift test) or corrupts renders
#          (un-pulled LFS textures render as 132-byte pointer files).
#   WARN = breaks only the xcodebuild app-test tier (known-broken on the
#          primary machine as of 2026-07-09) or is informational.
# Exit code: number of FAILs (0 = SPM tier healthy).
#
# No dependencies beyond git, the Swift toolchain, and standard macOS tools.

set -u

fails=0
pass() { printf 'PASS  %s\n' "$1"; }
warn() { printf 'WARN  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }

# --- 0. Locate repo root ----------------------------------------------------
ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$ROOT" ]; then
    fail "not inside a git repository — run from within the framer checkout"
    exit 1
fi
cd "$ROOT" || exit 1
pass "repo root: $ROOT"

# --- 1. Swift toolchain -----------------------------------------------------
if command -v swift >/dev/null 2>&1; then
    SWIFT_VER=$(swift --version 2>/dev/null | head -1)
    pass "swift toolchain present: $SWIFT_VER"
else
    fail "swift not found on PATH — install Xcode / Swift toolchain"
fi

# --- 2. xcodegen (needed only to regenerate Framer.xcodeproj) ---------------
if command -v xcodegen >/dev/null 2>&1; then
    XG_VER=$(xcodegen --version 2>/dev/null)
    pass "xcodegen present: $XG_VER"
else
    warn "xcodegen not found — needed for app-target work (brew install xcodegen); SPM tier unaffected"
fi

# --- 3. Git LFS install + pointer-file detection -----------------------------
if command -v git-lfs >/dev/null 2>&1; then
    pass "git-lfs installed: $(git lfs version 2>/dev/null | head -1)"
else
    fail "git-lfs not installed — overlay textures will be 132-byte pointers (brew install git-lfs; git lfs install; git lfs pull)"
fi

# A file still in pointer form starts with the LFS spec line. Real textures
# are JPEG/PNG/TIFF binaries. Scan every LFS-tracked path (168 files as of
# 2026-07-09; reading 64 bytes each is fast).
LFS_TOTAL=0
LFS_POINTERS=0
for f in $(git lfs ls-files -n 2>/dev/null); do
    [ -f "$f" ] || continue
    LFS_TOTAL=$((LFS_TOTAL + 1))
    if head -c 64 "$f" 2>/dev/null | grep -q 'git-lfs.github.com/spec'; then
        LFS_POINTERS=$((LFS_POINTERS + 1))
    fi
done
if [ "$LFS_TOTAL" -eq 0 ]; then
    warn "no LFS-tracked files found (expected ~168 under assets/textures/) — check git lfs install state"
elif [ "$LFS_POINTERS" -gt 0 ]; then
    fail "$LFS_POINTERS of $LFS_TOTAL LFS files are un-pulled pointer stubs — run: git lfs pull (overlays will not render until then)"
else
    pass "LFS content pulled: $LFS_TOTAL/$LFS_TOTAL tracked files are real binaries"
fi

# --- 4. Metal Toolchain component (xcodebuild tier only) --------------------
# SPM builds compile .metal via a runtime source-compile fallback, so a
# missing Metal Toolchain breaks ONLY `xcodebuild` builds of the app target.
MT_STATUS=$(xcodebuild -showComponent metalToolchain 2>/dev/null | awk -F': ' '/^Status/ {print $2}')
case "$MT_STATUS" in
    installed*|Installed*)
        pass "Metal Toolchain component installed (xcodebuild tier can compile .metal)"
        ;;
    "")
        warn "could not query Metal Toolchain (xcodebuild -showComponent metalToolchain returned nothing) — old Xcode?"
        ;;
    *)
        warn "Metal Toolchain status: '$MT_STATUS' — xcodebuild app builds will fail with 'cannot execute tool metal'. Fix: xcodebuild -downloadComponent metalToolchain. swift build/test are NOT affected."
        ;;
esac

# --- 5. Code-signing identity hint (xcodebuild tier only) --------------------
# The default xcodebuild test path signs with the team's Apple Development
# cert; a revoked/expired cert fails the build before compiling anything.
IDENT_OUT=$(security find-identity -v -p codesigning 2>/dev/null)
if echo "$IDENT_OUT" | grep -q 'CSSMERR_TP_CERT_REVOKED'; then
    warn "a codesigning identity is REVOKED: $(echo "$IDENT_OUT" | grep CSSMERR_TP_CERT_REVOKED | head -1 | sed 's/^ *//') — xcodebuild test will fail at signing; renew in Xcode or sign ad-hoc"
elif echo "$IDENT_OUT" | grep -q '0 valid identities'; then
    warn "no valid codesigning identities — xcodebuild test of the app target will fail at signing"
else
    pass "codesigning identities look usable: $(echo "$IDENT_OUT" | grep 'valid identities' | sed 's/^ *//')"
fi

# --- Summary -----------------------------------------------------------------
echo "---"
if [ "$fails" -eq 0 ]; then
    echo "env-doctor: SPM tier healthy (swift build / swift test should work). Check WARNs before touching the xcodebuild tier."
else
    echo "env-doctor: $fails FAIL(s) — fix these before trusting any build or render output."
fi
exit "$fails"
