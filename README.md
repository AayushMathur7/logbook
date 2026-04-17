# Driftly

**A local macOS app that tells you whether your focus session actually stayed on track.**

Driftly watches a goal-based work session, captures lightweight local context, and ends the block with a short review you can actually use. Instead of only telling you how long you worked, it tries to answer the better question:

**Did this block become the thing you meant to do?**

Website: [driftly.sh](https://driftly.sh)

[![License](https://img.shields.io/github/license/AayushMathur7/driftly)](https://github.com/AayushMathur7/driftly/blob/main/LICENSE)
![macOS](https://img.shields.io/badge/macOS-13%2B-black)

## Current Status

Driftly does not currently publish a public release build.

If you want to try it today, run it from source.

## Run From Source

From the repo root:

```bash
./scripts/dev.sh
```

That builds `dist/Driftly.app` and opens it.

After launch:

1. Grant Accessibility when prompted for richer window and page titles.
2. In Settings, choose your review provider: `Codex` or `Claude Code`.

If your provider is not installed or signed in yet, Driftly still saves the session, but it will not generate the AI review until the provider is ready.

## What Driftly Does

- Start a session with one clear goal.
- Capture local evidence such as app switches, page titles, file activity, and shell commands.
- Generate a short evidence-based review when the session ends.
- Offer optional in-session reminders while the session is running.
- Generate daily and weekly reflections from saved sessions.

The point is not to make a dashboard. The point is to help you see what the block actually turned into.

## Use It In 30 Seconds

1. Open Driftly.
2. Write one goal.
3. Start the session.
4. Do the work.
5. Read the review at the end.

That is the whole loop.

## Adapt It For Your Own Workflow

Driftly is opinionated, but it is also meant to be adaptable.

You can tune it for your own use case and style:

- change what context Driftly captures
- change how strict or simple reminders feel
- change the review writing guidance
- shape the output around your own workflow, language, and standards

If you are using `Claude Code` or `Codex`, you can improve the review quality further by editing the repo guidance and skill files that shape the writing and analysis behavior.

Useful files:

- [AGENTS.md](AGENTS.md)
- [CLAUDE.md](CLAUDE.md)
- [driftly-insight-writing skill](.agents/skills/driftly-insight-writing/SKILL.md)

That setup makes Driftly more than a fixed app. It becomes a review system you can adapt to your own work style.

## Privacy And Local-First Storage

Driftly is built to stay legible and trustworthy.

Session data stays on your Mac. Driftly is not recording your screen or logging every key you press. Reviews run through the provider you configure locally.

Depending on your settings, Driftly can capture:

- app switches, launches, and quits
- active window titles
- browser page titles, domains, and URLs
- Finder context
- shell commands through the shell integration
- file activity under watched folders
- clipboard previews
- session reminder events

It does **not** capture:

- screenshots
- screen recordings
- keystrokes
- audio
- camera or microphone input
- your data leaving your Mac by default

Storage paths:

- app data: `~/Library/Application Support/Driftly/`
- database: `~/Library/Application Support/Driftly/driftly.sqlite`
- shell integration: `integrations/shell/driftly.zsh`

See [PRIVACY.md](PRIVACY.md) for the full privacy model.

## Requirements

- macOS 13 or newer
- Accessibility permission for the best experience
- `Codex CLI` or `Claude Code` if you want AI reviews

Optional:

- shell integration if you want terminal commands captured

```zsh
source "/absolute/path/to/driftly/integrations/shell/driftly.zsh"
```

## Development Checks

Run checks from the repo root:

```bash
bash scripts/check.sh
```

## Docs

- [driftly.sh](https://driftly.sh)
- [docs/technical-architecture.md](docs/technical-architecture.md)
- [docs/event-model.md](docs/event-model.md)
- [docs/tracking-guide.md](docs/tracking-guide.md)
- [docs/testing.md](docs/testing.md)
- [LICENSE](LICENSE)
- [SECURITY.md](SECURITY.md)

## License

Driftly is released under the license in [LICENSE](LICENSE).
