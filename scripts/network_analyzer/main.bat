@echo off
setlocal

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0main.ps1"

echo.
pause
endlocal
