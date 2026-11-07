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
    .\bump.ps1 1.5.4
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+$')]
    [string]$NewVersion
)

$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot

# 1. Update VERSION file (Single Source of Truth for all PowerShell engine scripts)
$versionFile = Join-Path $projectRoot "VERSION"
Set-Content -LiteralPath $versionFile -Value $NewVersion -Encoding ASCII

# 2. Update core/freewinly-version.ps1 fallback default
$coreVerFile = Join-Path $projectRoot "core\freewinly-version.ps1"
if (Test-Path -LiteralPath $coreVerFile) {
    (Get-Content -LiteralPath $coreVerFile -Raw) -replace 'return "[0-9]+\.[0-9]+\.[0-9]+"', "return `"$NewVersion`"" |
        Set-Content -LiteralPath $coreVerFile -Encoding ASCII
}

# 3. Update README.md banner sample
$readmeFile = Join-Path $projectRoot "README.md"
if (Test-Path -LiteralPath $readmeFile) {
    (Get-Content -LiteralPath $readmeFile -Raw) -replace 'FreeWinly v[0-9]+\.[0-9]+\.[0-9]+', "FreeWinly v$NewVersion" |
        Set-Content -LiteralPath $readmeFile -Encoding UTF8
}

# 4. Update SKILL.md frontmatter description
$skillFile = Join-Path $projectRoot "SKILL.md"
if (Test-Path -LiteralPath $skillFile) {
    (Get-Content -LiteralPath $skillFile -Raw) -replace 'FreeWinly v[0-9]+\.[0-9]+\.[0-9]+', "FreeWinly v$NewVersion" |
        Set-Content -LiteralPath $skillFile -Encoding UTF8
}

Write-Host "`nFreeWinly canonical version successfully bumped to v$NewVersion!" -ForegroundColor Green

# 5. Automatically refresh release bundles
$bundleScript = Join-Path $projectRoot "bundle.ps1"
if (Test-Path -LiteralPath $bundleScript) {
    & $bundleScript
}
