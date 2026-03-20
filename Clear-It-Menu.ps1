#Requires -Version 5.1

<#
.SYNOPSIS
Interactive menu for Clear-It cleanup operations.

.DESCRIPTION
Provides a user-friendly menu interface for running Clear-It
cleanup operations with clear explanations of each option.
#>

param(
    [switch]$NoAdminCheck
)

function Show-Banner {
    Clear-Host
    Write-Host @"

    ================================================
              Clear-It - Windows Cleanup Tool
    ================================================
               Windows 10 / 11 Compatible
    ================================================

"@ -ForegroundColor Cyan
}

function Show-Menu {
    Write-Host "    SELECT AN OPTION:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    [1] SAFE PREVIEW (Recommended First)" -ForegroundColor Green
    Write-Host "        Shows what would be cleaned WITHOUT deleting anything" -ForegroundColor Gray
    Write-Host ""
    Write-Host "    [2] Clean Temp Files Only" -ForegroundColor White
    Write-Host "        Removes temp folders, caches, logs (keeps user profiles)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "    [3] Remove Inactive Profiles" -ForegroundColor White
    Write-Host "        Deletes user profiles inactive X days" -ForegroundColor Gray
    Write-Host ""
    Write-Host "    [4] Full Cleanup" -ForegroundColor Yellow
    Write-Host "        Profiles (inactive X days) + All temp/cache files" -ForegroundColor Gray
    Write-Host ""
    Write-Host "    [5] Custom Cleanup" -ForegroundColor White
    Write-Host "        Set your own parameters" -ForegroundColor Gray
    Write-Host ""
    Write-Host "    [Q] Quit" -ForegroundColor Red
    Write-Host ""
    Write-Host "    ================================================" -ForegroundColor Cyan
}

