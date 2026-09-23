@echo off
setlocal
cd /d "%~dp0"
title Psychostat CTT
echo.
echo Starting Psychostat CTT (scale development: cleaning/item analysis/EFA/CFA)...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_ctt_analysis.ps1"
set "exitcode=%ERRORLEVEL%"
if not "%exitcode%"=="0" (pause) else (echo. & echo Analysis finished. Window closes in 8 seconds - press any key to close now... & timeout /t 8 >nul)
endlocal & exit /b %exitcode%
