# skreamb0t brand theme for WinForms. Paper & ink, 1px ink borders, hard offset
# block shadows, mono uppercase labels, one pixel-font accent, purple only in the
# wordmark. Dark skreamb0t brand palette.
# Dark token set.

Set-StrictMode -Version 2.0
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

function Test-SMFontInstalled { param([string] $Family)
    $fc = New-Object System.Drawing.Text.InstalledFontCollection
    foreach ($f in $fc.Families) { if ($f.Name -eq $Family) { return $true } }
    return $false
}
function New-SMFont { param([string[]] $Families, [single] $Size, [Drawing.FontStyle] $Style = [Drawing.FontStyle]::Regular)
    foreach ($fam in $Families) { if (Test-SMFontInstalled $fam) { return New-Object System.Drawing.Font($fam, $Size, $Style) } }
    return New-Object System.Drawing.Font('Segoe UI', $Size, $Style)
}

$paper     = [Drawing.Color]::FromArgb(0x18, 0x18, 0x16)
$panel     = [Drawing.Color]::FromArgb(0x1F, 0x1F, 0x1D)
$surface   = [Drawing.Color]::FromArgb(0x11, 0x11, 0x10)
$ink       = [Drawing.Color]::FromArgb(0xDC, 0xDA, 0xD5)
$highlight = [Drawing.Color]::FromArgb(0x2A, 0x2A, 0x27)
$inkDim    = [Drawing.Color]::FromArgb([int]($panel.R * 0.4 + $ink.R * 0.6), [int]($panel.G * 0.4 + $ink.G * 0.6), [int]($panel.B * 0.4 + $ink.B * 0.6))
$border    = [Drawing.Color]::FromArgb([int]($panel.R * 0.75 + $ink.R * 0.25), [int]($panel.G * 0.75 + $ink.G * 0.25), [int]($panel.B * 0.75 + $ink.B * 0.25))

$script:SMTheme = @{
    # ---- brand tokens ----
    Paper           = $paper
    Panel           = $panel
    Surface         = $surface
    Ink             = $ink
    Highlight       = $highlight
    Border          = $border
    Purple          = [Drawing.Color]::FromArgb(0xA8, 0x55, 0xF7)   # wordmark only
    PurpleDeep      = [Drawing.Color]::FromArgb(0x93, 0x33, 0xEA)
    PurpleLight     = [Drawing.Color]::FromArgb(0xF0, 0xAB, 0xFC)
    # ---- semantic aliases used by the UI ----
    Bg              = $paper
    Grid            = $surface
    GridAlt         = $paper
    Text            = $ink
    TextDim         = $inkDim
    Accent          = $ink        # primary action = inverted (bg ink / text paper)
    Pending         = [Drawing.Color]::FromArgb(255, 176,  32)   # amber = staged, distinct from every row hue
    # ---- functional accents (chips only) ----
    # row palette kept from v2.0 first cut (user preference): soft hues that tint well over dark paper
    RiskCritical    = [Drawing.Color]::FromArgb(255,  92,  92)   # red
    RiskSuspicious  = [Drawing.Color]::FromArgb(214, 112, 255)   # violet
    RiskBroken      = [Drawing.Color]::FromArgb(255, 122, 166)   # pink
    RiskCaution     = [Drawing.Color]::FromArgb(238, 226, 128)   # pale straw
    RiskOptional    = [Drawing.Color]::FromArgb(114, 200, 255)   # sky blue
    RiskUnknown     = [Drawing.Color]::FromArgb(168, 175, 188)   # neutral grey
    Ok              = [Drawing.Color]::FromArgb(0x22, 0xC5, 0x5E)
    Warn            = [Drawing.Color]::FromArgb(0xFB, 0xBF, 0x24)
    # ---- type ----
    Font            = (New-SMFont @('Inter','Segoe UI') 9.5)
    FontBold        = (New-SMFont @('Inter SemiBold','Inter','Segoe UI') 9.5 ([Drawing.FontStyle]::Bold))
    Mono            = (New-SMFont @('JetBrains Mono','Cascadia Mono','Consolas') 8.5)
    MonoBold        = (New-SMFont @('JetBrains Mono','Cascadia Mono','Consolas') 8.5 ([Drawing.FontStyle]::Bold))
    Label           = (New-SMFont @('JetBrains Mono','Cascadia Mono','Consolas') 7.5 ([Drawing.FontStyle]::Bold))   # tiny uppercase labels
    Title           = (New-SMFont @('Inter SemiBold','Inter','Segoe UI') 15 ([Drawing.FontStyle]::Bold))
    Pixel           = (New-SMFont @('Press Start 2P','Inter SemiBold','Segoe UI') 9)
}

