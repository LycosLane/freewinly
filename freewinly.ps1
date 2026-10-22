#Requires -Version 5.1
<#
.SYNOPSIS
    FreeWinly - Open Source Windows Maintenance & Optimization Engine.
    Automates software updates, cache cleanup, drive optimization, and hardware diagnostics.
    
.DESCRIPTION
    Native Windows maintenance suite utilizing Winget, PowerShell 5.1+, COM APIs, DISM, and TRIM.
    Supports headless CLI automation, interactive TUI menu, dry-run check previews, and JIT elevation.

.PARAMETER Run
    Executes the enabled or specified modules immediately without opening the interactive menu.

.PARAMETER Check
    Performs a dry-run preview across enabled or specified modules without altering system state.

.PARAMETER Audit
    Alias for -Check. Runs the read-only diagnostic system inspection (hardware, logs, memory, updates, storage).

.PARAMETER Modules
    Optional array or comma-separated list of module BaseNames to run (e.g. -Modules 10_hardware_health,20_software_updates).

.PARAMETER ConfigPath
    Optional path to a custom configuration JSON file (defaults to .\config.json).

.PARAMETER CountdownSeconds
    Override the auto-start countdown duration (0 for instant execution, 3, 5, 10, 20, 30).

.PARAMETER HelpMe
    Displays CLI usage instructions and examples.

.EXAMPLE
    .\freewinly.ps1
    Starts interactive mode (unelevated, countdown timer, interactive TUI menu).

.EXAMPLE
    .\freewinly.ps1 -CountdownSeconds 0 -Run
    Runs all default modules immediately with zero waiting time.

.EXAMPLE
    .\freewinly.ps1 -Check
    Performs a dry-run preview of all default modules without making changes.

.EXAMPLE
    .\freewinly.ps1 -Run
    Runs all default modules immediately with automatic JIT elevation if needed.

.EXAMPLE
    .\freewinly.ps1 -ConfigPath "custom-config.json" -Run
    Runs FreeWinly using a custom configuration file.
#>

[CmdletBinding()]
param(
    [switch]$Run,
    [switch]$Check,
    [switch]$Audit,
    [string[]]$Modules = $null,
    [string]$ConfigPath = $null,
    [int]$CountdownSeconds = -1,
    [switch]$HelpMe
)

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$projectRoot = $PSScriptRoot
$configPath  = if ($ConfigPath -and (Test-Path $ConfigPath)) {
    $ConfigPath
} elseif ($ConfigPath) {
    Write-Warning "Specified config file '$ConfigPath' not found. Falling back to default config.json."
    Join-Path $projectRoot "config.json"
} else {
    Join-Path $projectRoot "config.json"
}

$modulesDir  = Join-Path $projectRoot "modules"
$logsDir     = Join-Path $projectRoot "logs"
$logFile     = Join-Path $logsDir "latest-run.log"

