# Generates build\app.ico from the skreamb0t mascot (assets\skreambot.png).
# Multi-size (16/24/32/48/64/128/256), PNG-compressed frames, transparent background.
param(
    [string] $Source  = (Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\skreambot.png'),
    [string] $OutFile = (Join-Path $PSScriptRoot 'app.ico')
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
if (-not (Test-Path $Source)) { throw "mascot not found: $Source" }
$src = [Drawing.Image]::FromFile($Source)

$frames = @()
foreach ($size in @(16, 24, 32, 48, 64, 128, 256)) {
    [int]$sz = $size
    $bmp = New-Object Drawing.Bitmap($sz, $sz, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.Clear([Drawing.Color]::Transparent)
    [int]$m = [Math]::Floor($sz / 50)
    $rect = New-Object Drawing.Rectangle($m, $m, ($sz - 2 * $m), ($sz - 2 * $m))
    $g.DrawImage($src, $rect)
    $g.Dispose()
    $ms = New-Object IO.MemoryStream
    $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $frames += @{ Size = $sz; Bytes = $ms.ToArray() }
}
$src.Dispose()
$fs = [IO.File]::Create($OutFile); $bw = New-Object IO.BinaryWriter($fs)
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$frames.Count)
$offset = 6 + 16 * $frames.Count
foreach ($f in $frames) {
    $s = if ($f.Size -ge 256) { 0 } else { $f.Size }
    $bw.Write([byte]$s); $bw.Write([byte]$s); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32); $bw.Write([uint32]$f.Bytes.Length); $bw.Write([uint32]$offset)
    $offset += $f.Bytes.Length
}
foreach ($f in $frames) { $bw.Write($f.Bytes) }
$bw.Dispose(); $fs.Dispose()
Write-Host "icon: $OutFile ($((Get-Item $OutFile).Length) bytes) from $Source"
