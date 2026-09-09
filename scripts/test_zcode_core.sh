#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_DIR="$(cd "$SCRIPT_DIR/../helper/CodexTouchBarHelper" && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/zcode-core-check.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

swiftc \
  -DZCODE_TESTING \
  -DZCODE_STANDALONE \
  -module-name ZCodeStandaloneCore \
  -o "$BUILD_DIR/zcode-core-check" \
  "$PACKAGE_DIR"/Sources/CodexTouchBarCore/ZCode*.swift \
  "$PACKAGE_DIR"/Tests/CodexTouchBarCoreTests/ZCodeStandaloneChecks.swift

"$BUILD_DIR/zcode-core-check"
