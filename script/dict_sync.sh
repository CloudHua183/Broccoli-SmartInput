#!/bin/zsh
# Sync the Broccoli SmartInput dictionaries through a private git repository.
#
# The repository working tree IS the dictionary folder: the input method reads
# and writes it directly (CustomUserPhraseLocation points here), so there is no
# copying and nothing can drift out of step. This script commits whatever the
# input method has written, merges what the other machines pushed, and pushes
# the result.
#
# Conflicts: .gitattributes marks the dictionary files as merge=union, so two
# machines adding different phrases produce a file containing both rather than
# a conflict. The dedupe pass below then removes any line that ended up twice,
# preserving order, because user phrase ranking depends on the order in which
# the phrases appear.

set -uo pipefail

REPO_DIR="${BROCCOLI_DICT_REPO:-$HOME/Library/Application Support/BroccoliSmartInputDict}"
LOG_DIR="$HOME/Library/Logs/BroccoliSmartInput"
LOG_FILE="$LOG_DIR/dict-sync.log"

/bin/mkdir -p "$LOG_DIR"

log() {
  echo "[$(/bin/date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

if [[ ! -d "$REPO_DIR/.git" ]]; then
  log "error: $REPO_DIR is not a git repository. Run setup_dict_sync.sh first."
  exit 1
fi

cd "$REPO_DIR"

MACHINE="$(/usr/sbin/scutil --get ComputerName 2>/dev/null || /bin/hostname -s)"

dedupe() {
  /usr/bin/python3 - "$@" <<'PY'
import io, sys
changed = []
for path in sys.argv[1:]:
    try:
        lines = io.open(path, encoding="utf-8").read().split("\n")
    except FileNotFoundError:
        continue
    seen = set()
    out = []
    for line in lines:
        key = line.strip()
        # Keep every blank line and comment; they carry no ranking meaning and
        # removing them would churn the file for no reason.
        if not key or key.startswith("#"):
            out.append(line)
            continue
        if key in seen:
            continue
        seen.add(key)
        out.append(line)
    new = "\n".join(out)
    if new != "\n".join(lines):
        io.open(path, "w", encoding="utf-8").write(new)
        changed.append(path)
for path in changed:
    print(path)
PY
}

commit_if_dirty() {
  local message="$1"
  if [[ -n "$(git status --porcelain)" ]]; then
    git add -A >/dev/null
    git -c user.name="Broccoli Dict Sync" -c user.email="dict-sync@localhost" \
      commit -q -m "$message" && log "committed: $message"
    return 0
  fi
  return 1
}

commit_if_dirty "local changes from $MACHINE"

if ! git fetch origin --quiet 2>>"$LOG_FILE"; then
  log "warning: fetch failed; staying offline this run"
  exit 0
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"

if git rev-parse --verify --quiet "origin/$BRANCH" >/dev/null; then
  if ! git merge --no-edit --quiet "origin/$BRANCH" >>"$LOG_FILE" 2>&1; then
    log "error: merge failed, leaving the tree for manual inspection"
    exit 1
  fi
  if [[ -n "$(dedupe data.txt data-plain-bpmf.txt exclude-phrases.txt exclude-phrases-plain-bpmf.txt phrases-replacement.txt smart-mixed-ascii-words.txt)" ]]; then
    commit_if_dirty "dedupe after merge on $MACHINE"
  fi
fi

if [[ -n "$(git log "origin/$BRANCH..HEAD" --oneline 2>/dev/null)" ]] || \
   ! git rev-parse --verify --quiet "origin/$BRANCH" >/dev/null; then
  if git push --quiet -u origin "$BRANCH" >>"$LOG_FILE" 2>&1; then
    log "pushed"
  else
    log "warning: push rejected, will retry next run"
  fi
fi

log "ok"
