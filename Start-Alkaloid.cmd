@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-AutoInstaller.ps1" -ProfilePath "%~dp0profiles\alkaloid.yaml"
pause
