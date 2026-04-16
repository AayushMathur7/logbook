# Install

## Current status

Driftly can be run from source today.

The repo also includes a DMG packaging path, but public distribution still needs signing, notarization, and clean-machine testing.

## Run from source

From the repo root:

```bash
./scripts/dev.sh
```

## What you need

- macOS 13 or newer
- Accessibility permission if you want window titles and stronger context
- Codex CLI or Claude Code if you want AI review
- shell integration if you want terminal commands captured

## Review generation

Session review generation can run through Codex CLI or Claude Code.

If your selected AI provider is not installed, signed in, or configured, Driftly still saves the session and timeline, but it does not generate a review.

## Validation

To verify the repo from source:

```bash
bash scripts/check.sh
```

## Public release gap

This repo now has a scriptable `.app` and `.dmg` packaging path, but it still needs real signing credentials, notarization, and clean-machine release testing for broader distribution.
