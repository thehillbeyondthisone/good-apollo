@echo off
title Aquarius - LM-7
pushd "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run-cabin.ps1" %*
if errorlevel 1 (
  echo.
  echo Aquarius could not start. Review the message above and docs\INTERACTION.md.
  pause
)
popd
