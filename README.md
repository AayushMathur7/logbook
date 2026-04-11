# Log Book

Log Book is a local-first macOS app for running intentional sessions and getting a review of what actually happened on your machine during that block.

The app is built around one loop:

1. Write what you want to do.
2. Start a timed session.
3. Let Log Book capture local evidence during the block.
4. End the session or let the timer finish.
5. Read a short review of what happened and whether the session matched the stated intent.

## Current Product Shape

Log Book is not an always-on memory product and it is not a passive life log.

The app is session-bounded:

- `Session` for starting a block, running it, generating the review, and reading the latest review
- `History` for reviewing saved sessions again
- `Settings` for capture toggles and local model configuration

The review logic is now intent-aware. That means surfaces like `YouTube`, `X`, `Spotify`, or `GitHub` are not treated as inherently good or bad. They are judged relative to what you said you wanted to do in that session.

Examples:

- `watch YouTube` can count as a matched session if the block mostly stayed on YouTube
- `deploy logbook to GitHub` can count GitHub, coding tools, and repo context as aligned or adjacent
- `scroll X` can be valid if that was explicitly the stated intent

## Architecture

The repo currently ships:

- a SwiftUI macOS app in `Sources/LogbookApp`
- a shared core library in `Sources/LogbookCore`
- a small CLI in `Sources/logbook`
- a self-test runner in `Sources/logbookselftest`

## Capture Model

Log Book captures lightweight local signals during a session.

Current capture includes:

- frontmost app activation, launch, and termination
- wake and sleep
- focused window title changes when Accessibility is granted
- browser tab titles, URLs, and domains for supported browsers
- Finder context when available
- shell commands imported from `integrations/shell/logbook.zsh`
- file activity under watched roots
- clipboard changes with a short preview
- calendar context when access is granted

The app does not capture screenshots, audio, OCR, camera, microphone, or keystrokes.

## Storage

Runtime storage is SQLite under:

```text
~/Library/Application Support/Logbook/logbook.sqlite
```

Saved data includes:

- raw events
- sessions
- derived session segments
- generated reviews
- capture settings

## Local Review Generation

Log Book currently uses `Ollama` for local review generation.

Important constraints:

- localhost only
- no cloud model fallback
- no remote API hosts
- reviews still work with a local fallback summary if Ollama is not configured or its response cannot be parsed

The current default base URL is:

```text
http://127.0.0.1:11434
```

## Running the App

From the repo root:

```bash
cd /Users/aayush/ai-projects/logbook
swift build
./.build/debug/LogbookApp
```

If an older process is still running, quit it first or kill it before relaunching:

```bash
pkill -f LogbookApp || true
cd /Users/aayush/ai-projects/logbook
swift build
./.build/debug/LogbookApp
```

Running the built binary directly is currently more reliable than `swift run LogbookApp` on this machine.

## Validation

Build:

```bash
swift build
```

Run the self-test suite:

```bash
swift run logbook-selftest
```

Useful CLI commands:

```bash
swift run logbook view
swift run logbook view --events --limit 20
swift run logbook view --summary
```

## Shell Hook

If you want exact terminal commands to show up in captured evidence, add this to `~/.zshrc`:

```zsh
source /Users/aayush/ai-projects/logbook/integrations/shell/logbook.zsh
```

Then open a new shell session.

## Privacy Notes

The app is designed to stay local:

- capture happens on-device
- storage stays on-device
- review generation stays local through Ollama

Privacy filtering and exclusions are configured in `Settings`.

## Key Files

- `Sources/LogbookApp/ContentView.swift` — main app surface and layout
- `Sources/LogbookApp/AppModel.swift` — session lifecycle, persistence wiring, review orchestration
- `Sources/LogbookApp/AIProviderBridge.swift` — Ollama integration and review prompt construction
- `Sources/LogbookCore/TimelineDeriver.swift` — evidence segmentation and intent-aware alignment
- `Sources/LogbookCore/SessionStore.swift` — SQLite persistence
- `Sources/logbookselftest/main.swift` — self-test coverage
