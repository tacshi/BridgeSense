<p align="center">
  <img src="assets/app_icon/bridgesense_icon_1024.png" alt="BridgeSense icon" width="120">
</p>

# BridgeSense

BridgeSense is a macOS utility for using a DualSense controller as a desktop
input device. It maps controller input to pointer movement, scrolling, keyboard
shortcuts, mouse clicks, haptics, and DualSense adaptive triggers.

## Features

- Left stick pointer control.
- Right stick scrolling.
- DualSense touchpad pointer control.
- Remappable buttons for keyboard shortcuts and mouse clicks.
- Optional per-button vibration using `Drive`, `Shoot`, and `Pulse` haptic
  patterns.
- DualSense adaptive trigger effects for vibration-enabled L2/R2 trigger
  bindings.

## Permissions

BridgeSense needs macOS Accessibility permission before it can post global
pointer, scroll, keyboard, and mouse-click events to other apps. Use the
`Request` button in BridgeSense, then enable `BridgeSense.app` in System
Settings when prompted.

If `Output` still shows `Blocked` after granting permission, quit every running
BridgeSense copy, remove the stale Accessibility entry, run
`./scripts/build_and_run.sh`, press `Request`, and enable the new
`BridgeSense.app` row.

The macOS sandbox is disabled because BridgeSense posts global input events
through Quartz.

## Development

Run the debug app:

```bash
./scripts/build_and_run.sh
```

Useful variants:

```bash
./scripts/build_and_run.sh --verify
./scripts/build_and_run.sh --logs
```

Verify changes:

```bash
flutter analyze
flutter test
flutter build macos --debug
```

## Release

`scripts/releash.sh` builds the release app, signs it, creates a DMG, notarizes
and staples it, validates Gatekeeper acceptance, and uploads the DMG to GitHub
Releases.

Create the notarytool keychain profile once:

```bash
xcrun notarytool store-credentials BridgeSense \
  --apple-id "<apple-id>" \
  --team-id "<team-id>" \
  --password "<app-specific-password>"
```

The GitHub CLI must also be authenticated:

```bash
gh auth status
```

Run a release:

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: Example Name (TEAMID)" \
  ./scripts/releash.sh 1.0.1
```

The release artifact is written to the project root as
`BridgeSense-<version>.dmg` and published to the `v<version>` GitHub Release.
