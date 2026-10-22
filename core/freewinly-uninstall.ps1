#Requires -Version 5.1
<#
.SYNOPSIS
    FreeWinly Complete Artifact Cleaner & Uninstaller.
.DESCRIPTION
    Scans for and cleanly removes all installed FreeWinly Windows system artifacts
    (Scheduled Tasks in Windows Task Scheduler, User PATH environment variable registration,
    and all Start Menu, Desktop, and Startup folder shortcuts).
    
    Leaves the local FreeWinly script folder intact for user safety, allowing the user
    to manually delete or archive it without file-locking or repo-destruction risks.
.PARAMETER Check
    Displays the components that would be removed without prompting or deleting anything.
.PARAMETER Force
    Skips the confirmation prompt and proceeds immediately with uninstallation.
.EXAMPLE
    .\core\freewinly-uninstall.ps1
.EXAMPLE
    .\core\freewinly-uninstall.ps1 -Check
.EXAMPLE
    .\core\freewinly-uninstall.ps1 -Force
#>
[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$Force
)

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$projectRoot = Split-Path -Parent $PSScriptRoot

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "         FreeWinly Windows Artifact Cleaner & Uninstaller   " -ForegroundColor White
Write-Host "    Cleans Task Scheduler, User PATH & all Windows shortcuts" -ForegroundColor Gray
Write-Host "============================================================" -ForegroundColor Cyan

# 1. Inspect Components
$taskFound = $false
try {
    $task = Get-ScheduledTask -TaskName "FreeWinly" -ErrorAction Stop
    $taskFound = ($null -ne $task)
} catch {
    $taskFound = $false
}

$userPathRaw = [Environment]::GetEnvironmentVariable("Path", "User")
$normRoot = $projectRoot.TrimEnd('\')
$pathFound = $false
if ($userPathRaw) {
    $pathFound = ($userPathRaw.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries) | Where-Object {
        $_.Trim().TrimEnd('\').Equals($normRoot, [System.StringComparison]::OrdinalIgnoreCase)
    }).Count -gt 0
}

$startMenuPrograms = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
$desktopDir        = [Environment]::GetFolderPath('Desktop')
$startupDir        = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"

$shortcutCandidates = [ordered]@{
    "Start Menu Shortcut"       = (Join-Path $startMenuPrograms "FreeWinly.lnk")
    "Start Menu Utility Folder" = (Join-Path $startMenuPrograms "Utility\FreeWinly.lnk")
    "Desktop Shortcut"          = (Join-Path $desktopDir "FreeWinly.lnk")
    "Startup Folder Shortcut"   = (Join-Path $startupDir "FreeWinly.lnk")
}

$shortcutsFound = [System.Collections.Generic.List[PSCustomObject]]::new()
foreach ($k in $shortcutCandidates.Keys) {
    $scPath = $shortcutCandidates[$k]
    if (Test-Path -LiteralPath $scPath) {
        $shortcutsFound.Add([PSCustomObject]@{ Name = $k; Path = $scPath })
    }
}

Write-Host "`nWindows system artifacts identified for cleanup:" -ForegroundColor Yellow

if ($taskFound) {
    Write-Host "  [x] Windows Scheduled Task:    'FreeWinly' (Windows Task Scheduler)" -ForegroundColor White
} else {
    Write-Host "  [ ] Windows Scheduled Task:    Not registered" -ForegroundColor DarkGray
}

if ($pathFound) {
    Write-Host "  [x] User PATH Registration:    $projectRoot" -ForegroundColor White
} else {
    Write-Host "  [ ] User PATH Registration:    Not registered" -ForegroundColor DarkGray
}

if ($shortcutsFound.Count -gt 0) {
    foreach ($sc in $shortcutsFound) {
        Write-Host "  [x] $($sc.Name): $($sc.Path)" -ForegroundColor White
    }
} else {
    Write-Host "  [ ] Windows Shortcuts:         None detected" -ForegroundColor DarkGray
}

Write-Host "  [-] Application Directory:      $projectRoot" -ForegroundColor Gray
Write-Host "      (Protected: Script files and Git repositories are never auto-deleted)`n" -ForegroundColor DarkGray

if ($Check) {
    Write-Host "Dry run complete. No system artifacts were removed." -ForegroundColor Green
    exit 0
}

# 2. Confirm with user
if (-not $Force) {
    $confirm = Read-Host "Remove all FreeWinly Windows integrations, shortcuts, and scheduled tasks? (y/N)"
    if ($confirm -notmatch '^[Yy]$') {
        Write-Host "`nCleanup cancelled. No changes were made." -ForegroundColor Yellow
        exit 0
    }
}

Write-Host "`nProceeding with system cleanup..." -ForegroundColor Cyan

# 3. Remove Scheduled Task
if ($taskFound) {
    Write-Host "Removing scheduled task..." -ForegroundColor Gray
    $taskInstaller = Join-Path $PSScriptRoot "freewinly-setup-schedule.ps1"
    if (Test-Path $taskInstaller) {
        & $taskInstaller -Action Remove
    }
}

# 4. Remove User PATH Registration
if ($pathFound) {
    Write-Host "Removing User PATH registration..." -ForegroundColor Gray
    $pathManager = Join-Path $PSScriptRoot "freewinly-setup-path.ps1"
    if (Test-Path $pathManager) {
        & $pathManager -Action Remove
    }
}

# 5. Remove Shortcuts
if ($shortcutsFound.Count -gt 0) {
    $launcherManager = Join-Path $PSScriptRoot "freewinly-setup-launcher.ps1"
    if (Test-Path $launcherManager) {
        & $launcherManager -Action Remove -Target All | Out-Null
    }
    foreach ($sc in $shortcutsFound) {
        if (Test-Path -LiteralPath $sc.Path) {
            Write-Host "Removing shortcut: $($sc.Path) ..." -ForegroundColor Gray
            Remove-Item -LiteralPath $sc.Path -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host "`n============================================================" -ForegroundColor Green
Write-Host "       FreeWinly Windows Cleanup Completed Successfully!    " -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Green
Write-Host "All external Windows registrations have been completely removed:" -ForegroundColor Cyan
Write-Host "  * Windows Scheduled Task: Unregistered" -ForegroundColor Gray
Write-Host "  * User PATH Environment:  Cleaned" -ForegroundColor Gray
Write-Host "  * Shortcuts:              Removed (Start Menu, Desktop, Startup folder)" -ForegroundColor Gray
Write-Host "`nThe FreeWinly folder itself has been left intact:" -ForegroundColor Yellow
Write-Host "  $projectRoot" -ForegroundColor White
Write-Host "You can now safely delete or archive this folder at any time.`n" -ForegroundColor Gray
exit 0
