#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT}/dist"
APP_NAME="Driftly.app"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}"
BUNDLE_EXECUTABLE="${APP_BUNDLE}/Contents/MacOS/DriftlyApp"
LOG_PATH="${DIST_DIR}/driftlyapp.log"

is_running() {
  ps -Ao command | grep -F "${BUNDLE_EXECUTABLE}" | grep -v grep >/dev/null 2>&1
}

mkdir -p "${DIST_DIR}"

BINARY_PATH="$(find "${ROOT}/.build" -path '*/debug/DriftlyApp' -type f | head -n 1)"
if [[ -z "${BINARY_PATH}" ]]; then
  swift build --product DriftlyApp
  BINARY_PATH="$(find "${ROOT}/.build" -path '*/debug/DriftlyApp' -type f | head -n 1)"
fi

if [[ -z "${BINARY_PATH}" ]]; then
  echo "Could not find built DriftlyApp binary."
  exit 1
fi

BUILD_DIR="$(dirname "${BINARY_PATH}")"

rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BINARY_PATH}" "${BUNDLE_EXECUTABLE}"

while IFS= read -r bundle_path; do
  cp -R "${bundle_path}" "${APP_BUNDLE}/Contents/Resources/"
done < <(find "${BUILD_DIR}" -maxdepth 1 -type d -name '*.bundle' | sort)

cat > "${APP_BUNDLE}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>DriftlyApp</string>
  <key>CFBundleIdentifier</key>
  <string>com.aayush.driftly.dev</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Driftly</string>
  <key>CFBundleDisplayName</key>
  <string>Driftly</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

chmod +x "${APP_BUNDLE}/Contents/MacOS/DriftlyApp"

if is_running; then
  osascript -e 'tell application "System Events" to tell process "DriftlyApp" to set frontmost to true' >/dev/null 2>&1 || true
  echo "Driftly is already running."
  echo "Built app bundle at:"
  echo "${APP_BUNDLE}"
  exit 0
fi

rm -f "${LOG_PATH}"
nohup "${BUNDLE_EXECUTABLE}" >"${LOG_PATH}" 2>&1 &
sleep 1

if is_running; then
  osascript -e 'tell application "System Events" to tell process "DriftlyApp" to set frontmost to true' >/dev/null 2>&1 || true
  echo "Built app bundle at:"
  echo "${APP_BUNDLE}"
  echo
  echo "Launched Driftly."
  exit 0
fi

echo "Built app bundle at:"
echo "${APP_BUNDLE}"
echo
echo "Driftly did not stay running."
echo "Check the launch log at:"
echo "${LOG_PATH}"
exit 1
