# Providers: StartupApproved / RunKeys / StartupFolders.
#
# These tests never write to the real StartupApproved keys and never need admin.
# Every write path is exercised through mocks; the only real reads are the Run keys
# (read-only) and a throwaway .lnk this file creates under $env:TEMP.

Set-StrictMode -Version 2.0

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here

. (Join-Path $root 'src\Core\Contracts.ps1')
. (Join-Path $root 'src\Core\Paths.ps1')
. (Join-Path $root 'src\Providers\StartupApproved.ps1')
. (Join-Path $root 'src\Providers\RunKeys.ps1')
. (Join-Path $root 'src\Providers\StartupFolders.ps1')

$script:SMTestRoot = Join-Path $env:TEMP ('SMProviderTests_' + [guid]::NewGuid().ToString('N'))
Initialize-SMPaths -Root $script:SMTestRoot | Out-Null

# The property names every provider entry must carry, taken from New-SMEntry itself.
$script:SMEntryContract = @((New-SMEntry -Name 'x' -Category 'x' -Kind 'RunKey' -Enabled $true).PSObject.Properties.Name)

Describe 'ConvertFrom-SMApprovedBytes' {

    It 'treats a missing record ($null) as enabled' {
        ConvertFrom-SMApprovedBytes -Bytes $null | Should Be $true
    }

    It 'treats an empty record as enabled' {
        ConvertFrom-SMApprovedBytes -Bytes ([byte[]]@()) | Should Be $true
    }

    It 'decodes 02 as enabled' {
        ConvertFrom-SMApprovedBytes -Bytes ([byte[]]@(2,0,0,0,0,0,0,0,0,0,0,0)) | Should Be $true
    }

    It 'decodes 03 as disabled' {
        ConvertFrom-SMApprovedBytes -Bytes ([byte[]]@(3,0,0,0,1,2,3,4,5,6,7,8)) | Should Be $false
    }

    It 'decodes the 06 variant as enabled' {
        ConvertFrom-SMApprovedBytes -Bytes ([byte[]]@(6,0,0,0,0,0,0,0,0,0,0,0)) | Should Be $true
    }

    It 'decodes the 07 variant as disabled' {
        ConvertFrom-SMApprovedBytes -Bytes ([byte[]]@(7,0,0,0,1,2,3,4,5,6,7,8)) | Should Be $false
    }
}

Describe 'New-SMApprovedBytes' {

    It 'writes 02 00 00 00 plus eight zero bytes when enabling' {
        $b = New-SMApprovedBytes -Enable $true
        $b.Length | Should Be 12
        $b[0] | Should Be 2
        (@($b[1..11] | Where-Object { $_ -ne 0 })).Count | Should Be 0
    }

    It 'writes 03 plus a non-zero FILETIME when disabling' {
        $b = New-SMApprovedBytes -Enable $false
        $b.Length | Should Be 12
        $b[0] | Should Be 3
        $b[1] | Should Be 0
        $b[2] | Should Be 0
        $b[3] | Should Be 0
        (@($b[4..11] | Where-Object { $_ -ne 0 })).Count | Should Not Be 0
    }

    It 'stores the current time as a little-endian FILETIME' {
        $b    = New-SMApprovedBytes -Enable $false
        $when = [datetime]::FromFileTime([BitConverter]::ToInt64($b, 4))
        ([math]::Abs(((Get-Date) - $when).TotalMinutes) -lt 5) | Should Be $true
    }

    It 'round-trips enabled through ConvertFrom-SMApprovedBytes' {
        ConvertFrom-SMApprovedBytes -Bytes (New-SMApprovedBytes -Enable $true) | Should Be $true
    }

    It 'round-trips disabled through ConvertFrom-SMApprovedBytes' {
        ConvertFrom-SMApprovedBytes -Bytes (New-SMApprovedBytes -Enable $false) | Should Be $false
    }
}

