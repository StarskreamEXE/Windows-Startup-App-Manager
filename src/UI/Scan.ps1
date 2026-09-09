Set-StrictMode -Version 2.0

function Start-SMInventoryScan {
    param(
        [Parameter(Mandatory)] [string] $Root,
        [Parameter(Mandatory)] [hashtable] $State,
        [string[]] $SourceFiles = @(
            'src/Core/Contracts.ps1','src/Core/Logging.ps1','src/Core/Paths.ps1',
            'src/Providers/StartupApproved.ps1','src/Providers/RunKeys.ps1','src/Providers/StartupFolders.ps1',
            'src/Providers/ScheduledTasks.ps1','src/Providers/Services.ps1','src/Providers/StoreApps.ps1',
            'src/Analysis/FileFacts.ps1','src/Analysis/BootPerf.ps1','src/Analysis/KnownApps.ps1','src/Analysis/Risk.ps1',
            'src/Engine/Inventory.ps1'
        )
    )
    $shared = [hashtable]::Synchronized(@{ Cancelled = $false; Label = 'Starting scan...'; Done = 0; Total = 1 })
    $workerState = $State.Clone()
    $workerState.Inventory = @(); $workerState.Pending = [ordered]@{}; $workerState.BootPerf = @{}
    $workerState.ScanWarnings = @(); $workerState.ScanComplete = $false
    $runspace = [RunspaceFactory]::CreateRunspace()
    $runspace.ApartmentState = 'STA'
    $runspace.ThreadOptions = 'ReuseThread'
    $shell = [PowerShell]::Create()
    try {
        $runspace.Open()
        $shell.Runspace = $runspace
        $worker = {
            param($Root,$State,$Shared,$SourceFiles)
            $ErrorActionPreference = 'Stop'
            foreach ($file in $SourceFiles) { . (Join-Path $Root $file) }
            $script:SM = $State
            $inventory = Get-SMInventory -Progress {
                param($done,$total,$label)
                $Shared.Done = $done; $Shared.Total = $total; $Shared.Label = $label
                if ($Shared.Cancelled) { throw (New-Object OperationCanceledException) }
            } -Cancelled { $Shared.Cancelled }
            if ($Shared.Cancelled) { throw (New-Object OperationCanceledException) }
            [pscustomobject]@{ Inventory = @($inventory); BootPerf = $script:SM.BootPerf; ScanWarnings = @($script:SM.ScanWarnings); ScanComplete = $script:SM.ScanComplete }
        }
        [void]$shell.AddScript($worker.ToString()).AddArgument($Root).AddArgument($workerState).AddArgument($shared).AddArgument($SourceFiles)
        $handle = $shell.BeginInvoke()
        return @{ Shell = $shell; Runspace = $runspace; Handle = $handle; Shared = $shared; StopHandle = $null }
    } catch { $shell.Dispose(); $runspace.Dispose(); throw }
}

function Stop-SMInventoryScan {
    param([Parameter(Mandatory)] [hashtable] $Job)
    $Job.Shared.Cancelled = $true
    if (-not $Job.Handle.IsCompleted -and $null -eq $Job.StopHandle) { $Job.StopHandle = $Job.Shell.BeginStop($null, $null) }
}

function Complete-SMInventoryScan {
    param([Parameter(Mandatory)] [hashtable] $Job)
    if (-not $Job.Handle.IsCompleted) { throw 'Scan is still running.' }
    $output = $Job.Shell.EndInvoke($Job.Handle)
    if ($Job.Shared.Cancelled) { throw (New-Object OperationCanceledException) }
    if ($Job.Shell.HadErrors) { throw ($Job.Shell.Streams.Error | Out-String) }
    if ($output.Count -ne 1) { throw 'Scan returned an invalid result.' }
    return $output[0]
}

function Close-SMInventoryScan {
    param([Parameter(Mandatory)] [hashtable] $Job)
    if (-not $Job.Handle.IsCompleted) { Stop-SMInventoryScan -Job $Job; $Job.Shell.Stop() }
    if ($null -ne $Job.StopHandle) { $Job.Shell.EndStop($Job.StopHandle) }
    $Job.Shell.Dispose()
    $Job.Runspace.Dispose()
}
