# Main window. Implements the USER MODEL from docs/ARCHITECTURE.md:
# tick = stage, Apply (N) = commit with confirmation, Discard, Undo, History.

Set-StrictMode -Version 2.0

$script:SMUI = @{}

function Get-SMZoomTargets {
    param($Target)
    $Target
    if ($Target -is [Windows.Forms.Control]) {
        foreach ($child in $Target.Controls) { Get-SMZoomTargets $child }
    }
    if ($Target -is [Windows.Forms.ToolStrip]) {
        foreach ($item in $Target.Items) { Get-SMZoomTargets $item }
    }
    if ($Target -is [Windows.Forms.ToolStripDropDownItem]) {
        foreach ($item in $Target.DropDownItems) { Get-SMZoomTargets $item }
    }
}

function Update-SMMainLayout {
    $u = $script:SMUI
    if (-not $u.ContainsKey('Zoom') -or $u.Form.IsDisposed -or $u.LayoutBusy) { return }
    $u.LayoutBusy = $true
    try {
        $logicalWidth = $u.Grid.ClientSize.Width / ($u.Zoom * [StartupManager.NativeTheme]::GetDpiForWindow($u.Form.Handle) / 96.0)
        $thresholds = @{ Path=1800; Command=1800; Flags=1400; Publisher=1200; Signed=1400; BootMs=1000; Category=900 }
        foreach ($name in $thresholds.Keys) { $u.Grid.Columns[$name].Visible = ($logicalWidth -ge $thresholds[$name]) }
        $weights = @{ Pending=70; Risk=80; Flags=100; Name=240; What=260; Publisher=130; Signed=70; BootMs=70; Category=160; Command=240; Path=200 }
        foreach ($name in $weights.Keys) { $u.Grid.Columns[$name].FillWeight = $weights[$name] }
        $u.Grid.HorizontalScrollingOffset = 0
        $stack = ($logicalWidth -lt 1000)
        $layout = $u.DetailColumns
        if ($stack -ne $u.DetailsStacked) {
            $layout.SuspendLayout()
            $layout.ColumnStyles.Clear(); $layout.RowStyles.Clear()
            if ($stack) {
                $layout.ColumnCount = 1; $layout.RowCount = 2
                [void]$layout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100)))
                [void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent', 50)))
                [void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent', 50)))
                $layout.SetCellPosition($u.FactsCell, (New-Object Windows.Forms.TableLayoutPanelCellPosition(0, 1)))
            } else {
                $layout.ColumnCount = 2; $layout.RowCount = 1
                [void]$layout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 46)))
                [void]$layout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 54)))
                [void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent', 100)))
                $layout.SetCellPosition($u.FactsCell, (New-Object Windows.Forms.TableLayoutPanelCellPosition(1, 0)))
            }
            $u.DetailsStacked = $stack
            $layout.ResumeLayout($true)
            if ($u.ContainsKey('Split')) { $u.Split.SplitterDistance = [int]($u.Split.Height * $(if ($stack) { 0.60 } else { 0.68 })) }
        }
        $u.Brand.Tag.Tagline = if ($logicalWidth -ge 1050) { 'everything that starts with windows' } else { '' }
        $u.Brand.Invalidate()
    } finally { $u.LayoutBusy = $false }
}

function Set-SMMainZoom {
    param([double] $Zoom = 1.0, [switch] $Force)
    $u = $script:SMUI
    $Zoom = [Math]::Round([Math]::Max(0.75, [Math]::Min(1.5, $Zoom)), 2)
    if ($Zoom -eq $u.Zoom -and -not $Force) { return }
    $controlScale = $Zoom * [StartupManager.NativeTheme]::GetDpiForWindow($u.Form.Handle) / 96.0
    $u.Form.SuspendLayout()
    $oldFonts = $u.ZoomFonts
    $u.ZoomFonts = New-Object System.Collections.ArrayList
    $fontCache = @{}
    try {
        foreach ($record in $u.ZoomTargets) {
            $base = $record.Font
            $key = "$($base.Name)|$($base.Size)|$($base.Style)"
            if (-not $fontCache.ContainsKey($key)) {
                $fontCache[$key] = New-Object Drawing.Font($base.FontFamily, ([single]($base.Size * $Zoom)), $base.Style)
                [void]$u.ZoomFonts.Add($fontCache[$key])
            }
            $record.Target.Font = $fontCache[$key]
        }
        foreach ($name in $u.BaseThemeFonts.Keys) {
            $base = $u.BaseThemeFonts[$name]
            $font = New-Object Drawing.Font($base.FontFamily, ([single]($base.Size * $Zoom)), $base.Style)
            $script:SMTheme[$name] = $font
            [void]$u.ZoomFonts.Add($font)
        }
        foreach ($record in $u.ToolbarSizes) {
            $record.Control.Width = [int]($record.Width * $controlScale)
            if ($record.Control -is [Windows.Forms.Button]) { $record.Control.Height = [int](30 * $controlScale) }
        }
        $u.Zoom = $Zoom
        $u.Brand.Height = [int](64 * $controlScale)
        $u.Grid.DefaultCellStyle.Font = $script:SMTheme.Font
        $u.Grid.ColumnHeadersDefaultCellStyle.Font = $script:SMTheme.Label
        $u.Grid.RowTemplate.Height = [int](26 * $controlScale)
        $u.Grid.ColumnHeadersHeight = [int](30 * $controlScale)
        $u.Grid.Columns['On'].Width = [int](40 * $controlScale)
        foreach ($row in $u.Grid.Rows) { $row.Height = [int](26 * $controlScale) }
        $u.ZoomReset.Text = ([char]0x21BA) + " $([int]($Zoom * 100))%"
        Update-SMMainStyles
        Update-SMMainDetails
    } finally {
        $u.Form.ResumeLayout($true)
        Update-SMMainLayout
        foreach ($font in $oldFonts) { $font.Dispose() }
    }
    if ($u.ContainsKey('PreferencesPath')) { Save-SMMainPreferences }
}

function Get-SMBlend { param([Drawing.Color] $A, [Drawing.Color] $B, [double] $T)
    [Drawing.Color]::FromArgb(
        [int]($A.R + ($B.R - $A.R) * $T), [int]($A.G + ($B.G - $A.G) * $T), [int]($A.B + ($B.B - $A.B) * $T))
}

function New-SMMenuItem { param([string] $Text, [scriptblock] $OnClick = $null, [switch] $CheckOnClick, [bool] $Checked = $false, [string] $Shortcut = '')
    $m = New-Object Windows.Forms.ToolStripMenuItem
    $m.Text = $Text
    if ($CheckOnClick) { $m.CheckOnClick = $true; $m.Checked = $Checked }
    if ($Shortcut) { $m.ShortcutKeyDisplayString = $Shortcut }
    if ($OnClick) { $m.Add_Click($OnClick) }
    return $m
}

# ---------------------------------------------------------------- data helpers
function Test-SMMainVisible { param($E)
    $u = $script:SMUI
    $cat = [string]$E.Category
    $show = switch -Wildcard ($cat) {
        'Registry Run*'            { $u.CatRun.Checked }
        'RunOnce*'                 { $u.CatRunOnce.Checked }
        'Startup Folder*'          { $u.CatFolder.Checked }
        'Scheduled Task (Windows)' { $u.CatTask.Checked -and $u.CatMsTask.Checked }
        'Scheduled Task'           { $u.CatTask.Checked }
        'Service*'                 { $u.CatSvc.Checked }
        'Store App*'               { $u.CatUwp.Checked }
        default                    { $true }
    }
    if (-not $show) { return $false }
    $flags = @($E.Flags)
    $pendingIds = $script:SM.Pending.Keys
    switch ([string]$u.Preset.SelectedItem) {
        'Third-party only'   { if ($E.Risk -eq 'Critical' -or ($flags -contains 'MS')) { return $false } }
        'Enabled only'       { if (-not $E.Enabled) { return $false } }
        'Disabled only'      { if ($E.Enabled) { return $false } }
        'Problems'           { if (-not ($E.Risk -in @('Broken','Suspicious') -or ($flags -contains 'UNSIGNED') -or ($flags -contains 'BAD-SIG'))) { return $false } }
        'Slow starters'      { if ($E.BootMs -lt 3000) { return $false } }
        'Updaters & helpers' { if (-not ($E.Risk -eq 'Optional' -or ($flags -contains 'UPDATER'))) { return $false } }
        'Windows core'       { if ($E.Risk -ne 'Critical') { return $false } }
        'Pending changes'    { if (-not ($pendingIds -contains [string]$E.Id)) { return $false } }
    }
    $q = [string]$u.Search.Text
    if ($q -eq [string]$u.SearchPlaceholder) { $q = '' }
    if ($q.Trim().Length -gt 0) {
        $q = $q.Trim()
        $hit = ($E.Name -like "*$q*") -or ($E.What -like "*$q*") -or ($E.Publisher -like "*$q*") -or
               ($E.Command -like "*$q*") -or ($E.ExePath -like "*$q*") -or ($E.Category -like "*$q*") -or
               ((@($E.Flags) -join ' ') -like "*$q*") -or ($E.Risk -like "*$q*")
        if (-not $hit) { return $false }
    }
    return $true
}

