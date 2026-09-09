# Standalone HTML report. Dot-source after src/Export/Export.ps1 - it reuses
# that file's escaping, style, sort script and table builder.
# No side effects except function/variable definitions.

Set-StrictMode -Version 2.0

function Get-SMReportMachineFacts {
    <#
    .SYNOPSIS
        Machine / user / OS facts for the report header. Never throws - a CIM
        failure just leaves the OS fields as 'Unknown'.
    #>
    [CmdletBinding()]
    param()
    $facts = [ordered]@{
        Machine   = [string]$env:COMPUTERNAME
        User      = [string]$env:USERNAME
        OSCaption = 'Unknown'
        OSVersion = 'Unknown'
        Generated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    }
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        if ($os) {
            if ($os.Caption) { $facts.OSCaption = [string]$os.Caption }
            if ($os.Version) { $facts.OSVersion = [string]$os.Version }
        }
    }
    catch {
        $facts.OSCaption = 'Unknown'
        $facts.OSVersion = 'Unknown'
    }
    return $facts
}

function Get-SMReportBootTiming {
    <#
    .SYNOPSIS
        Effective boot timing for one entry: the entry's own measurement when it
        has one, otherwise the boot-perf table keyed by executable file name.
        Returns @{TotalMs;DegradeMs} with -1 meaning "no data".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)] $Entry,
        [Parameter(Position = 1)] $BootPerf
    )
    $total = -1
    $degrade = -1
    try { $total = [int](Get-SMPropertyValue $Entry 'BootMs' -Default -1) } catch { $total = -1 }
    try { $degrade = [int](Get-SMPropertyValue $Entry 'DegradeMs' -Default -1) } catch { $degrade = -1 }

    return @{ TotalMs = $total; DegradeMs = $degrade }
}

function Get-SMReportRiskBreakdown {
    <# Risk level counts in severity order, with share of total. #>
    [CmdletBinding()]
    param([Parameter(Position = 0)] [AllowNull()] [AllowEmptyCollection()] $Entries)

    $list = @(@($Entries) | Where-Object { $null -ne $_ })
    $counts = [ordered]@{}
    foreach ($level in $script:SMRiskLevels) { $counts[$level] = 0 }
    foreach ($e in $list) {
        $r = [string](Get-SMPropertyValue $e 'Risk' -Default 'Unknown')
        if (-not $r) { $r = 'Unknown' }
        if (-not $counts.Contains($r)) { $counts[$r] = 0 }
        $counts[$r] = [int]$counts[$r] + 1
    }
    $total = $list.Count
    $rows = @()
    foreach ($k in $counts.Keys) {
        if ([int]$counts[$k] -eq 0) { continue }
        $share = if ($total -gt 0) { '{0:N1}%' -f (100.0 * $counts[$k] / $total) } else { '0.0%' }
        $rows += [pscustomobject][ordered]@{ Risk = $k; Count = [int]$counts[$k]; Share = $share }
    }
    return $rows
}

function Get-SMReportCategoryBreakdown {
    <# Category counts, biggest first. #>
    [CmdletBinding()]
    param([Parameter(Position = 0)] [AllowNull()] [AllowEmptyCollection()] $Entries)

    $list = @(@($Entries) | Where-Object { $null -ne $_ })
    $counts = @{}
    foreach ($e in $list) {
        $c = [string](Get-SMPropertyValue $e 'Category')
        if (-not $c) { $c = '(unknown)' }
        if (-not $counts.ContainsKey($c)) { $counts[$c] = 0 }
        $counts[$c] = [int]$counts[$c] + 1
    }
    $total = $list.Count
    $rows = @()
    foreach ($k in ($counts.Keys | Sort-Object -Property @{ Expression = { $counts[$_] }; Descending = $true }, @{ Expression = { $_ } })) {
        $share = if ($total -gt 0) { '{0:N1}%' -f (100.0 * $counts[$k] / $total) } else { '0.0%' }
        $rows += [pscustomobject][ordered]@{ Category = $k; Count = [int]$counts[$k]; Share = $share }
    }
    return $rows
}

