#Requires -Version 5.1
<#
.SYNOPSIS
    FreeWinly Configuration Initializer & Winget Exclusion Wizard.
.DESCRIPTION
    Scans installed packages via WinGet to identify standalone or self-updating applications
    with unknown version reporting, allowing the user to exclude them from automated upgrades.
    Generates or updates config.json with dynamically discovered modules, their execution order,
    and each module's communicated DefaultSettings.
.PARAMETER ConfigPath
    Optional path to the configuration JSON file (defaults to .\config.json in project root).
.EXAMPLE
    .\core\freewinly-init-config.ps1
.EXAMPLE
    .\core\freewinly-init-config.ps1 -ConfigPath "C:\path\to\config.json"
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
Write-Host "     FreeWinly v1.3.0 - Configuration & Exclusion Wizard    " -ForegroundColor White
Write-Host "        Scanning for applications with version quirks       " -ForegroundColor Gray
Write-Host "============================================================`n" -ForegroundColor Cyan

$existingConfig = if (Test-Path $ConfigPath) {
    try { Get-Content $ConfigPath -Raw | ConvertFrom-Json } catch { $null }
} else { $null }

$detectedExcludes = [System.Collections.Generic.List[object]]::new()

# Preserve existing exclusions (from v1.2.0 module settings or legacy root excluded)
$existingExcludedList = if ($existingConfig -and $existingConfig.modulesExecutionOrder -and $existingConfig.modulesExecutionOrder.'freewinly-update-software' -and $existingConfig.modulesExecutionOrder.'freewinly-update-software'.excluded) {
    $existingConfig.modulesExecutionOrder.'freewinly-update-software'.excluded
} elseif ($existingConfig -and $existingConfig.excluded) {
    $existingConfig.excluded
} else { @() }

foreach ($ex in $existingExcludedList) {
    $detectedExcludes.Add($ex)
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

                        if ($verText -and $verText -notmatch '\d' -and $pkgId -match '^[A-Za-z0-9\._-]+\.[A-Za-z0-9\._-]+$') {
                            if (-not ($detectedExcludes -contains $pkgId)) {
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

# Discover modules and sort by their communicated Order property
$rawModules = [System.Collections.Generic.List[PSCustomObject]]::new()
foreach ($mf in (Get-ChildItem (Join-Path $modulesDir "*.ps1") -ErrorAction SilentlyContinue)) {
    try {
        $info = & $mf.FullName -Action Info -ErrorAction Stop
        if ($info -and $info.Name) {
            $rawModules.Add([PSCustomObject]@{
                BaseName        = $mf.BaseName
                Order           = if ($null -ne $info.Order) { [int]$info.Order } else { 99 }
                Default         = if ($null -ne $info.Default) { [bool]$info.Default } else { $false }
                DefaultSettings = if ($info.DefaultSettings) { $info.DefaultSettings } else { [ordered]@{} }
            })
        }
    } catch { }
}

$sortedModules = $rawModules | Sort-Object Order, BaseName
$modulesExecutionOrder = [ordered]@{}

foreach ($m in $sortedModules) {
    $modBlock = [ordered]@{
        enabled = $m.Default
    }
    if ($m.DefaultSettings) {
        $keys = if ($m.DefaultSettings -is [System.Collections.IDictionary]) { $m.DefaultSettings.Keys } else { $m.DefaultSettings.PSObject.Properties.Name }
        foreach ($k in $keys) {
            $modBlock[$k] = $m.DefaultSettings[$k]
        }
    }
    if ($m.BaseName -eq 'freewinly-update-software') {
        $modBlock['excluded'] = @($detectedExcludes)
    }
    $modulesExecutionOrder[$m.BaseName] = $modBlock
}

$newConfig = [ordered]@{
    countdownSeconds      = if ($existingConfig -and $null -ne $existingConfig.countdownSeconds) { [int]$existingConfig.countdownSeconds } else { 10 }
    submenuView           = if ($existingConfig -and $existingConfig.submenuView) { [string]$existingConfig.submenuView } else { "Hidden" }
    expandedModules       = if ($existingConfig -and $existingConfig.expandedModules) { @($existingConfig.expandedModules) } else { @() }
    scheduleType          = if ($existingConfig -and $existingConfig.scheduleType) { $existingConfig.scheduleType } else { "Weekly" }
    scheduleDay           = if ($existingConfig -and $existingConfig.scheduleDay) { $existingConfig.scheduleDay } else { "Sunday" }
    scheduleTime          = if ($existingConfig -and $existingConfig.scheduleTime) { $existingConfig.scheduleTime } else { "12:00" }
    preCommands           = if ($existingConfig -and $existingConfig.preCommands) { @($existingConfig.preCommands) } else { @() }
    uninstall             = if ($existingConfig -and $existingConfig.uninstall) { @($existingConfig.uninstall) } else { @() }
    install               = if ($existingConfig -and $existingConfig.install) { @($existingConfig.install) } else { @() }
    postCommands          = if ($existingConfig -and $existingConfig.postCommands) { @($existingConfig.postCommands) } else { @() }
    modulesExecutionOrder = $modulesExecutionOrder
}

$newConfig | ConvertTo-Json -Depth 6 | Out-File -FilePath $ConfigPath -Encoding UTF8
Write-Host "`nConfiguration saved to: $ConfigPath" -ForegroundColor Green
Start-Sleep -Seconds 2
