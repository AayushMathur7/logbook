# Driftly

Driftly is a local-first macOS app that tells you whether your work session actually matched the goal you started with.

You type a goal, start a session, do your work, and Driftly gives you a short review in plain English at the end.

## Why It Exists

Most productivity tools measure activity.

Driftly measures alignment.

It is built to answer one question:

Did this block become the thing I meant to do?

## Quick Start

1. Clone the repo on a Mac running macOS 13 or newer.
2. Run Driftly from the repo root:

```bash
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build-local/clang-cache \
CLANG_MODULE_CACHE_PATH=$PWD/.build-local/clang-cache \
swift run --scratch-path $PWD/.build-local DriftlyApp
```

3. Grant Accessibility when macOS asks.
4. Start one session with a clear goal.
5. Read the review at the end.

If you want AI review generation, install Ollama locally first. If not, Driftly still works and falls back to a simpler local review.

## Setup

Required or recommended setup:

- macOS 13 or newer
- Accessibility if you want window titles and richer context
- Ollama if you want AI review generation
- shell integration if you want terminal commands captured

Shell integration:

```zsh
source "/absolute/path/to/driftly/integrations/shell/driftly.zsh"
```

## What It Captures

Depending on your settings, Driftly can capture:

- app switches, launches, and quits
- wake and sleep events
- active window titles
- browser page titles, domains, and URLs
- Finder context
- shell commands through the shell integration
- file activity under watched roots
- clipboard previews

It does not capture:

- screenshots
- screen recordings
- keystrokes
- audio
- camera or microphone input

## Privacy

Driftly is designed to stay local.

- captured session data stays on your Mac
- the database lives at `~/Library/Application Support/Driftly/driftly.sqlite`
- AI review generation is local through Ollama
- there is no cloud fallback

See [PRIVACY.md](/Users/aayush/ai-projects/driftly/PRIVACY.md:1) for the full privacy model.

## Current Status

Driftly is usable now, but it is not yet packaged as a polished signed and notarized public Mac download.

See:

- [docs/install.md](/Users/aayush/ai-projects/driftly/docs/install.md:1)
- [docs/release-macos.md](/Users/aayush/ai-projects/driftly/docs/release-macos.md:1)
- [docs/launch-checklist.md](/Users/aayush/ai-projects/driftly/docs/launch-checklist.md:1)

## Validation

```bash
bash scripts/check.sh
```

## For Builders

- `Sources/DriftlyApp` contains the SwiftUI macOS app
- `Sources/DriftlyCore` contains shared models, storage, privacy rules, and timeline logic
- `Sources/driftly` contains the small CLI
- `Sources/driftlyselftest` contains the self-test runner

## More

- [LICENSE](/Users/aayush/ai-projects/driftly/LICENSE:1)
- [SECURITY.md](/Users/aayush/ai-projects/driftly/SECURITY.md:1)
