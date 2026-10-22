#Requires -Version 5.1
<#
.SYNOPSIS
    FreeWinly First-Run Onboarding & Configuration Wizard.
.DESCRIPTION
    Scans installed packages via WinGet to identify standalone or self-updating applications
    with unknown version reporting, allowing the user to exclude them from automated upgrades.
    Generates or updates config.json with dynamically discovered default modules.
.PARAMETER ConfigPath
    Optional path to the configuration JSON file (defaults to .\config.json in project root).
.EXAMPLE
    .\core\onboarding.ps1
.EXAMPLE
    .\core\onboarding.ps1 -ConfigPath "C:\path\to\config.json"
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = $null
)

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$projectRoot = Split-Path -Parent $PSScriptRoot
$modulesDir  = Join-Path $projectRoot "modules"
if (-not $ConfigPath) {
    $ConfigPath = Join-Path $projectRoot "config.json"
}

Clear-Host
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "        FreeWinly v1.1.0 - First-Run Onboarding Setup       " -ForegroundColor White
Write-Host "        Scanning for applications with version quirks       " -ForegroundColor Gray
Write-Host "============================================================`n" -ForegroundColor Cyan

$existingConfig = if (Test-Path $ConfigPath) {
    try { Get-Content $ConfigPath -Raw | ConvertFrom-Json } catch { $null }
} else { $null }

$detectedExcludes = [System.Collections.Generic.List[string]]::new()
if ($existingConfig -and $existingConfig.excluded) {
    foreach ($ex in $existingConfig.excluded) {
        if ($ex -is [string] -and -not $detectedExcludes.Contains($ex)) {
            $detectedExcludes.Add($ex)
        }
    }
}

if (Get-Command winget -ErrorAction SilentlyContinue) {
    try {
        $lines = & winget upgrade --include-unknown --accept-source-agreements 2>&1 | Out-String -Stream
        $sepIdx = [array]::FindIndex($lines, [Predicate[string]]{ param($l) $l -match '^-{20,}' })
        if ($sepIdx -ge 1) {
            $header     = $lines[$sepIdx - 1]
            $colMatches = [regex]::Matches($header, '(?<=^|\s{2,})\S+')
            if ($colMatches.Count -ge 3) {
                $idStart    = $colMatches[1].Index
                $verStart   = $colMatches[2].Index
                $availStart = if ($colMatches.Count -ge 4) { $colMatches[3].Index } else { $header.Length }

                for ($i = $sepIdx + 1; $i -lt $lines.Count; $i++) {
                    $line = $lines[$i]
                    if ($line.Length -gt $verStart) {
                        $appName = $line.Substring(0, $idStart).Trim()
                        $pkgId   = $line.Substring($idStart, $verStart - $idStart).Trim()
                        $verLen  = [math]::Min($availStart - $verStart, $line.Length - $verStart)
                        $verText = if ($verLen -gt 0) { $line.Substring($verStart, $verLen).Trim() } else { "" }

                        # If version contains no digits (e.g. 'Unknown', 'Unbekannt', 'Inconnu', '<unknown>')
                        if ($verText -and $verText -notmatch '\d' -and $pkgId -match '^[A-Za-z0-9\._-]+\.[A-Za-z0-9\._-]+$') {
                            if (-not $detectedExcludes.Contains($pkgId)) {
                                Write-Host "Detected independent app: $appName (ID: $pkgId)" -ForegroundColor Yellow
                                $choice = Read-Host "Exclude '$pkgId' from automated Winget upgrades? (Y/n) [Default: Y]"
                                if ($choice -notmatch '^[Nn]$') {
                                    $detectedExcludes.Add($pkgId)
                                    Write-Host "  -> Added '$pkgId' to exclusions." -ForegroundColor Green
                                }
                            }
                        }
                    }
                }
            }
        }
    } catch {
        Write-Host "Winget scan skipped: $($_.Exception.Message)" -ForegroundColor Gray
    }
}

$enabled = if ($existingConfig -and $existingConfig.enabledModules) {
    $existingConfig.enabledModules
} else {
    @(Get-ChildItem (Join-Path $modulesDir "*.ps1") -ErrorAction SilentlyContinue | Sort-Object Name | Where-Object {
        try { (& $_.FullName -Action Info).Default -eq $true } catch { $true }
    } | Select-Object -ExpandProperty BaseName)
}

$newConfig = [ordered]@{
    preCommands           = if ($existingConfig -and $existingConfig.preCommands) { @($existingConfig.preCommands) } else { @() }
    uninstall             = if ($existingConfig -and $existingConfig.uninstall) { @($existingConfig.uninstall) } else { @() }
    install               = if ($existingConfig -and $existingConfig.install) { @($existingConfig.install) } else { @() }
    excluded              = @($detectedExcludes)
    postCommands          = if ($existingConfig -and $existingConfig.postCommands) { @($existingConfig.postCommands) } else { @() }
    enabledModules        = @($enabled)
    cleanupTempMinAgeDays = if ($existingConfig -and $existingConfig.cleanupTempMinAgeDays) { [int]$existingConfig.cleanupTempMinAgeDays } else { 7 }
    eventLogLookbackDays  = if ($existingConfig -and $existingConfig.eventLogLookbackDays) { [int]$existingConfig.eventLogLookbackDays } else { 7 }
    hddDefragMinDays      = if ($existingConfig -and $existingConfig.hddDefragMinDays) { [int]$existingConfig.hddDefragMinDays } else { 30 }
    countdownSeconds      = if ($existingConfig -and $null -ne $existingConfig.countdownSeconds) { [int]$existingConfig.countdownSeconds } else { 10 }
    scheduleType          = if ($existingConfig -and $existingConfig.scheduleType) { $existingConfig.scheduleType } else { "Weekly" }
    scheduleDay           = if ($existingConfig -and $existingConfig.scheduleDay) { $existingConfig.scheduleDay } else { "Sunday" }
    scheduleTime          = if ($existingConfig -and $existingConfig.scheduleTime) { $existingConfig.scheduleTime } else { "12:00" }
}

$newConfig | ConvertTo-Json -Depth 5 | Out-File -FilePath $ConfigPath -Encoding UTF8
Write-Host "`nConfiguration saved to: $ConfigPath" -ForegroundColor Green
Start-Sleep -Seconds 2
