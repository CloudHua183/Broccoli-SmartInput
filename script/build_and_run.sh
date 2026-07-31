#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="$ROOT_DIR/DerivedData"
PROJECT_PATH="$ROOT_DIR/McBopomofo.xcodeproj"
SCHEME="McBopomofoInstaller"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/McBopomofoInstaller.app"

pkill -x McBopomofoInstaller >/dev/null 2>&1 || true

xcodebuild build \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  SWIFT_ENABLE_EXPLICIT_MODULES=NO \
  CLANG_ENABLE_EXPLICIT_MODULES=NO

/usr/bin/open -n "$APP_PATH"

if [[ "${1:-}" == "--verify" ]]; then
  sleep 2
  pgrep -x McBopomofoInstaller >/dev/null
fi
