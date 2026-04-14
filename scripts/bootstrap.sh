#!/usr/bin/env bash

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Driftly targets macOS. Current platform: $(uname -s)"
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift is required. Install Xcode or Command Line Tools first."
  exit 1
fi

mkdir -p .local/state/driftly
mkdir -p tmp
swift build

cat <<'EOF'
Bootstrap complete.

Prepared:
- .local/state/driftly
- tmp
- Swift build artifacts

Next:
- run `swift run DriftlyApp`
- grant Accessibility access if you want focused window titles
- source `integrations/shell/driftly.zsh` from `.zshrc` for terminal command capture
EOF
