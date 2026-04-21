#!/usr/bin/env bash
set -euo pipefail

APP_NAME="ClearVoice"
SCHEME="ClearVoice"
CONFIGURATION="Release"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/ClearVoice.xcodeproj"
DERIVED_DATA_PATH="$ROOT_DIR/.build/DerivedDataRelease"
DIST_DIR="$ROOT_DIR/.build/dist"
VERSION="$(awk '/MARKETING_VERSION:/ { print $2; exit }' "$ROOT_DIR/project.yml")"
APP_BUNDLE="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

mkdir -p "$DIST_DIR"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Expected app bundle not found: $APP_BUNDLE" >&2
  exit 1
fi

STAGING_DIR="$(mktemp -d /tmp/clearvoice_dmg.XXXXXX)"
cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

cp -R "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "DMG created at: $DMG_PATH"
