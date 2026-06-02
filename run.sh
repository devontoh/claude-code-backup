#!/bin/bash
# Lightweight launcher called by the Claude Code Stop hook.
# Fires backup.sh in a detached background process so Claude does not wait for it.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
nohup "$SCRIPT_DIR/backup.sh" >> "$SCRIPT_DIR/backup.log" 2>&1 &
