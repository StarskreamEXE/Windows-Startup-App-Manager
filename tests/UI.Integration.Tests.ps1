Set-StrictMode -Version 2.0
$integrationRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $integrationRoot 'src/UI/Scan.ps1')
. (Join-Path $integrationRoot 'src/UI/MainForm.ps1')

. (Join-Path $integrationRoot 'src/Core/Logging.ps1')

Describe 'Inventory scan integration' {
    It 'publishes collected inventory and warnings after a handled provider error' {
        Set-Content (Join-Path $TestDrive 'inventory.ps1') @'
function Get-SMInventory {
    param($Progress,$Cancelled)
    try { Get-Item -LiteralPath (Join-Path $env:TEMP ([guid]::NewGuid().ToString())) -ErrorAction Stop } catch { }
    $script:SM.ScanWarnings = @('Provider unavailable')
    $script:SM.ScanComplete = $false
    $script:SM.BootPerf = @{}
    return ,@([pscustomobject]@{Name='collected fixture'})
}
'@
        $job = Start-SMInventoryScan -Root $TestDrive -State @{} -SourceFiles @('inventory.ps1')
        try {
            $job.Handle.AsyncWaitHandle.WaitOne(10000) | Should Be $true
            $result = Complete-SMInventoryScan $job
            $result.Inventory[0].Name | Should Be 'collected fixture'
            $result.ScanWarnings[0] | Should Be 'Provider unavailable'
        } finally { Close-SMInventoryScan $job }
    }
}

Describe 'Stale inventory safeguards' {
    BeforeEach {
        $timer = New-Object PSObject
        $timer | Add-Member ScriptMethod Stop { }
        $script:SM = @{ Inventory=@('previous'); Pending=[ordered]@{}; ScanComplete=$true; ScanWarnings=@() }
        $script:SMUI = @{
            Scanning=$true; Applying=$false; ScanJob=@{Shared=@{Label='Reading';Total=1;Done=0;Cancelled=$false};Handle=@{IsCompleted=$true}}
            Status=[pscustomobject]@{Text=''}; Progress=[pscustomobject]@{Maximum=1;Value=0}
            ScanTimer=$timer; CancelScan=[pscustomobject]@{Visible=$true}; Warnings=[pscustomobject]@{Visible=$false}
            ScanNotice=''; AfterScanMessage=''; CloseAfterScan=$false
        }
        Mock Complete-SMInventoryScan { throw 'Provider unavailable' }
        Mock Close-SMInventoryScan { }
        Mock Set-SMMainBusy { }
        Mock Write-SMLog { }
        Mock Show-SMMainError { }
    }
    It 'marks retained inventory stale after a failed refresh' {
        Complete-SMMainScan
        $script:SM.Inventory[0] | Should Be 'previous'
        $script:SM.ScanComplete | Should Be $false
        ($script:SM.ScanWarnings -join ' ') | Should Match 'failed|stale|previous'
    }
    It 'marks retained inventory stale after a cancelled refresh' {
        $script:SMUI.ScanJob.Shared.Cancelled=$true
        Complete-SMMainScan
        $script:SM.Inventory[0] | Should Be 'previous'
        $script:SM.ScanComplete | Should Be $false
        ($script:SM.ScanWarnings -join ' ') | Should Match 'cancel|stale|previous'
    }
    It 'blocks baseline saving and comparing when inventory is incomplete' {
        $script:SMUI.Scanning=$false
        $script:SM.ScanComplete=$false
        $script:SM.ScanWarnings=@('Services unavailable')
        Mock New-Object { throw 'A file dialog must not be created for incomplete inventory.' } -ParameterFilter { $TypeName -match 'FileDialog' }
        Invoke-SMMainBaseline
        Invoke-SMMainBaseline -Compare
        Assert-MockCalled New-Object -Times 0 -Scope It -ParameterFilter { $TypeName -match 'FileDialog' }
        Assert-MockCalled Show-SMMainError -Times 2 -Scope It -ParameterFilter { $Message -match 'complete|incomplete|scan' }
    }
}
