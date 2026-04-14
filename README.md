# LogBook

LogBook is a local-first macOS app that helps you compare the work you planned with the work that actually happened during a session.

You type a goal, start a timer, let the app capture lightweight local signals, and then read a short review in plain English.

The product is intentionally opinionated:

- it compares the session against the goal you typed
- it gives you a short recap instead of a dashboard
- it uses local evidence instead of generic productivity scores

## Core Loop

1. Write what you are focusing on.
2. Pick a session length.
3. Start the session.
4. Let LogBook capture lightweight local evidence during the block.
5. End the block or let the timer finish.
6. Read a short review and save it to history.

Current UX:

- `Session` is the main surface for setup, running, and the latest review.
- `History` lets you reopen past sessions and retry their reviews.
- `Settings` controls capture sources, privacy rules, retention, and local model configuration.

## Product Shape

LogBook is built around intent, not a hardcoded idea of productivity.

Examples:

- `watch YouTube` can be a matched session if the block mostly stayed on YouTube
- `deploy logbook to github` can count GitHub, coding tools, and repo context as aligned work
- `get my day ready` is broader, so the review should describe the block honestly instead of pretending it has stronger certainty than the evidence supports

The review UI currently focuses on:

- a one-line headline
- a short recap in plain language
- a short takeaway line
- inline app, site, and repo chips
- clickable inline links when the session captured a real URL for that mention
- saved history for past sessions
- per-review feedback so the app can learn what framing was helpful or wrong

In simple terms:

- you say what this block is for
- LogBook watches lightweight local signals during that block
- at the end, it tells you whether the block stayed on track

## What It Captures

LogBook captures lightweight local signals during a session window.

Current capture includes:

- frontmost app changes, launches, and terminations
- wake and sleep
- active window titles when Accessibility is granted
- browser page titles, URLs, and domains for supported browsers
- Finder context when available
- shell commands imported from `integrations/shell/logbook.zsh`
- file activity under watched roots
- clipboard changes with a short preview

It does not capture:

- screenshots
- OCR
- audio recordings
- camera or microphone
- keystrokes

## Why It Stays Lightweight

The app is designed to stay small and local:

- capture is session-scoped and event-based rather than media-heavy
- there is no screenshot, screen recording, or transcript pipeline
- storage stays in a local SQLite database under Application Support
- raw events are pruned by retention settings
- model calls are restricted to a local Ollama host

Runtime storage lives at:

```text
~/Library/Application Support/Logbook/logbook.sqlite
```

## Local Review Generation

LogBook currently uses Ollama for AI review generation.

Important constraints:

- localhost only
- no cloud fallback
- no remote model hosts
- no hidden network calls beyond your configured local Ollama instance

Default base URL:

```text
http://127.0.0.1:11434
```

If Ollama is not configured or fails, the app still saves the session and can fall back to a local non-LLM review.

## Repository Layout

This repo currently contains:

- `Sources/LogbookApp` for the SwiftUI macOS app
- `Sources/LogbookCore` for shared models, SQLite storage, privacy rules, and timeline derivation
- `Sources/logbook` for a small CLI to inspect stored data
- `Sources/logbookselftest` for the self-test runner

Key files:

- `Sources/LogbookApp/ContentView.swift` for the main app surface
- `Sources/LogbookApp/AppModel.swift` for session lifecycle, capture orchestration, history, and review persistence
- `Sources/LogbookApp/AIProviderBridge.swift` for Ollama integration, prompt construction, and review parsing
- `Sources/LogbookApp/UI/MarkdownText.swift` for inline review rendering and linked badges
- `Sources/LogbookCore/TimelineDeriver.swift` for timeline enrichment and intent-aware interpretation
- `Sources/LogbookCore/SessionStore.swift` for SQLite persistence

## Running The App

From the repo root:

```bash
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build-local/clang-cache \
CLANG_MODULE_CACHE_PATH=$PWD/.build-local/clang-cache \
swift run --scratch-path $PWD/.build-local LogbookApp
```

If you prefer to build first:

```bash
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build-local/clang-cache \
CLANG_MODULE_CACHE_PATH=$PWD/.build-local/clang-cache \
swift build --scratch-path $PWD/.build-local

./.build-local/debug/LogbookApp
```

## Validation

Run the default verification path from the repo root:

```bash
bash scripts/check.sh
```

Useful CLI commands:

```bash
swift run --scratch-path $PWD/.build-local logbook view
swift run --scratch-path $PWD/.build-local logbook view --events --limit 20
swift run --scratch-path $PWD/.build-local logbook view --summary
```

## Shell Integration

If you want terminal commands to show up in captured evidence, add this to your shell config:

```zsh
source "/absolute/path/to/logbook/integrations/shell/logbook.zsh"
```

Then open a new shell session.

## Privacy Notes

The app is designed to stay local:

- capture happens on-device
- storage stays on-device
- review generation stays local through Ollama

Exclusions, redactions, retention, and watched paths are configured in `Settings`.

See also:

- `LICENSE`
- `PRIVACY.md`
- `SECURITY.md`
- `docs/install.md`
- `docs/release-macos.md`
- `docs/launch-checklist.md`

## Current Limitations

- review quality still depends on the captured evidence and prompt quality
- app and browser context are best-effort and depend on macOS permissions
- browser and Finder inspection still depend on AppleScript and can be flaky
- the current launch story is optimized for technical users who can run a local model
