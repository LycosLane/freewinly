#Requires -Version 5.1
<#
.SYNOPSIS
    FreeWinly Complete Uninstaller.
.DESCRIPTION
    Scans for all installed FreeWinly system artifacts (Scheduled Tasks in Windows Task Scheduler,
    Start Menu shortcuts, and the application directory itself). Displays an interactive preview
    of what will be removed and asks for confirmation before cleaning up.
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
Write-Host "                FreeWinly Complete Uninstaller              " -ForegroundColor White
Write-Host "       Removes scheduled tasks, PATH, shortcuts & files     " -ForegroundColor Gray
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
$shortcutCandidates = @(
    (Join-Path $startMenuPrograms "Utility\FreeWinly.lnk"),
    (Join-Path $startMenuPrograms "FreeWinly.lnk")
)
$shortcutsFound = @($shortcutCandidates | Where-Object { Test-Path $_ })

Write-Host "`nComponents identified for removal:" -ForegroundColor Yellow

if ($taskFound) {
    Write-Host "  [x] Windows Scheduled Task:    'FreeWinly' (Windows Task Scheduler)" -ForegroundColor White
} else {
    Write-Host "  [ ] Windows Scheduled Task:    Not installed" -ForegroundColor DarkGray
}

if ($pathFound) {
    Write-Host "  [x] User PATH Registration:    $projectRoot" -ForegroundColor White
} else {
    Write-Host "  [ ] User PATH Registration:    Not registered" -ForegroundColor DarkGray
}

if ($shortcutsFound.Count -gt 0) {
    foreach ($sc in $shortcutsFound) {
        Write-Host "  [x] Start Menu Shortcut:       $sc" -ForegroundColor White
    }
} else {
    Write-Host "  [ ] Start Menu Shortcut:       Not installed" -ForegroundColor DarkGray
}

Write-Host "  [x] Application Directory:      $projectRoot" -ForegroundColor White
Write-Host "      (Includes all modules, local config.json, and execution logs)`n" -ForegroundColor Gray

if ($Check) {
    Write-Host "Dry run complete. No components were removed." -ForegroundColor Green
    exit 0
}

# 2. Confirm with user
if (-not $Force) {
    $confirm = Read-Host "Are you sure you want to completely remove FreeWinly from this PC? (y/N)"
    if ($confirm -notmatch '^[Yy]$') {
        Write-Host "`nUninstallation cancelled. No changes were made." -ForegroundColor Yellow
        exit 0
    }
}

Write-Host "`nProceeding with uninstallation..." -ForegroundColor Cyan

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

# 4. Remove Start Menu Shortcuts
foreach ($sc in $shortcutsFound) {
    Write-Host "Removing Start Menu shortcut: $sc ..." -ForegroundColor Gray
    Remove-Item -Path $sc -Force -ErrorAction SilentlyContinue
}

# 5. Cleanly Delete Application Folder via Detached Process
Write-Host "`nAll Windows registrations removed." -ForegroundColor Green
Write-Host "Deleting application directory: $projectRoot ..." -ForegroundColor Green
Write-Host "FreeWinly has been completely removed. Goodbye!`n" -ForegroundColor Cyan

Start-Sleep -Seconds 1

# Launch detached CMD from TEMP to delete folder after current process releases file lock
$cleanCommand = "timeout /t 2 /nobreak >nul & rmdir /s /q `"$projectRoot`""
Start-Process cmd.exe -ArgumentList "/c $cleanCommand" -WorkingDirectory $env:TEMP -WindowStyle Hidden
exit 0
