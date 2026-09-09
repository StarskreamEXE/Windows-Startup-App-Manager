# Pending-change set: stage -> confirm -> apply -> log -> undo.
# This is the ONLY place that calls Set-SMEntryState on behalf of the UI.

Set-StrictMode -Version 2.0

function Add-SMPendingChange {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Entry, [Parameter(Mandatory)] [bool] $Enable)
    if (-not $Entry.CanToggle) { throw "'$($Entry.Name)' cannot be toggled." }
    $key = [string]$Entry.Id   # string keys: an int would index the OrderedDictionary by position
    if ($Enable -eq [bool]$Entry.Enabled) {
        if ($script:SM.Pending.Contains($key)) { $script:SM.Pending.Remove($key) }
        return
    }
    $before = Get-SMEntryStateSnapshot -Entry $Entry
    if ([bool]$before.Enabled -ne [bool]$Entry.Enabled) { throw 'This item changed since the scan. Refresh before staging.' }
    if ($script:SM.Pending.Contains($key)) { $before = $script:SM.Pending[$key].BeforeState }
    $pending = New-SMPendingChange -Entry $Entry -To $Enable
    $pending | Add-Member NoteProperty BeforeState $before
    $script:SM.Pending[$key] = $pending
}

function Remove-SMPendingChange {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [int] $Id)
    if ($script:SM.Pending.Contains([string]$Id)) { $script:SM.Pending.Remove([string]$Id) }
}

function Get-SMPendingChanges {
    $list = @()
    foreach ($k in @($script:SM.Pending.Keys)) { $list += $script:SM.Pending[$k] }
    return ,[array]$list
}

function Clear-SMPendingChanges { $script:SM.Pending.Clear() }

function Invoke-SMApplyChanges {
    Assert-SMRecoveryJournalComplete
    $pending = Get-SMPendingChanges
    if ($pending.Count -eq 0) { return ,@() }
    foreach ($change in $pending) {
        $current = Get-SMEntryStateSnapshot $change.Entry
        if (-not (Test-SMSnapshotEqual $current $change.BeforeState)) { throw "'$($change.Name)' changed outside this app. Refresh and restage before applying." }
    }
    $batchId = [guid]::NewGuid().ToString()
    $backup = Backup-SMChangeBatch -Changes $pending -BatchId $batchId
    $results = @()
    foreach ($p in $pending) {
        $operationId = [guid]::NewGuid().ToString()
        $recordArgs = @{ Entry=$p.Entry; From=$p.From; To=$p.To; OperationId=$operationId; BatchId=$batchId; Before=$p.BeforeState }
        Write-SMChangeRecord (New-SMChangeRecord @recordArgs -Action prepare -Ok $false)
        $ok = $false; $err = ''
        $after = $null
        $attempted=$false
        $needsRecovery=$false
        try {
            if (-not (Test-SMSnapshotEqual (Get-SMEntryStateSnapshot $p.Entry) $p.BeforeState)) { throw 'State changed during apply. No change made to this item.' }
            $attempted=$true
            Set-SMEntryState -Entry $p.Entry -Enable $p.To
            $after = Get-SMEntryStateSnapshot $p.Entry
            if ([bool]$after.Enabled -ne $p.To) { throw 'Windows readback did not confirm the requested state.' }
            if ($p.BeforeState.PSObject.Properties['Configuration'] -and $after.Configuration -cne $p.BeforeState.Configuration) { throw 'The startup target changed during apply.' }
            if ($p.Kind -eq 'Service' -and -not (Test-SMSnapshotEqual $after.Delayed $p.BeforeState.Delayed)) { throw 'The service delayed-start setting was not preserved.' }
            $p.Entry.Enabled = $p.To
            $ok = $true
        } catch {
            $err = $_.Exception.Message
            if ($attempted) {
                $needsRecovery=$true
                try { $after=Get-SMEntryStateSnapshot $p.Entry; $needsRecovery=-not (Test-SMSnapshotEqual $after $p.BeforeState) } catch { }
            }
        }
        $rec = New-SMChangeRecord @recordArgs -Action apply -Ok $ok -Error $err -After $after -NeedsRecovery $needsRecovery
        Write-SMChangeRecord -Record $rec
        if ($ok) { Remove-SMPendingChange -Id $p.Id }
        $state = if ($p.To) { 'ENABLED' } else { 'DISABLED' }
        if ($ok) { Write-SMLog -Level INFO  -Message "Applied: '$($p.Name)' [$($p.Kind)] -> $state" }
        else     { Write-SMLog -Level ERROR -Message "Apply failed: '$($p.Name)' [$($p.Kind)] -> $state : $err" }
        $results += @{ Id = $p.Id; Name = $p.Name; Ok = $ok; Error = $err; From = $p.From; To = $p.To; BatchId=$batchId; OperationId=$operationId; VerifiedState=$after; Backup=$backup }
        if ($needsRecovery) { throw "'$($p.Name)' may have changed but could not be verified. Recover interrupted operation $operationId before further changes. $err" }
    }
    return ,[array]$results
}

