#Requires -Version 5.1
<#
.SYNOPSIS
    Cleans disposable desktop application disk, code, and shader caches.
.DESCRIPTION
    A generic, data-driven application cache cleaner. Safely cleans temporary caches
    for Discord, Microsoft Teams, Slack, Steam, Visual Studio Code, and user-configured
    custom applications.
    
    Safety Guarantee:
    - Never touches cookies, credentials, browsing history, sessions, or user data.
    - Automatically skips any open applications to avoid file lock contention.
    - Enforces strict path safety: targets must reside strictly under %APPDATA%,
      %LOCALAPPDATA%, or %TEMP% at least two segments below base directories.
    - Symlinks, junctions, and reparse points are never followed or traversed.
    - Only removes cache files older than the configured threshold (default: 3 days).
.PARAMETER Action
    'Info'  - Outputs module metadata (Name, Description, Order, Default, RequiresAdmin, DefaultSettings, SettingsDescriptions).
    'Check' - Analyzes disposable caches and reports reclaimable megabytes without deleting anything.
    'Run'   - Deletes eligible cache files and reports freed disk space.
.PARAMETER Settings
    Optional module settings object or hashtable containing enabled flags, global minAgeDays, and customApps.
.PARAMETER LogFile
    Optional file path to append cleanup statistics.
.EXAMPLE
    .\modules\freewinly-clean-apps.ps1 -Action Info
.EXAMPLE
    .\modules\freewinly-clean-apps.ps1 -Action Check
.EXAMPLE
    .\modules\freewinly-clean-apps.ps1 -Action Run -Settings @{ minAgeDays = 7; discord = $false }
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('Info', 'Check', 'Run')]
    [string]$Action = 'Run',

    [Parameter()]
    [object]$Settings = $null,

    [Parameter()]
    [string]$LogFile = $null
)

$builtinAppDefinitions = [ordered]@{
    'discord' = [ordered]@{
        name    = "Discord"
        enabled = $true
        process = @('Discord')
        paths   = @(
            '%APPDATA%\discord\Cache\Cache_Data',
            '%APPDATA%\discord\Code Cache',
            '%APPDATA%\discord\GPUCache'
        )
    }
    'teams' = [ordered]@{
        name    = "Microsoft Teams"
        enabled = $true
        process = @('ms-teams', 'Teams')
        paths   = @(
            '%LOCALAPPDATA%\Packages\MSTeams_*\LocalCache\Microsoft\MSTeams\EBWebView\Default\Cache\Cache_Data',
            '%APPDATA%\Microsoft\Teams\Cache'
        )
    }
    'slack' = [ordered]@{
        name    = "Slack"
        enabled = $true
        process = @('slack')
        paths   = @(
            '%APPDATA%\Slack\Cache\Cache_Data',
            '%APPDATA%\Slack\Code Cache',
            '%APPDATA%\Slack\GPUCache'
        )
    }
    'steam' = [ordered]@{
        name    = "Steam"
        enabled = $true
        process = @('steam', 'steamwebhelper')
        paths   = @(
            '%LOCALAPPDATA%\Steam\htmlcache\Cache\Cache_Data',
            '%LOCALAPPDATA%\Steam\htmlcache\Code Cache',
            '%LOCALAPPDATA%\Steam\htmlcache\GPUCache'
        )
    }
    'vscode' = [ordered]@{
        name    = "Visual Studio Code"
        enabled = $true
        process = @('Code')
        paths   = @(
            '%APPDATA%\Code\Cache\Cache_Data',
            '%APPDATA%\Code\CachedData',
            '%APPDATA%\Code\Code Cache',
            '%APPDATA%\Code\GPUCache'
        )
    }
}

