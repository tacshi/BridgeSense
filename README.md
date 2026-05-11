# BridgeSense

BridgeSense is a macOS Flutter utility that maps a DualSense or compatible
extended game controller to desktop input.

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
