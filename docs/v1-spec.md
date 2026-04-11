# Logbook V1 Spec

## Product

Logbook is a session-based macOS app for answering one question at the end of a work block:

`What was I actually doing, and did it match what I meant to do?`

V1 is intentionally narrow. It is not trying to be a daemon, a time tracker, or a second-brain system.

## V1 User Workflow

### Timed session

1. Enter a goal.
2. Pick a duration.
3. Start the session.
4. Let the block run quietly.
5. Read the AI review when the block ends.

### Manual test review

1. Enter an optional test goal.
2. Choose a minute range.
3. Click `Generate review`.
4. Inspect the exact same review format used for a timed session.

## Main UI

### Session

The primary screen.

Shows:

- session setup
- active timer
- completed session review
- quick note input
- test-review controls

### History

Stores completed timed-session reviews only.

Each row shows:

- review headline
- session goal
- time range

### Signals

Debug surface for raw captured events.

This is not the main product surface.

### Settings

Contains:

- capture toggle
- Accessibility / calendar status
- watch roots and privacy rules
- provider availability

## Output Format

Each completed review is organized around:

- `headline`
- `goal`
- `time range`
- `why`
- `key moments`
- `trace`
- `Model I/O`

The review should answer:

- what the user was actually doing
- whether it matched the stated goal
- what interrupted or took over

## What V1 Captures

- app activation / launch / termination
- wake / sleep
- focused window titles
- browser tab title + URL
- Finder path context
- shell commands
- file activity in watched roots
- clipboard changes
- manual quick notes

## Non-Goals

V1 does not attempt:

- screen recording
- keystroke capture
- live nudging during a session
- automatic blockers
- deep semantic understanding of arbitrary app content
- cloud sync
- a background daemon
- SQLite or full-text search

## Success Criteria

V1 is successful if:

- a user can run a timed session and get a readable review
- the review feels grounded in real evidence
- the History tab becomes a useful record of completed blocks
- raw signals remain inspectable when the AI output feels wrong

## Important Limits

- AI reviews are only as good as the captured signals.
- Browser detail is better than native-app detail.
- Some app-specific metadata depends on AppleScript and can be flaky.
- Manual test reviews are not stored in History; only completed timed sessions are.
