@echo off
rem IsDead WoW Launcher: updates the IsDead client files, then starts the game.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0IsDeadLauncher.ps1" %*
if errorlevel 1 pause
