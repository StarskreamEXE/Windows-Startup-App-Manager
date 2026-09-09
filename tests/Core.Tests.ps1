# Pester 3.4 tests for src/Core: Contracts.ps1, Paths.ps1, Logging.ps1.
# Runs without admin. Touches nothing outside a temp root; never reads or
# writes real startup state.

Set-StrictMode -Version 2.0

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\src\Core\Contracts.ps1')
. (Join-Path $here '..\src\Core\Paths.ps1')
. (Join-Path $here '..\src\Core\Logging.ps1')

$TestRoot = Join-Path $env:TEMP ("smtest_{0}" -f (Get-Random))
Initialize-SMPaths -Root $TestRoot | Out-Null

# --- test-local helpers (not part of the function contract) ---
function NewTestEntry {
    New-SMEntry -Name 'Test App' -Category 'Registry Run (User)' -Kind RunKey -Enabled $true `
        -Command '"C:\Apps\test.exe" /bg' -ExePath 'C:\Apps\test.exe' `
        -Source 'HKCU\Software\Microsoft\Windows\CurrentVersion\Run' `
        -Data @{ Hive = 'HKCU'; Leaf = 'Run'; Name = 'TestApp' }
}

function ResetTestLogs {
    $s = Get-SMState
    foreach ($f in @($s.LogFile, $s.ChangeFile)) {
        if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force }
    }
}

Describe 'Initialize-SMPaths / Get-SMState' {

    It 'creates the working directories under the given root' {
        $s = Get-SMState
        (Test-Path -LiteralPath $s.LogDir)    | Should Be $true
        (Test-Path -LiteralPath $s.BackupDir) | Should Be $true
        (Test-Path -LiteralPath $s.ReportDir) | Should Be $true
        (Test-Path -LiteralPath $s.ExportDir) | Should Be $true
    }

    It 'points LogFile and ChangeFile inside the temp root' {
        $s = Get-SMState
        $s.Root       | Should BeExactly $TestRoot
        $s.LogFile    | Should BeExactly (Join-Path $TestRoot 'logs\startup-manager.log')
        $s.ChangeFile | Should BeExactly (Join-Path $TestRoot 'logs\changes.jsonl')
    }

    It 'starts with empty runtime state' {
        $s = Get-SMState
        @($s.Inventory).Count | Should Be 0
        $s.Pending.Count      | Should Be 0
    }
}

Describe 'New-SMEntry' {

    It 'fills the provider block from the parameters' {
        $e = NewTestEntry
        $e.Name      | Should BeExactly 'Test App'
        $e.Kind      | Should BeExactly 'RunKey'
        $e.Enabled   | Should Be $true
        $e.CanToggle | Should Be $true
        $e.ExePath   | Should BeExactly 'C:\Apps\test.exe'
        $e.Data.Name | Should BeExactly 'TestApp'
    }

    It 'defaults the analysis block: Id 0, BootMs -1, DegradeMs -1' {
        $e = NewTestEntry
        $e.Id        | Should Be 0
        $e.BootMs    | Should Be -1
        $e.DegradeMs | Should Be -1
    }

    It 'defaults Risk and SigStatus to Unknown' {
        $e = NewTestEntry
        $e.Risk      | Should BeExactly 'Unknown'
        $e.SigStatus | Should BeExactly 'Unknown'
    }

    It 'defaults Flags to an empty array' {
        $e = NewTestEntry
        ($e.Flags -is [array]) | Should Be $true
        @($e.Flags).Count      | Should Be 0
    }

    It 'rejects a Kind outside the contract' {
        { New-SMEntry -Name 'x' -Category 'c' -Kind 'Nonsense' -Enabled $true } | Should Throw
    }
}

Describe 'New-SMChangeRecord' {

    It 'produces the jsonl schema fields' {
        $r = New-SMChangeRecord -Action apply -Entry (NewTestEntry) -From $true -To $false -Ok $true
        $r.action    | Should BeExactly 'apply'
        $r.id        | Should Be 0
        $r.name      | Should BeExactly 'Test App'
        $r.kind      | Should BeExactly 'RunKey'
        $r.category  | Should BeExactly 'Registry Run (User)'
        $r.from      | Should Be $true
        $r.to        | Should Be $false
        $r.ok        | Should Be $true
        $r.error     | Should BeExactly ''
        $r.data.Name | Should BeExactly 'TestApp'
        $r.ts        | Should Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}'
    }

    It 'rejects an action outside apply/undo' {
        { New-SMChangeRecord -Action 'delete' -Entry (NewTestEntry) -From $true -To $false -Ok $true } | Should Throw
    }
}

Describe 'Write-SMLog / Get-SMLogText' {

    It 'returns an empty string when the log file does not exist' {
        ResetTestLogs
        Get-SMLogText | Should BeExactly ''
    }

    It 'writes one timestamped line per call' {
        ResetTestLogs
        Write-SMLog -Level INFO -Message 'scan started'
        Get-SMLogText | Should Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \[INFO\] scan started$'
        @(Get-Content -LiteralPath (Get-SMState).LogFile).Count | Should Be 1
    }

    It 'records the level it was given' {
        ResetTestLogs
        Write-SMLog -Level WARN  -Message 'boot log unavailable'
        Write-SMLog -Level ERROR -Message 'provider failed'
        $text = Get-SMLogText
        $text | Should Match '\[WARN\] boot log unavailable'
        $text | Should Match '\[ERROR\] provider failed'
    }

    It 'flattens embedded newlines to a single line' {
        ResetTestLogs
        Write-SMLog -Level ERROR -Message "line one`r`nline two`nline three"
        $lines = @(Get-Content -LiteralPath (Get-SMState).LogFile)
        $lines.Count | Should Be 1
        $lines[0]    | Should Match 'line one \| line two \| line three$'
    }

    It 'rejects a level outside INFO/WARN/ERROR' {
        { Write-SMLog -Level 'TRACE' -Message 'x' } | Should Throw
    }

    It 'does not throw when the log target is unusable' {
        ResetTestLogs
        $s = Get-SMState
        $saved = $s.LogFile
        $s.LogFile = ''
        { Write-SMLog -Level INFO -Message 'nowhere to go' } | Should Not Throw
        $s.LogFile = $saved
    }

    It 'returns only the last n lines with -TailLines' {
        ResetTestLogs
        1..5 | ForEach-Object { Write-SMLog -Level INFO -Message ("entry {0}" -f $_) }
        $tail = Get-SMLogText -TailLines 2
        @($tail -split "`r`n").Count | Should Be 2
        $tail | Should Match 'entry 4'
        $tail | Should Match 'entry 5'
        $tail | Should Not Match 'entry 3'
    }
}

