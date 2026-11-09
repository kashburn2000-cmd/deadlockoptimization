' Double-click launcher for brightness.ps1 with no console window flash.
' Make a shortcut to this file and pin it to the taskbar or Start if you want it one click away.
Dim shell, here
Set shell = CreateObject("WScript.Shell")
here = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))
shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File """ & here & "brightness.ps1""", 0, False
