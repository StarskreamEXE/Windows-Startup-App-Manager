Set-StrictMode -Version 2.0
$root = Split-Path $PSScriptRoot -Parent
foreach ($file in @('Core/Contracts','Core/Paths','Core/Logging','Engine/Inventory','Engine/Changes','Engine/Backup')) { . "$root/src/$file.ps1" }
Initialize-SMPaths -Root (Join-Path $env:TEMP ('sm-recovery-' + [guid]::NewGuid())) | Out-Null

Describe 'Verified recovery operations' {
    BeforeEach {
        Clear-SMPendingChanges
        $script:current = $true
        $script:entry = New-SMEntry -Name Same -Category Task -Kind Task -Enabled $true -Data @{ Name='Same'; Path='\One\' }
        $script:entry.Id = 1
        Mock Get-SMEntryStateSnapshot { [pscustomobject]@{ Enabled=$script:current; Configuration='fixed' } }
        Mock Set-SMEntryState { param($Entry,$Enable) $script:current=$Enable }
        Mock Write-SMChangeRecord {}
        Mock Get-SMChangeRecords { @() }
        Mock Backup-SMChangeBatch { 'snapshot.json' }
    }
    It 'distinguishes tasks with identical names in different folders' {
        $other = New-SMEntry -Name Same -Category Task -Kind Task -Enabled $true -Data @{Name='Same';Path='\Two\'}
        (Get-SMEntryIdentity $entry) | Should Not Be (Get-SMEntryIdentity $other)
    }
    It 'keeps failed changes pending when readback disagrees' {
        Add-SMPendingChange $entry $false
        Mock Set-SMEntryState {}
        $result = Invoke-SMApplyChanges
        $result[0].Ok | Should Be $false
        (Get-SMPendingChanges).Count | Should Be 1
    }
    It 'blocks all mutation when recovery snapshot fails' {
        Add-SMPendingChange $entry $false
        Mock Backup-SMChangeBatch { throw 'disk full' }
        { Invoke-SMApplyChanges } | Should Throw
        Assert-MockCalled Set-SMEntryState -Times 0 -Scope It
    }
    It 'blocks stale staged state' {
        Add-SMPendingChange $entry $false
        $script:current=$false
        { Invoke-SMApplyChanges } | Should Throw
        Assert-MockCalled Set-SMEntryState -Times 0 -Scope It
    }
    It 'blocks mutation if the write-ahead journal fails' {
        Add-SMPendingChange $entry $false
        Mock Write-SMChangeRecord { throw 'journal locked' }
        { Invoke-SMApplyChanges } | Should Throw
        Assert-MockCalled Set-SMEntryState -Times 0 -Scope It
    }
    It 'applies every item in a multi-entry batch independently' {
        $other = New-SMEntry -Name Other -Category Task -Kind Task -Enabled $true -Data @{Name='Other';Path='\Two\'}
        $other.Id=2
        $script:states=@{1=$true;2=$true}
        Mock Get-SMEntryStateSnapshot { param($Entry) [pscustomobject]@{Enabled=$script:states[$Entry.Id];Configuration='fixed'} }
        Mock Set-SMEntryState { param($Entry,$Enable) $script:states[$Entry.Id]=$Enable }
        Add-SMPendingChange $entry $false
        Add-SMPendingChange $other $false
        $results=Invoke-SMApplyChanges
        $results.Count | Should Be 2
        @($results | Where-Object {-not $_.Ok}).Count | Should Be 0
        (Get-SMPendingChanges).Count | Should Be 0
    }
    It 'undoes only the exact referenced operation' {
        $first=New-SMChangeRecord -Action apply -Entry $entry -From $true -To $false -Ok $true -OperationId first -BatchId batch
        $second=New-SMChangeRecord -Action apply -Entry $entry -From $false -To $true -Ok $true -OperationId second -BatchId batch
        $undo=New-SMChangeRecord -Action undo -Entry $entry -From $true -To $false -Ok $true -OperationId third -BatchId batch -UndoOf second
        Mock Get-SMChangeRecords { @($first,$second,$undo) }
        $candidates=@(Get-SMUndoCandidates)
        $candidates.Count | Should Be 1
        $candidates[0].operationId | Should Be first
    }
    It 'undoes a batch in reverse order' {
        $first=New-SMChangeRecord -Action apply -Entry $entry -From $true -To $false -Ok $true -OperationId first -BatchId batch
        $second=New-SMChangeRecord -Action apply -Entry $entry -From $false -To $true -Ok $true -OperationId second -BatchId batch
        Mock Get-SMChangeRecords { @($first,$second) }
        $script:order=@()
        Mock Undo-SMOperation { param($Record) $script:order+=$Record.operationId; @{Ok=$true} }
        $results=Undo-SMLastBatch
        ($script:order -join ',') | Should Be 'second,first'
        $results.Count | Should Be 2
    }
    It 'refuses an unfinished write-ahead operation' {
        $record=New-SMChangeRecord -Action prepare -Entry $entry -From $true -To $false -Ok $false -OperationId unfinished -BatchId batch
        Mock Get-SMChangeRecords { @($record) }
        { Assert-SMRecoveryJournalComplete } | Should Throw
    }
    It 'ignores a completed write-ahead operation' {
        $prepare=New-SMChangeRecord -Action prepare -Entry $entry -From $true -To $false -Ok $false -OperationId finished -BatchId batch
        $complete=New-SMChangeRecord -Action apply -Entry $entry -From $true -To $false -Ok $true -OperationId finished -BatchId batch
        Mock Get-SMChangeRecords { @($prepare,$complete) }
        @(Get-SMInterruptedOperations).Count | Should Be 0
    }
    It 'requires recovery when the setter mutates and then throws' {
        Add-SMPendingChange $entry $false
        Mock Set-SMEntryState { $script:current=$false; throw 'partial mutation' }
        { Invoke-SMApplyChanges } | Should Throw
        Assert-MockCalled Write-SMChangeRecord -Scope It -Times 1 -ParameterFilter { $Record.action -eq 'apply' -and $Record.needsRecovery }
    }
    It 'does not close a failed mutation that needs recovery' {
        $prepare=New-SMChangeRecord -Action prepare -Entry $entry -From $true -To $false -Ok $false -OperationId partial -BatchId batch
        $complete=New-SMChangeRecord -Action apply -Entry $entry -From $true -To $false -Ok $false -OperationId partial -BatchId batch -NeedsRecovery $true
        Mock Get-SMChangeRecords { @($prepare,$complete) }
        @(Get-SMInterruptedOperations).Count | Should Be 1
    }
    It 'requires recovery when readback becomes unavailable after mutation' {
        Add-SMPendingChange $entry $false
        $script:unreadable=$false
        Mock Set-SMEntryState { $script:unreadable=$true }
        Mock Get-SMEntryStateSnapshot { if ($script:unreadable) { throw 'read unavailable' }; [pscustomobject]@{Enabled=$true;Configuration='fixed'} }
        { Invoke-SMApplyChanges } | Should Throw
        Assert-MockCalled Write-SMChangeRecord -Scope It -Times 1 -ParameterFilter { $Record.action -eq 'apply' -and $Record.needsRecovery }
    }
    It 'restores an interrupted operation and verifies its before state' {
        $before=[pscustomobject]@{Enabled=$true;Configuration='fixed'}
        $record=New-SMChangeRecord -Action prepare -Entry $entry -From $true -To $false -Ok $false -OperationId interrupted -BatchId batch -Before $before
        Mock Get-SMChangeRecords { @($record) }
        $script:current=$false
        Mock Restore-SMEntryStateSnapshot { $script:current=$true }
        $result=Restore-SMInterruptedOperation -OperationId interrupted
        $result.Ok | Should Be $true
        Assert-MockCalled Write-SMChangeRecord -Times 1 -Scope It -ParameterFilter { $Record.action -eq 'apply' -and -not $Record.ok -and -not $Record.needsRecovery }
    }
}

Describe 'Recovery persistence' {
    It 'rejects a failed native export even if the file already exists' {
        $file=Join-Path $script:SM.BackupDir 'existing.reg'
        [IO.File]::WriteAllText($file,"Windows Registry Editor Version 5.00`r`n[HKEY_CURRENT_USER\Test]",[Text.Encoding]::Unicode)
        Mock reg.exe { $global:LASTEXITCODE=1 }
        { Invoke-SMRegExport -Key 'HKCU\Test' -Out $file } | Should Throw
    }
    It 'rejects a successful native export with no registry sections' {
        $file=Join-Path $script:SM.BackupDir 'empty.reg'
        [IO.File]::WriteAllText($file,'Windows Registry Editor Version 5.00',[Text.Encoding]::Unicode)
        Mock reg.exe { $global:LASTEXITCODE=0 }
        { Invoke-SMRegExport -Key 'HKCU\Test' -Out $file } | Should Throw
    }
    It 'persists every entry and before state in the batch snapshot' {
        $entry=New-SMEntry -Name Same -Category Task -Kind Task -Enabled $true -Data @{Name='Same';Path='\One\'}
        $change=New-SMPendingChange $entry $false
        $change | Add-Member NoteProperty BeforeState ([pscustomobject]@{Enabled=$true;Configuration='task xml'})
        $batch=[guid]::NewGuid().ToString()
        $path=Backup-SMChangeBatch @($change) $batch
        $document=Get-Content $path -Raw | ConvertFrom-Json
        $document.BatchId | Should Be $batch
        $document.Changes[0].Before.Configuration | Should Be 'task xml'
    }
    It 'throws on a journal write failure' {
        $original=$script:SM.ChangeFile
        try {
            $script:SM.ChangeFile=$script:SM.BackupDir
            { Write-SMChangeRecord ([pscustomobject]@{test='test'}) } | Should Throw
        } finally { $script:SM.ChangeFile=$original }
    }
}
