@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%vpn_tester.ps1"

echo Starting VPN Tester...
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"

endlocal