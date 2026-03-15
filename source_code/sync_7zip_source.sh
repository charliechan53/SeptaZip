#!/bin/bash
#
# Sync the vendored 7-Zip source tree from a git ref.
#
# Usage:
#   ./source_code/sync_7zip_source.sh [git-ref]
# Example:
#   ./source_code/sync_7zip_source.sh upstream/main
#

set -euo pipefail

REF="${1:-upstream/main}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEST_DIR="$SCRIPT_DIR/7zip"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/7zip-sync.XXXXXX")"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if ! git -C "$REPO_ROOT" rev-parse --verify "$REF^{commit}" >/dev/null 2>&1; then
    echo "ERROR: git ref '$REF' not found."
    echo "Hint: fetch first, e.g. 'git fetch upstream --tags'."
    exit 1
fi

SRC_PREFIX=""
if git -C "$REPO_ROOT" cat-file -e "$REF:Asm" 2>/dev/null; then
    SRC_PREFIX=""
elif git -C "$REPO_ROOT" cat-file -e "$REF:source_code/7zip/Asm" 2>/dev/null; then
    SRC_PREFIX="source_code/7zip/"
else
    echo "ERROR: ref '$REF' does not contain expected 7-Zip source directories."
    echo "Checked both: Asm/C/CPP/DOC and source_code/7zip/Asm/C/CPP/DOC."
    exit 1
fi

echo "Syncing 7-Zip source from: $REF"
mkdir -p "$TMP_DIR/src"

git -C "$REPO_ROOT" archive "$REF" \
    "${SRC_PREFIX}Asm" "${SRC_PREFIX}C" "${SRC_PREFIX}CPP" "${SRC_PREFIX}DOC" \
    | tar -x -C "$TMP_DIR/src"

mkdir -p "$DEST_DIR"
rsync -a --delete "$TMP_DIR/src/${SRC_PREFIX}Asm/" "$DEST_DIR/Asm/"
rsync -a --delete "$TMP_DIR/src/${SRC_PREFIX}C/" "$DEST_DIR/C/"
rsync -a --delete "$TMP_DIR/src/${SRC_PREFIX}CPP/" "$DEST_DIR/CPP/"
rsync -a --delete "$TMP_DIR/src/${SRC_PREFIX}DOC/" "$DEST_DIR/DOC/"

echo "Sync complete:"
echo "  $DEST_DIR/Asm"
echo "  $DEST_DIR/C"
echo "  $DEST_DIR/CPP"
echo "  $DEST_DIR/DOC"
echo ""
echo "Next:"
echo "  1) Review changes: git status"
echo "  2) Rebuild 7zz: (cd MacApp && make build-7zz)"
