@echo off
:: Remove user profiles with custom inactivity days

title Clear-It - Remove Inactive Profiles (Custom Days)
cls
echo ============================================
echo Clear-It - Remove Inactive Profiles
echo ============================================
echo.
echo WARNING: This will DELETE user profiles that
echo have not been used for the specified number of days.
echo.
echo The following are ALWAYS protected:
echo   - Your current profile
echo   - System accounts (Administrator, Default, Guest)
echo   - Service accounts
echo.
echo RECOMMENDED: Run Preview-Cleanup.bat first!
echo.

set /p DAYS="Enter number of days of inactivity (e.g., 30, 60, 90, 180): "

if "%DAYS%"=="" set DAYS=90

echo.
echo Profiles inactive for %DAYS%+ days will be removed.
echo.
echo Press any key to continue...
pause >nul

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Clear-It.ps1" -Mode Profiles -InactiveDays %DAYS% -DryRun:$false

echo.
echo ============================================
echo Profile cleanup complete!
echo ============================================
pause
