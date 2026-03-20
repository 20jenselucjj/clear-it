@echo off
:: Safe preview mode - shows what would be cleaned without deleting anything
:: This is the recommended first step before any actual cleanup

title Clear-It - Preview Mode
cls
echo ============================================
echo Clear-It - Preview Mode (Safe)
echo ============================================
echo.
echo This will SHOW what would be cleaned WITHOUT
echo actually deleting anything.
echo.
echo Review the output carefully before running
echo the actual cleanup scripts.
echo.
echo Press any key to continue...
pause >nul

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Clear-It.ps1" -Mode All -DryRun:$true

echo.
echo ============================================
echo Preview complete. Review the output above.
echo ============================================
echo.
echo To actually clean, use one of these scripts:
echo   - Clean-TempFiles.bat
echo   - Clean-Profiles-90Days.bat
echo   - Full-Cleanup.bat
echo.
pause
