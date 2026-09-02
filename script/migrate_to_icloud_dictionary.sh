#!/bin/zsh
# Move the Broccoli SmartInput user dictionaries into iCloud Drive and point
# the input method at them.
#
# Why: the previous cloud sync used a Google Apps Script web app that had to
# allow anonymous access, because the input method cannot authenticate to
# Google. Letting iCloud Drive do the syncing means the files are reachable
# only from a Mac signed in to the owner's Apple Account, and the input method
# never touches the network at all.
#
# The originals are left in place as a backup; nothing is deleted.

set -euo pipefail

DOMAIN="org.openvanilla.inputmethod.McBopomofo"
SOURCE_DIR="$HOME/Library/Application Support/McBopomofo"
ICLOUD_ROOT="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
TARGET_DIR="$ICLOUD_ROOT/BroccoliSmartInput"

DICTIONARY_FILES=(
  data.txt
  data-plain-bpmf.txt
  exclude-phrases.txt
  exclude-phrases-plain-bpmf.txt
  phrases-replacement.txt
  smart-mixed-ascii-words.txt
)

if [[ ! -d "$ICLOUD_ROOT" ]]; then
  echo "error: iCloud Drive is not set up on this Mac ($ICLOUD_ROOT is missing)." >&2
  echo "Enable iCloud Drive in System Settings, then run this again." >&2
  exit 1
fi

echo "==> Source:  $SOURCE_DIR"
echo "==> Target:  $TARGET_DIR"

/bin/mkdir -p "$TARGET_DIR"

# Quit the input method first, so it cannot write the old location back over
# the preferences we are about to set.
/usr/bin/killall McBopomofo >/dev/null 2>&1 || true
/bin/sleep 1

copied=0
skipped=0
for name in "${DICTIONARY_FILES[@]}"; do
  src="$SOURCE_DIR/$name"
  dst="$TARGET_DIR/$name"
  if [[ ! -f "$src" ]]; then
    continue
  fi
  if [[ -f "$dst" ]]; then
    if /usr/bin/cmp -s "$src" "$dst"; then
      echo "    same, skipped: $name"
      skipped=$((skipped + 1))
      continue
    fi
    backup="$dst.$(/bin/date +%Y%m%d-%H%M%S).bak"
    /bin/cp "$dst" "$backup"
    echo "    existing target backed up: $(basename "$backup")"
  fi
  /usr/bin/ditto --norsrc "$src" "$dst"
  echo "    copied: $name"
  copied=$((copied + 1))
done

echo "==> $copied file(s) copied, $skipped already identical."
echo "==> Originals kept at $SOURCE_DIR"

# Point the input method at the iCloud folder.
/usr/bin/defaults write "$DOMAIN" UseCustomUserPhraseLocation -bool true
/usr/bin/defaults write "$DOMAIN" CustomUserPhraseLocation -string "$TARGET_DIR"

# Retire the old Apps Script configuration if it is still there. Without this
# file the "sync cloud dictionary" menu item does nothing, which is what we
# want now that iCloud does the syncing.
PATCH_SOURCE="$SOURCE_DIR/patch-source.json"
if [[ -f "$PATCH_SOURCE" ]]; then
  /bin/mv "$PATCH_SOURCE" "$PATCH_SOURCE.retired"
  echo "==> Retired $PATCH_SOURCE -> patch-source.json.retired"
fi

echo "==> Preferences now:"
echo "    UseCustomUserPhraseLocation = $(/usr/bin/defaults read "$DOMAIN" UseCustomUserPhraseLocation)"
echo "    CustomUserPhraseLocation    = $(/usr/bin/defaults read "$DOMAIN" CustomUserPhraseLocation)"

/usr/bin/open "$HOME/Library/Input Methods/McBopomofo.app" >/dev/null 2>&1 || true
/bin/sleep 1

echo
echo "Done. The input method now reads and writes its dictionaries in iCloud Drive."
echo "Run the same script on your other Macs; they will share the same folder."
