@echo off
rem Runs brightness.ps1 with the console visible and kept open, so you can read any error.
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -NoExit -File "%~dp0brightness.ps1"
