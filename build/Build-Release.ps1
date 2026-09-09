#requires -Version 5.1
[CmdletBinding()]
param([string] $OutputDirectory = (Join-Path $env:TEMP ('StartupManager-release-' + [guid]::NewGuid().ToString('N'))))

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$manifest = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'Release-Files.psd1')
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $output) { throw "Output directory already exists; choose a new directory: $output" }
$stage = Join-Path $output 'staging\Windows-Startup-App-Manager'
foreach ($relative in $manifest.Files) {
    if ($relative -match '(^[/\\]|:|\.\.|\*)') { throw "Unsafe release path: $relative" }
    $source = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Required release file missing: $relative" }
    if ((Get-Item -LiteralPath $source).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Release file cannot be a link: $relative" }
}
New-Item -ItemType Directory -Path $stage -Force | Out-Null
foreach ($relative in $manifest.Files) {
    $target = Join-Path $stage $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $root $relative) -Destination $target
}
& (Join-Path $stage 'build\Build-Exe.ps1') -OutFile (Join-Path $stage 'StartupManager.exe')
$archive = Join-Path $output ('Windows-Startup-App-Manager-' + $manifest.Version + '.zip')
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory((Split-Path -Parent $stage), $archive, [IO.Compression.CompressionLevel]::Optimal, $false)
$setup = Join-Path $output ('Windows-Startup-App-Manager-Setup-' + $manifest.Version + '.exe')
& (Join-Path $stage 'build\Build-Setup.ps1') -PayloadZip $archive -OutFile $setup
$checksum = @($archive, $setup | ForEach-Object { (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + (Split-Path -Leaf $_) })
Set-Content -LiteralPath (Join-Path $output 'SHA256SUMS.txt') -Value $checksum -Encoding ASCII
Write-Host "Release ZIP: $archive"
Write-Host "Setup EXE: $setup"
Write-Host "SHA256: $checksum"
Write-Host "Staging files preserved: $stage"
