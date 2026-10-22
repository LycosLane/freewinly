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

# Dot-source config I/O manager
. (Join-Path $PSScriptRoot "freewinly-config-io.ps1")

Clear-Host
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "     FreeWinly v1.5.0 - Configuration & Exclusion Wizard    " -ForegroundColor White
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

$updateModule = Join-Path $modulesDir "freewinly-update-software.ps1"
if (Test-Path $updateModule) {
    try {
        $availablePackages = & $updateModule -Action Scan -ErrorAction Stop
        foreach ($pkg in $availablePackages) {
            # Detect applications with non-numeric / missing versions (frequently cause infinite upgrade loops in WinGet)
            $hasVersionQuirk = ($pkg.InstalledVersion -and $pkg.InstalledVersion -notmatch '\d')

            if ($hasVersionQuirk) {
                if (-not ($detectedExcludes -contains $pkg.Id)) {
                    Write-Host "Detected app with version quirk: $($pkg.Name) (ID: $($pkg.Id))" -ForegroundColor Yellow
                    $choice = Read-Host "Exclude '$($pkg.Id)' from automated Winget upgrades? (Y/n) [Default: Y]"
                    if ($choice -notmatch '^[Nn]$') {
                        $detectedExcludes.Add($pkg.Id)
                        Write-Host "  -> Added '$($pkg.Id)' to exclusions." -ForegroundColor Green
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

$orderedBaseNames = [System.Collections.Generic.List[string]]::new()
if ($existingConfig -and $existingConfig.modulesExecutionOrder) {
    $existingKeys = if ($existingConfig.modulesExecutionOrder -is [System.Collections.IDictionary]) {
        $existingConfig.modulesExecutionOrder.Keys
    } else {
        $existingConfig.modulesExecutionOrder.PSObject.Properties.Name
    }
    foreach ($ek in $existingKeys) {
        if (($rawModules | Where-Object { $_.BaseName -eq $ek }) -and -not $orderedBaseNames.Contains($ek)) {
            $orderedBaseNames.Add($ek)
        }
    }
}
foreach ($m in $sortedModules) {
    if (-not $orderedBaseNames.Contains($m.BaseName)) {
        $orderedBaseNames.Add($m.BaseName)
    }
}

$moduleMap = @{}
foreach ($m in $rawModules) {
    $moduleMap[$m.BaseName] = $m
}

$modulesExecutionOrder = [ordered]@{}

foreach ($baseName in $orderedBaseNames) {
    $m = $moduleMap[$baseName]
    $existingMod = if ($existingConfig -and $existingConfig.modulesExecutionOrder) {
        $existingConfig.modulesExecutionOrder.$baseName
    } else { $null }

    $isEnabled = if ($null -ne $existingMod) {
        if ($existingMod -is [bool]) {
            [bool]$existingMod
        } elseif ($null -ne $existingMod.enabled) {
            [bool]$existingMod.enabled
        } else {
            $m.Default
        }
    } else {
        $m.Default
    }

    $modBlock = [ordered]@{
        enabled = $isEnabled
    }

    if ($m.BaseName -eq 'freewinly-clean-apps') {
        $modBlock['minAgeDays'] = if ($null -ne $existingMod -and $null -ne $existingMod.minAgeDays) { [int]$existingMod.minAgeDays } else { 3 }
        $defKeys = if ($m.DefaultSettings -is [System.Collections.IDictionary]) {
            $m.DefaultSettings.Keys
        } else {
            $m.DefaultSettings.PSObject.Properties.Name
        }
        foreach ($bName in $defKeys) {
            if ($bName -in @('minAgeDays', 'customApps')) { continue }
            $existingVal = if ($null -ne $existingMod) { $existingMod.$bName } else { $null }
            $bEnabled = if ($existingVal -is [bool]) {
                $existingVal
            } elseif ($null -ne $existingVal -and $null -ne $existingVal.enabled) {
                [bool]$existingVal.enabled
            } else {
                $true
            }
            $modBlock[$bName] = $bEnabled
        }
        $existingCust = if ($null -ne $existingMod -and $null -ne $existingMod.customApps) { $existingMod.customApps } else { [ordered]@{} }
        $modBlock['customApps'] = $existingCust
    } else {
        # Overlay default settings first
        if ($m.DefaultSettings) {
            $keys = if ($m.DefaultSettings -is [System.Collections.IDictionary]) { $m.DefaultSettings.Keys } else { $m.DefaultSettings.PSObject.Properties.Name }
            foreach ($k in $keys) {
                $modBlock[$k] = $m.DefaultSettings[$k]
            }
        }

        # Overlay existing customized settings
        if ($null -ne $existingMod -and -not ($existingMod -is [bool])) {
            $existingKeys = if ($existingMod -is [System.Collections.IDictionary]) {
                $existingMod.Keys
            } else {
                $existingMod.PSObject.Properties.Name
            }
            foreach ($ek in $existingKeys) {
                if ($ek -ne 'enabled') {
                    $modBlock[$ek] = $existingMod.$ek
                }
            }
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

Save-AtomicConfigFile -Path $ConfigPath -Config $newConfig -Depth 6
Write-Host "`nConfiguration saved to: $ConfigPath" -ForegroundColor Green
Start-Sleep -Seconds 2
