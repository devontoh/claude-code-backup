#!/bin/bash
# Claude Code Back Up - macOS Installer
# Built by Devon T. | https://www.linkedin.com/in/devontoh/
#
# Run this once from the folder where you cloned the repo:
#   bash install.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REMOTE_NAME="gdrive"
REMOTE_FOLDER="ClaudeCodeBackups"
SETTINGS_FILE="$HOME/.claude/settings.json"
RUN_SCRIPT="$SCRIPT_DIR/run.sh"
BACKUP_SCRIPT="$SCRIPT_DIR/backup.sh"

echo ""
echo "=== Claude Code Back Up - Setup ==="
echo "Built by Devon T. | https://www.linkedin.com/in/devontoh/"
echo ""

# Step 1: Dependencies
echo "Step 1: Checking dependencies..."

if ! command -v brew &>/dev/null; then
    echo "  Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

if ! command -v rclone &>/dev/null; then
    echo "  Installing rclone..."
    brew install rclone
else
    echo "  rclone: already installed"
fi

if ! command -v gpg &>/dev/null; then
    echo "  Installing gpg..."
    brew install gnupg
else
    echo "  gpg: already installed"
fi

chmod +x "$BACKUP_SCRIPT" "$RUN_SCRIPT"
echo ""

# Step 2: Google Drive
echo "Step 2: Connecting Google Drive..."

if ! rclone listremotes --log-level ERROR 2>/dev/null | grep -q "^${REMOTE_NAME}:"; then
    echo "  Launching rclone config..."
    echo "  Create a new remote, choose Google Drive, name it '$REMOTE_NAME'."
    echo ""
    rclone config
else
    echo "  Google Drive remote '$REMOTE_NAME': already configured"
fi

rclone mkdir "$REMOTE_NAME:$REMOTE_FOLDER" --log-level ERROR 2>/dev/null || true
echo ""

# Step 3: Encryption passphrase
echo "Step 3: Setting encryption passphrase..."

existing=$(security find-generic-password -a "claude-backup" -s "ClaudeCodeBackup" -w 2>/dev/null || true)

if [ -n "$existing" ]; then
    echo "  Passphrase already set in Keychain. Skipping."
else
    echo "  This passphrase encrypts every backup. Save it in your password manager."
    echo ""
    read -s -p "  Passphrase: " PASS1
    echo ""
    read -s -p "  Confirm passphrase: " PASS2
    echo ""

    if [ "$PASS1" != "$PASS2" ]; then
        echo "  ERROR: Passphrases do not match. Re-run install.sh."
        exit 1
    fi

    security add-generic-password -a "claude-backup" -s "ClaudeCodeBackup" -w "$PASS1" 2>/dev/null \
        || security delete-generic-password -a "claude-backup" -s "ClaudeCodeBackup" 2>/dev/null \
        && security add-generic-password -a "claude-backup" -s "ClaudeCodeBackup" -w "$PASS1"

    echo ""
    echo "  Passphrase saved to macOS Keychain."
    echo ""
    echo "  *** SAVE THIS PASSPHRASE IN YOUR PASSWORD MANAGER NOW. ***"
    echo "  If this Mac dies, the Keychain dies with it."
    echo "  Your Drive backups will be permanently unreadable without it."
fi

echo ""

# Step 4: Claude Code Stop hook
echo "Step 4: Adding Claude Code hook..."

HOOK_CMD="bash \"$RUN_SCRIPT\""

python3 - <<PYEOF
import json, os, sys

settings_path = "$SETTINGS_FILE"
hook_cmd = "$HOOK_CMD"

try:
    with open(settings_path, "r", encoding="utf-8") as f:
        settings = json.load(f)
except FileNotFoundError:
    settings = {}

hook_entry = {
    "matcher": "",
    "hooks": [{"type": "command", "command": hook_cmd}]
}

if "hooks" not in settings:
    settings["hooks"] = {}
if "Stop" not in settings["hooks"]:
    settings["hooks"]["Stop"] = []

already = any(
    any("run.sh" in h.get("command", "") for h in e.get("hooks", []))
    for e in settings["hooks"]["Stop"]
)

if not already:
    settings["hooks"]["Stop"].insert(0, hook_entry)
    with open(settings_path, "w", encoding="utf-8") as f:
        json.dump(settings, f, indent=2)
    print("  Hook added. Backup runs automatically after every Claude Code session.")
else:
    print("  Hook already present. Skipping.")
PYEOF

echo ""

# Step 5: First backup
echo "Step 5: Running first backup..."
echo "  This may take several minutes depending on your Documents size."
echo ""

bash "$BACKUP_SCRIPT"

echo ""
echo "=== Setup complete ==="
echo ""
echo "From now on, Claude Code backs itself up every time you end a session."
echo "Check the latest backup any time: ./backup.sh --check"
echo ""
