# Testing

## Default Verification Path

From the repo root:

```bash
bash scripts/check.sh
```

That currently does:

1. required-file checks
2. `swift build`
3. `swift run driftly-selftest`

## Self-Test Coverage

The self-test target currently checks:

- privacy exclusion by app bundle ID
- privacy exclusion by domain
- privacy exclusion by path prefix
- title redaction
- summary-only domain stripping
- sessionizer idle boundary behavior
- sessionizer browser-domain continuity behavior
- ignoring capture pause and resume as work content
- timeline derivation for common work and media surfaces
- observability classification for direct work, support work, and drift
- review-feedback persistence and prompt-ready example filtering

## Manual Checks Worth Doing

The automated tests do not cover:

- live `NSWorkspace` capture
- browser AppleScript behavior
- Finder AppleScript behavior
- Accessibility permission behavior
- FSEvents behavior
- real Ollama connectivity and model behavior
- SwiftUI session and history flows

For manual verification, run:

```bash
swift run DriftlyApp
```

Then verify:

- a session can start and finish
- a review can be generated with a configured local Ollama model
- History stores completed timed sessions
- review retry works from History
- browser titles, URLs, Finder paths, and clipboard previews appear only when the relevant capture sources and permissions are enabled
- privacy exclusions and redactions behave as expected
- shell command import works when the shell hook is installed
