#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="$ROOT_DIR/DerivedData"
PROJECT_PATH="$ROOT_DIR/McBopomofo.xcodeproj"
APP_NAME="McBopomofo.app"
BUILT_APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/$APP_NAME"
INSTALL_DIR="$HOME/Library/Input Methods"
INSTALLED_APP_PATH="$INSTALL_DIR/$APP_NAME"
INSTALLED_BINARY="$INSTALLED_APP_PATH/Contents/MacOS/McBopomofo"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

pkill -x McBopomofoInstaller >/dev/null 2>&1 || true
killall -9 McBopomofo >/dev/null 2>&1 || true

xcodebuild build \
  -project "$PROJECT_PATH" \
  -scheme McBopomofo \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED_DATA_PATH"

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALLED_APP_PATH"
cp -R "$BUILT_APP_PATH" "$INSTALL_DIR/"

"$INSTALLED_BINARY" install --all --select
"$LSREGISTER" -f -R -trusted "$INSTALLED_APP_PATH"

killall TextInputMenuAgent >/dev/null 2>&1 || true
/usr/bin/open "$INSTALLED_APP_PATH"

sleep 1
"$INSTALLED_BINARY" install --all --select

pgrep -x McBopomofo >/dev/null
echo "McBopomofo installed and 花椰輸入法 selected."
