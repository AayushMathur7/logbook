# How Reviews Are Built

## Session Review

The core artifact in the current app is the session review.

It is built from:

- the user-entered session goal
- the session time range
- all events captured during that range
- derived timeline segments and intent observations
- saved feedback from earlier reviews

## Prompt Inputs

The prompt sent to the local model includes:

- session goal
- start and end time
- top apps
- top titles
- top URLs and paths
- command activity
- clipboard previews
- a compact timeline of the session
- intent-aware observations about direct work, support work, drift, and breaks
- an allowlist of evidence mentions so the review stays grounded in what was actually captured

## Output Shape

The provider is asked for a short structured response that maps into:

- verdict
- headline
- recap
- takeaway

The app then enriches that output locally and renders:

- headline
- recap with inline chips and links when available
- takeaway
- dominant apps and session path hints
- attention segments for the saved review

## Review Quality Bar

A useful review should answer:

- what the user was actually doing
- whether that matched the goal
- what interrupted or displaced the block
- where the main thread held together or broke down

It should not degrade into a play-by-play of every event.

## Why Signals Still Matter

When the review feels wrong, the underlying evidence still matters.

The app keeps the captured events and derived timeline so the session can be retried, inspected through the CLI, and improved over time with review feedback.
