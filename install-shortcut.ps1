#Requires -Version 5.1
<#
.SYNOPSIS
    FreeWinly Start Menu Shortcut Installer.
    Creates a dedicated 'FreeWinly' shortcut in the user's Start Menu without hardcoded paths.
#>

$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot
$runnerScript = Join-Path $projectRoot "freewinly.ps1"

if (-not (Test-Path $runnerScript)) {
    Write-Error "Runner script not found at: $runnerScript"
    exit 1
}

$startMenuPrograms = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
$utilityFolder = Join-Path $startMenuPrograms "Utility"
if (-not (Test-Path $utilityFolder)) {
    # If Utility doesn't exist, place in root of Programs
    $targetDir = $startMenuPrograms
} else {
    $targetDir = $utilityFolder
}

$shortcutPath = Join-Path $targetDir "FreeWinly.lnk"

$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($shortcutPath)
$Shortcut.TargetPath       = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
$Shortcut.Arguments        = "-NoProfile -ExecutionPolicy Bypass -File `"$runnerScript`""
$Shortcut.WorkingDirectory = $projectRoot
$Shortcut.Description      = "FreeWinly - Open Source Windows Maintenance & Optimization"
$Shortcut.IconLocation     = "C:\Windows\System32\shell32.dll,238"
$Shortcut.Save()

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "         FreeWinly Shortcut Created Successfully!          " -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Shortcut location: $shortcutPath" -ForegroundColor Green
Write-Host "You can now launch FreeWinly directly by typing 'FreeWinly' in your Start Menu!`n" -ForegroundColor Cyan
