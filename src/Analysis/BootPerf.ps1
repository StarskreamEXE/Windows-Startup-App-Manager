# Measured boot impact, straight from the Windows Diagnostics-Performance log.
# Event 101 = "this application caused a delay in the startup process".
# Nothing here is estimated - if the log is unavailable the result is empty.
# Dot-source after src/Analysis/FileFacts.ps1.

Set-StrictMode -Version 2.0

function ConvertTo-SMBootPath {
    param([string] $Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    $normalized = ConvertTo-SMNormalPath ([Environment]::ExpandEnvironmentVariables($Path.Trim('"')))
    if ($normalized -notmatch '^(?:[A-Za-z]:\\|\\\\[^\\]+\\[^\\]+\\)') { return '' }
    try { return [IO.Path]::GetFullPath($normalized).ToLowerInvariant() } catch { return '' }
}

function Set-SMBootEvidence {
    param($Entry, [hashtable] $Perf, [int] $PathCount)
    $Entry.BootMs = -1
    $Entry.DegradeMs = -1
    $Entry.BootMeasuredAt = $null
    $Entry.BootConfidence = 'Unavailable: no recent exact-path event'
    $key = ConvertTo-SMBootPath $Entry.ExePath
    if (-not $key) { return }
    if ([IO.Path]::GetFileName($key) -match '^(svchost|powershell|pwsh|wscript|cscript|rundll32|dllhost|cmd|conhost|mshta|java|javaw|python|pythonw|node|dotnet)\.exe$') {
        $Entry.BootConfidence = 'Not attributed: shared host executable'
        return
    }
    if ($PathCount -ne 1) { $Entry.BootConfidence = 'Not attributed: multiple entries use this executable'; return }
    if ($Perf.ContainsKey($key)) {
        $Entry.BootMs = [int]$Perf[$key].TotalMs
        $Entry.DegradeMs = [int]$Perf[$key].DegradeMs
        $Entry.BootMeasuredAt = $Perf[$key].LastSeen
        $Entry.BootConfidence = 'Exact path, unique inventory entry; event is not a causal attribution'
    }
}

function Get-SMBootPerf {
    <#
    .SYNOPSIS
        Reads event 101 from Microsoft-Windows-Diagnostics-Performance/Operational.
    .OUTPUTS
        Hashtable keyed by normalized absolute executable path, value
        @{TotalMs;DegradeMs;LastSeen;Path;FriendlyName}. The entry with the
        most recent measurement wins. Returns @{} when the log cannot be read.
    #>
    [CmdletBinding()]
    param([ValidateRange(1,365)] [int] $Days = 30, [ValidateRange(1,10000)] [int] $MaxEvents = 1000)

    $result = @{}

    $events = $null
    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'
            Id      = 101
            StartTime = (Get-Date).AddDays(-$Days)
        } -MaxEvents $MaxEvents -ErrorAction Stop
    }
    catch {
        if (Get-Command Write-SMLog -ErrorAction SilentlyContinue) {
            Write-SMLog -Level WARN -Message ("Boot performance log unavailable: " + $_.Exception.Message)
        }
        return @{}
    }

    if ($null -eq $events) { return $result }

    foreach ($e in @($events)) {
        try {
            $doc = [xml]$e.ToXml()
            $nodes = $doc.SelectNodes('//*[local-name()="EventData"]/*[local-name()="Data"]')
            if ($null -eq $nodes -or $nodes.Count -eq 0) { continue }

            $data = @{}
            foreach ($n in $nodes) {
                $attr = $n.GetAttribute('Name')
                if (-not [string]::IsNullOrWhiteSpace($attr)) { $data[$attr] = $n.InnerText }
            }

            if (-not $data.ContainsKey('Name')) { continue }
            $name = [string]$data['Name']
            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            $totalMs = -1
            if ($data.ContainsKey('TotalTime')) {
                $tmp = 0
                if ([int]::TryParse([string]$data['TotalTime'], [ref]$tmp)) { $totalMs = $tmp }
            }
            if ($totalMs -lt 0) { continue }

            $degradeMs = 0
            if ($data.ContainsKey('DegradationTime')) {
                $tmp = 0
                if ([int]::TryParse([string]$data['DegradationTime'], [ref]$tmp)) { $degradeMs = $tmp }
            }
            if ($degradeMs -lt 0) { continue }

            $lastSeen = $null
            if ($data.ContainsKey('StartTime')) {
                try {
                    $lastSeen = [datetime]::Parse(
                        [string]$data['StartTime'],
                        [Globalization.CultureInfo]::InvariantCulture,
                        [Globalization.DateTimeStyles]::RoundtripKind)
                } catch { $lastSeen = $null }
            }
            if ($null -eq $lastSeen -and $e.PSObject.Properties['TimeCreated']) {
                try { $lastSeen = [datetime]$e.TimeCreated } catch { $lastSeen = $null }
            }

            $path = ''
            if ($data.ContainsKey('Path')) { $path = [string]$data['Path'] }
            $key = ConvertTo-SMBootPath $path
            if ($null -ne $lastSeen) { $lastSeen = $lastSeen.ToUniversalTime() }
            if (-not $key -or $null -eq $lastSeen -or $lastSeen -lt (Get-Date).ToUniversalTime().AddDays(-$Days) -or $lastSeen -gt (Get-Date).ToUniversalTime().AddMinutes(5)) { continue }
            $friendly = ''
            if ($data.ContainsKey('FriendlyName')) { $friendly = [string]$data['FriendlyName'] }

            if ($result.ContainsKey($key) -and $result[$key].LastSeen -ge $lastSeen) { continue }

            $result[$key] = @{
                TotalMs      = [int]$totalMs
                DegradeMs    = [int]$degradeMs
                LastSeen     = $lastSeen
                Path         = $path
                FriendlyName = $friendly
            }
        }
        catch {
            continue
        }
    }

    return $result
}
