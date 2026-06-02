# Claude Code Back Up

Never lose your Claude Code projects to a dead drive.

**Built by Devon T. | [linkedin.com/in/devontoh](https://www.linkedin.com/in/devontoh/)**

---

## What it does

Every time a Claude Code session ends, this runs silently in the background and:

- Archives your `Documents\` folder and `~\.claude\` (memory, settings, skills)
- Skips everything regeneratable: `node_modules`, `.next`, `dist`, `build`, `.cache`, `venv`
- Encrypts the archive with AES-256 before it leaves your machine
- Uploads directly to Google Drive via rclone (bypasses the buggy desktop client)
- Keeps the last 7 days of backups and prunes older ones automatically
- Alerts you if a backup fails or goes stale

## Why the Google Drive app always crashed

If you tried uploading your projects manually to iCloud or Google Drive and it always crashed, the reason is `node_modules`. A single Next.js project can have hundreds of thousands of tiny files with deeply nested paths that kill any cloud sync client. This script excludes all of that before the upload. Your projects go from gigabytes of junk to a few hundred MB of clean source files.

## Requirements

- Windows 10 or 11
- Google Drive account
- Claude Code installed

## Setup

Clone or download this repo, open PowerShell in the folder, then run:

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

The installer will:
1. Install `rclone` and `GPG` if not already installed
2. Walk you through connecting your Google Drive (browser sign-in, takes 2 minutes)
3. Ask you to set an encryption passphrase
4. Wire up the Claude Code hook so backups run automatically after every session
5. Run your first backup immediately

> **Important:** Save your passphrase in a password manager as soon as the installer asks. The passphrase is encrypted to your machine using Windows DPAPI. If your machine dies, the local key dies with it, and your Drive backups will be permanently unreadable without the passphrase.

## Manual commands

```powershell
# Run a backup right now
.\backup.ps1

# Check that the latest backup is fresh
.\backup.ps1 -Check
```

## How to restore

1. Download the archive from your Google Drive (`ClaudeCodeBackups` folder)
2. Decrypt it: `gpg -d backup.tar.gz.gpg > backup.tar.gz`
3. Extract it: `tar -xzf backup.tar.gz`
4. Run `npm install` in any project to rebuild `node_modules`

## Files

| File | Purpose |
|------|---------|
| `install.ps1` | One-time setup |
| `backup.ps1` | Backup logic, also used for `-Check` |
| `run.ps1` | Lightweight launcher called by the Claude Code hook |
| `.claude-backup-key` | Your DPAPI-encrypted passphrase (gitignored, never committed) |
| `backup.log` | Log of every backup run (gitignored) |

---

*Windows only for now. Silence means it is working.*
