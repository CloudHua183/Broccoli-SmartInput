#!/bin/zsh
# One-time per-machine setup for git-backed dictionary sync.
#
# Usage: ./script/setup_dict_sync.sh git@github.com:USER/REPO.git
#    or: ./script/setup_dict_sync.sh https://github.com/USER/REPO.git
#
# On the first machine this seeds the repository from the dictionaries the
# input method is currently using. On every other machine it clones what is
# already there. Either way the repository working tree becomes the input
# method's dictionary folder, and a launchd job keeps it in sync.

set -euo pipefail

REMOTE="${1:-}"
if [[ -z "$REMOTE" ]]; then
  echo "usage: $0 <git-remote-url>" >&2
  exit 2
fi

DOMAIN="org.openvanilla.inputmethod.McBopomofo"
REPO_DIR="$HOME/Library/Application Support/BroccoliSmartInputDict"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SYNC_SCRIPT="$SCRIPT_DIR/dict_sync.sh"
AGENT_DIR="$HOME/Library/LaunchAgents"
AGENT_LABEL="com.broccolismartinput.dictsync"
AGENT_PLIST="$AGENT_DIR/$AGENT_LABEL.plist"
LOG_DIR="$HOME/Library/Logs/BroccoliSmartInput"

DICTIONARY_FILES=(
  data.txt
  data-plain-bpmf.txt
  exclude-phrases.txt
  exclude-phrases-plain-bpmf.txt
  phrases-replacement.txt
  smart-mixed-ascii-words.txt
)

if [[ ! -x "$SYNC_SCRIPT" ]]; then
  echo "error: $SYNC_SCRIPT is missing or not executable" >&2
  exit 1
fi

CURRENT_LOCATION="$(/usr/bin/defaults read "$DOMAIN" CustomUserPhraseLocation 2>/dev/null || true)"
USE_CUSTOM="$(/usr/bin/defaults read "$DOMAIN" UseCustomUserPhraseLocation 2>/dev/null || echo 0)"
if [[ "$USE_CUSTOM" != "1" || -z "$CURRENT_LOCATION" ]]; then
  CURRENT_LOCATION="$HOME/Library/Application Support/McBopomofo"
fi
echo "==> Current dictionary folder: $CURRENT_LOCATION"
echo "==> Repository folder:         $REPO_DIR"

/bin/mkdir -p "$REPO_DIR" "$LOG_DIR"
cd "$REPO_DIR"

if [[ ! -d .git ]]; then
  git init -q -b main
fi
if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$REMOTE"
else
  git remote add origin "$REMOTE"
fi

# Distinguish "the remote is empty" from "we could not reach the remote".
# Treating a failed fetch as an empty remote would seed from this machine and
# later fight whatever is already on the remote, so fail loudly instead.
if ! git fetch origin 2>/tmp/broccoli-dict-fetch.err; then
  echo "error: cannot reach $REMOTE" >&2
  echo >&2
  /bin/cat /tmp/broccoli-dict-fetch.err >&2
  echo >&2
  echo "GitHub no longer accepts an account password over https. Authenticate" >&2
  echo "this machine first, then run this script again:" >&2
  echo >&2
  echo "    gh auth login" >&2
  echo >&2
  echo "Nothing was changed. Your dictionaries are untouched at:" >&2
  echo "    $CURRENT_LOCATION" >&2
  exit 1
fi

if git rev-parse --verify --quiet origin/main >/dev/null; then
  echo "==> Remote already has dictionaries; using them."
  git checkout -q -B main origin/main
else
  echo "==> Remote is empty; seeding it from this machine."
  cat > .gitattributes <<'ATTR'
# Two machines adding different phrases should produce a file with both, not a
# conflict. Union keeps both sides of a conflicting hunk; dict_sync.sh then
# removes any duplicated line, preserving order.
*.txt merge=union
ATTR
  cat > .gitignore <<'IGNORE'
diagnostics.log
*.bak
*.retired
.DS_Store
.broccoli-patch-base-*
IGNORE
  for name in "${DICTIONARY_FILES[@]}"; do
    if [[ -f "$CURRENT_LOCATION/$name" ]]; then
      /usr/bin/ditto --norsrc "$CURRENT_LOCATION/$name" "$REPO_DIR/$name"
      echo "    seeded: $name"
    fi
  done
  git add -A
  git -c user.name="Broccoli Dict Sync" -c user.email="dict-sync@localhost" \
    commit -q -m "Seed dictionaries from $(/usr/sbin/scutil --get ComputerName 2>/dev/null || /bin/hostname -s)"
  git push -q -u origin main
fi

# Point the input method at the repository and restart it.
/usr/bin/killall McBopomofo >/dev/null 2>&1 || true
/bin/sleep 1
/usr/bin/defaults write "$DOMAIN" UseCustomUserPhraseLocation -bool true
/usr/bin/defaults write "$DOMAIN" CustomUserPhraseLocation -string "$REPO_DIR"

/bin/mkdir -p "$AGENT_DIR"
/bin/cat > "$AGENT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$AGENT_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/zsh</string>
        <string>$SYNC_SCRIPT</string>
    </array>
    <key>StartInterval</key>
    <integer>900</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/dict-sync.stderr.log</string>
</dict>
</plist>
PLIST

/bin/launchctl bootout "gui/$(/usr/bin/id -u)/$AGENT_LABEL" >/dev/null 2>&1 || true
/bin/launchctl bootstrap "gui/$(/usr/bin/id -u)" "$AGENT_PLIST"

/usr/bin/open "$HOME/Library/Input Methods/McBopomofo.app" >/dev/null 2>&1 || true

echo
echo "==> Preferences now:"
echo "    UseCustomUserPhraseLocation = $(/usr/bin/defaults read "$DOMAIN" UseCustomUserPhraseLocation)"
echo "    CustomUserPhraseLocation    = $(/usr/bin/defaults read "$DOMAIN" CustomUserPhraseLocation)"
echo "==> launchd job $AGENT_LABEL installed, runs every 900s."
echo "==> Log: $LOG_DIR/dict-sync.log"
echo
echo "Done. The previous dictionary folder is untouched and can serve as a backup:"
echo "    $CURRENT_LOCATION"