if ($Action -eq 'Info') {
    $defSettings = [ordered]@{
        minAgeDays = 3
    }
    foreach ($k in $builtinAppDefinitions.Keys) {
        $app = $builtinAppDefinitions[$k]
        $defSettings[$k] = [ordered]@{
            enabled = $app.enabled
            process = $app.process
            paths   = $app.paths
        }
    }
    $defSettings['customApps'] = [ordered]@{}

    return [PSCustomObject]@{
        Name                 = "Desktop App Cache Cleanup"
        Description          = "Purges disposable application caches for Discord, Teams, Slack, Steam, VS Code, and custom apps"
        Order                = 32
        Default              = $true
        RequiresAdmin        = $false
        DefaultSettings      = $defSettings
        SettingsDescriptions = [ordered]@{
            minAgeDays = "Minimum file age in days before purging cache files"
            discord    = "Discord cache (skips if open)"
            teams      = "Microsoft Teams cache (skips if open)"
            slack      = "Slack cache (skips if open)"
            steam      = "Steam web & HTML cache (skips if open)"
            vscode     = "Visual Studio Code cache (skips if open)"
        }
    }
}

Write-Host "`n--- [freewinly-clean-apps] Desktop App Cache Cleanup [$Action] ---" -ForegroundColor Cyan

$globalMinAgeDays = if ($null -ne $Settings -and $null -ne $Settings.minAgeDays) { [int]$Settings.minAgeDays } else { 3 }
$globalCutoff = (Get-Date).AddDays(-$globalMinAgeDays)
Write-Host "Age threshold: files older than $globalMinAgeDays days (before $($globalCutoff.ToString('yyyy-MM-dd HH:mm')))`n" -ForegroundColor Gray

function Test-AppRunning {
    param([string[]]$ProcessNames)
    if (-not $ProcessNames -or $ProcessNames.Count -eq 0) { return $false }
    foreach ($p in $ProcessNames) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        $procs = Get-Process -Name $p -ErrorAction SilentlyContinue
        if ($procs) { return $true }
    }
    return $false
}

