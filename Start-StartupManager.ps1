#requires -Version 5.1
<#
    Startup Manager 2.0 - entry point.

    Responsibilities (and nothing else):
      1. Make sure we are running elevated (machine-wide Run keys, services and
         most scheduled tasks are invisible or untoggleable without admin).
      2. Dot-source every source file in the LOAD ORDER from docs/ARCHITECTURE.md,
         in that exact order, into ONE script scope.
      3. Initialise the shared state bag and the log.
      4. Show the main window.

    Nothing is applied to the system by this script. See docs/ARCHITECTURE.md.
#>

param(
    # Set by the elevated relaunch so we can tell a fresh start from a relaunch.
    [switch] $Elevated,
    # Skip the elevation step entirely (used by developers and by the test runner).
    [switch] $NoElevate
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------- helpers

function Test-SMIsAdministrator {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Show-SMStartupMessage {
    param([string] $Message, [string] $Caption = 'Startup Manager')
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        [System.Windows.Forms.MessageBox]::Show($Message, $Caption) | Out-Null
    } catch {
        # No WinForms available (headless / broken .NET) - the console message
        # written by the caller is then the only channel, which is fine.
    }
}

# ------------------------------------------------------------------ elevation

if (-not $NoElevate -and -not $Elevated -and -not (Test-SMIsAdministrator)) {
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
            '-File', ('"' + $PSCommandPath + '"'), '-Elevated'
        )
    } catch {
        Show-SMStartupMessage -Message @'
Startup Manager needs administrator rights.

Without them it cannot see machine-wide startup items, services or most
scheduled tasks, and it cannot turn anything on or off.

Right-click "Startup Manager.cmd" and choose "Run as administrator",
or answer Yes to the User Account Control prompt.
'@
    }
    exit
}

# ----------------------------------------------------------------- WinForms

# Theme.ps1 loads these too; Add-Type is a no-op once an assembly is loaded.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -Path (Join-Path $PSScriptRoot 'src\UI\NativeControls.cs') -ReferencedAssemblies System.Windows.Forms, System.Drawing
[StartupManager.NativeTheme]::EnableDpiAwareness()
[System.Windows.Forms.Application]::EnableVisualStyles()

# Give this process its own taskbar identity so Windows shows OUR window icon,
# not powershell.exe's, and groups/pins it as "Startup Manager".
try {
    Add-Type -Namespace SM -Name Shell -MemberDefinition '[DllImport("shell32.dll", SetLastError = true)] public static extern int SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string AppID);'
    [SM.Shell]::SetCurrentProcessExplicitAppUserModelID('skreamb0t.StartupManager') | Out-Null
} catch { }

# ---------------------------------------------------------------- LOAD ORDER

$Root = $PSScriptRoot

# This list is the LOAD ORDER from docs/ARCHITECTURE.md. Order matters:
# Contracts defines the shapes, Paths creates $script:SM, Logging needs $script:SM,
# Providers/Analysis/Engine/Export build on those, UI comes last.
$LoadOrder = @(
    'src\Core\Contracts.ps1'
    'src\Core\Paths.ps1'
    'src\Core\Settings.ps1'
    'src\Core\Logging.ps1'
    'src\Providers\StartupApproved.ps1'
    'src\Providers\RunKeys.ps1'
    'src\Providers\StartupFolders.ps1'
    'src\Providers\ScheduledTasks.ps1'
    'src\Providers\Services.ps1'
    'src\Providers\StoreApps.ps1'
    'src\Analysis\FileFacts.ps1'
    'src\Analysis\BootPerf.ps1'
    'src\Analysis\KnownApps.ps1'
    'src\Analysis\Risk.ps1'
    'src\Engine\Inventory.ps1'
    'src\Engine\Changes.ps1'
    'src\Engine\Backup.ps1'
    'src\Engine\Baseline.ps1'
    'src\Export\Export.ps1'
    'src\Export\Report.ps1'
    'src\UI\Theme.ps1'
    'src\UI\Dialogs.ps1'
    'src\UI\Scan.ps1'
    'src\UI\MainForm.ps1'
)

foreach ($relative in $LoadOrder) {
    $file = Join-Path $Root $relative
    if (-not (Test-Path -LiteralPath $file)) {
        $msg = "Startup Manager cannot start - missing file: $relative`r`nExpected at: $file"
        # -NoElevate is the console/developer path, so the thrown error is visible
        # there. A double-clicked (hidden-window) launch needs the dialog.
        if (-not $NoElevate) { Show-SMStartupMessage -Message $msg }
        throw $msg
    }
    . $file
}

# ---------------------------------------------------------------------- run

$state = Initialize-SMPaths -Root $Root
Write-SMLog -Level INFO -Message 'Startup Manager 2.1.1 starting'

[System.Windows.Forms.Application]::add_ThreadException({
    param($sender, $e)
    $ex = $e.Exception
    $msg = "UI thread exception: $($ex.GetType().FullName): $($ex.Message) | $($ex.StackTrace -replace '\r?\n', ' ; ')"
    try { Write-SMLog -Level ERROR -Message $msg } catch { }
})
try {
    Show-SMMainForm
} catch {
    $detail = "$($_.Exception.GetType().FullName): $($_.Exception.Message)`r`n" +
              "$($_.ScriptStackTrace)`r`n" +
              "$($_.Exception.StackTrace)"
    try { Write-SMLog -Level ERROR -Message ("Unhandled error in Show-SMMainForm: " + $detail) } catch { }
    Show-SMStartupMessage -Message ("Startup Manager hit an unexpected error and had to stop." + "`r`n`r`n" +
        $_.Exception.Message + "`r`n`r`n" +
        "The full details were written to:`r`n" + $state.LogFile)
    exit 1
}
