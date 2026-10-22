#Requires -Version 5.1
<#
.SYNOPSIS
    FreeWinly Release Packager.
    Generates 'FreeWinly.zip' (core standalone release) and
    'FreeWinly4LLM.zip' (includes SKILL.md for AI assistants).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot
$distDir     = Join-Path $projectRoot "dist"
$stageDir    = Join-Path $distDir "stage"
$coreZip     = Join-Path $distDir "FreeWinly.zip"
$llmZip      = Join-Path $distDir "FreeWinly4LLM.zip"

if (Test-Path $distDir) {
    Remove-Item -Recurse -Force $distDir
}

New-Item -ItemType Directory -Path $stageDir -Force | Out-Null

$coreItems = @(
    "freewinly.cmd",
    "freewinly.ps1",
    "config.example.json",
    "README.md",
    "LICENSE"
)

foreach ($item in $coreItems) {
    $src = Join-Path $projectRoot $item
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination $stageDir -Force
    }
}

Copy-Item -Path (Join-Path $projectRoot "core") -Destination $stageDir -Recurse -Force
Copy-Item -Path (Join-Path $projectRoot "modules") -Destination $stageDir -Recurse -Force

# Ensure no local configuration files or backups are shipped
Get-ChildItem -Path $stageDir -Filter "config*.json" -Recurse | Where-Object { $_.Name -ne "config.example.json" } | Remove-Item -Force -ErrorAction SilentlyContinue

# 1. Package FreeWinly.zip (core release package)
Compress-Archive -Path "$stageDir\*" -DestinationPath $coreZip -Force
$coreSize = [math]::Round((Get-Item $coreZip).Length / 1KB, 1)

# 2. Add SKILL.md and package FreeWinly4LLM.zip (AI agent skill package)
$skillSrc = Join-Path $projectRoot "SKILL.md"
if (Test-Path $skillSrc) {
    Copy-Item -Path $skillSrc -Destination $stageDir -Force
}
Compress-Archive -Path "$stageDir\*" -DestinationPath $llmZip -Force
$llmSize = [math]::Round((Get-Item $llmZip).Length / 1KB, 1)

# Cleanup staging folder
Remove-Item -Recurse -Force $stageDir

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "       FreeWinly Dual Release Packages Generated!           " -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "1. Pure Tool (For Humans / Offline):" -ForegroundColor White
Write-Host "   $coreZip ($coreSize KB)" -ForegroundColor Green
Write-Host "`n2. AI Agent Edition (Includes SKILL.md):" -ForegroundColor White
Write-Host "   $llmZip ($llmSize KB)" -ForegroundColor Green
Write-Host "`nReady to upload to GitHub Releases -> Assets.`n" -ForegroundColor Cyan
