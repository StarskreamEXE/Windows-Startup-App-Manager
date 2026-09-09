$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$root\src\Core\Contracts.ps1"
if (Test-Path "$root\src\Engine\Baseline.ps1") { . "$root\src\Engine\Baseline.ps1" }

Describe 'Local baseline comparison' {
    It 'round trips empty inventories' {
        $path = Join-Path $TestDrive 'empty.json'
        Save-SMBaseline -Entries @() -Path $path
        $baseline = Get-SMBaseline -Path $path
        @($baseline.Entries).Count | Should Be 0
        @(Compare-SMBaseline -Baseline $baseline -Entries @()).Count | Should Be 0
    }
    It 'reports added removed and changed entries using stable identity' {
        $before = New-SMEntry -Name 'Same' -Category 'Task' -Kind Task -Enabled $true -Command 'old' -Data @{Name='Same';Path='\A\'}
        $removed = New-SMEntry -Name 'Same' -Category 'Task' -Kind Task -Enabled $true -Data @{Name='Same';Path='\B\'}
        $path = Join-Path $TestDrive 'snapshot.json'
        Save-SMBaseline -Entries @($before,$removed) -Path $path
        $before.Enabled = $false; $before.Command = 'new'; $before.Id = 999
        $added = New-SMEntry -Name 'Same' -Category 'Task' -Kind Task -Enabled $true -Data @{Name='Same';Path='\C\'}
        $changes = @(Compare-SMBaseline (Get-SMBaseline $path) @($before,$added))
        $changes.Count | Should Be 3
        @($changes | Where-Object Change -eq Changed)[0].Fields -contains 'Enabled' | Should Be $true
        @($changes | Where-Object Change -eq Changed)[0].Fields -contains 'Command' | Should Be $true
    }
    It 'rejects invalid schemas and duplicate identities' {
        $path = Join-Path $TestDrive 'bad.json'
        Set-Content $path '{"SchemaVersion":99,"Entries":[]}'
        { Get-SMBaseline $path } | Should Throw
        $entry = New-SMEntry -Name 'Same' -Category 'Task' -Kind Task -Enabled $true -Data @{Name='Same';Path='\A\'}
        { Save-SMBaseline @($entry,$entry) $path } | Should Throw
    }
    It 'preserves Unicode names and paths from UTF8 snapshots' {
        $name = 'Startup ' + [char]0x65E5 + [char]0x672C
        $entry = New-SMEntry -Name $name -Category Task -Kind Task -Enabled $true -Command ('C:\' + $name + '\app.exe') -Data @{Name=$name;Path='\'}
        $path = Join-Path $TestDrive 'unicode.json'
        Save-SMBaseline @($entry) $path
        $baseline = Get-SMBaseline $path
        $baseline.Entries[0].Name | Should BeExactly $name
        @(Compare-SMBaseline $baseline @($entry)).Count | Should Be 0
    }
}