function Get-SMPendingText { param([int] $Id)
    if ($script:SM.Pending.Contains([string]$Id)) { if ($script:SM.Pending[[string]$Id].To) { return '-> ON' } else { return '-> OFF' } }
    return ''
}

function Update-SMMainRowStyle { param($Row)
    $u = $script:SMUI
    $id = [int]$Row.Cells['Id'].Value
    if (-not $u.ById.ContainsKey($id)) { return }
    $e = $u.ById[$id]
    $pending = $script:SM.Pending.Contains([string]$id)
    $base = if ($Row.Index % 2 -eq 0) { $script:SMTheme.Grid } else { $script:SMTheme.GridAlt }
    if ($pending) {
        $Row.DefaultCellStyle.BackColor = Get-SMBlend $base $script:SMTheme.Pending 0.28
        $Row.DefaultCellStyle.ForeColor = $script:SMTheme.Text
        $Row.Cells['Pending'].Style.ForeColor = $script:SMTheme.Pending
        $Row.Cells['Pending'].Style.Font = $script:SMTheme.FontBold
    } else {
        $rc = Get-SMRiskColor -Risk $e.Risk
        $Row.DefaultCellStyle.BackColor = if ($e.Risk -eq 'Unknown') { $base } else { Get-SMBlend $base $rc 0.10 }
        $Row.DefaultCellStyle.ForeColor = if ($e.Enabled) { $script:SMTheme.Text } else { $script:SMTheme.TextDim }
        $Row.Cells['Pending'].Style.ForeColor = $script:SMTheme.Text
        $Row.Cells['Pending'].Style.Font = $script:SMTheme.Font
    }
    $Row.Cells['Risk'].Style.ForeColor = Get-SMRiskColor -Risk $e.Risk
    $Row.Cells['Risk'].Style.Font = $script:SMTheme.FontBold
    $Row.Cells['On'].ReadOnly = (-not $e.CanToggle) -or ($e.Kind -eq 'Service' -and -not $u.AdvancedMode)
}

function Update-SMMainStyles {
    foreach ($row in $script:SMUI.Grid.Rows) { Update-SMMainRowStyle $row }
}

function Update-SMMainGrid {
    $u = $script:SMUI
    $u.Loading = $true
    $grid = $u.Grid
    $sortCol = $null; $sortDir = 'None'
    if ($grid.SortedColumn) { $sortCol = $grid.SortedColumn.Name; $sortDir = $grid.SortOrder }
    $dt = $u.Table
    $dt.BeginLoadData()
    $dt.Rows.Clear()
    $shown = 0
    foreach ($e in @($script:SM.Inventory)) {
        if (-not (Test-SMMainVisible $e)) { continue }
        $boot = if ($e.BootMs -ge 0) { [int]$e.BootMs } else { [DBNull]::Value }
        $on = if ($script:SM.Pending.Contains([string]$e.Id)) { [bool]$script:SM.Pending[[string]$e.Id].To } else { [bool]$e.Enabled }
        [void]$dt.Rows.Add($on, (Get-SMPendingText $e.Id), [string]$e.Risk, (@($e.Flags) -join ', '), [string]$e.Name, [string]$e.What,
            [string]$e.Publisher, [string]$e.SigStatus, $boot, [string]$e.Category, [string]$e.Command, [string]$e.ExePath, [int]$e.Id)
        $shown++
    }
    $dt.EndLoadData()
    if ($sortCol -and $sortDir -ne 'None') {
        $dir = if ($sortDir -eq 'Ascending') { [ComponentModel.ListSortDirection]::Ascending } else { [ComponentModel.ListSortDirection]::Descending }
        $grid.Sort($grid.Columns[$sortCol], $dir)
    }
    Update-SMMainStyles
    $u.Loading = $false
    Update-SMMainStatus $shown
}

function Update-SMMainStatus { param([int] $Shown = -1)
    $u = $script:SMUI
    $inv = @($script:SM.Inventory)
    if ($Shown -lt 0) { $Shown = $u.Grid.Rows.Count }
    $n = @{ RunKey=0; Folder=0; Task=0; Service=0; Uwp=0; RunOnce=0 }
    foreach ($e in $inv) { $n[$e.Kind]++ }
    $p = (Get-SMPendingChanges).Count
    $u.Status.Text = "  Showing $Shown of $($inv.Count)   |   $p pending   |   Run keys $($n.RunKey)   Startup folders $($n.Folder)   Logon/boot tasks $($n.Task)   Auto services $($n.Service)   Store apps $($n.Uwp)"
    $u.BtnApply.Text = "Apply ($p)"
    $u.BtnApply.Enabled = ($p -gt 0)
    $u.BtnDiscard.Enabled = ($p -gt 0)
    $u.MenuApply.Enabled = ($p -gt 0)
    $u.MenuDiscard.Enabled = ($p -gt 0)
    $u.Form.Text = "Windows Startup App Manager | STARTUP.manager by skreamb0t" + $(if ($p -gt 0) { "  -  $p UNSAVED CHANGE(S)" } else { '' })
}

function Update-SMMainDetails {
    $u = $script:SMUI
    $T = $script:SMTheme
    $box = $u.Details; $fx = $u.Facts
    $box.Clear(); $fx.Clear()
    if ($u.Grid.SelectedRows.Count -eq 0) {
        Add-SMRichLine $box '' 'Select a row to see what it is, what it does, and what happens if you turn it off.' $T.TextDim
        return
    }
    $id = [int]$u.Grid.SelectedRows[0].Cells['Id'].Value
    if (-not $u.ById.ContainsKey($id)) { return }
    $e = $u.ById[$id]

    # ---- left: narrative ----
    Add-SMRichHeading $box $e.Name
    $box.SelectionFont = $T.Label; $box.SelectionColor = (Get-SMRiskColor -Risk $e.Risk)
    $box.AppendText(([string]$e.Risk).ToUpper() + $(if (@($e.Flags).Count) { '   ' + ((@($e.Flags) -join '  ')) } else { '' }) + "`r`n")
    $box.SelectionFont = $T.Font; $box.SelectionColor = $T.Text
    Add-SMRichLine $box 'What it is' $e.What
    Add-SMRichLine $box 'What it does' $e.Explain
    Add-SMRichLine $box 'If you disable this' $e.DisableEffect $T.Pending
    Add-SMRichLine $box 'Command' $e.Command
    Add-SMRichLine $box 'Path' $(if ($e.ExePath) { $e.ExePath } else { '(none)' })
    Add-SMRichLine $box 'Source' $e.Source
    $leftLines = 9

    # ---- right: short facts ----
    Add-SMRichLine $fx 'Where it lives' $e.Category
    Add-SMRichLine $fx 'State' $(if ($e.Enabled) { 'ENABLED' } else { 'DISABLED' })
    Add-SMRichLine $fx 'Publisher' $(if ($e.Publisher) { $e.Publisher } else { '(unknown)' })
    Add-SMRichLine $fx 'Signed' ($e.SigStatus + $(if ($e.SigSigner) { '  by ' + $e.SigSigner } else { '' }))
    Add-SMRichLine $fx 'Version / Size' ($(if ($e.FileVersion) { $e.FileVersion } else { '(unknown)' }) + $(if ($e.SizeKB -gt 0) { "   /   $($e.SizeKB) KB" } else { '' }))
    Add-SMRichLine $fx 'Boot time' $(if ($e.BootMs -ge 0) { "$($e.BootMs) ms measured by Windows  (degradation $($e.DegradeMs) ms)" } else { 'no measurement recorded by Windows' })
    if ($e.PSObject.Properties['BootMeasuredAt']) { Add-SMRichLine $fx 'Measured at' ([string]$e.BootMeasuredAt); Add-SMRichLine $fx 'Attribution' ([string]$e.BootConfidence) }
    if ($e.PSObject.Properties['RiskEvidence']) { Add-SMRichLine $fx 'Impact evidence' ([string]$e.RiskEvidence); Add-SMRichLine $fx 'Security indicators' (@($e.SecurityFlags) -join ', ') }
    $rightLines = 6

    # ---- provider detail: split across BOTH columns so they end up the same height ----
    if ($e.Detail) {
        $lines = @(([string]$e.Detail) -split "\r?\n" | Where-Object { $_.Trim().Length -gt 0 })
        $total = $leftLines + $rightLines + $lines.Count
        $toRight = [Math]::Max(0, [int][Math]::Ceiling($total / 2.0) - $rightLines)
        if ($toRight -gt $lines.Count) { $toRight = $lines.Count }
        $rightPart = @($lines | Select-Object -First $toRight)
        $leftPart  = @($lines | Select-Object -Skip $toRight)
        foreach ($pair in @(@($fx, $rightPart), @($box, $leftPart))) {
            $tb = $pair[0]; $part = $pair[1]
            if ($part.Count -eq 0) { continue }
            $tb.SelectionFont = $T.Mono
            $tb.SelectionColor = $T.TextDim
            $tb.AppendText(($part -join "`r`n"))
            $tb.SelectionFont = $T.Font
        }
    }
    $box.SelectionStart = 0; $box.ScrollToCaret()
    $fx.SelectionStart = 0; $fx.ScrollToCaret()
}

