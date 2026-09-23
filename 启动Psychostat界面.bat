@echo off
setlocal
cd /d "%~dp0"
title Psychostat
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0scripts\psychostat_gui.ps1"
set "exitcode=%ERRORLEVEL%"
if not "%exitcode%"=="0" pause
endlocal & exit /b %exitcode%
