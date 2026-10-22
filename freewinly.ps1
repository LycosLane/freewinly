#Requires -Version 5.1
<#
.SYNOPSIS
    FreeWinly v1.1.0 - Open Source Windows Maintenance & Optimization Engine.
.DESCRIPTION
    Native Windows maintenance suite utilizing Winget, PowerShell 5.1+, COM APIs, and TRIM.
    Supports headless CLI automation, interactive TUI menu, dry-run check previews, and JIT elevation.
.PARAMETER Run
    Executes the enabled or specified modules immediately without opening the interactive menu.
.PARAMETER Check
    Performs a dry-run preview across enabled or specified modules without altering system state.
.PARAMETER Audit
    Alias for -Check. Runs the read-only diagnostic system inspection (hardware, logs, updates, storage).
.PARAMETER Modules
    Optional array or comma-separated list of module BaseNames to run (e.g. -Modules 10_hardware_health,20_software_updates).
.PARAMETER ConfigPath
    Optional path to a custom configuration JSON file (defaults to .\config.json).
.PARAMETER CountdownSeconds
    Override the auto-start countdown duration (0 for instant execution, 3, 5, 10, 20, 30).
.PARAMETER Interactive
    Indicates an interactive user session (keeps the console window open until Enter is pressed after completion).
.PARAMETER HelpMe
    Displays CLI usage instructions and examples (aliases: -Help, -h).
.EXAMPLE
    .\freewinly.ps1
.EXAMPLE
    .\freewinly.ps1 -Check
.EXAMPLE
    .\freewinly.ps1 -Run
.EXAMPLE
    .\freewinly.ps1 -Modules 10_hardware_health,20_software_updates -Run
#>
[CmdletBinding()]
param(
    [switch]$Run,
    [switch]$Check,
    [switch]$Audit,
    [string[]]$Modules = $null,
    [string]$ConfigPath = $null,
    [int]$CountdownSeconds = -1,
    [switch]$Interactive,
    [Alias('Help', 'h')]
    [switch]$HelpMe
)

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$projectRoot = $PSScriptRoot
$coreDir     = Join-Path $projectRoot "core"
$modulesDir  = Join-Path $projectRoot "modules"
$logsDir     = Join-Path $projectRoot "logs"
$logFile     = Join-Path $logsDir "latest-run.log"

$configPath = if ($ConfigPath -and (Test-Path $ConfigPath)) {
    (Resolve-Path $ConfigPath).Path
} elseif ($ConfigPath) {
    Write-Warning "Specified config file '$ConfigPath' not found. Falling back to default config.json."
    Join-Path $projectRoot "config.json"
} else {
    Join-Path $projectRoot "config.json"
}