function ConvertTo-SMHashtable {
    param($Obj)
    $h = @{}
    if ($null -eq $Obj) { return $h }
    if ($Obj -is [hashtable]) { return $Obj }
    foreach ($p in $Obj.PSObject.Properties) { $h[$p.Name] = $p.Value }
    return $h
}

function Undo-SMLastChange {
    $records = @(Get-SMUndoCandidates)
    if ($records.Count) { return (Undo-SMOperation $records[0]) }
    return $null
}

function Test-SMSnapshotEqual {
    param($Left, $Right)
    return (($Left | ConvertTo-Json -Compress -Depth 15) -ceq ($Right | ConvertTo-Json -Compress -Depth 15))
}

function Get-SMUndoCandidates {
    Assert-SMRecoveryJournalComplete
    $records = @(Get-SMChangeRecords -Strict)
    $undone = @{}
    foreach ($record in $records) {
        if ($record.action -eq 'undo' -and $record.ok -and $record.PSObject.Properties['undoOf']) { $undone[$record.undoOf] = $true }
    }
    for ($index=$records.Count-1; $index -ge 0; $index--) {
        $record=$records[$index]
        if ($record.action -eq 'apply' -and $record.ok -and $record.PSObject.Properties['operationId'] -and $record.operationId -and -not $undone.ContainsKey($record.operationId)) { $record }
    }
}

function Get-SMInterruptedOperations {
    $records=@(Get-SMChangeRecords -Strict)
    $finished=@{}
    foreach ($record in $records) {
        if ($record.action -in 'apply','undo' -and $record.PSObject.Properties['operationId'] -and $record.operationId -and (-not $record.PSObject.Properties['needsRecovery'] -or -not $record.needsRecovery)) { $finished[$record.operationId]=$true }
    }
    foreach ($record in $records) {
        if ($record.action -in 'prepare','prepare-undo' -and -not $finished.ContainsKey($record.operationId)) { $record }
    }
}

function Assert-SMRecoveryJournalComplete {
    $interrupted=@(Get-SMInterruptedOperations)
    if ($interrupted.Count) { throw "An interrupted change needs recovery review ($($interrupted[0].operationId)). Use History and preserve logs/changes.jsonl and backups before further changes." }
}

