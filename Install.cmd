@echo off
rem Opens the Claude Usage Widget setup window. No admin rights needed.
start "" powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0setup.ps1"