if (-not (Test-Path $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}

function Show-Banner {
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "           FreeWinly - Open Source Windows Engine           " -ForegroundColor White
    Write-Host "        Freeing Windows from bloatware, caches & fees       " -ForegroundColor Gray
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Write-Host $Message -ForegroundColor $Color
    Add-Content -Path $logFile -Value "[$timestamp] $Message" -Encoding UTF8
}

if ($HelpMe) {
    Show-Banner
    Write-Host @"
CLI Usage:
  .\freewinly.ps1                      Interactive mode (countdown timer, TUI menu, JIT elevation)
  .\freewinly.ps1 -Check               Dry-run preview / diagnostic audit (no changes made)
  .\freewinly.ps1 -Run                 Execute enabled modules immediately
  .\freewinly.ps1 -CountdownSeconds 0  Run without countdown delay (instant start)
  .\freewinly.ps1 -Audit               Alias for -Check (read-only health & stability audit)
  .\freewinly.ps1 -ConfigPath <file>   Use custom config JSON file
  .\freewinly.ps1 -Modules <list>      Specify modules to run or check (e.g. -Modules 10_hardware_health,20_software_updates)
  .\freewinly.ps1 -HelpMe              Show this help message

Module CLI Invocations:
  Individual modules in .\modules\ can also be called directly:
  .\modules\10_hardware_health.ps1 -Action Check
  .\modules\11_event_log_health.ps1 -Action Check
  .\modules\31_ssd_trim.ps1 -Action Run -Options @{ Drives = @('C') }
"@ -ForegroundColor Yellow
    exit 0
}

# -Audit is a friendly alias for -Check
if ($Audit) {
    $Check = $true
}

# ==================================================================
# 1. FIRST-RUN ONBOARDING WIZARD
# ==================================================================
function Run-OnboardingWizard {
    Clear-Host
    Show-Banner
    Write-Host "`n[First-Run Setup] Scanning for applications with version quirks...`n" -ForegroundColor Gray

    $detectedExcludes = [System.Collections.Generic.List[string]]::new()

    try {
        $lines = & winget upgrade --include-unknown --accept-source-agreements 2>&1 | Out-String -Stream
        $headerIdx = [array]::FindIndex($lines, [Predicate[string]]{ param($l) $l -match '^Name\s+Id\s+Version' })
        if ($headerIdx -ge 0) {
            $header   = $lines[$headerIdx]
            $idStart  = $header.IndexOf("Id")
            $verStart = $header.IndexOf("Version")
            for ($i = $headerIdx + 2; $i -lt $lines.Count; $i++) {
                $line = $lines[$i]
                if ($line -match '\sUnknown\s' -and $line.Length -gt $verStart) {
                    $appName = $line.Substring(0, $idStart).Trim()
                    $pkgId   = $line.Substring($idStart, $verStart - $idStart).Trim()
                    if ($pkgId -match '^[A-Za-z0-9\._-]+\.[A-Za-z0-9\._-]+$') {
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
    } catch {
        Write-Host "Winget scan skipped: $($_.Exception.Message)" -ForegroundColor Gray
    }

    $existingConfig = if (Test-Path $configPath) { Get-Content $configPath -Raw | ConvertFrom-Json } else { $null }
    $enabled = if ($existingConfig -and $existingConfig.enabledModules) {
        $existingConfig.enabledModules
    } else {
        @(Get-ChildItem (Join-Path $modulesDir "*.ps1") -ErrorAction SilentlyContinue | Where-Object {
            try { (& $_.FullName -Action Info).Default -eq $true } catch { $true }
        } | Select-Object -ExpandProperty BaseName)
    }

    $newConfig = [ordered]@{
        preCommands           = @()
        uninstall             = @()
        install               = @()
        excluded              = @($detectedExcludes)
        postCommands          = @()
        postponedPhases       = @()
        enabledModules        = @($enabled)
        cleanupTempMinAgeDays = 7
        eventLogLookbackDays  = 7
        hddDefragMinDays      = 30
        countdownSeconds      = 10
        scheduleType          = "Weekly"
        scheduleDay           = "Sunday"
        scheduleTime          = "12:00"
    }

    $newConfig | ConvertTo-Json -Depth 5 | Out-File -FilePath $configPath -Encoding UTF8
    Write-Host "`nConfiguration created successfully at: $configPath" -ForegroundColor Green
    Start-Sleep -Seconds 2
}

if (-not (Test-Path $configPath)) {
    Run-OnboardingWizard
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json

# Resolve countdown timer setting (CLI parameter > config.json > default 10)
$countdown = if ($CountdownSeconds -ge 0) {
    $CountdownSeconds
} elseif ($config -and $null -ne $config.countdownSeconds) {
    [int]$config.countdownSeconds
} else {
    10
}

# Flatten comma-separated Modules if passed as single string
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
    } catch {
        # Fallback if module fails Info query
    }

    $name          = if ($info -and $info.Name) { $info.Name } else { $baseName }
    $description   = if ($info -and $info.Description) { $info.Description } else { "" }
    $defaultVal    = if ($info -and $null -ne $info.Default) { $info.Default } else { $true }
    $requiresAdmin = if ($info -and $null -ne $info.RequiresAdmin) { $info.RequiresAdmin } else { $false }
    $options       = if ($info -and $info.Options) { $info.Options } else { @{} }

    # If the module requires target drives (e.g. SSD TRIM or HDD defrag) and none exist on this PC,
    # skip adding it to the TUI/execution list unless explicitly targeted via CLI (-Modules)
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

# ==================================================================
# 3. DRY-RUN CHECK / AUDIT MODE (-Check or -Audit)
# ==================================================================
if ($Check) {
    Show-Banner
    $targetModules = @($discoveredModules | Where-Object { $_.Enabled })
    Write-Host "`n=== [Dry-Run Check / Diagnostic Audit] Inspecting $($targetModules.Count) module(s) ===" -ForegroundColor Yellow
    Write-Host "Read-Only mode: No system modifications, updates, or deletions will be performed.`n" -ForegroundColor Gray

    foreach ($m in $targetModules) {
        try {
            & $m.Path -Action Check -Config $config -LogFile $logFile -Options $m.Options
        } catch {
            Write-Host "Error during check for $($m.Name): $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host "`n=== Diagnostic Audit & Dry-Run Check Completed Successfully ===" -ForegroundColor Green
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
                @{ Label = "[ Enter ]  Run All Checked Tasks [x]"; Key = "Enter" },
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
            switch ($key.Key) {
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
                "Enter" {
                    if ($selectedIndex -lt $discoveredModules.Count) {
                        $discoveredModules[$selectedIndex].Enabled = -not $discoveredModules[$selectedIndex].Enabled
                    } elseif ($selectedIndex -eq $discoveredModules.Count) {
                        # Run All Checked Tasks
                        $running = $false
                    } elseif ($selectedIndex -eq ($discoveredModules.Count + 1)) {
                        # Dry-Run Check / Audit
                        Clear-Host
                        Show-Banner
                        $targetModules = @($discoveredModules | Where-Object { $_.Enabled })
                        Write-Host "`n=== [Dry-Run Check / Diagnostic Audit] Inspecting $($targetModules.Count) module(s) ===" -ForegroundColor Yellow
                        foreach ($m in $targetModules) {
                            try { & $m.Path -Action Check -Config $config -LogFile $logFile -Options $m.Options } catch { Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red }
                        }
                        Read-Host "`nPress Enter to return to menu"
                    } elseif ($selectedIndex -eq ($discoveredModules.Count + 2)) {
                        # Cycle timer
                        $curIdx = $timerPresets.IndexOf($countdown)
                        $nextIdx = if ($curIdx -ge 0 -and $curIdx -lt ($timerPresets.Count - 1)) { $curIdx + 1 } else { 0 }
                        $countdown = $timerPresets[$nextIdx]
                        $config.countdownSeconds = $countdown
                        $config | ConvertTo-Json -Depth 5 | Out-File -FilePath $configPath -Encoding UTF8
                    } elseif ($selectedIndex -eq ($discoveredModules.Count + 3)) {
                        # Task Scheduler
                        Clear-Host
                        & (Join-Path $projectRoot "install-task.ps1")
                        $config = Get-Content $configPath -Raw | ConvertFrom-Json
                    } elseif ($selectedIndex -eq ($discoveredModules.Count + 4)) {
                        # Save
                        $enabledList = ($discoveredModules | Where-Object { $_.Enabled } | Select-Object -ExpandProperty BaseName)
                        $config.enabledModules = @($enabledList)
                        $config.countdownSeconds = $countdown
                        $config | ConvertTo-Json -Depth 5 | Out-File -FilePath $configPath -Encoding UTF8
                        Write-Host "`n  -> Default tasks and settings saved to config.json!" -ForegroundColor Green
                        Start-Sleep -Milliseconds 800
                    } elseif ($selectedIndex -eq ($discoveredModules.Count + 5)) {
                        # Onboarding
                        Run-OnboardingWizard
                        $config = Get-Content $configPath -Raw | ConvertFrom-Json
                    } elseif ($selectedIndex -eq ($discoveredModules.Count + 6)) {
                        # Install shortcut
                        & (Join-Path $projectRoot "install-shortcut.ps1")
                        Read-Host "`nPress Enter to return to menu"
                    } elseif ($selectedIndex -eq ($discoveredModules.Count + 7)) {
                        # Uninstall
                        Clear-Host
                        & (Join-Path $projectRoot "uninstall.ps1")
                        Read-Host "`nPress Enter to return to menu"
                    } elseif ($selectedIndex -eq ($discoveredModules.Count + 8)) {
                        # Quit
                        Write-Host "`nExiting FreeWinly." -ForegroundColor Yellow
                        exit 0
                    }
                }
                { $_ -in @("C", "A") } {
                    Clear-Host
                    Show-Banner
                    $targetModules = @($discoveredModules | Where-Object { $_.Enabled })
                    Write-Host "`n=== [Dry-Run Check / Diagnostic Audit] Inspecting $($targetModules.Count) module(s) ===" -ForegroundColor Yellow
                    foreach ($m in $targetModules) {
                        try { & $m.Path -Action Check -Config $config -LogFile $logFile -Options $m.Options } catch { Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red }
                    }
                    Read-Host "`nPress Enter to return to menu"
                }
                "T" {
                    $curIdx = $timerPresets.IndexOf($countdown)
                    $nextIdx = if ($curIdx -ge 0 -and $curIdx -lt ($timerPresets.Count - 1)) { $curIdx + 1 } else { 0 }
                    $countdown = $timerPresets[$nextIdx]
                    $config.countdownSeconds = $countdown
                    $config | ConvertTo-Json -Depth 5 | Out-File -FilePath $configPath -Encoding UTF8
                }
                "W" {
                    Clear-Host
                    & (Join-Path $projectRoot "install-task.ps1")
                    $config = Get-Content $configPath -Raw | ConvertFrom-Json
                }
                "S" {
                    $enabledList = ($discoveredModules | Where-Object { $_.Enabled } | Select-Object -ExpandProperty BaseName)
                    $config.enabledModules = @($enabledList)
                    $config.countdownSeconds = $countdown
                    $config | ConvertTo-Json -Depth 5 | Out-File -FilePath $configPath -Encoding UTF8
                    Write-Host "`n  -> Default tasks and settings saved to config.json!" -ForegroundColor Green
                    Start-Sleep -Milliseconds 800
                }
                "O" {
                    Run-OnboardingWizard
                    $config = Get-Content $configPath -Raw | ConvertFrom-Json
                }
                "I" {
                    & (Join-Path $projectRoot "install-shortcut.ps1")
                    Read-Host "`nPress Enter to return to menu"
                }
                "U" {
                    Clear-Host
                    & (Join-Path $projectRoot "uninstall.ps1")
                    Read-Host "`nPress Enter to return to menu"
                }
                "Q" {
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
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Run -Modules `"$selectedNames`" -ConfigPath `"$configPath`""
    exit 0
}

# ==================================================================
# 6. EXECUTION PIPELINE
# ==================================================================
Clear-Host
"==================================================================" | Out-File -FilePath $logFile -Encoding UTF8
Write-Log "FreeWinly Maintenance Pipeline Started" "Cyan"
"==================================================================" | Add-Content -Path $logFile -Encoding UTF8

$configModified = $false

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
if ($config.excluded) {
    $today = (Get-Date).Date
    $cleanExcludes = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $config.excluded) {
        if ($item -is [string]) {
            $cleanExcludes.Add($item)
        } elseif ($item.id -and $item.until) {
            if ($today -le [datetime]$item.until) {
                $cleanExcludes.Add($item)
            } else {
                Write-Log "Postponement expired & removed: $($item.id)" "Yellow"
                $configModified = $true
            }
        }
    }
    $config.excluded = $cleanExcludes
}

if ($configModified) {
    $config | ConvertTo-Json -Depth 5 | Out-File -FilePath $configPath -Encoding UTF8
    Write-Log "Configuration updated (cleared completed queues/hooks)." "Green"
}

Write-Log "`n=== FreeWinly Finished Successfully ===" "Green"
Write-Host "`nLog saved to: $logFile" -ForegroundColor Gray
Read-Host "Press Enter to close this window"