function Initialize-SMNativeControls {
    if (-not ('StartupManager.NativeTheme' -as [type])) {
        Add-Type -Path (Join-Path $PSScriptRoot 'NativeControls.cs') -ReferencedAssemblies System.Windows.Forms, System.Drawing
    }
}

function Set-SMScrollTheme {
    param([Parameter(Mandatory)] [Windows.Forms.Control] $Control)
    if (-not $Control.IsHandleCreated -or $Control.IsDisposed) { return }
    $classes = if ($Control -is [Windows.Forms.ScrollBar] -or $Control -is [Windows.Forms.RichTextBox]) { 'ScrollBar' } else { $null }
    $result = [StartupManager.NativeTheme]::SetWindowTheme($Control.Handle, 'DarkMode_Explorer', $classes)
    if ($result -ne 0) { Write-SMLog -Level WARN -Message "Scrollbar theme failed for $($Control.GetType().Name): $result" }
}

function Enable-SMDarkScrollbars {
    param([Parameter(Mandatory)] [Windows.Forms.Control] $Control)
    Initialize-SMNativeControls
    $Control.Add_HandleCreated({ Set-SMScrollTheme -Control $this })
    $Control.Add_ControlAdded({
        param($sender, $eventArgs)
        Enable-SMDarkScrollbars -Control $eventArgs.Control
    })
    foreach ($child in $Control.Controls) { Enable-SMDarkScrollbars -Control $child }
    Set-SMScrollTheme -Control $Control
}

function Get-SMRiskColor {
    [CmdletBinding()]
    param([string] $Risk)
    switch ("$Risk") {
        'Critical'   { return $script:SMTheme.RiskCritical }
        'Suspicious' { return $script:SMTheme.RiskSuspicious }
        'Broken'     { return $script:SMTheme.RiskBroken }
        'Caution'    { return $script:SMTheme.RiskCaution }
        'Optional'   { return $script:SMTheme.RiskOptional }
        default      { return $script:SMTheme.RiskUnknown }
    }
}

function New-SMButton {
    <# Brand button: uppercase mono, 1px ink border, invert on hover, "press in" on click.
       The 2px block shadow is painted by the parent - call Add-SMBlockShadows on the container. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Text,
        [int]    $Width  = 110,
        [int]    $Height = 28,
        [switch] $Accent
    )
    $T = $script:SMTheme
    $b = New-Object Windows.Forms.Button
    $b.Text      = $Text.ToUpper()
    $b.AccessibleName = $Text
    $b.Size      = New-Object Drawing.Size($Width, $Height)
    $b.FlatStyle = [Windows.Forms.FlatStyle]::Flat
    $b.UseVisualStyleBackColor = $false
    $b.Font      = $T.MonoBold
    $b.Cursor    = [Windows.Forms.Cursors]::Hand
    $b.FlatAppearance.BorderSize = 1
    $b.FlatAppearance.BorderColor = $T.Ink
    $b.Tag = @{ Accent = [bool]$Accent; Shadow = $true }
    if ($Accent) { $b.BackColor = $T.Ink;   $b.ForeColor = $T.Paper }
    else         { $b.BackColor = $T.Panel; $b.ForeColor = $T.Ink }
    $b.FlatAppearance.MouseOverBackColor = $T.Ink
    $b.FlatAppearance.MouseDownBackColor = $T.Ink
    $b.Add_MouseEnter({ param($s, $e) if ($s.Enabled) { $s.ForeColor = $script:SMTheme.Paper } })
    $b.Add_MouseLeave({ param($s, $e) if (-not $s.Tag.Accent) { $s.ForeColor = $script:SMTheme.Ink } })
    $b.Add_MouseDown({ param($s, $e) $s.Location = New-Object Drawing.Point(($s.Left + 1), ($s.Top + 1)) })
    $b.Add_MouseUp({ param($s, $e) $s.Location = New-Object Drawing.Point(($s.Left - 1), ($s.Top - 1)); if ($s.Parent) { $s.Parent.Invalidate() } })
    $b.Add_EnabledChanged({ param($s, $e)
        if ($s.Enabled) { if ($s.Tag.Accent) { $s.BackColor = $script:SMTheme.Ink; $s.ForeColor = $script:SMTheme.Paper } else { $s.BackColor = $script:SMTheme.Panel; $s.ForeColor = $script:SMTheme.Ink } }
        else { $s.BackColor = $script:SMTheme.Panel; $s.ForeColor = $script:SMTheme.TextDim }
        if ($s.Parent) { $s.Parent.Invalidate() }
    })
    $b.Add_Paint({
        param($sender, $event)
        if (-not $sender.Enabled) {
            $brush = New-Object Drawing.SolidBrush($script:SMTheme.Panel)
            try { $event.Graphics.FillRectangle($brush, 2, 2, ($sender.Width - 4), ($sender.Height - 4)) } finally { $brush.Dispose() }
            [Windows.Forms.TextRenderer]::DrawText($event.Graphics, $sender.Text, $sender.Font, $sender.ClientRectangle, $script:SMTheme.TextDim, ([Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [Windows.Forms.TextFormatFlags]::VerticalCenter))
        }
    })
    return $b
}

