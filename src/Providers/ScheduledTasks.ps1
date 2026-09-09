# Scheduled tasks that run at boot or at logon.
# Dot-source after src/Core/Contracts.ps1 (New-SMEntry lives there).
# Read-only collector + a single enable/disable toggle. Nothing is ever deleted.

Set-StrictMode -Version 2.0

# A task counts as a startup item when any of its triggers is one of these
# CIM classes (MSFT_TaskLogonTrigger / MSFT_TaskBootTrigger / MSFT_TaskSessionStateChangeTrigger).
$script:SMTaskStartupTriggerPattern = 'LogonTrigger|BootTrigger|SessionStateChangeTrigger'

function Get-SMTaskProperty {
    <#
    .SYNOPSIS
        Strict-mode safe property read. Returns $null when the object is $null
        or does not carry the property (CIM trigger classes differ per type).
    #>
    [CmdletBinding()]
    param($InputObject, [Parameter(Mandatory)] [string] $Name)

    if ($null -eq $InputObject) { return $null }
    $p = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function Resolve-SMTaskExePath {
    <#
    .SYNOPSIS
        Private resolver: pulls the executable out of a task action command line.
        Quoted first token, else the first ...\<something>.exe|com|bat|cmd|scr,
        else the first whitespace-delimited token. Environment variables expanded.
    #>
    [CmdletBinding()]
    param([string] $Command)

    if ([string]::IsNullOrWhiteSpace($Command)) { return '' }
    $c = $Command.Trim()
    $path = ''

    if ($c.StartsWith('"')) {
        $end = $c.IndexOf('"', 1)
        if ($end -gt 1) { $path = $c.Substring(1, $end - 1) }
    }
    if ([string]::IsNullOrWhiteSpace($path)) {
        $m = [regex]::Match($c, '^.*?\.(exe|com|bat|cmd|scr)(?=$|[\s"])', 'IgnoreCase')
        if ($m.Success) { $path = $m.Value }
    }
    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = ($c -split '\s+')[0]
    }
    if ([string]::IsNullOrWhiteSpace($path)) { return '' }

    try { $path = [Environment]::ExpandEnvironmentVariables($path) } catch { }
    return $path.Trim().Trim('"')
}

function Get-SMTaskTriggerLine {
    <#
    .SYNOPSIS
        One human-readable line for a single trigger: type, plus UserId and Delay
        when that trigger type carries them.
    #>
    [CmdletBinding()]
    param($Trigger)

    $class = [string](Get-SMTaskProperty (Get-SMTaskProperty $Trigger 'CimClass') 'CimClassName')
    if ([string]::IsNullOrWhiteSpace($class)) { $class = 'UnknownTrigger' }
    $line = 'Trigger: ' + ($class -replace '^MSFT_Task', '')

    $user = Get-SMTaskProperty $Trigger 'UserId'
    if (-not [string]::IsNullOrWhiteSpace([string]$user)) { $line += '  user: ' + [string]$user }

    $delay = Get-SMTaskProperty $Trigger 'Delay'
    if (-not [string]::IsNullOrWhiteSpace([string]$delay)) { $line += '  delay: ' + [string]$delay }

    $enabled = Get-SMTaskProperty $Trigger 'Enabled'
    if ($null -ne $enabled -and -not [bool]$enabled) { $line += '  (trigger disabled)' }

    return $line
}

function Test-SMTaskIsStartupTask {
    <# True when the task has at least one logon / boot / session-state trigger. #>
    [CmdletBinding()]
    param($Task)

    foreach ($tr in @(Get-SMTaskProperty $Task 'Triggers')) {
        if ($null -eq $tr) { continue }
        $class = [string](Get-SMTaskProperty (Get-SMTaskProperty $tr 'CimClass') 'CimClassName')
        if ($class -match $script:SMTaskStartupTriggerPattern) { return $true }
    }
    return $false
}

