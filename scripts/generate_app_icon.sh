#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/usage-bar-icon.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT
ICONSET="${WORK}/AppIcon.iconset"
mkdir -p "${ICONSET}" "${ROOT}/helper/CodexTouchBarHelper/AppBundle/Resources"
for size in 16 32 128 256 512; do
  sips -z "${size}" "${size}" "${ROOT}/assets/app-icon.png" --out "${ICONSET}/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "${retina}" "${retina}" "${ROOT}/assets/app-icon.png" --out "${ICONSET}/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "${ICONSET}" -o "${ROOT}/helper/CodexTouchBarHelper/AppBundle/Resources/AppIcon.icns"
echo 'Generated AppIcon.icns'
