Set-StrictMode -Version 2.0
$root = Split-Path -Parent $PSScriptRoot
$scanFile = Join-Path $root 'src/UI/Scan.ps1'
if (Test-Path $scanFile) { . $scanFile }

Describe 'Asynchronous inventory scan' {
    It 'runs outside the UI runspace and transfers only a completed inventory' {
        Set-Content (Join-Path $TestDrive 'inventory.ps1') @'
function Get-SMInventory {
    param($Progress,$Cancelled)
    & $Progress 1 2 'Reading fixture'
    $script:SM.ScanWarnings = @('Fixture unavailable')
    $script:SM.ScanComplete = $false
    $script:SM.BootPerf = @{}
    return ,@([pscustomobject]@{Name='fixture'})
}
'@
        $job = Start-SMInventoryScan -Root $TestDrive -State @{Inventory=@('old')} -SourceFiles @('inventory.ps1')
        try {
            $job.Handle.AsyncWaitHandle.WaitOne(10000) | Should Be $true
            $result = Complete-SMInventoryScan -Job $job
            $result.Inventory[0].Name | Should Be 'fixture'
            $result.ScanWarnings[0] | Should Be 'Fixture unavailable'
            $result.ScanComplete | Should Be $false
        } finally { Close-SMInventoryScan -Job $job }
    }
    It 'cancels a pipeline without publishing partial inventory' {
        Set-Content (Join-Path $TestDrive 'inventory.ps1') 'function Get-SMInventory { param($Progress,$Cancelled) Start-Sleep -Seconds 60 }'
        $job = Start-SMInventoryScan -Root $TestDrive -State @{} -SourceFiles @('inventory.ps1')
        try {
            Stop-SMInventoryScan -Job $job
            $job.Handle.AsyncWaitHandle.WaitOne(10000) | Should Be $true
            { Complete-SMInventoryScan -Job $job } | Should Throw
        } finally { Close-SMInventoryScan -Job $job }
    }
}
