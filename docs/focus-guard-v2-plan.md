# Focus Guard V2

## Goal

Turn LogBook from a post-session reviewer into a quiet in-session recovery tool.

The core promise is:

`LogBook catches focus breaks early and helps you get back on track.`

## What Changes

Focus Guard runs only during an active timed session.

It:
- waits until the session has been running for 5 minutes
- checks the current session every 30 seconds
- uses only local signals already captured in the session
- stays quiet when evidence is broad, weak, or ambiguous
- shows at most 2 prompts in a session

It does not:
- run outside active sessions
- rely on screenshots, OCR, or keystrokes
- interrupt idle time, sleep, or the final 2 minutes of a session

## Prompt Logic

Focus Guard shows a prompt only when all of this is true:

- the live mode looks like drifting or decompressing
- recent session labels look clearly off-goal
- that off-track state has stayed continuous for at least 90 seconds
- no cooldown or snooze is active

Default actions:
- `Back on track`
- `Snooze 10m`
- `Ignore`

Cooldown rules:
- 10-minute cooldown after a shown prompt
- `Snooze` adds a 10-minute suppression window
- prompt cap stays at 2 per session

If the user gets back on track within 2 minutes of a prompt, LogBook records that as a recovery.

## UI

The running session view now includes:
- a compact focus status row
- plain-English status text
- an in-app Focus Guard banner when a prompt is active

If the app is not frontmost and notifications are allowed, the same prompt can be delivered as a local notification.

## Review Output

Session reviews now include Focus Guard outcomes:
- prompts shown
- snoozes
- ignores
- recoveries
- whether drift stayed unresolved

This keeps the end review short while making it possible to say:
- you drifted and came back
- you drifted and stayed off-track

## Defaults

- enabled by default
- quiet tone
- conservative triggering
- local-only evidence
- no new database table

## Shipping Notes

This is meant to be the new default session behavior, not an optional side mode.

The feature should improve the product hook without adding setup friction.
