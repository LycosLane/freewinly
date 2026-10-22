#Requires -Version 5.1
<#
.SYNOPSIS
    FreeWinly v1.2.0 - Open Source Windows Maintenance & Optimization Engine.
.DESCRIPTION
    Native Windows maintenance suite utilizing Winget, PowerShell 5.1+, COM APIs, and TRIM.
    Supports headless CLI automation, interactive TUI menu, dry-run check previews,
    strict module contract validation, per-module scoped settings, and JIT elevation.
.PARAMETER Run
    Executes the enabled or specified modules immediately without opening the interactive menu.
.PARAMETER Check
    Performs a dry-run preview across enabled or specified modules without altering system state.
.PARAMETER Audit
    Alias for -Check. Runs the read-only diagnostic system inspection (hardware, logs, updates, storage).
.PARAMETER Modules
    Optional array or comma-separated list of module BaseNames to run (e.g. -Modules freewinly-check-hardware,freewinly-update-software).
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
    .\freewinly.ps1 -Modules freewinly-check-hardware,freewinly-update-software -Run
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
    Write-Host "         FreeWinly v1.2.0 - Open Source Windows Engine      " -ForegroundColor White
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
        countdownSeconds      = 10
        scheduleType          = "Weekly"
        scheduleDay           = "Sunday"
        scheduleTime          = "12:00"
        preCommands           = @()
        uninstall             = @()
        install               = @()
        postCommands          = @()
        modulesExecutionOrder = $null
    }
}

function Test-UserPathRegistered {
    $userPathRaw = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not $userPathRaw) { return $false }
    $normRoot = $projectRoot.TrimEnd('\')
    return (($userPathRaw.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries) | Where-Object {
        $_.Trim().TrimEnd('\').Equals($normRoot, [System.StringComparison]::OrdinalIgnoreCase)
    }).Count -gt 0)
}

