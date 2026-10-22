<#
.SYNOPSIS
    FreeWinly Application Launch Hijack Repair Module (CCleaner / IFEO).
.DESCRIPTION
    100% self-contained repair module.
    Detects and restores applications that fail to launch due to orphaned Image File Execution Options (IFEO)
    debuggers. Specifically targets broken "App Sleep / Performance Optimizer" hooks left behind by CCleaner
    (CCleanerReactivator.exe), which cause Windows to display "Windows cannot find 'app.exe'" errors.
.PARAMETER Action
    'Info'  - Returns module metadata object.
    'Check' - Scans registry for hijacked or broken application launch hooks without making changes.
    'Run'   - Safely removes orphaned hooks to restore normal application launching.
.PARAMETER Config
    Optional PSCustomObject loaded from config.json.
.PARAMETER LogFile
    Optional path to the execution log file.
.PARAMETER Options
    Optional hashtable of module-specific options.
.EXAMPLE
    .\modules\07_app_hijack_repair.ps1 -Action Info
.EXAMPLE
    .\modules\07_app_hijack_repair.ps1 -Action Check
.EXAMPLE
    .\modules\07_app_hijack_repair.ps1 -Action Run
#>
[CmdletBinding()]
param(
    [ValidateSet('Info', 'Check', 'Run')]
    [string]$Action = 'Run',

    [PSCustomObject]$Config = $null,
    [string]$LogFile = $null,
    [hashtable]$Options = @{}
)

function Get-HijackedLaunchHooks {
    $ifeoRoots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
    )

    $detected = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($root in $ifeoRoots) {
        if (Test-Path $root) {
            $keys = Get-ChildItem -Path $root -ErrorAction SilentlyContinue
            foreach ($k in $keys) {
                $subKeys = Get-ChildItem -Path $k.PSPath -ErrorAction SilentlyContinue
                foreach ($sk in $subKeys) {
                    $p = Get-ItemProperty -Path $sk.PSPath -ErrorAction SilentlyContinue
                    if ($p -and $p.Debugger) {
                        $dbg = $p.Debugger -replace '^"|"$', ''
                        $dbgPath = $dbg
                        if ($dbg -match '^([A-Za-z]:\\[^"]+?\.exe)') { $dbgPath = $matches[1] }
                        $exists = Test-Path $dbgPath
                        $isCCleaner = ($dbg -match 'CCleaner')

                        if (-not $exists -or $isCCleaner) {
                            $detected.Add([PSCustomObject]@{
                                AppName      = $k.PSChildName
                                SubKey       = $sk.PSChildName
                                RegistryPath = $sk.PSPath
                                ParentPath   = $k.PSPath
                                Debugger     = $p.Debugger
                                MissingFile  = (-not $exists)
                                IsCCleaner   = $isCCleaner
                                TargetPath   = $p.FilterFullPath
                            })
                        }
                    }
                }
            }
        }
    }
    return @($detected)
}

if ($Action -eq 'Info') {
    $currentHooks = Get-HijackedLaunchHooks
    $uniqueApps = @($currentHooks | Select-Object -ExpandProperty AppName -Unique)

    return [PSCustomObject]@{
        Name          = "App Launch Hijack Repair (CCleaner / IFEO)"
        Description   = "Detects and restores applications hijacked by orphaned CCleaner sleep hooks or broken debuggers"
        Default       = ($currentHooks.Count -gt 0)
        RequiresAdmin = $true
        Options       = @{
            DetectedCount = $currentHooks.Count
            AffectedApps  = $uniqueApps
        }
    }
}

Write-Host "`n--- [Module 07] App Launch Hijack Repair [$Action] ---" -ForegroundColor Cyan

$hooks = Get-HijackedLaunchHooks
$uniqueApps = @($hooks | Select-Object -ExpandProperty AppName -Unique)

if ($hooks.Count -eq 0) {
    Write-Host "[OK] Clean record. No hijacked application launch hooks or orphaned debuggers detected." -ForegroundColor Green
    if ($LogFile) { Add-Content -Path $LogFile -Value "App Hijack Check: Clean record. No broken launch hooks found." -Encoding UTF8 }
    return
}

if ($Action -eq 'Check') {
    Write-Host "Found $($hooks.Count) hijacked launch hook(s) affecting $($uniqueApps.Count) application(s):" -ForegroundColor Yellow
    Write-Host "These applications fail to launch because Windows intercepts them with a missing debugger:`n" -ForegroundColor Gray

    foreach ($app in $uniqueApps) {
        $appHooks = @($hooks | Where-Object { $_.AppName -eq $app })
        $first = $appHooks[0]
        $source = if ($first.IsCCleaner) { "Orphaned CCleaner Sleep Hook (CCleanerReactivator.exe missing)" } else { "Broken Debugger ($($first.Debugger))" }

        Write-Host "  * Application: $app" -ForegroundColor White
        Write-Host "    Issue:       $source" -ForegroundColor Yellow
        if ($first.TargetPath) {
            Write-Host "    Target:      $($first.TargetPath)" -ForegroundColor Gray
        }
        Write-Host "    Fix:         Run FreeWinly with Admin privileges to safely remove this hook.`n" -ForegroundColor Cyan
    }

    if ($LogFile) {
        Add-Content -Path $LogFile -Value "App Hijack Check: Found $($hooks.Count) hooks affecting: $($uniqueApps -join ', ')" -Encoding UTF8
    }
    return
}

# Run Action
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERROR] Removing registry launch hooks requires Administrator privileges." -ForegroundColor Red
    if ($LogFile) { Add-Content -Path $LogFile -Value "App Hijack Repair: Failed - requires Administrator privileges." -Encoding UTF8 }
    return
}

Write-Host "Restoring $($uniqueApps.Count) hijacked application(s)..." -ForegroundColor Cyan

$repairedCount = 0
$parentsToClean = [System.Collections.Generic.HashSet[string]]::new()

foreach ($h in $hooks) {
    try {
        if (Test-Path $h.RegistryPath) {
            Remove-Item -Path $h.RegistryPath -Recurse -Force -ErrorAction Stop
            $parentsToClean.Add($h.ParentPath) | Out-Null
            $repairedCount++
        }
    } catch {
        Write-Host "Failed to remove $($h.RegistryPath): $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Clean up empty parent UseFilter properties if no other hooks exist
foreach ($parent in $parentsToClean) {
    if (Test-Path $parent) {
        $remaining = Get-ChildItem -Path $parent -ErrorAction SilentlyContinue
        if ($remaining.Count -eq 0) {
            Remove-ItemProperty -Path $parent -Name "UseFilter" -ErrorAction SilentlyContinue
        }
    }
}

Write-Host "`n[SUCCESS] Successfully removed $repairedCount orphaned launch hook(s)!" -ForegroundColor Green
Write-Host "The following application(s) have been restored to normal launching:" -ForegroundColor Cyan
foreach ($app in $uniqueApps) {
    Write-Host "  -> $app" -ForegroundColor Green
}

if ($LogFile) {
    Add-Content -Path $LogFile -Value "App Hijack Repair: Removed $repairedCount hook(s) for $($uniqueApps -join ', ')." -Encoding UTF8
}
