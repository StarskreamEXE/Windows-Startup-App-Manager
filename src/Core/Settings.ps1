Set-StrictMode -Version 2.0

function Get-SMPreferences {
    param([Parameter(Mandatory)] [string] $Path)
    $preferences = @{ Zoom = 1.0; ReducedMotion = $false }
    if (-not (Test-Path -LiteralPath $Path)) { return $preferences }
    try {
        $saved = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($saved.PSObject.Properties['Zoom']) {
            $zoom = [double]$saved.Zoom
            if ($zoom -ge 0.75 -and $zoom -le 1.5) { $preferences.Zoom = $zoom }
        }
        if ($saved.PSObject.Properties['ReducedMotion'] -and $saved.ReducedMotion -is [bool]) {
            $preferences.ReducedMotion = $saved.ReducedMotion
        }
    } catch { }
    return $preferences
}

function Save-SMPreferences {
    param([Parameter(Mandatory)] [string] $Path, [ValidateRange(0.75,1.5)] [double] $Zoom, [bool] $ReducedMotion)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) { [void](New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop) }
    $json = @{ Zoom = $Zoom; ReducedMotion = $ReducedMotion } | ConvertTo-Json
    [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding($false)))
}
