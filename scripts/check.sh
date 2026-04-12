#!/usr/bin/env bash

set -euo pipefail

required_files=(
  "README.md"
  "Package.swift"
  "docs/v1-spec.md"
  "docs/technical-architecture.md"
  "docs/event-model.md"
  "integrations/shell/logbook.zsh"
)

for path in "${required_files[@]}"; do
  if [[ ! -f "$path" ]]; then
    echo "Missing required file: $path"
    exit 1
  fi
done

export SWIFTPM_MODULECACHE_OVERRIDE="${PWD}/.build-local/clang-cache"
export CLANG_MODULE_CACHE_PATH="${PWD}/.build-local/clang-cache"

swift build --scratch-path "${PWD}/.build-local"
swift run --scratch-path "${PWD}/.build-local" logbook-selftest

echo "Scaffold and build check passed."