function Restore-SMInterruptedOperation {
    param([Parameter(Mandatory)][string]$OperationId)
    $matches=@(Get-SMInterruptedOperations | Where-Object { $_.operationId -eq $OperationId })
    if ($matches.Count -ne 1) { throw 'Interrupted operation was not found uniquely.' }
    $record=$matches[0]
    $entry=New-SMEntry -Name $record.name -Category $record.category -Kind $record.kind -Enabled ([bool]$record.from) -Data (ConvertTo-SMHashtable $record.data) -Source $record.source
    $entry.Id=[int]$record.id
    $current=Get-SMEntryStateSnapshot $entry
    if ($record.before.PSObject.Properties['Configuration'] -and $current.Configuration -cne $record.before.Configuration) { throw 'The startup target configuration changed; automatic recovery refused.' }
    Restore-SMEntryStateSnapshot $entry $record.before
    $after=Get-SMEntryStateSnapshot $entry
    if (-not (Test-SMSnapshotEqual $after $record.before)) { throw 'Interrupted operation restoration could not be verified.' }
    $action=if ($record.action -eq 'prepare-undo') {'undo'} else {'apply'}
    Write-SMChangeRecord (New-SMChangeRecord -Action $action -Entry $entry -From ([bool]$record.from) -To ([bool]$record.to) -Ok $false -Error 'Interrupted operation restored to its write-ahead state.' -OperationId $record.operationId -BatchId $record.batchId -UndoOf $record.undoOf -Before $record.before -After $after)
    return @{Ok=$true;Name=$record.name;Error=''}
}

function Undo-SMOperation {
    param($Record)
    $entry=New-SMEntry -Name $Record.name -Category $Record.category -Kind $Record.kind -Enabled ([bool]$Record.to) -Data (ConvertTo-SMHashtable $Record.data) -Source $Record.source
    $entry.Id=[int]$Record.id
    $current=Get-SMEntryStateSnapshot $entry
    if (-not (Test-SMSnapshotEqual $current $Record.after)) { return @{Ok=$false;Name=$Record.name;Error='Current configuration differs from the applied state; undo refused.'} }
    $args=@{Entry=$entry;From=[bool]$Record.to;To=[bool]$Record.from;OperationId=[guid]::NewGuid().ToString();BatchId=$Record.batchId;UndoOf=$Record.operationId;Before=$current}
    Write-SMChangeRecord (New-SMChangeRecord @args -Action prepare-undo -Ok $false)
    $ok=$false; $errorText=''; $after=$null; $needsRecovery=$false
    try {
        Restore-SMEntryStateSnapshot -Entry $entry -Snapshot $Record.before
        $after=Get-SMEntryStateSnapshot $entry
        if (-not (Test-SMSnapshotEqual $after $Record.before)) { throw 'Restored state could not be verified.' }
        $ok=$true
    } catch {
        $errorText=$_.Exception.Message
        $needsRecovery=$true
        try { $after=Get-SMEntryStateSnapshot $entry; $needsRecovery=-not (Test-SMSnapshotEqual $after $current) } catch { }
    }
    Write-SMChangeRecord (New-SMChangeRecord @args -Action undo -Ok $ok -Error $errorText -After $after -NeedsRecovery $needsRecovery)
    return @{Ok=$ok;Name=$Record.name;Error=$errorText}
}

function Undo-SMLastBatch {
    $records=@(Get-SMUndoCandidates)
    if (-not $records.Count) { return ,@() }
    $batch=$records[0].batchId
    $results=@()
    foreach ($record in $records) { if ($record.batchId -eq $batch) { $result=Undo-SMOperation $record; $results+=$result; if (-not $result.Ok) { break } } }
    return ,$results
}

function Get-SMRegistryValueSnapshot {
    param([string]$Path,[string]$Name)
    if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) { return [pscustomobject]@{Exists=$false;Value=$null} }
    $item=Get-ItemProperty -LiteralPath $Path -ErrorAction Stop
    $property=$item.PSObject.Properties[$Name]
    return [pscustomobject]@{Exists=($null -ne $property);Value=$(if ($null -ne $property) { $property.Value } else { $null })}
}

