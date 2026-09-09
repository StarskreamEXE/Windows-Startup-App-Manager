Set-StrictMode -Version 2.0

function ConvertTo-SMBaselineEntries {
    param([AllowEmptyCollection()] [object[]] $Entries)
    $identities = @{}
    foreach ($entry in $Entries) {
        $identity = Get-SMEntryIdentity -Entry $entry
        if ($identities.ContainsKey($identity)) { throw 'Duplicate startup identity in baseline inventory.' }
        $identities[$identity] = $true
        [pscustomobject]@{
            Identity = $identity
            Name = [string]$entry.Name
            Kind = [string]$entry.Kind
            Enabled = [bool]$entry.Enabled
            Command = [string]$entry.Command
            ExePath = [string]$entry.ExePath
            Source = [string]$entry.Source
        }
    }
}

function Save-SMBaseline {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Entries, [Parameter(Mandatory)] [string] $Path)
    $snapshot = [pscustomobject]@{
        SchemaVersion = 1
        CreatedAt = (Get-Date).ToUniversalTime().ToString('o')
        Entries = @(ConvertTo-SMBaselineEntries $Entries)
    }
    $json = ConvertTo-Json -InputObject $snapshot -Depth 5
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($Path), $json, (New-Object Text.UTF8Encoding($false)))
}

function Get-SMBaseline {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($file.Length -gt 20MB) { throw 'Baseline exceeds the 20 MB size limit.' }
    $baseline = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if (-not $baseline.PSObject.Properties['SchemaVersion'] -or $baseline.SchemaVersion -ne 1 -or -not $baseline.PSObject.Properties['Entries']) { throw 'Unsupported baseline schema.' }
    $seen = @{}
    foreach ($entry in @($baseline.Entries)) {
        foreach ($field in @('Identity','Name','Kind','Enabled','Command','ExePath','Source')) {
            if ($null -eq $entry -or -not $entry.PSObject.Properties[$field]) { throw "Baseline entry is missing $field." }
        }
        if ([string]::IsNullOrWhiteSpace($entry.Identity) -or $entry.Enabled -isnot [bool] -or $entry.Kind -notin $script:SMKinds) { throw 'Invalid baseline entry.' }
        if ($seen.ContainsKey($entry.Identity)) { throw 'Duplicate identity in baseline.' }
        $seen[$entry.Identity] = $true
    }
    return $baseline
}

function Compare-SMBaseline {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Baseline, [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Entries)
    $previous = @{}
    foreach ($entry in @($Baseline.Entries)) { $previous[$entry.Identity] = $entry }
    foreach ($current in @(ConvertTo-SMBaselineEntries $Entries)) {
        if (-not $previous.ContainsKey($current.Identity)) {
            [pscustomobject]@{ Change='Added'; Identity=$current.Identity; Name=$current.Name; Kind=$current.Kind; Fields=@(); Before=$null; After=$current }
            continue
        }
        $before = $previous[$current.Identity]
        $fields = @('Name','Enabled','Command','ExePath','Source' | Where-Object { $before.$_ -cne $current.$_ })
        if ($fields.Count) { [pscustomobject]@{ Change='Changed'; Identity=$current.Identity; Name=$current.Name; Kind=$current.Kind; Fields=$fields; Before=$before; After=$current } }
        $previous.Remove($current.Identity)
    }
    foreach ($identity in @($previous.Keys | Sort-Object)) {
        $before = $previous[$identity]
        [pscustomobject]@{ Change='Removed'; Identity=$identity; Name=$before.Name; Kind=$before.Kind; Fields=@(); Before=$before; After=$null }
    }
}