function Get-SMScheduledTaskEntries {
    <#
    .SYNOPSIS
        Every scheduled task with a logon / boot / session-state-change trigger.
        Returns New-SMEntry objects; returns an empty array if the task service
        cannot be queried (never throws).
    #>
    [CmdletBinding()]
    param()

    $out = New-Object System.Collections.ArrayList
    try { $tasks = @(Get-ScheduledTask -ErrorAction Stop) }
    catch { throw }

    foreach ($t in $tasks) {
        if (-not (Test-SMTaskIsStartupTask $t)) { continue }

        $taskName = [string](Get-SMTaskProperty $t 'TaskName')
        $taskPath = [string](Get-SMTaskProperty $t 'TaskPath')
        $state    = [string](Get-SMTaskProperty $t 'State')
        $enabled  = Get-SMTaskProperty (Get-SMTaskProperty $t 'Settings') 'Enabled'
        if ($null -eq $enabled) { $enabled = ($state -ne 'Disabled') }

        # command = first action that actually executes something
        $cmd = ''
        foreach ($a in @(Get-SMTaskProperty $t 'Actions')) {
            $exe = [string](Get-SMTaskProperty $a 'Execute')
            if (-not [string]::IsNullOrWhiteSpace($exe)) {
                $cmd = ($exe + ' ' + [string](Get-SMTaskProperty $a 'Arguments')).Trim()
                break
            }
        }

        $category = 'Scheduled Task'
        if ($taskPath -like '\Microsoft\*') { $category = 'Scheduled Task (Windows)' }

        $lines = New-Object System.Collections.ArrayList
        foreach ($tr in @(Get-SMTaskProperty $t 'Triggers')) {
            if ($null -eq $tr) { continue }
            [void]$lines.Add((Get-SMTaskTriggerLine $tr))
        }

        $principal = Get-SMTaskProperty $t 'Principal'
        $runAs     = [string](Get-SMTaskProperty $principal 'UserId')
        $runLevel  = [string](Get-SMTaskProperty $principal 'RunLevel')
        $logonType = [string](Get-SMTaskProperty $principal 'LogonType')
        if ([string]::IsNullOrWhiteSpace($runAs)) {
            $gid = [string](Get-SMTaskProperty $principal 'GroupId')
            if (-not [string]::IsNullOrWhiteSpace($gid)) { $runAs = $gid }
        }
        $runAsShown = $runAs
        if ($runAs -eq 'S-1-5-18') { $runAsShown = 'S-1-5-18 (SYSTEM)' }
        if ([string]::IsNullOrWhiteSpace($runAsShown)) { $runAsShown = 'n/a' }
        [void]$lines.Add('Runs as: ' + $runAsShown)
        [void]$lines.Add('Run level: ' + $(if ([string]::IsNullOrWhiteSpace($runLevel)) { 'n/a' } else { $runLevel }))
        [void]$lines.Add('Logon type: ' + $(if ([string]::IsNullOrWhiteSpace($logonType)) { 'n/a' } else { $logonType }))

        $author = [string](Get-SMTaskProperty $t 'Author')
        if (-not [string]::IsNullOrWhiteSpace($author)) { [void]$lines.Add('Author: ' + $author) }
        $desc = [string](Get-SMTaskProperty $t 'Description')
        if (-not [string]::IsNullOrWhiteSpace($desc)) {
            [void]$lines.Add('Description: ' + ($desc -replace '\s*[\r\n]+\s*', ' '))
        }

        # run history - the task service can refuse this per task; never fatal
        $info = $null
        try { $info = Get-ScheduledTaskInfo -InputObject $t -ErrorAction Stop } catch { $info = $null }
        if ($null -eq $info) {
            [void]$lines.Add('Last run: n/a')
            [void]$lines.Add('Last result: n/a')
            [void]$lines.Add('Next run: n/a')
            [void]$lines.Add('Missed runs: n/a')
        }
        else {
            $lastRun = Get-SMTaskProperty $info 'LastRunTime'
            [void]$lines.Add('Last run: ' + $(if ($null -eq $lastRun) { 'n/a' } else { [string]$lastRun }))

            $res = Get-SMTaskProperty $info 'LastTaskResult'
            if ($null -eq $res) { [void]$lines.Add('Last result: n/a') }
            else {
                # LastTaskResult comes back as an unsigned 32-bit value; HRESULT
                # failure codes (0x80070002 etc.) overflow [int], so widen first.
                $resNum = [long]$res
                [void]$lines.Add(('Last result: 0x{0:X8} ({1})' -f $resNum, $resNum))
            }

            $next = Get-SMTaskProperty $info 'NextRunTime'
            [void]$lines.Add('Next run: ' + $(if ($null -eq $next) { 'n/a' } else { [string]$next }))

            $missed = Get-SMTaskProperty $info 'NumberOfMissedRuns'
            [void]$lines.Add('Missed runs: ' + $(if ($null -eq $missed) { 'n/a' } else { [string]$missed }))
        }

        $entry = New-SMEntry -Name $taskName -Category $category -Kind 'Task' `
            -Enabled ([bool]$enabled) `
            -Command $cmd -ExePath (Resolve-SMTaskExePath $cmd) -Source $taskPath `
            -Data @{ Name = $taskName; Path = $taskPath; RunAs = $runAs; RunLevel = $runLevel } `
            -Detail ($lines -join [Environment]::NewLine)
        [void]$out.Add($entry)
    }

    return , $out.ToArray()
}

function Set-SMScheduledTaskState {
    <# Enables or disables one scheduled task. Never deletes. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Entry,
        [Parameter(Mandatory)] [bool] $Enable
    )

    $task=Get-SMExactScheduledTask -Entry $Entry
    if ($Enable) { Enable-ScheduledTask -InputObject $task -ErrorAction Stop | Out-Null }
    else         { Disable-ScheduledTask -InputObject $task -ErrorAction Stop | Out-Null }
}

function Get-SMExactScheduledTask {
    param([Parameter(Mandatory)]$Entry)
    $matches=@(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskName -eq [string]$Entry.Data.Name -and $_.TaskPath -eq [string]$Entry.Data.Path })
    if ($matches.Count -ne 1) { throw 'The exact scheduled task identity is absent or ambiguous. Refresh before changing it.' }
    return $matches[0]
}
