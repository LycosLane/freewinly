#Requires -Version 5.1
<#
.SYNOPSIS
    FreeWinly Version Management Automation (Single Source of Truth).
.DESCRIPTION
    Updates the canonical project version across VERSION, README.md, and SKILL.md,
    and automatically rebuilds the release packages via bundle.ps1.
.PARAMETER NewVersion
    The new semantic version string (e.g. 1.5.4 or 1.6.0).
.EXAMPLE
    .\bump-version.ps1 1.5.4
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+$')]
    [string]$NewVersion
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# 1. Update VERSION file (Single Source of Truth for all PowerShell engine scripts)
$versionFile = Join-Path $projectRoot "VERSION"
[System.IO.File]::WriteAllText($versionFile, "$NewVersion`n", $utf8NoBom)

# 2. Update core/freewinly-version.ps1 fallback default
$coreVerFile = Join-Path $projectRoot "core\freewinly-version.ps1"
if (Test-Path -LiteralPath $coreVerFile) {
    $content = [System.IO.File]::ReadAllText($coreVerFile, [System.Text.Encoding]::UTF8)
    $content = $content -replace 'return "[0-9]+\.[0-9]+\.[0-9]+"', "return `"$NewVersion`""
    [System.IO.File]::WriteAllText($coreVerFile, $content, $utf8NoBom)
}

# 3. Update README.md banner sample
$readmeFile = Join-Path $projectRoot "README.md"
if (Test-Path -LiteralPath $readmeFile) {
    $content = [System.IO.File]::ReadAllText($readmeFile, [System.Text.Encoding]::UTF8)
    $content = $content -replace 'FreeWinly v[0-9]+\.[0-9]+\.[0-9]+', "FreeWinly v$NewVersion"
    [System.IO.File]::WriteAllText($readmeFile, $content, $utf8NoBom)
}

# 4. Update SKILL.md frontmatter description and metadata
$skillFile = Join-Path $projectRoot "SKILL.md"
if (Test-Path -LiteralPath $skillFile) {
    $content = [System.IO.File]::ReadAllText($skillFile, [System.Text.Encoding]::UTF8)
    $content = $content -replace 'FreeWinly v[0-9]+\.[0-9]+\.[0-9]+', "FreeWinly v$NewVersion"
    $content = $content -replace '- FreeWinly Version: [0-9]+\.[0-9]+\.[0-9]+', "- FreeWinly Version: $NewVersion"
    [System.IO.File]::WriteAllText($skillFile, $content, $utf8NoBom)
}

# 5. Update bucket/freewinly.json manifest
$scoopFile = Join-Path $projectRoot "bucket\freewinly.json"
if (Test-Path -LiteralPath $scoopFile) {
    $content = [System.IO.File]::ReadAllText($scoopFile, [System.Text.Encoding]::UTF8)
    $content = $content -replace '"version":\s*"[0-9]+\.[0-9]+\.[0-9]+"', "`"version`": `"$NewVersion`""
    $content = $content -replace '/v[0-9]+\.[0-9]+\.[0-9]+/FreeWinly\.zip', "/v$NewVersion/FreeWinly.zip"
    [System.IO.File]::WriteAllText($scoopFile, $content, $utf8NoBom)
}

Write-Host "`nFreeWinly canonical version successfully bumped to v$NewVersion!" -ForegroundColor Green

# 6. Automatically refresh release bundles
$bundleScript = Join-Path $PSScriptRoot "bundle.ps1"
if (Test-Path -LiteralPath $bundleScript) {
    & $bundleScript
}
