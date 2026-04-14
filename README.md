# Driftly

Driftly is a local-first macOS app for one question:

Did this work block become the thing I meant to do?

You set a goal, start a session, do your work, and Driftly reviews the block against what actually happened.

## Why Driftly Exists

Most productivity tools measure motion.

Driftly measures alignment.

It is built for people who do deep work in messy, real desktops and want a clearer answer than "you were active for 97 minutes."

## How It Works

1. Write what you want this block to become.
2. Start the session.
3. Driftly captures lightweight local context while you work.
4. End the session.
5. Driftly turns the session into a short review.

## Quick Start

From the repo root on a Mac running macOS 13 or newer:

```bash
./scripts/dev.sh
```

Then:

1. Open Driftly.
2. Grant Accessibility if you want better context.
3. Start a session with a clear goal.
4. End the session and read the review.

## What You Need

- macOS 13 or newer
- Accessibility if you want window and page titles instead of generic app-only activity
- Ollama if you want AI review generation
- shell integration if you want terminal commands captured

Shell integration:

```zsh
source "/absolute/path/to/driftly/integrations/shell/driftly.zsh"
```

Important:

- Driftly reviews are Ollama-only.
- If Ollama is not installed or no model is configured, Driftly still saves the session and timeline, but it does not generate a review.
- There is no fallback review mode.

## What It Captures

Depending on your settings, Driftly can capture:

- app switches, launches, and quits
- wake and sleep events
- active window titles
- browser page titles, domains, and URLs
- Finder context
- shell commands through the shell integration
- file activity under watched roots
- clipboard previews

It does not capture:

- screenshots
- screen recordings
- keystrokes
- audio
- camera or microphone input

## Privacy

Driftly is built to stay local.

- session data stays on your Mac
- the database lives at `~/Library/Application Support/Driftly/driftly.sqlite`
- AI review generation runs locally through Ollama

See [PRIVACY.md](/Users/aayush/ai-projects/driftly/PRIVACY.md:1) for the full privacy model.

## Releasing Driftly

This repo now includes a release path for building a real macOS app bundle and DMG.

Build a release app:

```bash
./scripts/build-app-bundle.sh --configuration release
```

Package a DMG:

```bash
./scripts/package-dmg.sh
```

For public distribution, the app should be signed, notarized, and shipped as a DMG. See [docs/release-macos.md](/Users/aayush/ai-projects/driftly/docs/release-macos.md:1).

## Beta Download

Beta builds should be shipped through GitHub Releases:

- [See the latest releases](https://github.com/AayushMathur7/driftly/releases)

If you share an unsigned beta DMG, macOS may ask the user to manually allow Driftly in Privacy & Security the first time they open it.

## Validation

```bash
bash scripts/check.sh
```

Or run:

```bash
make run
```

## Repo Guide

- [docs/install.md](/Users/aayush/ai-projects/driftly/docs/install.md:1)
- [docs/release-macos.md](/Users/aayush/ai-projects/driftly/docs/release-macos.md:1)
- [docs/launch-checklist.md](/Users/aayush/ai-projects/driftly/docs/launch-checklist.md:1)
- [AGENT.md](/Users/aayush/ai-projects/driftly/AGENT.md:1)
- [LICENSE](/Users/aayush/ai-projects/driftly/LICENSE:1)
- [SECURITY.md](/Users/aayush/ai-projects/driftly/SECURITY.md:1)
