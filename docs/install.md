# Install

## Current status

LogBook currently runs best for technical users who are comfortable installing a local model and running the app from source.

The polished public install path is still in progress.

## Run from source

From the repo root:

```bash
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build-local/clang-cache \
CLANG_MODULE_CACHE_PATH=$PWD/.build-local/clang-cache \
swift run --scratch-path $PWD/.build-local LogbookApp
```

## What you need

- macOS 13 or newer
- a local Ollama install if you want AI review
- Accessibility permission if you want window titles and stronger context

## If Ollama is not ready

You can still use LogBook without a local model.

The app will:

- save the session
- keep the local event timeline
- write a simpler local recap instead of the richer AI review

## Validation

To verify the repo from source:

```bash
bash scripts/check.sh
```

## Public release gap

This repo still needs a polished signed and notarized macOS release flow for broader distribution.
