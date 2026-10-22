#Requires -Version 5.1
<#
.SYNOPSIS
    FreeWinly Custom Application Cache Configuration Helper.
.DESCRIPTION
    Adds or removes user-defined application cache definitions in config.json.
    Validates candidate paths and processes by executing a dry-run check through
    freewinly-clean-apps.ps1 to enforce safety rules in a single canonical place.
.PARAMETER Name
    Name or identifier of the custom application.
.PARAMETER Process
    One or more process names (without .exe) used to skip cleanup while running.
.PARAMETER Path
    One or more directory paths (supports %APPDATA%, %LOCALAPPDATA%, %TEMP%, and forward or back slashes).
.PARAMETER MinAgeDays
    Optional minimum file age in days before cleaning files for this application.
.PARAMETER ConfigPath
    Optional path to the configuration JSON file.
.PARAMETER Remove
    Name of a custom application to remove from configuration.
.EXAMPLE
    .\core\freewinly-add-app.ps1
.EXAMPLE
    .\core\freewinly-add-app.ps1 -Name "Spotify" -Process "Spotify" -Path "%LOCALAPPDATA%/Spotify/Data"
.EXAMPLE
    .\core\freewinly-add-app.ps1 -Remove "Spotify"
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$Name,

    [Parameter()]
    [string[]]$Process,

    [Parameter()]
    [string[]]$Path,

    [Parameter()]
    [int]$MinAgeDays = -1,

    [Parameter()]
    [string]$ConfigPath = $null,

    [Parameter()]
    [string]$Remove = $null
)

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$projectRoot = Split-Path -Parent $PSScriptRoot
$modulesDir  = Join-Path $projectRoot "modules"
$cleanAppsModule = Join-Path $modulesDir "freewinly-clean-apps.ps1"

# Dot-source config I/O manager
. (Join-Path $PSScriptRoot "freewinly-config-io.ps1")

$targetConfig = if ($ConfigPath -and (Test-Path -LiteralPath $ConfigPath)) {
    (Resolve-Path -LiteralPath $ConfigPath).Path
} elseif ($ConfigPath) {
    [System.IO.Path]::GetFullPath($ConfigPath)
} else {
    Join-Path $projectRoot "config.json"
}

$defaultConfigTemplate = [PSCustomObject]@{
    countdownSeconds      = 10
    submenuView           = "Hidden"
    expandedModules       = @()
    scheduleType          = "Weekly"
    scheduleDay           = "Sunday"
    scheduleTime          = "12:00"
    preCommands           = @()
    uninstall             = @()
    install               = @()
    postCommands          = @()
    modulesExecutionOrder = [ordered]@{}
}

