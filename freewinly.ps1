#Requires -Version 5.1
<#
.SYNOPSIS
    FreeWinly - The Open Source, Bloatware-Free Windows PC Maintenance Engine.
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
    [Parameter()][switch]$Interactive = $false,
    [Parameter()][ValidateSet('Standard', 'Advanced')][string]$OutputMode = $null,
    [Parameter()][switch]$SkipHooks = $false
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
} elseif (-not [System.IO.Path]::IsPathRooted($ConfigPath)) {
    $ConfigPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).ProviderPath $ConfigPath))
}

# Dot-source core services
. (Join-Path $coreDir "freewinly-version.ps1")
. (Join-Path $coreDir "freewinly-config-io.ps1")
. (Join-Path $coreDir "freewinly-discovery.ps1")
. (Join-Path $coreDir "freewinly-tui.ps1")

# Cleanly normalize legacy Windows Administrator console DarkBlue if detected
Initialize-ConsoleTheme

function Show-Banner {
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host "         FreeWinly v$FreeWinlyVersion - Open Source Windows Engine      " -ForegroundColor Cyan
    Write-Host "        Freeing Windows from bloatware, caches & fees       " -ForegroundColor Gray
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkCyan
}

function Get-ActiveWingetExclusions {
    param($ExcludedSource)
    $today = (Get-Date).Date
    $res = [System.Collections.Generic.List[string]]::new()
    if (-not $ExcludedSource) { return @() }
    foreach ($item in $ExcludedSource) {
        if ($item -is [string]) {
            if (-not [string]::IsNullOrWhiteSpace($item)) {
                $res.Add($item)
            }
        } elseif ($item -and $item.id) {
            $untilDate = if ($item.until) { try { [datetime]$item.until } catch { $null } } else { $null }
            if (-not $untilDate -or $today -le $untilDate) {
                $res.Add([string]$item.id)
            }
        }
    }
    return @($res)
}

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Write-Host $Message -ForegroundColor $Color
    Add-Content -LiteralPath $logFile -Value "[$timestamp] $Message" -Encoding UTF8
}

$defaultConfigTemplate = [PSCustomObject]@{
    countdownSeconds      = 10
    submenuView           = "Hidden"
    outputMode            = "Standard"
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
  .\core\freewinly-self-update.ps1     Opt-in check and self-update for FreeWinly (Check / Update)
  .\core\freewinly-uninstall.ps1       Cleanly remove FreeWinly from this PC
"@ -ForegroundColor Yellow
    exit 0
}

if ($Audit) {
    $Check = $true
}

$isInteractiveSession = ((-not $Run -and -not $Check) -or $Interactive) -and (-not $Json)

