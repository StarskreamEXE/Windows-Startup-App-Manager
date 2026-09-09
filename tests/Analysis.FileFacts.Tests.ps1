# Pester 3.4 - Analysis layer: Resolve-SMExePath, Get-SMFileFacts, Get-SMBootPerf.
# Read-only: nothing here touches real startup state.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here

. (Join-Path $root 'src\Core\Contracts.ps1')
. (Join-Path $root 'src\Core\Paths.ps1')
. (Join-Path $root 'src\Analysis\FileFacts.ps1')
. (Join-Path $root 'src\Analysis\BootPerf.ps1')

function New-SMFakeEvent101 {
    <# A stand-in for an EventLogRecord: ToXml() returns a crafted event-101 document. #>
    param(
        [string] $Name,
        [string] $FriendlyName = '',
        [string] $Path = '',
        [int]    $TotalTime = 0,
        [int]    $DegradationTime = 0,
        [string] $StartTime = (Get-Date).ToUniversalTime().ToString('o')
    )
    $xml = '<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event">' +
           '<System><EventID>101</EventID><TimeCreated SystemTime="' + $StartTime + '"/></System>' +
           '<EventData>' +
           '<Data Name="StartTime">' + $StartTime + '</Data>' +
           '<Data Name="Name">' + $Name + '</Data>' +
           '<Data Name="FriendlyName">' + $FriendlyName + '</Data>' +
           '<Data Name="Version">10.0.0.1</Data>' +
           '<Data Name="TotalTime">' + $TotalTime + '</Data>' +
           '<Data Name="DegradationTime">' + $DegradationTime + '</Data>' +
           '<Data Name="Path">' + $Path + '</Data>' +
           '</EventData></Event>'
    $o = New-Object PSObject -Property @{
        TimeCreated = [datetime]'2026-01-02T03:04:05Z'
        XmlText     = $xml
    }
    $o | Add-Member -MemberType ScriptMethod -Name ToXml -Value { $this.XmlText }
    return $o
}

Describe 'Resolve-SMExePath' {

    It 'returns an empty string for an empty command' {
        (Resolve-SMExePath '').Length | Should Be 0
    }

    It 'returns an empty string for whitespace' {
        (Resolve-SMExePath '   ').Length | Should Be 0
    }

    It 'takes the quoted token when the path contains spaces' {
        Resolve-SMExePath '"C:\Program Files\Acme App\acme.exe" --background' |
            Should BeExactly 'C:\Program Files\Acme App\acme.exe'
    }

    It 'stops at the executable extension when unquoted with arguments' {
        Resolve-SMExePath 'C:\Tools\thing.exe /silent /nogui' |
            Should BeExactly 'C:\Tools\thing.exe'
    }

    It 'expands %SystemRoot% style environment variables' {
        Resolve-SMExePath '%SystemRoot%\system32\notepad.exe' |
            Should BeExactly (Join-Path $env:SystemRoot 'system32\notepad.exe')
    }

    It 'expands a leading \SystemRoot\ prefix' {
        Resolve-SMExePath '\SystemRoot\System32\svchost.exe -k netsvcs' |
            Should BeExactly (Join-Path $env:SystemRoot 'System32\svchost.exe')
    }

    It 'strips the \??\ NT namespace prefix' {
        Resolve-SMExePath '\??\C:\Program Files\Acme\agent.exe' |
            Should BeExactly 'C:\Program Files\Acme\agent.exe'
    }

    It 'resolves the host executable of a rundll32 style command' {
        Resolve-SMExePath 'rundll32.exe "C:\Program Files\Acme\acme.dll",StartUp' |
            Should BeExactly 'rundll32.exe'
    }

    It 'falls back to the first whitespace token when there is no known extension' {
        Resolve-SMExePath 'C:\Tools\runner --flag' | Should BeExactly 'C:\Tools\runner'
    }
}

Describe 'Get-SMFileFacts' {

    Context 'a real system executable' {
        Clear-SMFileFactsCache
        $notepad = Join-Path $env:SystemRoot 'System32\notepad.exe'
        $facts   = Get-SMFileFacts -Path $notepad

        It 'reports the file as existing' { $facts.Exists | Should Be $true }
        It 'reports a known signature status' {
            @('Valid', 'Unsigned', 'Invalid') -contains $facts.SigStatus | Should Be $true
        }
        It 'reports a non-empty publisher' { $facts.Publisher.Length -gt 0 | Should Be $true }
        It 'reports a positive size in KB' { $facts.SizeKB -gt 0 | Should Be $true }
    }

    Context 'a path that does not exist' {
        Clear-SMFileFactsCache
        $facts = Get-SMFileFacts -Path 'C:\NoSuchFolder_SMTest\nope.exe'

        It 'reports the file as missing' { $facts.Exists | Should Be $false }
        It 'reports Unknown signature'   { $facts.SigStatus | Should BeExactly 'Unknown' }
        It 'reports an empty publisher'  { $facts.Publisher.Length | Should Be 0 }
        It 'reports zero size'           { $facts.SizeKB | Should Be 0 }
    }

    Context 'an empty path' {
        Clear-SMFileFactsCache
        $facts = Get-SMFileFacts -Path ''

        It 'reports the file as missing' { $facts.Exists | Should Be $false }
        It 'reports Unknown signature'   { $facts.SigStatus | Should BeExactly 'Unknown' }
    }

    Context 'caching' {

        It 'calls Get-AuthenticodeSignature only once for two lookups of the same path' {
            Mock Get-AuthenticodeSignature {
                New-Object PSObject -Property @{
                    Status            = 'Valid'
                    SignerCertificate = New-Object PSObject -Property @{
                        Subject = 'CN=Contoso Signing, O=Contoso, C=US'
                    }
                }
            }
            Clear-SMFileFactsCache
            $p = Join-Path $env:SystemRoot 'System32\notepad.exe'
            $a = Get-SMFileFacts -Path $p
            $b = Get-SMFileFacts -Path $p

            $a.SigSigner | Should BeExactly 'Contoso Signing'
            $b.SigSigner | Should BeExactly 'Contoso Signing'
            Assert-MockCalled Get-AuthenticodeSignature -Exactly 1 -Scope It
        }

        It 'is emptied by Clear-SMFileFactsCache' {
            Mock Get-AuthenticodeSignature {
                New-Object PSObject -Property @{ Status = 'NotSigned'; SignerCertificate = $null }
            }
            Clear-SMFileFactsCache
            $p = Join-Path $env:SystemRoot 'System32\notepad.exe'
            $null = Get-SMFileFacts -Path $p
            Clear-SMFileFactsCache
            $f = Get-SMFileFacts -Path $p

            $f.SigStatus | Should BeExactly 'Unsigned'
            $f.SigSigner.Length | Should Be 0
            Assert-MockCalled Get-AuthenticodeSignature -Exactly 2 -Scope It
        }
    }
}

