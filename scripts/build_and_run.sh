#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="BridgeSense"
APP_BUNDLE="build/macos/Build/Products/Debug/BridgeSense.app"
BUNDLE_ID="com.example.bridgeSense"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

# Xcode can retain stale output paths from previous direct xcodebuild runs
# and warn when Flutter's local build root sees those paths outside its sandbox.
rm -rf "$ROOT_DIR/build/macos/Build/Intermediates.noindex/XCBuildData"

filter_xcode_noise() {
  awk '
    /DVTErrorPresenter: Unable to load simulator devices\./ { skipping_core_sim = 1; next }
    skipping_core_sim && /^Domain: DVTCoreSimulatorAdditionsErrorDomain$/ { next }
    skipping_core_sim && /^Code: 3$/ { next }
    skipping_core_sim && /^Failure Reason: The version of the CoreSimulator framework/ { next }
    skipping_core_sim && /^Recovery Suggestion: Please ensure/ { next }
    skipping_core_sim && /^--$/ { next }
    skipping_core_sim && /^CoreSimulator is out of date\./ { next }
    skipping_core_sim && /^$/ { skipping_core_sim = 0; next }
    /iOSSimulator: .*DVTCoreSimulatorAdditionsErrorDomain/ { next }
    { print }
  '
}

flutter build macos --debug 2>&1 | filter_xcode_noise

open_app() {
  /usr/bin/open -n "$ROOT_DIR/$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$ROOT_DIR/$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
