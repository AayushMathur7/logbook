# Driftly

**See where your focus went.**

Driftly is a Mac app that watches your work session, can quietly nudge you when you drift, and gives you a quick recap at the end.

You start a focus block with a clear plan and end it with a fuzzy memory. Most productivity tools tell you how long you worked, not whether you stayed on track. Driftly gives you a quick recap you can actually use before the next session.

## Why Use It

Most focus tools either track time or block distractions. Driftly is trying to answer a different question:

**Did this block actually become the thing you meant to do?**

If focus clearly slips, Driftly can quietly nudge you while the session is still running.

Then the session ends with something more useful than “I think that went fine”:

- what matched
- where it drifted
- what to do next

## Use It Locally

Clone the repo, then from the repo root run:

```bash
./scripts/dev.sh
```

That builds `dist/Driftly.app` and opens it.

## Use It In 30 Seconds

1. Open Driftly.
2. Write one goal.
3. Start the session.
4. Pick your review provider in Settings: Ollama, Codex CLI, or Claude Code.
5. Turn on Accessibility if you want better window and page titles.
6. Read the recap when the session ends.

There is nothing big to learn.

If your review provider is not installed or signed in yet, Driftly still saves the session, but it will not generate a review.

There is no fallback cloud review.

## What You Need

- macOS 13 or newer
- Accessibility permission for the best experience
- Ollama, Codex CLI, or Claude Code if you want AI reviews

Optional:

- shell integration if you want terminal commands captured

```zsh
source "/absolute/path/to/driftly/integrations/shell/driftly.zsh"
```

## Easy To Trust

- Easy to start: open the app, write one goal, and begin.
- Easy to read: each session ends with a short recap, so you can understand it in seconds.
- Easy to trust: Driftly is built for honest reflection, not noisy dashboards or fake scores.

## Private And Local-First

Session data stays on your Mac. Reviews run through your configured provider. Driftly is not recording your screen or logging every key you press.

Depending on your settings, Driftly can capture:

- app switches, launches, and quits
- active window titles
- browser page titles, domains, and URLs
- Finder context
- shell commands through the shell integration
- file activity under watched folders
- clipboard previews
- quiet drift signals during the block

It does **not** capture:

- screenshots
- screen recordings
- keystrokes
- audio
- camera or microphone input
- your data leaving your Mac by default

See [PRIVACY.md](/Users/aayush/ai-projects/driftly/PRIVACY.md:1) for the full privacy model.

## Dev

Run the app locally:

```bash
./scripts/dev.sh
```

Run checks:

```bash
bash scripts/check.sh
```

## Docs

- [docs/install.md](/Users/aayush/ai-projects/driftly/docs/install.md:1)
- [docs/launch-checklist.md](/Users/aayush/ai-projects/driftly/docs/launch-checklist.md:1)
- [AGENT.md](/Users/aayush/ai-projects/driftly/AGENT.md:1)
- [LICENSE](/Users/aayush/ai-projects/driftly/LICENSE:1)
- [SECURITY.md](/Users/aayush/ai-projects/driftly/SECURITY.md:1)
