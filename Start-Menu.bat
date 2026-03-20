@echo off
:: Launch the Clear-It interactive menu
:: This is the easiest way to use Clear-It

title Clear-It Menu Launcher
cls
echo ============================================
echo Clear-It - Windows Cleanup Tool
echo ============================================
echo.
echo Launching interactive menu...
echo.
echo This menu will guide you through:
echo   - Safe preview mode (see what would be cleaned)
echo   - Temp file cleanup
echo   - Profile cleanup (inactive accounts)
echo   - Full cleanup
echo   - Custom options
echo.
echo Administrator privileges may be requested.
echo.
pause

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Clear-It-Menu.ps1"
