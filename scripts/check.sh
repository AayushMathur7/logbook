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

swift build
swift run logbook-selftest

echo "Scaffold and build check passed."
