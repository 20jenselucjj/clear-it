@echo off
:: Full cleanup with custom inactivity days

title Clear-It - Full Cleanup (Custom Days)
cls
echo ============================================
echo Clear-It - Full Cleanup
echo ============================================
echo.
echo WARNING: This will perform a COMPLETE cleanup:
echo.
echo 1. REMOVE profiles inactive for specified days
echo 2. DELETE temp files and caches
echo.
echo Protected:
echo   - Your current profile
echo   - System accounts
echo   - Service accounts
echo.

set /p DAYS="Enter number of days for profile inactivity (e.g., 30, 60, 90, 180): "

if "%DAYS%"=="" set DAYS=90

echo.
echo Profiles inactive for %DAYS%+ days will be removed.
echo All temp/cache files will be deleted.
echo.
echo Press any key to continue...
pause >nul

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Clear-It.ps1" -Mode All -InactiveDays %DAYS% -DryRun:$false

echo.
echo ============================================
echo Full cleanup complete!
echo ============================================
pause
