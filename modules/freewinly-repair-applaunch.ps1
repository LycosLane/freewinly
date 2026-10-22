#Requires -Version 5.1
<#
.SYNOPSIS
    Inspects and repairs application launch interceptors in Image File Execution Options (IFEO).
.DESCRIPTION
    Scans the registry for programs configured with external launch debuggers.
    
    Distinguishes between:
    - Broken launch pointers: The configured helper or debugger binary no longer exists on disk
      (frequently left behind by uninstalled optimizer or sleep utilities). These prevent programs
      from starting and are safely removed.
    - Active launch interceptors: The configured tool exists on disk. These are reported for
      situational awareness, but are ignored and left untouched.
.PARAMETER Action
    'Info'  - Outputs module metadata (Name, Description, Order, Default, RequiresAdmin, DefaultSettings).
    'Check' - Inspects registry for broken launch pointers without making changes.
    'Run'   - Removes broken launch pointers from the registry. Requires Administrator rights.
.PARAMETER Settings
    Optional module settings object or hashtable.
.PARAMETER LogFile
    Optional file path to append diagnostic and repair results.
.EXAMPLE
    .\modules\freewinly-repair-applaunch.ps1 -Action Check
.EXAMPLE
    .\modules\freewinly-repair-applaunch.ps1 -Action Run
#>
[CmdletBinding()]
param(
    [ValidateSet('Info', 'Check', 'Run')]
    [string]$Action = 'Run',

    [object]$Settings = $null,
    [string]$LogFile = $null
)

function Get-LikelyAssociatedTool {
    param([string]$DebuggerPath)
    if ($DebuggerPath -match 'CCleaner|Piriform') {
        return "CCleaner (Sleep Mode / Performance Optimizer)"
    } elseif ($DebuggerPath -match 'Avast') {
        return "Avast Cleanup (Sleep Mode)"
    } elseif ($DebuggerPath -match 'AVG|Tuneup') {
        return "AVG TuneUp (Sleep Mode)"
    } elseif ($DebuggerPath -match 'IObit|AdvancedSystemCare') {
        return "IObit SystemCare / Uninstaller"
    } elseif ($DebuggerPath -match 'Razer|Cortex') {
        return "Razer Cortex"
    } else {
        return "Uninstalled or missing external utility / debugger"
    }
}

function Get-LaunchInterceptors {
    $ifeoRoots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
    )

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($root in $ifeoRoots) {
        if (Test-Path $root) {
            $keys = Get-ChildItem -Path $root -ErrorAction SilentlyContinue
            foreach ($k in $keys) {
                # 1. Check direct Debugger value on the image key
                $directProp = Get-ItemProperty -Path $k.PSPath -ErrorAction SilentlyContinue
                if ($directProp -and $directProp.Debugger) {
                    $dbg = $directProp.Debugger -replace '^"|"$', ''
                    $dbgPath = $dbg
                    if ($dbg -match '^([A-Za-z]:\\[^"]+?\.exe)') { $dbgPath = $matches[1] }
                    $exists = Test-Path $dbgPath

                    $results.Add([PSCustomObject]@{
                        AppName      = $k.PSChildName
                        SubKey       = $null
                        RegistryPath = $k.PSPath
                        ParentPath   = $k.PSPath
                        Debugger     = $directProp.Debugger
                        DebuggerPath = $dbgPath
                        FileExists   = $exists
                        IsBroken     = (-not $exists)
                        LikelySource = (Get-LikelyAssociatedTool -DebuggerPath $directProp.Debugger)
                        TargetPath   = $null
                    })
                }

                # 2. Check filtered subkeys (used by modern sleep tools)
                $subKeys = Get-ChildItem -Path $k.PSPath -ErrorAction SilentlyContinue
                foreach ($sk in $subKeys) {
                    $p = Get-ItemProperty -Path $sk.PSPath -ErrorAction SilentlyContinue
                    if ($p -and $p.Debugger) {
                        $dbg = $p.Debugger -replace '^"|"$', ''
                        $dbgPath = $dbg
                        if ($dbg -match '^([A-Za-z]:\\[^"]+?\.exe)') { $dbgPath = $matches[1] }
                        $exists = Test-Path $dbgPath

                        $results.Add([PSCustomObject]@{
                            AppName      = $k.PSChildName
                            SubKey       = $sk.PSChildName
                            RegistryPath = $sk.PSPath
                            ParentPath   = $k.PSPath
                            Debugger     = $p.Debugger
                            DebuggerPath = $dbgPath
                            FileExists   = $exists
                            IsBroken     = (-not $exists)
                            LikelySource = (Get-LikelyAssociatedTool -DebuggerPath $p.Debugger)
                            TargetPath   = $p.FilterFullPath
                        })
                    }
                }
            }
        }
    }
    return @($results)
}

$allHooks = Get-LaunchInterceptors
$brokenHooks = @($allHooks | Where-Object { $_.IsBroken })
$activeHooks = @($allHooks | Where-Object { -not $_.IsBroken })

$brokenApps = @($brokenHooks | Select-Object -ExpandProperty AppName -Unique)
$activeApps = @($activeHooks | Select-Object -ExpandProperty AppName -Unique)

