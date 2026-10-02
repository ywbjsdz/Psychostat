@echo off
REM Psychostat offline self-check (pure ASCII, no BOM: safe in any code page)
REM Runs the bundled R against the numeric regression suite (88 assertions).
setlocal
cd /d "%~dp0"

set "RS="
REM Project-relative first: works wherever the zip was extracted (incl. one extra wrapper folder).
if exist "%~dp0runtime\R\bin\Rscript.exe" set "RS=%~dp0runtime\R\bin\Rscript.exe"
if not defined RS if exist "%~dp0Psychostat-R\bin\Rscript.exe" set "RS=%~dp0Psychostat-R\bin\Rscript.exe"
if not defined RS if exist "%~dp0..\runtime\R\bin\Rscript.exe" set "RS=%~dp0..\runtime\R\bin\Rscript.exe"
if not defined RS if exist "%~dp0..\Psychostat-R\bin\Rscript.exe" set "RS=%~dp0..\Psychostat-R\bin\Rscript.exe"
if not defined RS if exist "%~dp0..\..\Psychostat-R\bin\Rscript.exe" set "RS=%~dp0..\..\Psychostat-R\bin\Rscript.exe"
REM Legacy fallbacks (unchanged): D: drive bundle, then an R installation in PATH.
if not defined RS if exist "D:\Psychostat-R\bin\Rscript.exe" set "RS=D:\Psychostat-R\bin\Rscript.exe"
if not defined RS if exist "D:\R-4.5.2\bin\Rscript.exe" set "RS=D:\R-4.5.2\bin\Rscript.exe"
if not defined RS for /d %%D in ("D:\R-*") do if exist "%%D\bin\Rscript.exe" set "RS=%%D\bin\Rscript.exe"
if not defined RS for /f "delims=" %%P in ('where Rscript.exe 2^>nul') do set "RS=%%P"

if not defined RS (
  echo.
  echo [FAILED] Rscript.exe not found.
  echo   Expected .\runtime\R\bin\Rscript.exe or .\Psychostat-R\bin\Rscript.exe
  echo   ^(beside this file, or in the folder one / two levels up^),
  echo   or D:\Psychostat-R\bin\Rscript.exe, or an installed R in PATH.
  echo.
  pause
  exit /b 1
)

echo ============================================================
echo  Psychostat self-check
echo  Using R: %RS%
echo  This takes 1-3 minutes. Please do not close this window.
echo ============================================================
echo.

"%RS%" --vanilla "%~dp0tests\test_numeric.R"
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
  echo ============================================================
  echo  RESULT: ALL NUMERIC TESTS PASSED
  echo  The tool and its bundled R are working correctly.
  echo ============================================================
) else (
  echo ============================================================
  echo  RESULT: TESTS FAILED  ^(exit code %RC%^)
  echo  Please copy this window's text and send it back.
  echo ============================================================
)
echo.
pause
exit /b %RC%
