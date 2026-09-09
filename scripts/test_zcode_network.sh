#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="${ROOT}/helper/CodexTouchBarHelper"
BUILD="$(mktemp -d /tmp/zcode-network-test.XXXXXX)"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/codex-touchbar-clang-cache"
swiftc -D ZCODE_TESTING -target "$(uname -m)-apple-macosx12.0" \
  "${PACKAGE}"/Sources/CodexTouchBarCore/ZCode*.swift \
  "${PACKAGE}/Tests/ZCodeNetworkHarness.swift" -o "${BUILD}/test-network"
"${BUILD}/test-network"
