@echo off
REM Double-click this file to run the Roblox + Claude Code setup.
REM It uses Windows PowerShell (built into Windows) and allows this one script to run
REM even if PowerShell's default policy blocks scripts.
REM
REM Options can be passed on the command line, for example:
REM   Run-Setup.cmd -DryRun
REM   Run-Setup.cmd -ProjectName obby-game -Skip Node
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup-RobloxDev.ps1" %*
set "RC=%ERRORLEVEL%"
echo.
echo Setup script finished with exit code %RC% (0 means everything succeeded).
echo Press any key to close this window.
pause >nul
endlocal & exit /b %RC%
