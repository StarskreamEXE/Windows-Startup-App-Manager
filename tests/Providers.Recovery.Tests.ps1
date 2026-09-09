Set-StrictMode -Version 2.0
$root=Split-Path $PSScriptRoot -Parent
foreach ($file in @('Core/Contracts','Providers/StartupApproved','Providers/ScheduledTasks','Providers/Services','Providers/StoreApps','Engine/Changes')) { . "$root/src/$file.ps1" }

Describe 'Provider recovery contracts' {
    It 'reads exact service startup and delayed settings without guessing' {
        $entry=New-SMEntry -Name Service -Category Service -Kind Service -Enabled $false -Data @{Name='Example'}
        Mock Get-ItemProperty { [pscustomobject]@{Start=3;ImagePath='example.exe'} }
        Mock Get-SMRegistryValueSnapshot { [pscustomobject]@{Exists=$true;Value=1} }
        $snapshot=Get-SMEntryStateSnapshot $entry
        $snapshot.Start | Should Be 3
        $snapshot.Delayed.Value | Should Be 1
        $snapshot.Enabled | Should Be $false
    }
    It 'restores manual startup rather than forcing automatic' {
        $entry=New-SMEntry -Name Service -Category Service -Kind Service -Enabled $false -Data @{Name='Example'}
        Mock Set-Service {}
        Mock New-ItemProperty {}
        Restore-SMEntryStateSnapshot $entry ([pscustomobject]@{Start=3;Delayed=[pscustomobject]@{Exists=$true;Value=1}})
        Assert-MockCalled Set-Service -Times 1 -Scope It -ParameterFilter {$StartupType -eq 'Manual' -and $Name -eq 'Example'}
    }
    It 'does not overwrite Store policy state' {
        $entry=New-SMEntry -Name Store -Category Store -Kind Uwp -Enabled $false -Data @{Path='HKCU:\Fake'}
        Mock Get-ItemProperty { [pscustomobject]@{State=3} }
        Mock Set-ItemProperty {}
        { Set-SMStoreAppState $entry $true } | Should Throw
        Assert-MockCalled Set-ItemProperty -Times 0 -Scope It
    }
    It 'surfaces service provider enumeration failures' {
        Mock Get-CimInstance { throw 'access denied' }
        { Get-SMServiceEntries } | Should Throw
    }
    It 'keeps missing approval distinct from an explicit enabled record' {
        $entry=New-SMEntry -Name App -Category Run -Kind RunKey -Enabled $true -Source 'HKCU:\FakeRun' -Data @{Hive='HKCU';Leaf='Run';Name='App'}
        Mock Get-SMRegistryValueSnapshot { param($Path,$Name) if ($Path -eq 'HKCU:\FakeRun') { [pscustomobject]@{Exists=$true;Value='app.exe'} } else { [pscustomobject]@{Exists=$false;Value=$null} } }
        $snapshot=Get-SMEntryStateSnapshot $entry
        $snapshot.Enabled | Should Be $true
        $snapshot.Approval.Exists | Should Be $false
        $snapshot.Configuration | Should Be 'app.exe'
    }
    It 'restores the exact approval byte record' {
        $entry=New-SMEntry -Name App -Category Run -Kind RunKey -Enabled $true -Source 'HKCU:\FakeRun' -Data @{Hive='HKCU';Leaf='Run';Name='App'}
        Mock New-ItemProperty {}
        Restore-SMEntryStateSnapshot $entry ([pscustomobject]@{Approval=[pscustomobject]@{Exists=$true;Value=@(3,0,0,0,1,2,3,4,5,6,7,8)}})
        Assert-MockCalled New-ItemProperty -Times 1 -Scope It -ParameterFilter { $Name -eq 'App' -and ($Value -join ',') -eq '3,0,0,0,1,2,3,4,5,6,7,8' }
    }
    It 'normalizes only the task enabled flag for configuration comparison' {
        $entry=New-SMEntry -Name Task -Category Task -Kind Task -Enabled $true -Data @{Name='Task';Path='\'}
        Mock Get-ScheduledTask {
            $settings=New-CimInstance -ClassName MSFT_TaskSettings -ClientOnly -Property @{Enabled=$true}
            New-CimInstance -ClassName MSFT_ScheduledTask -ClientOnly -Property @{TaskName='Task';TaskPath='\';Settings=$settings}
        }
        Mock Export-ScheduledTask { '<Task><Settings><Enabled>true</Enabled></Settings><Actions>app.exe</Actions></Task>' }
        $before=Get-SMEntryStateSnapshot $entry
        Mock Export-ScheduledTask { '<Task><Settings><Enabled>false</Enabled></Settings><Actions>other.exe</Actions></Task>' }
        $after=Get-SMEntryStateSnapshot $entry
        $before.Configuration | Should Not Be $after.Configuration
        $before.Configuration.Contains('Enabled') | Should Be $false
    }
    It 'resolves task wildcard metacharacters as literal identity' {
        $entry=New-SMEntry -Name 'Task[1]' -Category Task -Kind Task -Enabled $true -Data @{Name='Task[1]';Path='\Folder[1]\'}
        Mock Get-ScheduledTask {
            @([pscustomobject]@{TaskName='Task1';TaskPath='\Folder1\'},[pscustomobject]@{TaskName='Task[1]';TaskPath='\Folder[1]\'})
        }
        $task=Get-SMExactScheduledTask $entry
        $task.TaskName | Should Be 'Task[1]'
        $task.TaskPath | Should Be '\Folder[1]\'
    }
    It 'refuses task resolution if the exact identity is absent' {
        $entry=New-SMEntry -Name 'Task[1]' -Category Task -Kind Task -Enabled $true -Data @{Name='Task[1]';Path='\Folder[1]\'}
        Mock Get-ScheduledTask { [pscustomobject]@{TaskName='Task1';TaskPath='\Folder1\'} }
        { Get-SMExactScheduledTask $entry } | Should Throw
    }
}
