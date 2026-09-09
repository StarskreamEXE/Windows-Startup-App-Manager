# Export layer - turns entry objects into CSV / JSON / TXT / HTML on disk.
# Dot-source after Engine. No side effects except function/variable definitions.

Set-StrictMode -Version 2.0

# The flat column set every export format uses, in display order.
$script:SMExportColumns = @(
    'Enabled', 'Risk', 'Flags', 'Name', 'What', 'Category',
    'Publisher', 'SigStatus', 'BootMs', 'BootMeasuredAt', 'BootConfidence', 'RiskEvidence', 'SecurityFlags', 'Command', 'ExePath', 'Source'
)

# Risk -> hex colour used by every HTML surface (export table and report).
$script:SMRiskHtmlColors = [ordered]@{
    Critical   = '#ff5c5c'
    Suspicious = '#ff9f43'
    Broken     = '#8e8e93'
    Caution    = '#ffd166'
    Optional   = '#6ee7a8'
    Unknown    = '#c0c0c0'
}

# Command / ExePath are truncated to this many characters in the txt table.
$script:SMTxtCellCap = 80

function Get-SMPropertyValue {
    <#
    .SYNOPSIS
        StrictMode-safe property read. Returns $Default when the object is null,
        the property is absent, or its value is null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)] $Object,
        [Parameter(Position = 1, Mandatory)] [string] $Name,
        [Parameter(Position = 2)] $Default = ''
    )
    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $Default }
    if ($null -eq $prop.Value) { return $Default }
    return $prop.Value
}

function ConvertTo-SMShareSafeEntries {
    param([AllowNull()] [AllowEmptyCollection()] $Entries)
    $index = 0
    foreach ($entry in @($Entries)) {
        if ($null -eq $entry) { continue }
        $index++
        $kind = [string](Get-SMPropertyValue $entry 'Kind' 'RunKey')
        if ($kind -notin @('RunKey','RunOnce','Folder','Task','Service','Uwp')) { $kind = 'RunKey' }
        $safe = New-SMEntry -Name "Entry $index" -Kind $kind -Category $kind -Enabled ([bool](Get-SMPropertyValue $entry 'Enabled' $false))
        $risk = [string](Get-SMPropertyValue $entry 'Risk' 'Unknown')
        if ($risk -in $script:SMRiskLevels) { $safe.Risk = $risk }
        $safe.Flags = @((Get-SMPropertyValue $entry 'Flags' @()) | Where-Object { $_ -in $script:SMFlagList })
        $signature = [string](Get-SMPropertyValue $entry 'SigStatus' 'Unknown')
        if ($signature -in $script:SMSigStatus) { $safe.SigStatus = $signature }
        $safe.BootMs = [int](Get-SMPropertyValue $entry 'BootMs' -1)
        $safe.DegradeMs = [int](Get-SMPropertyValue $entry 'DegradeMs' -1)
        $safe
    }
}

function ConvertTo-SMHtmlText {
    <# HTML-escapes a value. Everything that reaches an HTML file goes through this. #>
    [CmdletBinding()]
    param([Parameter(Position = 0)] $Text)
    if ($null -eq $Text) { return '' }
    $s = [string]$Text
    $s = $s -replace '&', '&amp;'
    $s = $s -replace '<', '&lt;'
    $s = $s -replace '>', '&gt;'
    $s = $s -replace '"', '&quot;'
    $s = $s -replace "'", '&#39;'
    return $s
}

function Get-SMRiskHtmlColor {
    <# Hex colour for a risk level; Unknown's colour for anything unrecognised. #>
    [CmdletBinding()]
    param([Parameter(Position = 0)] [string] $Risk)
    if ($Risk -and $script:SMRiskHtmlColors.Contains($Risk)) { return $script:SMRiskHtmlColors[$Risk] }
    return $script:SMRiskHtmlColors['Unknown']
}

