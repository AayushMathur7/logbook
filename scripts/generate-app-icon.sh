#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_PATH="${1:-${ROOT}/dist/DriftlyAppIcon.icns}"
SOURCE_ICON="${ROOT}/Sources/DriftlyApp/Resources/DriftlyAppIconSource.png"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/driftly-icon.XXXXXX")"
ICONSET_DIR="${WORK_DIR}/Driftly.iconset"

cleanup() {
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

mkdir -p "${ICONSET_DIR}" "$(dirname "${OUTPUT_PATH}")"

if [[ ! -f "${SOURCE_ICON}" ]]; then
  echo "Missing source icon at ${SOURCE_ICON}" >&2
  exit 1
fi

specs=(
  "icon_16x16.png:16"
  "icon_16x16@2x.png:32"
  "icon_32x32.png:32"
  "icon_32x32@2x.png:64"
  "icon_128x128.png:128"
  "icon_128x128@2x.png:256"
  "icon_256x256.png:256"
  "icon_256x256@2x.png:512"
  "icon_512x512.png:512"
  "icon_512x512@2x.png:1024"
)

for spec in "${specs[@]}"; do
  filename="${spec%%:*}"
  size="${spec##*:}"
  sips -s format png -z "${size}" "${size}" "${SOURCE_ICON}" --out "${ICONSET_DIR}/${filename}" >/dev/null
done

iconutil -c icns "${ICONSET_DIR}" -o "${OUTPUT_PATH}"
