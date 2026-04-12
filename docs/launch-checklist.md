# Launch Checklist

This is the shortest practical list of what still needs to be true before Log Book is ready for outside users.

## Product

- Make the one-line promise clear in simple English.
- Keep the app focused on one job: compare the goal you typed with what the session became.
- Decide how central Calendar should be. Recommended: make it an optional power feature, not the whole product.

## Onboarding

- Add a first-run flow for Accessibility, Calendar, and Ollama setup.
- Detect whether Ollama is installed and whether a model is selected.
- Make the first successful session easy. Do not let users get lost in settings before they see value.

## Trust

- Publish `LICENSE`.
- Publish `PRIVACY.md`.
- Publish `SECURITY.md`.
- Explain what is captured, what is not captured, and where data lives.

## Distribution

- Ship a signed macOS app.
- Notarize releases.
- Decide how users install updates.
- Add release notes or a changelog.

## Lightweight proof

- Measure idle RAM.
- Measure CPU during a normal session.
- Measure database growth per hour of active use.
- Publish the app binary size and explain that capture is event-based, not media-heavy.

## Review quality

- Test the first-run review experience on a clean machine.
- Tune the prompt for broad goals and mixed sessions.
- Keep the fallback review path readable when Ollama is missing or weak.

## Suggested next product hooks

- Calendar-backed session checking: “Did the hour match what was on your calendar?”
- Stronger drift detection: “What took over this block?”
- Better interruption framing: “What broke your focus?”
