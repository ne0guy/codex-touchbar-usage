#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="${ROOT}/helper/CodexTouchBarHelper"
BUILD="$(mktemp -d /tmp/touchbar-cache-test.XXXXXX)"
trap 'rm -rf "${BUILD}"' EXIT
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/codex-touchbar-clang-cache"
swiftc -target "$(uname -m)-apple-macosx12.0" \
  "${PACKAGE}/Sources/CodexTouchBarCore/JSONSupport.swift" \
  "${PACKAGE}/Tests/CacheWriteChecks.swift" -o "${BUILD}/cache-check"
"${BUILD}/cache-check"
