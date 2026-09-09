$script:PackageRoot = Split-Path -Parent $PSScriptRoot

Describe 'Release packaging' {
    It 'has a versioned explicit allowlist without private runtime material' {
        $manifest = Import-PowerShellDataFile (Join-Path $script:PackageRoot 'build\Release-Files.psd1')
        $manifest.Version | Should Be '2.1.1'
        ($manifest.Files -contains 'LICENSE') | Should Be $true
        ($manifest.Files -contains 'THIRD-PARTY-NOTICES.md') | Should Be $true
        ($manifest.Files -contains 'fonts/OFL-Inter.txt') | Should Be $true
        @($manifest.Files | Where-Object { $_ -match '(?i)(CLAUDE|main-window|\.git/|logs/|backups/|reports/|exports/|\*|\.\.)' }).Count | Should Be 0
        foreach ($relative in $manifest.Files) {
            Test-Path -LiteralPath (Join-Path $script:PackageRoot $relative) -PathType Leaf | Should Be $true
        }
        foreach ($source in (Get-ChildItem -LiteralPath (Join-Path $script:PackageRoot 'src') -Recurse -File)) {
            $relative = $source.FullName.Substring($script:PackageRoot.Length + 1).Replace('\','/')
            ($manifest.Files -contains $relative) | Should Be $true
        }
    }

    It 'installs and upgrades in isolation without touching fonts or registration' {
        $destination = Join-Path $TestDrive 'installed'
        Mock New-ItemProperty { throw 'Unexpected font registration' }
        Mock Set-ItemProperty { throw 'Unexpected uninstall registration' }
        Mock Start-Process { throw 'Unexpected launch' }
        Mock New-Item { throw 'Unexpected registry key creation' } -ParameterFilter { $Path -like 'HK*:*' }
        & (Join-Path $script:PackageRoot 'Install.ps1') -Dest $destination -Portable -NoShortcuts
        Test-Path (Join-Path $destination 'LICENSE') | Should Be $true
        Test-Path (Join-Path $destination 'THIRD-PARTY-NOTICES.md') | Should Be $true
        Test-Path (Join-Path $destination 'CLAUDE.md') | Should Be $false
        Test-Path (Join-Path $destination 'docs\images\main-window.png') | Should Be $false
        $launcher = Join-Path $destination 'StartupManager.exe'
        (Get-Item $launcher).VersionInfo.FileVersion | Should Be '2.1.1.0'
        Set-Content -LiteralPath $launcher -Value 'stale launcher'
        Set-Content -LiteralPath (Join-Path $destination 'logs\keep.txt') -Value 'preserve user data'
        & (Join-Path $script:PackageRoot 'Install.ps1') -Dest $destination -Portable -NoShortcuts
        (Get-Item $launcher).VersionInfo.FileVersion | Should Be '2.1.1.0'
        Get-Content -LiteralPath (Join-Path $destination 'logs\keep.txt') | Should Be 'preserve user data'
        Assert-MockCalled New-ItemProperty -Times 0 -Exactly -Scope It
        Assert-MockCalled Set-ItemProperty -Times 0 -Exactly -Scope It
        Assert-MockCalled Start-Process -Times 0 -Exactly -Scope It
        Assert-MockCalled New-Item -Times 0 -Exactly -Scope It -ParameterFilter { $Path -like 'HK*:*' }
    }

    It 'installs from bracketed source paths into bracketed destinations' {
        $source = Join-Path $TestDrive '[download]'
        $destination = Join-Path $TestDrive '[installed]'
        $manifest = Import-PowerShellDataFile (Join-Path $script:PackageRoot 'build\Release-Files.psd1')
        foreach ($relative in $manifest.Files) {
            $target = Join-Path $source $relative
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $script:PackageRoot $relative) -Destination $target
        }
        & (Join-Path $source 'Install.ps1') -Dest $destination -Portable -NoShortcuts
        foreach ($relative in $manifest.Files) {
            (Get-FileHash -LiteralPath (Join-Path $destination $relative)).Hash | Should Be (Get-FileHash -LiteralPath (Join-Path $source $relative)).Hash
        }
        (Get-Item -LiteralPath (Join-Path $destination 'StartupManager.exe')).VersionInfo.FileVersion | Should Be '2.1.1.0'
    }

    It 'preserves a portable install during uninstall without touching registration' {
        $destination = Join-Path $TestDrive 'portable-remove'
        & (Join-Path $script:PackageRoot 'Install.ps1') -Dest $destination -Portable -NoShortcuts
        Mock Remove-Item { throw 'Uninstall must preserve files and avoid registry changes in portable mode' }
        Mock Start-Process { throw 'Uninstall must not launch a detached shell' }
        & (Join-Path $destination 'Uninstall.ps1') -Quiet -Portable
        Test-Path -LiteralPath $destination | Should Be $false
        $preserved = @(Get-ChildItem -LiteralPath $TestDrive -Directory -Filter 'portable-remove.uninstalled-*')
        $preserved.Count | Should Be 1
        Test-Path -LiteralPath (Join-Path $preserved[0].FullName 'LICENSE') | Should Be $true
        Assert-MockCalled Remove-Item -Times 0 -Exactly -Scope It
        Assert-MockCalled Start-Process -Times 0 -Exactly -Scope It
    }

    It 'builds a ZIP with notices and a matching SHA256 checksum' {
        $output = Join-Path $TestDrive 'release'
        & (Join-Path $script:PackageRoot 'build\Build-Release.ps1') -OutputDirectory $output
        $archive = Join-Path $output 'Windows-Startup-App-Manager-2.1.1.zip'
        Test-Path $archive | Should Be $true
        $checksum = Get-Content (Join-Path $output 'SHA256SUMS.txt')
        ($checksum -contains ((Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant() + '  Windows-Startup-App-Manager-2.1.1.zip')) | Should Be $true
        $setup = Join-Path $output 'Windows-Startup-App-Manager-Setup-2.1.1.exe'
        Test-Path -LiteralPath $setup | Should Be $true
        (Get-Item -LiteralPath $setup).VersionInfo.FileVersion | Should Be '2.1.1.0'
        ($checksum -contains ((Get-FileHash $setup -Algorithm SHA256).Hash.ToLowerInvariant() + '  Windows-Startup-App-Manager-Setup-2.1.1.exe')) | Should Be $true
        $assembly = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($setup))
        $payload = $assembly.GetManifestResourceStream('StartupManager.Payload.zip')
        $hasher = [Security.Cryptography.SHA256]::Create()
        try {
            $payload.Length | Should Be (Get-Item $archive).Length
            ([BitConverter]::ToString($hasher.ComputeHash($payload))).Replace('-','') | Should Be (Get-FileHash $archive -Algorithm SHA256).Hash
        } finally { $hasher.Dispose(); $payload.Dispose() }
        $extracted = Join-Path $TestDrive 'extracted-setup'
        $start = New-Object Diagnostics.ProcessStartInfo($setup, ('/extract-only "' + $extracted + '"'))
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $process = [Diagnostics.Process]::Start($start)
        $process.WaitForExit()
        $process.ExitCode | Should Be 0
        $process.Dispose()
        (Get-FileHash (Join-Path $extracted 'Windows-Startup-App-Manager\Install.ps1')).Hash | Should Be (Get-FileHash (Join-Path $script:PackageRoot 'Install.ps1')).Hash
        $repeat = [Diagnostics.Process]::Start($start)
        $repeat.WaitForExit()
        $repeat.ExitCode | Should Be 1
        $repeat.Dispose()
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead($archive)
        try {
            $names = @($zip.Entries | ForEach-Object { $_.FullName.Replace('\','/') })
            ($names -contains 'Windows-Startup-App-Manager/LICENSE') | Should Be $true
            ($names -contains 'Windows-Startup-App-Manager/StartupManager.exe') | Should Be $true
            @($names | Where-Object { $_ -match '(CLAUDE|main-window|\.git/|logs/|backups/|reports/|exports/)' }).Count | Should Be 0
        } finally { $zip.Dispose() }
        { & (Join-Path $script:PackageRoot 'build\Build-Release.ps1') -OutputDirectory $output } | Should Throw
    }

    It 'refuses to uninstall a source checkout that is not the registered install' {
        Mock Get-ItemProperty { [pscustomobject]@{ InstallLocation = (Join-Path $TestDrive 'different-install') } }
        Mock Move-Item { throw 'Unexpected move' }
        Mock Remove-Item { throw 'Unexpected removal' }
        { & (Join-Path $script:PackageRoot 'Uninstall.ps1') -Quiet } | Should Throw
        Assert-MockCalled Move-Item -Times 0 -Exactly -Scope It
        Assert-MockCalled Remove-Item -Times 0 -Exactly -Scope It
    }
}

Describe 'Setup archive safety' {
    It 'rejects traversal, absolute paths, alternate streams and duplicate paths' {
        Add-Type -Path (Join-Path $script:PackageRoot 'build\Installer.cs') -ReferencedAssemblies System.Windows.Forms,System.Drawing,System.IO.Compression,System.IO.Compression.FileSystem
        foreach ($name in @('../outside.txt','/absolute.txt','C:\outside.txt','folder/../../outside.txt','folder/file:stream','folder/CON','folder/file.')) {
            { [StartupManagerSetup.Payload]::GetSafePath((Join-Path $TestDrive 'safe'), $name) } | Should Throw
        }
        $memory = New-Object IO.MemoryStream
        $archive = New-Object IO.Compression.ZipArchive($memory, [IO.Compression.ZipArchiveMode]::Create, $true)
        [void]$archive.CreateEntry('same.txt')
        [void]$archive.CreateEntry('SAME.txt')
        $archive.Dispose()
        $memory.Position = 0
        try { { [StartupManagerSetup.Payload]::Extract($memory, (Join-Path $TestDrive 'duplicate')) } | Should Throw }
        finally { $memory.Dispose() }
        Test-Path -LiteralPath (Join-Path $TestDrive 'duplicate') | Should Be $false
    }
}
