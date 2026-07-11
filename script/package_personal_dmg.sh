#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export COPYFILE_DISABLE=1
DIST_DIR="$ROOT_DIR/dist"
VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$ROOT_DIR/Source/McBopomofo-Info.plist" 2>/dev/null || echo dev)"
PKG_PATH="$DIST_DIR/HuayeInput-v${VERSION}-personal.pkg"
STAGING_DIR="$DIST_DIR/dmg-staging"
DMG_PATH="$DIST_DIR/HuayeInput-v${VERSION}-personal.dmg"
VOLUME_NAME="HuayeInput-v${VERSION}-personal"

if [[ ! -f "$PKG_PATH" ]]; then
  echo "error: package not found: $PKG_PATH" >&2
  echo "run script/package_personal_installer.sh first" >&2
  exit 1
fi

/bin/rm -rf "$STAGING_DIR"
/bin/mkdir -p "$STAGING_DIR"
/usr/bin/ditto --norsrc "$PKG_PATH" "$STAGING_DIR/$(basename "$PKG_PATH")"
/usr/bin/hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "$DMG_PATH"
