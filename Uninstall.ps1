# Uninstalls Startup Manager for the current user.
# Removes shortcuts and the Installed-apps entry. The install folder is NOT
# deleted - it is renamed to  StartupManager.uninstalled-<timestamp>  so your
# logs, backups and reports survive. Delete that folder yourself if you want.

[CmdletBinding()]
param([switch] $Quiet, [switch] $Portable)
$ErrorActionPreference = 'Stop'
$here = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
$reg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\StartupManager'
if (-not $Portable) {
    $registered = Get-ItemProperty -LiteralPath $reg -Name InstallLocation -ErrorAction Stop
    if ([IO.Path]::GetFullPath($registered.InstallLocation).TrimEnd('\') -ne $here) {
        throw 'This is not the registered install location. Run the installed uninstaller, or use -Portable for an isolated copy.'
    }
}
$parent = Split-Path -Parent $here
if (-not $parent -or $here -eq [IO.Path]::GetPathRoot($here).TrimEnd('\')) { throw 'Refusing to rename a filesystem root.' }
$newName = (Split-Path -Leaf $here) + '.uninstalled-' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff')
$preserved = [IO.Path]::GetFullPath((Join-Path $parent $newName))
if ((Split-Path -Parent $preserved) -ne $parent -or $preserved -eq $here) { throw 'Invalid preservation path.' }
if (Test-Path -LiteralPath $preserved) { throw "Preservation path already exists: $preserved" }

if (-not $Quiet) {
    Add-Type -AssemblyName System.Windows.Forms
    $a = [System.Windows.Forms.MessageBox]::Show(
        "Remove Startup Manager shortcuts and its Installed-apps entry?`n`nYour logs, backups and reports are kept (folder is renamed, not deleted).",
        'Uninstall Startup Manager', 'YesNo', 'Question')
    if ($a -ne 'Yes') { exit 0 }
}

$shortcuts = @()
if (-not $Portable) {
    $shell = New-Object -ComObject WScript.Shell
    foreach ($shortcut in @(
    (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Startup Manager.lnk'),
    (Join-Path ([Environment]::GetFolderPath('Programs')) 'Startup Manager.lnk')
    )) {
        if ((Test-Path -LiteralPath $shortcut) -and $shell.CreateShortcut($shortcut).TargetPath -eq (Join-Path $here 'StartupManager.exe')) {
            $shortcuts += $shortcut
        }
    }
}
$previousLocation = Get-Location
try {
    Set-Location -LiteralPath $parent
    Move-Item -LiteralPath $here -Destination $preserved -ErrorAction Stop
} finally {
    if (Test-Path -LiteralPath $previousLocation.Path) { Set-Location -LiteralPath $previousLocation.Path }
}
foreach ($shortcut in $shortcuts) {
    $label = if ((Split-Path -Parent $shortcut) -eq [Environment]::GetFolderPath('Desktop')) { 'Desktop' } else { 'StartMenu' }
    Move-Item -LiteralPath $shortcut -Destination (Join-Path $preserved ($label + '-Startup Manager.lnk')) -ErrorAction Stop
}
if (-not $Portable) { Remove-Item -LiteralPath $reg -Recurse -Force -ErrorAction Stop }
Write-Host "Uninstalled. Files preserved at: $preserved"

if (-not $Quiet) {
    [System.Windows.Forms.MessageBox]::Show(
        "Startup Manager was uninstalled.`n`nYour files were kept at:`n" + $preserved,
        'Uninstall Startup Manager', 'OK', 'Information') | Out-Null
}
