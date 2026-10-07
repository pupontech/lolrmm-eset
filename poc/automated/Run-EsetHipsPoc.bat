@echo off
setlocal EnableExtensions DisableDelayedExpansion
pushd "%~dp0"
if errorlevel 1 exit /b 1
if not exist "Launch-Kit.ps1" goto :missing
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Launch-Kit.ps1" %*
set "RC=%ERRORLEVEL%"
goto :finish
:missing
echo FAILED: Launch-Kit.ps1 is missing. Extract the complete ZIP first.
set "RC=1"
:finish
echo.
echo Exit code: %RC%
echo 0 = dry-run complete; 1 = failure; 2 = observations complete, Phase 1 unverified.
pause
popd
exit /b %RC%
