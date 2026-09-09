# Windows services that start automatically (plus disabled ones, so they can be
# turned back on). Dot-source after src/Core/Contracts.ps1.
# Read-only collector + a single startup-type toggle. Nothing is ever deleted.

Set-StrictMode -Version 2.0

function Get-SMServiceProperty {
    <# Strict-mode safe property read; $null when absent. #>
    [CmdletBinding()]
    param($InputObject, [Parameter(Mandatory)] [string] $Name)

    if ($null -eq $InputObject) { return $null }
    $p = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function Resolve-SMServiceExePath {
    <#
    .SYNOPSIS
        Private resolver: pulls the image path out of a Win32_Service PathName.
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

function Test-SMServiceDelayedStart {
    <#
    .SYNOPSIS
        True when the service is configured for delayed auto-start
        (HKLM\SYSTEM\CurrentControlSet\Services\<name> value DelayedAutostart = 1).
        Read-only; any failure means "not delayed".
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    try {
        $key = 'HKLM:\SYSTEM\CurrentControlSet\Services\' + $Name
        if (-not (Test-Path -LiteralPath $key)) { return $false }
        $item = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
        $prop = $item.PSObject.Properties['DelayedAutostart']
        if ($null -eq $prop) { return $false }
        return ([int]$prop.Value -eq 1)
    }
    catch { return $false }
}

function Get-SMServiceEntries {
    <#
    .SYNOPSIS
        Every service with StartMode Auto (enabled) or Disabled (disabled).
        Manual / boot / system services are not startup items and are skipped.
        Query failures propagate to the scan warning collector.
    #>
    [CmdletBinding()]
    param()

    $out = New-Object System.Collections.ArrayList
    try { $svcs = @(Get-CimInstance -ClassName Win32_Service -ErrorAction Stop) }
    catch { throw }

    foreach ($s in $svcs) {
        $startMode = [string](Get-SMServiceProperty $s 'StartMode')
        if ($startMode -ne 'Auto' -and $startMode -ne 'Disabled') { continue }

        $name    = [string](Get-SMServiceProperty $s 'Name')
        $display = [string](Get-SMServiceProperty $s 'DisplayName')
        if ([string]::IsNullOrWhiteSpace($display)) { $display = $name }
        $pathName  = [string](Get-SMServiceProperty $s 'PathName')
        $startName = [string](Get-SMServiceProperty $s 'StartName')
        $state     = [string](Get-SMServiceProperty $s 'State')
        $svcType   = [string](Get-SMServiceProperty $s 'ServiceType')
        $desc      = [string](Get-SMServiceProperty $s 'Description')
        $procId    = Get-SMServiceProperty $s 'ProcessId'
        $delayed   = Test-SMServiceDelayedStart -Name $name

        $lines = New-Object System.Collections.ArrayList
        if (-not [string]::IsNullOrWhiteSpace($desc)) {
            [void]$lines.Add('Description: ' + ($desc -replace '\s*[\r\n]+\s*', ' '))
        }
        [void]$lines.Add('Runs as: ' + $(if ([string]::IsNullOrWhiteSpace($startName)) { 'n/a' } else { $startName }))
        [void]$lines.Add('State: ' + $(if ([string]::IsNullOrWhiteSpace($state)) { 'n/a' } else { $state }))
        [void]$lines.Add('Start mode: ' + $startMode)
        [void]$lines.Add('Service type: ' + $(if ([string]::IsNullOrWhiteSpace($svcType)) { 'n/a' } else { $svcType }))
        [void]$lines.Add('Delayed auto-start: ' + $(if ($delayed) { 'Yes' } else { 'No' }))
        [void]$lines.Add('Process id: ' + $(if ($null -eq $procId) { 'n/a' } else { [string]$procId }))

        $entry = New-SMEntry -Name ($display + '  [' + $name + ']') -Category ('Service (' + $startMode + ')') -Kind 'Service' `
            -Enabled ($startMode -eq 'Auto') `
            -Command $pathName -ExePath (Resolve-SMServiceExePath $pathName) -Source 'Services' `
            -Data @{ Name = $name; StartName = $startName; Delayed = $delayed; StartMode = $startMode } `
            -Detail ($lines -join [Environment]::NewLine)
        [void]$out.Add($entry)
    }

    return , $out.ToArray()
}

function Set-SMServiceState {
    <# Switches a service between Automatic and Disabled. Never deletes, never stops. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Entry,
        [Parameter(Mandatory)] [bool] $Enable
    )

    $name = [string]$Entry.Data.Name
    $path='HKLM:\SYSTEM\CurrentControlSet\Services\'+$name
    $delayed=Get-SMRegistryValueSnapshot $path 'DelayedAutoStart'
    if ($Enable) { Set-Service -Name $name -StartupType Automatic -ErrorAction Stop }
    else         { Set-Service -Name $name -StartupType Disabled -ErrorAction Stop }
    Restore-SMRegistryValue $path 'DelayedAutoStart' $delayed DWord
}
