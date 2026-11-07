#Requires -Version 5.1
<#
.SYNOPSIS
    FreeWinly Central Version Provider (Single Source of Truth).
.DESCRIPTION
    Resolves the canonical FreeWinly version number from the VERSION file
    or built-in fallback, exposing $global:FreeWinlyVersion and Get-FreeWinlyVersion.
.NOTES
    Part of the FreeWinly Core Toolchain (Windows 11 Native).
#>

function Get-FreeWinlyVersion {
    $versionFile = Join-Path (Split-Path -Parent $PSScriptRoot) "VERSION"
    if (Test-Path -LiteralPath $versionFile) {
        $v = (Get-Content -LiteralPath $versionFile -Raw).Trim()
        if ($v -match '^[0-9]+\.[0-9]+\.[0-9]+') { return $v }
    }
    return "1.5.3"
}

$global:FreeWinlyVersion = Get-FreeWinlyVersion


