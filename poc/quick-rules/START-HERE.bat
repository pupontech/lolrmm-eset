@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0START-HERE.ps1" %*
set "rc=%errorlevel%"
if /I "%~1"=="-ValidateOnly" goto done
pause
:done
exit /b %rc%
