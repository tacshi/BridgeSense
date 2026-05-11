#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-BridgeSense}"
PRODUCT_NAME="${PRODUCT_NAME:-bridge_sense}"
APP_BUNDLE_NAME="${APP_DISPLAY_NAME}.app"
SOURCE_APP="$ROOT_DIR/build/macos/Build/Products/Release/${PRODUCT_NAME}.app"
ENTITLEMENTS="$ROOT_DIR/macos/Runner/Release.entitlements"
WORK_DIR="$ROOT_DIR/build/releash"
STAGING_DIR="$WORK_DIR/staging"
DMG_ROOT="$WORK_DIR/dmg-root"
STAGED_APP="$STAGING_DIR/$APP_BUNDLE_NAME"
VERSION="${VERSION:-$(awk '/^version:/ {print $2; exit}' pubspec.yaml)}"
VERSION="${VERSION%%+*}"
DMG_PATH="${DMG_PATH:-$ROOT_DIR/${APP_DISPLAY_NAME}-${VERSION}.dmg}"
ASC_KEY_PATH="${APP_STORE_CONNECT_API_KEY_PATH:-${APP_STORE_CONNECT_KEY_PATH:-}}"
NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-BridgeSense}"

usage() {
  cat <<USAGE
Usage: DEVELOPER_ID_APPLICATION="Developer ID Application: ..." scripts/releash.sh

Required:
  DEVELOPER_ID_APPLICATION  Developer ID Application signing identity.

Notarization credentials:
  NOTARYTOOL_PROFILE       Defaults to BridgeSense.

Alternate notarization credentials:
  APPLE_ID + APPLE_TEAM_ID + APPLE_APP_SPECIFIC_PASSWORD
  APP_STORE_CONNECT_API_KEY_PATH + APP_STORE_CONNECT_KEY_ID + APP_STORE_CONNECT_ISSUER_ID

Optional:
  APP_DISPLAY_NAME          Defaults to BridgeSense.
  PRODUCT_NAME              Defaults to bridge_sense.
  VERSION                   Defaults to pubspec version without +build.
  DMG_PATH                  Defaults to ./BridgeSense-\$VERSION.dmg.
USAGE
}

fail() {
  echo "error: $*" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required tool: $1"
}

notary_args() {
  if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
    NOTARY_ARGS=(--keychain-profile "$NOTARYTOOL_PROFILE")
  elif [[ -n "$ASC_KEY_PATH" && -n "${APP_STORE_CONNECT_KEY_ID:-}" && -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
    NOTARY_ARGS=(
      --key "$ASC_KEY_PATH"
      --key-id "$APP_STORE_CONNECT_KEY_ID"
      --issuer "$APP_STORE_CONNECT_ISSUER_ID"
    )
  elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
    NOTARY_ARGS=(
      --apple-id "$APPLE_ID"
      --team-id "$APPLE_TEAM_ID"
      --password "$APPLE_APP_SPECIFIC_PASSWORD"
    )
  else
    usage
    fail "missing notarization credentials"
  fi
}

sign_code() {
  local path="$1"
  codesign --force --timestamp --options runtime --sign "$DEVELOPER_ID_APPLICATION" "$path"
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && {
  usage
  exit 0
}

[[ -n "${DEVELOPER_ID_APPLICATION:-}" ]] || {
  usage
  fail "DEVELOPER_ID_APPLICATION is required"
}

require_tool awk
require_tool codesign
require_tool ditto
require_tool flutter
require_tool hdiutil
require_tool xcrun
xcrun -f notarytool >/dev/null
xcrun -f stapler >/dev/null
notary_args

echo "Building release app..."
flutter build macos --release
[[ -d "$SOURCE_APP" ]] || fail "release app not found: $SOURCE_APP"
[[ -f "$ENTITLEMENTS" ]] || fail "entitlements not found: $ENTITLEMENTS"

case "$WORK_DIR" in
  "$ROOT_DIR"/build/*) rm -rf "$WORK_DIR" ;;
  *) fail "refusing to remove unexpected work directory: $WORK_DIR" ;;
esac
mkdir -p "$STAGING_DIR" "$DMG_ROOT"

echo "Staging $APP_BUNDLE_NAME..."
ditto "$SOURCE_APP" "$STAGED_APP"

echo "Signing nested code..."
while IFS= read -r -d '' item; do
  sign_code "$item"
done < <(
  find "$STAGED_APP" -depth \
    \( -name "*.framework" -o -name "*.dylib" -o -name "*.so" -o -name "*.xpc" -o -name "*.appex" \) \
    -print0
)

echo "Signing app..."
codesign \
  --force \
  --timestamp \
  --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --sign "$DEVELOPER_ID_APPLICATION" \
  "$STAGED_APP"
codesign --verify --deep --strict --verbose=2 "$STAGED_APP"

echo "Creating DMG..."
ditto "$STAGED_APP" "$DMG_ROOT/$APP_BUNDLE_NAME"
ln -s /Applications "$DMG_ROOT/Applications"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_DISPLAY_NAME" \
  -srcfolder "$DMG_ROOT" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG_PATH"

echo "Signing DMG..."
codesign --force --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

echo "Submitting DMG for notarization..."
xcrun notarytool submit "$DMG_PATH" --wait "${NOTARY_ARGS[@]}"

echo "Stapling DMG..."
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"

echo "Release DMG: $DMG_PATH"
