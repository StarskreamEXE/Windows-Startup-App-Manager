# Builds StartupManager.exe (native launcher stub) with the C# compiler that
# ships with every Windows install. No SDK, no NuGet, no internet.
#
#   powershell -ExecutionPolicy Bypass -File build\Build-Exe.ps1
#
param([string] $OutFile = (Join-Path (Split-Path -Parent $PSScriptRoot) 'StartupManager.exe'))

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

$csc = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:SystemRoot 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path $csc)) { throw "csc.exe not found. .NET Framework 4.x is required (it ships with Windows)." }

# icon: pull a stock icon out of shell32 so the exe is not a blank box
$ico = Join-Path $here 'app.ico'
if (-not (Test-Path $ico)) {
    Add-Type -AssemblyName System.Drawing
    $src = Join-Path $env:SystemRoot 'System32\taskmgr.exe'
    $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($src)
    $fs = [IO.File]::Create($ico)
    try { $icon.Save($fs) } finally { $fs.Dispose() }
}

$args = @(
    '/nologo', '/target:winexe', '/optimize+',
    "/out:$OutFile",
    "/win32manifest:$(Join-Path $here 'app.manifest')",
    "/win32icon:$ico",
    '/r:System.dll', '/r:System.Windows.Forms.dll',
    (Join-Path $here 'Launcher.cs')
)
Write-Host "csc -> $OutFile"
& $csc @args
if ($LASTEXITCODE -ne 0) { throw "csc.exe failed with exit code $LASTEXITCODE" }
Write-Host "Built: $OutFile ($([math]::Round((Get-Item $OutFile).Length / 1KB)) KB)"
