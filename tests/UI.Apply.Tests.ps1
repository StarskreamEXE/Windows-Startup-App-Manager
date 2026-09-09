Set-StrictMode -Version 2.0

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src\Engine\Changes.ps1')
. (Join-Path $root 'src\Engine\Backup.ps1')
. (Join-Path $root 'src\Core\Logging.ps1')
. (Join-Path $root 'src\UI\Dialogs.ps1')
. (Join-Path $root 'src\UI\MainForm.ps1')

Describe 'Apply result summary' {
    It 'counts each successful change after refreshing' {
        $script:SMUI = @{ Status = [pscustomobject]@{ Text = '' }; Scanning = $false; Applying = $false; AdvancedMode = $false }
        Mock Get-SMPendingChanges { ,@(@{ Name = 'First'; Kind='RunKey' }, @{ Name = 'Second'; Kind='Task' }) }
        Mock Show-SMApplyConfirmDialog { @{ Apply = $true; Backup = $false } }
        Mock Invoke-SMApplyChanges { ,@(@{ Ok = $true }, @{ Ok = $true }) }
        Mock Invoke-SMMainScan { $script:SMUI.Status.Text = 'Refreshed' }

        Invoke-SMMainApply

        $script:SMUI.Status.Text | Should Match 'Applied 2 change\(s\), 0 failed'
        Assert-MockCalled Invoke-SMMainScan -Times 1 -Exactly
    }
    It 'blocks overlapping apply during a scan' {
        $script:SMUI = @{ Scanning = $true; Applying = $false }
        Mock Invoke-SMApplyChanges { throw 'Must not run' }
        Invoke-SMMainApply
        Assert-MockCalled Invoke-SMApplyChanges -Times 0 -Exactly -Scope It
    }
    It 'reports a recovery failure without starting a misleading refresh' {
        $script:SMUI = @{ Status = [pscustomobject]@{ Text = '' }; Scanning = $false; Applying = $false; AdvancedMode = $false }
        Mock Get-SMPendingChanges { ,@(@{ Name='Test'; Kind='RunKey' }) }
        Mock Show-SMApplyConfirmDialog { @{Apply=$true} }
        Mock Invoke-SMApplyChanges { throw 'Recovery unavailable' }
        Mock Show-SMMainError {}
        Mock Invoke-SMMainScan {}
        Invoke-SMMainApply
        Assert-MockCalled Show-SMMainError -Times 1 -Exactly -Scope It -ParameterFilter { $Message -match 'Recovery unavailable' }
        Assert-MockCalled Invoke-SMMainScan -Times 0 -Exactly -Scope It
        $script:SMUI.Applying | Should Be $false
    }
}
