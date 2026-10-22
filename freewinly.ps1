#Requires -Version 5.1
<#
.SYNOPSIS
    FreeWinly v1.4.1 - The Open Source, Bloatware-Free Windows PC Maintenance Engine.
.DESCRIPTION
    A modular, transparent, non-intrusive Windows 11 PC optimization toolchain.
    Designed for casual users via an interactive ASCII tree-view console, and for
    advanced users and AI agents via CLI, headless automation, and standard JSON configuration.
.NOTES
    Author  : LycosLane
    License : MIT
    GitHub  : https://github.com/LycosLane/freewinly
#>

[CmdletBinding()]
param(
    [Parameter()][switch]$Run,
    [Parameter()][switch]$Check,
    [Parameter()][int]$CountdownSeconds = -1,
    [Parameter()][switch]$Audit,
    [Parameter()][string]$ConfigPath = $null,
    [Parameter()][string[]]$Modules = $null,
    [Parameter()][hashtable]$Settings = $null,
    [Parameter()][switch]$HelpMe = $false,
    [Parameter()][switch]$Interactive = $false
)

$ErrorActionPreference = "Continue"

$projectRoot = $PSScriptRoot
$coreDir     = Join-Path $projectRoot "core"
$modulesDir  = Join-Path $projectRoot "modules"
$logsDir     = Join-Path $projectRoot "logs"

