# Shared contracts for Startup Manager.
# Pure definitions only - no side effects. Dot-sourced first by the entry
# script and by every test file. Every other file builds against this.

Set-StrictMode -Version 2.0

# Provider kinds. Kind decides which provider toggles the entry.
$script:SMKinds = @('RunKey', 'RunOnce', 'Folder', 'Task', 'Service', 'Uwp')

# Risk levels, in display-severity order.
#   Critical   - Windows / driver / security component. Do not disable.
#   Suspicious - unsigned AND running from a throwaway location (Temp, Downloads, AppData root...).
#   Broken     - points at a file that no longer exists.
#   Caution    - disabling may break an app the user relies on.
#   Optional   - convenience, updater, tray helper, telemetry. Safe to disable.
#   Unknown    - nothing matched; not enough evidence to say.
$script:SMRiskLevels = @('Critical', 'Suspicious', 'Broken', 'Caution', 'Optional', 'Unknown')

# Flags are short upper-case tokens shown in the Flags column.
$script:SMFlagList = @(
    'MISSING',      # ExePath does not exist on disk
    'UNSIGNED',     # no Authenticode signature
    'BAD-SIG',      # signature present but invalid / hash mismatch / untrusted
    'TEMP-PATH',    # runs from Temp, Downloads, Desktop, or the AppData root
    'UPDATER',      # name or path looks like an auto-updater / crash reporter / telemetry helper
    'SYSTEM',       # runs as SYSTEM / highest privileges (tasks) or LocalSystem (services)
    'DELAYED',      # service uses delayed auto-start
    'SLOW',         # measured boot-time impact >= 3000 ms
    'MS',           # Microsoft-signed
    'ONE-SHOT'      # RunOnce - runs once then removes itself; cannot be toggled
)

# Signature status vocabulary.
$script:SMSigStatus = @('Valid', 'Unsigned', 'Invalid', 'Unknown')

function New-SMEntry {
    <#
    .SYNOPSIS
        Factory for the one object every layer passes around.
        Providers fill the first block. Analysis (via Inventory) fills the rest.
        Never add ad-hoc properties elsewhere - extend this factory instead.
    #>
    [CmdletBinding()]
    param(
        # ---- filled by the provider ----
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Category,     # human label e.g. 'Registry Run (User)'
        [Parameter(Mandatory)] [ValidateSet('RunKey','RunOnce','Folder','Task','Service','Uwp')] [string] $Kind,
        [Parameter(Mandatory)] [bool]   $Enabled,
        [bool]      $CanToggle = $true,
        [string]    $Command   = '',                   # full command line as registered
        [string]    $ExePath   = '',                   # resolved executable path, '' if unknown
        [string]    $Source    = '',                   # registry key / folder / task path / 'Services'
        [hashtable] $Data      = @{},                  # provider-private data needed to toggle
        [string]    $Detail    = ''                    # kind-specific multi-line info for the details pane
    )
    [pscustomobject]@{
        Id            = 0            # assigned by Get-SMInventory
        Name          = $Name
        Category      = $Category
        Kind          = $Kind
        Enabled       = $Enabled
        CanToggle     = $CanToggle
        Command       = $Command
        ExePath       = $ExePath
        Source        = $Source
        Data          = $Data
        Detail        = $Detail
        # ---- filled by Analysis / Inventory ----
        Exists        = $true
        Publisher     = ''
        Product       = ''
        FileVersion   = ''
        SizeKB        = 0
        SigStatus     = 'Unknown'
        SigSigner     = ''
        BootMs        = -1           # measured total start time from the Diagnostics-Performance log, -1 = no data
        DegradeMs     = -1           # measured boot degradation, -1 = no data
        BootMeasuredAt = $null
        BootConfidence = 'Unavailable'
        SecurityFlags = @()
        RiskEvidence = ''
        Risk          = 'Unknown'
        Flags         = @()          # string[] of $SMFlagList tokens
        What          = ''           # one line: what this thing is
        Explain       = ''           # a paragraph: what it does, who ships it
        DisableEffect = ''           # what happens if you turn it off
    }
}

function New-SMPendingChange {
    <# A staged (not yet applied) change. Held by Engine/Changes.ps1. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Entry,
        [Parameter(Mandatory)] [bool] $To
    )
    [pscustomobject]@{
        Id    = [int]$Entry.Id
        Name  = [string]$Entry.Name
        Kind  = [string]$Entry.Kind
        Risk  = [string]$Entry.Risk
        From  = [bool]$Entry.Enabled
        To    = $To
        Entry = $Entry
    }
}

function New-SMChangeRecord {
    <#
        One line of logs/changes.jsonl. Written after every applied or undone change.
        Data is the provider hashtable so Undo can re-target the same item later
        without a fresh scan.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('apply','undo','prepare','prepare-undo')] [string] $Action,
        [Parameter(Mandatory)] $Entry,
        [Parameter(Mandatory)] [bool] $From,
        [Parameter(Mandatory)] [bool] $To,
        [Parameter(Mandatory)] [bool] $Ok,
        [string] $Error = '',
        [string] $OperationId = '',
        [string] $BatchId = '',
        [string] $UndoOf = '',
        $Before = $null,
        $After = $null,
        [bool] $NeedsRecovery = $false
    )
    [pscustomobject]@{
        ts       = (Get-Date).ToUniversalTime().ToString('o')
        action   = $Action
        id       = [int]$Entry.Id
        name     = [string]$Entry.Name
        kind     = [string]$Entry.Kind
        category = [string]$Entry.Category
        from     = $From
        to       = $To
        ok       = $Ok
        error    = $Error
        data     = $Entry.Data
        source   = $Entry.Source
        operationId = $OperationId
        batchId  = $BatchId
        undoOf   = $UndoOf
        identity = Get-SMEntryIdentity -Entry $Entry
        before   = $Before
        after    = $After
        needsRecovery = $NeedsRecovery
    }
}

function Get-SMEntryIdentity {
    param([Parameter(Mandatory)] $Entry)
    $parts = switch ($Entry.Kind) {
        'Task' { @($Entry.Kind, $Entry.Data.Path, $Entry.Data.Name) }
        'Service' { @($Entry.Kind, $Entry.Data.Name) }
        'Uwp' { @($Entry.Kind, $Entry.Data.Path) }
        'Folder' { @($Entry.Kind, $Entry.Data.Hive, $Entry.Data.Leaf, $Entry.Data.Name) }
        default { @($Entry.Kind, $Entry.Data.Hive, $Entry.Data.Leaf, $Entry.Data.Name, $Entry.Source) }
    }
    return (($parts | ForEach-Object { ([string]$_).ToLowerInvariant() }) | ConvertTo-Json -Compress)
}
