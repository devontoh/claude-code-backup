# Claude Code Back Up - Installer
# Built by Devon T. | https://www.linkedin.com/in/devontoh/
#
# Run this once from the folder where you cloned the repo:
#   powershell -ExecutionPolicy Bypass -File install.ps1

$ErrorActionPreference = "Continue"

$KEY_FILE      = "$PSScriptRoot\.claude-backup-key"
$REMOTE_NAME   = "gdrive"
$REMOTE_FOLDER = "ClaudeCodeBackups"
$SETTINGS_FILE = "$env:USERPROFILE\.claude\settings.json"
$RUN_SCRIPT    = "$PSScriptRoot\run.ps1"
$BACKUP_SCRIPT = "$PSScriptRoot\backup.ps1"

Write-Host ""
Write-Host "=== Claude Code Back Up - Setup ===" -ForegroundColor Cyan
Write-Host "Built by Devon T. | https://www.linkedin.com/in/devontoh/" -ForegroundColor DarkGray
Write-Host ""

# Step 1: Install dependencies
Write-Host "Step 1: Checking dependencies..." -ForegroundColor Yellow

$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") `
          + ";" `
          + [System.Environment]::GetEnvironmentVariable("PATH", "User")

if (-not (Get-Command rclone -ErrorAction SilentlyContinue)) {
    Write-Host "  Installing rclone..." -ForegroundColor Gray
    winget install Rclone.Rclone --silent --accept-package-agreements --accept-source-agreements
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") `
              + ";" `
              + [System.Environment]::GetEnvironmentVariable("PATH", "User")
} else {
    Write-Host "  rclone: already installed" -ForegroundColor Green
}

if (-not (Get-Command gpg -ErrorAction SilentlyContinue) -and -not (Test-Path "C:\Program Files\GnuPG\bin\gpg.exe")) {
    Write-Host "  Installing GPG..." -ForegroundColor Gray
    winget install GnuPG.GnuPG --silent --accept-package-agreements --accept-source-agreements
} else {
    Write-Host "  GPG: already installed" -ForegroundColor Green
}

Write-Host ""

# Step 2: Configure Google Drive
Write-Host "Step 2: Connecting Google Drive..." -ForegroundColor Yellow

$remotes = & rclone listremotes --log-level ERROR 2>$null
if ($remotes -notcontains ($REMOTE_NAME + ":")) {
    Write-Host "  Launching rclone config..." -ForegroundColor Gray
    Write-Host "  Create a new remote, choose Google Drive, name it '$REMOTE_NAME'." -ForegroundColor Gray
    Write-Host ""
    & rclone config
} else {
    Write-Host "  Google Drive remote '$REMOTE_NAME': already configured" -ForegroundColor Green
}

& rclone mkdir ($REMOTE_NAME + ":" + $REMOTE_FOLDER) --log-level ERROR 2>$null
Write-Host ""

# Step 3: Set encryption passphrase
Write-Host "Step 3: Setting encryption passphrase..." -ForegroundColor Yellow

if (Test-Path $KEY_FILE) {
    Write-Host "  Passphrase already set. Skipping." -ForegroundColor Green
} else {
    Write-Host "  This passphrase encrypts every backup. Save it in your password manager." -ForegroundColor Gray
    Write-Host ""
    $pass1 = Read-Host "  Passphrase" -AsSecureString
    $pass2 = Read-Host "  Confirm passphrase" -AsSecureString

    $ptr1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass1)
    $ptr2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass2)
    $p1   = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr1)
    $p2   = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr2)

    if ($p1 -ne $p2) {
        Write-Host "  ERROR: Passphrases do not match. Re-run install.ps1." -ForegroundColor Red
        exit 1
    }

    $encrypted = ConvertFrom-SecureString $pass1
    $encrypted | Out-File -FilePath $KEY_FILE -Encoding UTF8

    Write-Host ""
    Write-Host "  Passphrase saved (encrypted to this machine)." -ForegroundColor Green
    Write-Host ""
    Write-Host "  *** SAVE THIS PASSPHRASE IN YOUR PASSWORD MANAGER NOW. ***" -ForegroundColor Yellow
    Write-Host "  If this machine dies, the encryption key dies with it." -ForegroundColor Yellow
    Write-Host "  Your Drive backups will be permanently unreadable without it." -ForegroundColor Yellow
}

Write-Host ""

# Step 4: Wire up the Claude Code Stop hook
Write-Host "Step 4: Adding Claude Code hook..." -ForegroundColor Yellow

$hookCmd = "powershell -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$RUN_SCRIPT`""

if (Test-Path $SETTINGS_FILE) {
    $raw      = Get-Content $SETTINGS_FILE -Raw -Encoding UTF8
    $settings = $raw | ConvertFrom-Json
} else {
    $settings = [PSCustomObject]@{}
}

$hookEntry = [PSCustomObject]@{
    matcher = ""
    hooks   = @([PSCustomObject]@{ type = "command"; command = $hookCmd })
}

if (-not $settings.PSObject.Properties["hooks"]) {
    $settings | Add-Member -NotePropertyName "hooks" -NotePropertyValue ([PSCustomObject]@{})
}
if (-not $settings.hooks.PSObject.Properties["Stop"]) {
    $settings.hooks | Add-Member -NotePropertyName "Stop" -NotePropertyValue @()
}

$alreadyAdded = $settings.hooks.Stop | Where-Object {
    $_.hooks | Where-Object { $_.command -like "*run.ps1*" }
}

if (-not $alreadyAdded) {
    $settings.hooks.Stop = @($hookEntry) + @($settings.hooks.Stop)
    $settings | ConvertTo-Json -Depth 10 | Out-File $SETTINGS_FILE -Encoding UTF8
    Write-Host "  Hook added. Backup runs automatically after every Claude Code session." -ForegroundColor Green
} else {
    Write-Host "  Hook already present. Skipping." -ForegroundColor Green
}

Write-Host ""

# Step 5: Run first backup
Write-Host "Step 5: Running first backup..." -ForegroundColor Yellow
Write-Host "  This may take several minutes depending on your Documents size." -ForegroundColor Gray
Write-Host ""

& powershell -NonInteractive -ExecutionPolicy Bypass -File $BACKUP_SCRIPT

Write-Host ""
Write-Host "=== Setup complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "From now on, Claude Code backs itself up every time you end a session." -ForegroundColor Cyan
Write-Host "Check the latest backup any time: .\backup.ps1 -Check" -ForegroundColor DarkGray
Write-Host ""