function Get-SMEntryStateSnapshot {
    param([Parameter(Mandatory)]$Entry)
    switch ($Entry.Kind) {
        { $_ -in 'RunKey','Folder' } {
            $path=Get-SMApprovedKeyPath $Entry.Data.Hive $Entry.Data.Leaf
            $value=Get-SMRegistryValueSnapshot $path $Entry.Data.Name
            $configuration=''
            if ($Entry.Kind -eq 'RunKey') {
                $launch=Get-SMRegistryValueSnapshot $Entry.Source $Entry.Data.Name
                if (-not $launch.Exists) { throw 'Startup registration no longer exists.' }
                $configuration=[string]$launch.Value
            } else { $configuration=(Get-FileHash -LiteralPath $Entry.Data.File -Algorithm SHA256 -ErrorAction Stop).Hash }
            return [pscustomobject]@{Enabled=(ConvertFrom-SMApprovedBytes ([byte[]]$value.Value));Configuration=$configuration;Approval=$value}
        }
        'Task' {
            $task=Get-SMExactScheduledTask -Entry $Entry
            $xml=[xml](Export-ScheduledTask -InputObject $task -ErrorAction Stop)
            $enabled=[bool]$task.Settings.Enabled
            $node=$xml.SelectSingleNode("//*[local-name()='Settings']/*[local-name()='Enabled']")
            if ($null -ne $node) { [void]$node.ParentNode.RemoveChild($node) }
            return [pscustomobject]@{Enabled=$enabled;Configuration=$xml.OuterXml}
        }
        'Service' {
            $path='HKLM:\SYSTEM\CurrentControlSet\Services\'+$Entry.Data.Name
            $properties=Get-ItemProperty -LiteralPath $path -ErrorAction Stop
            $delayed=Get-SMRegistryValueSnapshot $path 'DelayedAutoStart'
            return [pscustomobject]@{Enabled=([int]$properties.Start -eq 2);Start=[int]$properties.Start;Delayed=$delayed;Configuration=[string]$properties.ImagePath}
        }
        'Uwp' {
            $value=Get-SMRegistryValueSnapshot $Entry.Data.Path 'State'
            if (-not $value.Exists -or [int]$value.Value -notin 0,1,2) { throw 'Store startup state is absent, unknown, or managed by policy.' }
            return [pscustomobject]@{Enabled=([int]$value.Value -eq 2);State=[int]$value.Value}
        }
        default { throw 'This entry cannot be toggled.' }
    }
}

function Restore-SMRegistryValue {
    param([string]$Path,[string]$Name,$Value,[string]$Type)
    if ($Value.Exists) {
        $data=$Value.Value
        if ($Type -eq 'Binary') { $data=[byte[]]$data }
        New-ItemProperty -LiteralPath $Path -Name $Name -Value $data -PropertyType $Type -Force -ErrorAction Stop | Out-Null
    } else {
        $current=Get-SMRegistryValueSnapshot $Path $Name
        if ($current.Exists) { Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop }
    }
}

function Restore-SMEntryStateSnapshot {
    param($Entry,$Snapshot)
    switch ($Entry.Kind) {
        { $_ -in 'RunKey','Folder' } { Restore-SMRegistryValue (Get-SMApprovedKeyPath $Entry.Data.Hive $Entry.Data.Leaf) $Entry.Data.Name $Snapshot.Approval Binary }
        'Service' {
            $mode=switch ([int]$Snapshot.Start) { 2 {'Automatic'} 3 {'Manual'} 4 {'Disabled'} default {throw 'Unsupported service startup type.'} }
            Set-Service -Name $Entry.Data.Name -StartupType $mode -ErrorAction Stop
            Restore-SMRegistryValue ('HKLM:\SYSTEM\CurrentControlSet\Services\'+$Entry.Data.Name) 'DelayedAutoStart' $Snapshot.Delayed DWord
        }
        'Uwp' { Set-ItemProperty -LiteralPath $Entry.Data.Path -Name State -Value ([int]$Snapshot.State) -Type DWord -ErrorAction Stop }
        default { Set-SMEntryState $Entry ([bool]$Snapshot.Enabled) }
    }
}
