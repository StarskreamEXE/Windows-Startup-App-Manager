#requires -Version 5.1
<#
    Startup Manager - one command to run everything.

        powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1

    Two gates, both must be clean:
      1. Pester 3.4 unit tests  (tests\*.Tests.ps1)
      2. A PowerShell AST parse of every src\**\*.ps1 and Start-StartupManager.ps1,
         so a syntax error can never hide behind "no test covers that file".

    Exit code = failed tests + files that failed to parse. 0 means everything is green.

    *.Smoke.ps1 files are NOT run here - they open real windows and need a desktop.
    Run one by hand when you want to look at the UI.
#>

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$TestsDir = $PSScriptRoot
$Root     = Split-Path -Parent $TestsDir

# ------------------------------------------------------------------- Pester

Import-Module Pester -RequiredVersion 3.4.0 -ErrorAction Stop

$smokeFiles = @(Get-ChildItem -Path $TestsDir -Filter '*.Smoke.ps1' -Recurse -File -ErrorAction SilentlyContinue |
                    Sort-Object FullName)

$testFiles = @(Get-ChildItem -Path $TestsDir -Filter '*.Tests.ps1' -Recurse -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -notlike '*.Smoke.ps1' } |
                    Sort-Object FullName)

Write-Host ''
Write-Host '=== Pester ===' -ForegroundColor Cyan

$passed  = 0
$failed  = 0
$skipped = 0
$pending = 0
$total   = 0

if ($testFiles.Count -eq 0) {
    Write-Host "No *.Tests.ps1 files found under $TestsDir - nothing to run yet."
} else {
    $result  = Invoke-Pester -Path ($testFiles | ForEach-Object { $_.FullName }) -PassThru
    $passed  = [int]$result.PassedCount
    $failed  = [int]$result.FailedCount
    $skipped = [int]$result.SkippedCount
    $pending = [int]$result.PendingCount
    $total   = [int]$result.TotalCount
}

# -------------------------------------------------------------- parse check

Write-Host ''
Write-Host '=== Parse check ===' -ForegroundColor Cyan

$parseTargets = @()
$srcDir = Join-Path $Root 'src'
if (Test-Path -LiteralPath $srcDir) {
    $parseTargets += @(Get-ChildItem -Path $srcDir -Filter '*.ps1' -Recurse -File |
                           Sort-Object FullName | ForEach-Object { $_.FullName })
}
$entryScript = Join-Path $Root 'Start-StartupManager.ps1'
if (Test-Path -LiteralPath $entryScript) { $parseTargets += $entryScript }
$parseTargets += @(Get-ChildItem -LiteralPath $Root -Filter '*.ps1' -File | Where-Object { $_.FullName -ne $entryScript } | ForEach-Object { $_.FullName })
$parseTargets += @(Get-ChildItem -LiteralPath (Join-Path $Root 'build') -Filter '*.ps1' -File | ForEach-Object { $_.FullName })

$parseErrorCount = 0
foreach ($target in $parseTargets) {
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($target, [ref]$null, [ref]$errors) | Out-Null
    if ($errors -and $errors.Count -gt 0) {
        $parseErrorCount++
        Write-Host ("PARSE FAIL  " + $target) -ForegroundColor Red
        foreach ($e in $errors) {
            Write-Host ("    line {0}: {1}" -f $e.Extent.StartLineNumber, $e.Message) -ForegroundColor Red
        }
    }
}
Write-Host ("Parsed {0} file(s); {1} with errors." -f $parseTargets.Count, $parseErrorCount)

if ($parseTargets.Count -eq 0) {
    Write-Host "No src\**\*.ps1 or Start-StartupManager.ps1 found to parse." -ForegroundColor Yellow
}

# ------------------------------------------------------------------ summary

Write-Host ''
Write-Host '=== Summary ===' -ForegroundColor Cyan
Write-Host ("Passed:       {0}" -f $passed)
Write-Host ("Failed:       {0}" -f $failed) -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Green' })
Write-Host ("Skipped:      {0}" -f $skipped)
Write-Host ("Pending:      {0}" -f $pending)
Write-Host ("Total tests:  {0}" -f $total)
Write-Host ("Parse errors: {0}" -f $parseErrorCount) -ForegroundColor $(if ($parseErrorCount -gt 0) { 'Red' } else { 'Green' })

if ($smokeFiles.Count -gt 0) {
    Write-Host ''
    Write-Host 'Skipped smoke scripts (they open real windows, so they are not part of this run):' -ForegroundColor Yellow
    foreach ($s in $smokeFiles) {
        Write-Host ("  {0}" -f $s.Name)
    }
    Write-Host 'Run one by hand with:' -ForegroundColor Yellow
    Write-Host ('  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $smokeFiles[0].FullName)
}

$exitCode = $failed + $parseErrorCount
Write-Host ''
Write-Host ("Exit code: {0}" -f $exitCode)
exit $exitCode
