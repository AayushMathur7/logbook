# Privacy

Driftly is designed to be easy to understand.

## What the app does

Driftly watches lightweight local activity during a session so it can write a short review at the end.

The goal is simple:

- you type what you want to do
- the app watches lightweight local signals during that block
- the app writes a short recap of what happened

## What the app captures

Depending on your settings and macOS permissions, Driftly can capture:

- app switches, launches, and quits
- wake and sleep events
- active window titles
- browser page titles, domains, and URLs
- Finder context
- shell commands through the shell integration
- file activity under watched roots
- clipboard previews

## What the app does not capture

Driftly does not capture:

- screenshots
- screen recordings
- keystrokes
- audio recordings
- camera or microphone input

## Where data stays

Driftly is designed to keep data on your Mac.

- captured session data is stored locally
- the current database lives at `~/Library/Application Support/Driftly/driftly.sqlite`
- retention settings control how long raw events are kept

## AI review generation

Driftly can use one of three AI review paths:

- Ollama
- Codex CLI
- Claude Code

What that means:

- if you choose Ollama, model calls stay on a local Ollama host
- if you choose Codex CLI or Claude Code, the prompt is sent through that authenticated CLI on your Mac and then to that provider's service
- Driftly does not make hidden remote model calls outside the provider you selected

If the selected provider is unavailable, the app can still save the session, but AI review generation will not run.

## User controls

You can control:

- which capture sources are enabled
- which apps, domains, and paths are excluded
- which titles are redacted
- how long raw events are retained
- which watched roots are used

These controls live in `Settings`.

## Open questions before public launch

Before shipping broadly, this repo should also publish:

- the final open source license
- a clearer support policy
- a stable public release process for signed and notarized builds
