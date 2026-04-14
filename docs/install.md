# Install

## Current status

Driftly currently runs best for technical users who are comfortable installing a local model and running the app from source.

The polished public install path is still in progress.

## Run from source

From the repo root:

```bash
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build-local/clang-cache \
CLANG_MODULE_CACHE_PATH=$PWD/.build-local/clang-cache \
swift run --scratch-path $PWD/.build-local DriftlyApp
```

## What you need

- macOS 13 or newer
- a local Ollama install if you want AI review
- Accessibility permission if you want window titles and stronger context

## If Ollama is not ready

You can still use Driftly without a local model.

The app will:

- save the session
- keep the local event timeline
- skip AI review generation

## Validation

To verify the repo from source:

```bash
bash scripts/check.sh
```

## Public release gap

This repo now has a scriptable `.app` and `.dmg` packaging path, but it still needs real signing credentials, notarization, and clean-machine release testing for broader distribution.
