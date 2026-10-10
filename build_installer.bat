@echo off
rem Builds the app and packs it into a Windows installer (dist\ColdVPN-Setup-x.y.z.exe).
rem Double-click this file and approve the administrator prompt.
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tool\build_installer.ps1" %*
echo.
pause
