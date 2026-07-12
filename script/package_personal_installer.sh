#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export COPYFILE_DISABLE=1
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/DerivedData}"
PROJECT_PATH="$ROOT_DIR/McBopomofo.xcodeproj"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$DIST_DIR/personal-installer-staging"
SCRIPTS_DIR="$STAGING_DIR/scripts"
APP_SOURCE="$DERIVED_DATA_PATH/Build/Products/Release/McBopomofo.app"
VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$ROOT_DIR/Source/McBopomofo-Info.plist" 2>/dev/null || echo dev)"
PKG_PATH="$DIST_DIR/Broccoli-SmartInput-v${VERSION}-personal.pkg"

/bin/mkdir -p "$DIST_DIR"
/bin/rm -rf "$STAGING_DIR"
/bin/mkdir -p "$SCRIPTS_DIR"

xcodebuild build \
  -project "$PROJECT_PATH" \
  -scheme McBopomofo \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  ONLY_ACTIVE_ARCH=NO

if [[ ! -d "$APP_SOURCE" ]]; then
  echo "error: built app not found: $APP_SOURCE" >&2
  exit 1
fi

/usr/bin/ditto --norsrc "$APP_SOURCE" "$SCRIPTS_DIR/McBopomofo.app"

/bin/mkdir -p "$SCRIPTS_DIR/UserData"

/bin/cat > "$SCRIPTS_DIR/postinstall" <<'POSTINSTALL'
#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE="$SCRIPT_DIR/McBopomofo.app"
USER_DATA="$SCRIPT_DIR/UserData"

CONSOLE_USER="$(/usr/sbin/scutil <<<'show State:/Users/ConsoleUser' | /usr/bin/awk '/Name :/ && $3 != "loginwindow" { print $3; exit }')"
if [[ -z "${CONSOLE_USER:-}" ]]; then
  echo "error: could not determine console user" >&2
  exit 1
fi

USER_ID="$(/usr/bin/id -u "$CONSOLE_USER")"
USER_HOME="$(/usr/bin/dscl . -read "/Users/$CONSOLE_USER" NFSHomeDirectory | /usr/bin/awk '{ print $2 }')"
if [[ -z "${USER_HOME:-}" || ! -d "$USER_HOME" ]]; then
  echo "error: could not determine home directory for $CONSOLE_USER" >&2
  exit 1
fi

INPUT_METHODS_DIR="$USER_HOME/Library/Input Methods"
TARGET_APP="$INPUT_METHODS_DIR/McBopomofo.app"
SUPPORT_DIR="$USER_HOME/Library/Application Support/McBopomofo"

/usr/bin/killall McBopomofo >/dev/null 2>&1 || true
/usr/bin/find "$SCRIPT_DIR" -name '._*' -delete >/dev/null 2>&1 || true

/bin/mkdir -p "$INPUT_METHODS_DIR"
/bin/rm -rf "$TARGET_APP"
/usr/bin/ditto --norsrc "$APP_BUNDLE" "$TARGET_APP"

/bin/mkdir -p "$SUPPORT_DIR"
if [[ -d "$USER_DATA" ]]; then
  /usr/bin/ditto --norsrc "$USER_DATA" "$SUPPORT_DIR"
fi

/usr/bin/xattr -dr com.apple.quarantine "$TARGET_APP" >/dev/null 2>&1 || true
/usr/bin/find "$TARGET_APP" "$SUPPORT_DIR" -name '._*' -delete >/dev/null 2>&1 || true
/usr/sbin/chown -R "$CONSOLE_USER":staff "$TARGET_APP" "$SUPPORT_DIR"

/bin/launchctl asuser "$USER_ID" /usr/bin/sudo -u "$CONSOLE_USER" "$TARGET_APP/Contents/MacOS/McBopomofo" install --all --select >/dev/null 2>&1 || true

exit 0
POSTINSTALL

/bin/chmod +x "$SCRIPTS_DIR/postinstall"
/usr/bin/xattr -cr "$SCRIPTS_DIR" >/dev/null 2>&1 || true

/usr/bin/pkgbuild \
  --nopayload \
  --scripts "$SCRIPTS_DIR" \
  --identifier "tw.huaye.inputmethod.personal" \
  --version "$VERSION" \
  "$PKG_PATH"

/bin/rm -rf "$STAGING_DIR"

echo "$PKG_PATH"
