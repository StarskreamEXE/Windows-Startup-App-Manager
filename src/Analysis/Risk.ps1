# Risk classifier. Pure function of an entry's already-filled facts. No I/O.

Set-StrictMode -Version 2.0

function Get-SMRiskAssessment {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Entry)

    $flags = New-Object System.Collections.ArrayList
    $path  = [string]$Entry.ExePath
    $cmd   = [string]$Entry.Command
    $name  = [string]$Entry.Name
    $sig   = [string]$Entry.SigStatus
    $signer = [string]$Entry.SigSigner
    $pub   = [string]$Entry.Publisher
    $kind  = [string]$Entry.Kind
    $data  = $Entry.Data
    if ($null -eq $data) { $data = @{} }

    $hasPath  = -not [string]::IsNullOrWhiteSpace($path)
    $missing  = $hasPath -and [IO.Path]::IsPathRooted($path) -and (-not $Entry.Exists)
    $isMs     = ($signer -match 'Microsoft') -or (($sig -eq 'Valid') -and ($pub -match 'Microsoft'))
    $inWin    = $path -match '(?i)^[A-Z]:\\Windows\\'
    $unsigned = $hasPath -and $Entry.Exists -and ($sig -eq 'Unsigned')
    $badsig   = $hasPath -and $Entry.Exists -and ($sig -eq 'Invalid')
    $tempPath = ($path -match '(?i)\\(Temp|Downloads|Desktop)\\') -or
                ($path -match '(?i)\\AppData\\(Local|Roaming)\\[^\\]+\.exe$') -or
                ($path -match '(?i)\\ProgramData\\[^\\]+\.exe$')
    $updater  = ("$name $cmd" -match '(?i)update|updater|crash|report|telemetry|helper|maintenance')
    $system   = $false
    if ($kind -eq 'Task') {
        $ra = ''; $rl = ''
        if ($data.ContainsKey('RunAs'))    { $ra = [string]$data.RunAs }
        if ($data.ContainsKey('RunLevel')) { $rl = [string]$data.RunLevel }
        $system = ($ra -match '(?i)SYSTEM') -or ($rl -match '(?i)Highest')
    } elseif ($kind -eq 'Service') {
        $sn = ''
        if ($data.ContainsKey('StartName')) { $sn = [string]$data.StartName }
        $system = ($sn -match '(?i)LocalSystem')
    }
    $delayed = ($kind -eq 'Service') -and $data.ContainsKey('Delayed') -and [bool]$data.Delayed
    $slow    = ([int]$Entry.BootMs -ge 3000)

    if ($missing)  { [void]$flags.Add('MISSING') }
    if ($unsigned) { [void]$flags.Add('UNSIGNED') }
    if ($badsig)   { [void]$flags.Add('BAD-SIG') }
    if ($tempPath) { [void]$flags.Add('TEMP-PATH') }
    if ($updater)  { [void]$flags.Add('UPDATER') }
    if ($system)   { [void]$flags.Add('SYSTEM') }
    if ($delayed)  { [void]$flags.Add('DELAYED') }
    if ($slow)     { [void]$flags.Add('SLOW') }
    if ($isMs)     { [void]$flags.Add('MS') }
    if ($kind -eq 'RunOnce') { [void]$flags.Add('ONE-SHOT') }

    $known = Find-SMKnownApp -Name $name -Command $cmd

    # ---- risk ----
    $risk = 'Unknown'
    if ($missing) { $risk = 'Broken' }
    elseif ($null -ne $known) { $risk = $known.Risk }
    elseif (($unsigned -or $badsig) -and $tempPath) { $risk = 'Suspicious' }
    elseif ($unsigned -or $badsig) { $risk = 'Caution' }
    elseif ($updater) { $risk = 'Optional' }
    elseif ($kind -eq 'Uwp') { $risk = 'Optional' }
    elseif ($isMs) { $risk = 'Caution' }

    # ---- text ----
    $file = ''
    if ($hasPath) { $file = [IO.Path]::GetFileName($path) }
    $where = switch ($kind) {
        'RunKey'  { 'from a registry Run key' }
        'RunOnce' { 'from a RunOnce key (runs once, then removes itself)' }
        'Folder'  { 'from a Startup folder shortcut' }
        'Task'    { 'by a scheduled task at logon/boot' }
        'Service' { 'as a Windows service' }
        'Uwp'     { 'as a Store app startup task' }
        default   { 'at startup' }
    }
    $who = if ($pub) { $pub } elseif ($Entry.Product) { [string]$Entry.Product } else { '' }

    if ($null -ne $known) {
        $what = $known.What; $explain = $known.Explain; $effect = $known.DisableEffect
    } else {
        $what = if ($who -and $file) { "$who program ($file) started $where" }
                elseif ($file)       { "$file started $where" }
                else                 { "$name started $where" }
        $explain = "Registered to launch $where."
        if ($who) { $explain += " Published by $who." }
        $effect = 'This startup registration will no longer launch automatically. Its application or dependent features may stop working; the impact has not been verified.'
    }
    if ($risk -eq 'Critical') { $effect = 'Review carefully before disabling this matched component. ' + $effect }
    if ($missing) { $what = "File not found or inaccessible: $file"; $effect = 'The resolved executable could not be found. Verify the path and permissions before disabling; other launch paths may still work.' }
    if ($kind -eq 'RunOnce') { $effect = 'Cannot be toggled. It runs once at next logon and removes itself.' }
    $evidence = 'Heuristic only; publisher, location and privileges do not establish a Windows dependency or prove safety.'
    if ($null -ne $known) { $evidence = "Name/command pattern matched '$($known.What)'. This is not verified application identity. " + $evidence }

    return @{
        Risk          = $risk
        Flags         = [string[]]$flags.ToArray()
        What          = $what
        Explain       = $explain
        DisableEffect = $effect
        RiskEvidence  = $evidence
        SecurityFlags = [string[]]@($flags | Where-Object { $_ -in @('UNSIGNED','BAD-SIG','TEMP-PATH','SYSTEM') })
    }
}
