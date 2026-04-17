#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mkdir -p "${ROOT}/.swift-module-cache" "${ROOT}/.clang-module-cache" /tmp/driftly-build-local

export SWIFTPM_MODULECACHE_OVERRIDE="${ROOT}/.swift-module-cache"
export CLANG_MODULE_CACHE_PATH="${ROOT}/.clang-module-cache"

bash "${ROOT}/scripts/build-app-bundle.sh" \
  --configuration debug \
  --output-dir "${ROOT}/dist" \
  --scratch-path /tmp/driftly-build-local \
  --app-name "Driftly.app" \
  --display-name "Driftly" \
  --bundle-id "com.aayush.driftly.dev" \
  --version "0.1" \
  --build-number "1"
