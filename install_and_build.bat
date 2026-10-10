@echo off
rem Installs Git, Visual Studio Build Tools and Flutter, then builds the app.
rem Double-click this file and approve the administrator prompt.
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tool\install_tools.ps1" %*
echo.
pause
