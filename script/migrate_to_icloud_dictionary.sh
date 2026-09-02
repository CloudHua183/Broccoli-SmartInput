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

# Once the migration has run, $TARGET_DIR is the live dictionary folder and
# $SOURCE_DIR is a frozen backup. Copying source over target again would throw
# away every phrase added since the first run, so detect that state and skip
# the copy phase entirely.
CURRENT_LOCATION="$(/usr/bin/defaults read "$DOMAIN" CustomUserPhraseLocation 2>/dev/null || true)"
ALREADY_MIGRATED=0
if [[ "$CURRENT_LOCATION" == "$TARGET_DIR" ]]; then
  ALREADY_MIGRATED=1
  echo "==> Already migrated; the dictionaries in iCloud are the live copies."
  echo "    Skipping the copy phase so newer phrases are not overwritten."
fi

# Quit the input method first, so it cannot write the old location back over
# the preferences we are about to set.
/usr/bin/killall McBopomofo >/dev/null 2>&1 || true
/bin/sleep 1

copied=0
skipped=0
for name in "${DICTIONARY_FILES[@]}"; do
  if [[ $ALREADY_MIGRATED -eq 1 ]]; then
    break
  fi
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
    # Second guard: never let an older source overwrite a newer target.
    if [[ "$dst" -nt "$src" ]]; then
      echo "    target is newer, kept: $name"
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

echo "==> $copied file(s) copied, $skipped kept as-is."
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

# Earlier builds wrote diagnostics.log into the dictionary folder, which now
# means into iCloud Drive. Move any stray copy into ~/Library/Logs, where the
# current build writes it and where nothing syncs it.
LOG_DIR="$HOME/Library/Logs/BroccoliSmartInput"
STRAY_LOG="$TARGET_DIR/diagnostics.log"
if [[ -f "$STRAY_LOG" ]]; then
  /bin/mkdir -p "$LOG_DIR"
  /bin/mv "$STRAY_LOG" "$LOG_DIR/diagnostics.$(/bin/date +%Y%m%d-%H%M%S).log"
  echo "==> Moved stray diagnostics.log out of iCloud into $LOG_DIR"
fi

echo "==> Preferences now:"
echo "    UseCustomUserPhraseLocation = $(/usr/bin/defaults read "$DOMAIN" UseCustomUserPhraseLocation)"
echo "    CustomUserPhraseLocation    = $(/usr/bin/defaults read "$DOMAIN" CustomUserPhraseLocation)"

/usr/bin/open "$HOME/Library/Input Methods/McBopomofo.app" >/dev/null 2>&1 || true
/bin/sleep 1

echo
echo "Done. The input method now reads and writes its dictionaries in iCloud Drive."
echo "Run the same script on your other Macs; they will share the same folder."
