# Modal dialogs: Legend/Help, History & log viewer, Apply confirmation, Details, About.

Set-StrictMode -Version 2.0

function New-SMDialogForm {
    param([string] $Title, [int] $Width = 760, [int] $Height = 560)
    $f = New-Object Windows.Forms.Form
    $f.Text = $Title
    $f.Size = New-Object Drawing.Size($Width, $Height)
    $f.MinimumSize = New-Object Drawing.Size(480, 320)
    $f.StartPosition = 'CenterParent'
    $f.BackColor = $script:SMTheme.Bg
    $f.ForeColor = $script:SMTheme.Text
    $f.Font = $script:SMTheme.Font
    $f.KeyPreview = $true
    $f.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Escape') { $s.Close() } })
    return $f
}

function New-SMRichText {
    $r = New-Object Windows.Forms.RichTextBox
    $r.ReadOnly = $true
    $r.BackColor = $script:SMTheme.Grid
    $r.ForeColor = $script:SMTheme.Text
    $r.BorderStyle = 'None'
    $r.Font = $script:SMTheme.Font
    $r.DetectUrls = $false
    $r.WordWrap = $true; $r.ScrollBars = 'Vertical'
    Enable-SMDarkScrollbars -Control $r
    return $r
}

function Add-SMRichHeading { param($Box, [string] $Text)
    $Box.SelectionFont = $script:SMTheme.MonoBold
    $Box.SelectionColor = $script:SMTheme.Ink
    $Box.AppendText($Text.ToUpper() + "`r`n")
    $Box.SelectionFont = $script:SMTheme.Font
    $Box.SelectionColor = $script:SMTheme.Text
}
function Add-SMRichLine { param($Box, [string] $Label, [string] $Value, $Color = $null)
    if ($Label) {
        $Box.SelectionFont = $script:SMTheme.Label
        $Box.SelectionColor = $script:SMTheme.TextDim
        $Box.AppendText($Label.ToUpper() + '  ')
        $Box.SelectionFont = $script:SMTheme.Font
    }
    $Box.SelectionColor = if ($Color) { $Color } else { $script:SMTheme.Text }
    $Box.AppendText($Value + "`r`n")
    $Box.SelectionColor = $script:SMTheme.Text
}

function New-SMThemedGrid {
    $g = New-Object Windows.Forms.DataGridView
    $g.Dock = 'Fill'
    $g.ReadOnly = $true
    $g.AllowUserToAddRows = $false
    $g.AllowUserToDeleteRows = $false
    $g.AllowUserToResizeRows = $false
    $g.RowHeadersVisible = $false
    $g.SelectionMode = 'FullRowSelect'
    $g.AutoSizeColumnsMode = 'Fill'
    $g.ScrollBars = 'Vertical'
    $g.DefaultCellStyle.WrapMode = 'True'
    $g.AutoSizeRowsMode = 'DisplayedCellsExceptHeaders'
    $g.BackgroundColor = $script:SMTheme.Grid
    $g.GridColor = $script:SMTheme.Panel
    $g.BorderStyle = 'None'
    $g.EnableHeadersVisualStyles = $false
    $g.ColumnHeadersDefaultCellStyle.BackColor = $script:SMTheme.Panel
    $g.ColumnHeadersDefaultCellStyle.ForeColor = $script:SMTheme.Text
    $g.DefaultCellStyle.BackColor = $script:SMTheme.Grid
    $g.DefaultCellStyle.ForeColor = $script:SMTheme.Text
    $g.DefaultCellStyle.SelectionBackColor = $script:SMTheme.Ink
    $g.DefaultCellStyle.SelectionForeColor = $script:SMTheme.Paper
    $g.ColumnHeadersDefaultCellStyle.Font = $script:SMTheme.Label
    $g.GridColor = $script:SMTheme.Border; $g.CellBorderStyle = 'Single'; $g.BorderStyle = 'FixedSingle'
    $g.AlternatingRowsDefaultCellStyle.BackColor = $script:SMTheme.GridAlt
    Enable-SMDarkScrollbars -Control $g
    return $g
}

