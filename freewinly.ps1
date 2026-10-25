#Requires -Version 5.1
<#
.SYNOPSIS
    FreeWinly v1.5.1 - The Open Source, Bloatware-Free Windows PC Maintenance Engine.
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
    [Parameter()][switch]$Json = $false,
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
    Write-Host "         FreeWinly v1.5.1 - Open Source Windows Engine      " -ForegroundColor White
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
  .\freewinly.ps1 -Check -Json         Machine-readable JSON diagnostic output for AI agents
  .\freewinly.ps1 -Run                 Execute enabled modules immediately (headless)
  .\freewinly.ps1 -CountdownSeconds 0  Run without countdown delay (instant start)
  .\freewinly.ps1 -Audit               Alias for -Check (read-only health & stability audit)
  .\freewinly.ps1 -ConfigPath <file>   Use custom config JSON file
  .\freewinly.ps1 -Modules <list>      Specify modules to run or check (e.g. -Modules freewinly-clean-cache)
  .\freewinly.ps1 -Settings <hash>     Override settings for CLI target module (e.g. -Settings @{ minAgeDays=14 })
  .\freewinly.ps1 -Help                Show this help message

Core Utilities:
  .\core\freewinly-init-config.ps1     Initialize config.json & Winget exclusion wizard
  .\core\freewinly-setup-schedule.ps1  Configure Windows Task Scheduler automation
  .\core\freewinly-setup-launcher.ps1  Manage Start Menu, Desktop & Startup shortcuts
  .\core\freewinly-setup-path.ps1      Manage User PATH registration (Install / Remove / Toggle / Status)
  .\core\freewinly-add-app.ps1         Register or remove custom desktop app cache definitions
  .\core\freewinly-uninstall.ps1       Cleanly remove FreeWinly from this PC
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

