# Logbook V1 Spec

## Product

Logbook is a session-based macOS app for answering one question at the end of a work block:

`What was I actually doing, and did it match what I meant to do?`

V1 is intentionally narrow. It is not trying to be an always-on memory system, a time tracker, or a general life dashboard.

## V1 User Workflow

### Timed session

1. Enter a goal.
2. Pick a duration.
3. Start the session.
4. Let the block run quietly while Logbook captures lightweight local evidence.
5. Read the review when the block ends.
6. Save the block to History.

### History retry

1. Open `History`.
2. Select a prior session.
3. Retry review generation if you want a fresh pass on the same evidence.
4. Optionally delete the session or mark the review helpful or wrong.

## Main UI

### Session

The primary screen.

Shows:

- session setup
- active timer
- live event count and captured-activity preview
- completed session review

### History

Stores completed timed-session reviews.

Each row shows:

- review headline
- session goal
- time range

### Settings

Contains:

- capture toggles
- Accessibility status
- privacy and retention controls
- Ollama model availability

## Output Format

Each completed review is organized around:

- `headline`
- `summary`
- `focus assessment`
- inline entity spans and links
- short derived timeline context

The review should answer:

- what the user was actually doing
- whether that matched the stated goal
- what interrupted or took over

## What V1 Captures

- app activation, launch, and termination
- wake and sleep
- focused window titles
- browser tab title, URL, and domain
- Finder path context
- shell commands
- file activity in watched roots
- clipboard changes

## Non-Goals

V1 does not attempt:

- screen recording
- keystroke capture
- live nudging during a session
- automatic blockers
- deep semantic understanding of arbitrary app content
- cloud sync
- a separate background daemon
- remote model providers

## Success Criteria

V1 is successful if:

- a user can run a timed session and get a readable review
- the review feels grounded in real evidence
- the History tab becomes a useful record of completed blocks
- the privacy model is simple enough to trust

## Important Limits

- AI reviews are only as good as the captured signals.
- Browser detail is better than native-app detail.
- Some app-specific metadata depends on AppleScript and can be flaky.
- The current product depends on a working local Ollama setup instead of shipping its own model runtime.