function ConvertTo-SMFlatEntry {
    <#
    .SYNOPSIS
        Projects one entry onto the flat export column set. BootMs becomes ''
        when there is no measurement (-1). Flags are joined with ', '.
        Data and Detail are deliberately dropped.
    #>
    [CmdletBinding()]
    param([Parameter(Position = 0)] $Entry)

    $bootRaw = Get-SMPropertyValue $Entry 'BootMs' -Default -1
    $boot = -1
    try { $boot = [int]$bootRaw } catch { $boot = -1 }

    [pscustomobject][ordered]@{
        Enabled   = [bool](Get-SMPropertyValue $Entry 'Enabled' -Default $false)
        Risk      = [string](Get-SMPropertyValue $Entry 'Risk' -Default 'Unknown')
        Flags     = (@(Get-SMPropertyValue $Entry 'Flags' -Default @()) -join ', ')
        Name      = [string](Get-SMPropertyValue $Entry 'Name')
        What      = [string](Get-SMPropertyValue $Entry 'What')
        Category  = [string](Get-SMPropertyValue $Entry 'Category')
        Publisher = [string](Get-SMPropertyValue $Entry 'Publisher')
        SigStatus = [string](Get-SMPropertyValue $Entry 'SigStatus' -Default 'Unknown')
        BootMs    = $(if ($boot -ge 0) { $boot } else { '' })
        BootMeasuredAt = [string](Get-SMPropertyValue $Entry 'BootMeasuredAt')
        BootConfidence = [string](Get-SMPropertyValue $Entry 'BootConfidence')
        RiskEvidence = [string](Get-SMPropertyValue $Entry 'RiskEvidence')
        SecurityFlags = (@(Get-SMPropertyValue $Entry 'SecurityFlags' @()) -join ', ')
        Command   = [string](Get-SMPropertyValue $Entry 'Command')
        ExePath   = [string](Get-SMPropertyValue $Entry 'ExePath')
        Source    = [string](Get-SMPropertyValue $Entry 'Source')
    }
}

function Get-SMHtmlStyle {
    <# The one inline stylesheet. Dark theme, printable, no external assets. #>
    [CmdletBinding()]
    param()
    # skreamb0t brand tokens (dark). Paper & ink, 1px ink borders, hard block shadows,
    # mono uppercase labels. No external assets: fonts fall back if not installed.
    $css = @(
        ':root{--paper:#1D1D1B;--panel:#262624;--surface:#151514;--ink:#DCDAD5;--highlight:#333330;--dim:#8E8D89;--purple:#a855f7;--sans:"Inter",ui-sans-serif,system-ui,sans-serif;--mono:"JetBrains Mono",Consolas,ui-monospace,monospace;--pixel:"Press Start 2P",var(--sans)}'
        'body{background:var(--paper);color:var(--ink);font-family:var(--sans);font-size:13px;margin:0;padding:28px}'
        '.brand{display:flex;align-items:center;gap:14px;margin:0 0 18px 0}'
        '.mascot{width:56px;height:56px;object-fit:contain}'
        '.brand .by{margin:4px 0 0 0}'
        '.wm{display:flex;align-items:flex-end;gap:4px;margin:0;font-weight:700;font-size:22px;letter-spacing:-.02em;text-transform:uppercase;line-height:1}'
        '.wm .px{font-family:var(--pixel);font-size:12px;text-shadow:1px 1px 0 var(--purple);margin-left:3px;padding-bottom:2px}'
        '.by{font-family:var(--mono);font-size:9px;font-weight:700;opacity:.7;text-transform:lowercase;margin:4px 0 18px 0;display:block}'
        '.zero{background:linear-gradient(to right,#9333ea,#f0abfc,#9333ea);background-size:200% auto;-webkit-background-clip:text;background-clip:text;color:transparent;animation:tg 2s linear infinite}'
        '@keyframes tg{to{background-position:200% center}}'
        '@media(prefers-reduced-motion:reduce){.zero{animation:none;color:#a855f7}}'
        'h2{font-family:var(--mono);font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.15em;color:var(--dim);margin:30px 0 8px 0;border-bottom:1px solid var(--ink);padding-bottom:5px}'
        'p{margin:4px 0}'
        '.meta{font-family:var(--mono);font-size:11px;color:var(--dim)}'
        '.callout{background:var(--panel);border:1px solid var(--ink);box-shadow:3px 3px 0 0 var(--ink);padding:12px 16px;margin:16px 0}'
        '.empty{color:var(--dim);font-style:italic}'
        'table{border-collapse:collapse;width:100%;margin:6px 0 18px 0;background:var(--panel);border:1px solid var(--ink);box-shadow:3px 3px 0 0 var(--ink)}'
        'th{background:var(--surface);color:var(--ink);text-align:left;font-family:var(--mono);font-size:9px;font-weight:700;text-transform:uppercase;letter-spacing:.12em;padding:7px 8px;border:1px solid var(--ink);white-space:nowrap;cursor:pointer}'
        'th:hover{background:var(--ink);color:var(--paper)}'
        'td{padding:5px 8px;border:1px solid var(--highlight);vertical-align:top;word-break:break-word}'
        'tbody tr:nth-child(even){background:var(--paper)}'
        'tbody tr:hover{background:var(--highlight)}'
        'td.num{text-align:right;white-space:nowrap;font-family:var(--mono)}'
        'code{font-family:var(--mono);color:var(--ink);font-size:11px}'
        'details{margin:0}'
        'summary{cursor:pointer;font-family:var(--mono);font-size:10px;text-transform:uppercase;letter-spacing:.08em}'
        'details p{margin:4px 0 0 0}'
        '.ok{color:#22c55e}'
        '.bad{color:#ef4444}'
        '@media print{:root{--paper:#E4E3E0;--panel:#F0EFEC;--surface:#D1D0CC;--ink:#141414;--highlight:#FFFFFF;--dim:#555}table{box-shadow:none}}'
    )
    return ($css -join [Environment]::NewLine)
}