if (-not (Test-Path $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}

$dateStamp = (Get-Date).ToString("yyyyMMdd")
$logFile   = Join-Path $logsDir "freewinly-$dateStamp.log"

if (-not $ConfigPath) {
    $ConfigPath = Join-Path $projectRoot "config.json"
}

# Dot-source core services
. (Join-Path $coreDir "freewinly-config-io.ps1")
. (Join-Path $coreDir "freewinly-discovery.ps1")
. (Join-Path $coreDir "freewinly-tui.ps1")

function Show-Banner {
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "         FreeWinly v1.4.1 - Open Source Windows Engine      " -ForegroundColor White
    Write-Host "        Freeing Windows from bloatware, caches & fees       " -ForegroundColor Gray
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Write-Host $Message -ForegroundColor $Color
    Add-Content -Path $logFile -Value "[$timestamp] $Message" -Encoding UTF8
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
    modulesExecutionOrder = $null
}

if ($HelpMe) {
    Show-Banner
    Write-Host @"
CLI Usage:
  .\freewinly.ps1                      Interactive mode (countdown timer, TUI menu, JIT elevation)
  .\freewinly.ps1 -Check               Dry-run preview / diagnostic audit (no changes made)
  .\freewinly.ps1 -Run                 Execute enabled modules immediately (headless)
  .\freewinly.ps1 -CountdownSeconds 0  Run without countdown delay (instant start)
  .\freewinly.ps1 -Audit               Alias for -Check (read-only health & stability audit)
  .\freewinly.ps1 -ConfigPath <file>   Use custom config JSON file
  .\freewinly.ps1 -Modules <list>      Specify modules to run or check (e.g. -Modules freewinly-check-hardware,freewinly-update-software)
  .\freewinly.ps1 -Help                Show this help message

Core Utilities:
  .\core\freewinly-init-config.ps1     Initialize config.json & Winget exclusion wizard
  .\core\freewinly-setup-schedule.ps1  Configure Windows Task Scheduler automation
  .\core\freewinly-setup-launcher.ps1  Manage Start Menu shortcut (Install / Remove / Status)
  .\core\freewinly-setup-path.ps1      Manage User PATH registration (Install / Remove / Toggle / Status)
  .\core\freewinly-add-app.ps1         Register or remove custom desktop app cache definitions
  .\core\freewinly-uninstall.ps1       Cleanly remove FreeWinly from this PC

Standalone Module Invocations:
  .\modules\freewinly-check-hardware.ps1 -Action Check
  .\modules\freewinly-check-eventlog.ps1 -Action Check
  .\modules\freewinly-trim-ssd.ps1 -Action Run -Settings @{ excludedDrives = @('D') }
"@ -ForegroundColor Yellow
    exit 0
}

if ($Audit) {
    $Check = $true
}

$isInteractiveSession = (-not $Run) -or $Interactive

# 1. First-Run Configuration Initialization (if config.json does not exist yet)
if (-not (Test-Path $ConfigPath)) {
    $initScript = Join-Path $coreDir "freewinly-init-config.ps1"
    if (Test-Path $initScript) {
        & $initScript -ConfigPath $ConfigPath
    }
}

$configLoad = Get-SafeConfigFile -Path $ConfigPath -IsInteractive $isInteractiveSession -DefaultConfig $defaultConfigTemplate
$config = $configLoad.Config
$configWasCorrupted = [bool]$configLoad.IsCorrupted

$countdown = if ($CountdownSeconds -ge 0) {
    $CountdownSeconds
} elseif ($config -and $null -ne $config.countdownSeconds) {
    [int]$config.countdownSeconds
} else {
    10
}

if ($Modules -and $Modules.Count -eq 1 -and $Modules[0] -match ',') {
    $Modules = $Modules[0].Split(',') | ForEach-Object { $_.Trim() }
}

# 2. Discover, validate & order modules dynamically
$discovery = Get-DiscoveredModules -ModulesDir $modulesDir -Config $config -ModulesFilter $Modules
$discoveredModules = $discovery.DiscoveredModules
$validFileMap      = $discovery.ValidFileMap
$orderedBaseNames  = $discovery.OrderedBaseNames
$ignoredWarnings   = $discovery.IgnoredWarnings
$submenuView       = $discovery.SubmenuView

function Save-ConfigState {
    if ($configWasCorrupted) {
        Write-Warning "Configuration was corrupted on launch; skipping save to avoid overwriting invalid syntax."
        return
    }

    $modOrder = [ordered]@{}
    foreach ($dm in $discoveredModules) {
        $block = [ordered]@{
            enabled = if ($Modules) { [bool]$dm.ConfigEnabled } else { [bool]$dm.Enabled }
        }
        if ($dm.Settings) {
            if ($dm.BaseName -eq 'freewinly-clean-apps') {
                if ($null -ne $dm.Settings.minAgeDays) {
                    $block['minAgeDays'] = [int]$dm.Settings.minAgeDays
                }
                foreach ($bName in @('discord', 'teams', 'slack', 'steam', 'vscode')) {
                    if ($null -ne $dm.Settings.$bName) {
                        $v = $dm.Settings.$bName
                        $block[$bName] = if ($v -is [bool]) { $v } elseif ($null -ne $v.enabled) { [bool]$v.enabled } else { $true }
                    }
                }
                $block['customApps'] = if ($dm.Settings.customApps) { $dm.Settings.customApps } else { [ordered]@{} }
            } else {
                foreach ($prop in $dm.Settings.PSObject.Properties) {
                    $block[$prop.Name] = $prop.Value
                }
            }
        }
        $modOrder[$dm.BaseName] = $block
    }
    # Preserve valid modules that were hidden due to hardware applicability (e.g., freewinly-defrag-hdd on SSD-only PCs)
    foreach ($baseName in $orderedBaseNames) {
        if (-not $modOrder.Contains($baseName) -and $validFileMap.ContainsKey($baseName)) {
            $existing = if ($config.modulesExecutionOrder) { $config.modulesExecutionOrder.$baseName } else { $null }
            if ($null -ne $existing) {
                $modOrder[$baseName] = $existing
            }
        }
    }
    $config | Add-Member -NotePropertyName countdownSeconds -NotePropertyValue $countdown -Force
    $config | Add-Member -NotePropertyName submenuView -NotePropertyValue $submenuView -Force
    $expandedList = @($discoveredModules | Where-Object { $_.Expanded } | Select-Object -ExpandProperty BaseName)
    $config | Add-Member -NotePropertyName expandedModules -NotePropertyValue $expandedList -Force
    $config | Add-Member -NotePropertyName modulesExecutionOrder -NotePropertyValue ([PSCustomObject]$modOrder) -Force
    if ($config.PSObject.Properties['enabledModules']) {
        $config.PSObject.Properties.Remove('enabledModules')
    }
    if ($config.PSObject.Properties['excluded']) {
        $config.PSObject.Properties.Remove('excluded')
    }
    Save-AtomicConfigFile -Path $ConfigPath -Config $config -Depth 6
}

function Invoke-DryRunCheck {
    param([array]$TargetModules)
    Show-Banner
    if ($ignoredWarnings.Count -gt 0) {
        Write-Host ""
        foreach ($w in $ignoredWarnings) { Write-Host "  $w" -ForegroundColor Yellow }
    }
    Write-Host "`n=== [Dry-Run Check / Diagnostic Audit] Inspecting $($TargetModules.Count) module(s) ===" -ForegroundColor Yellow
    Write-Host "Read-Only mode: No system modifications, updates, or deletions will be performed.`n" -ForegroundColor Gray

    foreach ($m in $TargetModules) {
        try {
            & $m.Path -Action Check -Settings $m.Settings -LogFile $logFile
        } catch {
            Write-Host "Error during check for $($m.Name): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    Write-Host "`n=== Diagnostic Audit & Dry-Run Check Completed Successfully ===" -ForegroundColor Green
}

# 3. DRY-RUN CHECK / AUDIT MODE (-Check or -Audit)
if ($Check) {
    $targetModules = @($discoveredModules | Where-Object { $_.Enabled })
    Invoke-DryRunCheck -TargetModules $targetModules
    exit 0
}

# 4. INTERACTIVE MODE (Only if neither -Run nor -Check was specified)
if (-not $Run) {
    $menuResult = Invoke-InteractiveMenu `
        -DiscoveredModules $discoveredModules `
        -Config $config `
        -ConfigPath $ConfigPath `
        -CoreDir $coreDir `
        -LogFile $logFile `
        -Countdown $countdown `
        -SubmenuView $submenuView `
        -IgnoredWarnings $ignoredWarnings `
        -ValidFileMap $validFileMap `
        -OrderedBaseNames $orderedBaseNames `
        -IsInteractiveSession $isInteractiveSession `
        -ConfigWasCorrupted $configWasCorrupted `
        -DefaultConfigTemplate $defaultConfigTemplate `
        -SaveConfigCallback { Save-ConfigState } `
        -DryRunCallback { param($TargetModules) Invoke-DryRunCheck -TargetModules $TargetModules }

    $countdown = $menuResult.Countdown
    $submenuView = $menuResult.SubmenuView
}

# 5. JUST-IN-TIME (JIT) ELEVATION CHECK
$activeModules = @($discoveredModules | Where-Object { $_.Enabled })
if ($activeModules.Count -eq 0) {
    Write-Host "No modules selected to run. Exiting." -ForegroundColor Yellow
    exit 0
}

# Re-evaluate dynamic properties (e.g. requiresAdmin on network module)
foreach ($m in $activeModules) {
    Update-ModuleDynamicProps -Module $m
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$needsAdmin = ($activeModules | Where-Object { $_.RequiresAdmin -eq $true }).Count -gt 0

if ($needsAdmin -and -not $isAdmin) {
    Save-ConfigState
    Write-Host "`nSelected tasks require Administrator privileges." -ForegroundColor Yellow
    Write-Host "Elevating FreeWinly runner..." -ForegroundColor Cyan
    $selectedNames = ($activeModules | Select-Object -ExpandProperty BaseName) -join ','
    $interactiveArg = if ($isInteractiveSession) { " -Interactive" } else { "" }
    $psHost = try { (Get-Process -Id $PID).Path } catch { $null }
    if (-not $psHost -or -not (Test-Path $psHost)) { $psHost = 'powershell.exe' }
    Start-Process -FilePath $psHost -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Run$interactiveArg -Modules `"$selectedNames`" -ConfigPath `"$ConfigPath`""
    exit 0
}

# 6. EXECUTION PIPELINE
Clear-Host
"==================================================================" | Out-File -FilePath $logFile -Encoding UTF8
Write-Log "FreeWinly v1.4.1 Maintenance Pipeline Started" "Cyan"
"==================================================================" | Add-Content -Path $logFile -Encoding UTF8

$configModified = $false
$settingsSnapshotBefore = ($discoveredModules | Select-Object BaseName, Enabled, Settings | ConvertTo-Json -Depth 5 -Compress)

# 6.0 PRE-COMMANDS HOOK (Enables automated staging of admin tasks by AI assistants / configs)
if ($config -and $config.preCommands -and $config.preCommands.Count -gt 0) {
    Write-Log "`n--- Running Pre-Commands ($($config.preCommands.Count)) ---" "Cyan"
    foreach ($cmd in $config.preCommands) {
        Write-Log "Pre-Command: $cmd" "Cyan"
        try {
            $cmdOut = Invoke-Expression $cmd 2>&1
            $cmdOut | Out-Host
            $cmdOut | Add-Content -Path $logFile -Encoding UTF8
            Write-Log "RESULT: SUCCESS" "Green"
        } catch {
            Write-Log "ERROR: $($_.Exception.Message)" "Red"
        }
    }
    $config.preCommands = @()
    $configModified = $true
}

# 6.1 UNINSTALL HOOK (Facilitates transitioning unmanaged installations to clean WinGet packages)
if ($config -and $config.uninstall -and $config.uninstall.Count -gt 0) {
    Write-Log "`n--- Running Uninstalls ($($config.uninstall.Count)) ---" "Cyan"
    foreach ($id in $config.uninstall) {
        Write-Log "Uninstalling: $id ..." "Cyan"
        $uninstOut = & winget uninstall --id $id --silent --accept-source-agreements 2>&1
        $uninstOut | Out-Host
        $uninstOut | Add-Content -Path $logFile -Encoding UTF8
        Write-Log "RESULT: $id => Uninstalled" "Green"
    }
    $config.uninstall = @()
    $configModified = $true
}

# 6.2 INSTALL HOOK (Facilitates clean WinGet application onboarding)
if ($config -and $config.install -and $config.install.Count -gt 0) {
    Write-Log "`n--- Running Fresh Installs ($($config.install.Count)) ---" "Cyan"
    foreach ($id in $config.install) {
        Write-Log "Installing: $id ..." "Cyan"
        $instOut = & winget install --id $id --silent --accept-package-agreements --accept-source-agreements 2>&1
        $instOut | Out-Host
        $instOut | Add-Content -Path $logFile -Encoding UTF8
        Write-Log "RESULT: $id => Installed" "Green"
    }
    $config.install = @()
    $configModified = $true
}

# 6.3 RUN ENABLED MODULES IN CONFIGURED SEQUENCE
Write-Log "`nExecuting $($activeModules.Count) active maintenance module(s)..." "Cyan"

foreach ($m in $activeModules) {
    try {
        & $m.Path -Action Run -Settings $m.Settings -LogFile $logFile
    } catch {
        Write-Log "Module Error ($($m.Name)): $($_.Exception.Message)" "Red"
    }
}

# 6.4 POST-COMMANDS HOOK
if ($config -and $config.postCommands -and $config.postCommands.Count -gt 0) {
    Write-Log "`n--- Running Post-Commands ($($config.postCommands.Count)) ---" "Cyan"
    foreach ($cmd in $config.postCommands) {
        Write-Log "Post-Command: $cmd" "Cyan"
        try {
            $cmdOut = Invoke-Expression $cmd 2>&1
            $cmdOut | Out-Host
            $cmdOut | Add-Content -Path $logFile -Encoding UTF8
            Write-Log "RESULT: SUCCESS" "Green"
        } catch {
            Write-Log "ERROR: $($_.Exception.Message)" "Red"
        }
    }
    $config.postCommands = @()
    $configModified = $true
}

# Persist if any module updated its Settings (e.g. lastRun or expired postponements)
$settingsSnapshotAfter = ($discoveredModules | Select-Object BaseName, Enabled, Settings | ConvertTo-Json -Depth 5 -Compress)
if ($settingsSnapshotBefore -ne $settingsSnapshotAfter) {
    $configModified = $true
}

if ($configModified -and (Test-Path (Split-Path -Parent $ConfigPath))) {
    Save-ConfigState
    Write-Log "Configuration updated." "Green"
}

Write-Log "`n=== FreeWinly Finished Successfully ===" "Green"
Write-Host "`nLog saved to: $logFile" -ForegroundColor Gray

# Update verified last-good state preservation after run completes without unhandled error
if (-not $configWasCorrupted) {
    Update-LastGoodConfigFile -Path $ConfigPath
}

if ($isInteractiveSession) {
    Read-Host "Press Enter to close this window"
}