if (-not (Test-Path $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}

function Show-Banner {
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "         FreeWinly v1.1.0 - Open Source Windows Engine      " -ForegroundColor White
    Write-Host "        Freeing Windows from bloatware, caches & fees       " -ForegroundColor Gray
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Write-Host $Message -ForegroundColor $Color
    Add-Content -Path $logFile -Value "[$timestamp] $Message" -Encoding UTF8
}

function Get-SafeConfig {
    param([string]$Path)
    if (Test-Path $Path) {
        try {
            return (Get-Content $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
        } catch {
            Write-Warning "Failed to parse '$Path' (invalid JSON syntax). Using safe in-memory defaults."
        }
    }
    return [PSCustomObject]@{
        preCommands           = @()
        uninstall             = @()
        install               = @()
        excluded              = @()
        postCommands          = @()
        enabledModules        = $null
        cleanupTempMinAgeDays = 7
        eventLogLookbackDays  = 7
        hddDefragMinDays      = 30
        countdownSeconds      = 10
        scheduleType          = "Weekly"
        scheduleDay           = "Sunday"
        scheduleTime          = "12:00"
    }
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
  .\freewinly.ps1 -Modules <list>      Specify modules to run or check (e.g. -Modules 10_hardware_health,20_software_updates)
  .\freewinly.ps1 -Help                Show this help message

Core Utilities:
  .\core\onboarding.ps1                First-run setup & exclusion wizard
  .\core\scheduler.ps1                 Configure Windows Task Scheduler automation
  .\core\shortcut.ps1                  Manage Start Menu shortcut (Install / Remove / Status)
  .\core\uninstall.ps1                 Cleanly remove FreeWinly from this PC

Standalone Module Invocations:
  .\modules\10_hardware_health.ps1 -Action Check
  .\modules\11_event_log_health.ps1 -Action Check
  .\modules\31_ssd_trim.ps1 -Action Run -Options @{ Drives = @('C') }
"@ -ForegroundColor Yellow
    exit 0
}

if ($Audit) {
    $Check = $true
}

# Track whether this session was started interactively by a human (vs headless -Run)
$isInteractiveSession = (-not $Run) -or $Interactive

# 1. First-Run Onboarding (if config.json does not exist yet)
if (-not (Test-Path $configPath)) {
    $onboardingScript = Join-Path $coreDir "onboarding.ps1"
    if (Test-Path $onboardingScript) {
        & $onboardingScript -ConfigPath $configPath
    }
}

$config = Get-SafeConfig -Path $configPath

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

# ==================================================================
# 2. DISCOVER MODULES DYNAMICALLY (Via -Action Info)
# ==================================================================
$moduleFiles = Get-ChildItem (Join-Path $modulesDir "*.ps1") -ErrorAction SilentlyContinue | Sort-Object Name
$discoveredModules = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($mf in $moduleFiles) {
    $baseName = $mf.BaseName
    $info = $null

    try {
        $info = & $mf.FullName -Action Info -Config $config -ErrorAction Stop
    } catch { }

    $name          = if ($info -and $info.Name) { $info.Name } else { $baseName }
    $description   = if ($info -and $info.Description) { $info.Description } else { "" }
    $defaultVal    = if ($info -and $null -ne $info.Default) { $info.Default } else { $true }
    $requiresAdmin = if ($info -and $null -ne $info.RequiresAdmin) { $info.RequiresAdmin } else { $false }
    $options       = if ($info -and $info.Options) { $info.Options } else { @{} }

    $hasEmptyDrives = ($options -and $options.ContainsKey('DetectedDrives') -and (@($options['DetectedDrives']).Count -eq 0))
    if ($hasEmptyDrives -and -not ($Modules -and $Modules -contains $baseName)) {
        continue
    }

    $isEnabled = if ($Modules) {
        $Modules -contains $baseName
    } elseif ($config.enabledModules) {
        $config.enabledModules -contains $baseName
    } else {
        $defaultVal
    }

    $discoveredModules.Add([PSCustomObject]@{
        BaseName      = $baseName
        Name          = $name
        Description   = $description
        Path          = $mf.FullName
        Enabled       = [bool]$isEnabled
        RequiresAdmin = [bool]$requiresAdmin
        Options       = $options
    })
}

function Invoke-DryRunCheck {
    param([array]$TargetModules)
    Show-Banner
    Write-Host "`n=== [Dry-Run Check / Diagnostic Audit] Inspecting $($TargetModules.Count) module(s) ===" -ForegroundColor Yellow
    Write-Host "Read-Only mode: No system modifications, updates, or deletions will be performed.`n" -ForegroundColor Gray

    foreach ($m in $TargetModules) {
        try {
            & $m.Path -Action Check -Config $config -LogFile $logFile -Options $m.Options
        } catch {
            Write-Host "Error during check for $($m.Name): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    Write-Host "`n=== Diagnostic Audit & Dry-Run Check Completed Successfully ===" -ForegroundColor Green
}

# ==================================================================
# 3. DRY-RUN CHECK / AUDIT MODE (-Check or -Audit)
# ==================================================================
if ($Check) {
    $targetModules = @($discoveredModules | Where-Object { $_.Enabled })
    Invoke-DryRunCheck -TargetModules $targetModules
    exit 0
}

# ==================================================================
# 4. INTERACTIVE MODE (Only if neither -Run nor -Check was specified)
# ==================================================================
if (-not $Run) {
    Clear-Host
    Show-Banner
    Write-Host "`nScheduled Tasks to Run:" -ForegroundColor Yellow

    foreach ($m in $discoveredModules) {
        $mark  = if ($m.Enabled) { "[x]" } else { "[ ]" }
        $admin = if ($m.RequiresAdmin) { " [Admin]" } else { "" }
        $col   = if ($m.Enabled) { "Green" } else { "DarkGray" }
        Write-Host "  $mark $($m.Name)$admin" -ForegroundColor $col
    }

    $openMenu = $false

    if ($countdown -gt 0) {
        Write-Host "`nStarting in " -NoNewline -ForegroundColor Gray
        try {
            for ($sec = $countdown; $sec -gt 0; $sec--) {
                Write-Host "$sec... " -NoNewline -ForegroundColor Cyan
                for ($sub = 0; $sub -lt 10; $sub++) {
                    Start-Sleep -Milliseconds 100
                    if ([Console]::KeyAvailable) {
                        [Console]::ReadKey($true) | Out-Null
                        $openMenu = $true
                        break
                    }
                }
                if ($openMenu) { break }
            }
        } catch {
            $openMenu = $false
        }
    }

    if ($openMenu) {
        $selectedIndex = 0
        $timerPresets = @(0, 3, 5, 10, 20, 30)
        $running = $true

        while ($running) {
            $timerText = if ($countdown -eq 0) { "0s (Instant)" } else { "${countdown}s" }
            $schedSummary = if ($config.scheduleType -and $config.scheduleType -ne "Disabled") {
                if ($config.scheduleType -eq "Logon") { "Logon (+5m)" }
                else { "$($config.scheduleType) on $($config.scheduleDay) at $($config.scheduleTime)" }
            } else {
                "Disabled"
            }
            $actions = @(
                @{ Label = "[ Enter ]  Run All Checked Tasks [x]"; Key = "Run" },
                @{ Label = "[   C   ]  Dry-Run Check / Diagnostic Audit (No changes)"; Key = "C" },
                @{ Label = "[   T   ]  Auto-Start Countdown: [ $timerText ] (Press T to cycle: 0s, 3s, 5s, 10s, 20s, 30s)"; Key = "T" },
                @{ Label = "[   W   ]  Task Scheduler: [ $schedSummary ] (Press W to configure)"; Key = "W" },
                @{ Label = "[   S   ]  Save Selection as Default"; Key = "S" },
                @{ Label = "[   O   ]  Run First-Time Onboarding Wizard"; Key = "O" },
                @{ Label = "[   I   ]  Install / Update Start Menu Shortcut"; Key = "I" },
                @{ Label = "[   U   ]  Uninstall FreeWinly Completely"; Key = "U" },
                @{ Label = "[   Q   ]  Quit Without Running"; Key = "Q" }
            )
            $totalOptions = $discoveredModules.Count + $actions.Count

            Clear-Host
            Show-Banner
            Write-Host "Use [Up/Down] arrows to navigate, [Space] to toggle, [Enter] to run:`n" -ForegroundColor Gray

            for ($i = 0; $i -lt $discoveredModules.Count; $i++) {
                $m = $discoveredModules[$i]
                $pointer   = if ($i -eq $selectedIndex) { "> " } else { "  " }
                $checkMark = if ($m.Enabled) { "[x]" } else { "[ ]" }
                $admin     = if ($m.RequiresAdmin) { " [Admin]" } else { "" }
                $color     = if ($i -eq $selectedIndex) { "Cyan" } elseif ($m.Enabled) { "Green" } else { "DarkGray" }
                Write-Host "$pointer$checkMark $($m.Name)$admin" -ForegroundColor $color
            }

            Write-Host "`n------------------------------------------------------------" -ForegroundColor DarkGray

            for ($j = 0; $j -lt $actions.Count; $j++) {
                $actionIdx = $discoveredModules.Count + $j
                $pointer = if ($actionIdx -eq $selectedIndex) { "> " } else { "  " }
                $color   = if ($actionIdx -eq $selectedIndex) { "Yellow" } else { "White" }
                Write-Host "$pointer$($actions[$j].Label)" -ForegroundColor $color
            }

            $key = [Console]::ReadKey($true)
            $cmdKey = $key.Key.ToString()

            if ($cmdKey -eq "Enter") {
                if ($selectedIndex -lt $discoveredModules.Count) {
                    $cmdKey = "Spacebar"
                } else {
                    $cmdKey = $actions[$selectedIndex - $discoveredModules.Count].Key
                }
            }

            switch ($cmdKey) {
                "UpArrow" {
                    $selectedIndex--
                    if ($selectedIndex -lt 0) { $selectedIndex = $totalOptions - 1 }
                }
                "DownArrow" {
                    $selectedIndex++
                    if ($selectedIndex -ge $totalOptions) { $selectedIndex = 0 }
                }
                "Spacebar" {
                    if ($selectedIndex -lt $discoveredModules.Count) {
                        $discoveredModules[$selectedIndex].Enabled = -not $discoveredModules[$selectedIndex].Enabled
                    }
                }
                "Run" {
                    $running = $false
                }
                { $_ -in @("C", "A") } {
                    Clear-Host
                    $targetModules = @($discoveredModules | Where-Object { $_.Enabled })
                    Invoke-DryRunCheck -TargetModules $targetModules
                    Read-Host "`nPress Enter to return to menu"
                }
                "T" {
                    $curIdx = $timerPresets.IndexOf($countdown)
                    $nextIdx = if ($curIdx -ge 0 -and $curIdx -lt ($timerPresets.Count - 1)) { $curIdx + 1 } else { 0 }
                    $countdown = $timerPresets[$nextIdx]
                    $config | Add-Member -NotePropertyName countdownSeconds -NotePropertyValue $countdown -Force
                    $config | ConvertTo-Json -Depth 5 | Out-File -FilePath $configPath -Encoding UTF8
                }
                "W" {
                    Clear-Host
                    & (Join-Path $coreDir "scheduler.ps1")
                    $config = Get-SafeConfig -Path $configPath
                }
                "S" {
                    $enabledList = @($discoveredModules | Where-Object { $_.Enabled } | Select-Object -ExpandProperty BaseName)
                    $config | Add-Member -NotePropertyName enabledModules -NotePropertyValue $enabledList -Force
                    $config | Add-Member -NotePropertyName countdownSeconds -NotePropertyValue $countdown -Force
                    $config | ConvertTo-Json -Depth 5 | Out-File -FilePath $configPath -Encoding UTF8
                    Write-Host "`n  -> Default tasks and settings saved to config.json!" -ForegroundColor Green
                    Start-Sleep -Milliseconds 800
                }
                "O" {
                    & (Join-Path $coreDir "onboarding.ps1") -ConfigPath $configPath
                    $config = Get-SafeConfig -Path $configPath
                }
                "I" {
                    & (Join-Path $coreDir "shortcut.ps1")
                    Read-Host "`nPress Enter to return to menu"
                }
                "U" {
                    Clear-Host
                    & (Join-Path $coreDir "uninstall.ps1")
                    Read-Host "`nPress Enter to return to menu"
                }
                { $_ -in @("Q", "Escape") } {
                    Write-Host "`nExiting FreeWinly." -ForegroundColor Yellow
                    exit 0
                }
            }
        }
    }
}

# ==================================================================
# 5. JUST-IN-TIME (JIT) ELEVATION CHECK
# ==================================================================
$activeModules = @($discoveredModules | Where-Object { $_.Enabled })
if ($activeModules.Count -eq 0) {
    Write-Host "No modules selected to run. Exiting." -ForegroundColor Yellow
    exit 0
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$needsAdmin = ($activeModules | Where-Object { $_.RequiresAdmin -eq $true }).Count -gt 0

if ($needsAdmin -and -not $isAdmin) {
    Write-Host "`nSelected tasks require Administrator privileges." -ForegroundColor Yellow
    Write-Host "Elevating FreeWinly runner..." -ForegroundColor Cyan
    $selectedNames = ($activeModules | Select-Object -ExpandProperty BaseName) -join ','
    $interactiveArg = if ($isInteractiveSession) { " -Interactive" } else { "" }
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Run$interactiveArg -Modules `"$selectedNames`" -ConfigPath `"$configPath`""
    exit 0
}

# ==================================================================
# 6. EXECUTION PIPELINE
# ==================================================================
Clear-Host
"==================================================================" | Out-File -FilePath $logFile -Encoding UTF8
Write-Log "FreeWinly v1.1.0 Maintenance Pipeline Started" "Cyan"
"==================================================================" | Add-Content -Path $logFile -Encoding UTF8

$configModified = $false
$configSnapshotBefore = if ($config) { $config | ConvertTo-Json -Depth 5 -Compress } else { "" }

# 6.0 PRE-COMMANDS HOOK
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

# 6.1 UNINSTALL HOOK
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

# 6.2 INSTALL HOOK
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

# 6.3 RUN ENABLED MODULES
Write-Log "`nExecuting $($activeModules.Count) active maintenance module(s)..." "Cyan"

foreach ($m in $activeModules) {
    try {
        & $m.Path -Action Run -Config $config -LogFile $logFile -Options $m.Options
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

# Auto-cleanup expired postponements in exclusions
if ($config -and $config.excluded) {
    $today = (Get-Date).Date
    $cleanExcludes = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $config.excluded) {
        if ($item -is [string]) {
            $cleanExcludes.Add($item)
        } elseif ($item.id -and $item.until) {
            $untilDate = try { [datetime]$item.until } catch { $null }
            if ($untilDate -and $today -le $untilDate) {
                $cleanExcludes.Add($item)
            } else {
                Write-Log "Postponement expired & removed: $($item.id)" "Yellow"
                $configModified = $true
            }
        }
    }
    $config.excluded = @($cleanExcludes)
}

# Check if any module updated properties on $config (such as hddDefragLastRun)
$configSnapshotAfter = if ($config) { $config | ConvertTo-Json -Depth 5 -Compress } else { "" }
if ($configSnapshotBefore -ne $configSnapshotAfter) {
    $configModified = $true
}

if ($configModified -and (Test-Path (Split-Path -Parent $configPath))) {
    $config | ConvertTo-Json -Depth 5 | Out-File -FilePath $configPath -Encoding UTF8
    Write-Log "Configuration updated." "Green"
}

Write-Log "`n=== FreeWinly Finished Successfully ===" "Green"
Write-Host "`nLog saved to: $logFile" -ForegroundColor Gray

if ($isInteractiveSession) {
    Read-Host "Press Enter to close this window"
}