if ($Action -eq 'Info') {
    return [PSCustomObject]@{
        Name            = "App Launch Repair (Sleep Hooks)"
        Description     = "Repairs applications blocked by missing launch interceptors (e.g. from uninstalled sleep utilities)"
        Order           = 12
        Default         = $true
        RequiresAdmin   = ($brokenHooks.Count -gt 0)
        DefaultSettings = [ordered]@{}
    }
}

Write-Host "`n--- [freewinly-repair-applaunch] App Launch Repair [$Action] ---" -ForegroundColor Cyan

# Informational section: Active tools
if ($activeHooks.Count -gt 0) {
    Write-Host "[Info] Detected $($activeHooks.Count) active launch interceptor(s) on $($activeApps.Count) application(s):" -ForegroundColor Gray
    foreach ($app in $activeApps) {
        $firstActive = @($activeHooks | Where-Object { $_.AppName -eq $app })[0]
        Write-Host "  * Application: $app" -ForegroundColor Gray
        Write-Host "    Launcher:    $($firstActive.Debugger)" -ForegroundColor DarkGray
        Write-Host "    Status:      File exists on disk (active tool installed - will be ignored and left untouched)`n" -ForegroundColor DarkGray
    }
    if ($LogFile) {
        Add-Content -Path $LogFile -Value "App Launch Info: Active launch interceptors detected (ignored): $($activeApps -join ', ')" -Encoding UTF8
    }
}

# Broken pointers section
if ($brokenHooks.Count -eq 0) {
    Write-Host "[OK] All application launch pointers are healthy. Zero broken launch interceptors found." -ForegroundColor Green
    if ($LogFile) { Add-Content -Path $LogFile -Value "App Launch Check: Clean record. No broken launch pointers found." -Encoding UTF8 }
    return
}

if ($Action -eq 'Check') {
    Write-Host "Found $($brokenHooks.Count) broken launch pointer(s) affecting $($brokenApps.Count) application(s):" -ForegroundColor Yellow
    Write-Host "Windows cannot launch these applications because they point to a helper file that no longer exists:`n" -ForegroundColor Gray

    foreach ($app in $brokenApps) {
        $appHooks = @($brokenHooks | Where-Object { $_.AppName -eq $app })
        $first = $appHooks[0]

        Write-Host "  * Application: $app" -ForegroundColor White
        Write-Host "    Missing:     $($first.Debugger)" -ForegroundColor Red
        Write-Host "    Likely from: $($first.LikelySource)" -ForegroundColor Yellow
        if ($first.TargetPath) {
            Write-Host "    Target Path: $($first.TargetPath)" -ForegroundColor Gray
        }
        Write-Host "    Remediation: FreeWinly can safely remove this dead pointer to restore direct launching.`n" -ForegroundColor Cyan
    }

    if ($LogFile) {
        Add-Content -Path $LogFile -Value "App Launch Check: Found $($brokenHooks.Count) broken pointers affecting: $($brokenApps -join ', ')" -Encoding UTF8
    }
    return
}

# Run Action
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERROR] Removing registry launch pointers requires Administrator privileges." -ForegroundColor Red
    if ($LogFile) { Add-Content -Path $LogFile -Value "App Launch Repair: Failed - requires Administrator privileges." -Encoding UTF8 }
    return
}

Write-Host "Restoring $($brokenApps.Count) application(s) with broken launch pointers..." -ForegroundColor Cyan

$repairedCount = 0
$parentsToClean = [System.Collections.Generic.HashSet[string]]::new()

foreach ($h in $brokenHooks) {
    try {
        if ($h.SubKey -and (Test-Path $h.RegistryPath)) {
            # Subkey filter entry
            Remove-Item -Path $h.RegistryPath -Recurse -Force -ErrorAction Stop
            $parentsToClean.Add($h.ParentPath) | Out-Null
            $repairedCount++
        } elseif (-not $h.SubKey -and (Test-Path $h.RegistryPath)) {
            # Direct Debugger value
            Remove-ItemProperty -Path $h.RegistryPath -Name "Debugger" -ErrorAction Stop
            $repairedCount++
        }
    } catch {
        Write-Host "Failed to remove $($h.RegistryPath): $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Clean up empty parent UseFilter properties if no remaining subkeys exist
foreach ($parent in $parentsToClean) {
    if (Test-Path $parent) {
        $remaining = Get-ChildItem -Path $parent -ErrorAction SilentlyContinue
        if ($remaining.Count -eq 0) {
            Remove-ItemProperty -Path $parent -Name "UseFilter" -ErrorAction SilentlyContinue
        }
    }
}

Write-Host "`n[SUCCESS] Successfully removed $repairedCount broken launch pointer(s)!" -ForegroundColor Green
Write-Host "Direct launching restored for:" -ForegroundColor Cyan
foreach ($app in $brokenApps) {
    Write-Host "  -> $app" -ForegroundColor Green
}

if ($LogFile) {
    Add-Content -Path $LogFile -Value "App Launch Repair: Removed $repairedCount broken pointer(s) for $($brokenApps -join ', ')." -Encoding UTF8
}
