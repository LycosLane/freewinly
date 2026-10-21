#Requires -Version 5.1
<#
.SYNOPSIS
    FreeWinly - Open Source Windows Maintenance & Optimization Engine.
    Befreit Windows von Bloatware, alten Caches und unnötigen Abos.
    
    Features:
      - Automatic self-elevation on interactive desktop
      - First-run onboarding wizard if config.json is absent
      - 10-second auto-start countdown (press any key for interactive TUI)
      - Interactive TUI menu with toggleable checkboxes [x] / [ ]
      - Ad-hoc Run [Enter] vs. Save as Default [S]
      - Extensible modular pipeline from .\modules\*.ps1
      - Generic execution hooks (preCommands, uninstall, install, postCommands)
#>

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$projectRoot = $PSScriptRoot
$configPath  = Join-Path $projectRoot "config.json"
$modulesDir  = Join-Path $projectRoot "modules"
$logsDir     = Join-Path $projectRoot "logs"
$logFile     = Join-Path $logsDir "latest-run.log"

if (-not (Test-Path $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}

# ==================================================================
# 1. ELEVATION CHECK
# ==================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Elevating FreeWinly with Administrator privileges..." -ForegroundColor Yellow
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Write-Host $Message -ForegroundColor $Color
    Add-Content -Path $logFile -Value "[$timestamp] $Message" -Encoding UTF8
}

function Show-Banner {
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "           FreeWinly - Open Source Windows Engine           " -ForegroundColor White
    Write-Host "        Freeing Windows from bloatware, caches & fees       " -ForegroundColor Gray
    Write-Host "============================================================" -ForegroundColor Cyan
}

# ==================================================================
# 2. FIRST-RUN ONBOARDING WIZARD
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
    $enabled = if ($existingConfig -and $existingConfig.enabledModules) { $existingConfig.enabledModules } else { @('10_software_updates', '20_cache_cleanup', '30_ssd_trim') }

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
    }

    $newConfig | ConvertTo-Json -Depth 5 | Out-File -FilePath $configPath -Encoding UTF8
    Write-Host "`nConfiguration created successfully at: $configPath" -ForegroundColor Green
    Start-Sleep -Seconds 2
}

