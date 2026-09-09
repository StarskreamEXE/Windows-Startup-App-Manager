# StartupApproved - the exact enable/disable mechanism Task Manager uses.
#
# HKCU/HKLM \Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\<Leaf>
# holds one REG_BINARY value per launch point. The value is 12 bytes:
#   byte 0      : state. EVEN = enabled, ODD = disabled. (Windows writes 02/03,
#                 but 06/07 also occur - hence the parity test, not equality.)
#   bytes 1..3  : zero
#   bytes 4..11 : FILETIME (little-endian) of when it was disabled, zero when enabled.
# No value at all == enabled, because Windows only records a decision once one is made.
#
# Nothing here ever deletes a value - enable/disable only.

Set-StrictMode -Version 2.0

function Get-SMApprovedKeyPath {
    <#
    .SYNOPSIS
        Registry path of the StartupApproved leaf for a hive. Internal helper.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('HKCU','HKLM')] [string] $Hive,
        [Parameter(Mandatory)] [ValidateSet('Run','Run32','StartupFolder')] [string] $Leaf
    )
    $base = if ($Hive -eq 'HKCU') {
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
    } else {
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
    }
    return (Join-Path $base $Leaf)
}

function ConvertFrom-SMApprovedBytes {
    <#
    .SYNOPSIS
        Decodes a StartupApproved REG_BINARY value into "is enabled".
    .DESCRIPTION
        $null or an empty array means Windows has no record for this item,
        which means it has never been disabled - so it is enabled.
        Otherwise byte 0 even = enabled, odd = disabled.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([byte[]] $Bytes)

    if ($null -eq $Bytes) { return $true }
    if ($Bytes.Length -lt 1) { return $true }
    return ((([int]$Bytes[0]) % 2) -eq 0)
}

function New-SMApprovedBytes {
    <#
    .SYNOPSIS
        Builds the 12-byte StartupApproved value for the wanted state.
    .DESCRIPTION
        Enabled : 02 00 00 00 followed by eight zero bytes.
        Disabled: 03 00 00 00 followed by the current time as a little-endian FILETIME.
    #>
    [CmdletBinding()]
    [OutputType([byte[]])]
    param([Parameter(Mandatory)] [bool] $Enable)

    $bytes = New-Object byte[] 12
    if ($Enable) {
        $bytes[0] = 2
    } else {
        $bytes[0] = 3
        $ft = [BitConverter]::GetBytes((Get-Date).ToFileTime())
        [Array]::Copy($ft, 0, $bytes, 4, 8)
    }
    return ,$bytes
}

function Test-SMApproved {
    <#
    .SYNOPSIS
        Is the given launch point enabled according to StartupApproved?
    .DESCRIPTION
        Missing keys and values mean enabled. Read failures propagate so an
        inaccessible registration is never mistaken for a confirmed state.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [ValidateSet('HKCU','HKLM')] [string] $Hive,
        [Parameter(Mandatory)] [ValidateSet('Run','Run32','StartupFolder')] [string] $Leaf,
        [Parameter(Mandatory)] [string] $Name
    )

    $path = Get-SMApprovedKeyPath -Hive $Hive -Leaf $Leaf
    if (-not (Test-Path -Path $path)) { return $true }

    $value = $null
    try {
        $prop = Get-ItemProperty -Path $path -ErrorAction Stop
        if ($null -ne $prop -and $null -ne $prop.PSObject.Properties[$Name]) { $value = $prop.PSObject.Properties[$Name].Value }
    } catch {
        throw
    }
    if ($null -eq $value) { return $true }

    return (ConvertFrom-SMApprovedBytes -Bytes ([byte[]]$value))
}

function Set-SMApproved {
    <#
    .SYNOPSIS
        Writes the StartupApproved record for one launch point.
    .DESCRIPTION
        Creates the leaf key when Windows has never written one. Always writes a
        REG_BINARY value - it never removes anything.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('HKCU','HKLM')] [string] $Hive,
        [Parameter(Mandatory)] [ValidateSet('Run','Run32','StartupFolder')] [string] $Leaf,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [bool]   $Enable
    )

    $path = Get-SMApprovedKeyPath -Hive $Hive -Leaf $Leaf
    if (-not (Test-Path -Path $path)) {
        New-Item -Path $path -Force -ErrorAction Stop | Out-Null
    }
    $bytes = New-SMApprovedBytes -Enable $Enable
    New-ItemProperty -Path $path -Name $Name -Value $bytes -PropertyType Binary -Force -ErrorAction Stop | Out-Null
}
