Set-StrictMode -Version 2.0
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src\UI\Theme.ps1')

Describe 'Wordmark animation repaint region' {
    It 'repaints the animated zero after DPI and zoom change its position' {
        $originalTitle = $script:SMTheme.Title
        $originalLabel = $script:SMTheme.Label
        try {
            foreach ($scale in @(1.0, 1.75, 2.625)) {
                $script:SMTheme.Title = New-Object Drawing.Font($originalTitle.FontFamily, ([single]($originalTitle.Size * $scale)), $originalTitle.Style)
                $script:SMTheme.Label = New-Object Drawing.Font($originalLabel.FontFamily, ([single]($originalLabel.Size * $scale)), $originalLabel.Style)
                $panel = New-SMWordmark
                $panel.Tag.Timer.Stop()
                $panel.Size = New-Object Drawing.Size(1200, ([int](64 * $scale)))
                $bitmap = New-Object Drawing.Bitmap($panel.Width, $panel.Height)
                try {
                    $panel.DrawToBitmap($bitmap, $panel.ClientRectangle)
                    $graphics = [Drawing.Graphics]::FromImage($bitmap)
                    try {
                        $flags = [Windows.Forms.TextFormatFlags]::NoPadding
                        $titleSize = [Windows.Forms.TextRenderer]::MeasureText($graphics, 'STARTUP.', $script:SMTheme.Title, (New-Object Drawing.Size(1000,100)), $flags)
                        $prefixSize = [Windows.Forms.TextRenderer]::MeasureText($graphics, 'by skreamb', $script:SMTheme.Label, (New-Object Drawing.Size(1000,100)), $flags)
                        $zeroSize = [Windows.Forms.TextRenderer]::MeasureText($graphics, '0', $script:SMTheme.Label, (New-Object Drawing.Size(100,100)), $flags)
                        $zeroBounds = New-Object Drawing.Rectangle((14 + $prefixSize.Width), (14 + $titleSize.Height), $zeroSize.Width, $zeroSize.Height)
                    } finally { $graphics.Dispose() }
                    $script:invalidatedBounds = [Drawing.Rectangle]::Empty
                    $panel.Add_Invalidated({ param($sender, $eventArgs) $script:invalidatedBounds = $eventArgs.InvalidRect })
                    $tick = $panel.Tag.Timer.GetType().GetMethod('OnTick', [Reflection.BindingFlags]'Instance,NonPublic')
                    [void]$tick.Invoke($panel.Tag.Timer, @([EventArgs]::Empty))
                    $script:invalidatedBounds.Contains($zeroBounds) | Should Be $true
                } finally {
                    $bitmap.Dispose(); $panel.Dispose()
                    $script:SMTheme.Title.Dispose(); $script:SMTheme.Label.Dispose()
                }
            }
        } finally {
            $script:SMTheme.Title = $originalTitle
            $script:SMTheme.Label = $originalLabel
        }
    }
}
