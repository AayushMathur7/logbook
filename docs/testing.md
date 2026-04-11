# Testing

## Default Verification Path

```bash
cd /Users/aayush/ai-projects/logbook
bash scripts/check.sh
```

That currently does:

1. required-file checks
2. `swift build`
3. `swift run logbook-selftest`

## Self-Test Coverage

The self-test target currently checks:

- privacy exclusion by app bundle ID
- privacy exclusion by domain
- privacy exclusion by path prefix
- title redaction
- summary-only domain stripping
- sessionizer idle boundary behavior
- sessionizer browser-domain continuity behavior
- ignoring capture pause / resume as work content

## Manual Checks Worth Doing

The automated tests do not cover:

- live `NSWorkspace` capture
- browser AppleScript behavior
- Finder AppleScript behavior
- Accessibility permission behavior
- FSEvents behavior
- provider CLI behavior for real prompts
- SwiftUI session / history flows

For manual verification, run:

```bash
swift run LogbookApp
```

Then verify:

- a session can start and finish
- a review can be generated from the last `N` minutes
- History stores completed timed sessions
- Signals show browser titles / URLs, Finder paths, and clipboard previews when captured
- Model I/O shows provider, prompt, and raw response
