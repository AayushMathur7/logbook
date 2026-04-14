#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

OUTPUT_DIR="${ROOT}/dist/release"
SCRATCH_PATH="${ROOT}/.build-release"
APP_NAME="Driftly.app"
DISPLAY_NAME="Driftly"
VOLUME_NAME="Driftly"
DMG_NAME="Driftly.dmg"
BUNDLE_ID="${DRIFTLY_BUNDLE_ID:-com.aayush.driftly}"
VERSION="${DRIFTLY_VERSION:-0.1.0}"
BUILD_NUMBER="${DRIFTLY_BUILD_NUMBER:-1}"
SIGN_IDENTITY="${MACOS_DEVELOPER_IDENTITY:-}"
NOTARY_PROFILE="${APPLE_NOTARY_PROFILE:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
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
    --volume-name)
      VOLUME_NAME="${2:?missing value for --volume-name}"
      shift 2
      ;;
    --dmg-name)
      DMG_NAME="${2:?missing value for --dmg-name}"
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
    --sign-identity)
      SIGN_IDENTITY="${2:?missing value for --sign-identity}"
      shift 2
      ;;
    --notary-profile)
      NOTARY_PROFILE="${2:?missing value for --notary-profile}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

APP_OUTPUT_DIR="${OUTPUT_DIR}/app"
APP_BUNDLE="${APP_OUTPUT_DIR}/${APP_NAME}"
DMG_PATH="${OUTPUT_DIR}/${DMG_NAME}"
DMG_STAGING_DIR="${OUTPUT_DIR}/dmg-root"

rm -rf "${APP_OUTPUT_DIR}" "${DMG_STAGING_DIR}" "${DMG_PATH}"
mkdir -p "${APP_OUTPUT_DIR}" "${DMG_STAGING_DIR}" "${OUTPUT_DIR}"

"${ROOT}/scripts/build-app-bundle.sh" \
  --configuration release \
  --output-dir "${APP_OUTPUT_DIR}" \
  --scratch-path "${SCRATCH_PATH}" \
  --app-name "${APP_NAME}" \
  --display-name "${DISPLAY_NAME}" \
  --bundle-id "${BUNDLE_ID}" \
  --version "${VERSION}" \
  --build-number "${BUILD_NUMBER}"

if [[ -n "${SIGN_IDENTITY}" ]]; then
  codesign \
    --force \
    --sign "${SIGN_IDENTITY}" \
    --deep \
    --options runtime \
    --timestamp \
    "${APP_BUNDLE}"

  codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
  spctl --assess --type execute --verbose=2 "${APP_BUNDLE}"
fi

cp -R "${APP_BUNDLE}" "${DMG_STAGING_DIR}/"
ln -s /Applications "${DMG_STAGING_DIR}/Applications"

hdiutil create \
  -volname "${VOLUME_NAME}" \
  -srcfolder "${DMG_STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

if [[ -n "${SIGN_IDENTITY}" ]]; then
  codesign \
    --force \
    --sign "${SIGN_IDENTITY}" \
    --timestamp \
    "${DMG_PATH}"
fi

if [[ -n "${NOTARY_PROFILE}" ]]; then
  xcrun notarytool submit "${DMG_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait
  xcrun stapler staple "${DMG_PATH}"
fi

echo "Packaged DMG at:"
echo "${DMG_PATH}"
