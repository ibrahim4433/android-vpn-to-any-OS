@echo off
setlocal

:: Request Administrator privileges via PowerShell
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /B
)

pushd "%CD%"
CD /D "%~dp0"

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%vpn_tester.ps1"

echo Starting VPN Tester...
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"

endlocal