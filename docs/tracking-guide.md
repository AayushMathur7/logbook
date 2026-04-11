# How Reviews Are Built

## Session Review

The core artifact in the current app is the session review.

It is generated from:

- the user-entered session goal
- the session time range
- all events captured during that range
- local enrichments such as app durations, repo hints, and trace lines

## Prompt Inputs

The prompt sent to `codex` or `claude` includes:

- session goal
- start and end time
- top apps
- top titles
- top URLs and paths
- command activity
- app-switch count
- app durations
- inferred repo
- media summary
- clipboard preview
- a timestamped trace

## Output Shape

The provider is asked to return structured JSON for:

- `headline`
- `why`
- `reasons`
- `key moments`
- `dominant thread`
- `break point`

The app then enriches that output with local metadata and renders:

- headline
- goal
- time range
- why
- key moments
- trace
- model prompt / raw response

## Timed Session vs Test Review

### Timed session

- starts from the Session screen
- ends via the timer or `End session now`
- review is stored in History

### Test review

- uses the `Generate review` controls
- reviews the last `N` minutes
- is useful for prompt tuning and UI tuning
- is not stored in History

## What Makes A Good Review

A useful review should answer:

- what the user was actually doing
- whether that matched the goal
- what interrupted or displaced the block
- when the important shifts happened

It should not degrade into a play-by-play of every event.

## Why Signals Still Matter

The Signals view exists for one reason:

when the AI review feels wrong, you need to see the evidence it was built from.