function Add-SMBlockShadows {
    <# Paints the signature 2px hard ink shadow behind every shadow-tagged Button in a container. #>
    param([Parameter(Mandatory)] $Container)
    $Container.Add_Paint({
        param($s, $e)
        $brush = New-Object Drawing.SolidBrush($script:SMTheme.Ink)
        $dim   = New-Object Drawing.SolidBrush($script:SMTheme.Border)
        foreach ($c in $s.Controls) {
            if ($c -is [Windows.Forms.Button] -and $c.Tag -is [hashtable] -and $c.Tag.Shadow -and $c.Visible) {
                $b = if ($c.Enabled) { $brush } else { $dim }
                $e.Graphics.FillRectangle($b, ($c.Left + 2), ($c.Top + 2), $c.Width, $c.Height)
            }
        }
        $brush.Dispose(); $dim.Dispose()
    })
}

function New-SMLabel {
    [CmdletBinding()]
    param([string] $Text = '', [switch] $Bold, [switch] $Dim, [switch] $Mono, [int] $WrapWidth = 0, $Color = $null)
    $l = New-Object Windows.Forms.Label
    $l.Text      = $Text
    $l.AutoSize  = $true
    $l.BackColor = [Drawing.Color]::Transparent
    $l.Font      = if ($Mono) { if ($Bold) { $script:SMTheme.MonoBold } else { $script:SMTheme.Mono } } elseif ($Bold) { $script:SMTheme.FontBold } else { $script:SMTheme.Font }
    if ($null -ne $Color)  { $l.ForeColor = $Color }
    elseif ($Dim)          { $l.ForeColor = $script:SMTheme.TextDim }
    else                   { $l.ForeColor = $script:SMTheme.Text }
    if ($WrapWidth -gt 0) { $l.MaximumSize = New-Object Drawing.Size($WrapWidth, 0) }
    return $l
}

function New-SMTextBox {
    [CmdletBinding()]
    param([int] $Width = 240, [int] $Height = 0, [string] $Text = '', [switch] $Multiline, [switch] $ReadOnly, [switch] $Monospace)
    $t = New-Object Windows.Forms.TextBox
    $t.Text        = $Text
    $t.BackColor   = $script:SMTheme.Surface
    $t.ForeColor   = $script:SMTheme.Ink
    $t.BorderStyle = [Windows.Forms.BorderStyle]::FixedSingle
    $t.Font        = if ($Monospace) { $script:SMTheme.Mono } else { $script:SMTheme.Font }
    if ($Multiline) { $t.Multiline = $true; $t.ScrollBars = [Windows.Forms.ScrollBars]::Vertical; $t.WordWrap = $true }
    if ($ReadOnly) { $t.ReadOnly = $true }
    if ($Height -gt 0) { $t.Size = New-Object Drawing.Size($Width, $Height) } else { $t.Width = $Width }
    Enable-SMDarkScrollbars -Control $t
    return $t
}

function New-SMComboBox {
    [CmdletBinding()]
    param([object[]] $Items = @(), [int] $Width = 180)
    $c = New-Object Windows.Forms.ComboBox
    $c.DropDownStyle = [Windows.Forms.ComboBoxStyle]::DropDownList
    $c.FlatStyle     = [Windows.Forms.FlatStyle]::Flat
    $c.BackColor     = $script:SMTheme.Surface
    $c.ForeColor     = $script:SMTheme.Ink
    $c.Font          = $script:SMTheme.MonoBold
    $c.Width         = $Width
    foreach ($i in $Items) { [void]$c.Items.Add(([string]$i).ToUpper()) }
    if ($c.Items.Count -gt 0) { $c.SelectedIndex = 0 }
    Enable-SMDarkScrollbars -Control $c
    return $c
}

