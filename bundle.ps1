#Requires -Version 5.1
<#
.SYNOPSIS
    FreeWinly Release Packager.
    Generates a clean, distributable FreeWinly.zip ready to upload to GitHub Releases.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot
$distDir     = Join-Path $projectRoot "dist"
$stageDir    = Join-Path $distDir "FreeWinly"
$zipPath     = Join-Path $distDir "FreeWinly.zip"

if (Test-Path $distDir) {
    Remove-Item -Recurse -Force $distDir
}

New-Item -ItemType Directory -Path $stageDir -Force | Out-Null

$itemsToCopy = @(
    "freewinly.cmd",
    "freewinly.ps1",
    "install-shortcut.ps1",
    "config.example.json",
    "README.md",
    "LICENSE",
    "SKILL.md"
)

foreach ($item in $itemsToCopy) {
    $src = Join-Path $projectRoot $item
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination $stageDir -Force
    }
}

Copy-Item -Path (Join-Path $projectRoot "modules") -Destination $stageDir -Recurse -Force

Compress-Archive -Path "$stageDir\*" -DestinationPath $zipPath -Force
Remove-Item -Recurse -Force $stageDir

$sizeMB = [math]::Round((Get-Item $zipPath).Length / 1KB, 1)
Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "       FreeWinly Release Package Created Successfully!      " -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Package Path: $zipPath ($sizeMB KB)" -ForegroundColor Green
Write-Host "Ready to upload to GitHub Releases -> Assets -> FreeWinly.zip`n" -ForegroundColor Cyan
