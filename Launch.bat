@echo off
rem Launch Startup Manager from this folder (exe if present, otherwise the script).
if exist "%~dp0StartupManager.exe" (
    start "" "%~dp0StartupManager.exe"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Start-StartupManager.ps1"
)