function Get-SMHtmlWordmark {
    <# The brand header: STARTUP.MANAGER + "by skreamb0t" with the animated 0. #>
    [CmdletBinding()]
    param([string] $Suffix = 'MANAGER')
    # mascot embedded as a data URI so the report stays a single self-contained file
    $imgTag = ''
    try {
        $mascot = Join-Path (Get-SMState).Root 'assets\skreambot.png'
        if (Test-Path -LiteralPath $mascot) {
            $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($mascot))
            $imgTag = '<img class="mascot" alt="skreamb0t" src="data:image/png;base64,' + $b64 + '">'
        }
    } catch { $imgTag = '' }
    return ('<div class="brand">' + $imgTag + '<div><h1 class="wm">STARTUP.<span class="px">' + (ConvertTo-SMHtmlText $Suffix) + '</span></h1>' +
            '<span class="by">by skreamb<span class="zero">0</span>t</span></div></div>')
}

function Get-SMHtmlSortScript {
    <# Inline vanilla JS: click a header in any table.sortable to sort it. #>
    [CmdletBinding()]
    param()
    $js = @(
        '<script>'
        '(function(){'
        "var ts=document.querySelectorAll('table.sortable');"
        'for(var i=0;i<ts.length;i++){mk(ts[i]);}'
        'function mk(t){if(!t.tHead||!t.tHead.rows.length)return;var hs=t.tHead.rows[0].cells;'
        'for(var i=0;i<hs.length;i++){bind(t,hs,i);}}'
        "function bind(t,hs,n){hs[n].style.cursor='pointer';hs[n].title='Click to sort';"
        'hs[n].onclick=function(){var tb=t.tBodies[0];if(!tb)return;'
        'var rows=[].slice.call(tb.rows);'
        "var dir=hs[n].getAttribute('data-dir')==='asc'?-1:1;"
        "for(var j=0;j<hs.length;j++){hs[j].removeAttribute('data-dir');}"
        "hs[n].setAttribute('data-dir',dir===1?'asc':'desc');"
        'rows.sort(function(a,b){'
        "var x=(a.cells[n].getAttribute('data-v')||a.cells[n].textContent||'');"
        "var y=(b.cells[n].getAttribute('data-v')||b.cells[n].textContent||'');"
        'var nx=parseFloat(x),ny=parseFloat(y);'
        "if(x!==''&&y!==''&&!isNaN(nx)&&!isNaN(ny))return (nx-ny)*dir;"
        'x=x.toLowerCase();y=y.toLowerCase();'
        'return x<y?-dir:(x>y?dir:0);});'
        'for(var k=0;k<rows.length;k++){tb.appendChild(rows[k]);}};}'
        '})();'
        '</script>'
    )
    return ($js -join [Environment]::NewLine)
}

