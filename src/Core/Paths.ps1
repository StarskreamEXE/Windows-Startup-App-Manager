# Project paths and the shared state bag. Dot-source after Contracts.ps1.

Set-StrictMode -Version 2.0

function Initialize-SMPaths {
    <#
    .SYNOPSIS
        Creates $script:SM - the single shared state bag - and ensures the
        working directories exist. Idempotent. Call once from the entry script
        (and from tests with a temp -Root).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Root)

    $script:SM = @{
        Root       = $Root
        SrcDir     = Join-Path $Root 'src'
        LogDir     = Join-Path $Root 'logs'
        BackupDir  = Join-Path $Root 'backups'
        ReportDir  = Join-Path $Root 'reports'
        ExportDir  = Join-Path $Root 'exports'
        LogFile    = Join-Path $Root 'logs\startup-manager.log'
        ChangeFile = Join-Path $Root 'logs\changes.jsonl'
        # runtime state, owned by Engine/Changes.ps1 and Engine/Inventory.ps1
        Inventory  = @()
        Pending    = [ordered]@{}
        BootPerf   = @{}
    }
    foreach ($d in @($script:SM.LogDir, $script:SM.BackupDir, $script:SM.ReportDir, $script:SM.ExportDir)) {
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
    return $script:SM
}

function Get-SMState {
    <# Returns the shared state bag. Throws if Initialize-SMPaths was never called. #>
    if (-not (Get-Variable -Name SM -Scope Script -ErrorAction SilentlyContinue)) {
        throw 'Startup Manager state not initialised. Call Initialize-SMPaths first.'
    }
    return $script:SM
}
