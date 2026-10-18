@echo off
rem Chay install.ps1 bang PowerShell, khong can doi Execution Policy cua may.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
echo.
pause
