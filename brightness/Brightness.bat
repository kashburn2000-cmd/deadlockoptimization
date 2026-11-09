@echo off
rem Double-click launcher for brightness.ps1. A console window flashes for a moment;
rem use Brightness.vbs instead if that bothers you.
rem   Brightness.bat            opens the two-button window
rem   Brightness.bat night      sets Night and exits
rem   Brightness.bat normal     sets Normal and exits
if "%~1"=="" (
    start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0brightness.ps1"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0brightness.ps1" -Set %~1
)
