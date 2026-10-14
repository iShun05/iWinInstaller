@echo off
if exist "%~dp0iWinInstaller.exe" (start "" "%~dp0iWinInstaller.exe" & exit /b)
start "" powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0launch.ps1"
