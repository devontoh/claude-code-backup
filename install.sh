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
RCLONE_CONF="$HOME/.config/rclone/rclone.conf"
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

# Step 2: Connect Google Drive (browser only, no menus)
echo "Step 2: Connecting Google Drive..."

REMOTE_EXISTS=false
if [ -f "$RCLONE_CONF" ] && grep -q '\[gdrive\]' "$RCLONE_CONF" 2>/dev/null; then
    REMOTE_EXISTS=true
fi

if [ "$REMOTE_EXISTS" = "true" ]; then
    echo "  Google Drive remote 'gdrive': already configured"
else
    echo "  Your browser will open for Google sign-in."
    echo "  Sign in, allow access, then come back here."
    echo ""

    AUTH_OUTPUT=$(rclone authorize "drive" 2>/dev/null)

    # Extract token from between rclone's output markers
    TOKEN=$(echo "$AUTH_OUTPUT" | awk '/Paste the following/{p=1;next} /End paste/{p=0} p' | tr -d '\n\r')

    if [ -z "$TOKEN" ]; then
        echo "  ERROR: Could not get Google Drive token. Re-run install.sh."
        exit 1
    fi

    # Write rclone config directly - avoids shell quoting issues with the JSON token
    mkdir -p "$(dirname "$RCLONE_CONF")"
    printf '\n[gdrive]\ntype = drive\nscope = drive\ntoken = %s\n' "$TOKEN" >> "$RCLONE_CONF"

    echo "  Google Drive connected."
fi

rclone mkdir "$REMOTE_NAME:$REMOTE_FOLDER" --log-level ERROR 2>/dev/null || true
echo ""

# Step 3: Encryption passphrase
echo "Step 3: Setting encryption passphrase..."

EXISTING_PASS=$(security find-generic-password -a "claude-backup" -s "ClaudeCodeBackup" -w 2>/dev/null || true)

if [ -n "$EXISTING_PASS" ]; then
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

    security delete-generic-password -a "claude-backup" -s "ClaudeCodeBackup" 2>/dev/null || true
    security add-generic-password -a "claude-backup" -s "ClaudeCodeBackup" -w "$PASS1"

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
import json, os

settings_path = "$SETTINGS_FILE"
hook_cmd = r"""$HOOK_CMD"""

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
echo "Claude Code now backs itself up after every session."
echo "Check anytime: ./backup.sh --check"
echo ""
