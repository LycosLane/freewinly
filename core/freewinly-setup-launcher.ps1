#Requires -Version 5.1
<#
.SYNOPSIS
    FreeWinly Start Menu Shortcut Manager.
.DESCRIPTION
    Installs, inspects, or removes the dedicated 'FreeWinly' shortcut in the user's Start Menu
    without hardcoded paths.
.PARAMETER Action
    'Install' - Creates or updates the Start Menu shortcut.
    'Remove'  - Deletes the shortcut from the Start Menu.
    'Status'  - Checks if the shortcut is currently installed.
.EXAMPLE
    .\core\freewinly-setup-launcher.ps1
.EXAMPLE
    .\core\freewinly-setup-launcher.ps1 -Action Remove
.EXAMPLE
    .\core\freewinly-setup-launcher.ps1 -Action Status
#>
[CmdletBinding()]
param(
    [ValidateSet('Install', 'Remove', 'Status')]
    [string]$Action = 'Install'
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$runnerScript = Join-Path $projectRoot "freewinly.ps1"

$startMenuPrograms = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
$utilityFolder     = Join-Path $startMenuPrograms "Utility"

# Check possible locations
$shortcutCandidates = @(
    (Join-Path $utilityFolder "FreeWinly.lnk"),
    (Join-Path $startMenuPrograms "FreeWinly.lnk")
)

$existingShortcut = $shortcutCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($Action -eq 'Status') {
    if ($existingShortcut) {
        Write-Host "Start Menu shortcut is installed at: $existingShortcut" -ForegroundColor Green
    } else {
        Write-Host "Start Menu shortcut is not installed." -ForegroundColor Yellow
    }
    exit 0
}

if ($Action -eq 'Remove') {
    $foundAny = $false
    foreach ($sc in $shortcutCandidates) {
        if (Test-Path $sc) {
            Remove-Item -Path $sc -Force
            Write-Host "Removed shortcut from: $sc" -ForegroundColor Green
            $foundAny = $true
        }
    }
    if (-not $foundAny) {
        Write-Host "No Start Menu shortcut was found to remove." -ForegroundColor Yellow
    }
    exit 0
}

# Install Action
if (-not (Test-Path $runnerScript)) {
    Write-Error "Runner script not found at: $runnerScript"
    exit 1
}

$targetDir = if (Test-Path $utilityFolder) { $utilityFolder } else { $startMenuPrograms }
$shortcutPath = Join-Path $targetDir "FreeWinly.lnk"

$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($shortcutPath)
$Shortcut.TargetPath       = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$Shortcut.Arguments        = "-NoProfile -ExecutionPolicy Bypass -File `"$runnerScript`""
$Shortcut.WorkingDirectory = $projectRoot
$Shortcut.Description      = "FreeWinly - Open Source Windows Maintenance & Optimization"
$Shortcut.IconLocation     = "$env:SystemRoot\System32\shell32.dll,238"
$Shortcut.Save()

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "         FreeWinly Shortcut Created Successfully!          " -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Shortcut location: $shortcutPath" -ForegroundColor Green
Write-Host "You can now launch FreeWinly directly by typing 'FreeWinly' in your Start Menu!`n" -ForegroundColor Cyan
