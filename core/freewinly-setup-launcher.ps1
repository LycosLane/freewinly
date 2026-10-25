#Requires -Version 5.1
<#
.SYNOPSIS
    FreeWinly Shortcut & Launcher Manager (v1.5.1).
.DESCRIPTION
    Installs, inspects, or removes FreeWinly shortcuts across the Start Menu,
    the user's Desktop, and the Windows Startup folder (shell:startup).
    Placing FreeWinly in the Startup folder allows zero-admin logon maintenance
    with the built-in 10-second countdown.
.PARAMETER Action
    'Install', 'Remove', 'Status', or 'Interactive' (default when run from console).
.PARAMETER Target
    'StartMenu', 'Desktop', 'Startup', or 'All' (default 'StartMenu' for CLI, or selected via menu).
.EXAMPLE
    .\core\freewinly-setup-launcher.ps1 -Action Install -Target Desktop
.EXAMPLE
    .\core\freewinly-setup-launcher.ps1 -Action Install -Target Startup
.EXAMPLE
    .\core\freewinly-setup-launcher.ps1 -Action Status
#>
[CmdletBinding()]
param(
    [ValidateSet('Install', 'Remove', 'Status', 'Interactive')]
    [string]$Action = 'Interactive',
    [ValidateSet('StartMenu', 'Desktop', 'Startup', 'All')]
    [string]$Target = 'StartMenu'
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$runnerScript = Join-Path $projectRoot "freewinly.ps1"

$startMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
$desktopDir   = [Environment]::GetFolderPath('Desktop')
$startupDir   = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"

$shortcutMap = [ordered]@{
    'StartMenu' = @{
        Name = "Start Menu"
        Path = (Join-Path $startMenuDir "FreeWinly.lnk")
        Desc = "Appears in Start Menu search and pinned apps"
    }
    'Desktop' = @{
        Name = "Desktop"
        Path = (Join-Path $desktopDir "FreeWinly.lnk")
        Desc = "One-click access icon on your Windows desktop"
    }
    'Startup' = @{
        Name = "Startup Folder (Logon)"
        Path = (Join-Path $startupDir "FreeWinly.lnk")
        Desc = "Runs automatically 10s after logon (zero admin rights needed)"
    }
}

function Create-ShortcutFile {
    param([string]$Path)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $WshShell = New-Object -ComObject WScript.Shell
    $sc = $WshShell.CreateShortcut($Path)
    $sc.TargetPath       = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $sc.Arguments        = "-NoProfile -ExecutionPolicy Bypass -File `"$runnerScript`""
    $sc.WorkingDirectory = $projectRoot
    $sc.Description      = "FreeWinly - Open Source Windows Maintenance & Optimization"
    $customIcon = Join-Path $projectRoot "assets\icons\freewinly.ico"
    $sc.IconLocation     = if (Test-Path -LiteralPath $customIcon) { $customIcon } else { "$env:SystemRoot\System32\shell32.dll,238" }
    $sc.Save()
}

function Remove-ShortcutFile {
    param([string]$Path)
    if (Test-Path $Path) {
        Remove-Item -LiteralPath $Path -Force
        return $true
    }
    return $false
}

# Non-interactive CLI handling
if ($Action -eq 'Status') {
    Write-Host "`nFreeWinly Shortcut Status:" -ForegroundColor Cyan
    foreach ($k in $shortcutMap.Keys) {
        $entry = $shortcutMap[$k]
        $installed = Test-Path $entry.Path
        $statusStr = if ($installed) { "[Installed]" } else { "[Not Installed]" }
        $color = if ($installed) { "Green" } else { "DarkGray" }
        Write-Host "  $statusStr $($entry.Name) ($($entry.Path))" -ForegroundColor $color
    }
    Write-Host ""
    exit 0
}

if ($Action -in @('Install', 'Remove')) {
    $keysToProcess = if ($Target -eq 'All') { @($shortcutMap.Keys) } else { @($Target) }
    foreach ($k in $keysToProcess) {
        $entry = $shortcutMap[$k]
        if ($Action -eq 'Install') {
            Create-ShortcutFile -Path $entry.Path
            Write-Host "[OK] Created shortcut for $($entry.Name): $($entry.Path)" -ForegroundColor Green
        } else {
            $removed = Remove-ShortcutFile -Path $entry.Path
            if ($removed) {
                Write-Host "[OK] Removed shortcut for $($entry.Name)" -ForegroundColor Green
            } else {
                Write-Host "[Info] No shortcut found for $($entry.Name) to remove." -ForegroundColor Gray
            }
        }
    }
    exit 0
}

# Interactive Menu Mode
while ($true) {
    Clear-Host
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "       FreeWinly v1.5.1 - Shortcut & Launcher Manager       " -ForegroundColor White
    Write-Host "============================================================`n" -ForegroundColor Cyan

    $keys = @($shortcutMap.Keys)
    for ($i = 0; $i -lt $keys.Count; $i++) {
        $k = $keys[$i]
        $entry = $shortcutMap[$k]
        $installed = Test-Path $entry.Path
        $mark = if ($installed) { "[x]" } else { "[ ]" }
        $color = if ($installed) { "Green" } else { "DarkGray" }
        Write-Host "  [$($i + 1)] $mark $($entry.Name)" -ForegroundColor $color
        Write-Host "      $($entry.Desc)" -ForegroundColor Gray
    }

    Write-Host "`n------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  [4] Install All Shortcuts" -ForegroundColor Yellow
    Write-Host "  [5] Remove All Shortcuts" -ForegroundColor Yellow
    Write-Host "  [Q] Return to Main Menu" -ForegroundColor White

    Write-Host "`nEnter selection (1-3 to toggle, 4, 5, or Q): " -NoNewline -ForegroundColor Cyan
    $choice = [Console]::ReadKey($true).KeyChar.ToString().ToUpper()

    if ($choice -in @('1', '2', '3')) {
        $idx = [int]$choice - 1
        $selectedKey = $keys[$idx]
        $entry = $shortcutMap[$selectedKey]
        if (Test-Path $entry.Path) {
            Remove-ShortcutFile -Path $entry.Path | Out-Null
        } else {
            Create-ShortcutFile -Path $entry.Path
        }
    } elseif ($choice -eq '4') {
        foreach ($k in $keys) { Create-ShortcutFile -Path $shortcutMap[$k].Path }
    } elseif ($choice -eq '5') {
        foreach ($k in $keys) { Remove-ShortcutFile -Path $shortcutMap[$k].Path | Out-Null }
    } elseif ($choice -in @('Q', [char]27)) {
        break
    }
}
