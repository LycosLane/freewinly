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
$projectRoot = Split-Path -Parent $PSScriptRoot
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
    "LICENSE",
    "VERSION"
)

foreach ($item in $coreItems) {
    $src = Join-Path $projectRoot $item
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination $stageDir -Force
    }
}

Copy-Item -Path (Join-Path $projectRoot "assets") -Destination $stageDir -Recurse -Force
Copy-Item -Path (Join-Path $projectRoot "core") -Destination $stageDir -Recurse -Force
Copy-Item -Path (Join-Path $projectRoot "modules") -Destination $stageDir -Recurse -Force

# Ensure no local configuration files, backups, or gitignored local/custom modules are shipped
Get-ChildItem -Path $stageDir -Filter "config*.json" -Recurse | Where-Object { $_.Name -ne "config.example.json" } | Remove-Item -Force -ErrorAction SilentlyContinue
$stageModules = Join-Path $stageDir "modules"
if (Test-Path -LiteralPath $stageModules) {
    Get-ChildItem -LiteralPath $stageModules -Filter "*_local_*.ps1" -File | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath $stageModules -Filter "*_custom_*.ps1" -File | Remove-Item -Force -ErrorAction SilentlyContinue
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Set-CanonicalLineEndings {
    param([Parameter(Mandatory = $true)][string]$RootDir)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $crlfExts = @('.ps1', '.cmd')
    $lfExts   = @('.json', '.md', '.svg')
    $lfNames  = @('VERSION', 'LICENSE')
    foreach ($f in (Get-ChildItem -LiteralPath $RootDir -Recurse -File)) {
        $ext = $f.Extension.ToLowerInvariant()
        $targetEol = if ($crlfExts -contains $ext) {
            "`r`n"
        } elseif (($lfExts -contains $ext) -or ($lfNames -contains $f.Name)) {
            "`n"
        } else {
            $null
        }
        if ($null -ne $targetEol) {
            $raw = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
            $normalized = ($raw -replace "`r`n", "`n") -replace "`r", "`n"
            if ($targetEol -eq "`r`n") {
                $normalized = $normalized -replace "`n", "`r`n"
            }
            [System.IO.File]::WriteAllText($f.FullName, $normalized, $utf8NoBom)
        }
    }
}

function New-DeterministicZip {
    param(
        [Parameter(Mandatory = $true)][string]$SourceDir,
        [Parameter(Mandatory = $true)][string]$DestinationZip
    )
    if (Test-Path -LiteralPath $DestinationZip) {
        Remove-Item -LiteralPath $DestinationZip -Force
    }
    $fullSource = (Resolve-Path -LiteralPath $SourceDir).Path.TrimEnd('\')
    $fixedTime = [DateTimeOffset]::new(2026, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
    $fileItems = [System.Collections.Generic.List[object]]::new()
    foreach ($f in (Get-ChildItem -LiteralPath $fullSource -Recurse -File)) {
        $fileItems.Add([PSCustomObject]@{
            RelPath  = $f.FullName.Substring($fullSource.Length + 1).Replace('\', '/')
            FullName = $f.FullName
        })
    }
    $fileItems.Sort([System.Comparison[object]]{
        param($a, $b)
        [System.StringComparer]::Ordinal.Compare($a.RelPath, $b.RelPath)
    })

    $zip = [System.IO.Compression.ZipFile]::Open($DestinationZip, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($item in $fileItems) {
            $entry = $zip.CreateEntry($item.RelPath, [System.IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = $fixedTime
            $inStream = [System.IO.File]::OpenRead($item.FullName)
            try {
                $outStream = $entry.Open()
                try {
                    $inStream.CopyTo($outStream)
                } finally {
                    $outStream.Dispose()
                }
            } finally {
                $inStream.Dispose()
            }
        }
    } finally {
        $zip.Dispose()
    }
}

# 1. Package FreeWinly.zip (core release package)
Set-CanonicalLineEndings -RootDir $stageDir
New-DeterministicZip -SourceDir $stageDir -DestinationZip $coreZip
$coreSize = [math]::Round((Get-Item $coreZip).Length / 1KB, 1)

# 2. Add SKILL.md and package FreeWinly4LLM.zip (AI agent skill package)
$skillSrc = Join-Path $projectRoot "SKILL.md"
if (Test-Path $skillSrc) {
    Copy-Item -Path $skillSrc -Destination $stageDir -Force
}
Set-CanonicalLineEndings -RootDir $stageDir
New-DeterministicZip -SourceDir $stageDir -DestinationZip $llmZip
$llmSize = [math]::Round((Get-Item $llmZip).Length / 1KB, 1)

# Cleanup staging folder
Remove-Item -Recurse -Force $stageDir

# 3. Generate SHA256SUMS.txt for release asset verification
$sumsPath = Join-Path $distDir "SHA256SUMS.txt"
$coreHash = (Get-FileHash -LiteralPath $coreZip -Algorithm SHA256).Hash
$llmHash  = (Get-FileHash -LiteralPath $llmZip -Algorithm SHA256).Hash
$sumsContent = "$coreHash  FreeWinly.zip`r`n$llmHash  FreeWinly4LLM.zip`r`n"
[System.IO.File]::WriteAllText($sumsPath, $sumsContent, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "       FreeWinly Dual Release Packages Generated!           " -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "1. Pure Tool (For Humans / Offline):" -ForegroundColor White
Write-Host "   $coreZip ($coreSize KB)" -ForegroundColor Green
Write-Host "`n2. AI Agent Edition (Includes SKILL.md):" -ForegroundColor White
Write-Host "   $llmZip ($llmSize KB)" -ForegroundColor Green
Write-Host "`n3. Checksums:" -ForegroundColor White
Write-Host "   $sumsPath" -ForegroundColor Cyan
Write-Host "`nReady to upload to GitHub Releases -> Assets.`n" -ForegroundColor Cyan
