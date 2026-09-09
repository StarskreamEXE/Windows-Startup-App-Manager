# Hard facts about a file on disk: publisher, product, version, size, Authenticode.
# Nothing is guessed - anything that cannot be read stays empty / 'Unknown'.
# Dot-source after src/Core/Paths.ps1.

Set-StrictMode -Version 2.0

# Per-path cache. Key = lower-case path. Value = the facts hashtable.
$script:SMFileFactsCache = @{}

function Resolve-SMExePath {
    <#
    .SYNOPSIS
        Extracts the executable path out of a registered command line.
    .DESCRIPTION
        Order: quoted first token -> first '...\<something>.exe|com|bat|cmd|scr'
        -> first whitespace-delimited token. %VAR% environment variables are
        expanded. The NT-namespace prefixes seen in service PathName values are
        normalised: '\??\' is stripped, '\SystemRoot\' becomes the real Windows
        directory. Returns '' when there is nothing to resolve.
    #>
    [CmdletBinding()]
    param([string] $Command = '')

    if ([string]::IsNullOrWhiteSpace($Command)) { return '' }

    $c = $Command.Trim()
    $path = ''

    if ($c.StartsWith('"')) {
        $end = $c.IndexOf('"', 1)
        if ($end -gt 0) { $path = $c.Substring(1, $end - 1) }
        else            { $path = $c.Substring(1) }
    }
    else {
        $c = ConvertTo-SMNormalPath $c
        $m = [regex]::Match($c, '^(.*?\.(exe|com|bat|cmd|scr))(\s|$)', 'IgnoreCase')
        if ($m.Success) { $path = $m.Groups[1].Value }
        else            { $path = ($c -split '\s+')[0] }
    }

    if ([string]::IsNullOrWhiteSpace($path)) { return '' }

    $path = [Environment]::ExpandEnvironmentVariables($path)
    $path = ConvertTo-SMNormalPath $path
    return $path.Trim()
}

function ConvertTo-SMNormalPath {
    <# Strips '\??\' and expands a leading '\SystemRoot\'. Internal helper. #>
    [CmdletBinding()]
    param([string] $Path = '')

    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    $p = $Path.Trim()
    if ($p.StartsWith('\??\'))    { $p = $p.Substring(4) }
    $sysRootPrefix = '\SystemRoot\'
    if ($p.Length -gt $sysRootPrefix.Length -and
        $p.Substring(0, $sysRootPrefix.Length).Equals($sysRootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        $p = (Join-Path $env:SystemRoot $p.Substring($sysRootPrefix.Length))
    }
    return $p
}

function New-SMEmptyFileFacts {
    <# The "we know nothing" shape. Internal helper. #>
    return @{
        Exists      = $false
        Publisher   = ''
        Product     = ''
        FileVersion = ''
        SizeKB      = 0
        SigStatus   = 'Unknown'
        SigSigner   = ''
    }
}

function Get-SMFileFacts {
    <#
    .SYNOPSIS
        Returns @{Exists;Publisher;Product;FileVersion;SizeKB;SigStatus;SigSigner}
        for one file. Cached per lower-case path in $script:SMFileFactsCache
        because Get-AuthenticodeSignature costs 20-30 ms per file.
    #>
    [CmdletBinding()]
    param([string] $Path = '')

    if ([string]::IsNullOrWhiteSpace($Path)) { return (New-SMEmptyFileFacts) }

    $key = $Path.ToLowerInvariant()
    if ($script:SMFileFactsCache.ContainsKey($key)) { return $script:SMFileFactsCache[$key] }

    $facts = New-SMEmptyFileFacts

    $exists = $false
    try { $exists = [bool](Test-Path -LiteralPath $Path -PathType Leaf) } catch { $exists = $false }

    if (-not $exists) {
        $script:SMFileFactsCache[$key] = $facts
        return $facts
    }

    $facts.Exists = $true

    try {
        $vi = [Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
        $pub = $vi.CompanyName
        if ([string]::IsNullOrWhiteSpace($pub)) { $pub = $vi.ProductName }
        if (-not [string]::IsNullOrWhiteSpace($pub))              { $facts.Publisher   = $pub.Trim() }
        if (-not [string]::IsNullOrWhiteSpace($vi.ProductName))   { $facts.Product     = $vi.ProductName.Trim() }
        if (-not [string]::IsNullOrWhiteSpace($vi.FileVersion))   { $facts.FileVersion = $vi.FileVersion.Trim() }
    } catch { }

    try {
        $len = (Get-Item -LiteralPath $Path -ErrorAction Stop).Length
        $facts.SizeKB = [int][math]::Ceiling($len / 1KB)
    } catch { }

    try {
        $sig = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
        if ($null -eq $sig) {
            $facts.SigStatus = 'Unknown'
        }
        else {
            $status = [string]$sig.Status
            if     ($status -eq 'Valid')     { $facts.SigStatus = 'Valid' }
            elseif ($status -eq 'NotSigned') { $facts.SigStatus = 'Unsigned' }
            else                             { $facts.SigStatus = 'Invalid' }

            $cert = $null
            if ($sig.PSObject.Properties['SignerCertificate']) { $cert = $sig.SignerCertificate }
            if ($null -ne $cert -and $cert.PSObject.Properties['Subject']) {
                $subject = [string]$cert.Subject
                $m = [regex]::Match($subject, 'CN=([^,]+)')
                if ($m.Success) { $facts.SigSigner = $m.Groups[1].Value.Trim() }
            }
        }
    } catch {
        $facts.SigStatus = 'Unknown'
        $facts.SigSigner = ''
    }

    $script:SMFileFactsCache[$key] = $facts
    return $facts
}

function Clear-SMFileFactsCache {
    <# Drops every cached file fact. Called before a fresh inventory scan. #>
    [CmdletBinding()]
    param()
    $script:SMFileFactsCache = @{}
}
