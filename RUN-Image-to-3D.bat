@echo off
title Image → 3D (TripoSR)

REM Drag JPG/PNG files onto this .bat OR just double-click it.
REM It launches the PowerShell picker/runner and keeps the window open.

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" ^
  -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -NoExit ^
  -File "C:\ai3d\TripoSR\launch_picker.ps1" %*

REM The PowerShell script shows logs and pauses at the end.
