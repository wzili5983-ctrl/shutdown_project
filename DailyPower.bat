@echo off
setlocal
title Daily Power Schedule
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0DailyPower.ps1"
pause
endlocal
