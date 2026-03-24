# Clear-It

Clear-It is a Windows 10/11 cleanup tool for IT admins and support staff. It safely previews cleanup actions first, can remove inactive user profiles, and clears common temp/cache locations such as browser caches, Windows Update downloads, crash dumps, logs, and recycle-bin contents.

## Quick Start

Double-click `Start-Menu.bat` to open the interactive menu.

## Available Scripts

| Script | Purpose |
| --- | --- |
| `Start-Menu.bat` | Opens the guided interactive menu. |
| `Preview-Cleanup.bat` | Safe preview of a full cleanup with no deletions. |
| `Clean-TempFiles.bat` | Deletes temp files, caches, logs, dumps, and recycle-bin contents only. |
| `Clean-Profiles-Custom.bat` | Prompts for inactivity days, then removes matching inactive profiles. |
| `Full-Cleanup-Custom.bat` | Prompts for inactivity days, then removes inactive profiles and temp/cache data. |

## Safety Guarantees

- `Clear-It.ps1` runs in DryRun mode by default.
- Actual deletion only happens when `-DryRun:$false` is passed explicitly.
- Built-in, system, and currently active profiles are protected from profile removal.
- Locked files are skipped instead of stopping the run.
- Transcript logging is enabled by default unless `-NoLog` is used.

## PowerShell Direct Usage

```powershell
.\Clear-It.ps1
.\Clear-It.ps1 -Mode Profiles -InactiveDays 60 -DryRun:$false
.\Clear-It.ps1 -Mode TempFiles -TempFileAgeDays 7 -DryRun:$false
.\Clear-It.ps1 -Mode All -InactiveDays 90 -DryRun:$false -ExcludeUsers @('svc_backup','admin.jones')
.\Clear-It.ps1 -Mode TempFiles -SkipBrowserCache -SkipWindowsUpdate
```

## Requirements

- Windows 10 or Windows 11
- PowerShell 5.1 or newer
- Administrator privileges

## Notes

- Start with `Preview-Cleanup.bat` or menu option `1` before any live cleanup.
- The script writes `Clear-It_<timestamp>.log` in the script folder unless logging is disabled.
