@echo off
rem PCL CE Download Bridge - native messaging host launcher
rem Chromium requires 'path' in the native messaging manifest to be an executable.
rem A .ps1 cannot be used there, so this .cmd forwards to Windows PowerShell.
setlocal
set "PS1=%~dp0native-host.ps1"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%PS1%"
exit /b %ERRORLEVEL%
