#!/bin/bash
# Claude Code Back Up - macOS
# Built by Devon T. | https://www.linkedin.com/in/devontoh/
#
# Usage:
#   ./backup.sh          run a backup now
#   ./backup.sh --check  verify the latest backup is fresh

REMOTE_NAME="gdrive"
REMOTE_FOLDER="ClaudeCodeBackups"
KEEP_DAYS=7
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$SCRIPT_DIR/backup.log"

SOURCES=(
    "$HOME/Documents"
    "$HOME/.claude"
)

EXCLUDES=(
    "node_modules" ".next" "dist" "build"
    ".cache" "__pycache__" ".venv" "venv"
    ".turbo" ".output" ".DS_Store"
)

log() {
    local level="${2:-INFO}"
    local line="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $1"
    echo "$line" | tee -a "$LOG_FILE"
}

notify() {
    local title="$1"
    local msg="$2"
    osascript -e "display notification \"$msg\" with title \"$title\"" 2>/dev/null || true
}

get_passphrase() {
    security find-generic-password -a "claude-backup" -s "ClaudeCodeBackup" -w 2>/dev/null
}

# CHECK
if [ "$1" = "--check" ]; then
    files=$(rclone lsjson --log-level ERROR "$REMOTE_NAME:$REMOTE_FOLDER" 2>/dev/null)
    if [ -z "$files" ] || [ "$files" = "[]" ]; then
        echo "No backups found in $REMOTE_NAME:$REMOTE_FOLDER"
        exit 1
    fi

    newest=$(echo "$files" | python3 -c "
import json, sys
from datetime import datetime, timezone
files = sorted(json.load(sys.stdin), key=lambda x: x['ModTime'], reverse=True)
f = files[0]
mod = datetime.fromisoformat(f['ModTime'].replace('Z','+00:00'))
age = (datetime.now(timezone.utc) - mod).total_seconds() / 3600
print(f\"{f['Name']}  ({age:.1f}h ago)  ({f['Size']/1024/1024:.1f} MB)\")
if age > 48:
    print('WARNING: backup is stale')
    sys.exit(1)
")
    echo "OK - newest backup: $newest"
    echo ""
    echo "All backups in $REMOTE_NAME:$REMOTE_FOLDER:"
    echo "$files" | python3 -c "
import json, sys
files = sorted(json.load(sys.stdin), key=lambda x: x['ModTime'], reverse=True)
for f in files:
    print(f\"  {f['Name']}  ({f['Size']/1024/1024:.1f} MB)\")
"
    exit 0
fi

# BACKUP
log "Backup started."

TMP_PASS=""
TMP_TAR=""
TMP_ENC=""

cleanup() {
    [ -n "$TMP_PASS" ] && rm -f "$TMP_PASS"
    [ -n "$TMP_TAR"  ] && rm -f "$TMP_TAR"
    [ -n "$TMP_ENC"  ] && rm -f "$TMP_ENC"
}
trap cleanup EXIT

PASSPHRASE=$(get_passphrase)
if [ -z "$PASSPHRASE" ]; then
    log "Passphrase not found in Keychain. Run install.sh first." "ERROR"
    exit 1
fi

DATE=$(date '+%Y-%m-%d_%H%M')
BACKUP_NAME="claude-backup-$DATE.tar.gz.gpg"
REMOTE_PATH="$REMOTE_NAME:$REMOTE_FOLDER/$BACKUP_NAME"

TMP_PASS=$(mktemp)
TMP_TAR=$(mktemp).tar.gz
TMP_ENC=$(mktemp).tar.gz.gpg

printf '%s' "$PASSPHRASE" > "$TMP_PASS"

# Step 1: Archive
TAR_ARGS=()
for ex in "${EXCLUDES[@]}"; do
    TAR_ARGS+=("--exclude=$ex")
done
TAR_ARGS+=("-czf" "$TMP_TAR")
TAR_ARGS+=("${SOURCES[@]}")

log "Archiving: Documents + .claude"
tar "${TAR_ARGS[@]}" 2>/dev/null
TAR_EXIT=$?
if [ $TAR_EXIT -gt 1 ]; then
    log "tar failed with exit code $TAR_EXIT" "ERROR"
    notify "Claude Backup FAILED" "tar failed - check backup.log"
    exit 1
fi
[ $TAR_EXIT -eq 1 ] && log "tar: some files skipped (non-fatal)"

# Step 2: Encrypt
log "Encrypting..."
gpg --batch --yes --passphrase-file "$TMP_PASS" --symmetric --cipher-algo AES256 -o "$TMP_ENC" "$TMP_TAR"
if [ $? -ne 0 ]; then
    log "gpg failed" "ERROR"
    notify "Claude Backup FAILED" "Encryption failed - check backup.log"
    exit 1
fi

ENC_SIZE=$(stat -f%z "$TMP_ENC" 2>/dev/null || stat -c%s "$TMP_ENC")
ENC_MB=$(echo "scale=1; $ENC_SIZE / 1048576" | bc)
log "Encrypted size: ${ENC_MB} MB"

if [ "$ENC_SIZE" -lt 1024 ]; then
    log "Encrypted file too small - archive likely empty" "ERROR"
    exit 1
fi

# Step 3: Upload
log "Uploading to $REMOTE_PATH"
rclone copyto "$TMP_ENC" "$REMOTE_PATH" --log-level ERROR
if [ $? -ne 0 ]; then
    log "rclone upload failed" "ERROR"
    notify "Claude Backup FAILED" "Upload failed - check backup.log"
    exit 1
fi

log "Upload complete: $BACKUP_NAME"

# Prune old backups
log "Pruning backups older than $KEEP_DAYS days..."
rclone lsjson --log-level ERROR "$REMOTE_NAME:$REMOTE_FOLDER" 2>/dev/null | python3 -c "
import json, sys, subprocess
from datetime import datetime, timezone, timedelta
files = json.load(sys.stdin)
cutoff = datetime.now(timezone.utc) - timedelta(days=$KEEP_DAYS)
for f in files:
    mod = datetime.fromisoformat(f['ModTime'].replace('Z','+00:00'))
    if mod < cutoff:
        print(f\"Deleting: {f['Name']}\")
        subprocess.run(['rclone','delete','$REMOTE_NAME:$REMOTE_FOLDER/'+f['Name'],'--log-level','ERROR'])
"

log "Backup finished successfully."
