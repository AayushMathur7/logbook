# Event Model

## Canonical Type

The runtime event model lives in `Sources/DriftlyCore/ActivityModels.swift`.

```json
{
  "id": "evt_01",
  "occurredAt": "2026-04-11T01:23:45Z",
  "source": "browser",
  "kind": "tabChanged",
  "appName": "Google Chrome",
  "bundleID": "com.google.Chrome",
  "windowTitle": "GitHub - AayushMathur7/driftly",
  "path": null,
  "resourceTitle": "AayushMathur7/driftly pull request",
  "resourceURL": "https://github.com/AayushMathur7/driftly/pull/42",
  "domain": "github.com",
  "clipboardPreview": null,
  "noteText": null,
  "relatedID": null,
  "command": null,
  "workingDirectory": null,
  "commandStartedAt": null,
  "commandFinishedAt": null,
  "durationMilliseconds": null,
  "exitCode": null
}
```

## Sources

### `workspace`

- `appActivated`
- `appLaunched`
- `appTerminated`

### `accessibility`

- `windowChanged`

### `browser`

- `tabFocused`
- `tabChanged`

### `presence`

- `userIdle`
- `userResumed`

### `system`

- `systemWoke`
- `systemSlept`
- `clipboardChanged`
- `capturePaused`
- `captureResumed`

### `shell`

- `commandStarted`
- `commandFinished`

### `fileSystem`

- `fileCreated`
- `fileModified`
- `fileRenamed`
- `fileDeleted`

### `manual`

- `noteAdded`
- `sessionPinned`

## High-Value Fields

- `appName` — current app label
- `bundleID` — stable identifier for privacy rules
- `windowTitle` — focused window title when available
- `resourceTitle` — browser title or related resource label
- `resourceURL` — captured URL when allowed
- `domain` — normalized host
- `path` — concrete filesystem path for file events
- `workingDirectory` — shell or Finder context
- `clipboardPreview` — short copied text/URL preview
- `command` — terminal command text

## What The Model Does Not Mean

These events are evidence, not truth.

For example:

- a file modification does not prove deliberate editing
- a YouTube URL does not prove passive drift
- a browser title does not prove understanding

The AI review is built on top of these signals, but the raw signals themselves are not semantic understanding.

## Privacy Rules

Applied before persistence:

- excluded app bundle IDs
- excluded browser domains
- excluded path prefixes
- redacted window-title bundle IDs
- dropped shell-command directory prefixes
- summary-only domains that keep only the domain and drop the full URL