function New-SMHtmlTable {
    <#
    .SYNOPSIS
        Escaped HTML table from flat objects. -Columns picks and orders the
        properties, -NumericColumns right-aligns, -RiskColumn colours that cell
        by risk level, -RawHtmlColumns passes already-built HTML straight through.
        Renders an "(none)" paragraph when there is nothing to show.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)] [AllowNull()] [AllowEmptyCollection()] $Objects,
        [Parameter(Mandatory)] [string[]] $Columns,
        [string[]] $Headers,
        [string[]] $NumericColumns = @(),
        [string[]] $RawHtmlColumns = @(),
        [string] $RiskColumn = '',
        [string] $EmptyText = '(none)'
    )
    $rows = @(@($Objects) | Where-Object { $null -ne $_ })
    if ($rows.Count -eq 0) { return ('<p class="empty">' + (ConvertTo-SMHtmlText $EmptyText) + '</p>') }

    $head = if ($Headers -and $Headers.Count -eq $Columns.Count) { $Headers } else { $Columns }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<table class="sortable"><thead><tr>')
    foreach ($h in $head) { [void]$sb.AppendLine('<th>' + (ConvertTo-SMHtmlText $h) + '</th>') }
    [void]$sb.AppendLine('</tr></thead><tbody>')
    foreach ($row in $rows) {
        [void]$sb.AppendLine('<tr>')
        foreach ($c in $Columns) {
            $raw = [string](Get-SMPropertyValue $row $c)
            if ($RawHtmlColumns -contains $c) {
                [void]$sb.AppendLine('<td>' + $raw + '</td>')
                continue
            }
            $esc = ConvertTo-SMHtmlText $raw
            $cls = ''
            $style = ''
            if ($NumericColumns -contains $c) { $cls = ' class="num"' }
            if ($RiskColumn -and $c -eq $RiskColumn) {
                $style = ' style="color:' + (Get-SMRiskHtmlColor $raw) + ';font-weight:600"'
            }
            [void]$sb.AppendLine('<td' + $cls + $style + ' data-v="' + $esc + '">' + $esc + '</td>')
        }
        [void]$sb.AppendLine('</tr>')
    }
    [void]$sb.AppendLine('</tbody></table>')
    return $sb.ToString()
}

function Write-SMExportLog {
    <# INFO log line, but only if the Logging layer happens to be loaded. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Message)
    $cmd = Get-Command -Name 'Write-SMLog' -ErrorAction SilentlyContinue
    if ($cmd) { Write-SMLog -Level 'INFO' -Message $Message }
}

function Initialize-SMExportDirectory {
    <# Makes sure the parent folder of an output file exists. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    $dir = Split-Path -Path $Path -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function ConvertTo-SMTxtTable {
    <# Fixed-width aligned text table over the flat export columns. #>
    [CmdletBinding()]
    param([Parameter(Position = 0)] [AllowNull()] [AllowEmptyCollection()] $FlatRows)

    $ellipsis = [string][char]0x2026
    $cols = $script:SMExportColumns
    $capped = @('Command', 'ExePath')

    $cells = New-Object System.Collections.ArrayList
    foreach ($r in @($FlatRows)) {
        if ($null -eq $r) { continue }
        $line = [ordered]@{}
        foreach ($c in $cols) {
            $v = [string](Get-SMPropertyValue $r $c)
            $v = $v -replace '[\r\n\t]+', ' '
            if ($capped -contains $c -and $v.Length -gt $script:SMTxtCellCap) {
                $v = $v.Substring(0, $script:SMTxtCellCap - 1) + $ellipsis
            }
            $line[$c] = $v
        }
        [void]$cells.Add($line)
    }

    $width = @{}
    foreach ($c in $cols) {
        $w = $c.Length
        foreach ($line in $cells) { if ($line[$c].Length -gt $w) { $w = $line[$c].Length } }
        $width[$c] = $w
    }

    $sb = New-Object System.Text.StringBuilder
    $headParts = @()
    $ruleParts = @()
    foreach ($c in $cols) {
        $headParts += $c.PadRight($width[$c])
        $ruleParts += ('-' * $width[$c])
    }
    [void]$sb.AppendLine(($headParts -join '  ').TrimEnd())
    [void]$sb.AppendLine(($ruleParts -join '  ').TrimEnd())
    foreach ($line in $cells) {
        $parts = @()
        foreach ($c in $cols) { $parts += $line[$c].PadRight($width[$c]) }
        [void]$sb.AppendLine(($parts -join '  ').TrimEnd())
    }
    return $sb.ToString()
}