# 1. First-Run Configuration Initialization (if config.json is missing or empty, skip during -Check)
$configNeedsInit = (-not (Test-Path -LiteralPath $ConfigPath)) -or [string]::IsNullOrWhiteSpace((Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction SilentlyContinue))
if ($configNeedsInit -and -not $Check) {
    $initScript = Join-Path $coreDir "freewinly-init-config.ps1"
    if (Test-Path -LiteralPath $initScript) {
        if ($isInteractiveSession) {
            & $initScript -ConfigPath $ConfigPath
        } else {
            & $initScript -ConfigPath $ConfigPath -NonInteractive
        }
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

if ($Modules -and $Modules.Count -gt 0) {
    $Modules = @($Modules | ForEach-Object { $_.Split(',') } | ForEach-Object { $_.Trim() -replace '\.ps1$', '' } | Where-Object { $_ })
}

# 2. Discover, validate & order modules dynamically (merging CLI -Settings if passed)
$discovery = Get-DiscoveredModules -ModulesDir $modulesDir -Config $config -ModulesFilter $Modules -CliSettings $Settings -Quiet:$Json
$discoveredModules = $discovery.DiscoveredModules
$validFileMap      = $discovery.ValidFileMap
$orderedBaseNames  = $discovery.OrderedBaseNames
$ignoredWarnings   = $discovery.IgnoredWarnings
$submenuView       = $discovery.SubmenuView
$outputMode        = if ($OutputMode) { $OutputMode } elseif ($config -and $config.outputMode -eq 'Advanced') { 'Advanced' } else { 'Standard' }

function Save-ConfigState {
    param(
        [int]$NewCountdown = $script:countdown,
        [string]$NewSubmenuView = $script:submenuView,
        [string]$NewOutputMode = $script:outputMode
    )

    if ($configWasCorrupted) {
        Write-Warning "Configuration was corrupted on launch; skipping save to avoid overwriting invalid syntax."
        return
    }

    $script:countdown   = $NewCountdown
    $script:submenuView = $NewSubmenuView
    $script:outputMode  = $NewOutputMode

    # Snapshot in-memory hook lists only if this session modified them, so external edits are preserved
    $hookSnapPre   = if ($script:modifiedHooks.preCommands  -and $script:config -and $null -ne $script:config.preCommands)  { @($script:config.preCommands) }  else { $null }
    $hookSnapUn    = if ($script:modifiedHooks.uninstall    -and $script:config -and $null -ne $script:config.uninstall)    { @($script:config.uninstall) }    else { $null }
    $hookSnapIn    = if ($script:modifiedHooks.install      -and $script:config -and $null -ne $script:config.install)      { @($script:config.install) }      else { $null }
    $hookSnapPost  = if ($script:modifiedHooks.postCommands -and $script:config -and $null -ne $script:config.postCommands) { @($script:config.postCommands) } else { $null }

    # Reload latest non-corrupted config from disk so sub-tools (schedule, wizard, custom apps) are preserved
    if (Test-Path -LiteralPath $ConfigPath) {
        $freshLoad = Get-SafeConfigFile -Path $ConfigPath -IsInteractive $false -DefaultConfig $defaultConfigTemplate
        if (-not $freshLoad.IsCorrupted -and $null -ne $freshLoad.Config) {
            $script:config = $freshLoad.Config
        }
    }

    if ($null -ne $hookSnapPre)  { $script:config | Add-Member -NotePropertyName preCommands  -NotePropertyValue @($hookSnapPre)  -Force }
    if ($null -ne $hookSnapUn)   { $script:config | Add-Member -NotePropertyName uninstall    -NotePropertyValue @($hookSnapUn)   -Force }
    if ($null -ne $hookSnapIn)   { $script:config | Add-Member -NotePropertyName install      -NotePropertyValue @($hookSnapIn)   -Force }
    if ($null -ne $hookSnapPost) { $script:config | Add-Member -NotePropertyName postCommands -NotePropertyValue @($hookSnapPost) -Force }

    $dmByBase = @{}
    foreach ($dm in $discoveredModules) {
        $dmByBase[$dm.BaseName] = $dm
    }

    $modOrder = [ordered]@{}
    $basesToWrite = [System.Collections.Generic.List[string]]::new()
    foreach ($dm in $discoveredModules) {
        if (-not $basesToWrite.Contains($dm.BaseName)) { $basesToWrite.Add($dm.BaseName) }
    }
    foreach ($ob in $orderedBaseNames) {
        if (-not $basesToWrite.Contains($ob)) { $basesToWrite.Add($ob) }
    }
    $script:orderedBaseNames.Clear()
    foreach ($b in $basesToWrite) { $script:orderedBaseNames.Add($b) }

    foreach ($baseName in $basesToWrite) {
        if ($dmByBase.ContainsKey($baseName)) {
            $dm = $dmByBase[$baseName]
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
        } elseif ($validFileMap.ContainsKey($baseName)) {
            $existing = if ($config.modulesExecutionOrder) { $config.modulesExecutionOrder.$baseName } else { $null }
            if ($null -ne $existing) {
                $modOrder[$baseName] = $existing
            }
        }
    }
    # Append any reordered active modules that were added dynamically
    foreach ($dm in $discoveredModules) {
        if (-not $modOrder.Contains($dm.BaseName)) {
            $modOrder[$dm.BaseName] = [ordered]@{ enabled = if ($Modules) { [bool]$dm.ConfigEnabled } else { [bool]$dm.Enabled } }
        }
    }
    $config | Add-Member -NotePropertyName countdownSeconds -NotePropertyValue $countdown -Force
    $config | Add-Member -NotePropertyName submenuView -NotePropertyValue $submenuView -Force
    $config | Add-Member -NotePropertyName outputMode -NotePropertyValue $outputMode -Force
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
        [switch]$AsJson = $false,
        [string]$CurrentOutputMode = "Standard"
    )

    if ($AsJson) {
        $jsonResult = [ordered]@{
            tool      = "FreeWinly"
            version   = $FreeWinlyVersion
            timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            modules   = @()
        }
        foreach ($m in $TargetModules) {
            $rawOutput = try {
                $checkOut = (& $m.Path -Action Check -Settings $m.Settings -LogFile $logFile) *>&1 | Out-String
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
    Write-Host "`n=== [Dry-Run Check / Diagnostic Audit] Inspecting $($TargetModules.Count) module(s) [$CurrentOutputMode Mode] ===" -ForegroundColor Cyan
    Write-Host "Read-Only mode: No system modifications, updates, or deletions will be performed.`n" -ForegroundColor Gray
    $env:FREEWINLY_OUTPUT_MODE = $CurrentOutputMode

    if ($CurrentOutputMode -eq 'Standard') {
        $totalCount = $TargetModules.Count
        $totalDigits = "$totalCount".Length
        $step = 0
        foreach ($m in $TargetModules) {
            $step++
            $stepStr = "$step".PadLeft($totalDigits)
            $stepPrefix = "[ $stepStr/$totalCount ]"
            $paddedName = "$($m.Name)".PadRight(35, '.')
            Write-Host "  $stepPrefix $paddedName " -NoNewline -ForegroundColor White

            if ($m.BaseName -eq 'freewinly-update-software') {
                if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
                    Write-Host "[ Notice ] " -NoNewline -ForegroundColor Yellow
                    Write-Host "(Winget CLI not available)" -ForegroundColor Gray
                    continue
                }
                try {
                    $avail = & $m.Path -Action Scan
                    $cleanSettings = if ($m.Settings) { $m.Settings } else { @{} }
                    $activeExcludes = Get-ActiveWingetExclusions -ExcludedSource $cleanSettings.excluded
                    $toUpdate = @($avail | Where-Object {
                        $id = $_.Id
                        $name = $_.Name
                        -not ($activeExcludes | Where-Object { $id -eq $_ -or $name -match [regex]::Escape($_) })
                    })
                    if ($toUpdate.Count -eq 0) {
                        Write-Host "[ OK ] " -NoNewline -ForegroundColor Green
                        Write-Host "(All packages up to date)" -ForegroundColor Gray
                    } else {
                        Write-Host "[ $($toUpdate.Count) Pending Update$(if ($toUpdate.Count -gt 1) { 's' }) ]" -ForegroundColor Yellow
                        $subIndent = "  " + "".PadRight($stepPrefix.Length + 1)
                        foreach ($pkg in $toUpdate) {
                            $appName = $pkg.Name
                            if ($appName.Length -gt 24) { $appName = $appName.Substring(0, 21) + "..." }
                            $padApp = "$subIndent- $appName".PadRight(35 + $subIndent.Length)
                            $oldVer = "$($pkg.InstalledVersion)".PadRight(10)
                            $newVer = "$($pkg.AvailableVersion)".PadRight(12)
                            Write-Host "$padApp $oldVer -> $newVer " -NoNewline -ForegroundColor White
                            Write-Host "[ Update Available ]" -ForegroundColor Yellow
                        }
                        Write-Host "  $stepPrefix $paddedName " -NoNewline -ForegroundColor White
                        Write-Host "[ OK ] " -NoNewline -ForegroundColor Green
                        Write-Host "($($toUpdate.Count) pending)" -ForegroundColor Gray
                    }
                } catch {
                    Write-Host "[ Error ]" -ForegroundColor Red
                    Add-Content -LiteralPath $logFile -Value "Error during check for $($m.Name): $($_.Exception.Message)" -Encoding UTF8
                }
            } else {
                try {
                    $outLines = & $m.Path -Action Check -Settings $m.Settings -LogFile $logFile *>&1
                    $outText = ($outLines | Out-String)
                    if (-not [string]::IsNullOrWhiteSpace($outText)) {
                        Add-Content -LiteralPath $logFile -Value $outText.TrimEnd() -Encoding UTF8
                    }
                    if ($outText -match '(?<!0\s+)\b(Exception|Failed|Error)\b' -and $outText -notmatch 'Zero broken|0 errors|0 failed') {
                        Write-Host "[ Notice ]" -ForegroundColor Yellow
                    } else {
                        Write-Host "[ OK ]" -ForegroundColor Green
                    }
                } catch {
                    Write-Host "[ Error ]" -ForegroundColor Red
                    Add-Content -LiteralPath $logFile -Value "Error during check for $($m.Name): $($_.Exception.Message)" -Encoding UTF8
                }
            }
        }
    } else {
        foreach ($m in $TargetModules) {
            try {
                & $m.Path -Action Check -Settings $m.Settings -LogFile $logFile
            } catch {
                Write-Host "Error during check for $($m.Name): $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
    Write-Host "`n=== Diagnostic Audit & Dry-Run Check Completed Successfully ===" -ForegroundColor Green
    Write-Host "Detailed report and raw output saved to: $logFile" -ForegroundColor Gray
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
    $remaining = [System.Collections.Generic.List[string]]::new()
    foreach ($cmd in $Commands) {
        Write-Log "Running: $cmd" "Cyan"
        try {
            $global:LASTEXITCODE = 0
            $cmdOut = Invoke-Expression $cmd 2>&1
            $cmdOk = $?
            $cmdExit = $LASTEXITCODE
            if ($outputMode -eq 'Advanced') { $cmdOut | Out-Host }
            $cmdStr = ($cmdOut | Out-String)
            if (-not [string]::IsNullOrWhiteSpace($cmdStr)) {
                Add-Content -LiteralPath $TargetLogFile -Value $cmdStr.TrimEnd() -Encoding UTF8
            }
            if ($cmdOk -and ($null -eq $cmdExit -or $cmdExit -eq 0)) {
                Write-Log "RESULT: SUCCESS" "Green"
            } else {
                $script:moduleErrors++
                $remaining.Add($cmd)
                Write-Log "RESULT: FAILED (ExitCode $cmdExit)" "Red"
            }
        } catch {
            $script:moduleErrors++
            $remaining.Add($cmd)
            Write-Log "ERROR: $($_.Exception.Message)" "Red"
        }
    }
    return , @($remaining)
}

# Security Gate: Package identifier validation & prompt injection protection for software onboarding
function Invoke-SecuredPackagesHook {
    param(
        [string]$HookName,
        [array]$PackageIds,
        [bool]$IsInteractive,
        [string]$OutputMode,
        [string]$TargetLogFile
    )
    if (-not $PackageIds -or $PackageIds.Count -eq 0) { return @() }

    # Headless protection: Refuse package install/uninstall hooks without interactive human consent
    if (-not $IsInteractive) {
        Write-Log "`n[SECURITY BLOCKED] Execution of $($PackageIds.Count) $HookName package(s) was blocked in headless mode for safety." "Red"
        Write-Log "Package operations in config.json require interactive human confirmation." "Yellow"
        return $PackageIds
    }

    $packageIdRegex = '^[A-Za-z0-9\._+-]+(\.[A-Za-z0-9\._+-]+)*$|^[A-Za-z0-9]{12}$'

    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host "     [SECURITY GATE] Software $HookName Authorization       " -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "The following $HookName package ID(s) are configured in config.json:" -ForegroundColor Gray
    foreach ($id in $PackageIds) {
        Write-Host "  > $id" -ForegroundColor White
    }

    $auth = Read-Host "`nAuthorize $HookName of these package(s)? (y/N)"
    if ($auth -notmatch '^[Yy]$') {
        Write-Log "Execution of $HookName rejected by user." "Yellow"
        return $PackageIds
    }

    Write-Log "`n--- Running Authorized $HookName ($($PackageIds.Count)) ---" "Cyan"
    $actionVerb = if ($HookName -eq 'Uninstall') { 'uninstall' } else { 'install' }
    $remaining = [System.Collections.Generic.List[string]]::new()
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        $script:moduleErrors++
        Write-Log "ERROR: Winget CLI is not available on this system. Skipping $HookName hook." "Red"
        return , @($PackageIds)
    }
    foreach ($id in $PackageIds) {
        if ($id -notmatch $packageIdRegex) {
            $script:moduleErrors++
            $remaining.Add($id)
            Write-Log "WARNING: Invalid package identifier '$id'. Skipping for security." "Red"
            continue
        }
        Write-Log "$($HookName)ing: $id ..." "Cyan"
        $wingetArgs = if ($actionVerb -eq 'uninstall') {
            @('uninstall', '--id', $id, '--exact', '--silent', '--accept-source-agreements', '--disable-interactivity')
        } else {
            @('install', '--id', $id, '--exact', '--silent', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
        }
        $origWingetEnc = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
            $global:LASTEXITCODE = 0
            $procOut = & winget @wingetArgs 2>&1
            $pkgExit = $LASTEXITCODE
        } finally {
            [Console]::OutputEncoding = $origWingetEnc
        }
        if ($OutputMode -eq 'Advanced') { $procOut | Out-Host }
        $procStr = ($procOut | Out-String)
        if (-not [string]::IsNullOrWhiteSpace($procStr)) {
            Add-Content -LiteralPath $TargetLogFile -Value $procStr.TrimEnd() -Encoding UTF8
        }
        if ($pkgExit -eq 0) {
            Write-Log "RESULT: $id => Completed" "Green"
        } else {
            $script:moduleErrors++
            $remaining.Add($id)
            Write-Log "RESULT: $id => Failed (ExitCode $pkgExit)" "Red"
        }
    }
    return , @($remaining)
}

# 3. DRY-RUN CHECK / AUDIT MODE (-Check or -Audit)
if ($Check) {
    $targetModules = @($discoveredModules | Where-Object { $_.Enabled })
    Invoke-DryRunCheck -TargetModules $targetModules -AsJson:$Json -CurrentOutputMode $outputMode
    exit 0
}

# 4. INTERACTIVE MODE (Only if neither -Run nor -Check was specified)
if (-not $Run) {
    $menuResult = Invoke-InteractiveMenu `
        -DiscoveredModules $discoveredModules `
        -Config $config `
        -ConfigPath $ConfigPath `
        -CoreDir $coreDir `
        -ModulesDir $modulesDir `
        -LogFile $logFile `
        -Countdown $countdown `
        -SubmenuView $submenuView `
        -OutputMode $outputMode `
        -IgnoredWarnings $ignoredWarnings `
        -ValidFileMap $validFileMap `
        -OrderedBaseNames $orderedBaseNames `
        -IsInteractiveSession $isInteractiveSession `
        -ConfigWasCorrupted $configWasCorrupted `
        -DefaultConfigTemplate $defaultConfigTemplate `
        -SaveConfigCallback { param($Countdown, $SubmenuView, $OutputMode) Save-ConfigState -NewCountdown $Countdown -NewSubmenuView $SubmenuView -NewOutputMode $OutputMode } `
        -DryRunCallback { param($TargetModules, $OutputMode) Invoke-DryRunCheck -TargetModules $TargetModules -CurrentOutputMode $OutputMode }

    $countdown   = $menuResult.Countdown
    $submenuView = $menuResult.SubmenuView
    if ($menuResult.OutputMode) { $outputMode = $menuResult.OutputMode }

    if ($menuResult.Action -eq 'Restart') {
        Write-Host "`nRestarting FreeWinly with updated files..." -ForegroundColor Cyan
        $psHost = try { (Get-Process -Id $PID).Path } catch { $null }
        if (-not $psHost -or -not (Test-Path $psHost)) { $psHost = 'powershell.exe' }
        $restartArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
        if ($ConfigPath) { $restartArgs += @('-ConfigPath', $ConfigPath) }
        if ($outputMode) { $restartArgs += @('-OutputMode', $outputMode) }
        & $psHost @restartArgs
        exit $LASTEXITCODE
    }
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
$needsAdmin = @($activeModules | Where-Object { $_.RequiresAdmin -eq $true }).Count -gt 0

if ($needsAdmin -and -not $isAdmin) {
    if ($Settings) {
        Write-Host "`n[ERROR] CLI -Settings overrides cannot be forwarded across UAC elevation." -ForegroundColor Red
        Write-Host "Please re-run this command from an elevated Administrator terminal." -ForegroundColor Yellow
        exit 1
    }
    if (-not $Modules) {
        Save-ConfigState
    }
    Write-Host "`nSelected tasks require Administrator privileges." -ForegroundColor Yellow
    Write-Host "Launching elevated FreeWinly runner in a new window..." -ForegroundColor Cyan
    $selectedNames = ($activeModules | Select-Object -ExpandProperty BaseName) -join ','
    $psHost = try { (Get-Process -Id $PID).Path } catch { $null }
    if (-not $psHost -or -not (Test-Path $psHost)) { $psHost = 'powershell.exe' }

    # Embed quotes around path arguments so spaces in install paths or ConfigPath never break PS 5.1 Start-Process
    $elevationArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Run')
    if ($isInteractiveSession) { $elevationArgs += '-Interactive' }
    if ($SkipHooks) { $elevationArgs += '-SkipHooks' }
    if ($selectedNames) { $elevationArgs += @('-Modules', "`"$selectedNames`"") }
    if ($ConfigPath) { $elevationArgs += @('-ConfigPath', "`"$ConfigPath`"") }
    if ($outputMode) { $elevationArgs += @('-OutputMode', $outputMode) }

    try {
        if ($isInteractiveSession) {
            Start-Process -FilePath $psHost -Verb RunAs -ArgumentList $elevationArgs -ErrorAction Stop
            exit 0
        } else {
            $proc = Start-Process -FilePath $psHost -Verb RunAs -Wait -PassThru -ArgumentList $elevationArgs -ErrorAction Stop
            exit $proc.ExitCode
        }
    } catch {
        Write-Host "`nAdministrator elevation was cancelled or rejected by user." -ForegroundColor Yellow
        Write-Host "Elevated maintenance cannot continue without authorization." -ForegroundColor Gray
        exit 1
    }
}

# 6. EXECUTION PIPELINE
Initialize-ConsoleTheme
Clear-Host
"------------------------------------------------------------------" | Add-Content -LiteralPath $logFile -Encoding UTF8
Write-Log "FreeWinly v$FreeWinlyVersion Maintenance Pipeline Started [$outputMode Mode]" "Cyan"
"------------------------------------------------------------------" | Add-Content -LiteralPath $logFile -Encoding UTF8

$configModified = $false
$script:modifiedHooks = @{
    preCommands  = $false
    uninstall    = $false
    install      = $false
    postCommands = $false
}
$moduleErrors = 0
$settingsSnapshotBefore = ($discoveredModules | Select-Object BaseName, Enabled, Settings | ConvertTo-Json -Depth 6 -Compress)

# 6.0 PRE-COMMANDS HOOK (With Prompt Injection Security Firewall)
if (-not $SkipHooks -and $config -and $config.preCommands -and $config.preCommands.Count -gt 0) {
    $remainingPre = @(Invoke-SecuredCommandsHook -HookName "preCommands" -Commands $config.preCommands -IsInteractive $isInteractiveSession -TargetLogFile $logFile)
    if ($remainingPre.Count -ne $config.preCommands.Count) {
        $config.preCommands = $remainingPre
        $script:modifiedHooks.preCommands = $true
        $configModified = $true
    }
}

# 6.1 UNINSTALL HOOK (Facilitates transitioning unmanaged installations to clean WinGet packages)
if (-not $SkipHooks -and $config -and $config.uninstall -and $config.uninstall.Count -gt 0) {
    $remainingUninst = @(Invoke-SecuredPackagesHook -HookName "Uninstall" -PackageIds $config.uninstall -IsInteractive $isInteractiveSession -OutputMode $outputMode -TargetLogFile $logFile)
    if ($remainingUninst.Count -ne $config.uninstall.Count) {
        $config.uninstall = $remainingUninst
        $script:modifiedHooks.uninstall = $true
        $configModified = $true
    }
}

# 6.2 INSTALL HOOK (Facilitates clean WinGet application onboarding)
if (-not $SkipHooks -and $config -and $config.install -and $config.install.Count -gt 0) {
    $remainingInst = @(Invoke-SecuredPackagesHook -HookName "Install" -PackageIds $config.install -IsInteractive $isInteractiveSession -OutputMode $outputMode -TargetLogFile $logFile)
    if ($remainingInst.Count -ne $config.install.Count) {
        $config.install = $remainingInst
        $script:modifiedHooks.install = $true
        $configModified = $true
    }
}

function Get-WingetNoticeInfo {
    param([int]$ExitCode, [string]$OutputText)
    if ($ExitCode -eq -2147009240 -or $OutputText -match '0x80073d28|administrator privileges are required|elevation required') {
        return @{ Text = 'Requires Admin'; NeedsAdmin = $true }
    } elseif ($OutputText -match 'different from the current version installed|different install technology') {
        return @{ Text = 'Manual install needed'; NeedsAdmin = $false }
    } elseif ($ExitCode -eq -1978335189) {
        return @{ Text = 'No applicable update'; NeedsAdmin = $false }
    } elseif ($ExitCode -eq -1978335212) {
        return @{ Text = 'App in use - close and retry'; NeedsAdmin = $false }
    } elseif ($ExitCode -eq 1618) {
        return @{ Text = 'Another installer running'; NeedsAdmin = $false }
    } elseif ($ExitCode -eq 3010) {
        return @{ Text = 'Restart required'; NeedsAdmin = $false }
    }
    return @{ Text = "ExitCode $ExitCode"; NeedsAdmin = $false }
}

function Get-ModuleNoticeSummary {
    param([PSCustomObject]$Module, [string]$OutputText)
    if (-not $OutputText) {
        return [PSCustomObject]@{ HasNotice = $false; Reason = $null; Retryable = $false; NeedsAdmin = $false }
    }

    if ($Module.BaseName -in @('freewinly-clean-browsers', 'freewinly-clean-apps')) {
        $skippedApps = [System.Collections.Generic.List[string]]::new()
        foreach ($line in ($OutputText -split '\r?\n')) {
            if ($line -match 'Skipped\s+(.+?)\s*\(Application is open') {
                $skippedApps.Add($matches[1].Trim())
            } elseif ($line -match '\[Skipped\]\s+(.+?)\s+is currently running') {
                $skippedApps.Add($matches[1].Trim())
            }
        }
        if ($skippedApps.Count -gt 0) {
            return [PSCustomObject]@{
                HasNotice  = $true
                Reason     = "Skipped (open): $($skippedApps -join ', ') - close and press R to retry"
                Retryable  = $true
                NeedsAdmin = $false
            }
        }
    }

    if ($Module.BaseName -eq 'freewinly-check-eventlog' -and $OutputText -match 'Found\s+(\d+)\s+recurring error pattern') {
        $evCount = $matches[1]
        $examples = [System.Collections.Generic.List[string]]::new()
        foreach ($line in ($OutputText -split '\r?\n')) {
            if ($line -match "Application\s+'([^']+)'\s+is crashing") {
                if (-not $examples.Contains($matches[1])) { $examples.Add($matches[1]) }
            } elseif ($line -match 'Sample:\s+The\s+(.+?)\s+service failed') {
                if (-not $examples.Contains($matches[1])) { $examples.Add($matches[1]) }
            }
            if ($examples.Count -ge 2) { break }
        }
        $exStr = if ($examples.Count -gt 0) { " ($($examples -join ', '))" } else { "" }
        return [PSCustomObject]@{
            HasNotice  = $true
            Reason     = "$evCount recurring event(s)$exStr - press L for details"
            Retryable  = $false
            NeedsAdmin = $false
        }
    }

    if ($Module.BaseName -eq 'freewinly-check-hardware' -and $OutputText -match 'Found\s+(\d+)\s+device') {
        return [PSCustomObject]@{
            HasNotice  = $true
            Reason     = "$($matches[1]) device warning(s) - press L for details"
            Retryable  = $false
            NeedsAdmin = $false
        }
    }

    if ($OutputText -match '(?<!0\s+)\b(Exception|Failed|Error|SucceededWithErrors|Aborted)\b|\[App Ignored\]|skipped\s*\(Requires Administrator privileges\)' -and $OutputText -notmatch 'Zero broken|0 errors|0 failed') {
        $needsElev = ($OutputText -match 'Access denied|Administrator privileges|elevation required|0x80073d28')
        $reasonLine = ($OutputText -split '\r?\n' | Where-Object { $_ -match '(?<!0\s+)\b(Exception|Failed|Error|SucceededWithErrors|Aborted)\b|\[App Ignored\]|skipped\s*\(Requires Administrator privileges\)' } | Select-Object -First 1)
        if ($reasonLine) {
            $reasonLine = $reasonLine.Trim()
            if ($reasonLine.Length -gt 95) { $reasonLine = $reasonLine.Substring(0, 92) + '...' }
        } else {
            $reasonLine = 'Completed with warnings (press L for log)'
        }
        $isOpError = (($OutputText -match '(?<!0\s+)\b(Exception|Failed|Error|Aborted)\b') -and ($Module.BaseName -notmatch '^freewinly-check-')) -or ($OutputText -match 'Failed to query (Windows Event Logs|hardware status)')
        return [PSCustomObject]@{
            HasNotice  = $true
            Reason     = if ($needsElev) { "$reasonLine (requires Admin)" } else { $reasonLine }
            Retryable  = ($Module.BaseName -notmatch '^freewinly-check-')
            NeedsAdmin = $needsElev
            IsError    = $isOpError
        }
    }

    return [PSCustomObject]@{ HasNotice = $false; Reason = $null; Retryable = $false; NeedsAdmin = $false; IsError = $false }
}

function Show-RunSummary {
    param([array]$Notices)
    if (-not $Notices -or $Notices.Count -eq 0) { return }
    Write-Host "`n--- Summary / Attention Needed ---" -ForegroundColor Yellow
    foreach ($n in $Notices) {
        Write-Host "  * $($n.Module.Name): " -NoNewline -ForegroundColor White
        Write-Host $n.Reason -ForegroundColor Yellow
    }
}

function Invoke-ModuleBatch {
    param([array]$TargetModules)
    $batchNotices = [System.Collections.Generic.List[PSCustomObject]]::new()
    $batchErrors  = 0
    $isStd        = ($outputMode -eq 'Standard')
    $env:FREEWINLY_OUTPUT_MODE = $outputMode

    if ($isStd) {
        Write-Host "`nExecuting $($TargetModules.Count) active maintenance module(s) [Standard Mode]:`n" -ForegroundColor Cyan
    } else {
        Write-Log "`nExecuting $($TargetModules.Count) active maintenance module(s) [Advanced Mode]..." "Cyan"
    }

    $totalCount = $TargetModules.Count
    $totalDigits = "$totalCount".Length
    $step = 0
    foreach ($m in $TargetModules) {
        $step++
        $stepStr = "$step".PadLeft($totalDigits)
        $stepPrefix = "[ $stepStr/$totalCount ]"
        $paddedName = "$($m.Name)".PadRight(35, '.')
        if ($isStd) {
            Write-Host "  $stepPrefix $paddedName " -NoNewline -ForegroundColor White
        }

        if ($m.BaseName -eq 'freewinly-update-software') {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
                    $sw.Stop()
                    if ($isStd) {
                        Write-Host "[ Notice ] " -NoNewline -ForegroundColor Yellow
                        Write-Host "(Winget CLI not available) ($([math]::Round($sw.Elapsed.TotalSeconds, 1))s)" -ForegroundColor Gray
                    } else {
                        Write-Host "Winget CLI is not available on this system. Skipping." -ForegroundColor Yellow
                    }
                    $batchNotices.Add([PSCustomObject]@{
                        Module     = $m
                        Reason     = 'Winget CLI not available'
                        Retryable  = $false
                        NeedsAdmin = $false
                    })
                    continue
                }

                $origSyncEnc = [Console]::OutputEncoding
                try {
                    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
                    & winget source update --disable-interactivity 2>&1 | Out-Null
                } finally {
                    [Console]::OutputEncoding = $origSyncEnc
                }
                $avail = & $m.Path -Action Scan
                $cleanSettings = if ($m.Settings) { $m.Settings } else { @{} }
                if ($cleanSettings.excluded) {
                    $todayDate = (Get-Date).Date
                    $keptExcl = [System.Collections.Generic.List[object]]::new()
                    $exclChanged = $false
                    foreach ($exItem in $cleanSettings.excluded) {
                        if ($exItem -is [string]) {
                            if (-not [string]::IsNullOrWhiteSpace($exItem)) { $keptExcl.Add($exItem) }
                        } elseif ($exItem -and $exItem.id) {
                            $uDate = if ($exItem.until) { try { [datetime]$exItem.until } catch { $null } } else { $null }
                            if (-not $uDate -or $todayDate -le $uDate) {
                                $keptExcl.Add($exItem)
                            } else {
                                $exclChanged = $true
                                Add-Content -LiteralPath $logFile -Value "Expired postponement removed: $($exItem.id)" -Encoding UTF8
                            }
                        }
                    }
                    if ($exclChanged -and $m.Settings -is [PSCustomObject]) {
                        $m.Settings | Add-Member -NotePropertyName excluded -NotePropertyValue @($keptExcl) -Force
                    }
                }
                $activeExcludes = Get-ActiveWingetExclusions -ExcludedSource $cleanSettings.excluded
                $toUpdate = [System.Collections.Generic.List[PSCustomObject]]::new()
                foreach ($pkg in $avail) {
                    $id = $pkg.Id
                    $name = $pkg.Name
                    if ($activeExcludes | Where-Object { $id -eq $_ -or $name -match [regex]::Escape($_) }) {
                        Add-Content -LiteralPath $logFile -Value "SKIPPED: $name ($id)" -Encoding UTF8
                        if (-not $isStd) { Write-Host "SKIPPED: $name ($id)" -ForegroundColor Yellow }
                    } else {
                        $toUpdate.Add($pkg)
                    }
                }

                if ($toUpdate.Count -eq 0) {
                    $modOutput = & $m.Path -Action Run -Settings $m.Settings -LogFile $logFile *>&1
                    $sw.Stop()
                    if (-not $isStd -and $modOutput) { $modOutput | Out-Host }
                    if ($modOutput) { Add-Content -LiteralPath $logFile -Value ($modOutput | Out-String).TrimEnd() -Encoding UTF8 }
                    if ($isStd) {
                        Write-Host "[ OK ] " -NoNewline -ForegroundColor Green
                        Write-Host "(All packages up to date) ($([math]::Round($sw.Elapsed.TotalSeconds, 1))s)" -ForegroundColor Gray
                    }
                } else {
                    if ($isStd) {
                        Write-Host "[ $($toUpdate.Count) Pending Update$(if ($toUpdate.Count -gt 1) { 's' }) ]" -ForegroundColor Cyan
                    } else {
                        Write-Host "`n--- [freewinly-update-software] Updating $($toUpdate.Count) package(s) ---" -ForegroundColor Cyan
                    }
                    $updatedCount = 0
                    $noticeCount  = 0
                    $failedPkgReasons = [System.Collections.Generic.List[string]]::new()
                    $pkgNeedsAdmin = $false
                    $subIndent = "  " + "".PadRight($stepPrefix.Length + 1)
                    foreach ($pkg in $toUpdate) {
                        $appName = $pkg.Name
                        if ($appName.Length -gt 24) { $appName = $appName.Substring(0, 21) + "..." }
                        $padApp = "$subIndent- $appName".PadRight(35 + $subIndent.Length)
                        $oldVer = "$($pkg.InstalledVersion)".PadRight(10)
                        $newVer = "$($pkg.AvailableVersion)".PadRight(12)
                        Write-Host "$padApp $oldVer -> $newVer " -NoNewline -ForegroundColor White

                        $pkgSw = [System.Diagnostics.Stopwatch]::StartNew()
                        $origUpgEnc = [Console]::OutputEncoding
                        try {
                            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
                            $global:LASTEXITCODE = 0
                            $out = & winget upgrade --id $pkg.Id --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1
                            $exitCode = $LASTEXITCODE
                        } finally {
                            [Console]::OutputEncoding = $origUpgEnc
                        }
                        $pkgSw.Stop()
                        $elapsed = [math]::Round($pkgSw.Elapsed.TotalSeconds, 1)

                        if (-not $isStd -and $out) { $out | Out-Host }
                        if ($logFile) {
                            $out | Add-Content -LiteralPath $logFile -Encoding UTF8
                            Add-Content -LiteralPath $logFile -Value "RESULT: $($pkg.Id) => ExitCode $exitCode" -Encoding UTF8
                        }

                        $outStr = ($out | Out-String)
                        if ($exitCode -eq 0) {
                            $updatedCount++
                            Write-Host "[ OK ] " -NoNewline -ForegroundColor Green
                            Write-Host "(${elapsed}s)" -ForegroundColor Gray
                        } else {
                            $noticeCount++
                            $wInfo = Get-WingetNoticeInfo -ExitCode $exitCode -OutputText $outStr
                            if ($wInfo.NeedsAdmin) { $pkgNeedsAdmin = $true }
                            if ($exitCode -notin @(3010, -1978335189)) { $batchErrors++ }
                            $failedPkgReasons.Add("$($pkg.Id) ($($wInfo.Text))")
                            Write-Host "[ Notice ] " -NoNewline -ForegroundColor Yellow
                            Write-Host "($($wInfo.Text)) (${elapsed}s)" -ForegroundColor Gray
                        }
                    }
                    $sw.Stop()
                    $totalElapsed = [math]::Round($sw.Elapsed.TotalSeconds, 1)
                    $summaryDetails = "$updatedCount updated"
                    if ($noticeCount -gt 0) {
                        $summaryDetails += ", $noticeCount notice$(if ($noticeCount -gt 1) { 's' })"
                        $batchNotices.Add([PSCustomObject]@{
                            Module     = $m
                            Reason     = $failedPkgReasons -join '; '
                            Retryable  = $true
                            NeedsAdmin = $pkgNeedsAdmin
                        })
                    }
                    $statusColor = if ($noticeCount -gt 0) { "Yellow" } else { "Green" }
                    $statusTag   = if ($noticeCount -gt 0) { "[ Notice ]" } else { "[ OK ]" }
                    Write-Host "  $stepPrefix $paddedName " -NoNewline -ForegroundColor White
                    Write-Host "$statusTag " -NoNewline -ForegroundColor $statusColor
                    Write-Host "($summaryDetails) (${totalElapsed}s)" -ForegroundColor Gray
                }
            } catch {
                $sw.Stop()
                $batchErrors++
                if ($isStd) { Write-Host "[ Error ]" -ForegroundColor Red }
                Write-Log "Module Error ($($m.Name)): $($_.Exception.Message)" "Red"
                $batchNotices.Add([PSCustomObject]@{
                    Module     = $m
                    Reason     = $_.Exception.Message
                    Retryable  = $true
                    NeedsAdmin = $false
                })
            }
        } else {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $modOutput = & $m.Path -Action Run -Settings $m.Settings -LogFile $logFile *>&1
                $sw.Stop()
                if (-not $isStd -and $modOutput) { $modOutput | Out-Host }
                $modStr = ($modOutput | Out-String)
                if (-not [string]::IsNullOrWhiteSpace($modStr)) {
                    Add-Content -LiteralPath $logFile -Value $modStr.TrimEnd() -Encoding UTF8
                }
                $noticeInfo = Get-ModuleNoticeSummary -Module $m -OutputText $modStr
                if ($noticeInfo.HasNotice) {
                    if ($noticeInfo.PSObject.Properties['IsError'] -and $noticeInfo.IsError) {
                        $batchErrors++
                    }
                    if ($isStd) {
                        Write-Host "[ Notice ] " -NoNewline -ForegroundColor Yellow
                        Write-Host "($([math]::Round($sw.Elapsed.TotalSeconds, 1))s)" -ForegroundColor Gray
                    }
                    $batchNotices.Add([PSCustomObject]@{
                        Module     = $m
                        Reason     = $noticeInfo.Reason
                        Retryable  = $noticeInfo.Retryable
                        NeedsAdmin = $noticeInfo.NeedsAdmin
                    })
                } else {
                    if ($isStd) {
                        Write-Host "[ OK ] " -NoNewline -ForegroundColor Green
                        Write-Host "($([math]::Round($sw.Elapsed.TotalSeconds, 1))s)" -ForegroundColor Gray
                    }
                }
            } catch {
                $sw.Stop()
                $batchErrors++
                if ($isStd) { Write-Host "[ Error ]" -ForegroundColor Red }
                Write-Log "Module Error ($($m.Name)): $($_.Exception.Message)" "Red"
                $batchNotices.Add([PSCustomObject]@{
                    Module     = $m
                    Reason     = $_.Exception.Message
                    Retryable  = ($m.BaseName -notmatch '^freewinly-check-')
                    NeedsAdmin = $false
                })
            }
        }
    }

    return [PSCustomObject]@{
        Notices = @($batchNotices)
        Errors  = $batchErrors
    }
}

# 6.3 RUN ENABLED MODULES IN CONFIGURED SEQUENCE
$hookErrors = $moduleErrors
$batchResult = Invoke-ModuleBatch -TargetModules $activeModules
$moduleErrors += $batchResult.Errors

# 6.4 POST-COMMANDS HOOK (With Prompt Injection Security Firewall)
if (-not $SkipHooks -and $config -and $config.postCommands -and $config.postCommands.Count -gt 0) {
    $remainingPost = @(Invoke-SecuredCommandsHook -HookName "postCommands" -Commands $config.postCommands -IsInteractive $isInteractiveSession -TargetLogFile $logFile)
    if ($remainingPost.Count -ne $config.postCommands.Count) {
        $config.postCommands = $remainingPost
        $script:modifiedHooks.postCommands = $true
        $configModified = $true
    }
}

# Persist if any module updated its Settings (skip if transient CLI -Settings override was passed)
$settingsSnapshotAfter = ($discoveredModules | Select-Object BaseName, Enabled, Settings | ConvertTo-Json -Depth 6 -Compress)
if (-not $Settings -and ($settingsSnapshotBefore -ne $settingsSnapshotAfter)) {
    $configModified = $true
}

if ($configModified -and (Test-Path (Split-Path -Parent $ConfigPath))) {
    Save-ConfigState
    Write-Log "Configuration updated." "Green"
}

$currentNotices = @($batchResult.Notices)
Show-RunSummary -Notices $currentNotices

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
    try {
        while ($true) {
            $retryModules = @($currentNotices | Where-Object { $_.Retryable } | ForEach-Object { $_.Module } | Select-Object -Unique)
            $canElevateRetry = (-not $isAdmin) -and ($retryModules.Count -gt 0)

            $promptParts = [System.Collections.Generic.List[string]]::new()
            if ($retryModules.Count -gt 0) { $promptParts.Add('[R] retry affected') }
            if ($canElevateRetry)        { $promptParts.Add('[E] retry as Admin') }
            $promptParts.Add('[L] open log')
            $promptParts.Add('[Enter / Esc] close')
            Write-Host ("Press " + ($promptParts -join ', ') + "...") -ForegroundColor Cyan

            $k = [Console]::ReadKey($true)
            if ($k.Key -in @('Enter', 'Escape', 'Q')) {
                break
            } elseif ($k.Key -eq 'L') {
                if (Test-Path -LiteralPath $logFile) {
                    try {
                        Start-Process -FilePath $logFile -ErrorAction Stop
                    } catch {
                        Start-Process -FilePath "notepad.exe" -ArgumentList @($logFile) -ErrorAction SilentlyContinue
                    }
                    Write-Host "Opened log file." -ForegroundColor Gray
                } else {
                    Write-Host "Log file not found at '$logFile'." -ForegroundColor Yellow
                }
            } elseif ($k.Key -eq 'R' -and $retryModules.Count -gt 0) {
                $retryBefore = ($discoveredModules | Select-Object BaseName, Enabled, Settings | ConvertTo-Json -Depth 6 -Compress)
                $retryResult = Invoke-ModuleBatch -TargetModules $retryModules
                $nonRetryNotices = @($currentNotices | Where-Object { -not $_.Retryable })
                $currentNotices = @($nonRetryNotices) + @($retryResult.Notices)
                $moduleErrors = $hookErrors + $retryResult.Errors
                $retryAfter = ($discoveredModules | Select-Object BaseName, Enabled, Settings | ConvertTo-Json -Depth 6 -Compress)
                if (-not $Settings -and ($retryBefore -ne $retryAfter) -and (Test-Path (Split-Path -Parent $ConfigPath))) {
                    Save-ConfigState
                }
                if (-not $configWasCorrupted -and $moduleErrors -eq 0) {
                    Update-LastGoodConfigFile -Path $ConfigPath
                }
                if ($retryResult.Notices.Count -eq 0 -and $retryResult.Errors -eq 0) {
                    Write-Host "`n[OK] All retried items completed cleanly!" -ForegroundColor Green
                }
                Show-RunSummary -Notices $currentNotices
            } elseif ($k.Key -eq 'E' -and $canElevateRetry) {
                if ($Settings) {
                    Write-Host "`n[ERROR] CLI -Settings overrides cannot be forwarded across UAC elevation." -ForegroundColor Red
                    continue
                }
                if (-not $Modules) {
                    Save-ConfigState
                }
                $retryNames = ($retryModules | Select-Object -ExpandProperty BaseName) -join ','
                $psHost = try { (Get-Process -Id $PID).Path } catch { $null }
                if (-not $psHost -or -not (Test-Path $psHost)) { $psHost = 'powershell.exe' }
                $elevArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Run', '-Interactive', '-SkipHooks', '-Modules', "`"$retryNames`"")
                if ($ConfigPath) { $elevArgs += @('-ConfigPath', "`"$ConfigPath`"") }
                if ($outputMode) { $elevArgs += @('-OutputMode', $outputMode) }
                try {
                    Start-Process -FilePath $psHost -Verb RunAs -ArgumentList $elevArgs -ErrorAction Stop
                    exit 0
                } catch {
                    Write-Host "Administrator elevation was cancelled by user." -ForegroundColor Yellow
                }
            }
        }
    } catch {
        Read-Host "Press Enter to close this window"
    }
} else {
    # Deterministic exit code for CI/CD and automation
    if ($moduleErrors -gt 0) { exit 1 } else { exit 0 }
}
