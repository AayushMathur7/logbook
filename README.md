# Driftly

Driftly is a local-first macOS app that tells you whether your work session stayed true to the goal you set.

You start with a simple sentence like `ship the onboarding fix` or `write the investor update`. Driftly watches lightweight local signals during that block and gives you a short, plain-English review of what actually happened.

It is built for people who do focused computer work and want a more honest answer than "you were active for 47 minutes."

## Why Driftly Exists

Most productivity tools measure motion.

Driftly measures alignment.

It is not trying to score your whole day. It is trying to answer one question at the end of one block:

`Did this session become the thing I meant to do?`

That makes it useful for:

- developers trying to protect build or shipping time
- founders trying to keep sessions tied to real priorities
- writers and researchers trying to notice when the block quietly drifted
- anyone who wants a quick review instead of another dashboard

## What You Get

- A goal-first session flow
- A short review in plain English after each block
- Session history you can reopen later
- A local timeline built from lightweight evidence
- Optional local AI review generation through Ollama

The product is intentionally opinionated:

- you define the session goal
- Driftly compares the block against that goal
- the output is a short recap, not a productivity score

## How It Works

1. Type what this session is for.
2. Pick a session length.
3. Start the timer.
4. Let Driftly capture lightweight local evidence during the block.
5. End the session or let the timer finish.
6. Read a short review of how the block actually went.

In simple terms:

- you say what this block is for
- Driftly watches lightweight local signals during that block
- at the end, it tells you whether the block stayed on track

## Why It Feels Different

Driftly is built around intent, not a hardcoded idea of productivity.

Examples:

- `watch YouTube` can be a matched session if the block mostly stayed on YouTube
- `deploy driftly to github` can treat GitHub, terminal work, code editors, and repo context as aligned work
- `get my day ready` is broader, so the review should describe the block honestly instead of pretending it has stronger certainty than the evidence supports

The review UI currently focuses on:

- a one-line headline
- a short recap in plain language
- a short takeaway line
- inline app, site, and repo chips
- clickable inline links when the session captured a real URL for that mention
- saved history for past sessions
- per-review feedback so the app can learn what framing was helpful or wrong

## Privacy By Design

Driftly is designed to stay lightweight and local.

It can capture:

- frontmost app changes, launches, and terminations
- wake and sleep
- active window titles when Accessibility is granted
- browser page titles, URLs, and domains for supported browsers
- Finder context when available
- shell commands imported from `integrations/shell/driftly.zsh`
- file activity under watched roots
- clipboard changes with a short preview

It does not capture:

- screenshots
- OCR
- audio recordings
- camera or microphone
- keystrokes

Storage stays local in:

```text
~/Library/Application Support/Driftly/driftly.sqlite
```

If you use AI review generation, Driftly currently talks only to a local Ollama host. There is no cloud fallback and no hidden remote model call path.

See [PRIVACY.md](/Users/aayush/ai-projects/driftly/PRIVACY.md:1) for the full privacy model.

## Current Status

Driftly is promising, but it is not yet packaged as a polished public Mac download for non-technical users.

Right now the project is best suited for:

- technical users who can run a macOS app from source
- early testers comfortable granting macOS permissions
- people who are already comfortable installing Ollama locally if they want AI review

The public release gap is mostly distribution and onboarding:

- signed macOS app distribution
- notarized releases
- smoother first-run setup
- clearer install path for non-technical users

See [docs/install.md](/Users/aayush/ai-projects/driftly/docs/install.md:1), [docs/release-macos.md](/Users/aayush/ai-projects/driftly/docs/release-macos.md:1), and [docs/launch-checklist.md](/Users/aayush/ai-projects/driftly/docs/launch-checklist.md:1).

## Run From Source

From the repo root:

```bash
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build-local/clang-cache \
CLANG_MODULE_CACHE_PATH=$PWD/.build-local/clang-cache \
swift run --scratch-path $PWD/.build-local DriftlyApp
```

If you prefer to build first:

```bash
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build-local/clang-cache \
CLANG_MODULE_CACHE_PATH=$PWD/.build-local/clang-cache \
swift build --scratch-path $PWD/.build-local

./.build-local/debug/DriftlyApp
```

What you need:

- macOS 13 or newer
- Accessibility permission if you want stronger context capture
- a local Ollama install if you want AI review generation

If Ollama is not ready, Driftly can still save sessions, keep the local event timeline, and generate a simpler non-LLM review.

## Validation

Run the default verification path from the repo root:

```bash
bash scripts/check.sh
```

Useful CLI commands:

```bash
swift run --scratch-path $PWD/.build-local driftly view
swift run --scratch-path $PWD/.build-local driftly view --events --limit 20
swift run --scratch-path $PWD/.build-local driftly view --summary
```

## Shell Integration

If you want terminal commands to show up in captured evidence, add this to your shell config:

```zsh
source "/absolute/path/to/driftly/integrations/shell/driftly.zsh"
```

Then open a new shell session.

## Repository Layout

This repo currently contains:

- `Sources/DriftlyApp` for the SwiftUI macOS app
- `Sources/DriftlyCore` for shared models, SQLite storage, privacy rules, and timeline derivation
- `Sources/driftly` for a small CLI to inspect stored data
- `Sources/driftlyselftest` for the self-test runner

Key files:

- `Sources/DriftlyApp/ContentView.swift` for the main app surface
- `Sources/DriftlyApp/AppModel.swift` for session lifecycle, capture orchestration, history, and review persistence
- `Sources/DriftlyApp/AIProviderBridge.swift` for Ollama integration, prompt construction, and review parsing
- `Sources/DriftlyApp/UI/MarkdownText.swift` for inline review rendering and linked badges
- `Sources/DriftlyCore/TimelineDeriver.swift` for timeline enrichment and intent-aware interpretation
- `Sources/DriftlyCore/SessionStore.swift` for SQLite persistence

## Current Limitations

- review quality still depends on the captured evidence and prompt quality
- app and browser context are best-effort and depend on macOS permissions
- browser and Finder inspection still depend on AppleScript and can be flaky
- the current launch story is still optimized for technical users

## More

- [LICENSE](/Users/aayush/ai-projects/driftly/LICENSE:1)
- [PRIVACY.md](/Users/aayush/ai-projects/driftly/PRIVACY.md:1)
- [SECURITY.md](/Users/aayush/ai-projects/driftly/SECURITY.md:1)
- [docs/install.md](/Users/aayush/ai-projects/driftly/docs/install.md:1)
- [docs/release-macos.md](/Users/aayush/ai-projects/driftly/docs/release-macos.md:1)
- [docs/launch-checklist.md](/Users/aayush/ai-projects/driftly/docs/launch-checklist.md:1)