if (-not (Test-Path $configPath)) {
    Run-OnboardingWizard
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json

# ==================================================================
# 3. DISCOVER MODULES
# ==================================================================
$moduleFiles = Get-ChildItem (Join-Path $modulesDir "*.ps1") -ErrorAction SilentlyContinue | Sort-Object Name
$modules = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($mf in $moduleFiles) {
    $baseName = $mf.BaseName
    $content = Get-Content $mf.FullName -TotalCount 10

    $name = $baseName
    $defaultEnabled = $true
    foreach ($line in $content) {
        if ($line -match '^#\s*Name:\s*(.+)$') { $name = $matches[1].Trim() }
        if ($line -match '^#\s*Default:\s*(.+)$') {
            $val = $matches[1].Trim()
            $defaultEnabled = ($val -eq 'true' -or $val -eq '1')
        }
    }

    $isEnabled = if ($config.enabledModules) {
        $config.enabledModules -contains $baseName
    } else {
        $defaultEnabled
    }

    $modules.Add([PSCustomObject]@{
        BaseName = $baseName
        Name     = $name
        Path     = $mf.FullName
        Enabled  = $isEnabled
    })
}

# ==================================================================
# 4. 10-SECOND COUNTDOWN (Press any key for interactive menu)
# ==================================================================
Clear-Host
Show-Banner
Write-Host "`nScheduled Tasks to Run:" -ForegroundColor Yellow

foreach ($m in $modules) {
    $mark = if ($m.Enabled) { "[x]" } else { "[ ]" }
    $col  = if ($m.Enabled) { "Green" } else { "DarkGray" }
    Write-Host "  $mark $($m.Name)" -ForegroundColor $col
}

Write-Host "`nStarting in " -NoNewline -ForegroundColor Gray
$openMenu = $false

try {
    for ($sec = 10; $sec -gt 0; $sec--) {
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

# ==================================================================
# 5. INTERACTIVE TUI MENU (if key was pressed)
# ==================================================================
if ($openMenu) {
    $selectedIndex = 0
    $totalOptions = $modules.Count + 5
    $running = $true

    while ($running) {
        Clear-Host
        Show-Banner
        Write-Host "Use [Up/Down] arrows to navigate, [Space] to toggle, [Enter] to run:`n" -ForegroundColor Gray

        for ($i = 0; $i -lt $modules.Count; $i++) {
            $m = $modules[$i]
            $pointer = if ($i -eq $selectedIndex) { "> " } else { "  " }
            $check   = if ($m.Enabled) { "[x]" } else { "[ ]" }
            $color   = if ($i -eq $selectedIndex) { "Cyan" } elseif ($m.Enabled) { "Green" } else { "DarkGray" }
            Write-Host "$pointer$check $($m.Name)" -ForegroundColor $color
        }

        Write-Host "`n------------------------------------------------------------" -ForegroundColor DarkGray

        $actions = @(
            @{ Label = "[ Enter ]  Run All Checked Tasks [x]"; Key = "Enter" },
            @{ Label = "[   S   ]  Save Selection as Default"; Key = "S" },
            @{ Label = "[   O   ]  Run First-Time Onboarding Wizard"; Key = "O" },
            @{ Label = "[   I   ]  Reinstall Start Menu Shortcut"; Key = "I" },
            @{ Label = "[   Q   ]  Quit Without Running"; Key = "Q" }
        )

        for ($j = 0; $j -lt $actions.Count; $j++) {
            $actionIdx = $modules.Count + $j
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
                if ($selectedIndex -lt $modules.Count) {
                    $modules[$selectedIndex].Enabled = -not $modules[$selectedIndex].Enabled
                }
            }
            "Enter" {
                if ($selectedIndex -lt $modules.Count) {
                    $modules[$selectedIndex].Enabled = -not $modules[$selectedIndex].Enabled
                } elseif ($selectedIndex -eq $modules.Count) {
                    # Run All Checked Tasks
                    $running = $false
                } elseif ($selectedIndex -eq ($modules.Count + 1)) {
                    # Save Selection as Default
                    $enabledList = ($modules | Where-Object { $_.Enabled } | Select-Object -ExpandProperty BaseName)
                    $config.enabledModules = @($enabledList)
                    $config | ConvertTo-Json -Depth 5 | Out-File -FilePath $configPath -Encoding UTF8
                    Write-Host "`n  -> Default tasks saved to config.json!" -ForegroundColor Green
                    Start-Sleep -Milliseconds 800
                } elseif ($selectedIndex -eq ($modules.Count + 2)) {
                    Run-OnboardingWizard
                    $config = Get-Content $configPath -Raw | ConvertFrom-Json
                } elseif ($selectedIndex -eq ($modules.Count + 3)) {
                    & (Join-Path $projectRoot "install-shortcut.ps1")
                    Read-Host "`nPress Enter to return to menu"
                } elseif ($selectedIndex -eq ($modules.Count + 4)) {
                    Write-Host "`nExiting FreeWinly." -ForegroundColor Yellow
                    exit
                }
            }
            "S" {
                $enabledList = ($modules | Where-Object { $_.Enabled } | Select-Object -ExpandProperty BaseName)
                $config.enabledModules = @($enabledList)
                $config | ConvertTo-Json -Depth 5 | Out-File -FilePath $configPath -Encoding UTF8
                Write-Host "`n  -> Default tasks saved to config.json!" -ForegroundColor Green
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
            "Q" {
                Write-Host "`nExiting FreeWinly." -ForegroundColor Yellow
                exit
            }
        }
    }
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
$activeModules = $modules | Where-Object { $_.Enabled }
Write-Log "`nExecuting $($activeModules.Count) active maintenance module(s)..." "Cyan"

foreach ($m in $activeModules) {
    try {
        & $m.Path -Config $config -LogFile $logFile
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
