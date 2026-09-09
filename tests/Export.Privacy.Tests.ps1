Set-StrictMode -Version 2.0
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src/Core/Contracts.ps1')
. (Join-Path $root 'src/Export/Export.ps1')
. (Join-Path $root 'src/Export/Report.ps1')

Describe 'Share-safe exports' {
    BeforeEach {
        $script:privateEntry = New-SMEntry -Name 'secret-person task' -Kind Task -Category 'Scheduled Task' -Enabled $true -Command 'C:\Users\secret-person\app.exe --token private-token' -ExePath 'C:\Users\secret-person\app.exe' -Source '\secret-person\' -Data @{ Secret = 'private-token' } -Detail 'private-token'
        $script:privateEntry.What = 'secret-person custom app'
        $script:privateEntry.Publisher = 'secret-person'
        $script:privateEntry.Explain = 'private-token'
        $script:privateEntry.DisableEffect = 'private-token'
        $script:privateEntry.BootMs = 4321
    }
    It 'removes all free-text identifiers in every share-safe export format' {
        foreach ($format in @('csv','json','txt','html')) {
            $path = Join-Path $TestDrive ('safe.' + $format)
            Export-SMEntries -Entries @($script:privateEntry) -Format $format -Path $path -ShareSafe | Out-Null
            $text = Get-Content -LiteralPath $path -Raw
            $text | Should Not Match 'secret-person|private-token|C:\\Users'
            $text | Should Match 'Entry 1'
        }
        $script:privateEntry.Name | Should Be 'secret-person task'
    }
    It 'omits machine identity and change history from share-safe reports' {
        Mock Get-SMReportMachineFacts { throw 'Private machine facts must not be read' }
        $path = Join-Path $TestDrive 'report.html'
        New-SMReport -Entries @($script:privateEntry) -ChangeRecords @(@{name='private-token'}) -Path $path -ShareSafe | Out-Null
        (Get-Content $path -Raw) | Should Not Match 'secret-person|private-token'
        Assert-MockCalled Get-SMReportMachineFacts -Times 0 -Exactly -Scope It
    }
    It 'neutralizes spreadsheet formulas without altering ordinary JSON values' {
        $script:privateEntry.Name = '=HYPERLINK("https://example.invalid")'
        Export-SMEntries -Entries @($script:privateEntry) -Format csv -Path (Join-Path $TestDrive 'formula.csv') | Out-Null
        (Import-Csv (Join-Path $TestDrive 'formula.csv'))[0].Name.StartsWith("'=") | Should Be $true
    }
    It 'does not restore ambiguous filename timing in reports' {
        $script:privateEntry.BootMs = -1
        $timing = Get-SMReportBootTiming $script:privateEntry @{ 'app.exe' = @{TotalMs=9999;DegradeMs=9999} }
        $timing.TotalMs | Should Be -1
    }
    It 'includes attributable measurement evidence in ordinary exports' {
        $script:privateEntry.BootMeasuredAt = '2026-09-09T12:00:00Z'
        $script:privateEntry.BootConfidence = 'Exact path'
        $script:privateEntry.RiskEvidence = 'Heuristic only'
        $path = Join-Path $TestDrive 'evidence.json'
        Export-SMEntries -Entries @($script:privateEntry) -Format json -Path $path | Out-Null
        $row = @(Get-Content $path -Raw | ConvertFrom-Json)[0]
        $row.BootConfidence | Should Be 'Exact path'
        $row.RiskEvidence | Should Be 'Heuristic only'
        $row.BootMeasuredAt | Should Match '2026-09-09'
    }
}
