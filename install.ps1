# Claude Code Back Up - Windows Installer
# Built by Devon T. | https://www.linkedin.com/in/devontoh/
#
# Run this once from the folder where you cloned the repo:
#   powershell -ExecutionPolicy Bypass -File install.ps1

$ErrorActionPreference = "Continue"

$KEY_FILE      = "$PSScriptRoot\.claude-backup-key"
$REMOTE_NAME   = "gdrive"
$REMOTE_FOLDER = "ClaudeCodeBackups"
$RCLONE_CONF   = "$env:APPDATA\rclone\rclone.conf"
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

$gpgInstalled = (Get-Command gpg -ErrorAction SilentlyContinue) -or (Test-Path "C:\Program Files\GnuPG\bin\gpg.exe")
if (-not $gpgInstalled) {
    Write-Host "  Installing GPG..." -ForegroundColor Gray
    winget install GnuPG.GnuPG --silent --accept-package-agreements --accept-source-agreements
} else {
    Write-Host "  GPG: already installed" -ForegroundColor Green
}

Write-Host ""

# Step 2: Connect Google Drive (fully automated - browser only, no menus)
Write-Host "Step 2: Connecting Google Drive..." -ForegroundColor Yellow

$remoteExists = (Test-Path $RCLONE_CONF) -and ((Get-Content $RCLONE_CONF -Raw -ErrorAction SilentlyContinue) -match '\[gdrive\]')

if ($remoteExists) {
    Write-Host "  Google Drive remote 'gdrive': already configured" -ForegroundColor Green
} else {
    Write-Host "  Your browser will open for Google sign-in." -ForegroundColor Gray
    Write-Host "  Sign in, allow access, then come back here." -ForegroundColor Gray
    Write-Host ""

    $authRaw = & rclone authorize "drive" 2>$null

    # Extract token from between rclone's output markers
    $capturing = $false
    $tokenParts = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $authRaw) {
        $s = "$line"
        if ($s -match 'Paste the following') { $capturing = $true; continue }
        if ($s -match 'End paste')           { $capturing = $false; continue }
        if ($capturing -and $s.Trim() -ne '')  { $tokenParts.Add($s.Trim()) }
    }
    $token = ($tokenParts -join "").Trim()

    if (-not $token) {
        Write-Host "  ERROR: Could not get Google Drive token. Re-run install.ps1." -ForegroundColor Red
        exit 1
    }

    # Write rclone config directly - avoids CLI quoting issues with the JSON token
    New-Item -ItemType Directory -Force -Path (Split-Path $RCLONE_CONF) | Out-Null
    $entry = "`r`n[gdrive]`r`ntype = drive`r`nscope = drive`r`ntoken = $token`r`n"
    Add-Content -Path $RCLONE_CONF -Value $entry -Encoding UTF8

    Write-Host "  Google Drive connected." -ForegroundColor Green
}

& rclone mkdir ($REMOTE_NAME + ":" + $REMOTE_FOLDER) --log-level ERROR 2>$null
Write-Host ""

# Step 3: Encryption passphrase
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
    $settings = Get-Content $SETTINGS_FILE -Raw -Encoding UTF8 | ConvertFrom-Json
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

# Step 5: First backup
Write-Host "Step 5: Running first backup..." -ForegroundColor Yellow
Write-Host "  This may take several minutes depending on your Documents size." -ForegroundColor Gray
Write-Host ""

& powershell -NonInteractive -ExecutionPolicy Bypass -File $BACKUP_SCRIPT

Write-Host ""
Write-Host "=== Setup complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Claude Code now backs itself up after every session." -ForegroundColor Cyan
Write-Host "Check anytime: .\backup.ps1 -Check" -ForegroundColor DarkGray
Write-Host ""