function Get-SMReportSlowStarters {
    <# Top N entries by measured boot time, slowest first. Unmeasured are skipped. #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)] [AllowNull()] [AllowEmptyCollection()] $Entries,
        [Parameter(Position = 1)] $BootPerf,
        [int] $Top = 15
    )
    $rows = @()
    foreach ($e in @(@($Entries) | Where-Object { $null -ne $_ })) {
        $t = Get-SMReportBootTiming $e $BootPerf
        if ([int]$t.TotalMs -lt 0) { continue }
        $rows += [pscustomobject][ordered]@{
            Name      = [string](Get-SMPropertyValue $e 'Name')
            What      = [string](Get-SMPropertyValue $e 'What')
            Category  = [string](Get-SMPropertyValue $e 'Category')
            BootMs    = [int]$t.TotalMs
            MeasuredAt = [string](Get-SMPropertyValue $e 'BootMeasuredAt')
            Attribution = [string](Get-SMPropertyValue $e 'BootConfidence')
            DegradeMs = $(if ([int]$t.DegradeMs -ge 0) { [int]$t.DegradeMs } else { '' })
        }
    }
    return @($rows | Sort-Object -Property BootMs -Descending | Select-Object -First $Top)
}

function Get-SMReportProblems {
    <# Broken / Suspicious entries plus anything flagged BAD-SIG, UNSIGNED or MISSING. #>
    [CmdletBinding()]
    param([Parameter(Position = 0)] [AllowNull()] [AllowEmptyCollection()] $Entries)

    $badFlags = @('BAD-SIG', 'UNSIGNED', 'MISSING')
    $rows = @()
    foreach ($e in @(@($Entries) | Where-Object { $null -ne $_ })) {
        $risk = [string](Get-SMPropertyValue $e 'Risk' -Default 'Unknown')
        $flags = @(Get-SMPropertyValue $e 'Flags' -Default @())
        $hit = ($risk -eq 'Broken' -or $risk -eq 'Suspicious')
        foreach ($f in $flags) { if ($badFlags -contains [string]$f) { $hit = $true } }
        if (-not $hit) { continue }
        $rows += [pscustomobject][ordered]@{
            Name          = [string](Get-SMPropertyValue $e 'Name')
            Risk          = $risk
            Flags         = ($flags -join ', ')
            What          = [string](Get-SMPropertyValue $e 'What')
            DisableEffect = [string](Get-SMPropertyValue $e 'DisableEffect')
            ExePath       = [string](Get-SMPropertyValue $e 'ExePath')
        }
    }
    return $rows
}

function Get-SMReportChangeRows {
    <# Last N change records, newest last, flattened for the changes table. #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)] [AllowNull()] [AllowEmptyCollection()] $ChangeRecords,
        [int] $Last = 50
    )
    $arrow = [string][char]0x2192
    $all = @(@($ChangeRecords) | Where-Object { $null -ne $_ })
    if ($all.Count -gt $Last) { $all = @($all[($all.Count - $Last)..($all.Count - 1)]) }

    $rows = @()
    foreach ($r in $all) {
        $from = [bool](Get-SMPropertyValue $r 'from' -Default $false)
        $to = [bool](Get-SMPropertyValue $r 'to' -Default $false)
        $ok = [bool](Get-SMPropertyValue $r 'ok' -Default $false)
        $rows += [pscustomobject][ordered]@{
            When   = [string](Get-SMPropertyValue $r 'ts')
            Action = [string](Get-SMPropertyValue $r 'action')
            Name   = [string](Get-SMPropertyValue $r 'name')
            Change = ('{0} {1} {2}' -f $(if ($from) { 'ON' } else { 'OFF' }), $arrow, $(if ($to) { 'ON' } else { 'OFF' }))
            Result = $(if ((Get-SMPropertyValue $r 'action') -in @('prepare','prepare-undo')) { 'prepared' } elseif (Get-SMPropertyValue $r 'needsRecovery' $false) { 'recovery required' } elseif ($ok) { 'ok' } else { 'failed' })
            Error  = [string](Get-SMPropertyValue $r 'error')
        }
    }
    return $rows
}