$baseDirs = @()
foreach ($envVar in @($env:APPDATA, $env:LOCALAPPDATA, $env:TEMP)) {
    if (-not [string]::IsNullOrWhiteSpace($envVar) -and (Test-Path -LiteralPath $envVar)) {
        try {
            $resolved = [System.IO.Path]::GetFullPath($envVar).TrimEnd('\', '/')
            if (-not ($baseDirs -contains $resolved)) {
                $baseDirs += $resolved
            }
        } catch { }
    }
}

function Test-CleanAppPathSafety {
    param([string]$RawPath)
    if ([string]::IsNullOrWhiteSpace($RawPath)) {
        return @{ IsValid = $false; Reason = "Path is empty or null" }
    }

    # Normalize forward slashes and expand environment variables
    $p = $RawPath.Replace('/', '\')
    $p = [System.Environment]::ExpandEnvironmentVariables($p)

    # Collapse duplicate slashes
    while ($p -match '\\\\') { $p = $p.Replace('\\', '\') }
    $p = $p.TrimEnd('\')

    # Reject .. segments
    $segments = $p.Split('\')
    if ($segments -contains '..') {
        return @{ IsValid = $false; Reason = "Path contains forbidden '..' traversal segment" }
    }

    # Reject drive roots (e.g. C: or C:\)
    if ($p -match '^[a-zA-Z]:\\?$') {
        return @{ IsValid = $false; Reason = "Drive roots are strictly forbidden" }
    }

    # Reject invalid path characters (excluding wildcard *)
    if ($p -match '[\<\>\"\|\?\:]' -and $p -notmatch '^[a-zA-Z]:') {
        return @{ IsValid = $false; Reason = "Path contains invalid characters" }
    }

    # Wildcard validation: at most ONE '*' wildcard in entire path
    $starCount = ($p.ToCharArray() | Where-Object { $_ -eq '*' }).Count
    if ($starCount -gt 1) {
        return @{ IsValid = $false; Reason = "Path contains multiple wildcards (maximum of 1 permitted)" }
    }

    # Match against allowed base directories (%APPDATA%, %LOCALAPPDATA%, %TEMP%)
    $matchedBase = $null
    foreach ($b in $baseDirs) {
        $bSep = $b + '\'
        if ($p.Equals($b, [System.StringComparison]::OrdinalIgnoreCase)) {
            return @{ IsValid = $false; Reason = "Path cannot be the base directory itself ($b)" }
        }
        if ($p.StartsWith($bSep, [System.StringComparison]::OrdinalIgnoreCase)) {
            $matchedBase = $b
            break
        }
    }

    if (-not $matchedBase) {
        return @{ IsValid = $false; Reason = "Path must reside strictly under %APPDATA%, %LOCALAPPDATA%, or %TEMP%" }
    }

    # Segments below base
    $rel = $p.Substring($matchedBase.Length + 1)
    $relSegs = @($rel.Split('\', [System.StringSplitOptions]::RemoveEmptyEntries))

    if ($relSegs.Count -lt 2) {
        return @{ IsValid = $false; Reason = "Path must be at least 2 segments below base directory (got $($relSegs.Count) segment(s))" }
    }

    # Wildcard in first segment below base is forbidden
    if ($relSegs[0] -match '\*') {
        return @{ IsValid = $false; Reason = "Wildcard is forbidden in the first segment directly below base directory" }
    }

    return @{ IsValid = $true; Reason = $null; NormalizedPath = $p }
}

function Get-TargetDirectories {
    param([string[]]$PathPatterns)
    $dirs = [System.Collections.Generic.List[System.IO.DirectoryInfo]]::new()
    foreach ($pattern in $PathPatterns) {
        try {
            if ($pattern -match '\*') {
                $matched = Get-Item -Path $pattern -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer }
                if ($matched) {
                    foreach ($m in $matched) {
                        if ($m -and (Test-Path -LiteralPath $m.FullName)) {
                            # Skip reparse points / symlinks / junctions
                            if (-not ($m.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                                $dirs.Add($m)
                            }
                        }
                    }
                }
            } elseif (Test-Path -LiteralPath $pattern) {
                $item = Get-Item -LiteralPath $pattern -ErrorAction SilentlyContinue
                if ($item -and $item.PSIsContainer) {
                    if (-not ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                        $dirs.Add($item)
                    }
                }
            }
        } catch { }
    }
    return $dirs
}

# Assemble candidate applications: Built-ins overlaid with $Settings, plus customApps
$appsToProcess = [System.Collections.Generic.List[hashtable]]::new()

foreach ($key in $builtinAppDefinitions.Keys) {
    $appDef = $builtinAppDefinitions[$key]
    $isEnabled = $appDef.enabled

    # Check for user overrides in $Settings
    if ($null -ne $Settings) {
        $userVal = if ($Settings -is [System.Collections.IDictionary]) {
            $Settings[$key]
        } elseif ($Settings.PSObject.Properties[$key]) {
            $Settings.$key
        } else { $null }

        if ($null -ne $userVal) {
            if ($userVal -is [bool]) {
                $isEnabled = [bool]$userVal
            } elseif ($null -ne $userVal.enabled) {
                $isEnabled = [bool]$userVal.enabled
            }
        }
    }

    $appsToProcess.Add(@{
        Key        = $key
        Name       = $appDef.name
        Enabled    = $isEnabled
        Process    = $appDef.process
        Paths      = $appDef.paths
        MinAgeDays = $null
        IsCustom   = $false
    })
}

# Merge user-defined customApps
if ($null -ne $Settings) {
    $customAppsObj = if ($Settings -is [System.Collections.IDictionary]) {
        $Settings['customApps']
    } elseif ($Settings.PSObject.Properties['customApps']) {
        $Settings.customApps
    } else { $null }

    if ($null -ne $customAppsObj) {
        $customKeys = if ($customAppsObj -is [System.Collections.IDictionary]) {
            $customAppsObj.Keys
        } else {
            $customAppsObj.PSObject.Properties.Name
        }

        foreach ($ck in $customKeys) {
            $cDef = $customAppsObj.$ck
            if (-not $cDef) { continue }

            $cName = if ($cDef.name) { [string]$cDef.name } else { [string]$ck }
            $cEnabled = if ($null -ne $cDef.enabled) { [bool]$cDef.enabled } else { $true }
            $cProcess = if ($cDef.process) { @($cDef.process) } else { @() }
            $cPaths = if ($cDef.paths) { @($cDef.paths) } elseif ($cDef.path) { @($cDef.path) } else { @() }
            $cMinAge = if ($null -ne $cDef.minAgeDays) { [int]$cDef.minAgeDays } else { $null }

            $appsToProcess.Add(@{
                Key        = $ck
                Name       = $cName
                Enabled    = $cEnabled
                Process    = $cProcess
                Paths      = $cPaths
                MinAgeDays = $cMinAge
                IsCustom   = $true
            })
        }
    }
}

$totalBytes = 0
$totalFreedFiles = 0
$reportedAny = $false

foreach ($app in $appsToProcess) {
    if (-not $app.Enabled) { continue }

    $appName = $app.Name

    # 1. Skip if application is currently open
    if (Test-AppRunning -ProcessNames $app.Process) {
        Write-Host "  [-] [Skipped] $appName is currently running." -ForegroundColor Yellow
        continue
    }

    # 2. Strict path safety enforcement
    $safePaths = [System.Collections.Generic.List[string]]::new()
    $isAppIgnored = $false

    foreach ($rawPath in $app.Paths) {
        $safety = Test-CleanAppPathSafety -RawPath $rawPath
        if (-not $safety.IsValid) {
            Write-Host "  [!] [App Ignored] '$appName': $($safety.Reason)" -ForegroundColor Yellow
            $isAppIgnored = $true
            break
        }
        $safePaths.Add($safety.NormalizedPath)
    }

    if ($isAppIgnored) {
        continue
    }

    # 3. Locate target cache directories
    $dirs = Get-TargetDirectories -PathPatterns $safePaths
    if ($dirs.Count -eq 0) { continue }

    # 4. Effective age cutoff calculation (respecting 0)
    $effectiveDays = if ($null -ne $app.MinAgeDays) { [int]$app.MinAgeDays } else { $globalMinAgeDays }
    $effectiveCutoff = (Get-Date).AddDays(-$effectiveDays)

    # 5. Enumerate eligible cache files (fast recursive pass; skipping reparse points)
    $files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    foreach ($d in $dirs) {
        $found = Get-ChildItem -LiteralPath $d.FullName -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object {
            (-not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) -and
            (($_.Directory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) -and
            ($_.LastWriteTime -lt $effectiveCutoff)
        }
        if ($found) {
            foreach ($f in $found) { $files.Add($f) }
        }
    }

    if ($files.Count -eq 0) { continue }

    $reportedAny = $true
    $appBytes = ($files | Measure-Object -Property Length -Sum).Sum
    $appCount = $files.Count

    if ($Action -eq 'Run') {
        $appFreedBytes = 0
        $appFreedCount = 0
        foreach ($f in $files) {
            try {
                $len = $f.Length
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
                $appFreedBytes += $len
                $appFreedCount++
            } catch {
                # Locked files or access denied are safely skipped without error
            }
        }
        if ($appFreedCount -gt 0) {
            $totalBytes += $appFreedBytes
            $totalFreedFiles += $appFreedCount
            $mb = [math]::Round($appFreedBytes / 1MB, 1)
            Write-Host "  [+] Cleaned $appName ($appFreedCount files) -> Freed $mb MB" -ForegroundColor Green
            if ($LogFile) { Add-Content -Path $LogFile -Value "Cleaned $($appName): $appFreedCount files -> Freed $mb MB" -Encoding UTF8 }
        }
    } else {
        # Check / Preview mode
        $totalBytes += $appBytes
        $totalFreedFiles += $appCount
        $mb = [math]::Round($appBytes / 1MB, 1)
        Write-Host "  [+] $($appName): $appCount files -> $mb MB reclaimable" -ForegroundColor White
    }
}

$summaryMb = [math]::Round($totalBytes / 1MB, 1)
if ($Action -eq 'Run') {
    if ($totalBytes -gt 0) {
        Write-Host "`nTotal desktop app cache freed: $summaryMb MB ($totalFreedFiles files)." -ForegroundColor Green
        if ($LogFile) { Add-Content -Path $LogFile -Value "Total desktop app cache freed: $summaryMb MB ($totalFreedFiles files)" -Encoding UTF8 }
    } else {
        Write-Host "`nNo expired desktop app cache files needed cleanup (threshold: >$globalMinAgeDays days)." -ForegroundColor Gray
    }
} else {
    if ($totalBytes -gt 0) {
        Write-Host "`nTotal reclaimable desktop app cache: $summaryMb MB ($totalFreedFiles files)." -ForegroundColor Green
    } else {
        Write-Host "`nNo expired desktop app cache files found (threshold: >$globalMinAgeDays days)." -ForegroundColor Gray
    }
}