# 2. Discover, validate & order modules dynamically (merging CLI -Settings if passed)
$discovery = Get-DiscoveredModules -ModulesDir $modulesDir -Config $config -ModulesFilter $Modules -CliSettings $Settings
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
                $appKeys = if ($dm.Settings -is [System.Collections.IDictionary]) {
                    $dm.Settings.Keys
                } else {
                    $dm.Settings.PSObject.Properties.Name
                }
                foreach ($k in $appKeys) {
                    if ($k -notin @('minAgeDays', 'customApps')) {
                        $v = $dm.Settings.$k
                        $block[$k] = if ($v -is [bool]) { $v } elseif ($null -ne $v.enabled) { [bool]$v.enabled } else { $true }
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
    param(
        [array]$TargetModules,
        [switch]$AsJson = $false
    )

    if ($AsJson) {
        $jsonResult = [ordered]@{
            tool      = "FreeWinly"
            version   = "1.5.1"
            timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            modules   = @()
        }
        foreach ($m in $TargetModules) {
            $rawOutput = try {
                $checkOut = & {
                    $origInfo = $InformationPreference
                    $InformationPreference = 'SilentlyContinue'
                    try {
                        (& $m.Path -Action Check -Settings $m.Settings -LogFile $logFile 6>$null)
                    } finally {
                        $InformationPreference = $origInfo
                    }
                } 2>&1 | Out-String
                $checkOut.Trim()
            } catch {
                "Error: $($_.Exception.Message)"
            }
            $jsonResult.modules += [ordered]@{
                baseName    = $m.BaseName
                name        = $m.Name
                description = $m.Description
                output      = $rawOutput
            }
        }
        $jsonResult | ConvertTo-Json -Depth 6
        return
    }

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

# Security Gate: Prompt injection protection for custom elevated commands
function Invoke-SecuredCommandsHook {
    param(
        [string]$HookName,
        [array]$Commands,
        [bool]$IsInteractive,
        [string]$TargetLogFile
    )
    if (-not $Commands -or $Commands.Count -eq 0) { return @() }

    # Headless protection: Refuse arbitrary elevated command execution without interactive human consent
    if (-not $IsInteractive) {
        Write-Log "`n[SECURITY BLOCKED] Execution of $($Commands.Count) $HookName command(s) was blocked in headless mode for safety." "Red"
        Write-Log "Arbitrary commands in config.json require interactive human confirmation to prevent indirect prompt injection." "Yellow"
        return $Commands
    }

    Write-Host "`n============================================================" -ForegroundColor Yellow
    Write-Host "   [SECURITY GATE] Elevated Custom Commands Authorization   " -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host "The following $HookName command(s) are configured to execute as Administrator:" -ForegroundColor Gray
    foreach ($cmd in $Commands) {
        Write-Host "  > $cmd" -ForegroundColor Yellow
    }
    Write-Host "`nTo protect against indirect AI prompt injections and unauthorized scripts," -ForegroundColor Gray
    Write-Host "custom elevated commands require your explicit authorization." -ForegroundColor Gray

    $auth = Read-Host "`nAuthorize executing these command(s) as Administrator? (y/N)"
    if ($auth -notmatch '^[Yy]$') {
        Write-Log "Execution of $HookName rejected by user." "Yellow"
        return $Commands
    }

    Write-Log "`n--- Running Authorized $HookName ($($Commands.Count)) ---" "Cyan"
    foreach ($cmd in $Commands) {
        Write-Log "Running: $cmd" "Cyan"
        try {
            $cmdOut = Invoke-Expression $cmd 2>&1
            $cmdOut | Out-Host
            $cmdOut | Add-Content -Path $TargetLogFile -Encoding UTF8
            Write-Log "RESULT: SUCCESS" "Green"
        } catch {
            Write-Log "ERROR: $($_.Exception.Message)" "Red"
        }
    }
    return @()
}

# 3. DRY-RUN CHECK / AUDIT MODE (-Check or -Audit)
if ($Check) {
    $targetModules = @($discoveredModules | Where-Object { $_.Enabled })
    Invoke-DryRunCheck -TargetModules $targetModules -AsJson:$Json
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
    Write-Host "Launching elevated FreeWinly runner in a new window..." -ForegroundColor Cyan
    $selectedNames = ($activeModules | Select-Object -ExpandProperty BaseName) -join ','
    $psHost = try { (Get-Process -Id $PID).Path } catch { $null }
    if (-not $psHost -or -not (Test-Path $psHost)) { $psHost = 'powershell.exe' }

    # Array argument passing avoids command-line quoting/escaping issues with spaces in paths
    $elevationArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-Run')
    if ($isInteractiveSession) { $elevationArgs += '-Interactive' }
    if ($selectedNames) { $elevationArgs += @('-Modules', $selectedNames) }
    if ($ConfigPath) { $elevationArgs += @('-ConfigPath', $ConfigPath) }

    Start-Process -FilePath $psHost -Verb RunAs -ArgumentList $elevationArgs
    exit 0
}

# 6. EXECUTION PIPELINE
Clear-Host
"==================================================================" | Out-File -FilePath $logFile -Encoding UTF8
Write-Log "FreeWinly v1.5.1 Maintenance Pipeline Started" "Cyan"
"==================================================================" | Add-Content -Path $logFile -Encoding UTF8

$configModified = $false
$moduleErrors = 0
$settingsSnapshotBefore = ($discoveredModules | Select-Object BaseName, Enabled, Settings | ConvertTo-Json -Depth 5 -Compress)

# 6.0 PRE-COMMANDS HOOK (With Prompt Injection Security Firewall)
if ($config -and $config.preCommands -and $config.preCommands.Count -gt 0) {
    $remainingPre = Invoke-SecuredCommandsHook -HookName "preCommands" -Commands $config.preCommands -IsInteractive $isInteractiveSession -TargetLogFile $logFile
    if ($remainingPre.Count -ne $config.preCommands.Count) {
        $config.preCommands = $remainingPre
        $configModified = $true
    }
}

# 6.1 UNINSTALL HOOK (Facilitates transitioning unmanaged installations to clean WinGet packages)
if ($config -and $config.uninstall -and $config.uninstall.Count -gt 0) {
    Write-Log "`n--- Running Uninstalls ($($config.uninstall.Count)) ---" "Cyan"
    foreach ($id in $config.uninstall) {
        Write-Log "Uninstalling: $id ..." "Cyan"
        $uninstOut = & winget uninstall --id $id --silent --accept-source-agreements --disable-interactivity 2>&1
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
        $instOut = & winget install --id $id --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1
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
        $moduleErrors++
        Write-Log "Module Error ($($m.Name)): $($_.Exception.Message)" "Red"
    }
}

# 6.4 POST-COMMANDS HOOK (With Prompt Injection Security Firewall)
if ($config -and $config.postCommands -and $config.postCommands.Count -gt 0) {
    $remainingPost = Invoke-SecuredCommandsHook -HookName "postCommands" -Commands $config.postCommands -IsInteractive $isInteractiveSession -TargetLogFile $logFile
    if ($remainingPost.Count -ne $config.postCommands.Count) {
        $config.postCommands = $remainingPost
        $configModified = $true
    }
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

if ($moduleErrors -eq 0) {
    Write-Log "`n=== FreeWinly Finished Successfully ===" "Green"
} else {
    Write-Log "`n=== FreeWinly Finished with $moduleErrors Module Warning(s)/Error(s) ===" "Yellow"
}
Write-Host "`nLog saved to: $logFile" -ForegroundColor Gray

# Update verified last-good state preservation after run completes without unhandled error
if (-not $configWasCorrupted -and $moduleErrors -eq 0) {
    Update-LastGoodConfigFile -Path $ConfigPath
}

if ($isInteractiveSession) {
    Read-Host "Press Enter to close this window"
} else {
    # Deterministic exit code for CI/CD and automation
    if ($moduleErrors -gt 0) { exit 1 } else { exit 0 }
}
