# Logbook

Logbook is a local-first macOS app for running intentional work sessions and getting an AI review of what actually happened during the block.

The current product is not a passive timeline or a background daemon. It is a session-based app with four surfaces:

- `Session` — start a timed session or generate a review for the last `N` minutes
- `History` — browse completed timed-session reviews
- `Signals` — inspect raw captured events
- `Settings` — capture rules, watch roots, and AI provider selection

## What Exists Today

The repository currently ships:

- a SwiftUI macOS app in `Sources/LogbookApp`
- a shared core library in `Sources/LogbookCore`
- a small CLI in `Sources/logbook`
- a self-test runner in `Sources/logbookselftest`
- local JSON persistence under `~/Library/Application Support/Logbook`
- optional `codex` and `claude` CLI integrations for AI-written reviews

## Core Workflow

1. Enter a session goal and duration.
2. Start the session.
3. Let Logbook capture lightweight desktop signals.
4. When the timer ends, Logbook sends the session evidence to `codex` or `claude`.
5. Review:
   - what you were actually doing
   - whether it matched the goal
   - what interrupted or took over
   - key moments
   - a trace of the captured evidence

There is also a `Generate review` tester on the Session screen for reviewing the last `N` minutes without waiting for a timer.

## Captured Signals

Current capture includes:

- frontmost app activation, launch, and termination
- wake and sleep
- focused window title changes when Accessibility is granted
- browser tab title + URL for supported browsers
- Finder selection / front-window path when available
- shell commands imported from `integrations/shell/logbook.zsh`
- file activity under watched roots
- clipboard changes with a short preview
- manual quick notes and pinned session reviews

## Storage

Current storage is JSON, not SQLite:

- `events.json`
- `session-reviews.json`
- `capture-settings.json`

All are stored under `~/Library/Application Support/Logbook`.

## Quick Start

```bash
cd /Users/aayush/ai-projects/logbook
swift build
bash scripts/check.sh
swift run LogbookApp
```

Useful extras:

```bash
swift run logbook view
swift run logbook view --events --limit 20
swift run logbook view --summary
swift run logbook-selftest
```

## Shell Hook

If you want exact terminal commands in reviews and traces, add this to `~/.zshrc`:

```zsh
source /Users/aayush/ai-projects/logbook/integrations/shell/logbook.zsh
```

Then open a new shell session.

## AI Providers

Logbook currently supports:

- `Codex CLI`
- `Claude Code`

The app shells out to the selected provider and stores:

- the rendered review
- the exact prompt
- the raw provider response

The `Model I/O` section in the review UI shows that debug data.

## Docs

- `docs/v1-spec.md` — current product scope
- `docs/technical-architecture.md` — actual runtime architecture
- `docs/event-model.md` — captured event schema and sources
- `docs/tracking-guide.md` — how session reviews are built
- `docs/testing.md` — build and verification path
