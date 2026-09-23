@echo off
setlocal
cd /d "%~dp0"
title Psychostat - Clean up installed environment
echo.
echo ================================================================
echo   Psychostat : clean up what this tool installed on your PC
echo ================================================================
echo   * A preview is shown first. Nothing is deleted until you type Y.
echo   * Only removes Psychostat's OWN folders (its R package library,
echo     its Python dependencies, its temp folder) and the record file.
echo   * Your existing R / Python, your shared libraries, your results
echo     (outputs) and your data (data) are never deleted.
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\uninstall_psychostat.ps1" %*
set "exitcode=%ERRORLEVEL%"
echo.
if not "%exitcode%"=="0" (
  echo Some items could not be removed - please read the messages above.
) else (
  echo Finished.
)
echo Press any key to close this window...
pause >nul
endlocal & exit /b %exitcode%
