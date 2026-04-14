# Driftly Codebase Guide

This file is a quick orientation guide for humans or coding agents working in this repo.

## What Driftly Is

Driftly is a local-first macOS app that compares a session goal with what actually happened during the session.

The product flow is:

1. start a session with a goal
2. capture lightweight local evidence during that session
3. derive timeline segments from raw events
4. generate an Ollama-backed review
5. save the session, review, and history locally

## Repo Layout

- `Sources/DriftlyApp`: macOS app, UI, orchestration, permissions, settings, review generation flow
- `Sources/DriftlyCore`: shared models, persistence, privacy rules, timeline derivation, focus logic
- `Sources/driftly`: small CLI for inspecting local data
- `Sources/driftlyselftest`: self-test runner
- `scripts`: local dev, packaging, and validation scripts
- `docs`: install, release, architecture, and launch notes

## Important Entry Points

- `Sources/DriftlyApp/main.swift`: app entry point
- `Sources/DriftlyApp/DriftlyApp.swift`: app lifecycle, windows, menu bar wiring
- `Sources/DriftlyApp/AppModel.swift`: central coordinator for session lifecycle, capture, history, and review generation
- `Sources/DriftlyApp/ContentView.swift`: primary app UI
- `Sources/DriftlyApp/AIProviderBridge.swift`: Ollama integration and structured review generation
- `Sources/DriftlyCore/SessionStore.swift`: SQLite persistence
- `Sources/DriftlyCore/TimelineDeriver.swift`: turns raw events into readable session segments
- `Sources/DriftlyCore/CaptureSettings.swift`: settings and privacy filters

## How Data Flows

1. `ActivityMonitor` and related sources capture local events.
2. `AppModel` stores events through `SessionStore`.
3. At session end, `TimelineDeriver` builds segments from the captured events.
4. `AIProviderBridge.ollama` generates the review if an Ollama model is configured.
5. `SessionStore` saves the session, segments, and review for history.

## Review Rules

- Session reviews are Ollama-only.
- If Ollama is unavailable or no model is configured, Driftly saves the session but review generation does not run.
- There is no non-AI fallback session review path.

## Permissions and Setup

- Accessibility is optional but recommended for window titles and richer context.
- Notifications are optional and mainly affect focus-guard nudges.
- Shell integration is optional and adds terminal command evidence.
- Ollama is optional unless AI review generation is required.

## Local Commands

Run the app:

```bash
./scripts/dev.sh
```

Or:

```bash
make run
```

Run checks:

```bash
bash scripts/check.sh
```

Build a release app bundle:

```bash
./scripts/build-app-bundle.sh --configuration release
```

Build a DMG:

```bash
./scripts/package-dmg.sh
```

## Current Architectural Notes

- The app is SwiftPM-based, not Xcode-project-based.
- Local app launching and release app bundling now share the same bundle builder script.
- Public distribution still requires Developer ID signing, notarization, and clean-machine verification.

## Editing Guidance

- Keep user-facing copy short and plain.
- Do not reintroduce fallback session-review language unless the product behavior changes.
- Keep `scripts/run-app.sh` as a dev launcher, not the public release path.
- Prefer updating docs when product behavior changes, especially around review generation, privacy, and setup.