function New-SMReportInventoryRows {
    <#
        Flat inventory rows for the report: the export column set plus a
        pre-built collapsible Details cell holding Explain and DisableEffect.
    #>
    [CmdletBinding()]
    param([Parameter(Position = 0)] [AllowNull()] [AllowEmptyCollection()] $Entries)

    $rows = @()
    foreach ($e in @(@($Entries) | Where-Object { $null -ne $_ })) {
        $flat = ConvertTo-SMFlatEntry $e
        $explain = ConvertTo-SMHtmlText ([string](Get-SMPropertyValue $e 'Explain'))
        $effect = ConvertTo-SMHtmlText ([string](Get-SMPropertyValue $e 'DisableEffect'))
        if (-not $explain) { $explain = '(no description available)' }
        if (-not $effect) { $effect = '(effect not known)' }
        $details = '<details><summary>More</summary><p>' + $explain +
                   '</p><p><strong>If you disable this:</strong> ' + $effect + '</p></details>'
        $props = [ordered]@{}
        foreach ($c in $script:SMExportColumns) { $props[$c] = (Get-SMPropertyValue $flat $c) }
        $props['Details'] = $details
        $rows += [pscustomobject]$props
    }
    return $rows
}

function New-SMReport {
    <#
    .SYNOPSIS
        Writes a standalone, printable dark-themed HTML report to $Path and
        returns the path.
    .DESCRIPTION
        Sections: header, "Windows Settings shows only N of M" callout, risk and
        category breakdowns, slowest starters, problems, full inventory, recent
        changes. Inline CSS and JS only - no external assets, no network.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyCollection()] $Entries,
        [AllowNull()] $BootPerf = @{},
        [AllowNull()] [AllowEmptyCollection()] $ChangeRecords = @(),
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Path,
        [switch] $ShareSafe,
        [string[]] $ScanWarnings = @()
    )

    Initialize-SMExportDirectory -Path $Path

    if ($ShareSafe) {
        $Entries = @(ConvertTo-SMShareSafeEntries -Entries $Entries)
        $ChangeRecords = @()
        $BootPerf = @{}
        $ScanWarnings = @($ScanWarnings | ForEach-Object { 'A scan source was unavailable; inventory may be incomplete.' } | Select-Object -Unique)
    }

    $list = @(@($Entries) | Where-Object { $null -ne $_ })
    $total = $list.Count
    $settingsVisible = @($list | Where-Object {
            $k = [string](Get-SMPropertyValue $_ 'Kind')
            $k -eq 'RunKey' -or $k -eq 'Folder'
        }).Count

    $facts = if ($ShareSafe) {
        @{ Machine = 'Not included'; User = 'Not included'; OSCaption = 'Windows'; OSVersion = 'Not included'; Generated = (Get-Date).ToString('yyyy-MM-dd') }
    } else { Get-SMReportMachineFacts }
    $riskRows = Get-SMReportRiskBreakdown $list
    $catRows = Get-SMReportCategoryBreakdown $list
    $slowRows = Get-SMReportSlowStarters $list $BootPerf -Top 15
    $problemRows = Get-SMReportProblems $list
    $invRows = New-SMReportInventoryRows $list
    $changeRows = Get-SMReportChangeRows $ChangeRecords -Last 50

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<!DOCTYPE html>')
    [void]$sb.AppendLine('<html lang="en"><head><meta charset="utf-8">')
    [void]$sb.AppendLine('<title>Startup Manager Report</title>')
    [void]$sb.AppendLine('<style>')
    [void]$sb.AppendLine((Get-SMHtmlStyle))
    [void]$sb.AppendLine('</style></head><body>')

    # 1 - header
    [void]$sb.AppendLine((Get-SMHtmlWordmark -Suffix 'REPORT'))
    [void]$sb.AppendLine('<p class="meta">Machine: <strong>' + (ConvertTo-SMHtmlText $facts.Machine) +
        '</strong> &middot; User: <strong>' + (ConvertTo-SMHtmlText $facts.User) + '</strong></p>')
    [void]$sb.AppendLine('<p class="meta">OS: ' + (ConvertTo-SMHtmlText $facts.OSCaption) +
        ' (version ' + (ConvertTo-SMHtmlText $facts.OSVersion) + ')</p>')
    [void]$sb.AppendLine('<p class="meta">Generated: ' + (ConvertTo-SMHtmlText $facts.Generated) +
        ' &middot; Total entries: <strong>' + $total + '</strong></p>')

    # 2 - callout
    [void]$sb.AppendLine('<div class="callout">This inventory covers registry entries, startup folders, scheduled tasks, services and Store app tasks. It is not a measurement of the entries currently shown by Windows Settings.</div>')
    foreach ($warning in $ScanWarnings) { [void]$sb.AppendLine('<p class="bad">Incomplete scan: ' + (ConvertTo-SMHtmlText $warning) + '</p>') }
    if ($ShareSafe) { [void]$sb.AppendLine('<p class="meta">Share-safe report: names, paths, commands, machine identity and change history are omitted. Review before sharing.</p>') }

    # 3 - breakdowns
    [void]$sb.AppendLine('<h2>Risk breakdown</h2>')
    [void]$sb.AppendLine((New-SMHtmlTable -Objects $riskRows -Columns @('Risk', 'Count', 'Share') `
                -NumericColumns @('Count') -RiskColumn 'Risk' -EmptyText 'No entries to summarise.'))
    [void]$sb.AppendLine('<h2>Category breakdown</h2>')
    [void]$sb.AppendLine((New-SMHtmlTable -Objects $catRows -Columns @('Category', 'Count', 'Share') `
                -NumericColumns @('Count') -EmptyText 'No entries to summarise.'))

    # 4 - slowest starters
    [void]$sb.AppendLine('<h2>Slowest starters</h2>')
    [void]$sb.AppendLine('<p class="meta">Top 15 by latest attributable measurement in the last 30 days. Shared hosts and entries without a reliable path match are excluded. Timings are not additive or guaranteed boot-time savings.</p>')
    [void]$sb.AppendLine((New-SMHtmlTable -Objects $slowRows `
                -Columns @('Name', 'What', 'Category', 'BootMs', 'DegradeMs', 'MeasuredAt', 'Attribution') `
                -Headers @('Name', 'What it is', 'Where it lives', 'Boot ms', 'Degradation ms', 'Measured at', 'Attribution') `
                -NumericColumns @('BootMs', 'DegradeMs') `
                -EmptyText 'No boot timing data was available for these entries.'))

    # 5 - problems
    [void]$sb.AppendLine('<h2>Problems</h2>')
    [void]$sb.AppendLine('<p class="meta">Broken, suspicious, unsigned, badly signed or missing items.</p>')
    [void]$sb.AppendLine((New-SMHtmlTable -Objects $problemRows `
                -Columns @('Name', 'Risk', 'Flags', 'What', 'DisableEffect', 'ExePath') `
                -Headers @('Name', 'Risk', 'Flags', 'What it is', 'If you disable this', 'Path') `
                -RiskColumn 'Risk' -EmptyText 'No problems found.'))

    # 6 - full inventory
    [void]$sb.AppendLine('<h2>Full inventory</h2>')
    [void]$sb.AppendLine((New-SMHtmlTable -Objects $invRows `
                -Columns (@($script:SMExportColumns) + 'Details') `
                -NumericColumns @('BootMs') -RawHtmlColumns @('Details') -RiskColumn 'Risk' `
                -EmptyText 'No startup entries were found.'))

    # 7 - recent changes
    [void]$sb.AppendLine('<h2>Recent changes</h2>')
    [void]$sb.AppendLine('<p class="meta">The last 50 applied or undone changes, oldest first.</p>')
    [void]$sb.AppendLine((New-SMHtmlTable -Objects $changeRows `
                -Columns @('When', 'Action', 'Name', 'Change', 'Result', 'Error') `
                -EmptyText 'No changes have been applied yet.'))

    [void]$sb.AppendLine((Get-SMHtmlSortScript))
    [void]$sb.AppendLine('</body></html>')

    Set-Content -LiteralPath $Path -Value $sb.ToString() -Encoding UTF8
    Write-SMExportLog -Message ('Wrote report with {0} entries and {1} change records to {2}' -f $total, @($changeRows).Count, $Path)
    return $Path
}