Describe 'Test-SMApproved' {

    It 'reports enabled when the StartupApproved key does not exist' {
        Mock Test-Path { $false }
        Mock Get-ItemProperty { throw 'must not be called' }
        Test-SMApproved -Hive 'HKCU' -Leaf 'Run' -Name 'Anything' | Should Be $true
    }

    It 'reports enabled when the key exists but the value does not' {
        Mock Test-Path { $true }
        Mock Get-ItemProperty { [pscustomobject]@{ Unrelated = 'value' } }
        Test-SMApproved -Hive 'HKCU' -Leaf 'Run' -Name 'Anything' | Should Be $true
    }

    It 'reports enabled when the recorded value is null' {
        Mock Test-Path { $true }
        Mock Get-ItemProperty { $h = @{}; $h['Anything'] = $null; [pscustomobject]$h }
        Test-SMApproved -Hive 'HKCU' -Leaf 'Run' -Name 'Anything' | Should Be $true
    }

    It 'propagates access failures rather than claiming the entry is enabled' {
        Mock Test-Path { $true }
        Mock Get-ItemProperty { throw [UnauthorizedAccessException]::new('Access denied') }
        { Test-SMApproved -Hive 'HKCU' -Leaf 'Run' -Name 'Anything' } | Should Throw
    }

    It 'reports enabled for a recorded 02 value' {
        Mock Test-Path { $true }
        Mock Get-ItemProperty { $h = @{}; $h['Widget'] = [byte[]]@(2,0,0,0,0,0,0,0,0,0,0,0); [pscustomobject]$h }
        Test-SMApproved -Hive 'HKLM' -Leaf 'Run32' -Name 'Widget' | Should Be $true
    }

    It 'reports disabled for a recorded 03 value' {
        Mock Test-Path { $true }
        Mock Get-ItemProperty { $h = @{}; $h['Widget'] = [byte[]]@(3,0,0,0,9,8,7,6,5,4,3,2); [pscustomobject]$h }
        Test-SMApproved -Hive 'HKCU' -Leaf 'StartupFolder' -Name 'Widget' | Should Be $false
    }
}

Describe 'Set-SMApproved' {

    It 'writes a Binary value whose first byte is 02 when enabling' {
        Mock Test-Path { $true }
        Mock New-Item { }
        Mock New-ItemProperty { }

        Set-SMApproved -Hive 'HKCU' -Leaf 'Run' -Name 'Widget' -Enable $true

        Assert-MockCalled New-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'Widget' -and $PropertyType -eq 'Binary' -and $Value[0] -eq 2
        }
    }

    It 'writes a Binary value whose first byte is 03 when disabling' {
        Mock Test-Path { $true }
        Mock New-Item { }
        Mock New-ItemProperty { }

        Set-SMApproved -Hive 'HKLM' -Leaf 'Run32' -Name 'Widget' -Enable $false

        Assert-MockCalled New-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'Widget' -and $PropertyType -eq 'Binary' -and $Value[0] -eq 3
        }
    }

    It 'targets the StartupApproved leaf key for the requested hive' {
        Mock Test-Path { $true }
        Mock New-Item { }
        Mock New-ItemProperty { }

        Set-SMApproved -Hive 'HKCU' -Leaf 'StartupFolder' -Name 'Widget.lnk' -Enable $false

        Assert-MockCalled New-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path -eq 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
        }
    }

    It 'creates the leaf key when Windows has never written one' {
        Mock Test-Path { $false }
        Mock New-Item { }
        Mock New-ItemProperty { }

        Set-SMApproved -Hive 'HKCU' -Leaf 'Run' -Name 'Widget' -Enable $true

        Assert-MockCalled New-Item -Times 1 -Exactly -Scope It
        Assert-MockCalled New-ItemProperty -Times 1 -Exactly -Scope It
    }

    It 'does not create the leaf key when it already exists' {
        Mock Test-Path { $true }
        Mock New-Item { }
        Mock New-ItemProperty { }

        Set-SMApproved -Hive 'HKCU' -Leaf 'Run' -Name 'Widget' -Enable $true

        Assert-MockCalled New-Item -Times 0 -Exactly -Scope It
    }
}

