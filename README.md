# Log Book

Log Book is a local-only macOS app for reviewing what actually happened during a focused session.

You write what you want to focus on, start a timer, let the app capture lightweight local evidence during the block, and then read a short review of how the session actually went.

The product is not an always-on memory app and it is not a blocker like SelfControl. The point is not to stop you from drifting. The point is to show you, clearly and locally, what the session turned into.

## What The App Does

The app is built around one loop:

1. Write what you are focusing on.
2. Pick a session length.
3. Start the session.
4. Let Log Book capture local evidence during the block.
5. End the block or let the timer finish.
6. Read a short review and save it to history.

Current UX:

- `Session` is the main surface for setup, running, generating, and the latest review.
- `History` lets you reopen past sessions and retry their reviews.
- `Settings` controls capture sources and Ollama configuration.

The review is intentionally short. It is meant to read like a one-screen recap, not a dashboard.

## Product Shape

Log Book judges a session against the intent you typed, not against a hardcoded idea of productivity.

Examples:

- `I wanna just watch YouTube` can be a matched session if the block mostly stayed on YouTube.
- `deploy logbook to github` can count GitHub, coding tools, and repo context as aligned work.
- `help me get my day ready` is treated as broader and fuzzier, so the review should describe the block honestly rather than pretending it knows more than the evidence shows.

The review UI currently supports:

- a one-line headline for the session
- a short recap in plain language
- a short takeaway line
- inline app/site/repo badges
- clickable inline links when the session captured a real URL for that mention
- stored history for past sessions

## Capture Model

Log Book captures lightweight local signals during a session window.

Current capture includes:

- frontmost app changes, launches, and terminations
- wake and sleep
- active window titles when Accessibility is granted
- browser page titles, URLs, and domains for supported browsers
- Finder context when available
- shell commands imported from `integrations/shell/logbook.zsh`
- file activity under watched roots
- clipboard changes with a short preview
- nearby calendar context when Calendar access is granted

The app does not capture:

- screenshots
- OCR
- audio recordings
- camera or microphone
- keystrokes

## Storage

Runtime storage is SQLite under:

```text
~/Library/Application Support/Logbook/logbook.sqlite
```

Stored data includes:

- raw captured events
- sessions
- derived timeline segments
- saved reviews
- capture and Ollama settings

Raw events are pruned by retention settings. Session history and reviews stay until deleted.

## Local Review Generation

Log Book currently uses Ollama only.

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

## Architecture

This repo currently contains:

- `Sources/LogbookApp` — the SwiftUI macOS app
- `Sources/LogbookCore` — shared models, SQLite store, and timeline derivation
- `Sources/logbook` — a small CLI for inspecting stored data
- `Sources/logbookselftest` — a self-test runner

Core files:

- [Sources/LogbookApp/ContentView.swift](/Users/aayush/ai-projects/logbook/Sources/LogbookApp/ContentView.swift) — main app surface and state-driven UI
- [Sources/LogbookApp/AppModel.swift](/Users/aayush/ai-projects/logbook/Sources/LogbookApp/AppModel.swift) — session lifecycle, capture orchestration, history selection, and review persistence
- [Sources/LogbookApp/AIProviderBridge.swift](/Users/aayush/ai-projects/logbook/Sources/LogbookApp/AIProviderBridge.swift) — Ollama prompt construction and review parsing
- [Sources/LogbookApp/UI/MarkdownText.swift](/Users/aayush/ai-projects/logbook/Sources/LogbookApp/UI/MarkdownText.swift) — inline review rendering, badges, emphasis, and inline links
- [Sources/LogbookCore/TimelineDeriver.swift](/Users/aayush/ai-projects/logbook/Sources/LogbookCore/TimelineDeriver.swift) — timeline enrichment and intent-aware interpretation
- [Sources/LogbookCore/SessionStore.swift](/Users/aayush/ai-projects/logbook/Sources/LogbookCore/SessionStore.swift) — SQLite persistence

## Running The App

From the repo root:

```bash
cd /Users/aayush/ai-projects/logbook
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build-local/clang-cache CLANG_MODULE_CACHE_PATH=$PWD/.build-local/clang-cache swift run --scratch-path $PWD/.build-local LogbookApp
```

If you prefer to build first:

```bash
cd /Users/aayush/ai-projects/logbook
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build-local/clang-cache CLANG_MODULE_CACHE_PATH=$PWD/.build-local/clang-cache swift build --scratch-path $PWD/.build-local
./.build-local/debug/LogbookApp
```

If another instance is already running:

```bash
pkill -f LogbookApp
```

Then relaunch with one of the commands above.

## Validation

Build:

```bash
cd /Users/aayush/ai-projects/logbook
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build-local/clang-cache CLANG_MODULE_CACHE_PATH=$PWD/.build-local/clang-cache swift build --scratch-path $PWD/.build-local
```

Run self-tests:

```bash
cd /Users/aayush/ai-projects/logbook
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build-local/clang-cache CLANG_MODULE_CACHE_PATH=$PWD/.build-local/clang-cache swift run --scratch-path $PWD/.build-local logbook-selftest
```

Useful CLI commands:

```bash
cd /Users/aayush/ai-projects/logbook
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build-local/clang-cache CLANG_MODULE_CACHE_PATH=$PWD/.build-local/clang-cache swift run --scratch-path $PWD/.build-local logbook view
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build-local/clang-cache CLANG_MODULE_CACHE_PATH=$PWD/.build-local/clang-cache swift run --scratch-path $PWD/.build-local logbook view --events --limit 20
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build-local/clang-cache CLANG_MODULE_CACHE_PATH=$PWD/.build-local/clang-cache swift run --scratch-path $PWD/.build-local logbook view --summary
```

## Shell Hook

If you want terminal commands to show up in captured evidence, add this to `~/.zshrc`:

```zsh
source /Users/aayush/ai-projects/logbook/integrations/shell/logbook.zsh
```

Then open a new shell session.

## Privacy Notes

The app is designed to stay local:

- capture happens on-device
- storage stays on-device
- review generation stays local through Ollama

Exclusions and redactions are configured in `Settings`.

## Current Limitations

- The review quality still depends on the captured evidence and prompt quality.
- Old saved reviews may not have newer inline features like clickable links until they are retried.
- App and browser context is best-effort and depends on macOS permissions.
- Some surfaces, especially broad goals, still need prompt tuning to produce cleaner summaries.
