#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $PayloadZip,
    [Parameter(Mandatory)] [string] $OutFile
)

$ErrorActionPreference = 'Stop'
$payload = (Resolve-Path -LiteralPath $PayloadZip -ErrorAction Stop).Path
$target = [IO.Path]::GetFullPath($OutFile)
if (Test-Path -LiteralPath $target) { throw "Setup output already exists: $target" }
if (-not (Test-Path -LiteralPath (Split-Path -Parent $target) -PathType Container)) { throw 'The setup output parent directory must already exist.' }
$compiler = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw 'The 64-bit .NET Framework C# compiler is required.' }
$arguments = @(
    '/nologo', '/target:winexe', '/platform:x64', '/optimize+',
    ('/out:' + $target), ('/resource:' + $payload + ',StartupManager.Payload.zip'),
    ('/win32manifest:' + (Join-Path $PSScriptRoot 'Setup.manifest')),
    ('/win32icon:' + (Join-Path $PSScriptRoot 'app.ico')),
    '/r:System.dll', '/r:System.Core.dll', '/r:System.Windows.Forms.dll', '/r:System.Drawing.dll',
    '/r:System.IO.Compression.dll', '/r:System.IO.Compression.FileSystem.dll',
    (Join-Path $PSScriptRoot 'Installer.cs')
)
& $compiler @arguments
if ($LASTEXITCODE -ne 0) { throw "Setup compilation failed with exit code $LASTEXITCODE" }
if (-not (Test-Path -LiteralPath $target -PathType Leaf) -or (Get-Item -LiteralPath $target).Length -eq 0) { throw 'Compiler returned success without producing a setup executable.' }
Write-Host "Built self-contained setup: $target"
