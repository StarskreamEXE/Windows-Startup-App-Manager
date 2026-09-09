Set-StrictMode -Version 2.0
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src\UI\Theme.ps1')

Describe 'Ctrl wheel zoom routing' {
    BeforeEach {
        $script:zoomForm = $null
        Initialize-SMNativeControls
        $script:zoomForm = New-Object Windows.Forms.Form
        $script:zoomBox = New-Object Windows.Forms.TextBox
        $script:zoomForm.Controls.Add($script:zoomBox)
        $script:zoomFilter = New-Object StartupManager.ZoomWheelFilter($script:zoomForm)
        $script:zoomSteps = 0
        $script:zoomFilter.add_ZoomRequested({ param($steps) $script:zoomSteps += $steps })
    }
    AfterEach { if ($script:zoomForm) { $script:zoomForm.Dispose() } }

    It 'consumes Ctrl wheel and requests one zoom step' {
        $message = [Windows.Forms.Message]::Create($script:zoomBox.Handle, 0x20A, [IntPtr]((120 -shl 16) -bor 8), [IntPtr]::Zero)
        $script:zoomFilter.PreFilterMessage([ref]$message) | Should Be $true
        $script:zoomSteps | Should Be 1
    }
    It 'leaves ordinary wheel input available for scrolling' {
        $message = [Windows.Forms.Message]::Create($script:zoomBox.Handle, 0x20A, [IntPtr](120 -shl 16), [IntPtr]::Zero)
        $script:zoomFilter.PreFilterMessage([ref]$message) | Should Be $false
        $script:zoomSteps | Should Be 0
    }
    It 'accumulates high resolution wheel movement and supports zoom out' {
        foreach ($delta in @(-60, -60)) {
            $message = [Windows.Forms.Message]::Create($script:zoomBox.Handle, 0x20A, [IntPtr](($delta -shl 16) -bor 8), [IntPtr]::Zero)
            [void]$script:zoomFilter.PreFilterMessage([ref]$message)
        }
        $script:zoomSteps | Should Be -1
    }
    It 'does not intercept wheel input for another window' {
        $other = New-Object Windows.Forms.Form
        try {
            $message = [Windows.Forms.Message]::Create($other.Handle, 0x20A, [IntPtr]((120 -shl 16) -bor 8), [IntPtr]::Zero)
            $script:zoomFilter.PreFilterMessage([ref]$message) | Should Be $false
            $script:zoomSteps | Should Be 0
        } finally { $other.Dispose() }
    }
}
