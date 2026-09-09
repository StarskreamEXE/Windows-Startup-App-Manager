# Installs Startup Manager for the current user.
#
#   Install.bat                  (double-click)
#   powershell -ExecutionPolicy Bypass -File Install.ps1 [-Dest <folder>] [-NoShortcuts] [-Launch]
#
# What it does:
#   1. Rebuilds StartupManager.exe on every install and upgrade using Windows csc.exe.
#   2. Copies the app to  %LOCALAPPDATA%\Programs\StartupManager  (no admin needed to install;
#      the app itself asks for admin when it runs).
#   3. Creates Desktop and Start Menu shortcuts.
#   4. Registers in Settings > Apps > Installed apps so it can be uninstalled normally.
# Nothing is deleted. Re-running upgrades in place.

[CmdletBinding()]
param(
    [string] $Dest = (Join-Path $env:LOCALAPPDATA 'Programs\StartupManager'),
    [switch] $NoShortcuts,
    [switch] $Portable,
    [switch] $Launch
)

$ErrorActionPreference = 'Stop'
$Source  = $PSScriptRoot
$manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $Source 'build\Release-Files.psd1')
$Version = $manifest.Version
$Dest = [IO.Path]::GetFullPath($Dest)
if ($Dest.TrimEnd('\') -eq $Source.TrimEnd('\')) { throw 'Install destination must differ from the source directory.' }

function Step($m) { Write-Host ("  " + $m) -ForegroundColor Cyan }

Write-Host ''
Write-Host 'Startup Manager installer' -ForegroundColor Green
Write-Host ("  from: " + $Source)
Write-Host ("  to:   " + $Dest)
Write-Host ''

# 1. exe
foreach ($relative in $manifest.Files) {
    if ($relative -match '(^[/\\]|:|\.\.|\*)') { throw "Unsafe installation path: $relative" }
    if (-not (Test-Path -LiteralPath (Join-Path $Source $relative) -PathType Leaf)) { throw "Required installation file missing: $relative" }
}

# 1b. brand fonts (per-user, no admin) - Inter / JetBrains Mono / Press Start 2P
$fontSrc = Join-Path $Source 'fonts'
if (-not $Portable -and (Test-Path -LiteralPath $fontSrc)) {
    Step 'Installing fonts (per-user) ...'
    Add-Type -AssemblyName System.Drawing
    $fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    if (-not (Test-Path -LiteralPath $fontDir)) { New-Item -ItemType Directory -Path $fontDir -Force | Out-Null }
    $freg = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    if (-not (Test-Path $freg)) { New-Item -Path $freg -Force | Out-Null }
    $installed = (New-Object System.Drawing.Text.InstalledFontCollection).Families | ForEach-Object { $_.Name }
    foreach ($f in (Get-ChildItem -LiteralPath $fontSrc -Filter *.ttf)) {
        try {
            $pfc = New-Object System.Drawing.Text.PrivateFontCollection; $pfc.AddFontFile($f.FullName)
            $fam = $pfc.Families[0].Name
            $fontDest = Join-Path $fontDir $f.Name
            if ((Test-Path -LiteralPath $fontDest) -or ($installed -contains $fam -and $f.BaseName -match 'Regular$')) { continue }
            Copy-Item -LiteralPath $f.FullName -Destination $fontDest -Force
            $style = switch -Regex ($f.BaseName) { 'BoldItalic$' {' Bold Italic'} 'Bold$' {' Bold'} 'Italic$' {' Italic'} default {''} }
            New-ItemProperty -Path $freg -Name ("$fam$style (TrueType)") -Value $fontDest -PropertyType String -Force | Out-Null
            Write-Host ("    " + $fam + $style)
        } catch { Write-Warning ("Font installation failed for " + $f.Name + ": " + $_.Exception.Message) }
        finally { if ($pfc) { $pfc.Dispose(); $pfc = $null } }
    }
}

# 2. copy
Step 'Copying files ...'
if (-not (Test-Path -LiteralPath $Dest)) { New-Item -ItemType Directory -Path $Dest -Force | Out-Null }
$items = $manifest.Files
foreach ($i in $items) {
    $from = Join-Path $Source $i
    $to = Join-Path $Dest $i
    if (Test-Path -LiteralPath $from -PathType Container) {
        # overwrite in place (never delete): copy every file, create folders as needed
        Get-ChildItem -LiteralPath $from -Recurse -File | ForEach-Object {
            $rel    = $_.FullName.Substring($from.Length).TrimStart('\')
            $target = Join-Path $to $rel
            $dir    = Split-Path -Parent $target
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            Copy-Item -LiteralPath $_.FullName -Destination $target -Force
        }
    } else {
        $targetDir = Split-Path -Parent $to
        if (-not (Test-Path -LiteralPath $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
        Copy-Item -LiteralPath $from -Destination $to -Force
    }
}
Step 'Rebuilding StartupManager.exe ...'
& (Join-Path $Dest 'build\Build-Exe.ps1') -OutFile (Join-Path $Dest 'StartupManager.exe')
foreach ($d in @('logs', 'backups', 'reports', 'exports')) {
    $p = Join-Path $Dest $d
    if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}

# 3. shortcuts
$exeInstalled = Join-Path $Dest 'StartupManager.exe'
if (-not $NoShortcuts -and -not $Portable) {
    Step 'Creating shortcuts ...'
    $wsh = New-Object -ComObject WScript.Shell
    foreach ($lnk in @(
        (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Startup Manager.lnk'),
        (Join-Path ([Environment]::GetFolderPath('Programs')) 'Startup Manager.lnk')
    )) {
        $s = $wsh.CreateShortcut($lnk)
        $s.TargetPath = $exeInstalled
        $s.WorkingDirectory = $Dest
        $s.IconLocation = $exeInstalled + ',0'
        $s.Description = 'See and control everything that starts with Windows'
        $s.Save()
        Write-Host ("    " + $lnk)
    }
}

# 4. Add/Remove Programs (per-user, no admin)
if (-not $Portable) {
Step 'Registering in Installed apps ...'
$reg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\StartupManager'
if (-not (Test-Path $reg)) { New-Item -Path $reg -Force | Out-Null }
$uninst = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $Dest 'Uninstall.ps1') + '"'
Set-ItemProperty $reg 'DisplayName'     'Windows Startup App Manager'
Set-ItemProperty $reg 'DisplayVersion'  $Version
Set-ItemProperty $reg 'Publisher'       'skreamb0t'
Set-ItemProperty $reg 'InstallLocation' $Dest
Set-ItemProperty $reg 'DisplayIcon'     $exeInstalled
Set-ItemProperty $reg 'UninstallString' $uninst
Set-ItemProperty $reg 'NoModify' 1 -Type DWord
Set-ItemProperty $reg 'NoRepair' 1 -Type DWord
Set-ItemProperty $reg 'InstallDate' (Get-Date -Format 'yyyyMMdd')
}

Write-Host ''
Write-Host 'Installed.' -ForegroundColor Green
Write-Host ("  Run:       " + $exeInstalled)
if ($Portable) { Write-Host '  Portable: no fonts, shortcuts, or Installed-apps registration changed.' }
else { Write-Host '  Uninstall: Settings > Apps > Installed apps > Windows Startup App Manager, or run Uninstall.ps1' }
Write-Host ''

if ($Launch) { Start-Process -FilePath $exeInstalled -WorkingDirectory $Dest }