# 1. Removal workflow
if ($Remove) {
    $cfgRes = Get-SafeConfigFile -Path $targetConfig -DefaultConfig $defaultConfigTemplate
    $cfg = $cfgRes.Config

    if ($cfg -and $cfg.modulesExecutionOrder -and $cfg.modulesExecutionOrder.'freewinly-clean-apps') {
        $cleanAppsBlock = $cfg.modulesExecutionOrder.'freewinly-clean-apps'
        $customApps = $cleanAppsBlock.customApps

        $foundKey = $null
        if ($customApps) {
            $keys = if ($customApps -is [System.Collections.IDictionary]) { $customApps.Keys } else { $customApps.PSObject.Properties.Name }
            foreach ($k in $keys) {
                if ($k.Equals($Remove, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $foundKey = $k
                    break
                }
            }
        }

        if ($foundKey) {
            if ($customApps -is [System.Collections.IDictionary]) {
                $customApps.Remove($foundKey)
            } else {
                $customApps.PSObject.Properties.Remove($foundKey)
            }
            Save-AtomicConfigFile -Path $targetConfig -Config $cfg
            Write-Host "`n[+] Custom application '$foundKey' was removed from config.json." -ForegroundColor Green
            exit 0
        } else {
            Write-Warning "Custom application '$Remove' was not found in config.json."
            exit 1
        }
    } else {
        Write-Warning "freewinly-clean-apps is not configured in '$targetConfig'."
        exit 1
    }
}

$cleanAppsInfo = if (Test-Path -LiteralPath $cleanAppsModule) { & $cleanAppsModule -Action Info } else { $null }
$builtinKeys = [System.Collections.Generic.List[string]]::new()
$reservedNames = [System.Collections.Generic.List[string]]::new()

if ($cleanAppsInfo -and $cleanAppsInfo.DefaultSettings) {
    $rawKeys = if ($cleanAppsInfo.DefaultSettings -is [System.Collections.IDictionary]) {
        $cleanAppsInfo.DefaultSettings.Keys
    } else {
        $cleanAppsInfo.DefaultSettings.PSObject.Properties.Name
    }
    foreach ($k in $rawKeys) {
        if ($k -notin @('minAgeDays', 'customApps')) {
            $builtinKeys.Add($k)
            $reservedNames.Add($k.ToLowerInvariant())
            $appObj = if ($cleanAppsInfo.DefaultSettings -is [System.Collections.IDictionary]) {
                $cleanAppsInfo.DefaultSettings[$k]
            } else {
                $cleanAppsInfo.DefaultSettings.$k
            }
            if ($appObj -and $appObj.process) {
                foreach ($proc in $appObj.process) {
                    $reservedNames.Add($proc.ToLowerInvariant())
                }
            }
        }
    }
}
if ($builtinKeys.Count -eq 0) {
    $builtinKeys.AddRange(@('discord', 'teams', 'slack', 'steam', 'vscode'))
    $reservedNames.AddRange(@('discord', 'teams', 'ms-teams', 'slack', 'steam', 'vscode', 'code', 'visual studio code'))
}

function Test-IsReservedName {
    param([string]$AppName)
    if ([string]::IsNullOrWhiteSpace($AppName)) { return $false }
    $norm = $AppName.Trim().ToLowerInvariant()
    return ($reservedNames -contains $norm)
}

# 2. Interactive prompt workflow (when no parameters supplied)
$isInteractive = [string]::IsNullOrWhiteSpace($Name)

if ($isInteractive) {
    Clear-Host
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "          FreeWinly - Add Custom Application Cache          " -ForegroundColor White
    Write-Host "    Configure user-defined cache paths with safety rules    " -ForegroundColor Gray
    Write-Host "============================================================`n" -ForegroundColor Cyan

    while ($true) {
        $Name = (Read-Host "Application Name (e.g. Spotify, Notion, OBS)").Trim()
        if ([string]::IsNullOrWhiteSpace($Name)) {
            Write-Host "Application name cannot be empty." -ForegroundColor Yellow
            continue
        }
        if (Test-IsReservedName -AppName $Name) {
            Write-Host "Error: '$Name' is reserved by a built-in application. Please choose a different name." -ForegroundColor Red
            continue
        }
        break
    }

    $rawProcs = Read-Host "Process Name(s) to check if running (comma-separated, without .exe, or press Enter if none)"
    $Process = if ($rawProcs) {
        @($rawProcs.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    } else { @() }

    while ($true) {
        $rawPaths = Read-Host "Cache Directory Path(s) (comma-separated, e.g. %LOCALAPPDATA%/Spotify/Data)"
        $Path = if ($rawPaths) {
            @($rawPaths.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        } else { @() }

        if ($Path.Count -eq 0) {
            Write-Host "At least one cache directory path is required." -ForegroundColor Yellow
            continue
        }
        break
    }

    $rawAge = Read-Host "Minimum file age in days (press Enter to inherit global default [3])"
    if ($rawAge -match '^\d+$') {
        $MinAgeDays = [int]$rawAge
    }
}

# 3. Parameter validation
if ([string]::IsNullOrWhiteSpace($Name)) {
    Write-Host "Error: -Name is required." -ForegroundColor Red
    exit 1
}

if (Test-IsReservedName -AppName $Name) {
    Write-Host "Error: '$Name' clashes with a built-in application name. Please specify a different name." -ForegroundColor Red
    exit 1
}

if (-not $Path -or $Path.Count -eq 0) {
    Write-Host "Error: At least one -Path must be specified." -ForegroundColor Red
    exit 1
}

# 4. Construct candidate object
$candidateDef = [ordered]@{
    enabled = $true
    process = if ($Process) { @($Process) } else { @() }
    paths   = @($Path)
}
if ($MinAgeDays -ge 0) {
    $candidateDef['minAgeDays'] = $MinAgeDays
}

Write-Host "`nValidating '$Name' against FreeWinly safety rules..." -ForegroundColor Cyan

# 5. Invoke freewinly-clean-apps.ps1 -Action Check with candidate custom app to validate safety rules
$testSettings = @{
    customApps = @{
        $Name = $candidateDef
    }
}
foreach ($k in $builtinKeys) {
    $testSettings[$k] = $false
}

$outputLines = & $cleanAppsModule -Action Check -Settings $testSettings *>&1
$hasIgnored = $false
$ignoredReason = ""

foreach ($line in $outputLines) {
    $str = $line.ToString()
    if ($str -match '\[App Ignored\]') {
        $hasIgnored = $true
        $ignoredReason = $str
    }
    Write-Host "  $str" -ForegroundColor Gray
}

if ($hasIgnored) {
    Write-Host "`n[Validation Failed] Target path violates FreeWinly safety constraints:" -ForegroundColor Red
    Write-Host "  $ignoredReason`n" -ForegroundColor Yellow
    if ($isInteractive) {
        Read-Host "Press Enter to return"
    }
    exit 1
}

Write-Host "`n[Validation Passed] Safety constraints satisfied." -ForegroundColor Green

# 6. Confirmation and atomic write to config.json
if ($isInteractive) {
    $confirm = Read-Host "`nAdd '$Name' to FreeWinly configuration? (Y/n) [Default: Y]"
    if ($confirm -match '^[Nn]$') {
        Write-Host "`nOperation cancelled. No changes were made." -ForegroundColor Yellow
        Start-Sleep -Milliseconds 600
        exit 0
    }
}

# Load current config
$cfgRes = Get-SafeConfigFile -Path $targetConfig -DefaultConfig $defaultConfigTemplate
$cfg = $cfgRes.Config

if (-not $cfg.modulesExecutionOrder) {
    $cfg | Add-Member -NotePropertyName modulesExecutionOrder -NotePropertyValue ([ordered]@{}) -Force
}

$modOrder = $cfg.modulesExecutionOrder
$cleanAppsEntry = if ($modOrder -is [System.Collections.IDictionary]) {
    $modOrder['freewinly-clean-apps']
} else {
    $modOrder.PSObject.Properties['freewinly-clean-apps']
}

if (-not $cleanAppsEntry) {
    $newEntry = [ordered]@{
        enabled    = $true
        minAgeDays = 3
    }
    foreach ($k in $builtinKeys) {
        $newEntry[$k] = $true
    }
    $newEntry['customApps'] = [ordered]@{}
    if ($modOrder -is [System.Collections.IDictionary]) {
        $modOrder['freewinly-clean-apps'] = $newEntry
    } else {
        $modOrder | Add-Member -NotePropertyName 'freewinly-clean-apps' -NotePropertyValue $newEntry -Force
    }
}

$targetCleanApps = if ($modOrder -is [System.Collections.IDictionary]) {
    $modOrder['freewinly-clean-apps']
} else {
    $modOrder.'freewinly-clean-apps'
}

$custApps = if ($targetCleanApps -is [System.Collections.IDictionary]) {
    $targetCleanApps['customApps']
} else {
    $targetCleanApps.customApps
}

if (-not $custApps) {
    $custApps = [ordered]@{}
    if ($targetCleanApps -is [System.Collections.IDictionary]) {
        $targetCleanApps['customApps'] = $custApps
    } else {
        $targetCleanApps | Add-Member -NotePropertyName customApps -NotePropertyValue $custApps -Force
    }
}

if ($custApps -is [System.Collections.IDictionary]) {
    $custApps[$Name] = $candidateDef
} else {
    $custApps | Add-Member -NotePropertyName $Name -NotePropertyValue $candidateDef -Force
}

Save-AtomicConfigFile -Path $targetConfig -Config $cfg
Write-Host "`n[+] Successfully saved custom application '$Name' to config.json!" -ForegroundColor Green
Start-Sleep -Milliseconds 800
exit 0