function New-SMButtonRow { param($Form, [string[]] $Buttons, [int] $AccentIndex = 0)
    $p = New-Object Windows.Forms.FlowLayoutPanel
    $p.Dock = 'Bottom'; $p.Height = 46; $p.FlowDirection = 'RightToLeft'; $p.Padding = New-Object Windows.Forms.Padding(8)
    $p.BackColor = $script:SMTheme.Panel
    Add-SMBlockShadows -Container $p
    $made = @{}
    for ($i = $Buttons.Count - 1; $i -ge 0; $i--) {
        $b = if ($i -eq $AccentIndex) { New-SMButton -Text $Buttons[$i] -Width 120 -Accent } else { New-SMButton -Text $Buttons[$i] -Width 120 }
        $p.Controls.Add($b); $made[$Buttons[$i]] = $b
    }
    $Form.Controls.Add($p)
    return $made
}

# ------------------------------------------------------------------ Legend / Help
function Show-SMLegendDialog {
    $f = New-SMDialogForm -Title 'How Startup Manager works' -Width 760 -Height 640
    $box = New-SMRichText; $box.Dock = 'Fill'; $box.Margin = New-Object Windows.Forms.Padding(12)
    $f.Controls.Add($box)
    $btn = New-SMButtonRow -Form $f -Buttons @('Got it')
    $btn['Got it'].Add_Click({ $this.FindForm().Close() })

    Add-SMRichHeading $box 'The four steps'
    Add-SMRichLine $box '' '1. Tick or untick the box in the "On" column. This only STAGES a change - nothing happens yet. The row turns amber and the Pending column shows what will happen.'
    Add-SMRichLine $box '' '2. Click the big "Apply (N)" button (or Ctrl+S). A confirmation lists every change with warnings.'
    Add-SMRichLine $box '' '3. Confirm. A mandatory recovery snapshot and journal are written first. Each setting is read back after applying; failures stay staged.'
    Add-SMRichLine $box '' '4. Changed your mind? "Discard" clears staged changes. "Undo last" (Ctrl+Z) reverts the last applied change. "History" shows every change ever made.'
    Add-SMRichLine $box '' ''
    Add-SMRichHeading $box 'Risk colours'
    Add-SMRichLine $box 'Critical'   'Pattern matched a potentially important component. Review evidence; this is not verified identity.' $script:SMTheme.RiskCritical
    Add-SMRichLine $box 'Suspicious' 'Unsigned AND running from a throwaway location (Temp, Downloads, AppData root). Investigate.' $script:SMTheme.RiskSuspicious
    Add-SMRichLine $box 'Broken'     'Points at a file that no longer exists. Safe to disable.' $script:SMTheme.RiskBroken
    Add-SMRichLine $box 'Caution'    'Disabling may break an app you rely on (chat, sync, peripherals).' $script:SMTheme.RiskCaution
    Add-SMRichLine $box 'Optional'   'Updater, tray helper, launcher, telemetry. Safe to disable.' $script:SMTheme.RiskOptional
    Add-SMRichLine $box 'Unknown'    'Not enough evidence. Read the details pane before deciding.' $script:SMTheme.RiskUnknown
    Add-SMRichLine $box '' ''
    Add-SMRichHeading $box 'Flags'
    foreach ($pair in @(
        @('MISSING','the file does not exist on disk'), @('UNSIGNED','no digital signature'), @('BAD-SIG','signature present but invalid'),
        @('TEMP-PATH','runs from Temp / Downloads / Desktop / AppData root'), @('UPDATER','looks like an auto-updater or crash reporter'),
        @('SYSTEM','runs as SYSTEM / highest privileges'), @('DELAYED','service uses delayed auto-start'),
        @('SLOW','Windows measured it taking 3 s or more at boot'), @('MS','signed by Microsoft'), @('ONE-SHOT','RunOnce - runs once then removes itself'))) {
        Add-SMRichLine $box $pair[0] $pair[1]
    }
    Add-SMRichLine $box '' ''
    Add-SMRichHeading $box 'Columns'
    Add-SMRichLine $box 'Boot ms' 'Latest exact-path measurement within 30 days. Shared hosts and ambiguous matches are excluded. Blank means no usable evidence, not fast.'
    Add-SMRichLine $box 'Signed'  'Valid / Unsigned / Invalid Authenticode signature of the executable.'
    Add-SMRichLine $box 'Where it lives' 'Which launch mechanism registered it. Windows Settings only shows "Registry Run" and "Startup Folder" items.'
    Add-SMRichLine $box '' ''
    Add-SMRichHeading $box 'Files'
    Add-SMRichLine $box 'Logs'    $script:SM.LogDir
    Add-SMRichLine $box 'Backups' $script:SM.BackupDir
    Add-SMRichLine $box 'Reports' $script:SM.ReportDir
    Add-SMRichLine $box 'Exports' $script:SM.ExportDir
    $box.SelectionStart = 0; $box.ScrollToCaret()
    [void]$f.ShowDialog()
}

