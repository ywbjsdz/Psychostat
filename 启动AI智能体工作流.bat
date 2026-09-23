@echo off
setlocal
cd /d "%~dp0"
title Psychostat AI Workflow
echo.
echo Opening the AI-assistant handover note (no API key needed)...
for /f "delims=" %%i in ('dir /b /a-d "%~dp0\*.md" 2^>nul ^| findstr /b /i "AI"') do (
  start "" notepad "%~dp0%%i"
  goto :opened
)
:opened
echo Hand the data file and this note to your AI assistant; follow the prompt inside.
pause
endlocal
