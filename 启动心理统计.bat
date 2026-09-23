@echo off
setlocal
cd /d "%~dp0"
title Psychostat Stats
echo.
echo Starting Psychostat Statistics (SPSS-aligned teaching modules)...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_stats_analysis.ps1"
set "exitcode=%ERRORLEVEL%"
if not "%exitcode%"=="0" (pause) else (echo. & echo Analysis finished. Window closes in 8 seconds - press any key to close now... & timeout /t 8 >nul)
endlocal & exit /b %exitcode%