# ---------------------------------------------------------------- actions
function Invoke-SMMainScan {
    $u = $script:SMUI
    if ($u.Scanning -or $u.Applying) { return }
    try {
        $u.ScanJob = Start-SMInventoryScan -Root $script:SM.Root -State $script:SM
        $u.Scanning = $true
        Set-SMMainBusy -Busy $true
        $u.CancelScan.Visible = $true
        $u.ScanTimer.Start()
    } catch {
        $u.Scanning = $false
        Set-SMMainBusy -Busy $false
        Show-SMMainError -Message ('Could not start scan: ' + $_.Exception.Message)
    }
}

function Set-SMMainBusy {
    param([bool] $Busy)
    $u = $script:SMUI
    if (-not $u.ContainsKey('Toolbar')) { return }
    $u.Toolbar.Enabled = -not $Busy
    $u.Menu.Enabled = -not $Busy
    $u.Grid.Enabled = -not $Busy
    $u.Progress.Visible = $Busy
    if (-not $Busy) { Update-SMMainStatus }
}

function Show-SMMainError {
    param([string] $Message)
    Write-SMLog -Level ERROR -Message $Message
    $script:SMUI.Status.Text = '  ' + $Message
    [void][Windows.Forms.MessageBox]::Show($Message, 'Startup Manager', 'OK', 'Warning')
}

function Complete-SMMainScan {
    $u = $script:SMUI
    if (-not $u.Scanning) { return }
    $job = $u.ScanJob
    $u.Status.Text = '  ' + $job.Shared.Label
    $u.Progress.Maximum = [Math]::Max(1, [int]$job.Shared.Total)
    $u.Progress.Value = [Math]::Min($u.Progress.Maximum, [Math]::Max(0, [int]$job.Shared.Done))
    if (-not $job.Handle.IsCompleted) { return }
    $u.ScanTimer.Stop()
    $message = ''
    try {
        $result = Complete-SMInventoryScan -Job $job
        $inventory = @($result.Inventory)
        $byIdentity = @{}
        foreach ($entry in $inventory) { $byIdentity[(Get-SMEntryIdentity $entry)] = $entry }
        $pending = [ordered]@{}
        $nextId = $inventory.Count + 1
        $warnings = @($result.ScanWarnings)
        foreach ($change in (Get-SMPendingChanges)) {
            $identity = Get-SMEntryIdentity $change.Entry
            if ($byIdentity.ContainsKey($identity)) {
                $change.Entry = $byIdentity[$identity]
                $change.Id = $change.Entry.Id
            } else {
                $change.Id = $nextId; $change.Entry.Id = $nextId; $nextId++
                $inventory += $change.Entry
                $warnings += "Staged target no longer appears in the scan: $($change.Name). Discard or refresh before applying."
            }
            $pending[[string]$change.Id] = $change
        }
        $script:SM.Pending = $pending
        $script:SM.Inventory = $inventory
        $script:SM.BootPerf = $result.BootPerf
        $script:SM.ScanWarnings = $warnings
        $script:SM.ScanComplete = [bool]$result.ScanComplete -and $warnings.Count -eq 0
        $u.ById = @{}
        foreach ($entry in $inventory) { $u.ById[[int]$entry.Id] = $entry }
        Update-SMMainGrid
        Update-SMMainDetails
        if ($warnings.Count) { $message = 'Incomplete scan: ' + ($warnings -join ' | ') }
    } catch {
        $message = if ($job.Shared.Cancelled) { 'Scan cancelled. Previous inventory and staged changes retained.' } else { 'Scan failed; previous inventory retained: ' + $_.Exception.Message }
        $script:SM.ScanComplete = $false
        $script:SM.ScanWarnings = @($script:SM.ScanWarnings) + $message
        Write-SMLog -Level WARN -Message $message
    } finally {
        Close-SMInventoryScan -Job $job
        $u.ScanJob = $null; $u.Scanning = $false
        $u.CancelScan.Visible = $false
        Set-SMMainBusy -Busy $false
    }
    $u.ScanNotice = $message
    $u.Warnings.Visible = -not [string]::IsNullOrWhiteSpace($message)
    if ($message) { $u.Status.Text = '  ' + $message }
    if ($u.AfterScanMessage) {
        $u.Status.Text = '  ' + $u.AfterScanMessage + ' ' + $u.Status.Text.Trim()
        $u.AfterScanMessage = ''
    }
    if ($u.CloseAfterScan) { $u.CloseAfterScan = $false; $u.Form.Close() }
}

function Invoke-SMMainApply {
    $u = $script:SMUI
    if ($u.Scanning -or $u.Applying) { return }
    $changes = Get-SMPendingChanges
    if ($changes.Count -eq 0) { return }
    if (@($changes | Where-Object { $_.Kind -eq 'Service' }).Count -and -not $u.AdvancedMode) {
        Show-SMMainError 'Enable advanced service changes in Tools before applying service changes.'
        return
    }
    $r = Show-SMApplyConfirmDialog -Changes $changes
    if (-not $r.Apply) { Write-SMLog -Level INFO -Message 'Apply cancelled by user'; return }
    $u.Applying = $true
    Set-SMMainBusy -Busy $true
    try { $results = Invoke-SMApplyChanges }
    catch { Show-SMMainError ('Apply stopped: ' + $_.Exception.Message); return }
    finally { $u.Applying = $false; Set-SMMainBusy -Busy $false }
    $okN = @($results | Where-Object { $_.Ok }).Count
    $bad = @($results | Where-Object { -not $_.Ok })
    if ($bad.Count -gt 0) {
        $msg = ($bad | ForEach-Object { "$($_.Name): $($_.Error)" }) -join "`n"
        [Windows.Forms.MessageBox]::Show("Applied $okN, failed $($bad.Count):`n`n$msg", 'Startup Manager', 'OK', 'Warning') | Out-Null
    }
    $u.AfterScanMessage = "Applied $okN change(s), $($bad.Count) failed."
    Invoke-SMMainScan
    $u.Status.Text = '  ' + $u.AfterScanMessage + ' Refreshing confirmed state...'
}

function Invoke-SMMainDiscard {
    if ($script:SMUI.Scanning -or $script:SMUI.Applying) { return }
    Clear-SMPendingChanges
    Write-SMLog -Level INFO -Message 'Pending changes discarded'
    Update-SMMainGrid
}

function Invoke-SMMainUndo {
    param([switch] $Batch)
    $u = $script:SMUI
    if ($u.Scanning -or $u.Applying) { return }
    if ((Get-SMPendingChanges).Count) { Show-SMMainError 'Apply or discard staged changes before undo.'; return }
    $label = if ($Batch) { 'the last Apply batch' } else { 'the last applied change' }
    if ([Windows.Forms.MessageBox]::Show("Restore $label? Current settings will be checked before restoring.", 'Confirm undo', 'OKCancel', 'Warning') -ne 'OK') { return }
    $u.Applying = $true; Set-SMMainBusy -Busy $true
    try { if ($Batch) { $results = Undo-SMLastBatch } else { $results = @(Undo-SMLastChange) } }
    catch { Show-SMMainError ('Undo stopped: ' + $_.Exception.Message); return }
    finally { $u.Applying = $false; Set-SMMainBusy -Busy $false }
    $results = @($results | Where-Object { $null -ne $_ })
    if (-not $results.Count) { $u.Status.Text = '  Nothing to undo.'; return }
    $failed = @($results | Where-Object { -not $_.Ok })
    if ($failed.Count) { Show-SMMainError (($failed | ForEach-Object { "$($_.Name): $($_.Error)" }) -join "`n") }
    $u.AfterScanMessage = "Undo: $($results.Count - $failed.Count) restored, $($failed.Count) failed."
    Invoke-SMMainScan
}

function Get-SMMainSelectedEntries {
    $u = $script:SMUI
    $list = @()
    foreach ($row in $u.Grid.SelectedRows) { $id = [int]$row.Cells['Id'].Value; if ($u.ById.ContainsKey($id)) { $list += $u.ById[$id] } }
    return ,[array]$list
}

