#Requires -Version 5.1

<#
.SYNOPSIS
    Clear-It: Comprehensive Windows 10/11 cleanup script for user profiles and temp/cache data.

.DESCRIPTION
    This script provides two major cleanup capabilities:
      1. PROFILE CLEANUP  - Remove inactive user profiles based on days since last logon
      2. TEMP/CACHE CLEANUP - Clear temporary files, browser caches, Windows Update cache, crash dumps, etc.

    Safety features:
      - DryRun/Simulation mode (default) shows what WOULD be deleted without touching anything
      - Admin privilege detection and auto-elevation
      - System/built-in accounts are always excluded from profile deletion
      - Currently logged-in profiles are never deleted
      - Locked files are silently skipped
      - Detailed logging with optional transcript

.PARAMETER Mode
    What to clean. Valid values:
      Profiles  - Only remove inactive user profiles
      TempFiles - Only clean temp/cache files
      All       - Both profiles AND temp files (default)

.PARAMETER InactiveDays
    Number of days of inactivity before a profile is eligible for removal. Default: 90.

.PARAMETER TempFileAgeDays
    Only delete temp files older than this many days. Default: 0 (all temp files).

.PARAMETER DryRun
    Simulation mode. Shows what would be cleaned without deleting anything. DEFAULT IS TRUE.
    You must explicitly pass -DryRun:$false to actually delete.

.PARAMETER ExcludeUsers
    Array of usernames to always exclude from profile deletion (in addition to built-in accounts).

.PARAMETER SkipBrowserCache
    Skip browser cache cleanup (Chrome, Edge, Firefox, Brave).

.PARAMETER SkipWindowsUpdate
    Skip Windows Update cache cleanup (avoids stopping wuauserv/BITS services).

.PARAMETER LogPath
    Path to write a transcript log. If not specified, logs to Clear-It_<timestamp>.log in script directory.

.PARAMETER NoLog
    Disable transcript logging entirely.

.EXAMPLE
    .\Clear-It.ps1
    # DryRun mode (default) - shows what would be cleaned, deletes nothing

.EXAMPLE
    .\Clear-It.ps1 -Mode Profiles -InactiveDays 60 -DryRun:$false
    # Actually delete user profiles inactive for 60+ days

.EXAMPLE
    .\Clear-It.ps1 -Mode TempFiles -TempFileAgeDays 7 -DryRun:$false
    # Delete temp files older than 7 days

.EXAMPLE
    .\Clear-It.ps1 -Mode All -InactiveDays 90 -DryRun:$false -ExcludeUsers @('svc_backup','admin.jones')
    # Full cleanup, excluding specific users from profile deletion

.EXAMPLE
    .\Clear-It.ps1 -Mode TempFiles -SkipBrowserCache -SkipWindowsUpdate
    # DryRun preview of temp cleanup, skipping browsers and WU cache

.NOTES
    Author:  Clear-It Project
    Version: 1.0.0
    Date:    2026-03-20
    License: MIT
    Tested:  Windows 10 22H2, Windows 11 23H2/24H2
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateSet('Profiles', 'TempFiles', 'All')]
    [string]$Mode = 'All',

    [Parameter()]
    [ValidateRange(1, 3650)]
    [int]$InactiveDays = 90,

    [Parameter()]
    [ValidateRange(0, 3650)]
    [int]$TempFileAgeDays = 0,

    [Parameter()]
    [bool]$DryRun = $true,

    [Parameter()]
    [string[]]$ExcludeUsers = @(),

    [Parameter()]
    [switch]$SkipBrowserCache,

    [Parameter()]
    [switch]$SkipWindowsUpdate,

    [Parameter()]
    [string]$LogPath,

    [Parameter()]
    [switch]$NoLog
)

# ============================================================================
# CONFIGURATION
# ============================================================================

$Script:Version = '1.0.0'
$Script:StartTime = Get-Date
$Script:TotalFilesRemoved = 0
$Script:TotalFilesFailed = 0
$Script:TotalBytesFreed = 0
$Script:ProfilesRemoved = 0
$Script:ProfilesFailed = 0

