# Microsoft Store (UWP/packaged) app startup tasks.
# Dot-source after src/Core/Contracts.ps1.
# Read-only collector + a State toggle (2 = on, 1 = off). Nothing is ever deleted.

Set-StrictMode -Version 2.0

$script:SMStoreAppRoot = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData'

function Get-SMStoreAppFriendlyName {
    <#
    .SYNOPSIS
        Strips the 13-character publisher hash off a package family name
        (Contoso.App_8wekyb3d8bbwe -> Contoso.App) for display. The full package
        name is kept in Detail and in Data.
    #>
    [CmdletBinding()]
    param([AllowEmptyString()] [string] $Package)

    if ([string]::IsNullOrWhiteSpace($Package)) { return '' }
    return ($Package -replace '_[a-z0-9]{13}$', '')
}

function Get-SMStoreAppEntries {
    <#
    .SYNOPSIS
        Startup tasks registered by packaged (Store) apps. States 2 and 4 are
        enabled; policy-managed and unknown states are read-only. Read errors
        propagate to the scan warning collector.
    #>
    [CmdletBinding()]
    param()

    $out = New-Object System.Collections.ArrayList
    try {
        if (-not (Test-Path -LiteralPath $script:SMStoreAppRoot)) { return , $out.ToArray() }
        $packages = @(Get-ChildItem -LiteralPath $script:SMStoreAppRoot -ErrorAction Stop)
    }
    catch { throw }

    foreach ($pkg in $packages) {
        $tasksKey = Join-Path $pkg.PSPath 'StartupTasks'
        if (-not (Test-Path -LiteralPath $tasksKey)) { continue }

        $tasks = @()
        $tasks = @(Get-ChildItem -LiteralPath $tasksKey -ErrorAction Stop)

        foreach ($task in $tasks) {
            $package  = [string]$pkg.PSChildName
            $taskName = [string]$task.PSChildName
            $friendly = Get-SMStoreAppFriendlyName -Package $package

            $state = 0
            try {
                $item = Get-ItemProperty -LiteralPath $task.PSPath -Name 'State' -ErrorAction Stop
                $prop = $item.PSObject.Properties['State']
                if ($null -ne $prop) { $state = [int]$prop.Value }
            }
            catch { throw }

            $lines = New-Object System.Collections.ArrayList
            [void]$lines.Add('Package: ' + $package)
            [void]$lines.Add('Startup task: ' + $taskName)
            [void]$lines.Add('State value: ' + [string]$state + $(if ($state -in 2,4) { ' (enabled)' } else { ' (disabled)' }))
            if ($state -notin 0,1,2) { [void]$lines.Add('Read-only: policy-managed or unknown startup state.') }
            [void]$lines.Add('Registry: ' + [string]$task.PSPath)

            $entry = New-SMEntry -Name ($friendly + ' \ ' + $taskName) -Category 'Store App Startup Task' -Kind 'Uwp' `
                -Enabled ($state -in 2,4) -CanToggle ($state -in 0,1,2) `
                -Command '(Store app package)' -ExePath '' -Source ([string]$task.PSPath) `
                -Data @{ Path = [string]$task.PSPath; Package = $package; Task = $taskName; State=$state } `
                -Detail ($lines -join [Environment]::NewLine)
            [void]$out.Add($entry)
        }
    }

    return , $out.ToArray()
}

function Set-SMStoreAppState {
    <# Writes the State DWORD: 2 = enabled, 1 = disabled. Never deletes the key. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Entry,
        [Parameter(Mandatory)] [bool] $Enable
    )

    $value = 1
    if ($Enable) { $value = 2 }
    $current=Get-ItemProperty -LiteralPath $Entry.Data.Path -Name State -ErrorAction Stop
    if ([int]$current.State -notin 0,1,2) { throw 'Store startup state is managed by policy or unknown.' }
    Set-ItemProperty -LiteralPath ([string]$Entry.Data.Path) -Name 'State' -Value $value -Type DWord -ErrorAction Stop
}
