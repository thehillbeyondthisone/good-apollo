@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run-cabin.ps1" -XR %*
if errorlevel 1 pause
