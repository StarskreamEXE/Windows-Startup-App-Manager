# The user and all-users Startup folders.
#
# Same enable/disable mechanism as the Run keys: the file stays where it is and the
# decision is recorded in StartupApproved under the StartupFolder leaf, keyed by the
# file name. Nothing is ever moved or deleted.

Set-StrictMode -Version 2.0

function Get-SMStartupFolderDefinitions {
    <#
    .SYNOPSIS
        The Startup folders we scan. Internal helper (also the mock point for tests).
    #>
    [CmdletBinding()]
    param()
    return @(
        @{ Dir = [Environment]::GetFolderPath('Startup');       Hive = 'HKCU'; Category = 'Startup Folder (User)' }
        @{ Dir = [Environment]::GetFolderPath('CommonStartup'); Hive = 'HKLM'; Category = 'Startup Folder (All Users)' }
    )
}

function Resolve-SMShortcut {
    <#
    .SYNOPSIS
        Reads a .lnk with WScript.Shell.
    .DESCRIPTION
        Returns @{Target;Arguments;WorkingDirectory}. If the shell object or the
        shortcut cannot be read, Target falls back to the .lnk path itself so the
        entry is still usable and honest about what it knows.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    $result = @{ Target = $Path; Arguments = ''; WorkingDirectory = '' }
    $shell = $null
    try {
        $shell = New-Object -ComObject WScript.Shell
        $link  = $shell.CreateShortcut($Path)
        if (-not [string]::IsNullOrWhiteSpace($link.TargetPath)) { $result.Target = [string]$link.TargetPath }
        if ($null -ne $link.Arguments)        { $result.Arguments        = [string]$link.Arguments }
        if ($null -ne $link.WorkingDirectory) { $result.WorkingDirectory = [string]$link.WorkingDirectory }
    } catch {
        # Broken or locked shortcut: keep the .lnk path as the best available answer.
    } finally {
        if ($null -ne $shell) {
            try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) } catch { }
        }
    }
    return $result
}

function Get-SMStartupFolderEntries {
    <#
    .SYNOPSIS
        Every file in the user and all-users Startup folders, as New-SMEntry objects.
    .DESCRIPTION
        Read-only. desktop.ini is skipped. .lnk files are resolved to their target,
        arguments and working directory.
    #>
    [CmdletBinding()]
    param()

    $out = New-Object System.Collections.ArrayList

    foreach ($def in (Get-SMStartupFolderDefinitions)) {
        $dir = [string]$def.Dir
        if ([string]::IsNullOrWhiteSpace($dir)) { continue }
        if (-not (Test-Path -LiteralPath $dir)) { continue }

        $files = @()
        $files = @(Get-ChildItem -LiteralPath $dir -File -ErrorAction Stop)

        foreach ($file in $files) {
            if ($file.Name -eq 'desktop.ini') { continue }

            $target    = $file.FullName
            $arguments = ''
            $workDir   = ''
            if ($file.Extension -eq '.lnk') {
                $link      = Resolve-SMShortcut -Path $file.FullName
                $target    = [string]$link.Target
                $arguments = [string]$link.Arguments
                $workDir   = [string]$link.WorkingDirectory
            }

            $command = $target
            if (-not [string]::IsNullOrWhiteSpace($arguments)) { $command = ($target + ' ' + $arguments).Trim() }

            $enabled = $true
            $enabled = Test-SMApproved -Hive $def.Hive -Leaf 'StartupFolder' -Name $file.Name

            $detail = @(
                "Folder       : $dir"
                "File         : $($file.FullName)"
                "Target       : $target"
                "Arguments    : $arguments"
                "Working dir  : $workDir"
                "Approval     : $($def.Hive) StartupApproved\StartupFolder"
            ) -join [Environment]::NewLine

            [void]$out.Add((New-SMEntry `
                -Name      $file.Name `
                -Category  $def.Category `
                -Kind      'Folder' `
                -Enabled   ([bool]$enabled) `
                -CanToggle $true `
                -Command   $command `
                -ExePath   $target `
                -Source    $dir `
                -Data      @{ Hive = $def.Hive; Leaf = 'StartupFolder'; Name = $file.Name; File = $file.FullName } `
                -Detail    $detail))
        }
    }

    return $out.ToArray()
}

function Set-SMStartupFolderState {
    <#
    .SYNOPSIS
        Enables or disables a Startup folder item through StartupApproved.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Entry,
        [Parameter(Mandatory)] [bool] $Enable
    )

    $data = $Entry.Data
    if ($null -eq $data -or -not $data.ContainsKey('Hive') -or -not $data.ContainsKey('Leaf') -or -not $data.ContainsKey('Name')) {
        throw 'Startup folder entry is missing the Hive/Leaf/Name data needed to toggle it.'
    }
    Set-SMApproved -Hive $data.Hive -Leaf $data.Leaf -Name $data.Name -Enable $Enable
}
