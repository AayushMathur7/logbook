# macOS Release Guide

This repo now includes a simple CLI release path for building a macOS `.app` bundle and packaging it as a `.dmg`.

It is intended for distribution outside the Mac App Store.

## Recommended release shape

For a public release, Driftly should be shipped as:

1. a release `.app`
2. signed with `Developer ID Application`
3. notarized by Apple
4. stapled after notarization
5. packaged in a `.dmg`

That matches Apple’s recommended outside-the-App-Store flow for Gatekeeper and notarization.

## Scripts

### Build a release app bundle

```bash
./scripts/build-app-bundle.sh --configuration release
```

By default this writes:

```text
dist/Driftly.app
```

### Build a DMG

```bash
./scripts/package-dmg.sh
```

By default this writes:

```text
dist/release/Driftly.dmg
```

## Signing

To sign the app and DMG, provide a Developer ID identity:

```bash
MACOS_DEVELOPER_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
./scripts/package-dmg.sh
```

The script signs:

- the `.app`
- the `.dmg`

It also runs local signature verification for the app bundle.

## Notarization

The script supports notarization through `notarytool` using a saved keychain profile.

First store credentials once on your release machine:

```bash
xcrun notarytool store-credentials "driftly-notary"
```

Then run:

```bash
MACOS_DEVELOPER_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
APPLE_NOTARY_PROFILE="driftly-notary" \
./scripts/package-dmg.sh
```

That will:

1. build the release app
2. sign it
3. create the DMG
4. submit the DMG to Apple
5. wait for notarization
6. staple the DMG

## Useful options

Both scripts support overrides for:

- output directory
- scratch path
- app name
- display name
- bundle identifier
- version
- build number

Example:

```bash
DRIFTLY_VERSION="0.2.0" \
DRIFTLY_BUILD_NUMBER="12" \
./scripts/package-dmg.sh --bundle-id com.aayush.driftly
```

## Notes

- `scripts/run-app.sh` is still the local dev launcher.
- `scripts/build-app-bundle.sh` is the shared bundle builder used by both local app launching and release packaging.
- If you want a more Apple-native release workflow later, you can still move this into an Xcode archive pipeline or CI job.

## Before publishing

Test the downloaded DMG on a clean Mac and verify:

- first launch works
- Accessibility onboarding is clear
- session start and finish work
- AI review works when Codex or Claude Code is configured
- the no-provider state is understandable when the selected local CLI is not configured
- shell integration instructions are correct
