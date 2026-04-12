# Privacy

Log Book is designed to be easy to understand.

## What the app does

Log Book watches lightweight local activity during a session so it can write a short review at the end.

The goal is simple:

- you type what you want to do
- the app watches lightweight local signals during that block
- the app writes a short recap of what happened

## What the app captures

Depending on your settings and macOS permissions, Log Book can capture:

- app switches, launches, and quits
- wake and sleep events
- active window titles
- browser page titles, domains, and URLs
- Finder context
- shell commands through the shell integration
- file activity under watched roots
- clipboard previews
- nearby calendar titles

## What the app does not capture

Log Book does not capture:

- screenshots
- screen recordings
- keystrokes
- audio recordings
- camera or microphone input

## Where data stays

Log Book is designed to keep data on your Mac.

- captured session data is stored locally
- the current database lives at `~/Library/Application Support/Logbook/logbook.sqlite`
- retention settings control how long raw events are kept

## AI review generation

Log Book currently uses a local Ollama model for AI review generation.

- model calls are limited to a local Ollama host
- there is no cloud fallback
- there are no hidden remote model calls

If Ollama is unavailable, the app can still save the session and fall back to a simpler local review path.

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