Describe 'Write-SMChangeRecord / Get-SMChangeRecords' {

    It 'returns an empty array when the change file does not exist' {
        ResetTestLogs
        @(Get-SMChangeRecords).Count | Should Be 0
    }

    It 'round-trips a record through one compact json line' {
        ResetTestLogs
        $rec = New-SMChangeRecord -Action apply -Entry (NewTestEntry) -From $true -To $false -Ok $true
        Write-SMChangeRecord -Record $rec

        @(Get-Content -LiteralPath (Get-SMState).ChangeFile).Count | Should Be 1

        $back = @(Get-SMChangeRecords)
        $back.Count        | Should Be 1
        $back[0].action    | Should BeExactly 'apply'
        $back[0].name      | Should BeExactly 'Test App'
        $back[0].kind      | Should BeExactly 'RunKey'
        $back[0].from      | Should Be $true
        $back[0].to        | Should Be $false
        $back[0].ok        | Should Be $true
        $back[0].data.Name | Should BeExactly 'TestApp'
        $back[0].ts        | Should BeExactly $rec.ts
    }

    It 'returns records oldest first' {
        ResetTestLogs
        foreach ($n in 1..3) {
            $e = NewTestEntry
            $e.Name = "App $n"
            Write-SMChangeRecord -Record (New-SMChangeRecord -Action apply -Entry $e -From $true -To $false -Ok $true)
        }
        $back = @(Get-SMChangeRecords)
        $back.Count   | Should Be 3
        $back[0].name | Should BeExactly 'App 1'
        $back[2].name | Should BeExactly 'App 3'
    }

    It 'returns only the newest n with -Last, still oldest first' {
        ResetTestLogs
        foreach ($n in 1..3) {
            $e = NewTestEntry
            $e.Name = "App $n"
            Write-SMChangeRecord -Record (New-SMChangeRecord -Action apply -Entry $e -From $true -To $false -Ok $true)
        }
        $back = @(Get-SMChangeRecords -Last 2)
        $back.Count   | Should Be 2
        $back[0].name | Should BeExactly 'App 2'
        $back[1].name | Should BeExactly 'App 3'
    }

    It 'returns everything when -Last is larger than the file' {
        ResetTestLogs
        Write-SMChangeRecord -Record (New-SMChangeRecord -Action apply -Entry (NewTestEntry) -From $true -To $false -Ok $true)
        @(Get-SMChangeRecords -Last 50).Count | Should Be 1
    }

    It 'skips a malformed line, logs a WARN and does not throw' {
        ResetTestLogs
        $s = Get-SMState
        Write-SMChangeRecord -Record (New-SMChangeRecord -Action apply -Entry (NewTestEntry) -From $true -To $false -Ok $true)
        Add-Content -LiteralPath $s.ChangeFile -Value '{ this is not json' -Encoding UTF8
        Write-SMChangeRecord -Record (New-SMChangeRecord -Action undo -Entry (NewTestEntry) -From $false -To $true -Ok $true)

        { Get-SMChangeRecords | Out-Null } | Should Not Throw

        $back = @(Get-SMChangeRecords)
        $back.Count     | Should Be 2
        $back[0].action | Should BeExactly 'apply'
        $back[1].action | Should BeExactly 'undo'
        Get-SMLogText   | Should Match '\[WARN\] Skipped malformed change-log line 2'
    }

    It 'ignores blank lines' {
        ResetTestLogs
        $s = Get-SMState
        Write-SMChangeRecord -Record (New-SMChangeRecord -Action apply -Entry (NewTestEntry) -From $true -To $false -Ok $true)
        Add-Content -LiteralPath $s.ChangeFile -Value '' -Encoding UTF8
        @(Get-SMChangeRecords).Count | Should Be 1
    }
}

# --- cleanup: remove the temp root created for this run ---
if ($TestRoot -and (Test-Path -LiteralPath $TestRoot)) {
    Remove-Item -LiteralPath $TestRoot -Recurse -Force -ErrorAction SilentlyContinue
}
