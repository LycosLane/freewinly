#Requires -Version 5.1
<#
.SYNOPSIS
    FreeWinly User PATH Environment Variable Manager.
.DESCRIPTION
    Adds, removes, toggles, or checks FreeWinly directories (root, core, and modules)
    in the current Windows User's PATH environment variable. Does not require Administrator
    privileges and enables tab-completion of all 'freewinly-*' commands in any terminal.
.PARAMETER Action
    'Install' - Adds FreeWinly directories to User PATH.
    'Remove'  - Removes FreeWinly directories from User PATH.
    'Toggle'  - Installs if not present, or removes if already present.
    'Status'  - Checks whether FreeWinly is currently registered in User PATH.
.EXAMPLE
    .\core\freewinly-setup-path.ps1 -Action Install
.EXAMPLE
    .\core\freewinly-setup-path.ps1 -Action Remove
.EXAMPLE
    .\core\freewinly-setup-path.ps1 -Action Status
#>
[CmdletBinding()]
param(
    [ValidateSet('Install', 'Remove', 'Toggle', 'Status')]
    [string]$Action = 'Install'
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$coreDir     = Join-Path $projectRoot "core"
$modulesDir  = Join-Path $projectRoot "modules"

$targetDirs = @($projectRoot, $coreDir, $modulesDir)

$userPathRaw = [Environment]::GetEnvironmentVariable("Path", "User")
$userPaths   = if ($userPathRaw) {
    @($userPathRaw.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim().TrimEnd('\') })
} else {
    @()
}

$normalizedRoot = $projectRoot.TrimEnd('\')
$isInstalled = ($userPaths | Where-Object { $_.Equals($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0

if ($Action -eq 'Status') {
    if ($isInstalled) {
        Write-Host "User PATH integration is enabled ($projectRoot)." -ForegroundColor Green
    } else {
        Write-Host "User PATH integration is disabled." -ForegroundColor Yellow
    }
    return
}

if ($Action -eq 'Toggle') {
    $Action = if ($isInstalled) { 'Remove' } else { 'Install' }
}

if ($Action -eq 'Remove') {
    $normTargets = @($targetDirs | ForEach-Object { $_.TrimEnd('\') })
    $filtered = @($userPaths | Where-Object {
        $p = $_
        ($normTargets | Where-Object { $p.Equals($_, [System.StringComparison]::OrdinalIgnoreCase) }).Count -eq 0
    })
    $newPathStr = $filtered -join ';'
    [Environment]::SetEnvironmentVariable("Path", $newPathStr, "User")
    Write-Host "`nRemoved FreeWinly from User PATH." -ForegroundColor Yellow
    return
}

# Install Action
$updatedPaths = [System.Collections.Generic.List[string]]::new()
foreach ($p in $userPaths) {
    $updatedPaths.Add($p)
}

foreach ($td in $targetDirs) {
    $norm = $td.TrimEnd('\')
    $exists = ($updatedPaths | Where-Object { $_.Equals($norm, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
    if (-not $exists) {
        $updatedPaths.Add($norm)
    }
}

$newPathStr = $updatedPaths -join ';'
[Environment]::SetEnvironmentVariable("Path", $newPathStr, "User")
$env:Path = "$env:Path;$($targetDirs -join ';')"

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "       FreeWinly Added to User PATH Successfully!           " -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Registered directories in User PATH:" -ForegroundColor Green
foreach ($td in $targetDirs) {
    Write-Host "  + $td" -ForegroundColor Gray
}
Write-Host "`nYou can now run 'freewinly' and tab-complete 'freewinly-*' in any new terminal!`n" -ForegroundColor Cyan
