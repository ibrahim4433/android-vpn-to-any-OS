@echo off
echo Starting VPN Tester...
echo Requesting Administrator permissions...

:: This command instantly bypasses execution policies and launches the script as Admin
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"D:\test\vpn_tester.ps1\"' -Verb RunAs"

exit