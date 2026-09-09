param([string] $OutputDirectory = (Join-Path $env:TEMP 'StartupManager-layout-check'))

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$root = Split-Path -Parent $PSScriptRoot
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -Path (Join-Path $root 'src\UI\NativeControls.cs') -ReferencedAssemblies System.Windows.Forms, System.Drawing
[StartupManager.NativeTheme]::EnableDpiAwareness()
Add-Type -Namespace SMLayoutCapture -Name Native -MemberDefinition '[DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr window, IntPtr context, uint flags);'
[Windows.Forms.Application]::EnableVisualStyles()
$entrySource = Get-Content (Join-Path $root 'Start-StartupManager.ps1') -Raw
$loadBlock = [regex]::Match($entrySource, '(?s)\$LoadOrder = @\((.*?)\)').Groups[1].Value
foreach ($match in [regex]::Matches($loadBlock, "'([^']+)'")) { . (Join-Path $root $match.Groups[1].Value) }
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
Initialize-SMPaths -Root $OutputDirectory | Out-Null
$script:SM.Root = $root
Set-Content (Join-Path $script:SM.LogDir '.legend-shown') 'layout test'

function Get-SMInventory {
    param([scriptblock] $Progress)
    $script:SM.Inventory = @(foreach ($number in 1..60) {
        $entry = New-SMEntry -Name "Layout entry $number" -Category 'Registry Run (User)' -Kind RunKey -Enabled $true
        $entry.Id = $number
        $entry.What = 'A long description that stays available in the details pane at every window size.'
        $entry.Command = 'C:\Applications\A long application folder\startup.exe --background --long-argument-for-layout-validation'
        $entry.ExePath = 'C:\Applications\A long application folder\startup.exe'
        $entry.Explain = $entry.What
        $entry.DisableEffect = 'Does not start automatically.'
        $entry
    })
    return ,$script:SM.Inventory
}

function Invoke-SMMainScan {
    [void](Get-SMInventory)
    $script:SMUI.ById = @{}
    foreach ($entry in $script:SM.Inventory) { $script:SMUI.ById[$entry.Id] = $entry }
    Update-SMMainGrid
}

function Get-SMEntryStateSnapshot {
    param($Entry)
    return [pscustomobject]@{ Enabled = $Entry.Enabled; Configuration = $Entry.Command }
}

$script:smokeError = $null
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 500
$timer.Add_Tick({
    $this.Stop()
    try {
        $ui = $script:SMUI
        Set-SMMainReducedMotion -Enabled $true
        if ($ui.Brand.Tag.Timer.Enabled) { throw 'Reduced motion did not stop animation' }
        Set-SMMainReducedMotion -Enabled $false
        if (-not $ui.Brand.Tag.Timer.Enabled) { throw 'Animation did not resume' }
        $entry = $script:SM.Inventory[0]
        Add-SMPendingChange -Entry $entry -Enable $false
        Update-SMMainGrid
        foreach ($size in @(@(800,600), @(1100,720), @(1560,920), @(2000,1000))) {
            $ui.Form.Size = New-Object Drawing.Size($size[0], $size[1])
            foreach ($zoom in @(0.75, 1.0, 1.5)) {
                Set-SMMainZoom -Zoom $zoom
                Update-SMMainLayout
                [Windows.Forms.Application]::DoEvents()
                $visibleWidth = ($ui.Grid.Columns | Where-Object Visible | Measure-Object Width -Sum).Sum
                if ($visibleWidth -gt $ui.Grid.ClientSize.Width) { throw "Grid overflows at $size / $zoom" }
                if ($ui.Grid.HorizontalScrollingOffset -ne 0) { throw 'Grid scrolled sideways' }
                if ($ui.Zoom -ne $zoom) { throw 'Zoom did not update' }
                foreach ($record in $ui.ToolbarSizes) {
                    if ($record.Control.Right -gt $record.Control.Parent.ClientSize.Width) { throw "Toolbar clipped: $($record.Control.Text) at $size / $zoom" }
                }
                if ((Get-SMPendingChanges).Count -ne 1) { throw 'Layout lost the staged change' }
            }
            $ui.ZoomReset.PerformClick()
            if ($ui.Zoom -ne 1.0) { throw 'Reset did not restore 100 percent' }
            $bitmap = New-Object Drawing.Bitmap($ui.Form.Width, $ui.Form.Height)
            $graphics = [Drawing.Graphics]::FromImage($bitmap)
            $context = $graphics.GetHdc()
            [void][SMLayoutCapture.Native]::PrintWindow($ui.Form.Handle, $context, 2)
            $graphics.ReleaseHdc($context); $graphics.Dispose()
            $bitmap.Save((Join-Path $OutputDirectory ("layout-$($size[0]).png")))
            $bitmap.Dispose()
        }
        Set-SMMainZoom -Zoom 3.0
        if ($ui.Zoom -ne 1.5) { throw 'Upper zoom limit failed' }
        Set-SMMainZoom -Zoom 0.1
        if ($ui.Zoom -ne 0.75) { throw 'Lower zoom limit failed' }
        $ui.ZoomReset.PerformClick()
        Write-Host 'PASS: 12 size/zoom combinations, zoom limits, reset, toolbar bounds, grid bounds, and staged-change preservation.'
    } catch { $script:smokeError = $_ }
    finally { Clear-SMPendingChanges; $script:SMUI.Form.Close() }
})
$timer.Start()
try { Show-SMMainForm }
finally { $timer.Dispose() }
if ($script:smokeError) { throw $script:smokeError }
