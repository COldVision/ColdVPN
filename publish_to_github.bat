@echo off
rem Prepares the project as a git repository and offers to push it to GitHub.
rem Double-click this file. It asks before anything is published.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tool\publish_github.ps1" %*
echo.
pause
