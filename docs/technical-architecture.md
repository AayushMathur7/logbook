# Technical Architecture

## Current Reality

This branch does not have a daemon, SQLite, or a split app/agent runtime.

The current architecture is:

- `LogbookApp` captures signals in-process
- `LogbookCore` holds shared models and logic
- local JSON files store events, reviews, and settings
- `codex` / `claude` CLIs generate session reviews on demand

## Targets

### `LogbookCore`

Shared code in `Sources/LogbookCore`.

Responsibilities:

- event schema
- persistence helpers
- privacy filtering
- sessionization
- review models

### `LogbookApp`

SwiftUI macOS app in `Sources/LogbookApp`.

Responsibilities:

- UI
- app-side capture
- session timer
- provider selection
- AI review generation

### `logbook`

CLI for reading locally stored events and sessions.

### `logbook-selftest`

Lightweight self-test runner for privacy filtering and sessionization behavior.

## Capture Pipeline

### Workspace events

From `NSWorkspace` notifications:

- app activation
- app launch
- app termination
- wake
- sleep

### Accessibility

When permission is granted:

- focused window title

### Browser adapters

AppleScript-backed tab inspection for supported browsers:

- title
- URL
- domain

### Finder adapter

AppleScript-backed path inspection:

- selected item path or front-window path

### Shell import

The shell hook writes structured command events into:

- `~/Library/Application Support/Logbook/inbox/terminal.tsv`

The app imports those events on a timer.

### File events

`FSEvents` watches configured roots and emits:

- create
- modify
- rename
- delete

### Clipboard

Pasteboard changes are sampled and stored as a short preview.

## Persistence

Files under Application Support:

- `events.json`
- `session-reviews.json`
- `capture-settings.json`

The app writes whole JSON snapshots atomically.

## Session Review Flow

1. Collect all events between `startedAt` and `endedAt`.
2. Build a structured evidence prompt.
3. Send that prompt to the selected provider CLI.
4. Parse the returned JSON into `SessionReview`.
5. Enrich the review locally with:
   - key moments fallback
   - trace
   - app durations
   - switch count
   - inferred repo
   - nearby calendar title
6. Persist the review if it came from a real timed session.

## Provider Integration

`AIProviderBridge` currently supports:

- `codex exec`
- `claude -p`

Both integrations are CLI-based, not SDK-based.

The app stores:

- provider title
- exact prompt
- raw response
- parsed review

## Known Architectural Debt

- capture still runs on the app process
- browser / Finder inspection uses synchronous AppleScript
- AppModel still computes legacy focus / mode / pattern state even though the UI is now session-first
- JSON persistence will become a bottleneck long before search or long-history use cases are solved
