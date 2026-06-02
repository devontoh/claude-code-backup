# Claude Code Back Up
# Encrypts and uploads your Claude Code projects to Google Drive after every session.
# Built by Devon T. | https://www.linkedin.com/in/devontoh/
#
# Usage:
#   .\backup.ps1          run a backup now
#   .\backup.ps1 -Check   verify the latest backup is fresh

param([switch]$Check)

$ErrorActionPreference = "Continue"

# CONFIG
$REMOTE_NAME   = "gdrive"
$REMOTE_FOLDER = "ClaudeCodeBackups"
$KEEP_DAYS     = 7
$KEY_FILE      = "$PSScriptRoot\.claude-backup-key"
$LOG_FILE      = "$PSScriptRoot\backup.log"

$SOURCES = @(
    "$env:USERPROFILE\Documents",
    "$env:USERPROFILE\.claude"
)

$EXCLUDES = @(
    "node_modules", ".next", "dist", "build",
    ".cache", "__pycache__", ".venv", "venv",
    ".turbo", ".output", "Thumbs.db",
    "My Videos", "My Music", "My Pictures", "desktop.ini"
)

function Write-Log {
    param([string]$Msg, [string]$Level = "INFO")
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Msg"
    Add-Content -Path $LOG_FILE -Value $line -Encoding UTF8
    if ($Level -eq "ERROR") { Write-Host $line -ForegroundColor Red }
    else                    { Write-Host $line }
}

function Show-Notification {
    param([string]$Title, [string]$Body, [bool]$IsError = $false)
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $tray = New-Object System.Windows.Forms.NotifyIcon
        if ($IsError) { $tray.Icon = [System.Drawing.SystemIcons]::Warning }
        else          { $tray.Icon = [System.Drawing.SystemIcons]::Information }
        $tray.BalloonTipTitle = $Title
        $tray.BalloonTipText  = $Body
        $tray.Visible = $true
        $tray.ShowBalloonTip(10000)
        Start-Sleep -Seconds 11
        $tray.Dispose()
    } catch { }
}

function Get-Passphrase {
    if (-not (Test-Path $KEY_FILE)) {
        throw "Key file not found. Run install.ps1 first."
    }
    $enc  = (Get-Content $KEY_FILE -Raw -Encoding UTF8).Trim()
    $sec  = ConvertTo-SecureString $enc
    $ptr  = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr)
}

# CHECK
if ($Check) {
    $json  = & rclone lsjson --log-level ERROR ($REMOTE_NAME + ":" + $REMOTE_FOLDER) 2>$null
    $files = $json | ConvertFrom-Json | Sort-Object ModTime -Descending

    if (-not $files -or $files.Count -eq 0) {
        Write-Host "No backups found in $REMOTE_NAME`:$REMOTE_FOLDER" -ForegroundColor Red
        exit 1
    }

    $newest  = [datetime]$files[0].ModTime
    $age     = (Get-Date) - $newest
    $ageHrs  = [math]::Round($age.TotalHours, 1)
    $ageDays = [math]::Round($age.TotalDays, 1)

    if ($age.TotalDays -gt 2) {
        $msg = "Newest backup is $ageDays days old."
        Write-Host "WARNING: $msg" -ForegroundColor Red
        Show-Notification "Claude Backup Warning" $msg $true
    } else {
        Write-Host "OK - newest backup: $($files[0].Name) (${ageHrs}h ago)" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "All backups in $REMOTE_NAME`:$REMOTE_FOLDER`:"
    foreach ($f in $files) {
        $sizeMB = [math]::Round($f.Size / 1MB, 1)
        Write-Host "  $($f.Name)  ($sizeMB MB)"
    }
    exit 0
}

# BACKUP
Write-Log "Backup started."

$tmpPass = $null
$tmpTar  = $null
$tmpEnc  = $null

try {
    $passphrase = Get-Passphrase

    $date       = Get-Date -Format "yyyy-MM-dd_HHmm"
    $backupName = "claude-backup-$date.tar.gz.gpg"
    $remotePath = $REMOTE_NAME + ":" + $REMOTE_FOLDER + "/" + $backupName

    $gpgExe = "gpg"
    foreach ($c in @("C:\Program Files\GnuPG\bin\gpg.exe", "C:\Program Files (x86)\GnuPG\bin\gpg.exe")) {
        if (Test-Path $c) { $gpgExe = $c; break }
    }

    $tmpPass = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($tmpPass, $passphrase, [System.Text.Encoding]::ASCII)

    $tmpTar = Join-Path $env:TEMP ("claude-backup-$date.tar.gz")
    $tmpEnc = Join-Path $env:TEMP ("claude-backup-$date.tar.gz.gpg")

    # Step 1: Archive
    $tarArgs = @()
    foreach ($ex in $EXCLUDES) { $tarArgs += "--exclude=$ex" }
    $tarArgs += @("-czf", $tmpTar)
    $tarArgs += $SOURCES

    Write-Log "Archiving: Documents + .claude"
    & tar @tarArgs
    $tarExit = $LASTEXITCODE
    if ($tarExit -gt 1) { throw "tar failed with exit code $tarExit" }
    if ($tarExit -eq 1) { Write-Log "tar: some files skipped (non-fatal)" }

    # Step 2: Encrypt
    Write-Log "Encrypting..."
    & $gpgExe --batch --yes --passphrase-file $tmpPass --symmetric --cipher-algo AES256 -o $tmpEnc $tmpTar
    if ($LASTEXITCODE -ne 0) { throw "gpg failed with exit code $LASTEXITCODE" }

    $encSize = (Get-Item $tmpEnc).Length
    if ($encSize -lt 1024) { throw "Encrypted file too small ($encSize bytes) - archive likely empty" }
    Write-Log ("Encrypted size: " + [math]::Round($encSize / 1MB, 1) + " MB")

    # Step 3: Upload
    Write-Log ("Uploading to " + $remotePath)
    & rclone copyto $tmpEnc $remotePath --log-level ERROR
    if ($LASTEXITCODE -ne 0) { throw "rclone upload failed with exit code $LASTEXITCODE" }

    Write-Log "Upload complete: $backupName"

    # Prune - only after a successful upload
    Write-Log "Pruning backups older than $KEEP_DAYS days..."
    $allJson  = & rclone lsjson --log-level ERROR ($REMOTE_NAME + ":" + $REMOTE_FOLDER) 2>$null
    $allFiles = $allJson | ConvertFrom-Json
    $cutoff   = (Get-Date).AddDays(-$KEEP_DAYS)

    foreach ($f in $allFiles) {
        if ([datetime]$f.ModTime -lt $cutoff) {
            Write-Log "Deleting old backup: $($f.Name)"
            & rclone delete ($REMOTE_NAME + ":" + $REMOTE_FOLDER + "/" + $f.Name) --log-level ERROR 2>$null
        }
    }

    Write-Log "Backup finished successfully."

} catch {
    Write-Log "BACKUP FAILED: $_" "ERROR"
    Show-Notification "Claude Code Backup FAILED" $_.ToString() $true
    exit 1

} finally {
    if ($tmpPass -and (Test-Path $tmpPass)) { Remove-Item $tmpPass -Force -ErrorAction SilentlyContinue }
    if ($tmpTar  -and (Test-Path $tmpTar))  { Remove-Item $tmpTar  -Force -ErrorAction SilentlyContinue }
    if ($tmpEnc  -and (Test-Path $tmpEnc))  { Remove-Item $tmpEnc  -Force -ErrorAction SilentlyContinue }
}
