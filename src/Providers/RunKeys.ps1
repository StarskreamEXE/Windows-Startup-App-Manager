# Registry Run / RunOnce launch points.
#
# Run keys are the classic startup location. Their enabled state does NOT live in
# the Run key itself - it lives in StartupApproved (see StartupApproved.ps1), which
# is what Task Manager reads and writes, so our view and Windows' own UI agree.
#
# RunOnce is listed for visibility only: those values delete themselves after they
# run, so there is nothing to toggle.

Set-StrictMode -Version 2.0

function Get-SMRunKeyDefinitions {
    <#
    .SYNOPSIS
        The Run key locations we scan. Internal helper (also a mock point for tests).
    #>
    [CmdletBinding()]
    param()
    return @(
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';             Hive = 'HKCU'; Leaf = 'Run';   Category = 'Registry Run (User)' }
        @{ Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run';             Hive = 'HKLM'; Leaf = 'Run';   Category = 'Registry Run (Machine)' }
        @{ Path = 'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Run'; Hive = 'HKLM'; Leaf = 'Run32'; Category = 'Registry Run (Machine 32-bit)' }
        @{ Path = 'HKCU:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Run'; Hive = 'HKCU'; Leaf = 'Run32'; Category = 'Registry Run (User 32-bit)' }
    )
}

function Get-SMRunOnceDefinitions {
    <#
    .SYNOPSIS
        The RunOnce key locations we scan. Internal helper.
    #>
    [CmdletBinding()]
    param()
    return @(
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'; Hive = 'HKCU' }
        @{ Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce'; Hive = 'HKLM' }
    )
}

function Resolve-SMRunKeyExePath {
    <#
    .SYNOPSIS
        Pulls the executable out of a registered command line.
    .DESCRIPTION
        Local, self-contained copy of the resolver logic: quoted first token wins,
        else the first path ending in a runnable extension, else the first
        whitespace-delimited token. Environment variables are expanded.
        Deliberately independent of Analysis\FileFacts.ps1 - that file is
        dot-sourced after this one, so we must not depend on it.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Command)

    if ([string]::IsNullOrWhiteSpace($Command)) { return '' }
    $c = $Command.Trim()

    $exe = $null
    if ($c.StartsWith('"')) {
        $end = $c.IndexOf('"', 1)
        if ($end -gt 0) { $exe = $c.Substring(1, $end - 1) }
    }
    if ($null -eq $exe) {
        $m = [regex]::Match($c, '^(.*?\.(exe|com|bat|cmd|scr))(\s|$)', 'IgnoreCase')
        if ($m.Success) { $exe = $m.Groups[1].Value }
    }
    if ($null -eq $exe) { $exe = ($c -split '\s+')[0] }
    if ([string]::IsNullOrWhiteSpace($exe)) { return '' }

    try { $exe = [Environment]::ExpandEnvironmentVariables($exe) } catch { }
    return ([string]$exe).Trim()
}

function Get-SMRunKeyEntries {
    <#
    .SYNOPSIS
        Every value under the Run and RunOnce keys, as New-SMEntry objects.
    .DESCRIPTION
        Read-only. A hive that is missing or unreadable is skipped, never fatal.
        Values with an empty name (the key's default value) are skipped.
    #>
    [CmdletBinding()]
    param()

    $out = New-Object System.Collections.ArrayList

    foreach ($def in (Get-SMRunKeyDefinitions)) {
        if (-not (Test-Path -Path $def.Path)) { continue }
        $key = Get-Item -Path $def.Path -ErrorAction Stop

        foreach ($name in $key.GetValueNames()) {
            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            $command = [string]$key.GetValue($name)
            $enabled = $true
            $enabled = Test-SMApproved -Hive $def.Hive -Leaf $def.Leaf -Name $name

            $detail = @(
                "Registry key : $($def.Path)"
                "Value name   : $name"
                "Value data   : $command"
                "Approval     : $($def.Hive) StartupApproved\$($def.Leaf)"
            ) -join [Environment]::NewLine

            [void]$out.Add((New-SMEntry `
                -Name      $name `
                -Category  $def.Category `
                -Kind      'RunKey' `
                -Enabled   ([bool]$enabled) `
                -CanToggle $true `
                -Command   $command `
                -ExePath   (Resolve-SMRunKeyExePath -Command $command) `
                -Source    $def.Path `
                -Data      @{ Hive = $def.Hive; Leaf = $def.Leaf; Name = $name } `
                -Detail    $detail))
        }
    }

    foreach ($def in (Get-SMRunOnceDefinitions)) {
        if (-not (Test-Path -Path $def.Path)) { continue }
        $key = Get-Item -Path $def.Path -ErrorAction Stop

        foreach ($name in $key.GetValueNames()) {
            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            $command = [string]$key.GetValue($name)
            $detail = @(
                "Registry key : $($def.Path)"
                "Value name   : $name"
                "Value data   : $command"
                'Note         : RunOnce entries run once and delete themselves. They cannot be toggled.'
            ) -join [Environment]::NewLine

            [void]$out.Add((New-SMEntry `
                -Name      $name `
                -Category  'RunOnce (one-shot)' `
                -Kind      'RunOnce' `
                -Enabled   $true `
                -CanToggle $false `
                -Command   $command `
                -ExePath   (Resolve-SMRunKeyExePath -Command $command) `
                -Source    $def.Path `
                -Data      @{ Hive = $def.Hive; Leaf = 'RunOnce'; Name = $name } `
                -Detail    $detail))
        }
    }

    return $out.ToArray()
}

function Set-SMRunKeyState {
    <#
    .SYNOPSIS
        Enables or disables a Run key entry through StartupApproved.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Entry,
        [Parameter(Mandatory)] [bool] $Enable
    )

    $data = $Entry.Data
    if ($null -eq $data -or -not $data.ContainsKey('Hive') -or -not $data.ContainsKey('Leaf') -or -not $data.ContainsKey('Name')) {
        throw 'Run key entry is missing the Hive/Leaf/Name data needed to toggle it.'
    }
    Set-SMApproved -Hive $data.Hive -Leaf $data.Leaf -Name $data.Name -Enable $Enable
}
