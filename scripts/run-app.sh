#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT}/dist"
APP_NAME="Driftly.app"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}"
BUNDLE_EXECUTABLE="${APP_BUNDLE}/Contents/MacOS/DriftlyApp"

is_running() {
  pgrep -x "DriftlyApp" >/dev/null 2>&1 \
    || pgrep -x "Driftly" >/dev/null 2>&1 \
    || pgrep -fx "${BUNDLE_EXECUTABLE}" >/dev/null 2>&1
}

"${ROOT}/scripts/build-app-bundle.sh" \
  --configuration debug \
  --output-dir "${DIST_DIR}" \
  --scratch-path "${ROOT}/.build-local" \
  --app-name "${APP_NAME}" \
  --display-name "Driftly" \
  --bundle-id "com.aayush.driftly.dev" \
  --version "0.1" \
  --build-number "1"

if is_running; then
  open "${APP_BUNDLE}" >/dev/null 2>&1 || true
  echo "Driftly is already running."
  echo "Built app bundle at:"
  echo "${APP_BUNDLE}"
  exit 0
fi

open "${APP_BUNDLE}"
sleep 2

if is_running; then
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
echo "Open the bundle manually from Finder or use Console.app if macOS blocked the launch."
exit 1