# ------------------------------------------------------------------ History / Log viewer
function Show-SMLogViewer {
    $f = New-SMDialogForm -Title 'History & logs' -Width 980 -Height 640
    $tabs = New-Object Windows.Forms.TabControl; $tabs.Dock = 'Fill'
    $t1 = New-Object Windows.Forms.TabPage; $t1.Text = 'Change history'; $t1.BackColor = $script:SMTheme.Bg
    $t2 = New-Object Windows.Forms.TabPage; $t2.Text = 'Log';            $t2.BackColor = $script:SMTheme.Bg
    $tabs.TabPages.AddRange(@($t1, $t2))

    $g = New-SMThemedGrid
    $dt = New-Object System.Data.DataTable
    foreach ($c in @('When','Action','Name','Kind','From','To','Result','Error','Operation','Batch')) { [void]$dt.Columns.Add($c) }
    $recs = @(Get-SMChangeRecords)
    for ($i = $recs.Count - 1; $i -ge 0; $i--) {
        $r = $recs[$i]
        $when = ''; try { $when = ([datetime]$r.ts).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss') } catch { $when = [string]$r.ts }
        $result = if ($r.action -in @('prepare','prepare-undo')) { 'prepared' } elseif (Get-SMPropertyValue $r 'needsRecovery' $false) { 'recovery required' } elseif ($r.ok) { 'verified' } else { 'failed' }
        [void]$dt.Rows.Add($when, [string]$r.action, [string]$r.name, [string]$r.kind,
            $(if([bool]$r.from){'ON'}else{'OFF'}), $(if([bool]$r.to){'ON'}else{'OFF'}), $result, [string]$r.error, [string](Get-SMPropertyValue $r 'operationId'), [string](Get-SMPropertyValue $r 'batchId'))
    }
    $g.DataSource = $dt
    $t1.Controls.Add($g)

    $tb = New-SMRichText
    $tb.Multiline = $true; $tb.ReadOnly = $true; $tb.ScrollBars = 'Vertical'; $tb.WordWrap = $true; $tb.Dock = 'Fill'
    $tb.BackColor = $script:SMTheme.Grid; $tb.ForeColor = $script:SMTheme.Text
    $tb.Font = New-Object Drawing.Font('Consolas', 9)
    $tb.Text = (Get-SMLogText -TailLines 500)
    $t2.Controls.Add($tb)

    $f.Controls.Add($tabs)
    $btn = New-SMButtonRow -Form $f -Buttons @('Close','Open logs folder')
    $btn['Close'].Add_Click({ $this.FindForm().Close() })
    $btn['Open logs folder'].Add_Click({ Start-Process explorer.exe $script:SM.LogDir })
    $tabs.BringToFront()
    [void]$f.ShowDialog()
    if ($tb.Text.Length -gt 0) { $tb.SelectionStart = $tb.Text.Length; $tb.ScrollToCaret() }
}

# ------------------------------------------------------------------ Apply confirmation
function Show-SMApplyConfirmDialog {
    param([Parameter(Mandatory)] [AllowEmptyCollection()] $Changes)
    $list = @($Changes)
    $result = @{ Apply = $false; Backup = $true }
    $f = New-SMDialogForm -Title "Apply $($list.Count) change(s)?" -Width 820 -Height 520

    $nOff = @($list | Where-Object { -not $_.To }).Count
    $nOn  = $list.Count - $nOff
    $hasCritical = @($list | Where-Object { $_.Risk -eq 'Critical' -or $_.Kind -eq 'Service' }).Count -gt 0

    $top = New-Object Windows.Forms.Panel; $top.Dock = 'Top'; $top.Height = $(if ($hasCritical) { 84 } else { 40 }); $top.BackColor = $script:SMTheme.Panel
    $sum = New-SMLabel -Text "$nOff will be DISABLED, $nOn will be ENABLED. Nothing has been changed yet."
    $sum.Location = New-Object Drawing.Point(12, 10); $sum.AutoSize = $true
    $top.Controls.Add($sum)
    if ($hasCritical) {
        $warn = New-SMLabel -Text 'WARNING: you are about to change a Windows/driver component or a service. This can break boot, audio, networking or security.'
        $warn.ForeColor = $script:SMTheme.RiskCritical; $warn.Location = New-Object Drawing.Point(12, 40); $warn.AutoSize = $true; $warn.Font = $script:SMTheme.FontBold
        $top.Controls.Add($warn)
    }
    $f.Controls.Add($top)

    $g = New-SMThemedGrid
    $dt = New-Object System.Data.DataTable
    foreach ($c in @('!','Name','Kind','Change','Risk')) { [void]$dt.Columns.Add($c) }
    foreach ($p in $list) {
        $mark = if ($p.Risk -eq 'Critical' -or $p.Kind -eq 'Service') { '!' } else { '' }
        $transition = if ($p.Kind -eq 'Service') { if ($p.To) { 'Disabled -> Automatic' } else { 'Automatic -> Disabled' } } else { if ($p.To) { 'OFF -> ON' } else { 'ON -> OFF' } }
        [void]$dt.Rows.Add($mark, $p.Name, $p.Kind, $transition, $p.Risk)
    }
    $g.DataSource = $dt
    $g.Add_DataBindingComplete({
        $this.Columns[0].Width = 24; $this.Columns[0].AutoSizeMode = 'None'
        foreach ($row in $this.Rows) {
            if ([string]$row.Cells[0].Value -eq '!') { $row.DefaultCellStyle.BackColor = [Drawing.Color]::FromArgb(90, 30, 30); $row.DefaultCellStyle.ForeColor = $script:SMTheme.RiskCritical }
        }
    })
    $f.Controls.Add($g); $g.BringToFront()

    $bottom = New-Object Windows.Forms.Panel; $bottom.Dock = 'Bottom'; $bottom.Height = 36; $bottom.BackColor = $script:SMTheme.Panel
    $chk = New-SMLabel -Text 'Required: recovery snapshot, durable journal and Windows state verification.'
    $chk.AutoSize = $true
    $chk.ForeColor = $script:SMTheme.Text; $chk.Location = New-Object Drawing.Point(12, 8)
    $bottom.Controls.Add($chk)
    $f.Controls.Add($bottom)

    $f.Tag = @{ Result = $result; Chk = $chk }
    $btn = New-SMButtonRow -Form $f -Buttons @('Apply','Cancel') -AccentIndex 0
    $btn['Apply'].Add_Click({ $frm = $this.FindForm(); $frm.Tag.Result.Apply = $true; $frm.Close() })
    $btn['Cancel'].Add_Click({ $this.FindForm().Close() })
    $f.AcceptButton = $btn['Apply']
    [void]$f.ShowDialog()
    return $result
}

# ------------------------------------------------------------------ Details
function Show-SMDetailsDialog {
    param([Parameter(Mandatory)] $Entry)
    $e = $Entry
    $f = New-SMDialogForm -Title "Details - $($e.Name)" -Width 860 -Height 680
    $box = New-SMRichText; $box.Dock = 'Fill'
    $f.Controls.Add($box)
    $f.Tag = $e
    $btn = New-SMButtonRow -Form $f -Buttons @('Close','Open file location','Copy command')
    $btn['Close'].Add_Click({ $this.FindForm().Close() })
    $btn['Copy command'].Add_Click({ $en = $this.FindForm().Tag; if ($en.Command) { [Windows.Forms.Clipboard]::SetText([string]$en.Command) } })
    $btn['Open file location'].Add_Click({
        $en = $this.FindForm().Tag
        if ($en.ExePath -and (Test-Path -LiteralPath $en.ExePath)) { Start-Process explorer.exe ('/select,"' + $en.ExePath + '"') }
        elseif ($en.Kind -eq 'Folder' -and $en.Data.ContainsKey('File')) { Start-Process explorer.exe ('/select,"' + $en.Data.File + '"') }
    })
    Add-SMRichHeading $box $e.Name
    Add-SMRichLine $box 'What it is' $e.What
    Add-SMRichLine $box 'Where it lives' $e.Category
    Add-SMRichLine $box 'State' $(if ($e.Enabled) { 'ENABLED' } else { 'DISABLED' })
    Add-SMRichLine $box 'Risk' ($e.Risk + $(if (@($e.Flags).Count) { '   [' + (@($e.Flags) -join ', ') + ']' } else { '' })) (Get-SMRiskColor -Risk $e.Risk)
    Add-SMRichLine $box '' ''
    Add-SMRichHeading $box 'What it does'
    Add-SMRichLine $box '' $e.Explain
    Add-SMRichHeading $box 'If you disable this'
    Add-SMRichLine $box '' $e.DisableEffect
    Add-SMRichLine $box '' ''
    Add-SMRichHeading $box 'Facts'
    Add-SMRichLine $box 'Publisher' $(if ($e.Publisher) { $e.Publisher } else { '(unknown)' })
    Add-SMRichLine $box 'Product'   $(if ($e.Product) { $e.Product } else { '(unknown)' })
    Add-SMRichLine $box 'Signed'    ($e.SigStatus + $(if ($e.SigSigner) { ' - ' + $e.SigSigner } else { '' }))
    Add-SMRichLine $box 'Version'   $(if ($e.FileVersion) { $e.FileVersion } else { '(unknown)' })
    Add-SMRichLine $box 'Size'      $(if ($e.SizeKB -gt 0) { "$($e.SizeKB) KB" } else { '(unknown)' })
    Add-SMRichLine $box 'Boot time' $(if ($e.BootMs -ge 0) { "$($e.BootMs) ms measured by Windows (degradation $($e.DegradeMs) ms)" } else { 'no measurement recorded by Windows' })
    if ($e.PSObject.Properties['BootMeasuredAt']) { Add-SMRichLine $box 'Measured at' ([string]$e.BootMeasuredAt); Add-SMRichLine $box 'Attribution' ([string]$e.BootConfidence) }
    if ($e.PSObject.Properties['RiskEvidence']) { Add-SMRichLine $box 'Impact evidence' ([string]$e.RiskEvidence); Add-SMRichLine $box 'Security indicators' (@($e.SecurityFlags) -join ', ') }
    Add-SMRichLine $box 'Command'   $e.Command
    Add-SMRichLine $box 'Path'      $e.ExePath
    Add-SMRichLine $box 'Source'    $e.Source
    if ($e.Detail) {
        Add-SMRichLine $box '' ''
        Add-SMRichHeading $box 'Provider detail'
        $box.SelectionFont = New-Object Drawing.Font('Consolas', 9)
        $box.AppendText([string]$e.Detail + "`r`n")
        $box.SelectionFont = $script:SMTheme.Font
    }
    $box.SelectionStart = 0; $box.ScrollToCaret()
    [void]$f.ShowDialog()
}

# ------------------------------------------------------------------ About
function Show-SMAboutDialog {
    $f = New-SMDialogForm -Title 'About Startup Manager' -Width 560 -Height 360
    $box = New-SMRichText; $box.Dock = 'Fill'
    $f.Controls.Add($box)
    $btn = New-SMButtonRow -Form $f -Buttons @('Close')
    $btn['Close'].Add_Click({ $this.FindForm().Close() })
    Add-SMRichHeading $box 'STARTUP.MANAGER 2.1.0  by skreamb0t'
    Add-SMRichLine $box '' 'Shows everything that starts with Windows - Run keys, Startup folders, logon/boot scheduled tasks, automatic services and Store app tasks - and lets you stage, review, apply, log and undo changes.'
    Add-SMRichLine $box '' ''
    Add-SMRichLine $box '' 'Never deletes anything. Nothing is applied until you click Apply. Every change is logged.'
    Add-SMRichLine $box '' ''
    Add-SMRichLine $box 'Project' $script:SM.Root
    Add-SMRichLine $box 'Logs'    $script:SM.LogDir
    [void]$f.ShowDialog()
}
