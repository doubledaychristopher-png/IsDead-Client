@echo off
rem Publishes the files in .\files to GitHub for every player's launcher.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish.ps1" %*
pause