function New-SMWordmark {
    <# "STARTUP." (Inter bold) + "MANAGER" (pixel font, purple hard shadow) + "by skreamb0t" with the animated 0. #>
    [CmdletBinding()]
    param([string] $Product = 'STARTUP.', [string] $Suffix = 'MANAGER', [string] $Tagline = '', [string] $ImagePath = '')
    $T = $script:SMTheme
    $p = New-Object Windows.Forms.Panel
    $p.Height = 64; $p.Dock = 'Top'; $p.BackColor = $T.Panel
    $img = $null
    if ($ImagePath -and (Test-Path -LiteralPath $ImagePath)) { try { $img = [Drawing.Image]::FromFile($ImagePath) } catch { $img = $null } }
    $p.Tag = @{ Product = $Product; Suffix = $Suffix; Tagline = $Tagline; Phase = 0.0; Image = $img; AnimationBounds = [Drawing.Rectangle]::Empty }
    $timer = New-Object Windows.Forms.Timer; $timer.Interval = 40; $timer.Tag = $p
    $p.Tag.Timer = $timer
    $p.Add_Disposed({ $this.Tag.Timer.Stop(); $this.Tag.Timer.Dispose(); if ($null -ne $this.Tag.Image) { $this.Tag.Image.Dispose() } })
    $timer.Add_Tick({ param($s, $e) $pnl = $s.Tag; $pnl.Tag.Phase = ($pnl.Tag.Phase + 0.02) % 1.0; $pnl.Invalidate($pnl.Tag.AnimationBounds) })
    $p.Add_SizeChanged({ $this.Invalidate() })
    $timer.Start()
    $p.Add_Paint({
        param($s, $e)
        $T = $script:SMTheme; $g = $e.Graphics
        $g.TextRenderingHint = [Drawing.Text.TextRenderingHint]::ClearTypeGridFit
        # bottom border 1px ink
        $g.FillRectangle((New-Object Drawing.SolidBrush($T.Ink)), 0, $s.Height - 1, $s.Width, 1)
        $x = 14; $y = 12
        if ($null -ne $s.Tag.Image) {
            $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $sz = $s.Height - 14
            $g.DrawImage($s.Tag.Image, (New-Object Drawing.Rectangle($x, 6, $sz, $sz)))
            $x += $sz + 12
        }
        $ff = [Windows.Forms.TextFormatFlags]::NoPadding -bor [Windows.Forms.TextFormatFlags]::PreserveGraphicsClipping
        $sz1 = [Windows.Forms.TextRenderer]::MeasureText($g, $s.Tag.Product, $T.Title, (New-Object Drawing.Size(1000, 100)), $ff)
        [Windows.Forms.TextRenderer]::DrawText($g, $s.Tag.Product, $T.Title, (New-Object Drawing.Point($x, $y)), $T.Ink, $ff)
        $x2 = $x + $sz1.Width + 4; $y2 = $y + $sz1.Height - 16
        [Windows.Forms.TextRenderer]::DrawText($g, $s.Tag.Suffix, $T.Pixel, (New-Object Drawing.Point(($x2 + 1), ($y2 + 1))), $T.Purple, $ff)
        [Windows.Forms.TextRenderer]::DrawText($g, $s.Tag.Suffix, $T.Pixel, (New-Object Drawing.Point($x2, $y2)), $T.Ink, $ff)
        # byline
        $by = 'by skreamb'; $yb = $y + $sz1.Height + 2
        $szb = [Windows.Forms.TextRenderer]::MeasureText($g, $by, $T.Label, (New-Object Drawing.Size(1000, 100)), $ff)
        [Windows.Forms.TextRenderer]::DrawText($g, $by, $T.Label, (New-Object Drawing.Point($x, $yb)), $T.TextDim, $ff)
        # animated 0: ping-pong between purple-deep and purple-light
        $ph = [double]$s.Tag.Phase; $tt = if ($ph -lt 0.5) { $ph * 2 } else { (1 - $ph) * 2 }
        $c0 = [Drawing.Color]::FromArgb([int](0x93 + (0xF0 - 0x93) * $tt), [int](0x33 + (0xAB - 0x33) * $tt), [int](0xEA + (0xFC - 0xEA) * $tt))
        $sz0 = [Windows.Forms.TextRenderer]::MeasureText($g, '0', $T.Label, (New-Object Drawing.Size(100, 100)), $ff)
        $s.Tag.AnimationBounds = New-Object Drawing.Rectangle(($x + $szb.Width - 2), ($yb - 2), ($sz0.Width + 4), ($sz0.Height + 4))
        [Windows.Forms.TextRenderer]::DrawText($g, '0', $T.Label, (New-Object Drawing.Point(($x + $szb.Width), $yb)), $c0, $ff)
        [Windows.Forms.TextRenderer]::DrawText($g, 't', $T.Label, (New-Object Drawing.Point(($x + $szb.Width + $sz0.Width), $yb)), $T.TextDim, $ff)
        if ($s.Tag.Tagline) {
            $tl = $s.Tag.Tagline.ToUpper()
            $szt = [Windows.Forms.TextRenderer]::MeasureText($g, $tl, $T.Label, (New-Object Drawing.Size(2000, 100)), $ff)
            [Windows.Forms.TextRenderer]::DrawText($g, $tl, $T.Label, (New-Object Drawing.Point(($s.Width - $szt.Width - 16), [int](($s.Height - $szt.Height) / 2))), $T.TextDim, $ff)
        }
    })
    return $p
}