function Get-SMMainVisibleEntries {
    $u = $script:SMUI
    $list = @()
    foreach ($row in $u.Grid.Rows) { $id = [int]$row.Cells['Id'].Value; if ($u.ById.ContainsKey($id)) { $list += $u.ById[$id] } }
    return ,[array]$list
}

function Invoke-SMMainStage { param([bool] $Enable)
    $u = $script:SMUI
    if ($u.Scanning -or $u.Applying) { return }
    $n = 0
    $errors = @()
    foreach ($e in (Get-SMMainSelectedEntries)) {
        if (-not $e.CanToggle) { continue }
        try {
            if ($e.Kind -eq 'Service' -and -not $u.AdvancedMode) { throw 'Enable advanced service changes in Tools first.' }
            Add-SMPendingChange -Entry $e -Enable $Enable; $n++
        } catch { $errors += "$($e.Name): $($_.Exception.Message)" }
    }
    Write-SMLog -Level INFO -Message "Staged $n item(s) -> $(if($Enable){'ON'}else{'OFF'})"
    Update-SMMainGrid
    if ($errors.Count) { Show-SMMainError ($errors -join "`n") }
}

function Invoke-SMMainExport { param([string] $Format, [bool] $All, [switch] $ShareSafe)
    $u = $script:SMUI
    $entries = if ($All) { @($script:SM.Inventory) } else { Get-SMMainVisibleEntries }
    $tag = if ($All) { 'all' } else { 'view' }
    if ($ShareSafe) { $tag += '_share-safe' }
    $path = Join-Path $script:SM.ExportDir ("startup_" + $tag + "_" + (Get-Date -Format 'yyyyMMdd_HHmmss_fffffff') + "." + $Format)
    try {
        $p = Export-SMEntries -Entries $entries -Format $Format -Path $path -ShareSafe:$ShareSafe
        Write-SMLog -Level INFO -Message "Exported $($entries.Count) entries ($tag) to $p"
        $u.Status.Text = "  Exported: $p"
        Start-Process explorer.exe ('/select,"' + $p + '"')
    } catch { [Windows.Forms.MessageBox]::Show("Export failed:`n$($_.Exception.Message)", 'Startup Manager', 'OK', 'Error') | Out-Null }
}

function Invoke-SMMainReport {
    param([switch] $ShareSafe)
    $u = $script:SMUI
    $tag = if ($ShareSafe) { 'share-safe_' } else { '' }
    $path = Join-Path $script:SM.ReportDir ("startup_report_" + $tag + (Get-Date -Format 'yyyyMMdd_HHmmss_fffffff') + ".html")
    try {
        $p = New-SMReport -Entries @($script:SM.Inventory) -BootPerf $script:SM.BootPerf -ChangeRecords @(Get-SMChangeRecords) -Path $path -ShareSafe:$ShareSafe -ScanWarnings @($script:SM.ScanWarnings)
        Write-SMLog -Level INFO -Message "Report written: $p"
        $u.Status.Text = "  Report: $p"
        Start-Process $p
    } catch { [Windows.Forms.MessageBox]::Show("Report failed:`n$($_.Exception.Message)", 'Startup Manager', 'OK', 'Error') | Out-Null }
}

function Open-SMMainLocation {
    $sel = Get-SMMainSelectedEntries
    if ($sel.Count -eq 0) { return }
    $e = $sel[0]
    try {
        if ($e.Kind -eq 'Folder' -and $e.Data.ContainsKey('File')) { Start-Process explorer.exe ('/select,"' + $e.Data.File + '"'); return }
        if ($e.ExePath -and (Test-Path -LiteralPath $e.ExePath)) { Start-Process explorer.exe ('/select,"' + $e.ExePath + '"') }
        else { $script:SMUI.Status.Text = "  File not found on disk: $($e.ExePath)" }
    } catch { $script:SMUI.Status.Text = '  ' + $_.Exception.Message }
}

function Save-SMMainPreferences {
    $u = $script:SMUI
    try { Save-SMPreferences -Path $u.PreferencesPath -Zoom $u.Zoom -ReducedMotion $u.ReducedMotion }
    catch { Write-SMLog -Level WARN -Message ('Could not save display preferences: ' + $_.Exception.Message) }
}

function Set-SMMainReducedMotion {
    param([bool] $Enabled)
    $u = $script:SMUI
    $u.ReducedMotion = $Enabled
    if ($Enabled) { $u.Brand.Tag.Timer.Stop(); $u.Brand.Tag.Phase = 0.0; $u.Brand.Invalidate() }
    else { $u.Brand.Tag.Timer.Start() }
    Save-SMMainPreferences
}

function Invoke-SMMainBaseline {
    param([switch] $Compare)
    if ($script:SMUI.Scanning -or $script:SMUI.Applying) { return }
    if (-not $script:SM.ScanComplete) { Show-SMMainError 'A complete scan is required before saving or comparing a baseline. Refresh and resolve Scan details first.'; return }
    $dialog = if ($Compare) { New-Object Windows.Forms.OpenFileDialog } else { New-Object Windows.Forms.SaveFileDialog }
    $dialog.Filter = 'Startup baseline (*.json)|*.json'; $dialog.InitialDirectory = $script:SM.BackupDir
    $dialog.FileName = 'startup-baseline.json'
    try {
        if ($dialog.ShowDialog() -ne 'OK') { return }
        if ($Compare) {
            $baseline = Get-SMBaseline -Path $dialog.FileName
            $changes = @(Compare-SMBaseline -Baseline $baseline -Entries @($script:SM.Inventory))
            $form = New-SMDialogForm -Title "Baseline comparison: $($changes.Count) differences" -Width 1000 -Height 650
            try {
                $box = New-SMRichText; $box.Dock = 'Fill'; $form.Controls.Add($box)
                Add-SMRichHeading $box 'Local baseline comparison'
                Add-SMRichLine $box '' 'Read-only comparison. This does not apply or restore any settings. An incomplete scan can appear to remove items.'
                foreach ($change in $changes) {
                    Add-SMRichHeading $box ("$($change.Change): $($change.Name)")
                    Add-SMRichLine $box 'Fields' (@($change.Fields) -join ', ')
                    Add-SMRichLine $box 'Before' ($change.Before | ConvertTo-Json -Depth 6 -Compress)
                    Add-SMRichLine $box 'After' ($change.After | ConvertTo-Json -Depth 6 -Compress)
                }
                if (-not $changes.Count) { Add-SMRichLine $box '' 'No differences found.' }
                [void]$form.ShowDialog()
            } finally { $form.Dispose() }
        } else {
            Save-SMBaseline -Entries @($script:SM.Inventory) -Path $dialog.FileName
            $script:SMUI.Status.Text = '  Baseline saved locally. Contains private paths and commands: ' + $dialog.FileName
        }
    } catch { Show-SMMainError ('Baseline failed: ' + $_.Exception.Message) }
    finally { $dialog.Dispose() }
}

function Invoke-SMMainRecovery {
    if ($script:SMUI.Scanning -or $script:SMUI.Applying) { return }
    try {
        $operations = @(Get-SMInterruptedOperations)
        if (-not $operations.Count) { $script:SMUI.Status.Text = '  No interrupted operations.'; return }
        foreach ($operation in $operations) {
            $prompt = "Restore the saved pre-change state for '$($operation.name)'?`nOperation: $($operation.operationId)`nReview History first if another tool has changed this item."
            if ([Windows.Forms.MessageBox]::Show($prompt, 'Recover interrupted change', 'OKCancel', 'Warning') -ne 'OK') { break }
            [void](Restore-SMInterruptedOperation -OperationId $operation.operationId)
        }
        Invoke-SMMainScan
    } catch { Show-SMMainError ('Recovery stopped: ' + $_.Exception.Message) }
}