# Built-in / system accounts to ALWAYS exclude from profile deletion
$Script:BuiltInAccounts = @(
    'Administrator'
    'Default'
    'DefaultAccount'
    'Guest'
    'Public'
    'WDAGUtilityAccount'
    'defaultuser0'
    'All Users'
)

# System SIDs to ALWAYS exclude
$Script:SystemSIDs = @(
    'S-1-5-18'   # SYSTEM / LocalSystem
    'S-1-5-19'   # NT AUTHORITY\LocalService
    'S-1-5-20'   # NT AUTHORITY\NetworkService
)

# ============================================================================
#  HELPER FUNCTIONS
# ============================================================================

function Write-Banner {
    $banner = @"

  =============================================
    Clear-It v$Script:Version - Windows Cleanup
    $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  =============================================
  Mode:           $Mode
  DryRun:         $DryRun
  InactiveDays:   $InactiveDays
  TempFileAge:    $TempFileAgeDays day(s)
  Computer:       $env:COMPUTERNAME
  User:           $env:USERNAME
  =============================================

"@
    Write-Host $banner -ForegroundColor Cyan
}

function Write-Section {
    param([string]$Title)
    Write-Host "`n--- $Title ---" -ForegroundColor Yellow
}

function Write-Action {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'DryRun')]
        [string]$Level = 'Info'
    )
    $prefix = switch ($Level) {
        'Info'    { '[INFO]   '; }
        'Success' { '[OK]     '; }
        'Warning' { '[WARN]   '; }
        'Error'   { '[ERROR]  '; }
        'DryRun'  { '[DRYRUN] '; }
    }
    $color = switch ($Level) {
        'Info'    { 'White' }
        'Success' { 'Green' }
        'Warning' { 'DarkYellow' }
        'Error'   { 'Red' }
        'DryRun'  { 'Magenta' }
    }
    Write-Host "$prefix$Message" -ForegroundColor $color
}

