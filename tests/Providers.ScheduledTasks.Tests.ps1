Set-StrictMode -Version 2.0

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src\Core\Contracts.ps1')
. (Join-Path $root 'src\Providers\ScheduledTasks.ps1')
. (Join-Path $root 'src\Engine\Changes.ps1')

Describe 'Scheduled task startup state' {
    BeforeEach {
        $script:testTask = [pscustomobject]@{
            TaskName = 'Test startup task'
            TaskPath = '\'
            State = 'Running'
            Settings = [pscustomobject]@{ Enabled = $false }
            Triggers = @([pscustomobject]@{
                CimClass = [pscustomobject]@{ CimClassName = 'MSFT_TaskLogonTrigger' }
            })
        }
        Mock Get-ScheduledTask { $script:testTask }
        Mock Get-ScheduledTaskInfo { $null }
    }

    It 'shows a disabled task as off even while it is running' {
        $entries = Get-SMScheduledTaskEntries
        $entries.Count | Should Be 1
        $entries[0].Enabled | Should Be $false
    }

    It 'shows an enabled running task as on' {
        $script:testTask.Settings.Enabled = $true
        (Get-SMScheduledTaskEntries)[0].Enabled | Should Be $true
    }

    It 'keeps a disabled ready task off' {
        $script:testTask.State = 'Ready'
        (Get-SMScheduledTaskEntries)[0].Enabled | Should Be $false
    }

    It 'falls back to state when settings are unavailable' {
        $script:testTask.Settings = $null
        $script:testTask.State = 'Disabled'
        (Get-SMScheduledTaskEntries)[0].Enabled | Should Be $false
        $script:testTask.State = 'Ready'
        (Get-SMScheduledTaskEntries)[0].Enabled | Should Be $true
    }
}
