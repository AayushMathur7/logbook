# macOS Release Guide

This document describes what still needs to be true before Driftly is ready for a public macOS release.

## Current gap

The project builds and runs through Swift Package Manager today, but a broader public release should ship as a signed and notarized macOS app bundle.

That means the release work is not just `swift build`.

## Minimum public release standard

- create a distributable `.app`
- sign the app with an Apple Developer ID certificate
- notarize the app with Apple
- staple the notarization result
- publish the signed artifact with install notes

## Practical release checklist

1. Build the release app bundle.
2. Sign the bundle with Developer ID Application.
3. Verify the code signature locally.
4. Submit the app for notarization.
5. Staple the notarization ticket.
6. Test the downloaded artifact on a clean Mac.
7. Publish release notes with install and permission guidance.

## What to test before publishing

- first launch
- Accessibility permission flow
- local model setup flow
- session start and finish
- local recap when no model is configured
- AI review when a model is configured
- shell integration instructions

## What still needs to be added to the repo

- a final packaging path for the `.app`
- a repeatable release script or Xcode archive flow
- versioned release notes
- a download and install path for non-technical users
