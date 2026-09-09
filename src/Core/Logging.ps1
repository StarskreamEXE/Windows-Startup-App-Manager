# Text log + JSONL change log. Dot-source after Contracts.ps1 and Paths.ps1.
# Every layer writes here; the user can open logs/startup-manager.log and
# logs/changes.jsonl at any time and see exactly what the tool did.

Set-StrictMode -Version 2.0

function Write-SMLog {
    <#
    .SYNOPSIS
        Appends one UTF-8 line to $SM.LogFile as 'yyyy-MM-dd HH:mm:ss [LEVEL] message'.
    .DESCRIPTION
        Never throws. Logging failures (state not initialised, unwritable directory,
        file locked) are swallowed so that no caller can be broken by its own logging.
        Embedded newlines are replaced with ' | ' so one call is always one line.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('INFO','WARN','ERROR')] [string] $Level,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Message
    )

    try {
        $state = Get-Variable -Name SM -Scope Script -ErrorAction SilentlyContinue
        if (-not $state) { return }
        $bag = $state.Value
        if (-not $bag) { return }
        $file = $bag['LogFile']
        if (-not $file) { return }

        $flat = $Message -replace "`r`n", ' | ' -replace "`r", ' | ' -replace "`n", ' | '
        $line = '{0} [{1}] {2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Level, $flat

        $dir = Split-Path -Parent $file
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
        }
        $enc = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::AppendAllText($file, ($line + [Environment]::NewLine), $enc)
    } catch {
        # Logging must never break the caller.
    }
}

function Write-SMChangeRecord {
    <#
    .SYNOPSIS
        Appends one compact JSON line (a New-SMChangeRecord object) to $SM.ChangeFile.
    .DESCRIPTION
        Write failures throw. The write-ahead record must reach disk before any
        mutation; a missing completion record requires explicit recovery review.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Record
    )

    try {
        $bag  = Get-SMState
        $file = $bag['ChangeFile']
        if (-not $file) { throw 'No ChangeFile in state.' }

        $json = $Record | ConvertTo-Json -Compress -Depth 15
        $json = $json -replace "`r`n", ' ' -replace "`r", ' ' -replace "`n", ' '

        $dir = Split-Path -Parent $file
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
        }
        $enc = New-Object System.Text.UTF8Encoding($false)
        $bytes = $enc.GetBytes($json + [Environment]::NewLine)
        $stream = New-Object IO.FileStream($file, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::Read)
        try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    } catch {
        Write-SMLog -Level ERROR -Message ("Could not write change record: " + $_.Exception.Message)
        throw
    }
}

function Get-SMChangeRecords {
    <#
    .SYNOPSIS
        Reads $SM.ChangeFile and returns the records oldest -> newest.
    .DESCRIPTION
        Missing file (or uninitialised state) returns @(). A line that is not valid
        JSON is skipped and reported with a WARN log line - never an exception.
        -Last n returns only the n newest records (still oldest -> newest).
    #>
    [CmdletBinding()]
    param(
        [ValidateRange(0, 2147483647)] [int] $Last = 0,
        [switch] $Strict
    )

    $file = $null
    try {
        $state = Get-Variable -Name SM -Scope Script -ErrorAction SilentlyContinue
        if ($state -and $state.Value) { $file = $state.Value['ChangeFile'] }
    } catch {
        $file = $null
    }
    if (-not $file -or -not (Test-Path -LiteralPath $file)) { return @() }

    $lines = @()
    try {
        $lines = @(Get-Content -LiteralPath $file -Encoding UTF8 -ErrorAction Stop)
    } catch {
        Write-SMLog -Level WARN -Message ("Could not read change log: " + $_.Exception.Message)
        if ($Strict) { throw }
        return @()
    }

    $records = New-Object System.Collections.ArrayList
    $n = 0
    foreach ($line in $lines) {
        $n++
        if ($null -eq $line) { continue }
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0) { continue }
        $obj = $null
        try {
            $obj = $trimmed | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-SMLog -Level WARN -Message ("Skipped malformed change-log line {0}: {1}" -f $n, $_.Exception.Message)
            if ($Strict) { throw 'Recovery journal contains a malformed record. Preserve the journal and resolve recovery before making further changes.' }
            continue
        }
        if ($null -eq $obj) { continue }
        [void]$records.Add($obj)
    }

    $all = $records.ToArray()
    if ($Last -gt 0 -and $all.Count -gt $Last) {
        return @($all[($all.Count - $Last)..($all.Count - 1)])
    }
    return @($all)
}

function Get-SMLogText {
    <#
    .SYNOPSIS
        Returns $SM.LogFile as a single string ('' when the file does not exist).
        -TailLines n returns only the last n lines.
    #>
    [CmdletBinding()]
    param(
        [ValidateRange(0, 2147483647)] [int] $TailLines = 0
    )

    $file = $null
    try {
        $state = Get-Variable -Name SM -Scope Script -ErrorAction SilentlyContinue
        if ($state -and $state.Value) { $file = $state.Value['LogFile'] }
    } catch {
        $file = $null
    }
    if (-not $file -or -not (Test-Path -LiteralPath $file)) { return '' }

    try {
        $lines = @(Get-Content -LiteralPath $file -Encoding UTF8 -ErrorAction Stop)
    } catch {
        return ''
    }
    if ($lines.Count -eq 0) { return '' }
    if ($TailLines -gt 0 -and $lines.Count -gt $TailLines) {
        $lines = @($lines[($lines.Count - $TailLines)..($lines.Count - 1)])
    }
    return ($lines -join [Environment]::NewLine)
}
