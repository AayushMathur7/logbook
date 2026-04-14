# Technical Architecture

## Current Reality

The current architecture is:

- `LogbookApp` captures signals in-process
- `LogbookCore` holds shared models, privacy rules, timeline derivation, and storage
- local SQLite stores events, sessions, reviews, settings, and review feedback
- Ollama is the only review provider and is restricted to localhost

There is no daemon process today. Capture starts and stops from the app itself.

## Main Components

### `LogbookCore`

Shared code in `Sources/LogbookCore`.

Responsibilities:

- event schema
- capture settings
- privacy filtering
- sessionization
- timeline and attention derivation
- session review models
- SQLite persistence

### `LogbookApp`

SwiftUI macOS app in `Sources/LogbookApp`.

Responsibilities:

- session-first UI
- app-side capture
- permission handling
- session timer
- review generation
- history and feedback flows

### `logbook`

CLI for inspecting locally stored events and sessions.

### `logbook-selftest`

Self-test runner for privacy filtering, timeline derivation, observability logic, and review feedback persistence.

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

### Clipboard and presence

The app also captures:

- short clipboard previews
- user idle and resume events

## Persistence

The runtime database lives at:

- `~/Library/Application Support/Logbook/logbook.sqlite`

The store currently persists:

- raw events
- saved sessions
- generated reviews
- capture settings
- review feedback
- review learning memory

## Session Review Flow

1. Collect all events between `startedAt` and `endedAt`.
2. Derive timeline segments and intent-aware observations.
3. Build a structured prompt from the goal, events, and derived timeline.
4. Send the prompt to Ollama over localhost.
5. Parse the result into a short review.
6. Enrich the review locally with inline spans, dominant apps, session path, and attention segments.
7. Persist the review if it came from a completed timed session.

## Privacy Model

Privacy filtering happens before persistence.

Current controls include:

- excluded app bundle IDs
- excluded browser domains
- excluded path prefixes
- redacted title bundle IDs
- dropped shell-command directory prefixes
- summary-only domains that keep only the domain and drop the full URL

## Known Architectural Debt

- capture still runs in the app process instead of a separate background component
- browser and Finder inspection still depend on synchronous AppleScript
- `AppModel` owns a large amount of state and orchestration logic
- first-run setup still depends on manual permissions, shell setup, and local model configuration
