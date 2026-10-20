#!/usr/bin/env bash

set -euo pipefail

usage() {
    echo "Usage: $0 <vX.Y.Z> <source-root> <derived-data> <artifact-directory>" >&2
    exit 2
}

fail() {
    echo "error: $*" >&2
    exit 1
}

[[ $# -eq 4 ]] || usage

TAG="$1"
SOURCE_ROOT="$2"
DERIVED_DATA="$3"
ARTIFACT_DIRECTORY="$4"

[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "error: release tag must look like vX.Y.Z (received: $TAG)" >&2
    exit 2
}

for tool in codesign ditto git lipo plutil python3 shasum unzip xcodebuild; do
    command -v "$tool" >/dev/null 2>&1 || fail "required tool is unavailable: $tool"
done

[[ -d "$SOURCE_ROOT" ]] || fail "source root is not a directory: $SOURCE_ROOT"
SOURCE_ROOT="$(cd "$SOURCE_ROOT" && pwd -P)"
PROJECT_PATH="$SOURCE_ROOT/Framer.xcodeproj"
[[ -d "$PROJECT_PATH" ]] || fail "Xcode project not found: $PROJECT_PATH"

HEAD_COMMIT="$(git -C "$SOURCE_ROOT" rev-parse --verify 'HEAD^{commit}' 2>/dev/null)" || \
    fail "source root is not a readable Git worktree: $SOURCE_ROOT"
TAG_COMMIT="$(git -C "$SOURCE_ROOT" rev-parse --verify "refs/tags/$TAG^{commit}" 2>/dev/null)" || \
    fail "release tag is unavailable in the source repository: $TAG"
[[ "$HEAD_COMMIT" == "$TAG_COMMIT" ]] || \
    fail "source HEAD $HEAD_COMMIT does not match $TAG commit $TAG_COMMIT"
git -C "$SOURCE_ROOT" diff --cached --quiet "$HEAD_COMMIT" -- || \
    fail "source index differs from the $TAG commit"

# Compare working files directly with HEAD blobs. This is deliberately more exact
# than `git status`: two small raw PNGs under the repository's broad LFS attribute
# pattern otherwise appear modified when the LFS clean filter rewrites them.
python3 - "$SOURCE_ROOT" <<'PY'
import hashlib
import os
import re
import stat
import subprocess
import sys

root = sys.argv[1]
tree = subprocess.check_output(
    ["git", "-C", root, "ls-tree", "-rz", "--full-tree", "HEAD"]
)
tracked = []
for record in tree.split(b"\0"):
    if not record:
        continue
    metadata, raw_path = record.split(b"\t", 1)
    mode, kind, raw_oid = metadata.split(b" ", 2)
    tracked.append((mode.decode(), kind.decode(), raw_oid.decode(), os.fsdecode(raw_path)))

untracked = subprocess.check_output(
    ["git", "-C", root, "ls-files", "-z", "--others", "--exclude-standard"]
)
untracked = [os.fsdecode(path) for path in untracked.split(b"\0") if path]
if untracked:
    raise SystemExit(
        "error: source contains nonignored untracked files: " + ", ".join(untracked[:10])
    )

cat_file = subprocess.Popen(
    ["git", "-C", root, "cat-file", "--batch"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
)
assert cat_file.stdin is not None
assert cat_file.stdout is not None

pointer_header = b"version https://git-lfs.github.com/spec/v1\n"
try:
    for mode, kind, oid, relative in tracked:
        if kind != "blob":
            raise SystemExit(f"error: unsupported tracked Git object ({kind}): {relative}")
        cat_file.stdin.write((oid + "\n").encode())
        cat_file.stdin.flush()
        header = cat_file.stdout.readline().split()
        if len(header) != 3 or header[1] != b"blob":
            raise SystemExit(f"error: could not read tagged Git blob: {relative}")
        size = int(header[2])
        expected = cat_file.stdout.read(size)
        if cat_file.stdout.read(1) != b"\n":
            raise SystemExit(f"error: malformed git cat-file response: {relative}")

        path = os.path.join(root, relative)
        if mode == "120000":
            if not os.path.islink(path) or os.fsencode(os.readlink(path)) != expected:
                raise SystemExit(f"error: tracked symlink differs from {relative} at {oid}")
            continue
        if mode not in {"100644", "100755"}:
            raise SystemExit(f"error: unsupported tracked file mode {mode}: {relative}")
        if not os.path.isfile(path) or os.path.islink(path):
            raise SystemExit(f"error: tracked file is missing or has the wrong type: {relative}")
        executable = bool(os.stat(path).st_mode & stat.S_IXUSR)
        if executable != (mode == "100755"):
            raise SystemExit(f"error: tracked executable mode differs from tag: {relative}")

        if expected.startswith(pointer_header):
            digest_match = re.search(rb"^oid sha256:([0-9a-f]{64})$", expected, re.MULTILINE)
            size_match = re.search(rb"^size ([0-9]+)$", expected, re.MULTILINE)
            if digest_match is None or size_match is None:
                raise SystemExit(f"error: malformed Git LFS pointer in tag: {relative}")
            actual_size = os.path.getsize(path)
            if actual_size != int(size_match.group(1)):
                raise SystemExit(f"error: tracked Git LFS size differs from tag: {relative}")
            actual_digest = hashlib.sha256()
            with open(path, "rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    actual_digest.update(chunk)
            if actual_digest.hexdigest().encode() != digest_match.group(1):
                raise SystemExit(f"error: tracked Git LFS content differs from tag: {relative}")
        else:
            with open(path, "rb") as stream:
                if stream.read() != expected:
                    raise SystemExit(f"error: tracked file differs from tag: {relative}")
finally:
    cat_file.stdin.close()
    cat_file.stdout.close()
    return_code = cat_file.wait()
    if return_code != 0 and sys.exc_info()[0] is None:
        raise SystemExit("error: git cat-file failed while verifying tagged source")
PY

EXPECTED_VERSION="${TAG#v}"
BUNDLE_IDENTIFIER="com.arthursoares.Framer"
APP_NAME="Framer.app"
ASSET_NAME="Framer-${TAG}-macos-universal.zip"
CHECKSUM_NAME="$ASSET_NAME.sha256"

# A source checkout containing LFS pointer stubs can compile and produce a broken
# app. Inspect every tracked release asset before invoking xcodebuild.
python3 - "$SOURCE_ROOT" <<'PY'
import os
import subprocess
import sys

root = sys.argv[1]
tracked = subprocess.check_output(
    ["git", "-C", root, "ls-files", "-z", "--", "assets/textures", "assets/fonts"]
).split(b"\0")
tracked = [os.fsdecode(path) for path in tracked if path]
if not tracked:
    raise SystemExit("error: no tracked textures or fonts were found")

pointer_header = b"version https://git-lfs.github.com/spec/v1"
for relative in tracked:
    path = os.path.join(root, relative)
    if not os.path.isfile(path):
        raise SystemExit(f"error: tracked release asset is missing: {relative}")
    if os.path.getsize(path) == 0:
        raise SystemExit(f"error: tracked release asset is empty: {relative}")
    with open(path, "rb") as stream:
        if stream.read(len(pointer_header)) == pointer_header:
            raise SystemExit(f"error: Git LFS asset is not hydrated: {relative}")
PY

mkdir -p "$DERIVED_DATA" "$ARTIFACT_DIRECTORY"
DERIVED_DATA="$(cd "$DERIVED_DATA" && pwd -P)"
ARTIFACT_DIRECTORY="$(cd "$ARTIFACT_DIRECTORY" && pwd -P)"

TEMP_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/framer-macos-package.XXXXXX")"
cleanup() {
    local status=$?
    trap - EXIT
    rm -rf -- "$TEMP_DIRECTORY"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

xcodebuild build \
    -project "$PROJECT_PATH" \
    -scheme Framer \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    ARCHS='arm64 x86_64' \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO

APP_PATH="$DERIVED_DATA/Build/Products/Release/$APP_NAME"
CONTENTS_PATH="$APP_PATH/Contents"
RESOURCES_PATH="$CONTENTS_PATH/Resources"
EXECUTABLE_PATH="$CONTENTS_PATH/MacOS/Framer"
INFO_PLIST="$CONTENTS_PATH/Info.plist"

[[ -d "$APP_PATH" ]] || fail "built app not found: $APP_PATH"
[[ -x "$EXECUTABLE_PATH" ]] || fail "built app executable is missing or not executable"
[[ -f "$INFO_PLIST" ]] || fail "built app Info.plist is missing"
plutil -lint "$INFO_PLIST" >/dev/null
[[ -d "$RESOURCES_PATH" ]] || fail "built app Resources directory is missing"
[[ -n "$(find "$RESOURCES_PATH" -mindepth 1 -print -quit)" ]] || \
    fail "built app Resources directory is empty"
[[ -z "$(find "$RESOURCES_PATH" -type f -size 0 -print -quit)" ]] || \
    fail "built app contains an empty resource file"

ACTUAL_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
ACTUAL_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
MINIMUM_SYSTEM_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO_PLIST")"
[[ "$ACTUAL_VERSION" == "$EXPECTED_VERSION" ]] || \
    fail "built app version is $ACTUAL_VERSION, expected $EXPECTED_VERSION from $TAG"
[[ "$ACTUAL_IDENTIFIER" == "$BUNDLE_IDENTIFIER" ]] || \
    fail "built app identifier is $ACTUAL_IDENTIFIER, expected $BUNDLE_IDENTIFIER"
[[ "$MINIMUM_SYSTEM_VERSION" == "14.0" ]] || \
    fail "built app minimum macOS version is $MINIMUM_SYSTEM_VERSION, expected 14.0"

ARCHITECTURES="$(lipo -archs "$EXECUTABLE_PATH")"
python3 - "$ARCHITECTURES" <<'PY'
import sys

actual = set(sys.argv[1].split())
expected = {"arm64", "x86_64"}
if actual != expected:
    raise SystemExit(
        "error: app executable architectures are "
        + " ".join(sorted(actual))
        + "; expected exactly arm64 and x86_64"
    )
PY

[[ -s "$RESOURCES_PATH/Assets.car" ]] || fail "compiled asset catalog is missing or empty"
[[ -s "$RESOURCES_PATH/AppIcon.icns" ]] || fail "compiled app icon is missing or empty"
[[ -d "$RESOURCES_PATH/framer_FramerCore.bundle" ]] || \
    fail "FramerCore resource bundle is missing"
[[ -n "$(find "$RESOURCES_PATH/framer_FramerCore.bundle" -type f -print -quit)" ]] || \
    fail "FramerCore resource bundle is empty"

METALLIB_PATH="$(find "$RESOURCES_PATH" -type f -name default.metallib -size +0c -print -quit)"
[[ -n "$METALLIB_PATH" ]] || fail "compiled default.metallib is missing or empty"

# Folder-reference resources must retain the exact bytes from the tagged source.
python3 - "$SOURCE_ROOT" "$RESOURCES_PATH" <<'PY'
import filecmp
import os
import subprocess
import sys

root, resources = sys.argv[1:]
tracked = subprocess.check_output(
    ["git", "-C", root, "ls-files", "-z", "--", "assets/textures", "assets/fonts"]
).split(b"\0")
for raw_relative in tracked:
    if not raw_relative:
        continue
    relative = os.fsdecode(raw_relative)
    bundled_relative = relative[len("assets/"):] if relative.startswith("assets/") else relative
    source_path = os.path.join(root, relative)
    bundled_path = os.path.join(resources, bundled_relative)
    if not os.path.isfile(bundled_path):
        raise SystemExit(f"error: bundled release asset is missing: {bundled_relative}")
    if not filecmp.cmp(source_path, bundled_path, shallow=False):
        raise SystemExit(f"error: bundled release asset differs from source: {bundled_relative}")
PY

# Apply an ad-hoc signature after the unsigned build. No entitlements are passed,
# so the local release artifact does not inherit the source sandbox entitlement.
codesign --force --deep --sign - --identifier "$BUNDLE_IDENTIFIER" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

SIGNATURE_DETAILS="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1)"
grep -qx "Identifier=$BUNDLE_IDENTIFIER" <<<"$SIGNATURE_DETAILS" || \
    fail "ad-hoc signature identifier is not $BUNDLE_IDENTIFIER"
ENTITLEMENTS="$(codesign -d --entitlements - "$APP_PATH" 2>&1)"
grep -q 'com.apple.security.app-sandbox' <<<"$ENTITLEMENTS" && \
    fail "packaged app unexpectedly has the App Sandbox entitlement"

STAGED_ASSET="$TEMP_DIRECTORY/$ASSET_NAME"
STAGED_CHECKSUM="$TEMP_DIRECTORY/$CHECKSUM_NAME"
ditto -c -k --keepParent --norsrc "$APP_PATH" "$STAGED_ASSET"

unzip -tq "$STAGED_ASSET"
python3 - "$STAGED_ASSET" <<'PY'
import pathlib
import sys
import zipfile

archive = sys.argv[1]
with zipfile.ZipFile(archive) as package:
    names = package.namelist()
    if not names:
        raise SystemExit("error: app ZIP is empty")
    for name in names:
        path = pathlib.PurePosixPath(name)
        if path.is_absolute() or ".." in path.parts:
            raise SystemExit(f"error: unsafe ZIP entry: {name}")
        if not path.parts or path.parts[0] != "Framer.app":
            raise SystemExit(f"error: unexpected top-level ZIP entry: {name}")
    bad_member = package.testzip()
    if bad_member is not None:
        raise SystemExit(f"error: ZIP CRC verification failed for: {bad_member}")
PY

CHECKSUM="$(shasum -a 256 "$STAGED_ASSET" | awk '{print $1}')"
printf '%s  %s\n' "$CHECKSUM" "$ASSET_NAME" > "$STAGED_CHECKSUM"
(
    cd "$TEMP_DIRECTORY"
    shasum -a 256 -c "$CHECKSUM_NAME"
)

EXTRACTION_ROOT="$TEMP_DIRECTORY/extracted"
mkdir "$EXTRACTION_ROOT"
ditto -x -k "$STAGED_ASSET" "$EXTRACTION_ROOT"
EXTRACTED_APP="$EXTRACTION_ROOT/$APP_NAME"
[[ -x "$EXTRACTED_APP/Contents/MacOS/Framer" ]] || \
    fail "relocated app executable is missing or not executable"

# Compare every directory, regular file byte digest, symlink target, and mode bit
# so relocation cannot silently add, omit, or alter app bundle inventory.
python3 - "$APP_PATH" "$EXTRACTED_APP" <<'PY'
import hashlib
import os
import stat
import sys


def digest(path):
    value = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def inventory(root):
    entries = {}
    for current, directories, files in os.walk(root, followlinks=False):
        for name in directories + files:
            path = os.path.join(current, name)
            relative = os.path.relpath(path, root)
            metadata = os.lstat(path)
            mode = stat.S_IMODE(metadata.st_mode)
            if stat.S_ISLNK(metadata.st_mode):
                entries[relative] = ("symlink", mode, os.readlink(path))
            elif stat.S_ISDIR(metadata.st_mode):
                entries[relative] = ("directory", mode)
            elif stat.S_ISREG(metadata.st_mode):
                entries[relative] = ("file", mode, metadata.st_size, digest(path))
            else:
                entries[relative] = ("other", mode)
    return entries


source, extracted = sys.argv[1:]
source_inventory = inventory(source)
extracted_inventory = inventory(extracted)
if source_inventory != extracted_inventory:
    missing = sorted(set(source_inventory) - set(extracted_inventory))
    extra = sorted(set(extracted_inventory) - set(source_inventory))
    changed = sorted(
        key
        for key in set(source_inventory) & set(extracted_inventory)
        if source_inventory[key] != extracted_inventory[key]
    )
    details = []
    if missing:
        details.append("missing=" + ",".join(missing[:5]))
    if extra:
        details.append("extra=" + ",".join(extra[:5]))
    if changed:
        details.append("changed=" + ",".join(changed[:5]))
    raise SystemExit("error: relocated app inventory differs: " + "; ".join(details))
PY

codesign --verify --deep --strict --verbose=2 "$EXTRACTED_APP"
EXTRACTED_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$EXTRACTED_APP/Contents/Info.plist")"
EXTRACTED_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$EXTRACTED_APP/Contents/Info.plist")"
[[ "$EXTRACTED_IDENTIFIER" == "$BUNDLE_IDENTIFIER" ]] || \
    fail "relocated app identifier changed during packaging"
[[ "$EXTRACTED_VERSION" == "$EXPECTED_VERSION" ]] || \
    fail "relocated app version changed during packaging"

mv -f "$STAGED_ASSET" "$ARTIFACT_DIRECTORY/$ASSET_NAME"
mv -f "$STAGED_CHECKSUM" "$ARTIFACT_DIRECTORY/$CHECKSUM_NAME"
(
    cd "$ARTIFACT_DIRECTORY"
    shasum -a 256 -c "$CHECKSUM_NAME"
)

echo "release asset: $ARTIFACT_DIRECTORY/$ASSET_NAME"
echo "checksum: $ARTIFACT_DIRECTORY/$CHECKSUM_NAME"
echo "verified tag commit: $TAG_COMMIT"
echo "verified app: version $ACTUAL_VERSION, macOS $MINIMUM_SYSTEM_VERSION+, $ARCHITECTURES"
echo "verified ad-hoc signature, exact bundled assets, ZIP CRC, checksum, and relocated inventory"
