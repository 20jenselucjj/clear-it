@echo off
:: Clean temporary files only (does NOT remove user profiles)

title Clear-It - Clean Temp Files Only
cls
echo ============================================
echo Clear-It - Clean Temp Files Only
echo ============================================
echo.
echo This will delete temporary files and caches
echo but WILL NOT remove any user profiles.
echo.
echo Files to be cleaned:
echo   - User temp folders
echo   - Browser caches (Chrome, Edge, Firefox, Brave)
echo   - Windows Update cache
echo   - Crash dumps
echo   - Prefetch files
echo   - Memory dumps
echo   - System logs
echo   - Recycle Bin
echo.
echo Press any key to start cleanup...
pause >nul

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Clear-It.ps1" -Mode TempFiles -DryRun:$false

echo.
echo ============================================
echo Temp file cleanup complete!
echo ============================================
pause
