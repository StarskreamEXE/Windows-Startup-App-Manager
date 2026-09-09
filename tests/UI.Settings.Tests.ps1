Set-StrictMode -Version 2.0
$root = Split-Path -Parent $PSScriptRoot
$settingsFile = Join-Path $root 'src/Core/Settings.ps1'
if (Test-Path $settingsFile) { . $settingsFile }

Describe 'Display preferences' {
    It 'defaults safely when settings are absent or invalid' {
        $path = Join-Path $TestDrive 'settings.json'
        (Get-SMPreferences -Path $path).Zoom | Should Be 1.0
        Set-Content $path '{ broken'
        (Get-SMPreferences -Path $path).ReducedMotion | Should Be $false
    }
    It 'persists zoom and reduced motion but not advanced mode' {
        $path = Join-Path $TestDrive 'settings.json'
        Save-SMPreferences -Path $path -Zoom 1.3 -ReducedMotion $true
        $settings = Get-SMPreferences -Path $path
        $settings.Zoom | Should Be 1.3
        $settings.ReducedMotion | Should Be $true
        (Get-Content $path -Raw) | Should Not Match 'Advanced'
    }
    It 'rejects out-of-range zoom from a modified settings file' {
        $path = Join-Path $TestDrive 'settings.json'
        Set-Content $path '{"Zoom":100,"ReducedMotion":true}'
        (Get-SMPreferences -Path $path).Zoom | Should Be 1.0
    }
}
