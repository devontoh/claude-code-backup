# Lightweight launcher called by the Claude Code Stop hook.
# Fires backup.ps1 in a detached background process so Claude does not wait for it.
$script = Join-Path $PSScriptRoot "backup.ps1"
Start-Process powershell -ArgumentList @(
    "-NonInteractive", "-WindowStyle", "Hidden",
    "-ExecutionPolicy", "Bypass", "-File", $script
) -WindowStyle Hidden