Describe 'Resolve-SMRunKeyExePath' {

    It 'returns an empty string for an empty command' {
        Resolve-SMRunKeyExePath -Command '' | Should BeExactly ''
    }

    It 'takes the quoted first token' {
        Resolve-SMRunKeyExePath -Command '"C:\Program Files\App\app.exe" --silent' |
            Should BeExactly 'C:\Program Files\App\app.exe'
    }

    It 'takes an unquoted path ending in a runnable extension' {
        Resolve-SMRunKeyExePath -Command 'C:\Tools\helper.exe -run now' |
            Should BeExactly 'C:\Tools\helper.exe'
    }

    It 'falls back to the first whitespace token' {
        Resolve-SMRunKeyExePath -Command 'rundll32 shell32.dll,Control_RunDLL' |
            Should BeExactly 'rundll32'
    }

    It 'expands environment variables' {
        Resolve-SMRunKeyExePath -Command '%SystemRoot%\system32\notepad.exe' |
            Should BeExactly (Join-Path $env:SystemRoot 'system32\notepad.exe')
    }
}

Describe 'Get-SMRunKeyEntries' {

    # Read-only against the live registry - this never writes anything.
    $script:RunEntries = @(Get-SMRunKeyEntries)

    It 'returns objects carrying the New-SMEntry contract properties' {
        foreach ($e in $script:RunEntries) {
            $names = @($e.PSObject.Properties.Name)
            foreach ($p in $script:SMEntryContract) {
                ($names -contains $p) | Should Be $true
            }
        }
        # a machine with no Run values is legal; the loop above is the assertion
        ($script:RunEntries -is [array]) | Should Be $true
    }

    It 'only produces Kinds the contract allows for this provider' {
        foreach ($e in $script:RunEntries) {
            (@('RunKey','RunOnce') -contains $e.Kind) | Should Be $true
        }
        (@($script:SMKinds) -contains 'RunKey') | Should Be $true
    }

    It 'never emits an entry with an empty value name' {
        foreach ($e in $script:RunEntries) {
            [string]::IsNullOrWhiteSpace($e.Name) | Should Be $false
        }
        ($script:RunEntries -is [array]) | Should Be $true
    }

    It 'carries Hive/Leaf/Name toggle data on every entry' {
        foreach ($e in $script:RunEntries) {
            $e.Data.ContainsKey('Hive') | Should Be $true
            $e.Data.ContainsKey('Leaf') | Should Be $true
            $e.Data.ContainsKey('Name') | Should Be $true
            $e.Data.Name | Should BeExactly $e.Name
        }
        ($script:RunEntries -is [array]) | Should Be $true
    }

    It 'names the registry key and value in Detail, and the key in Source' {
        foreach ($e in $script:RunEntries) {
            ($e.Detail.Contains($e.Source)) | Should Be $true
            ($e.Detail.Contains($e.Name))   | Should Be $true
        }
        ($script:RunEntries -is [array]) | Should Be $true
    }

    It 'marks RunOnce entries as one-shot and not toggleable' {
        foreach ($e in @($script:RunEntries | Where-Object { $_.Kind -eq 'RunOnce' })) {
            $e.CanToggle | Should Be $false
            $e.Category  | Should BeExactly 'RunOnce (one-shot)'
        }
        ($script:RunEntries -is [array]) | Should Be $true
    }

    It 'marks Run key entries as toggleable and hive/leaf tagged' {
        foreach ($e in @($script:RunEntries | Where-Object { $_.Kind -eq 'RunKey' })) {
            $e.CanToggle | Should Be $true
            (@('Run','Run32') -contains $e.Data.Leaf) | Should Be $true
            (@('HKCU','HKLM') -contains $e.Data.Hive) | Should Be $true
        }
        ($script:RunEntries -is [array]) | Should Be $true
    }

    It 'builds one entry per named value and skips the default value' {
        Mock Get-SMRunKeyDefinitions {
            @(@{ Path = 'HKCU:\Software\StartupManagerTests\Run'; Hive = 'HKCU'; Leaf = 'Run'; Category = 'Registry Run (User)' })
        }
        Mock Get-SMRunOnceDefinitions { @() }
        Mock Test-Path { $true }
        Mock Get-Item {
            $key = New-Object psobject
            $key | Add-Member -MemberType ScriptMethod -Name GetValueNames -Value { ,@('', 'Fake Widget') } -PassThru |
                   Add-Member -MemberType ScriptMethod -Name GetValue -Value { param($n) '"C:\Tools\widget.exe" --tray' } -PassThru
        }
        Mock Test-SMApproved { $false }

        $entries = @(Get-SMRunKeyEntries)
        $entries.Count            | Should Be 1
        $entries[0].Name          | Should BeExactly 'Fake Widget'
        $entries[0].Kind          | Should BeExactly 'RunKey'
        $entries[0].Enabled       | Should Be $false
        $entries[0].CanToggle     | Should Be $true
        $entries[0].Command       | Should BeExactly '"C:\Tools\widget.exe" --tray'
        $entries[0].ExePath       | Should BeExactly 'C:\Tools\widget.exe'
        $entries[0].Source        | Should BeExactly 'HKCU:\Software\StartupManagerTests\Run'
        $entries[0].Data.Leaf     | Should BeExactly 'Run'
        $entries[0].Data.Hive     | Should BeExactly 'HKCU'
    }
}

