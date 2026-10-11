@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Launch-Kq8.ps1" -EmergencySkipUi
if errorlevel 1 (
  set __COMPAT_LAYER=!
  start "" "%~dp0Mask.exe"
)
exit /b 0
