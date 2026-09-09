$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$root\src\Core\Contracts.ps1"
. "$root\src\Analysis\FileFacts.ps1"
. "$root\src\Analysis\BootPerf.ps1"
. "$root\src\Analysis\KnownApps.ps1"
. "$root\src\Analysis\Risk.ps1"
. "$root\src\Engine\Inventory.ps1"

Describe 'Evidence-based diagnostics' {
    It 'does not claim Windows depends on an arbitrary signed host' {
        $entry = New-SMEntry -Name 'Custom script' -Category 'Task' -Kind Task -Enabled $true -ExePath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
        $entry.SigStatus = 'Valid'; $entry.SigSigner = 'Microsoft Windows'
        $result = Get-SMRiskAssessment $entry
        $result.Risk | Should Not Be 'Critical'
        $result.DisableEffect | Should Not Match 'depends on this'
        $result.RiskEvidence | Should Match 'not establish'
    }
    It 'does not call an unresolved relative executable broken' {
        $entry = New-SMEntry -Name 'Custom' -Category 'Task' -Kind Task -Enabled $true -ExePath 'custom.exe'
        $entry.Exists = $false
        (Get-SMRiskAssessment $entry).Risk | Should Not Be 'Broken'
    }
    It 'normalizes absolute paths without filename-only attribution' {
        ConvertTo-SMBootPath 'C:\Apps\..\Tools\APP.exe' | Should Be 'c:\tools\app.exe'
        ConvertTo-SMBootPath 'app.exe' | Should Be ''
    }
    It 'refuses shared host attribution' {
        $entry = New-SMEntry -Name 'Task' -Category 'Task' -Kind Task -Enabled $true -ExePath 'C:\Windows\System32\svchost.exe'
        $perf = @{ 'c:\windows\system32\svchost.exe' = @{ TotalMs=9000; DegradeMs=100; LastSeen=(Get-Date) } }
        Set-SMBootEvidence -Entry $entry -Perf $perf -PathCount 1
        $entry.BootMs | Should Be -1
        $entry.BootConfidence | Should Match 'shared host'
    }
    It 'refuses ambiguous duplicate executable attribution' {
        $entry = New-SMEntry -Name 'Task' -Category 'Task' -Kind Task -Enabled $true -ExePath 'C:\Tools\app.exe'
        Set-SMBootEvidence $entry @{ 'c:\tools\app.exe' = @{TotalMs=3000;DegradeMs=200;LastSeen=(Get-Date)} } 2
        $entry.BootMs | Should Be -1
    }
    It 'assigns exact unique path with timestamp and confidence' {
        $entry = New-SMEntry -Name 'Task' -Category 'Task' -Kind Task -Enabled $true -ExePath 'C:\Tools\app.exe'
        $when = Get-Date
        Set-SMBootEvidence $entry @{ 'c:\tools\app.exe' = @{TotalMs=3000;DegradeMs=200;LastSeen=$when} } 1
        $entry.BootMs | Should Be 3000
        $entry.BootMeasuredAt | Should Be $when
        $entry.BootConfidence | Should Match 'Exact path'
    }
}

Describe 'Inventory scan status' {
    function Get-SMRunKeyEntries { }
    function Get-SMStartupFolderEntries { }
    function Get-SMScheduledTaskEntries { }
    function Get-SMServiceEntries { }
    function Get-SMStoreAppEntries { }
    function Write-SMLog { param($Level,$Message) }
    BeforeEach {
        $script:SM = @{ Inventory=@('previous') }
        Mock Get-SMRunKeyEntries { }
        Mock Get-SMStartupFolderEntries { }
        Mock Get-SMScheduledTaskEntries { }
        Mock Get-SMServiceEntries { }
        Mock Get-SMStoreAppEntries { }
        Mock Get-SMBootPerf { @{} }
    }
    It 'publishes provider failures rather than a complete scan' {
        Mock Get-SMServiceEntries { throw 'Access denied' }
        $null = Get-SMInventory
        $script:SM.ScanComplete | Should Be $false
        ($script:SM.ScanWarnings -join ' ') | Should Match 'Services: Access denied'
    }
    It 'cancels without replacing the previous inventory' {
        { Get-SMInventory -Cancelled { $true } } | Should Throw
        $script:SM.Inventory[0] | Should Be 'previous'
        $script:SM.ScanComplete | Should Be $false
    }
    It 'marks a successful empty scan complete' {
        $null = Get-SMInventory
        $script:SM.ScanComplete | Should Be $true
        $script:SM.ScanWarnings.Count | Should Be 0
    }
}
