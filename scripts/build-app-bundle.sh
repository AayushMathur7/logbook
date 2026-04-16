#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CONFIGURATION="release"
OUTPUT_DIR="${ROOT}/dist"
SCRATCH_PATH=""
APP_NAME="Driftly.app"
DISPLAY_NAME="Driftly"
EXECUTABLE_NAME="DriftlyApp"
BUNDLE_ID="com.aayush.driftly"
VERSION="${DRIFTLY_VERSION:-0.1.0}"
BUILD_NUMBER="${DRIFTLY_BUILD_NUMBER:-1}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --configuration)
      CONFIGURATION="${2:?missing value for --configuration}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:?missing value for --output-dir}"
      shift 2
      ;;
    --scratch-path)
      SCRATCH_PATH="${2:?missing value for --scratch-path}"
      shift 2
      ;;
    --app-name)
      APP_NAME="${2:?missing value for --app-name}"
      shift 2
      ;;
    --display-name)
      DISPLAY_NAME="${2:?missing value for --display-name}"
      shift 2
      ;;
    --bundle-id)
      BUNDLE_ID="${2:?missing value for --bundle-id}"
      shift 2
      ;;
    --version)
      VERSION="${2:?missing value for --version}"
      shift 2
      ;;
    --build-number)
      BUILD_NUMBER="${2:?missing value for --build-number}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

case "${CONFIGURATION}" in
  debug|release)
    ;;
  *)
    echo "Unsupported configuration: ${CONFIGURATION}. Use debug or release." >&2
    exit 1
    ;;
esac

if [[ -z "${SCRATCH_PATH}" ]]; then
  if [[ "${CONFIGURATION}" == "debug" ]]; then
    SCRATCH_PATH="${ROOT}/.build-local"
  else
    SCRATCH_PATH="${ROOT}/.build-release"
  fi
fi

MODULE_CACHE_DIR="${SCRATCH_PATH}/clang-cache"
APP_BUNDLE="${OUTPUT_DIR}/${APP_NAME}"
APP_CONTENTS="${APP_BUNDLE}/Contents"
BINARY_DESTINATION="${APP_CONTENTS}/MacOS/${EXECUTABLE_NAME}"

if [[ -d "${SCRATCH_PATH}" ]]; then
  find "${SCRATCH_PATH}" -type d \( -name ModuleCache -o -name ModuleCache.noindex \) -prune -exec rm -rf {} +
fi
rm -rf "${MODULE_CACHE_DIR}"
mkdir -p "${OUTPUT_DIR}" "${MODULE_CACHE_DIR}"

env \
  SWIFTPM_MODULECACHE_OVERRIDE="${MODULE_CACHE_DIR}" \
  CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_DIR}" \
  swift build \
    -c "${CONFIGURATION}" \
    --scratch-path "${SCRATCH_PATH}" \
    --product "${EXECUTABLE_NAME}"

BINARY_PATH="$(find "${SCRATCH_PATH}" -path "*/${CONFIGURATION}/${EXECUTABLE_NAME}" -type f | head -n 1)"
if [[ -z "${BINARY_PATH}" ]]; then
  echo "Could not find built ${EXECUTABLE_NAME} binary in ${SCRATCH_PATH}." >&2
  exit 1
fi

BUILD_DIR="$(dirname "${BINARY_PATH}")"

rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_CONTENTS}/MacOS" "${APP_CONTENTS}/Resources"

cp "${BINARY_PATH}" "${BINARY_DESTINATION}"
"${ROOT}/scripts/generate-app-icon.sh" "${APP_CONTENTS}/Resources/DriftlyAppIcon.icns"

while IFS= read -r bundle_path; do
  cp -R "${bundle_path}" "${APP_CONTENTS}/Resources/"
done < <(find "${BUILD_DIR}" -maxdepth 1 -type d -name '*.bundle' | sort)

cat > "${APP_CONTENTS}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${EXECUTABLE_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleIconFile</key>
  <string>DriftlyAppIcon</string>
  <key>CFBundleName</key>
  <string>${DISPLAY_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${DISPLAY_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

chmod +x "${BINARY_DESTINATION}"

# Give local builds a stable code identity even without a paid Apple signing cert.
# This helps macOS treat the app more consistently for permissions like Accessibility.
codesign \
  --force \
  --sign - \
  --deep \
  "${APP_BUNDLE}" >/dev/null 2>&1 || true

echo "Built app bundle at:"
echo "${APP_BUNDLE}"
