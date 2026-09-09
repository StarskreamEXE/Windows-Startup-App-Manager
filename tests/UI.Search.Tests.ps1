Set-StrictMode -Version 2.0
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src/Core/Contracts.ps1')
. (Join-Path $root 'src/UI/MainForm.ps1')

Describe 'Literal inventory search' {
    BeforeEach {
        $script:SM = @{ Pending = [ordered]@{} }
        $script:SMUI = @{
            CatRun = @{ Checked = $true }
            Preset = @{ SelectedItem = 'All items' }
            Search = @{ Text = '' }
            SearchPlaceholder = 'Search entries'
        }
        $entry = New-SMEntry -Name 'ordinary' -Category 'Registry Run (User)' -Kind RunKey -Enabled $true
    }
    It 'matches wildcard characters literally without rejecting incomplete brackets' {
        foreach ($query in @('[', ']', '[]', '*', '?', '`')) {
            $script:SMUI.Search.Text = $query
            $entry.Name = 'ordinary'
            (Test-SMMainVisible $entry) | Should Be $false
            $entry.Name = 'prefix' + $query + 'suffix'
            (Test-SMMainVisible $entry) | Should Be $true
        }
    }
    It 'matches each searchable field case-insensitively and trims the query' {
        $script:SMUI.Search.Text = '  NEEDLE  '
        foreach ($field in @('Name', 'What', 'Publisher', 'Command', 'ExePath', 'Category', 'Flags', 'Risk')) {
            $original = $entry.$field
            $entry.$field = 'prefixNeedleSuffix'
            (Test-SMMainVisible $entry) | Should Be $true
            $entry.$field = $original
        }
    }
}

Describe 'Inventory grid error cleanup' {
    BeforeEach {
        $table = [pscustomobject]@{ Rows = (New-Object Collections.ArrayList); EndCalls = 0; FailEnd = $false }
        $table | Add-Member ScriptMethod BeginLoadData { }
        $table | Add-Member ScriptMethod EndLoadData { $this.EndCalls++; if ($this.FailEnd) { throw 'End load failed' } }
        $script:SM = @{ Inventory = @([pscustomobject]@{ Name = 'fixture' }) }
        $script:SMUI = @{ Loading = $false; Grid = @{ SortedColumn = $null }; Table = $table }
        Mock Test-SMMainVisible { throw 'Filtering failed' }
        Mock Update-SMMainStyles { }
        Mock Update-SMMainStatus { }
    }
    It 'ends the table load and restores event processing after filtering fails' {
        { Update-SMMainGrid } | Should Throw 'Filtering failed'
        $script:SMUI.Loading | Should Be $false
        $script:SMUI.Table.EndCalls | Should Be 1
    }
    It 'restores event processing even when ending the table load fails' {
        $script:SM.Inventory = @()
        $script:SMUI.Table.FailEnd = $true
        { Update-SMMainGrid } | Should Throw 'End load failed'
        $script:SMUI.Loading | Should Be $false
    }
}