function ConvertTo-SMEntriesHtml {
    <# Standalone dark HTML page holding the flat entry table. #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)] [AllowNull()] [AllowEmptyCollection()] $FlatRows,
        [string] $Title = 'Startup Manager - Startup Entries'
    )
    $rows = @(@($FlatRows) | Where-Object { $null -ne $_ })
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<!DOCTYPE html>')
    [void]$sb.AppendLine('<html lang="en"><head><meta charset="utf-8">')
    [void]$sb.AppendLine('<title>' + (ConvertTo-SMHtmlText $Title) + '</title>')
    [void]$sb.AppendLine('<style>')
    [void]$sb.AppendLine((Get-SMHtmlStyle))
    [void]$sb.AppendLine('</style></head><body>')
    [void]$sb.AppendLine((Get-SMHtmlWordmark -Suffix 'EXPORT'))
    [void]$sb.AppendLine('<p class="meta">' + (ConvertTo-SMHtmlText ('Exported {0} - {1} entries - click a column header to sort' -f $stamp, $rows.Count)) + '</p>')
    [void]$sb.AppendLine((New-SMHtmlTable -Objects $rows -Columns $script:SMExportColumns -NumericColumns @('BootMs') -RiskColumn 'Risk' -EmptyText 'No startup entries to show.'))
    [void]$sb.AppendLine((Get-SMHtmlSortScript))
    [void]$sb.AppendLine('</body></html>')
    return $sb.ToString()
}

function Export-SMEntries {
    <#
    .SYNOPSIS
        Writes the given entries to $Path as csv, json, txt or html.
    .DESCRIPTION
        Always the same flat column set: Enabled, Risk, Flags, Name, What,
        Category, Publisher, SigStatus, BootMs, Command, ExePath, Source.
        The provider-private Data hashtable and the Detail block are never
        exported. Returns the path that was written.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowNull()] [AllowEmptyCollection()] $Entries,
        [Parameter(Mandatory)] [ValidateSet('csv', 'json', 'txt', 'html')] [string] $Format,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Path,
        [switch] $ShareSafe
    )

    Initialize-SMExportDirectory -Path $Path

    if ($ShareSafe) { $Entries = @(ConvertTo-SMShareSafeEntries -Entries $Entries) }

    $flat = @()
    foreach ($e in @($Entries)) {
        if ($null -eq $e) { continue }
        $flat += (ConvertTo-SMFlatEntry $e)
    }

    switch ($Format) {
        'csv' {
            foreach ($row in $flat) {
                foreach ($property in $row.PSObject.Properties) {
                    if ($property.Value -is [string] -and $property.Value -match '^[\s]*[=+@-]') {
                        $property.Value = "'" + $property.Value
                    }
                }
            }
            if ($flat.Count -eq 0) {
                $header = ($script:SMExportColumns | ForEach-Object { '"' + $_ + '"' }) -join ','
                Set-Content -LiteralPath $Path -Value $header -Encoding UTF8
            }
            else {
                $flat | Select-Object -Property $script:SMExportColumns |
                    Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
            }
        }
        'json' {
            if ($flat.Count -eq 0) {
                $json = '[]'
            }
            else {
                $json = $flat | Select-Object -Property $script:SMExportColumns | ConvertTo-Json -Depth 4
                # PowerShell 5.1 emits a bare object (not an array) for a single item.
                if ($flat.Count -eq 1) { $json = '[' + [Environment]::NewLine + $json + [Environment]::NewLine + ']' }
            }
            Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
        }
        'txt' {
            Set-Content -LiteralPath $Path -Value (ConvertTo-SMTxtTable $flat) -Encoding UTF8
        }
        'html' {
            Set-Content -LiteralPath $Path -Value (ConvertTo-SMEntriesHtml $flat) -Encoding UTF8
        }
    }

    Write-SMExportLog -Message ('Exported {0} entries as {1} to {2}' -f $flat.Count, $Format, $Path)
    return $Path
}