# ---------------------------------------------------------------- the form
function Show-SMMainForm {
    [CmdletBinding()]
    param([int] $AutoCloseMs = 0)

    $u = $script:SMUI
    $T = $script:SMTheme
    $u.Loading = $true
    $u.ById = @{}

    $form = New-Object Windows.Forms.Form
    $u.Scanning = $false; $u.Applying = $false; $u.AdvancedMode = $false
    $u.ScanJob = $null; $u.CloseAfterScan = $false; $u.AfterScanMessage = ''; $u.ScanNotice = ''
    $u.PreferencesPath = Join-Path $script:SM.LogDir 'preferences.json'
    $preferences = Get-SMPreferences -Path $u.PreferencesPath
    $u.ReducedMotion = $preferences.ReducedMotion
    $u.SavedZoom = $preferences.Zoom
    $script:SM.ScanWarnings = @(); $script:SM.ScanComplete = $false
    $form.Text = 'Windows Startup App Manager | STARTUP.manager by skreamb0t'
    $workArea = [Windows.Forms.Screen]::FromPoint([Windows.Forms.Cursor]::Position).WorkingArea
    $form.Size = New-Object Drawing.Size(([Math]::Min(1560, $workArea.Width)), ([Math]::Min(920, $workArea.Height)))
    $form.MinimumSize = New-Object Drawing.Size(800, 600)
    $form.AutoScaleDimensions = New-Object Drawing.SizeF(96, 96)
    $form.AutoScaleMode = 'Dpi'
    $form.StartPosition = 'CenterScreen'
    $form.BackColor = $T.Bg; $form.ForeColor = $T.Text; $form.Font = $T.Font
    $form.KeyPreview = $true
    $u.Form = $form

    # ---- menu ----
    $menu = New-Object Windows.Forms.MenuStrip
    $menu.BackColor = $T.Panel; $menu.ForeColor = $T.Text; $menu.Font = $T.MonoBold; $menu.RenderMode = 'System'
    $mFile = New-SMMenuItem 'File'; $mView = New-SMMenuItem 'View'; $mTools = New-SMMenuItem 'Tools'; $mHelp = New-SMMenuItem 'Help'
    $mExpView = New-SMMenuItem 'Export current view'; $mExpAll = New-SMMenuItem 'Export everything'
    foreach ($fmt in @('csv','json','txt','html')) {
        $mExpView.DropDownItems.Add((New-SMMenuItem ($fmt.ToUpper()) ([scriptblock]::Create("Invoke-SMMainExport -Format '$fmt' -All `$false")))) | Out-Null
        $mExpAll.DropDownItems.Add((New-SMMenuItem ($fmt.ToUpper()) ([scriptblock]::Create("Invoke-SMMainExport -Format '$fmt' -All `$true")))) | Out-Null
    }
    $mFile.DropDownItems.AddRange(@($mExpView, $mExpAll, (New-SMMenuItem 'Generate report' { Invoke-SMMainReport }),
        (New-SMMenuItem 'Generate share-safe report' { Invoke-SMMainReport -ShareSafe }),
        (New-SMMenuItem 'Save local baseline...' { Invoke-SMMainBaseline }),
        (New-SMMenuItem 'Compare with baseline...' { Invoke-SMMainBaseline -Compare }),
        (New-SMMenuItem 'Backup registry now' { try { $b = Backup-SMRegistry; $script:SMUI.Status.Text = "  Backup written: $b" } catch { $script:SMUI.Status.Text = "  Backup failed: $($_.Exception.Message)" } }),
        (New-Object Windows.Forms.ToolStripSeparator), (New-SMMenuItem 'Exit' { $script:SMUI.Form.Close() })))
    $u.CatRun     = New-SMMenuItem 'Registry Run keys'   { Update-SMMainGrid } -CheckOnClick -Checked $true
    $u.CatRunOnce = New-SMMenuItem 'RunOnce (one-shot)'  { Update-SMMainGrid } -CheckOnClick -Checked $true
    $u.CatFolder  = New-SMMenuItem 'Startup folders'     { Update-SMMainGrid } -CheckOnClick -Checked $true
    $u.CatTask    = New-SMMenuItem 'Scheduled tasks'     { Update-SMMainGrid } -CheckOnClick -Checked $true
    $u.CatMsTask  = New-SMMenuItem "Windows' own tasks"  { Update-SMMainGrid } -CheckOnClick -Checked $false
    $u.CatSvc     = New-SMMenuItem 'Services (Automatic)' { Update-SMMainGrid } -CheckOnClick -Checked $false
    $u.CatUwp     = New-SMMenuItem 'Store app tasks'     { Update-SMMainGrid } -CheckOnClick -Checked $true
    $mView.DropDownItems.AddRange(@((New-SMMenuItem 'Refresh' { Invoke-SMMainScan } -Shortcut 'F5'), (New-Object Windows.Forms.ToolStripSeparator),
        $u.CatRun, $u.CatRunOnce, $u.CatFolder, $u.CatTask, $u.CatMsTask, $u.CatSvc, $u.CatUwp))
    $u.MenuApply   = New-SMMenuItem 'Apply staged changes' { Invoke-SMMainApply } -Shortcut 'Ctrl+S'
    $u.MenuDiscard = New-SMMenuItem 'Discard staged changes' { Invoke-SMMainDiscard }
    $mTools.DropDownItems.AddRange(@($u.MenuApply, $u.MenuDiscard, (New-SMMenuItem 'Undo last applied change' { Invoke-SMMainUndo } -Shortcut 'Ctrl+Z'),
        (New-SMMenuItem 'Undo last Apply batch' { Invoke-SMMainUndo -Batch }),
        (New-SMMenuItem 'Recover interrupted change...' { Invoke-SMMainRecovery }),
        (New-SMMenuItem 'History & logs' { Show-SMLogViewer }), (New-Object Windows.Forms.ToolStripSeparator),
        (New-SMMenuItem 'Open Task Scheduler' { Start-Process taskschd.msc }), (New-SMMenuItem 'Open Services' { Start-Process services.msc }),
        (New-SMMenuItem 'Open Startup folder' { Start-Process explorer.exe ([Environment]::GetFolderPath('Startup')) }),
        (New-SMMenuItem 'Open logs folder' { Start-Process explorer.exe $script:SM.LogDir })))
    $advanced = New-SMMenuItem 'Advanced service changes' {
        if ($this.Checked -and [Windows.Forms.MessageBox]::Show('Service changes can affect networking, security and boot. Enabling a disabled service sets Automatic, not its unknown historical type. Enable advanced service changes for this session?', 'Advanced mode', 'OKCancel', 'Warning') -ne 'OK') { $this.Checked = $false }
        $script:SMUI.AdvancedMode = $this.Checked
        Update-SMMainGrid
    } -CheckOnClick
    [void]$mTools.DropDownItems.Add($advanced)
    $mHelp.DropDownItems.AddRange(@((New-SMMenuItem 'How this works (legend)' { Show-SMLegendDialog } -Shortcut 'F1'), (New-SMMenuItem 'About' { Show-SMAboutDialog })))
    $menu.Items.AddRange(@($mFile, $mView, $mTools, $mHelp))
    $form.MainMenuStrip = $menu

    # ---- toolbar ----
    $bar = New-Object Windows.Forms.FlowLayoutPanel
    $bar.Dock = 'Top'; $bar.AutoSize = $true; $bar.AutoSizeMode = 'GrowAndShrink'; $bar.WrapContents = $true; $bar.BackColor = $T.Paper
    $bar.Padding = New-Object Windows.Forms.Padding(14, 6, 14, 6)
    $x = 14
    $u.BtnApply = New-SMButton -Text 'Apply (0)' -Width 130 -Accent
    $u.BtnApply.Location = New-Object Drawing.Point($x, 11); $u.BtnApply.Height = 30; $u.BtnApply.Enabled = $false; $x += 136
    $u.BtnDiscard = New-SMButton -Text 'Discard' -Width 80; $u.BtnDiscard.Location = New-Object Drawing.Point($x, 11); $u.BtnDiscard.Height = 30; $u.BtnDiscard.Enabled = $false; $x += 96
    $btnRefresh = New-SMButton -Text 'Refresh' -Width 80; $btnRefresh.Location = New-Object Drawing.Point($x, 11); $btnRefresh.Height = 30; $x += 96
    $u.Search = New-SMTextBox -Width 300; $u.Search.Location = New-Object Drawing.Point($x, 14); $x += 310
    $u.Preset = New-SMComboBox -Items @('All items','Third-party only','Enabled only','Disabled only','Problems','Slow starters','Updaters & helpers','Windows core','Pending changes') -Width 170
    $u.Preset.Location = New-Object Drawing.Point($x, 14); $u.Preset.SelectedIndex = 0; $x += 180
    $btnCats = New-SMButton -Text 'Categories' -Width 100; $btnCats.Location = New-Object Drawing.Point($x, 11); $btnCats.Height = 30; $x += 116
    $btnReport = New-SMButton -Text 'Report' -Width 80; $btnReport.Location = New-Object Drawing.Point($x, 11); $btnReport.Height = 30; $x += 88
    $btnExport = New-SMButton -Text 'Export' -Width 80; $btnExport.Location = New-Object Drawing.Point($x, 11); $btnExport.Height = 30; $x += 88
    $btnUndo = New-SMButton -Text 'Undo last' -Width 90; $btnUndo.Location = New-Object Drawing.Point($x, 11); $btnUndo.Height = 30; $x += 98
    $btnHist = New-SMButton -Text 'History' -Width 80; $btnHist.Location = New-Object Drawing.Point($x, 11); $btnHist.Height = 30; $x += 88
    $btnHelp = New-SMButton -Text 'Help' -Width 60; $btnHelp.Location = New-Object Drawing.Point($x, 11); $btnHelp.Height = 30
    $bar.Controls.AddRange(@($u.BtnApply, $u.BtnDiscard, $btnRefresh, $u.Search, $u.Preset, $btnCats, $btnReport, $btnExport, $btnUndo, $btnHist, $btnHelp))
    foreach ($control in $bar.Controls) { $control.Margin = New-Object Windows.Forms.Padding(0, 5, 10, 5) }

    # search placeholder
    $u.SearchPlaceholder = 'Search name, publisher, command, path...'
    $u.Search.ForeColor = $T.TextDim; $u.Search.Text = $u.SearchPlaceholder
    $u.Search.Add_GotFocus({ if ($script:SMUI.Search.Text -eq $script:SMUI.SearchPlaceholder) { $script:SMUI.Search.Text = ''; $script:SMUI.Search.ForeColor = $script:SMTheme.Text } })
    $u.Search.Add_LostFocus({ if ($script:SMUI.Search.Text.Trim() -eq '') { $script:SMUI.Search.Text = $script:SMUI.SearchPlaceholder; $script:SMUI.Search.ForeColor = $script:SMTheme.TextDim } })
    $u.Search.Add_TextChanged({ if (-not $script:SMUI.Loading -and $script:SMUI.Search.Text -ne $script:SMUI.SearchPlaceholder) { Update-SMMainGrid } })

    $catMenu = New-Object Windows.Forms.ContextMenuStrip
    $catMenu.Items.AddRange(@($u.CatRun, $u.CatRunOnce, $u.CatFolder, $u.CatTask, $u.CatMsTask, $u.CatSvc, $u.CatUwp)) | Out-Null
    # menu items can only live in one strip; rebuild View menu with clones that proxy the same state
    $mView.DropDownItems.Clear()
    $mView.DropDownItems.Add((New-SMMenuItem 'Refresh' { Invoke-SMMainScan } -Shortcut 'F5')) | Out-Null
    $mView.DropDownItems.Add((New-SMMenuItem 'Categories...' { $script:SMUI.CatMenu.Show([Windows.Forms.Cursor]::Position) })) | Out-Null
    [void]$mView.DropDownItems.Add((New-SMMenuItem 'Reduced motion' { Set-SMMainReducedMotion -Enabled $this.Checked } -CheckOnClick -Checked $u.ReducedMotion))
    $u.CatMenu = $catMenu
    $btnCats.Add_Click({ $script:SMUI.CatMenu.Show($script:SMUI.BtnCats, 0, $script:SMUI.BtnCats.Height) })
    $u.BtnCats = $btnCats

    $expMenu = New-Object Windows.Forms.ContextMenuStrip
    foreach ($fmt in @('csv','json','txt','html')) {
        $expMenu.Items.Add((New-SMMenuItem ("Current view as " + $fmt.ToUpper()) ([scriptblock]::Create("Invoke-SMMainExport -Format '$fmt' -All `$false")))) | Out-Null
    }
    $expMenu.Items.Add((New-Object Windows.Forms.ToolStripSeparator)) | Out-Null
    foreach ($fmt in @('csv','json','txt','html')) {
        $expMenu.Items.Add((New-SMMenuItem ("Everything as " + $fmt.ToUpper()) ([scriptblock]::Create("Invoke-SMMainExport -Format '$fmt' -All `$true")))) | Out-Null
    }
    [void]$expMenu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
    foreach ($fmt in @('csv','json','txt','html')) {
        [void]$expMenu.Items.Add((New-SMMenuItem ("Share-safe view as " + $fmt.ToUpper()) ([scriptblock]::Create("Invoke-SMMainExport -Format '$fmt' -All `$false -ShareSafe"))))
    }
    [void]$expMenu.Items.Add((New-SMMenuItem 'Share-safe HTML report' { Invoke-SMMainReport -ShareSafe }))
    $u.ExpMenu = $expMenu; $u.BtnExport = $btnExport
    $btnExport.Add_Click({ $script:SMUI.ExpMenu.Show($script:SMUI.BtnExport, 0, $script:SMUI.BtnExport.Height) })

    $u.BtnApply.Add_Click({ Invoke-SMMainApply })
    $u.BtnDiscard.Add_Click({ Invoke-SMMainDiscard })
    $btnRefresh.Add_Click({ Invoke-SMMainScan })
    $btnReport.Add_Click({ Invoke-SMMainReport })
    $btnUndo.Add_Click({ Invoke-SMMainUndo })
    $btnHist.Add_Click({ Show-SMLogViewer })
    $btnHelp.Add_Click({ Show-SMLegendDialog })
    $u.Preset.Add_SelectedIndexChanged({ if (-not $script:SMUI.Loading) { Update-SMMainGrid } })

    # ---- status ----
    $statusStrip = New-Object Windows.Forms.StatusStrip
    $statusStrip.BackColor = $T.Panel; $statusStrip.SizingGrip = $false; $statusStrip.Padding = New-Object Windows.Forms.Padding(10, 3, 10, 3)
    $u.Status = New-Object Windows.Forms.ToolStripStatusLabel
    $u.Status.ForeColor = $T.Text; $u.Status.Font = $T.Mono; $u.Status.Spring = $true; $u.Status.TextAlign = 'MiddleLeft'; $u.Status.Text = '  READY.'
    $u.Progress = New-Object Windows.Forms.ToolStripProgressBar
    $u.Progress.Width = 260; $u.Progress.Visible = $false
    $u.CancelScan = New-Object Windows.Forms.ToolStripStatusLabel
    $u.CancelScan.Text = 'Cancel scan'; $u.CancelScan.IsLink = $true; $u.CancelScan.LinkColor = $T.Ink; $u.CancelScan.Visible = $false
    $u.CancelScan.AccessibleName = 'Cancel the current scan'
    $u.CancelScan.Add_Click({ if ($script:SMUI.Scanning) { Stop-SMInventoryScan -Job $script:SMUI.ScanJob; $script:SMUI.Status.Text = '  Cancelling scan...' } })
    $u.Warnings = New-Object Windows.Forms.ToolStripStatusLabel
    $u.Warnings.Text = 'Scan details'; $u.Warnings.IsLink = $true; $u.Warnings.LinkColor = $T.Warn; $u.Warnings.Visible = $false
    $u.Warnings.Add_Click({ [void][Windows.Forms.MessageBox]::Show($script:SMUI.ScanNotice, 'Scan details', 'OK', 'Information') })
    $githubLink = New-Object Windows.Forms.ToolStripStatusLabel
    $githubLink.Text = 'GitHub'; $githubLink.IsLink = $true; $githubLink.Font = $T.Mono
    $githubLink.LinkColor = $T.Text; $githubLink.ActiveLinkColor = $T.Accent; $githubLink.LinkVisited = $false
    $githubLink.ToolTipText = 'https://github.com/StarskreamEXE/Windows-Startup-App-Manager'
    $githubLink.AccessibleName = 'Open Startup Manager on GitHub'
    $githubLink.Margin = New-Object Windows.Forms.Padding(12, 0, 0, 0)
    $githubIcon = Join-Path $script:SM.Root 'assets\github-mark.png'
    if (Test-Path -LiteralPath $githubIcon) {
        try { $githubLink.Image = [Drawing.Image]::FromFile($githubIcon) }
        catch { Write-SMLog -Level WARN -Message "Could not load GitHub icon: $($_.Exception.Message)" }
    }
    $githubLink.Add_Click({
        try { Start-Process 'https://github.com/StarskreamEXE/Windows-Startup-App-Manager' -ErrorAction Stop }
        catch { $script:SMUI.Status.Text = '  Could not open GitHub: ' + $_.Exception.Message }
    })
    $githubLink.Add_Disposed({ if ($null -ne $this.Image) { $this.Image.Dispose() } })
    $u.ZoomReset = New-Object Windows.Forms.ToolStripStatusLabel
    $u.ZoomReset.Text = ([char]0x21BA) + ' 100%'; $u.ZoomReset.IsLink = $true; $u.ZoomReset.Font = $T.Mono
    $u.ZoomReset.LinkColor = $T.Ink; $u.ZoomReset.ActiveLinkColor = $T.Ink
    $u.ZoomReset.ToolTipText = 'Reset zoom (Ctrl+0). Ctrl+mouse wheel to zoom.'
    $u.ZoomReset.AccessibleName = 'Reset zoom to 100 percent'
    $u.ZoomReset.Add_Click({ Set-SMMainZoom -Zoom 1.0 })
    $statusStrip.Items.AddRange(@($u.Status, $u.Progress, $u.CancelScan, $u.Warnings, $u.ZoomReset, $githubLink))
    $u.ScanTimer = New-Object Windows.Forms.Timer
    $u.ScanTimer.Interval = 150
    $u.ScanTimer.Add_Tick({ Complete-SMMainScan })
    $u.Toolbar = $bar; $u.Menu = $menu

    # ---- split: grid / details ----
    $split = New-Object Windows.Forms.SplitContainer
    $split.Dock = 'Fill'; $split.Orientation = 'Horizontal'; $split.BackColor = $T.Bg; $split.SplitterWidth = 10
    $split.Panel1.Padding = New-Object Windows.Forms.Padding(14, 10, 14, 0)
    $split.Panel2.Padding = New-Object Windows.Forms.Padding(14, 0, 14, 14)
    $split.Panel1.BackColor = $T.Bg; $split.Panel2.BackColor = $T.Bg

    $grid = New-Object Windows.Forms.DataGridView
    Enable-SMDarkScrollbars -Control $grid
    $grid.Dock = 'Fill'
    $grid.AllowUserToAddRows = $false; $grid.AllowUserToDeleteRows = $false; $grid.AllowUserToResizeRows = $false
    $grid.RowHeadersVisible = $false; $grid.SelectionMode = 'FullRowSelect'; $grid.MultiSelect = $true
    $grid.AutoSizeColumnsMode = 'Fill'; $grid.AutoGenerateColumns = $false
    $grid.ScrollBars = 'Vertical'; $grid.AllowUserToResizeColumns = $false
    $grid.BackgroundColor = $T.Grid; $grid.GridColor = $T.Border; $grid.BorderStyle = 'FixedSingle'
    $grid.CellBorderStyle = 'Single'
    $grid.EnableHeadersVisualStyles = $false
    $grid.ColumnHeadersBorderStyle = 'Single'
    $grid.ColumnHeadersDefaultCellStyle.BackColor = $T.Panel; $grid.ColumnHeadersDefaultCellStyle.ForeColor = $T.Ink
    $grid.ColumnHeadersDefaultCellStyle.Font = $T.Label
    $grid.ColumnHeadersHeight = 30
    $grid.DefaultCellStyle.BackColor = $T.Grid; $grid.DefaultCellStyle.ForeColor = $T.Text
    $grid.DefaultCellStyle.SelectionBackColor = $T.Ink; $grid.DefaultCellStyle.SelectionForeColor = $T.Paper
    $grid.RowTemplate.Height = 26
    $grid.EditMode = 'EditOnEnter'
    $u.Grid = $grid

    $dt = New-Object System.Data.DataTable
    [void]$dt.Columns.Add('On', [bool]); [void]$dt.Columns.Add('Pending', [string]); [void]$dt.Columns.Add('Risk', [string]); [void]$dt.Columns.Add('Flags', [string])
    [void]$dt.Columns.Add('Name', [string]); [void]$dt.Columns.Add('What', [string]); [void]$dt.Columns.Add('Publisher', [string]); [void]$dt.Columns.Add('Signed', [string])
    [void]$dt.Columns.Add('BootMs', [int]); [void]$dt.Columns.Add('Category', [string]); [void]$dt.Columns.Add('Command', [string]); [void]$dt.Columns.Add('Path', [string]); [void]$dt.Columns.Add('Id', [int])
    $u.Table = $dt

    $cOn = New-Object Windows.Forms.DataGridViewCheckBoxColumn; $cOn.Name = 'On'; $cOn.HeaderText = 'On'; $cOn.DataPropertyName = 'On'; $cOn.Width = 40
    $grid.Columns.Add($cOn) | Out-Null
    foreach ($spec in @(@('Pending','Pending',70), @('Risk','Risk',80), @('Flags','Flags',150), @('Name','Name',240), @('What','What it is',260), @('Publisher','Publisher',160),
                        @('Signed','Signed',70), @('BootMs','Boot ms',70), @('Category','Where it lives',180), @('Command','Command',380), @('Path','Path',300), @('Id','Id',40))) {
        $c = New-Object Windows.Forms.DataGridViewTextBoxColumn
        $c.Name = $spec[0]; $c.HeaderText = ([string]$spec[1]).ToUpper(); $c.DataPropertyName = $spec[0]; $c.FillWeight = $spec[2]; $c.ReadOnly = $true
        if ($spec[0] -eq 'BootMs') { $c.DefaultCellStyle.Alignment = 'MiddleRight' }
        $grid.Columns.Add($c) | Out-Null
    }
    $grid.Columns['Id'].Visible = $false
    foreach ($column in $grid.Columns) { $column.MinimumWidth = 24 }
    $grid.Columns['On'].AutoSizeMode = 'None'
    $grid.DataSource = $dt

    $grid.Add_CurrentCellDirtyStateChanged({ if ($script:SMUI.Grid.IsCurrentCellDirty) { $script:SMUI.Grid.CommitEdit([Windows.Forms.DataGridViewDataErrorContexts]::Commit) } })
    $grid.Add_CellValueChanged({
        param($s, $ev)
        $u = $script:SMUI
        if ($u.Loading -or $u.Scanning -or $u.Applying -or $ev.RowIndex -lt 0) { return }
        if ($u.Grid.Columns[$ev.ColumnIndex].Name -ne 'On') { return }
        $row = $u.Grid.Rows[$ev.RowIndex]
        $id = [int]$row.Cells['Id'].Value
        if (-not $u.ById.ContainsKey($id)) { return }
        $e = $u.ById[$id]
        $new = [bool]$row.Cells['On'].Value
        try {
            if ($e.Kind -eq 'Service' -and -not $u.AdvancedMode) { throw 'Enable advanced service changes in Tools first.' }
            Add-SMPendingChange -Entry $e -Enable $new
        } catch {
            $u.Loading = $true; $row.Cells['On'].Value = $e.Enabled; $u.Loading = $false
            $u.Status.Text = '  ' + $_.Exception.Message
            return
        }
        $u.Loading = $true; $row.Cells['Pending'].Value = (Get-SMPendingText $id); $u.Loading = $false
        Update-SMMainRowStyle $row
        Update-SMMainStatus
    })
    $grid.Add_DataBindingComplete({ if (-not $script:SMUI.Loading) { Update-SMMainStyles } })
    $grid.Add_Sorted({ Update-SMMainStyles })
    $grid.Add_SelectionChanged({ if (-not $script:SMUI.Loading) { Update-SMMainDetails } })
    $grid.Add_CellDoubleClick({ param($s, $ev) if ($ev.RowIndex -ge 0) { $sel = Get-SMMainSelectedEntries; if ($sel.Count) { Show-SMDetailsDialog -Entry $sel[0] } } })
    $grid.Add_DataError({ param($s, $ev) $ev.ThrowException = $false })

    $ctx = New-Object Windows.Forms.ContextMenuStrip
    $ctx.Items.AddRange(@(
        (New-SMMenuItem 'Stage: turn ON'  { Invoke-SMMainStage -Enable $true }),
        (New-SMMenuItem 'Stage: turn OFF' { Invoke-SMMainStage -Enable $false }),
        (New-Object Windows.Forms.ToolStripSeparator),
        (New-SMMenuItem 'Open file location' { Open-SMMainLocation }),
        (New-SMMenuItem 'Open in Task Scheduler / Services' { $sel = Get-SMMainSelectedEntries; if ($sel.Count) { switch ($sel[0].Kind) { 'Task' { Start-Process taskschd.msc } 'Service' { Start-Process services.msc } default { Open-SMMainLocation } } } }),
        (New-SMMenuItem 'Copy command' { $sel = Get-SMMainSelectedEntries; if ($sel.Count -and $sel[0].Command) { [Windows.Forms.Clipboard]::SetText([string]$sel[0].Command) } }),
        (New-SMMenuItem 'Copy path' { $sel = Get-SMMainSelectedEntries; if ($sel.Count -and $sel[0].ExePath) { [Windows.Forms.Clipboard]::SetText([string]$sel[0].ExePath) } }),
        (New-SMMenuItem 'Search the web for this' { $sel = Get-SMMainSelectedEntries; if ($sel.Count) { $q = if ($sel[0].ExePath) { [IO.Path]::GetFileName($sel[0].ExePath) } else { $sel[0].Name }; Start-Process ('https://www.bing.com/search?q=' + [uri]::EscapeDataString($q + ' startup')) } }),
        (New-Object Windows.Forms.ToolStripSeparator),
        (New-SMMenuItem 'Details...' { $sel = Get-SMMainSelectedEntries; if ($sel.Count) { Show-SMDetailsDialog -Entry $sel[0] } })
    ))
    $grid.ContextMenuStrip = $ctx
    $grid.Add_CellMouseDown({ param($s, $ev) if ($ev.Button -eq 'Right' -and $ev.RowIndex -ge 0) { $r = $script:SMUI.Grid.Rows[$ev.RowIndex]; if (-not $r.Selected) { $script:SMUI.Grid.ClearSelection(); $r.Selected = $true } } })

    # details: two filled columns inside a 1px-ink-bordered panel
    #   left  = what it is / what it does / if you disable it
    #   right = facts (publisher, signature, boot time, command, path, source) + provider detail
    $details = New-SMRichText; $details.Dock = 'Fill'; $details.BackColor = $T.Panel
    $facts   = New-SMRichText; $facts.Dock   = 'Fill'; $facts.BackColor   = $T.Panel
    $u.Details = $details; $u.Facts = $facts
    $detailsWrap = New-Object Windows.Forms.Panel
    $detailsWrap.Dock = 'Fill'; $detailsWrap.BackColor = $T.Ink; $detailsWrap.Padding = New-Object Windows.Forms.Padding(1)
    $cols = New-Object Windows.Forms.TableLayoutPanel
    $cols.Dock = 'Fill'; $cols.BackColor = $T.Panel; $cols.ColumnCount = 2; $cols.RowCount = 1
    [void]$cols.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent, 46)))
    [void]$cols.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent, 54)))
    $leftCell = New-Object Windows.Forms.Panel;  $leftCell.Dock = 'Fill';  $leftCell.BackColor = $T.Panel;  $leftCell.Padding = New-Object Windows.Forms.Padding(20, 14, 12, 14)
    $rightCell = New-Object Windows.Forms.Panel; $rightCell.Dock = 'Fill'; $rightCell.BackColor = $T.Panel; $rightCell.Padding = New-Object Windows.Forms.Padding(12, 14, 20, 14)
    # 1px ink divider between the columns
    $divider = New-Object Windows.Forms.Panel; $divider.Dock = 'Left'; $divider.Width = 1; $divider.BackColor = $T.Border
    $rightCell.Controls.Add($facts); $rightCell.Controls.Add($divider)
    $leftCell.Controls.Add($details)
    $cols.Controls.Add($leftCell, 0, 0); $cols.Controls.Add($rightCell, 1, 0)
    $u.DetailColumns = $cols; $u.FactsCell = $rightCell; $u.DetailsStacked = $false
    $detailsWrap.Controls.Add($cols)
    $split.Panel1.Controls.Add($grid)
    $split.Panel2.Controls.Add($detailsWrap)

    $mascot = Join-Path $script:SM.Root 'assets\skreambot.png'
    $brand = New-SMWordmark -Product 'STARTUP.' -Suffix 'MANAGER' -Tagline 'everything that starts with windows' -ImagePath $mascot
    $ico = Join-Path $script:SM.Root 'build\app.ico'
    if (Test-Path -LiteralPath $ico) {
        try { $form.Icon = New-Object Drawing.Icon($ico); $form.ShowIcon = $true }
        catch { Write-SMLog -Level WARN -Message "Could not load window icon: $($_.Exception.Message)" }
    } else { Write-SMLog -Level WARN -Message "Window icon not found: $ico" }
    Add-SMBlockShadows -Container $bar
    $form.Controls.Add($split)
    $form.Controls.Add($bar)
    $form.Controls.Add($brand)
    $form.Controls.Add($statusStrip)
    $form.Controls.Add($menu)
    $split.BringToFront()
    $u.Brand = $brand; $u.Zoom = 1.0; $u.LayoutBusy = $false
    if ($u.ReducedMotion) { $brand.Tag.Timer.Stop() }
    $u.Search.AccessibleName = 'Search startup entries'
    $u.Preset.AccessibleName = 'Filter startup entries'
    $grid.AccessibleName = 'Startup entries; Space stages the selected entry'
    $details.AccessibleName = 'Selected entry description and disable impact'
    $facts.AccessibleName = 'Selected entry evidence and configuration'
    $tabIndex = 0
    foreach ($control in $bar.Controls) { $control.TabIndex = $tabIndex; $tabIndex++; if (-not $control.AccessibleName) { $control.AccessibleName = $control.Text } }
    $u.ToolbarSizes = @($bar.Controls | ForEach-Object { @{ Control = $_; Width = $_.Width } })
    $u.ZoomTargets = @(Get-SMZoomTargets $form | ForEach-Object { @{ Target = $_; Font = $_.Font } })
    $u.BaseThemeFonts = @{}
    foreach ($name in @($T.Keys)) { if ($T[$name] -is [Drawing.Font]) { $u.BaseThemeFonts[$name] = $T[$name] } }
    $u.ZoomFonts = New-Object System.Collections.ArrayList
    $u.ZoomFilter = New-Object StartupManager.ZoomWheelFilter($form)
    $u.ZoomFilter.add_ZoomRequested({ param($steps) Set-SMMainZoom -Zoom ($script:SMUI.Zoom + $steps * 0.1) })
    [Windows.Forms.Application]::AddMessageFilter($u.ZoomFilter)
    $grid.Add_SizeChanged({ Update-SMMainLayout })
    $form.Add_DpiChanged({ Set-SMMainZoom -Zoom $script:SMUI.Zoom -Force })
    $form.Add_FormClosed({
        $script:SMUI.ScanTimer.Stop(); $script:SMUI.ScanTimer.Dispose()
        [Windows.Forms.Application]::RemoveMessageFilter($script:SMUI.ZoomFilter)
        foreach ($name in $script:SMUI.BaseThemeFonts.Keys) { $script:SMTheme[$name] = $script:SMUI.BaseThemeFonts[$name] }
    })

    # ---- keys ----
    $form.Add_KeyDown({
        param($s, $ev)
        $u = $script:SMUI
        if ($u.Scanning -or $u.Applying) {
            if ($ev.KeyCode -eq 'Escape' -and $u.Scanning) { Stop-SMInventoryScan -Job $u.ScanJob }
            return
        }
        if ($ev.Control -and $ev.KeyCode -eq 'S') { Invoke-SMMainApply; $ev.Handled = $true }
        elseif ($ev.Control -and $ev.KeyCode -eq 'Z') { Invoke-SMMainUndo; $ev.Handled = $true }
        elseif ($ev.Control -and $ev.KeyCode -eq 'F') { $u.Search.Focus(); $ev.Handled = $true }
        elseif ($ev.Control -and $ev.KeyCode -in @('D0', 'NumPad0')) { Set-SMMainZoom -Zoom 1.0; $ev.Handled = $true; $ev.SuppressKeyPress = $true }
        elseif ($ev.KeyCode -eq 'F5') { Invoke-SMMainScan; $ev.Handled = $true }
        elseif ($ev.KeyCode -eq 'F1') { Show-SMLegendDialog; $ev.Handled = $true }
        elseif (($ev.KeyCode -eq 'Space' -or $ev.KeyCode -eq 'Delete') -and $u.Grid.Focused -and $u.Grid.SelectedRows.Count -gt 0) {
            $sel = Get-SMMainSelectedEntries
            if ($sel.Count) { $cur = if ($script:SM.Pending.Contains([string]$sel[0].Id)) { $script:SM.Pending[[string]$sel[0].Id].To } else { $sel[0].Enabled }; Invoke-SMMainStage -Enable (-not $cur) }
            $ev.Handled = $true; $ev.SuppressKeyPress = $true
        }
    })

    $form.Add_FormClosing({
        param($s, $ev)
        if ($script:SMUI.Scanning) {
            $script:SMUI.CloseAfterScan = $true
            Stop-SMInventoryScan -Job $script:SMUI.ScanJob
            $ev.Cancel = $true
            return
        }
        $p = (Get-SMPendingChanges).Count
        if ($p -gt 0) {
            $a = [Windows.Forms.MessageBox]::Show("You have $p staged change(s) that were never applied.`n`nYes = Apply them now`nNo = Discard them`nCancel = go back", 'Unsaved changes', 'YesNoCancel', 'Warning')
            if ($a -eq 'Cancel') { $ev.Cancel = $true; return }
            if ($a -eq 'Yes') { Invoke-SMMainApply; if ((Get-SMPendingChanges).Count -gt 0) { $ev.Cancel = $true; return } }
            else { Clear-SMPendingChanges }
        }
        Write-SMLog -Level INFO -Message 'Startup Manager closed'
    })

    $u.Split = $split
    $form.Add_Shown({
        $sp = $script:SMUI.Split; $sp.SplitterDistance = [int]($sp.Height * $(if ($script:SMUI.DetailsStacked) { 0.60 } else { 0.68 }))
        $script:SMUI.Loading = $false
        Invoke-SMMainScan
        Set-SMMainZoom -Zoom $script:SMUI.SavedZoom -Force
        $flag = Join-Path $script:SM.LogDir '.legend-shown'
        if (-not (Test-Path -LiteralPath $flag)) { Show-SMLegendDialog; Set-Content -LiteralPath $flag -Value (Get-Date).ToString('o') }
    })

    if ($AutoCloseMs -gt 0) {
        $timer = New-Object Windows.Forms.Timer; $timer.Interval = $AutoCloseMs
        $timer.Add_Tick({ $script:SMUI.Form.Close() }); $timer.Start()
    }
    try { [void]$form.ShowDialog() }
    finally {
        if ($null -ne $u.ScanJob) { Close-SMInventoryScan -Job $u.ScanJob }
        [Windows.Forms.Application]::RemoveMessageFilter($u.ZoomFilter)
        $form.Dispose()
        foreach ($font in $u.ZoomFonts) { $font.Dispose() }
    }
}
