#!/usr/bin/env bash

set -euo pipefail

usage() {
    echo "Usage: $0 <vX.Y.Z> [scratch-path] [artifact-directory]" >&2
    exit 2
}

[[ $# -ge 1 && $# -le 3 ]] || usage

TAG="$1"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "error: release tag must look like vX.Y.Z (received: $TAG)" >&2
    exit 2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRATCH_PATH="${2:-${TMPDIR:-/tmp}/framer-release-build}"
ARTIFACT_DIRECTORY="${3:-${TMPDIR:-/tmp}/framer-release-artifacts}"
EXPECTED_VERSION="${TAG#v}"
ASSET_NAME="framer-${TAG}-macos-arm64.tar.gz"
BUNDLE_NAME="framer_FramerCore.bundle"

mkdir -p "$SCRATCH_PATH" "$ARTIFACT_DIRECTORY"

SMOKE_DIRECTORY=""
HIDDEN_BUILD_BUNDLE=""
cleanup() {
    local status=$?
    trap - EXIT

    if [[ -n "$HIDDEN_BUILD_BUNDLE" && -d "$HIDDEN_BUILD_BUNDLE" ]]; then
        mv "$HIDDEN_BUILD_BUNDLE" "$BUNDLE_PATH" || status=1
    fi
    if [[ -n "$SMOKE_DIRECTORY" && -d "$SMOKE_DIRECTORY" ]]; then
        rm -rf "$SMOKE_DIRECTORY" || status=1
    fi

    exit "$status"
}
trap cleanup EXIT

swift build \
    --package-path "$REPOSITORY_ROOT" \
    --scratch-path "$SCRATCH_PATH" \
    --configuration release

BIN_DIRECTORY="$(swift build \
    --package-path "$REPOSITORY_ROOT" \
    --scratch-path "$SCRATCH_PATH" \
    --configuration release \
    --show-bin-path)"
BIN_PATH="$BIN_DIRECTORY/framer"
BUNDLE_PATH="$BIN_DIRECTORY/$BUNDLE_NAME"

[[ -x "$BIN_PATH" ]] || {
    echo "error: release binary not found at $BIN_PATH" >&2
    exit 1
}
[[ -d "$BUNDLE_PATH" ]] || {
    echo "error: SwiftPM resource bundle not found at $BUNDLE_PATH" >&2
    exit 1
}

ACTUAL_VERSION="$("$BIN_PATH" --version)"
[[ "$ACTUAL_VERSION" == "$EXPECTED_VERSION" ]] || {
    echo "error: binary prints $ACTUAL_VERSION but release tag is $TAG" >&2
    exit 1
}

file "$BIN_PATH" | grep -q 'arm64' || {
    echo "error: release binary is not arm64: $(file "$BIN_PATH")" >&2
    exit 1
}

ASSET_PATH="$ARTIFACT_DIRECTORY/$ASSET_NAME"
CHECKSUM_PATH="$ARTIFACT_DIRECTORY/SHA256SUMS"
rm -f "$ASSET_PATH" "$CHECKSUM_PATH"
tar -czf "$ASSET_PATH" -C "$BIN_DIRECTORY" framer "$BUNDLE_NAME"

while IFS= read -r entry; do
    case "$entry" in
        framer|"$BUNDLE_NAME"|"$BUNDLE_NAME"/*) ;;
        *)
            echo "error: unexpected archive entry: $entry" >&2
            exit 1
            ;;
    esac
done < <(tar -tzf "$ASSET_PATH")

(
    cd "$ARTIFACT_DIRECTORY"
    shasum -a 256 "$ASSET_NAME" > SHA256SUMS
    shasum -a 256 -c SHA256SUMS
)

SMOKE_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/framer-release-smoke.XXXXXX")"
RELOCATED_DIRECTORY="$SMOKE_DIRECTORY/relocated"
mkdir -p "$RELOCATED_DIRECTORY" "$SMOKE_DIRECTORY/user-home"
tar -xzf "$ASSET_PATH" -C "$RELOCATED_DIRECTORY"

[[ -x "$RELOCATED_DIRECTORY/framer" ]] || {
    echo "error: packaged binary is not executable after extraction" >&2
    exit 1
}
[[ -d "$RELOCATED_DIRECTORY/$BUNDLE_NAME" ]] || {
    echo "error: packaged resource bundle is missing after extraction" >&2
    exit 1
}

printf '%s\n' \
    'output_format: png' \
    'no_metadata: true' \
    'layers:' \
    '  - type: shader' \
    '    shader_style: ascii' \
    > "$SMOKE_DIRECTORY/ascii.yaml"

# SwiftPM's generated bundle accessor falls back to the absolute build path.
# Hide that bundle during the relocated smoke so the archive must be complete.
HIDDEN_BUILD_BUNDLE="$BUNDLE_PATH.release-smoke-hidden.$$"
mv "$BUNDLE_PATH" "$HIDDEN_BUILD_BUNDLE"

RELOCATED_VERSION="$(CFFIXED_USER_HOME="$SMOKE_DIRECTORY/user-home" \
    "$RELOCATED_DIRECTORY/framer" --version)"
[[ "$RELOCATED_VERSION" == "$EXPECTED_VERSION" ]] || {
    echo "error: relocated binary prints $RELOCATED_VERSION but release tag is $TAG" >&2
    exit 1
}

(
    cd "$SMOKE_DIRECTORY"
    CFFIXED_USER_HOME="$SMOKE_DIRECTORY/user-home" \
        "$RELOCATED_DIRECTORY/framer" process \
        --input "$REPOSITORY_ROOT/Tests/FramerCoreTests/Resources/sample.jpg" \
        --output-file "$SMOKE_DIRECTORY/ascii-smoke.png" \
        --config "$SMOKE_DIRECTORY/ascii.yaml"
)
[[ -s "$SMOKE_DIRECTORY/ascii-smoke.png" ]] || {
    echo "error: relocated ASCII smoke did not produce an image" >&2
    exit 1
}

mv "$HIDDEN_BUILD_BUNDLE" "$BUNDLE_PATH"
HIDDEN_BUILD_BUNDLE=""

echo "release asset: $ASSET_PATH"
echo "checksums: $CHECKSUM_PATH"
echo "verified version: $ACTUAL_VERSION"
echo "verified relocated ASCII render with build bundle unavailable"
