@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Launch-Kq8.ps1" %*
if errorlevel 1 (
  echo Launcher failed.
  pause
)
exit /b %ERRORLEVEL%
