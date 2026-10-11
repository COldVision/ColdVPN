@echo off
rem Installs the Android build tools if needed and builds dist\ColdVPN-x.y.z.apk.
rem Double-click this file and approve the administrator prompt.
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tool\setup_android.ps1" %*
echo.
pause