Describe 'Set-SMRunKeyState' {

    It 'forwards the entry data to Set-SMApproved' {
        Mock Set-SMApproved { }
        $entry = New-SMEntry -Name 'Widget' -Category 'Registry Run (User)' -Kind 'RunKey' -Enabled $true `
                             -Data @{ Hive = 'HKCU'; Leaf = 'Run'; Name = 'Widget' }

        Set-SMRunKeyState -Entry $entry -Enable $false

        Assert-MockCalled Set-SMApproved -Times 1 -Exactly -ParameterFilter {
            $Hive -eq 'HKCU' -and $Leaf -eq 'Run' -and $Name -eq 'Widget' -and $Enable -eq $false
        }
    }

    It 'throws when the entry has no toggle data' {
        $entry = New-SMEntry -Name 'Widget' -Category 'RunOnce (one-shot)' -Kind 'RunOnce' -Enabled $true
        { Set-SMRunKeyState -Entry $entry -Enable $false } | Should Throw
    }
}

Describe 'Resolve-SMShortcut' {

    $script:LnkDir    = Join-Path $script:SMTestRoot 'FakeStartup'
    New-Item -ItemType Directory -Path $script:LnkDir -Force | Out-Null
    $script:LnkPath   = Join-Path $script:LnkDir 'Fake Widget.lnk'
    $script:LnkTarget = Join-Path $env:SystemRoot 'system32\notepad.exe'

    $sh  = New-Object -ComObject WScript.Shell
    $lnk = $sh.CreateShortcut($script:LnkPath)
    $lnk.TargetPath       = $script:LnkTarget
    $lnk.Arguments        = '--fake-arg'
    $lnk.WorkingDirectory = $script:LnkDir
    $lnk.Save()

    It 'reads target, arguments and working directory from a .lnk' {
        $r = Resolve-SMShortcut -Path $script:LnkPath
        $r.Target           | Should Be $script:LnkTarget
        $r.Arguments        | Should BeExactly '--fake-arg'
        $r.WorkingDirectory | Should BeExactly $script:LnkDir
    }

    It 'falls back to the .lnk path when the shortcut cannot be read' {
        $broken = Join-Path $script:LnkDir 'Broken.lnk'
        Set-Content -LiteralPath $broken -Value 'not a shortcut' -Encoding Ascii
        $r = Resolve-SMShortcut -Path $broken
        $r.Target | Should BeExactly $broken
    }
}

Describe 'Get-SMStartupFolderEntries' {

    It 'builds an entry from a .lnk in the scanned folder' {
        Mock Get-SMStartupFolderDefinitions {
            @(@{ Dir = $script:LnkDir; Hive = 'HKCU'; Category = 'Startup Folder (User)' })
        }
        Mock Test-SMApproved { $true }

        $found = @(Get-SMStartupFolderEntries | Where-Object { $_.Name -eq 'Fake Widget.lnk' })
        $found.Count | Should Be 1

        $e = $found[0]
        $e.Kind      | Should BeExactly 'Folder'
        $e.Category  | Should BeExactly 'Startup Folder (User)'
        $e.Enabled   | Should Be $true
        $e.CanToggle | Should Be $true
        $e.ExePath   | Should Be $script:LnkTarget
        $e.Command   | Should Be ($script:LnkTarget + ' --fake-arg')
        $e.Source    | Should BeExactly $script:LnkDir
        $e.Data.Hive | Should BeExactly 'HKCU'
        $e.Data.Leaf | Should BeExactly 'StartupFolder'
        $e.Data.Name | Should BeExactly 'Fake Widget.lnk'
        $expectedFile = Get-ChildItem -LiteralPath (Split-Path -Parent $script:LnkPath) -File | Where-Object { $_.Name -eq (Split-Path -Leaf $script:LnkPath) }
        $e.Data.File | Should BeExactly $expectedFile.FullName
        $e.Detail.Contains('Working dir')      | Should Be $true
        $e.Detail.IndexOf($script:LnkTarget, [StringComparison]::OrdinalIgnoreCase) | Should BeGreaterThan -1
        $e.Detail.Contains('--fake-arg')       | Should Be $true
    }

    It 'reports the disabled state from StartupApproved' {
        Mock Get-SMStartupFolderDefinitions {
            @(@{ Dir = $script:LnkDir; Hive = 'HKCU'; Category = 'Startup Folder (User)' })
        }
        Mock Test-SMApproved { $false }

        $found = @(Get-SMStartupFolderEntries | Where-Object { $_.Name -eq 'Fake Widget.lnk' })
        $found[0].Enabled | Should Be $false
    }

    It 'skips desktop.ini' {
        Set-Content -LiteralPath (Join-Path $script:LnkDir 'desktop.ini') -Value '[.ShellClassInfo]' -Encoding Ascii
        Mock Get-SMStartupFolderDefinitions {
            @(@{ Dir = $script:LnkDir; Hive = 'HKCU'; Category = 'Startup Folder (User)' })
        }
        Mock Test-SMApproved { $true }

        $names = @(Get-SMStartupFolderEntries | ForEach-Object { $_.Name })
        ($names -contains 'desktop.ini') | Should Be $false
    }

    It 'skips folders that do not exist' {
        Mock Get-SMStartupFolderDefinitions {
            @(@{ Dir = (Join-Path $script:SMTestRoot 'NoSuchFolder'); Hive = 'HKCU'; Category = 'Startup Folder (User)' })
        }
        Mock Test-SMApproved { $true }

        @(Get-SMStartupFolderEntries).Count | Should Be 0
    }
}

Describe 'Set-SMStartupFolderState' {

    It 'forwards the entry data to Set-SMApproved' {
        Mock Set-SMApproved { }
        $entry = New-SMEntry -Name 'Widget.lnk' -Category 'Startup Folder (All Users)' -Kind 'Folder' -Enabled $true `
                             -Data @{ Hive = 'HKLM'; Leaf = 'StartupFolder'; Name = 'Widget.lnk'; File = 'C:\x\Widget.lnk' }

        Set-SMStartupFolderState -Entry $entry -Enable $true

        Assert-MockCalled Set-SMApproved -Times 1 -Exactly -ParameterFilter {
            $Hive -eq 'HKLM' -and $Leaf -eq 'StartupFolder' -and $Name -eq 'Widget.lnk' -and $Enable -eq $true
        }
    }

    It 'throws when the entry has no toggle data' {
        $entry = New-SMEntry -Name 'Widget.lnk' -Category 'Startup Folder (User)' -Kind 'Folder' -Enabled $true
        { Set-SMStartupFolderState -Entry $entry -Enable $true } | Should Throw
    }
}

# scratch this file created under $env:TEMP - nothing of the user's is touched
if (Test-Path -LiteralPath $script:SMTestRoot) {
    Remove-Item -LiteralPath $script:SMTestRoot -Recurse -Force -ErrorAction SilentlyContinue
}
