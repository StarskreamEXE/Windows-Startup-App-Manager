$root = Split-Path -Parent $PSScriptRoot
. "$root/src/Core/Contracts.ps1"
. "$root/src/Analysis/KnownApps.ps1"
. "$root/src/Analysis/Risk.ps1"

Describe 'Security evidence takes precedence over known application patterns' {
    foreach ($signature in @('Unsigned', 'Invalid')) {
        It "keeps a $signature known application in Downloads suspicious" {
            $entry = New-SMEntry -Name GoogleChromeAutoLaunch -Category Task -Kind Task -Enabled $true -ExePath 'C:\Users\Example\Downloads\chrome.exe' -Command 'chrome.exe --no-startup-window'
            $entry.SigStatus = $signature
            $result = Get-SMRiskAssessment $entry
            $result.Risk | Should Be 'Suspicious'
            ($result.SecurityFlags -contains 'TEMP-PATH') | Should Be $true
            $expectedFlag = if ($signature -eq 'Unsigned') { 'UNSIGNED' } else { 'BAD-SIG' }
            ($result.SecurityFlags -contains $expectedFlag) | Should Be $true
        }

        It "requires caution for a $signature known optional application elsewhere" {
            $entry = New-SMEntry -Name GoogleChromeAutoLaunch -Category Task -Kind Task -Enabled $true -ExePath 'C:\Apps\chrome.exe' -Command 'chrome.exe --no-startup-window'
            $entry.SigStatus = $signature
            (Get-SMRiskAssessment $entry).Risk | Should Be 'Caution'
        }

        It "preserves critical dependency guidance for a $signature critical match" {
            $entry = New-SMEntry -Name RtkAudUService -Category Service -Kind Service -Enabled $true -ExePath 'C:\Apps\RtkAudUService.exe'
            $entry.SigStatus = $signature
            $result = Get-SMRiskAssessment $entry
            $result.Risk | Should Be 'Critical'
            $result.DisableEffect | Should Match 'Review carefully'
        }
    }

    It 'does not reassure users that disabling a suspicious name match is safe' {
        $entry = New-SMEntry -Name GoogleChromeAutoLaunch -Category Task -Kind Task -Enabled $true -ExePath 'C:\Users\Example\Downloads\chrome.exe' -Command 'chrome.exe --no-startup-window'
        $entry.SigStatus = 'Invalid'
        $result = Get-SMRiskAssessment $entry
        $result.DisableEffect | Should Not Match '\bSafe\b'
        $result.DisableEffect | Should Match 'Verify'
    }

    It 'retains the normal known application classification for a valid signature' {
        $entry = New-SMEntry -Name GoogleChromeAutoLaunch -Category Task -Kind Task -Enabled $true -ExePath 'C:\Apps\chrome.exe' -Command 'chrome.exe --no-startup-window'
        $entry.SigStatus = 'Valid'
        (Get-SMRiskAssessment $entry).Risk | Should Be 'Optional'
    }
}
