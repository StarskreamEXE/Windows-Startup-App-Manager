@echo off
title Startup Manager - install
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" -Launch
if errorlevel 1 (
    echo.
    echo Install failed. See the messages above.
    pause
)