function Test-IsAdmin {
    <#
    .SYNOPSIS
        Check if the current PowerShell session has administrator privileges.
        Modern replacement for VBScript elevation detection.
    #>
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Request-Elevation {
    <#
    .SYNOPSIS
        Relaunch the current script with elevated (admin) privileges via UAC prompt.
    #>
    if (-not (Test-IsAdmin)) {
        Write-Action "Script requires administrator privileges. Requesting elevation..." -Level Warning
        $scriptPath = $MyInvocation.ScriptName
        if (-not $scriptPath) { $scriptPath = $PSCommandPath }

        # Rebuild argument list
        $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$scriptPath`"")
    # Pass through key parameters
    $argList += "-Mode", $Mode
    $argList += "-InactiveDays", $InactiveDays
    $argList += "-TempFileAgeDays", $TempFileAgeDays
    $argList += "-DryRun:`$$DryRun"
        if ($ExcludeUsers.Count -gt 0) {
            $argList += "-ExcludeUsers", ($ExcludeUsers -join ',')
        }
        if ($SkipBrowserCache) { $argList += "-SkipBrowserCache" }
        if ($SkipWindowsUpdate) { $argList += "-SkipWindowsUpdate" }
        if ($NoLog) { $argList += "-NoLog" }
        if ($LogPath) { $argList += "-LogPath", "`"$LogPath`"" }

        try {
            Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
        }
        catch {
            Write-Action "Failed to elevate: $_" -Level Error
            Write-Action "Please right-click PowerShell and select 'Run as Administrator'." -Level Error
        }
        exit
    }
}

function Get-FreeSpaceGB {
    [math]::Round((Get-PSDrive C).Free / 1GB, 2)
}

function Remove-SafeItems {
    <#
    .SYNOPSIS
        Safely remove files from a path with age filtering, locked-file handling, and dry-run support.
    .PARAMETER Path
        The directory path to clean.
    .PARAMETER Filter
        Optional file filter (e.g., "*.pf", "*.log"). Default: all files.
    .PARAMETER Recurse
        Recurse into subdirectories.
    .PARAMETER Description
        Human-readable description for logging.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$Filter = '*',

        [switch]$Recurse,

        [string]$Description = $Path
    )

    if (-not (Test-Path $Path)) {
        Write-Action "Skipped (not found): $Description" -Level Info
        return
    }

    $cutoff = (Get-Date).AddDays(-$TempFileAgeDays)
    $removed = 0
    $failed = 0
    $bytesFreed = 0

    $items = if ($Recurse) {
        Get-ChildItem -Path $Path -Filter $Filter -Recurse -Force -ErrorAction SilentlyContinue
    }
    else {
        Get-ChildItem -Path $Path -Filter $Filter -Force -ErrorAction SilentlyContinue
    }

    $filesToRemove = $items | Where-Object {
        -not $_.PSIsContainer -and $_.LastWriteTime -lt $cutoff
    }

    foreach ($file in $filesToRemove) {
        if ($DryRun) {
            $sizeMB = [math]::Round($file.Length / 1MB, 2)
            Write-Action "Would remove: $($file.FullName) ($sizeMB MB)" -Level DryRun
            $bytesFreed += $file.Length
            $removed++
        }
        else {
            try {
                $fileSize = $file.Length
                Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                $bytesFreed += $fileSize
                $removed++
            }
            catch {
                # File is locked by another process - skip silently
                $failed++
            }
        }
    }

    # Also try to remove empty directories if recursing
    if ($Recurse -and -not $DryRun) {
        Get-ChildItem -Path $Path -Directory -Recurse -Force -ErrorAction SilentlyContinue |
            Sort-Object { $_.FullName.Length } -Descending |
            ForEach-Object {
                $dirItems = Get-ChildItem -Path $_.FullName -Force -ErrorAction SilentlyContinue
                if (-not $dirItems) {
                    try { Remove-Item $_.FullName -Force -ErrorAction Stop } catch { }
                }
            }
    }

    $sizeMBTotal = [math]::Round($bytesFreed / 1MB, 2)
    $actionWord = if ($DryRun) { "Would clean" } else { "Cleaned" }
    Write-Action "$actionWord $Description : $removed files ($sizeMBTotal MB), $failed skipped" -Level $(if ($removed -gt 0) { 'Success' } else { 'Info' })

    $Script:TotalFilesRemoved += $removed
    $Script:TotalFilesFailed += $failed
    $Script:TotalBytesFreed += $bytesFreed
}

function Remove-SafeItemsAllUsers {
    <#
    .SYNOPSIS
        Run Remove-SafeItems across all user profile directories.
    .PARAMETER SubPath
        The subpath under C:\Users\<username>\ to clean.
    .PARAMETER Filter
        Optional file filter.
    .PARAMETER Description
        Human-readable description.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SubPath,

        [string]$Filter = '*',

        [string]$Description
    )

    $userDirs = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '^(Public|Default|Default User|All Users)$' }

    foreach ($userDir in $userDirs) {
        $fullPath = Join-Path $userDir.FullName $SubPath
        $desc = if ($Description) { "$Description ($($userDir.Name))" } else { $fullPath }
        Remove-SafeItems -Path $fullPath -Filter $Filter -Recurse -Description $desc
    }
}

# ============================================================================
#  PROFILE CLEANUP
# ============================================================================

function Invoke-ProfileCleanup {
    <#
    .SYNOPSIS
        Remove user profiles that haven't been used in $InactiveDays days.
        Uses CIM (Win32_UserProfile) for safe, registry-aware profile deletion.
    #>

    Write-Section "USER PROFILE CLEANUP (Inactive > $InactiveDays days)"

    $currentUser = $env:USERNAME
    $cutoffDate = (Get-Date).AddDays(-$InactiveDays)

    # Merge built-in exclusions with user-specified exclusions
    $allExclusions = $Script:BuiltInAccounts + $ExcludeUsers + @($currentUser)
    $allExclusions = $allExclusions | Sort-Object -Unique

    Write-Action "Current user (always excluded): $currentUser" -Level Info
    Write-Action "Additional exclusions: $($ExcludeUsers -join ', ')" -Level Info
    Write-Action "Cutoff date: $($cutoffDate.ToString('yyyy-MM-dd HH:mm:ss'))" -Level Info

    # Get all user profiles via CIM
    try {
        $allProfiles = Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop
    }
    catch {
        Write-Action "Failed to enumerate user profiles: $_" -Level Error
        return
    }

    # Display all detected profiles first
    Write-Host ""
    Write-Action "Detected profiles:" -Level Info

    $allProfiles | Where-Object { $_.Special -eq $false } | ForEach-Object {
        $userName = Split-Path $_.LocalPath -Leaf
        $lastUsed = if ($_.LastUseTime) { $_.LastUseTime.ToString('yyyy-MM-dd HH:mm:ss') } else { 'Never' }
        $status = @()
        if ($_.Loaded) { $status += 'LOADED' }
        if ($userName -in $allExclusions) { $status += 'EXCLUDED' }
        if ($_.SID -in $Script:SystemSIDs) { $status += 'SYSTEM-SID' }
        if ($_.LastUseTime -and $_.LastUseTime -lt $cutoffDate) { $status += 'INACTIVE' }
        $statusStr = if ($status) { " [$($status -join ', ')]" } else { '' }

        Write-Host "    $userName - Last used: $lastUsed$statusStr" -ForegroundColor Gray
    }

    # Filter to profiles eligible for deletion
    $profilesToDelete = $allProfiles | Where-Object {
        $userName = Split-Path $_.LocalPath -Leaf

        # ALL of these must be true for deletion
        ($_.Special -eq $false) -and                          # Not a system profile
        ($_.Loaded -eq $false) -and                           # Not currently loaded/logged in
        ($_.SID -notin $Script:SystemSIDs) -and               # Not a system SID
        ($userName -notin $allExclusions) -and                 # Not in exclusion list
        ($_.LastUseTime) -and                                  # Has a last-use timestamp
        ($_.LastUseTime -lt $cutoffDate)                       # Older than cutoff
    }

    if (-not $profilesToDelete -or $profilesToDelete.Count -eq 0) {
        Write-Host ""
        Write-Action "No profiles found eligible for removal." -Level Success
        return
    }

    Write-Host ""
    Write-Action "Profiles eligible for removal: $($profilesToDelete.Count)" -Level Warning

    # Show details of what will be removed
    $profileTable = foreach ($profile in $profilesToDelete) {
        $userName = Split-Path $profile.LocalPath -Leaf
        $daysUnused = [math]::Round(((Get-Date) - $profile.LastUseTime).TotalDays, 0)
        $profileSize = 0
        if (Test-Path $profile.LocalPath) {
            $profileSize = (Get-ChildItem $profile.LocalPath -Recurse -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        }
        $sizeMB = [math]::Round($profileSize / 1MB, 2)

        [PSCustomObject]@{
            Username   = $userName
            LastUsed   = $profile.LastUseTime.ToString('yyyy-MM-dd')
            DaysUnused = $daysUnused
            SizeMB     = $sizeMB
            Path       = $profile.LocalPath
            SID        = $profile.SID
        }
    }

    $profileTable | Format-Table Username, LastUsed, DaysUnused, SizeMB, Path -AutoSize | Out-String | Write-Host

    # Execute deletion
    foreach ($profile in $profilesToDelete) {
        $userName = Split-Path $profile.LocalPath -Leaf

        if ($DryRun) {
            Write-Action "Would remove profile: $userName ($($profile.LocalPath))" -Level DryRun
            $Script:ProfilesRemoved++
        }
        else {
            try {
                Write-Action "Removing profile: $userName ..." -Level Warning
                # Remove-CimInstance handles both the folder AND the registry entry
                Remove-CimInstance -InputObject $profile -ErrorAction Stop
                Write-Action "Successfully removed: $userName" -Level Success
                $Script:ProfilesRemoved++
            }
            catch {
                Write-Action "Failed to remove $userName : $_" -Level Error
                $Script:ProfilesFailed++

                # Fallback: try manual removal if CIM fails
                Write-Action "Attempting manual folder removal for $userName ..." -Level Warning
                try {
                    if (Test-Path $profile.LocalPath) {
                        Remove-Item -Path $profile.LocalPath -Recurse -Force -ErrorAction Stop
                        Write-Action "Manually removed folder: $($profile.LocalPath)" -Level Success
                        Write-Action "NOTE: Registry entry may remain. Run 'SystemPropertiesAdvanced.exe' > User Profiles to verify." -Level Warning
                    }
                }
                catch {
                    Write-Action "Manual removal also failed for $userName : $_" -Level Error
                }
            }
        }
    }
}

# ============================================================================
#  TEMP / CACHE CLEANUP
# ============================================================================

function Invoke-TempFileCleanup {
    <#
    .SYNOPSIS
        Clean temporary files, caches, crash dumps, and logs across user and system locations.
    #>

    Write-Section "TEMPORARY FILE CLEANUP (Files older than $TempFileAgeDays day(s))"

    # ------------------------------------------------------------------
    # 1. USER-SPECIFIC LOCATIONS (all user profiles)
    # ------------------------------------------------------------------

    Write-Section "User Temp Folders"
    Remove-SafeItemsAllUsers -SubPath "AppData\Local\Temp" -Description "User Temp"

    Write-Section "User Crash Dumps"
    Remove-SafeItemsAllUsers -SubPath "AppData\Local\CrashDumps" -Description "Crash Dumps"

    Write-Section "IE / Edge Legacy Cache (INetCache)"
    Remove-SafeItemsAllUsers -SubPath "AppData\Local\Microsoft\Windows\INetCache" -Description "INetCache"

    Write-Section "IE / Edge Legacy Cookies (INetCookies)"
    Remove-SafeItemsAllUsers -SubPath "AppData\Local\Microsoft\Windows\INetCookies" -Description "INetCookies"

    Write-Section "Windows Error Reporting (WER)"
    Remove-SafeItemsAllUsers -SubPath "AppData\Local\Microsoft\Windows\WER\ReportQueue" -Description "WER ReportQueue"
    Remove-SafeItemsAllUsers -SubPath "AppData\Local\Microsoft\Windows\WER\Temp" -Description "WER Temp"

    Write-Section "Temporary Internet Files (Legacy)"
    Remove-SafeItemsAllUsers -SubPath "AppData\Local\Microsoft\Windows\Temporary Internet Files" -Description "Temporary Internet Files"

    Write-Section "Recent Documents Shortcuts"
    Remove-SafeItemsAllUsers -SubPath "AppData\Roaming\Microsoft\Windows\Recent" -Description "Recent Shortcuts"

    Write-Section "Thumbnail Cache"
    Remove-SafeItemsAllUsers -SubPath "AppData\Local\Microsoft\Windows\Explorer" -Filter "thumbcache_*.db" -Description "Thumbnail Cache"

    # ------------------------------------------------------------------
    # 2. BROWSER CACHES (all user profiles)
    # ------------------------------------------------------------------

    if (-not $SkipBrowserCache) {
        Write-Section "Browser Caches"

        $userDirs = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch '^(Public|Default|Default User|All Users)$' }

        foreach ($userDir in $userDirs) {
            $userName = $userDir.Name

            # Google Chrome
            $chromeBase = Join-Path $userDir.FullName "AppData\Local\Google\Chrome\User Data"
            if (Test-Path $chromeBase) {
                $chromeProfiles = @("Default") + @(
                    Get-ChildItem $chromeBase -Directory -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -match '^Profile \d+$' } |
                        Select-Object -ExpandProperty Name
                )
                foreach ($cp in $chromeProfiles) {
                    Remove-SafeItems -Path (Join-Path $chromeBase "$cp\Cache\Cache_Data") -Recurse -Description "Chrome Cache ($userName\$cp)"
                    Remove-SafeItems -Path (Join-Path $chromeBase "$cp\Code Cache") -Recurse -Description "Chrome Code Cache ($userName\$cp)"
                    Remove-SafeItems -Path (Join-Path $chromeBase "$cp\Service Worker\CacheStorage") -Recurse -Description "Chrome SW Cache ($userName\$cp)"
                }
            }

            # Microsoft Edge (Chromium)
            $edgeBase = Join-Path $userDir.FullName "AppData\Local\Microsoft\Edge\User Data"
            if (Test-Path $edgeBase) {
                $edgeProfiles = @("Default") + @(
                    Get-ChildItem $edgeBase -Directory -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -match '^Profile \d+$' } |
                        Select-Object -ExpandProperty Name
                )
                foreach ($ep in $edgeProfiles) {
                    Remove-SafeItems -Path (Join-Path $edgeBase "$ep\Cache\Cache_Data") -Recurse -Description "Edge Cache ($userName\$ep)"
                    Remove-SafeItems -Path (Join-Path $edgeBase "$ep\Code Cache") -Recurse -Description "Edge Code Cache ($userName\$ep)"
                }
            }

            # Mozilla Firefox
            $firefoxProfiles = Join-Path $userDir.FullName "AppData\Local\Mozilla\Firefox\Profiles"
            if (Test-Path $firefoxProfiles) {
                Get-ChildItem $firefoxProfiles -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                    Remove-SafeItems -Path (Join-Path $_.FullName "cache2") -Recurse -Description "Firefox Cache ($userName\$($_.Name))"
                }
            }

            # Brave Browser
            $braveBase = Join-Path $userDir.FullName "AppData\Local\BraveSoftware\Brave-Browser\User Data"
            if (Test-Path $braveBase) {
                $braveProfiles = @("Default") + @(
                    Get-ChildItem $braveBase -Directory -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -match '^Profile \d+$' } |
                        Select-Object -ExpandProperty Name
                )
                foreach ($bp in $braveProfiles) {
                    Remove-SafeItems -Path (Join-Path $braveBase "$bp\Cache\Cache_Data") -Recurse -Description "Brave Cache ($userName\$bp)"
                }
            }
        }
    }
    else {
        Write-Action "Browser cache cleanup skipped (-SkipBrowserCache)" -Level Info
    }

    # ------------------------------------------------------------------
    # 3. SYSTEM-WIDE LOCATIONS (require admin)
    # ------------------------------------------------------------------

    Write-Section "System Temp (C:\Windows\Temp)"
    Remove-SafeItems -Path "$env:WINDIR\Temp" -Recurse -Description "Windows\Temp"

    Write-Section "Prefetch Files"
    Remove-SafeItems -Path "$env:WINDIR\Prefetch" -Filter "*.pf" -Description "Prefetch"

    Write-Section "Memory Dump Files"
    # Full memory dump
    $memDmp = Join-Path $env:WINDIR "MEMORY.DMP"
    if (Test-Path $memDmp) {
        $dmpSize = [math]::Round((Get-Item $memDmp).Length / 1MB, 2)
        if ($DryRun) {
            Write-Action "Would remove: MEMORY.DMP ($dmpSize MB)" -Level DryRun
        }
        else {
            try {
                Remove-Item $memDmp -Force -ErrorAction Stop
                Write-Action "Removed MEMORY.DMP ($dmpSize MB)" -Level Success
                $Script:TotalBytesFreed += (Get-Item $memDmp -ErrorAction SilentlyContinue).Length
            }
            catch {
                Write-Action "Could not remove MEMORY.DMP (may be locked): $_" -Level Warning
            }
        }
    }
    # Minidumps
    Remove-SafeItems -Path "$env:WINDIR\Minidump" -Filter "*.dmp" -Description "Minidumps"

    Write-Section "Windows Debug/Security Logs"
    Remove-SafeItems -Path "$env:WINDIR\Debug" -Filter "*.log" -Recurse -Description "Debug Logs"
    Remove-SafeItems -Path "$env:WINDIR\security\logs" -Filter "*.log" -Recurse -Description "Security Logs"

    Write-Section "CBS / DISM Logs (old only)"
    # Only delete rotated logs, NOT the active CBS.log
    $cbsPath = "$env:WINDIR\Logs\CBS"
    if (Test-Path $cbsPath) {
        $cutoff = (Get-Date).AddDays(-[Math]::Max($TempFileAgeDays, 7)) # At least 7 days old for CBS
        Get-ChildItem $cbsPath -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object {
                -not $_.PSIsContainer -and
                $_.Name -ne 'CBS.log' -and   # Never delete active CBS.log
                $_.Extension -in @('.log', '.cab') -and
                $_.LastWriteTime -lt $cutoff
            } |
            ForEach-Object {
                if ($DryRun) {
                    Write-Action "Would remove: $($_.FullName)" -Level DryRun
                    $Script:TotalFilesRemoved++
                }
                else {
                    try {
                        Remove-Item $_.FullName -Force -ErrorAction Stop
                        $Script:TotalFilesRemoved++
                    }
                    catch { $Script:TotalFilesFailed++ }
                }
            }
    }
    Remove-SafeItems -Path "$env:WINDIR\Logs\DISM" -Filter "*.log" -Recurse -Description "DISM Logs"
    Remove-SafeItems -Path "$env:WINDIR\Logs\DPX" -Filter "*.log" -Recurse -Description "DPX Logs"

    Write-Section "Windows Error Reporting (System-wide)"
    Remove-SafeItems -Path "C:\ProgramData\Microsoft\Windows\WER\ReportQueue" -Recurse -Description "System WER ReportQueue"
    Remove-SafeItems -Path "C:\ProgramData\Microsoft\Windows\WER\ReportArchive" -Recurse -Description "System WER ReportArchive"

    Write-Section "Delivery Optimization Cache"
    Remove-SafeItems -Path "$env:WINDIR\SoftwareDistribution\DeliveryOptimization" -Recurse -Description "Delivery Optimization (System)"

    Write-Section "Network Service Temp Logs"
    Remove-SafeItems -Path "$env:WINDIR\ServiceProfiles\NetworkService\AppData\Local\Temp" -Filter "*.log" -Recurse -Description "NetworkService Temp Logs"

    # ------------------------------------------------------------------
    # 4. WINDOWS UPDATE CACHE (optional, requires service stop)
    # ------------------------------------------------------------------

    if (-not $SkipWindowsUpdate) {
        Write-Section "Windows Update Cache (SoftwareDistribution)"

        if ($DryRun) {
            $wuPath = "$env:WINDIR\SoftwareDistribution\Download"
            if (Test-Path $wuPath) {
                $wuSize = (Get-ChildItem $wuPath -Recurse -Force -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                $wuSizeMB = [math]::Round($wuSize / 1MB, 2)
                Write-Action "Would clean Windows Update cache: ~$wuSizeMB MB" -Level DryRun
                Write-Action "Would stop services: wuauserv, BITS" -Level DryRun
            }
            else {
                Write-Action "Windows Update cache not found." -Level Info
            }
        }
        else {
            Write-Action "Stopping Windows Update and BITS services..." -Level Warning
            try {
                Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
                Stop-Service -Name BITS -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 3

                Remove-SafeItems -Path "$env:WINDIR\SoftwareDistribution\Download" -Recurse -Description "WU Download Cache"

                Write-Action "Restarting services..." -Level Info
                Start-Service -Name BITS -ErrorAction SilentlyContinue
                Start-Service -Name wuauserv -ErrorAction SilentlyContinue
                Write-Action "Windows Update services restarted." -Level Success
            }
            catch {
                Write-Action "Error managing Windows Update services: $_" -Level Error
                # Ensure services are restarted even on error
                Start-Service -Name BITS -ErrorAction SilentlyContinue
                Start-Service -Name wuauserv -ErrorAction SilentlyContinue
            }
        }
    }
    else {
        Write-Action "Windows Update cache cleanup skipped (-SkipWindowsUpdate)" -Level Info
    }

    # ------------------------------------------------------------------
    # 5. RECYCLE BIN (all users)
    # ------------------------------------------------------------------

    Write-Section "Recycle Bin"
    if ($DryRun) {
        Write-Action "Would empty Recycle Bin for all users" -Level DryRun
    }
    else {
        try {
            Clear-RecycleBin -Force -ErrorAction SilentlyContinue
            Write-Action "Recycle Bin emptied." -Level Success
        }
        catch {
            Write-Action "Could not empty Recycle Bin: $_" -Level Warning
        }
    }
}

# ============================================================================
#  SUMMARY
# ============================================================================

function Write-Summary {
    param([double]$StartFreeGB)

    $endFreeGB = Get-FreeSpaceGB
    $reclaimedGB = [math]::Round($endFreeGB - $StartFreeGB, 2)
    $duration = (Get-Date) - $Script:StartTime

    $summary = @"

  =============================================
    CLEANUP SUMMARY
  =============================================
  Duration:           $($duration.ToString('mm\:ss'))
  Mode:               $Mode
  DryRun:             $DryRun

  Profiles removed:   $($Script:ProfilesRemoved)
  Profiles failed:    $($Script:ProfilesFailed)

  Files cleaned:      $($Script:TotalFilesRemoved)
  Files skipped:      $($Script:TotalFilesFailed) (locked)
  Estimated freed:    $([math]::Round($Script:TotalBytesFreed / 1MB, 2)) MB

  Disk free before:   $StartFreeGB GB
  Disk free after:    $endFreeGB GB
  Actual reclaimed:   $reclaimedGB GB
  =============================================

"@

    if ($DryRun) {
        $summary += @"
  ** THIS WAS A DRY RUN - NOTHING WAS DELETED **
  To actually clean, run with:  -DryRun:`$false

"@
    }

    Write-Host $summary -ForegroundColor $(if ($DryRun) { 'Magenta' } else { 'Green' })
}

# ============================================================================
#  MAIN EXECUTION
# ============================================================================

# 1. Check and request admin
Request-Elevation

if (-not (Test-IsAdmin)) {
    Write-Host "ERROR: This script must run as Administrator." -ForegroundColor Red
    Write-Host "Right-click PowerShell > 'Run as Administrator', then try again." -ForegroundColor Yellow
    exit 1
}

# 2. Start logging
if (-not $NoLog) {
    if (-not $LogPath) {
        $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $LogPath = Join-Path $scriptDir "Clear-It_$timestamp.log"
    }
    try {
        Start-Transcript -Path $LogPath -Append -ErrorAction Stop | Out-Null
        Write-Action "Transcript logging to: $LogPath" -Level Info
    }
    catch {
        Write-Action "Could not start transcript: $_" -Level Warning
    }
}

# 3. Show banner
Write-Banner

# 4. Record starting disk space
$startFreeGB = Get-FreeSpaceGB
Write-Action "Starting free disk space: $startFreeGB GB" -Level Info

if ($DryRun) {
    Write-Host ""
    Write-Host "  *** DRY RUN MODE - No files will be deleted ***" -ForegroundColor Magenta
    Write-Host "  *** Pass -DryRun:`$false to perform actual cleanup ***" -ForegroundColor Magenta
    Write-Host ""
}

# 5. Execute based on mode
switch ($Mode) {
    'Profiles' {
        Invoke-ProfileCleanup
    }
    'TempFiles' {
        Invoke-TempFileCleanup
    }
    'All' {
        Invoke-ProfileCleanup
        Invoke-TempFileCleanup
    }
}

# 6. Summary
Write-Summary -StartFreeGB $startFreeGB

# 7. Stop transcript
if (-not $NoLog) {
    try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
}

Write-Host "Clear-It complete. Press any key to exit..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
