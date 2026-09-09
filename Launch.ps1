# Launches Startup Manager from this folder.
# Prefers the exe (one UAC prompt, proper icon); falls back to the script.
$here = $PSScriptRoot
$exe  = Join-Path $here 'StartupManager.exe'
if (Test-Path $exe) {
    Start-Process -FilePath $exe -WorkingDirectory $here
} else {
    Start-Process -FilePath 'powershell.exe' -WorkingDirectory $here -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
        '-File', ('"' + (Join-Path $here 'Start-StartupManager.ps1') + '"')
    )
}