Describe 'Get-SMBootPerf' {

    It 'returns an empty hashtable when the log cannot be read' {
        Mock Get-WinEvent { throw 'No events were found that match the specified selection criteria.' }
        $r = Get-SMBootPerf
        $r.Count | Should Be 0
    }

    It 'parses event 101 into measurements keyed by normalized full path' {
        Mock Get-WinEvent {
            @(
                (New-SMFakeEvent101 -Name 'Taskmgr.exe' -FriendlyName 'Task Manager' -Path 'C:\Windows\System32\Taskmgr.exe' -TotalTime 6971 -DegradationTime 2506)
            )
        }
        $r = Get-SMBootPerf

        $r.Count | Should Be 1
        $r.ContainsKey('c:\windows\system32\taskmgr.exe') | Should Be $true
        $r['c:\windows\system32\taskmgr.exe'].TotalMs | Should Be 6971
        $r['c:\windows\system32\taskmgr.exe'].DegradeMs | Should Be 2506
        $r['c:\windows\system32\taskmgr.exe'].Path | Should BeExactly 'C:\Windows\System32\Taskmgr.exe'
        $r['c:\windows\system32\taskmgr.exe'].FriendlyName | Should BeExactly 'Task Manager'
        $r['c:\windows\system32\taskmgr.exe'].LastSeen.GetType().Name | Should BeExactly 'DateTime'
    }

    It 'keeps the latest measurement rather than the historical maximum' {
        Mock Get-WinEvent {
            @(
                (New-SMFakeEvent101 -Name 'Acme.exe' -Path 'C:\A\Acme.exe' -TotalTime 1200 -DegradationTime 100 -StartTime (Get-Date).AddDays(-2).ToString('o')),
                (New-SMFakeEvent101 -Name 'acme.exe' -Path 'C:\A\Acme.exe' -TotalTime 8400 -DegradationTime 900 -StartTime (Get-Date).AddDays(-1).ToString('o')),
                (New-SMFakeEvent101 -Name 'Acme.exe' -Path 'C:\A\Acme.exe' -TotalTime 300  -DegradationTime 10)
            )
        }
        $r = Get-SMBootPerf

        $r.Count | Should Be 1
        $r['c:\a\acme.exe'].TotalMs | Should Be 300
        $r['c:\a\acme.exe'].DegradeMs | Should Be 10
    }

    It 'skips events whose payload cannot be parsed' {
        Mock Get-WinEvent {
            $bad = New-Object PSObject -Property @{ TimeCreated = [datetime]'2026-01-02T03:04:05Z' }
            $bad | Add-Member -MemberType ScriptMethod -Name ToXml -Value { 'not xml at all <<<' }
            @(
                $bad,
                (New-SMFakeEvent101 -Name 'Good.exe' -Path 'C:\G\Good.exe' -TotalTime 500 -DegradationTime 5)
            )
        }
        $r = Get-SMBootPerf

        $r.Count | Should Be 1
        $r['c:\g\good.exe'].TotalMs | Should Be 500
    }
    It 'bounds the query and rejects stale and pathless measurements' {
        Mock Get-WinEvent {
            (New-SMFakeEvent101 -Name 'old.exe' -Path 'C:\old.exe' -StartTime (Get-Date).AddDays(-31).ToString('o'))
            (New-SMFakeEvent101 -Name 'unknown.exe')
        }
        (Get-SMBootPerf).Count | Should Be 0
        Assert-MockCalled Get-WinEvent -Scope It -ParameterFilter { $MaxEvents -eq 1000 -and $FilterHashtable.ContainsKey('StartTime') }
    }
    It 'rejects negative timing and keeps same filename at different paths separate' {
        Mock Get-WinEvent {
            (New-SMFakeEvent101 -Name 'app.exe' -Path 'C:\A\app.exe' -TotalTime 100)
            (New-SMFakeEvent101 -Name 'app.exe' -Path 'C:\B\app.exe' -TotalTime 200)
            (New-SMFakeEvent101 -Name 'bad.exe' -Path 'C:\bad.exe' -TotalTime -10)
        }
        $result = Get-SMBootPerf
        $result.Count | Should Be 2
        $result['c:\a\app.exe'].TotalMs | Should Be 100
        $result['c:\b\app.exe'].TotalMs | Should Be 200
    }
}
