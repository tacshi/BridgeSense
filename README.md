# BridgeSense

BridgeSense is a macOS Flutter utility that maps a DualSense or compatible
extended game controller to desktop input, including mouse movement, scrolling,
keyboard shortcuts, mouse clicks, haptics, adaptive triggers, and menu bar
background operation.

## Current bridge

- L stick moves the pointer.
- R stick scrolls the view under the pointer.
- DualSense touchpad movement moves the pointer.
- Button bindings default to `Off`.
- Common DualSense controls can be remapped to keyboard keys or mouse click.
- Vibration is a secondary effect that can be enabled per button binding.
- Controller haptics are exposed as `Drive`, `Shoot`, and `Pulse` patterns.
- DualSense adaptive triggers are used when macOS reports the controller as a
  `GCDualSenseGamepad`.
- Closing the window keeps BridgeSense running from its menu bar status item.
- The macOS app icon is generated from the checked-in app icon source at
  `assets/app_icon/bridgesense_icon_1024.png`.

## Permissions

macOS must trust the app for Accessibility before global pointer, scroll, and
keyboard events can reach other apps. Use the `Request` button in BridgeSense,
then enable the app in System Settings if macOS opens the permission pane.

The macOS sandbox entitlement is disabled for this utility because the app posts
global input events through Quartz.

## Run

```bash
./scripts/build_and_run.sh
```

Useful variants:

```bash
./scripts/build_and_run.sh --verify
./scripts/build_and_run.sh --logs
```

## Verify

```bash
flutter analyze
flutter test
flutter build macos --debug
```

## Release

`scripts/releash.sh` builds a release macOS app, signs it with the
`DEVELOPER_ID_APPLICATION` identity, creates a root-level DMG, notarizes it with
Apple, staples the ticket, and validates Gatekeeper acceptance.

The script uses the saved notarytool keychain profile `BridgeSense` by default.
Create that profile outside the repo before releasing:

```bash
xcrun notarytool store-credentials BridgeSense \
  --apple-id "<apple-id>" \
  --team-id "<team-id>" \
  --password "<app-specific-password>"
```

Run a release:

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: Example Name (TEAMID)" \
  ./scripts/releash.sh
```

The output is written to the project root as `BridgeSense-<version>.dmg`.
