# Aggregates every provider, enriches with Analysis, and dispatches state changes.

Set-StrictMode -Version 2.0

function Get-SMInventory {
    [CmdletBinding()]
    param([scriptblock] $Progress = $null, [scriptblock] $Cancelled = $null)

    $script:SM.ScanWarnings = @()
    $script:SM.ScanComplete = $false
    Clear-SMFileFactsCache

    $collectors = @(
        @{ Name = 'Run keys';        Fn = 'Get-SMRunKeyEntries' }
        @{ Name = 'Startup folders'; Fn = 'Get-SMStartupFolderEntries' }
        @{ Name = 'Scheduled tasks'; Fn = 'Get-SMScheduledTaskEntries' }
        @{ Name = 'Services';        Fn = 'Get-SMServiceEntries' }
        @{ Name = 'Store apps';      Fn = 'Get-SMStoreAppEntries' }
    )
    $all = New-Object System.Collections.ArrayList
    $step = 0
    foreach ($c in $collectors) {
        if ($Cancelled -and (& $Cancelled)) { throw [OperationCanceledException]::new('Scan cancelled.') }
        $step++
        if ($Progress) { & $Progress $step ($collectors.Count + 1) "Scanning $($c.Name)..." }
        try {
            # providers may `return ,$array`; piping enumerates whatever shape comes back
            $providerErrors = @()
            $items = @(& $c.Fn -ErrorVariable +providerErrors | ForEach-Object { $_ })
            foreach ($providerError in $providerErrors) { $script:SM.ScanWarnings += "$($c.Name): $providerError" }
            foreach ($i in $items) {
                if ($null -eq $i) { continue }
                if ($i -is [array]) { foreach ($j in $i) { if ($null -ne $j) { [void]$all.Add($j) } } }
                else { [void]$all.Add($i) }
            }
        } catch {
            $script:SM.ScanWarnings += "$($c.Name): $($_.Exception.Message)"
            Write-SMLog -Level ERROR -Message "Collector $($c.Fn) failed: $($_.Exception.Message)"
        }
    }

    if ($Progress) { & $Progress $collectors.Count ($collectors.Count + 1) 'Reading boot performance log...' }
    $perf = @{}
    try { $perf = Get-SMBootPerf } catch { Write-SMLog -Level WARN -Message "Boot perf unavailable: $($_.Exception.Message)" }
    if ($null -eq $perf) { $perf = @{} }
    $script:SM.BootPerf = $perf

    $total = $all.Count
    $pathCounts = @{}
    foreach ($entry in $all) {
        $key = ConvertTo-SMBootPath $entry.ExePath
        if ($key) { if (-not $pathCounts.ContainsKey($key)) { $pathCounts[$key] = 0 }; $pathCounts[$key]++ }
    }
    $id = 0
    foreach ($e in $all) {
        if ($Cancelled -and (& $Cancelled)) { throw [OperationCanceledException]::new('Scan cancelled.') }
        $id++
        $e.Id = $id
        if ($Progress -and ($id % 5 -eq 0 -or $id -eq $total)) { & $Progress $id $total "Analysing $id of $total : $($e.Name)" }
        try {
            if (-not [string]::IsNullOrWhiteSpace($e.ExePath)) {
                $f = Get-SMFileFacts -Path $e.ExePath
                $e.Exists      = [bool]$f.Exists
                $e.Publisher   = [string]$f.Publisher
                $e.Product     = [string]$f.Product
                $e.FileVersion = [string]$f.FileVersion
                $e.SizeKB      = [int]$f.SizeKB
                $e.SigStatus   = [string]$f.SigStatus
                $e.SigSigner   = [string]$f.SigSigner
                $key = ConvertTo-SMBootPath $e.ExePath
                $pathCount = 0
                if ($key -and $pathCounts.ContainsKey($key)) { $pathCount = $pathCounts[$key] }
                Set-SMBootEvidence -Entry $e -Perf $perf -PathCount $pathCount
            }
            $r = Get-SMRiskAssessment -Entry $e
            $e.Risk          = $r.Risk
            $e.Flags         = [string[]]$r.Flags
            $e.What          = $r.What
            $e.Explain       = $r.Explain
            $e.DisableEffect = $r.DisableEffect
            $e.RiskEvidence = $r.RiskEvidence
            $e.SecurityFlags = $r.SecurityFlags
        } catch {
            $script:SM.ScanWarnings += "Analysis for '$($e.Name)': $($_.Exception.Message)"
            Write-SMLog -Level WARN -Message "Analysis failed for '$($e.Name)': $($_.Exception.Message)"
        }
    }

    $arr = $all.ToArray()
    $script:SM.Inventory = $arr
    $counts = @{}
    foreach ($e in $arr) { if ($counts.ContainsKey($e.Kind)) { $counts[$e.Kind]++ } else { $counts[$e.Kind] = 1 } }
    $summary = ($counts.Keys | Sort-Object | ForEach-Object { "$_=$($counts[$_])" }) -join ' '
    $script:SM.ScanComplete = ($script:SM.ScanWarnings.Count -eq 0)
    Write-SMLog -Level INFO -Message "Scan finished: $total entries ($summary), $($script:SM.ScanWarnings.Count) warnings"
    return ,$arr
}

function Set-SMEntryState {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Entry, [Parameter(Mandatory)] [bool] $Enable)
    switch ([string]$Entry.Kind) {
        'RunKey'  { Set-SMRunKeyState        -Entry $Entry -Enable $Enable }
        'Folder'  { Set-SMStartupFolderState -Entry $Entry -Enable $Enable }
        'Task'    { Set-SMScheduledTaskState -Entry $Entry -Enable $Enable }
        'Service' { Set-SMServiceState       -Entry $Entry -Enable $Enable }
        'Uwp'     { Set-SMStoreAppState      -Entry $Entry -Enable $Enable }
        default   { throw 'This entry cannot be toggled.' }
    }
}
