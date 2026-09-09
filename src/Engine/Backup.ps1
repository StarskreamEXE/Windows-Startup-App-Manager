# Registry backup of every key this tool can write to.

Set-StrictMode -Version 2.0

function Invoke-SMRegExport {
    param([string] $Key, [string] $Out)
    & reg.exe export $Key $Out /y 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Registry export failed for $Key (exit $LASTEXITCODE)." }
    if (-not (Test-Path -LiteralPath $Out)) { throw "Registry export produced no file for $Key." }
    $content=[IO.File]::ReadAllText($Out, [Text.Encoding]::Unicode)
    if ($content -notmatch '^Windows Registry Editor Version 5\.00' -or $content -notmatch '(?m)^\[HKEY_') { throw "Registry export is invalid or empty for $Key." }
    return $true
}

function Backup-SMRegistry {
    $stamp = (Get-Date -Format 'yyyy-MM-dd_HHmmss') + '_' + [guid]::NewGuid().ToString('N')
    $file  = Join-Path $script:SM.BackupDir ("startup_backup_" + $stamp + ".reg")
    $keys  = @(
        'HKCU\Software\Microsoft\Windows\CurrentVersion\Run'
        'HKLM\Software\Microsoft\Windows\CurrentVersion\Run'
        'HKLM\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Run'
        'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
        'HKLM\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
    )
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('Windows Registry Editor Version 5.00')
    [void]$sb.AppendLine('; Startup Manager backup ' + $stamp)
    foreach ($k in $keys) {
        $providerPath=$k -replace '^HKCU\\','HKCU:\' -replace '^HKLM\\','HKLM:\'
        if (-not (Test-Path -LiteralPath $providerPath -ErrorAction Stop)) { continue }
        $tmp = Join-Path $script:SM.BackupDir ([guid]::NewGuid().ToString('N') + '.reg')
        if (Invoke-SMRegExport -Key $k -Out $tmp) {
            $lines = @(Get-Content -LiteralPath $tmp -Encoding Unicode)
            if ($lines.Count -gt 1) { foreach ($l in $lines[1..($lines.Count - 1)]) { [void]$sb.AppendLine($l) } }
        }
    }
    [IO.File]::WriteAllText($file, $sb.ToString(), [Text.Encoding]::Unicode)
    Write-SMLog -Level INFO -Message "Registry backup written: $file"
    return $file
}

function Backup-SMChangeBatch {
    param([Parameter(Mandatory)][array]$Changes,[Parameter(Mandatory)][string]$BatchId)
    $file=Join-Path $script:SM.BackupDir ('batch_'+$BatchId+'.json')
    $document=[pscustomobject]@{Schema=1;BatchId=$BatchId;Created=(Get-Date).ToUniversalTime().ToString('o');Changes=@($Changes | ForEach-Object {
        [pscustomobject]@{Identity=(Get-SMEntryIdentity $_.Entry);Entry=$_.Entry;Before=$_.BeforeState;Requested=$_.To}
    })}
    $json=$document | ConvertTo-Json -Depth 20
    $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes($json)
    $stream=New-Object IO.FileStream($file,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try { $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    $check=Get-Content -LiteralPath $file -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($check.BatchId -ne $BatchId -or @($check.Changes).Count -ne $Changes.Count) { throw 'Recovery snapshot verification failed. No changes applied.' }
    return $file
}