function Test-ModuleContract {
    param([string]$FilePath)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($FilePath, [ref]$tokens, [ref]$parseErrors)

    if ($parseErrors -and $parseErrors.Count -gt 0) {
        return [PSCustomObject]@{
            IsValid = $false
            Reason  = "Syntax error at line $($parseErrors[0].Extent.StartLineNumber): $($parseErrors[0].Message)"
            Info    = $null
        }
    }

    if (-not $ast.ParamBlock -or -not $ast.ParamBlock.Parameters) {
        return [PSCustomObject]@{
            IsValid = $false
            Reason  = "Missing param() block with required '-Action' parameter (Info, Check, Run)."
            Info    = $null
        }
    }

    $hasActionParam = ($ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -ieq 'Action' }).Count -gt 0
    if (-not $hasActionParam) {
        return [PSCustomObject]@{
            IsValid = $false
            Reason  = "Missing required '-Action' parameter (Info, Check, Run)."
            Info    = $null
        }
    }

    $info = $null
    try {
        $info = & $FilePath -Action Info -ErrorAction Stop
    } catch {
        return [PSCustomObject]@{
            IsValid = $false
            Reason  = "Execution of '-Action Info' failed: $($_.Exception.Message)"
            Info    = $null
        }
    }

    if (-not $info) {
        return [PSCustomObject]@{
            IsValid = $false
            Reason  = "'-Action Info' returned null instead of a metadata object."
            Info    = $null
        }
    }

    if (-not ($info.Name -is [string]) -or [string]::IsNullOrWhiteSpace($info.Name)) {
        return [PSCustomObject]@{
            IsValid = $false
            Reason  = "Metadata is missing a valid 'Name' string."
            Info    = $null
        }
    }

    $cleanName = $info.Name.Trim()
    if ($cleanName.Length -lt 3 -or $cleanName.Length -gt 50) {
        return [PSCustomObject]@{
            IsValid = $false
            Reason  = "Name '$($cleanName.Substring(0, [math]::Min(25, $cleanName.Length)))...' must be 3-50 characters (got $($cleanName.Length) chars)."
            Info    = $null
        }
    }

    if ($cleanName -match '[\r\n]') {
        return [PSCustomObject]@{
            IsValid = $false
            Reason  = "Name must be a single line without newline characters."
            Info    = $null
        }
    }

    if (-not ($info.Description -is [string]) -or [string]::IsNullOrWhiteSpace($info.Description)) {
        return [PSCustomObject]@{
            IsValid = $false
            Reason  = "Metadata is missing a valid 'Description' string."
            Info    = $null
        }
    }

    if ($info.Description.Trim().Length -gt 120) {
        return [PSCustomObject]@{
            IsValid = $false
            Reason  = "Description exceeds maximum length of 120 characters ($($info.Description.Trim().Length) chars)."
            Info    = $null
        }
    }

    if (-not ($info.Default -is [bool])) {
        return [PSCustomObject]@{
            IsValid = $false
            Reason  = "Metadata 'Default' property must be a boolean (`$true or `$false)."
            Info    = $null
        }
    }

    if (-not ($info.RequiresAdmin -is [bool])) {
        return [PSCustomObject]@{
            IsValid = $false
            Reason  = "Metadata 'RequiresAdmin' property must be a boolean (`$true or `$false)."
            Info    = $null
        }
    }

    return [PSCustomObject]@{
        IsValid = $true
        Reason  = $null
        Info    = $info
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
  .\freewinly.ps1 -Modules <list>      Specify modules to run or check (e.g. -Modules freewinly-check-hardware,freewinly-update-software)
  .\freewinly.ps1 -Help                Show this help message

Core Utilities:
  .\core\freewinly-init-config.ps1     Initialize config.json & Winget exclusion wizard
  .\core\freewinly-setup-schedule.ps1  Configure Windows Task Scheduler automation
  .\core\freewinly-setup-launcher.ps1  Manage Start Menu shortcut (Install / Remove / Status)
  .\core\freewinly-setup-path.ps1      Manage User PATH registration (Install / Remove / Toggle / Status)
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
if (-not (Test-Path $configPath)) {
    $initScript = Join-Path $coreDir "freewinly-init-config.ps1"
    if (Test-Path $initScript) {
        & $initScript -ConfigPath $configPath
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
# 2. DISCOVER, VALIDATE & ORDER MODULES DYNAMICALLY
# ==================================================================
$moduleFiles = Get-ChildItem (Join-Path $modulesDir "*.ps1") -ErrorAction SilentlyContinue
$validFileMap = @{}
$ignoredWarnings = [System.Collections.Generic.List[string]]::new()

foreach ($mf in $moduleFiles) {
    $validation = Test-ModuleContract -FilePath $mf.FullName
    if (-not $validation.IsValid) {
        $msg = "[Module Ignored] '$($mf.Name)' was not loaded: $($validation.Reason)"
        $ignoredWarnings.Add($msg)
        Write-Host $msg -ForegroundColor Yellow
        continue
    }
    $validFileMap[$mf.BaseName] = [PSCustomObject]@{
        File = $mf
        Info = $validation.Info
    }
}

# Reconcile execution order:
# 1. First in the sequence defined in config.modulesExecutionOrder
# 2. Followed by any newly added modules sorted by their Info.Order
$orderedBaseNames = [System.Collections.Generic.List[string]]::new()
$hasModOrderConfig = ($null -ne $config.modulesExecutionOrder)

if ($hasModOrderConfig) {
    $cfgKeys = if ($config.modulesExecutionOrder -is [System.Collections.IDictionary]) {
        $config.modulesExecutionOrder.Keys
    } else {
        $config.modulesExecutionOrder.PSObject.Properties.Name
    }
    foreach ($k in $cfgKeys) {
        if ($validFileMap.ContainsKey($k) -and -not $orderedBaseNames.Contains($k)) {
            $orderedBaseNames.Add($k)
        }
    }
}

$newModules = @($validFileMap.Keys | Where-Object { -not $orderedBaseNames.Contains($_) } | ForEach-Object {
    [PSCustomObject]@{
        BaseName = $_
        Order    = if ($null -ne $validFileMap[$_].Info.Order) { [int]$validFileMap[$_].Info.Order } else { 99 }
    }
} | Sort-Object Order, BaseName)

foreach ($nm in $newModules) {
    $orderedBaseNames.Add($nm.BaseName)
}

$discoveredModules = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($baseName in $orderedBaseNames) {
    $entry = $validFileMap[$baseName]
    $mf    = $entry.File
    $info  = $entry.Info

    # Build merged settings object (DefaultSettings overlaid with user's config block)
    $modSettings = [ordered]@{}
    if ($info.DefaultSettings) {
        $defKeys = if ($info.DefaultSettings -is [System.Collections.IDictionary]) {
            $info.DefaultSettings.Keys
        } else {
            $info.DefaultSettings.PSObject.Properties.Name
        }
        foreach ($dk in $defKeys) {
            $modSettings[$dk] = $info.DefaultSettings[$dk]
        }
    }

    $cfgEntry = if ($hasModOrderConfig) { $config.modulesExecutionOrder.$baseName } else { $null }
    $enabledInCfg = $null

    if ($null -ne $cfgEntry) {
        if ($cfgEntry -is [bool]) {
            $enabledInCfg = $cfgEntry
        } else {
            if ($null -ne $cfgEntry.enabled) {
                $enabledInCfg = [bool]$cfgEntry.enabled
            }
            $uKeys = if ($cfgEntry -is [System.Collections.IDictionary]) {
                $cfgEntry.Keys
            } else {
                $cfgEntry.PSObject.Properties.Name
            }
            foreach ($uk in $uKeys) {
                if ($uk -ne 'enabled') {
                    $modSettings[$uk] = $cfgEntry.$uk
                }
            }
        }
    }

    # Determine if enabled:
    # - CLI -Modules override > config.modulesExecutionOrder > (if brand-new unconfigured module & config exists: false, else Info.Default)
    $isEnabled = if ($Modules) {
        $Modules -contains $baseName
    } elseif ($null -ne $enabledInCfg) {
        $enabledInCfg
    } elseif ($hasModOrderConfig) {
        # A brand-new module dropped into modules/ that was not in config.json yet defaults to disabled for safety
        $false
    } else {
        $info.Default
    }

    $settingsObj = [PSCustomObject]$modSettings

    # Update dynamic title if minAgeDays or lookbackDays was customized in settings
    $displayName = $info.Name
    if ($baseName -eq 'freewinly-clean-cache' -and $settingsObj.minAgeDays) {
        $displayName = "Safe Cache & Temp Cleanup (>$($settingsObj.minAgeDays) days)"
    } elseif ($baseName -eq 'freewinly-check-eventlog' -and $settingsObj.lookbackDays) {
        $displayName = "System Stability & Event Logs (Last $($settingsObj.lookbackDays)d)"
    }

    $isApplicable = if ($null -ne $info.Applicable) { [bool]$info.Applicable } else { $true }

    # Skip inapplicable hardware modules (e.g. HDD Defrag on SSD-only PC) from menu unless explicitly requested via -Modules
    if (-not $isApplicable -and -not ($Modules -and $Modules -contains $baseName)) {
        continue
    }

    $discoveredModules.Add([PSCustomObject]@{
        BaseName      = $baseName
        Name          = $displayName
        Description   = $info.Description
        Path          = $mf.FullName
        Enabled       = [bool]$isEnabled
        RequiresAdmin = [bool]$info.RequiresAdmin
        Settings      = $settingsObj
    })
}

function Save-ConfigState {
    $modOrder = [ordered]@{}
    foreach ($dm in $discoveredModules) {
        $block = [ordered]@{
            enabled = [bool]$dm.Enabled
        }
        if ($dm.Settings) {
            foreach ($prop in $dm.Settings.PSObject.Properties) {
                $block[$prop.Name] = $prop.Value
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
    $config | Add-Member -NotePropertyName modulesExecutionOrder -NotePropertyValue ([PSCustomObject]$modOrder) -Force
    if ($config.PSObject.Properties['enabledModules']) {
        $config.PSObject.Properties.Remove('enabledModules')
    }
    if ($config.PSObject.Properties['excluded']) {
        $config.PSObject.Properties.Remove('excluded')
    }
    $config | ConvertTo-Json -Depth 6 | Out-File -FilePath $configPath -Encoding UTF8
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
    if ($ignoredWarnings.Count -gt 0) {
        Write-Host ""
        foreach ($w in $ignoredWarnings) { Write-Host "  $w" -ForegroundColor Yellow }
    }
    Write-Host "`nScheduled Tasks to Run (in execution order):" -ForegroundColor Yellow

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
            $pathStatus = if (Test-UserPathRegistered) { "Enabled" } else { "Disabled" }

            $actions = @(
                @{ Label = "[ Enter ]  Run All Checked Tasks [x]"; Key = "Run" },
                @{ Label = "[   C   ]  Dry-Run Check / Diagnostic Audit (No changes)"; Key = "C" },
                @{ Label = "[   T   ]  Auto-Start Countdown: [ $timerText ] (Press T to cycle)"; Key = "T" },
                @{ Label = "[   W   ]  Task Scheduler: [ $schedSummary ] (Press W to configure)"; Key = "W" },
                @{ Label = "[   P   ]  User PATH CLI Auto-Complete: [ $pathStatus ] (Press P to toggle)"; Key = "P" },
                @{ Label = "[   S   ]  Save Selection & Order as Default"; Key = "S" },
                @{ Label = "[   O   ]  Run Configuration & Exclusion Wizard"; Key = "O" },
                @{ Label = "[   I   ]  Install / Update Start Menu Launcher"; Key = "I" },
                @{ Label = "[   U   ]  Uninstall FreeWinly Completely"; Key = "U" },
                @{ Label = "[   Q   ]  Quit Without Running"; Key = "Q" }
            )
            $totalOptions = $discoveredModules.Count + $actions.Count

            Clear-Host
            Show-Banner
            if ($ignoredWarnings.Count -gt 0) {
                foreach ($w in $ignoredWarnings) { Write-Host "  $w" -ForegroundColor Yellow }
            }
            Write-Host "Use [Up/Down] to navigate, [Space] to toggle, [+/-] to reorder, [Enter] to run:`n" -ForegroundColor Gray

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

            # Reorder module up/down with [+] / [-]
            if ($selectedIndex -lt $discoveredModules.Count) {
                if ($key.KeyChar -eq '-' -or $key.Key -eq 'Subtract') {
                    if ($selectedIndex -gt 0) {
                        $temp = $discoveredModules[$selectedIndex - 1]
                        $discoveredModules[$selectedIndex - 1] = $discoveredModules[$selectedIndex]
                        $discoveredModules[$selectedIndex] = $temp
                        $selectedIndex--
                    }
                    continue
                } elseif ($key.KeyChar -eq '+' -or $key.Key -eq 'Add' -or $key.KeyChar -eq '=') {
                    if ($selectedIndex -lt ($discoveredModules.Count - 1)) {
                        $temp = $discoveredModules[$selectedIndex + 1]
                        $discoveredModules[$selectedIndex + 1] = $discoveredModules[$selectedIndex]
                        $discoveredModules[$selectedIndex] = $temp
                        $selectedIndex++
                    }
                    continue
                }
            }

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
                    Save-ConfigState
                }
                "W" {
                    Clear-Host
                    & (Join-Path $coreDir "freewinly-setup-schedule.ps1")
                    $config = Get-SafeConfig -Path $configPath
                }
                "P" {
                    & (Join-Path $coreDir "freewinly-setup-path.ps1") -Action Toggle
                    Start-Sleep -Milliseconds 900
                }
                "S" {
                    Save-ConfigState
                    Write-Host "`n  -> Module selection, order, and settings saved to config.json!" -ForegroundColor Green
                    Start-Sleep -Milliseconds 800
                }
                "O" {
                    & (Join-Path $coreDir "freewinly-init-config.ps1") -ConfigPath $configPath
                    $config = Get-SafeConfig -Path $configPath
                }
                "I" {
                    & (Join-Path $coreDir "freewinly-setup-launcher.ps1")
                    Read-Host "`nPress Enter to return to menu"
                }
                "U" {
                    Clear-Host
                    & (Join-Path $coreDir "freewinly-uninstall.ps1")
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
Write-Log "FreeWinly v1.2.0 Maintenance Pipeline Started" "Cyan"
"==================================================================" | Add-Content -Path $logFile -Encoding UTF8

$configModified = $false
$settingsSnapshotBefore = ($discoveredModules | Select-Object BaseName, Enabled, Settings | ConvertTo-Json -Depth 5 -Compress)

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

if ($configModified -and (Test-Path (Split-Path -Parent $configPath))) {
    Save-ConfigState
    Write-Log "Configuration updated." "Green"
}

Write-Log "`n=== FreeWinly Finished Successfully ===" "Green"
Write-Host "`nLog saved to: $logFile" -ForegroundColor Gray

if ($isInteractiveSession) {
    Read-Host "Press Enter to close this window"
}
