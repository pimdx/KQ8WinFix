@echo off
setlocal
cd /d "%~dp0"
echo KQ8 Win11 Fix Setup
echo If the game is under Program Files / GOG, right-click this file and
echo choose "Run as administrator".
echo.
powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0tools\Install-Kq8Hd-Gui.ps1"
if errorlevel 1 (
  echo.
  echo Setup failed. Try Run as administrator, or allow the UAC prompt.
  pause
  exit /b 1
)
exit /b 0