function Test-IsAdmin {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Request-Elevation {
    if (-not (Test-IsAdmin)) {
        Write-Host ""
        Write-Host "    Administrator privileges required." -ForegroundColor Yellow
        Write-Host "    Requesting elevation..." -ForegroundColor Yellow
        Start-Sleep -Seconds 2

        $scriptPath = $PSCommandPath
        $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$scriptPath`"", "-NoAdminCheck")

        try {
            Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
        }
        catch {
            Write-Host "    ERROR: Failed to elevate. Please run as Administrator." -ForegroundColor Red
            Read-Host "    Press Enter to exit"
        }
        exit
    }
}

function Get-ScriptDirectory {
    if ($PSScriptRoot) { return $PSScriptRoot }
    return (Get-Location).Path
}

function Invoke-ClearIt {
    param(
        [string]$Mode,
        [int]$InactiveDays = 90,
        [int]$TempFileAgeDays = 0,
        [bool]$DryRun = $false,
        [string[]]$ExcludeUsers = @(),
        [switch]$SkipBrowserCache,
        [switch]$SkipWindowsUpdate
    )

    $scriptDir = Get-ScriptDirectory
    $mainScript = Join-Path $scriptDir "Clear-It.ps1"

    if (-not (Test-Path $mainScript)) {
        Write-Host "    ERROR: Clear-It.ps1 not found in: $scriptDir" -ForegroundColor Red
        Read-Host "    Press Enter to return to menu"
        return
    }

    Write-Host ""
    Write-Host " Starting Clear-It..." -ForegroundColor Cyan
    Write-Host " Mode: $Mode | DryRun: $DryRun | InactiveDays: $InactiveDays" -ForegroundColor Gray
    Start-Sleep -Seconds 1

    # Build splatting parameters for direct invocation (avoids Invoke-Expression issues with booleans)
    $clearItParams = @{
        Mode = $Mode
        InactiveDays = $InactiveDays
        TempFileAgeDays = $TempFileAgeDays
        DryRun = $DryRun
    }
    if ($ExcludeUsers.Count -gt 0) { $clearItParams['ExcludeUsers'] = $ExcludeUsers }
    if ($SkipBrowserCache) { $clearItParams['SkipBrowserCache'] = $true }
    if ($SkipWindowsUpdate) { $clearItParams['SkipWindowsUpdate'] = $true }

    # Execute Clear-It.ps1 directly with splatting
    & $mainScript @clearItParams

    Write-Host ""
    Read-Host "    Press Enter to return to menu"
}

function Show-CustomMenu {
    Show-Banner
    Write-Host "    CUSTOM CLEANUP OPTIONS" -ForegroundColor Yellow
    Write-Host "    ================================================" -ForegroundColor Cyan
    Write-Host ""

    # Mode selection
    Write-Host "    Select cleanup mode:" -ForegroundColor White
    Write-Host "    [1] Profiles only"
    Write-Host "    [2] Temp files only"
    Write-Host "    [3] Both"
    Write-Host ""
    $modeChoice = Read-Host "    Enter choice (1-3)"
    $selectedMode = switch ($modeChoice) {
        '1' { 'Profiles' }
        '2' { 'TempFiles' }
        default { 'All' }
    }

    # Inactive days
    $inactiveDays = Read-Host "    Days of inactivity before profile removal (default: 90)"
    if ([string]::IsNullOrWhiteSpace($inactiveDays)) { $inactiveDays = 90 }
    try { $inactiveDays = [int]$inactiveDays } catch { $inactiveDays = 90 }

    # Temp file age
    $tempAge = Read-Host "    Min age of temp files to delete in days (default: 0 = all)"
    if ([string]::IsNullOrWhiteSpace($tempAge)) { $tempAge = 0 }
    try { $tempAge = [int]$tempAge } catch { $tempAge = 0 }

    # Dry run
    Write-Host ""
    Write-Host "    IMPORTANT: Enable Dry Run (preview only)?" -ForegroundColor Yellow
    Write-Host "    [Y] Yes - Preview only (safe, recommended)"
    Write-Host "    [N] No - Actually delete files"
    $dryRunChoice = Read-Host "    Enter choice (Y/N)"
    $dryRun = ($dryRunChoice -ne 'N')

    # Skip options
    Write-Host ""
    $skipBrowsers = (Read-Host "    Skip browser caches? (Y/N, default: N)") -eq 'Y'
    $skipWU = (Read-Host "    Skip Windows Update cache? (Y/N, default: N)") -eq 'Y'

    # Exclude users
    Write-Host ""
    $excludeInput = Read-Host "    Users to exclude from profile deletion (comma-separated, or leave blank)"
    $excludeUsers = if ($excludeInput) { $excludeInput -split ',' | ForEach-Object { $_.Trim() } } else { @() }

    Invoke-ClearIt -Mode $selectedMode -InactiveDays $inactiveDays -TempFileAgeDays $tempAge `
                   -DryRun $dryRun -ExcludeUsers $excludeUsers `
                   -SkipBrowserCache:$skipBrowsers -SkipWindowsUpdate:$skipWU
}

function Get-InactiveDays {
    param([int]$DefaultDays = 90)
    
    Write-Host ""
    Write-Host "    Enter number of days for profile inactivity threshold:" -ForegroundColor White
    Write-Host "    (Profiles inactive longer than this will be removed)" -ForegroundColor Gray
    Write-Host ""
    $days = Read-Host "    Days (default: $DefaultDays)"
    
    if ([string]::IsNullOrWhiteSpace($days)) { 
        return $DefaultDays 
    }
    
    try { 
        $daysInt = [int]$days
        if ($daysInt -lt 1) { $daysInt = $DefaultDays }
        return $daysInt
    } 
    catch { 
        Write-Host "    Invalid number. Using default: $DefaultDays" -ForegroundColor Yellow
        Start-Sleep -Seconds 1
        return $DefaultDays 
    }
}

# Main execution
if (-not $NoAdminCheck) {
    Request-Elevation
}

# Main loop
while ($true) {
    Show-Banner
    Show-Menu

    $choice = Read-Host "    Enter your choice"

    switch ($choice.ToUpper()) {
        '1' {
            # Safe Preview
            Show-Banner
            Write-Host "    Running SAFE PREVIEW..." -ForegroundColor Green
            Start-Sleep -Seconds 1
            Invoke-ClearIt -Mode All -DryRun $true
        }
        '2' {
            # Temp Files Only
            Show-Banner
            Write-Host "    This will CLEAN TEMP FILES ONLY." -ForegroundColor Yellow
            Write-Host "    User profiles will NOT be touched." -ForegroundColor Gray
            Write-Host ""
            $confirm = Read-Host "    Continue? (Y/N)"
            if ($confirm -eq 'Y') {
                Invoke-ClearIt -Mode TempFiles -DryRun $false
            }
        }
        '3' {
            # Remove Inactive Profiles - Now asks for days!
            Show-Banner
            $inactiveDays = Get-InactiveDays -DefaultDays 90
            
            Show-Banner
            Write-Host "    WARNING: This will DELETE INACTIVE PROFILES!" -ForegroundColor Red
            Write-Host "    Profiles inactive ${inactiveDays}+ days will be removed." -ForegroundColor Yellow
            Write-Host "    Your current profile and system accounts are protected." -ForegroundColor Gray
            Write-Host ""
            $confirm = Read-Host "    Continue? (Y/N)"
            if ($confirm -eq 'Y') {
                Invoke-ClearIt -Mode Profiles -InactiveDays $inactiveDays -DryRun $false
            }
        }
        '4' {
            # Full Cleanup - Now asks for days!
            Show-Banner
            $inactiveDays = Get-InactiveDays -DefaultDays 90
            
            Show-Banner
            Write-Host "    WARNING: This will perform FULL CLEANUP!" -ForegroundColor Red
            Write-Host "    - Remove profiles inactive ${inactiveDays}+ days" -ForegroundColor Yellow
            Write-Host "    - Delete all temp/cache files" -ForegroundColor Yellow
            Write-Host "    Your current profile is protected." -ForegroundColor Gray
            Write-Host ""
            Write-Host "    RECOMMENDED: Run option [1] first to preview!" -ForegroundColor Cyan
            Write-Host ""
            $confirm = Read-Host "    Continue? (Y/N)"
            if ($confirm -eq 'Y') {
                Invoke-ClearIt -Mode All -InactiveDays $inactiveDays -DryRun $false
            }
        }
        '5' {
            # Custom
            Show-CustomMenu
        }
        'Q' {
            exit 0
        }
        default {
            Write-Host "    Invalid choice. Press Enter to try again." -ForegroundColor Red
            Read-Host
        }
    }
}
