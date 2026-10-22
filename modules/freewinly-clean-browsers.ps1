#Requires -Version 5.1
<#
.SYNOPSIS
    Cleans disposable browser and desktop application disk, shader, and code caches.
.DESCRIPTION
    Purges temporary caches from Microsoft Edge, Google Chrome, Mozilla Firefox,
    LibreWolf, Brave, Vivaldi, Opera, Discord, Microsoft Teams, Slack, Spotify, Steam,
    and Visual Studio Code.
    
    Safety Guarantee:
    - Never touches cookies, browsing history, sessions, saved passwords, or bookmarks.
    - Automatically checks running processes and skips any open applications to avoid
      file lock contention or session disruption.
    - Only removes cache files older than the configured threshold (default: 3 days).
.PARAMETER Action
    'Info'  - Outputs module metadata (Name, Description, Order, Default, RequiresAdmin, DefaultSettings, SettingsDescriptions).
    'Check' - Analyzes disposable caches and reports reclaimable megabytes without deleting anything.
    'Run'   - Deletes eligible cache files and reports freed disk space.
.PARAMETER Settings
    Optional module settings object or hashtable.
.PARAMETER LogFile
    Optional file path to append cleanup statistics.
.EXAMPLE
    .\modules\freewinly-clean-browsers.ps1 -Action Info
.EXAMPLE
    .\modules\freewinly-clean-browsers.ps1 -Action Check
.EXAMPLE
    .\modules\freewinly-clean-browsers.ps1 -Action Run -Settings @{ minAgeDays = 7; cleanChrome = $false }
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

$minAgeDays       = if ($null -ne $Settings -and $null -ne $Settings.minAgeDays) { [int]$Settings.minAgeDays } else { 3 }
$cleanEdge        = if ($null -ne $Settings -and $null -ne $Settings.cleanEdge) { [bool]$Settings.cleanEdge } else { $true }
$cleanChrome      = if ($null -ne $Settings -and $null -ne $Settings.cleanChrome) { [bool]$Settings.cleanChrome } else { $true }
$cleanFirefox     = if ($null -ne $Settings -and $null -ne $Settings.cleanFirefox) { [bool]$Settings.cleanFirefox } else { $true }
$cleanBrave       = if ($null -ne $Settings -and $null -ne $Settings.cleanBrave) { [bool]$Settings.cleanBrave } else { $true }
$cleanDesktopApps = if ($null -ne $Settings -and $null -ne $Settings.cleanDesktopApps) { [bool]$Settings.cleanDesktopApps } else { $true }

if ($Action -eq 'Info') {
    return [PSCustomObject]@{
        Name                 = "Browser & App Cache Cleanup"
        Description          = "Purges disposable browser & app caches without touching cookies or logins (skips open apps)"
        Order                = 31
        Default              = $true
        RequiresAdmin        = $false
        DefaultSettings      = [ordered]@{
            minAgeDays       = 3
            cleanEdge        = $true
            cleanChrome      = $true
            cleanFirefox     = $true
            cleanBrave       = $true
            cleanDesktopApps = $true
        }
        SettingsDescriptions = [ordered]@{
            minAgeDays       = "Minimum file age in days before purging cache files"
            cleanEdge        = "Microsoft Edge disk & shader caches (skips if open)"
            cleanChrome      = "Google Chrome disk & shader caches (skips if open)"
            cleanFirefox     = "Mozilla Firefox & LibreWolf disk cache (skips if open)"
            cleanBrave       = "Brave, Vivaldi & Opera Chromium caches (skips if open)"
            cleanDesktopApps = "Desktop app caches: Discord, Teams, Slack, Spotify, Steam, VS Code (skips if open)"
        }
    }
}

Write-Host "`n--- [freewinly-clean-browsers] Browser & App Cache Cleanup [$Action] ---" -ForegroundColor Cyan

$cutoff = (Get-Date).AddDays(-$minAgeDays)
Write-Host "Age threshold: files older than $minAgeDays days (before $($cutoff.ToString('yyyy-MM-dd HH:mm')))`n" -ForegroundColor Gray

function Test-AppRunning {
    param([string[]]$ProcessNames)
    foreach ($p in $ProcessNames) {
        $procs = Get-Process -Name $p -ErrorAction SilentlyContinue
        if ($procs) { return $true }
    }
    return $false
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
                            $dirs.Add($m)
                        }
                    }
                }
            } elseif (Test-Path -LiteralPath $pattern) {
                $item = Get-Item -LiteralPath $pattern -ErrorAction SilentlyContinue
                if ($item -and $item.PSIsContainer) {
                    $dirs.Add($item)
                }
            }
        } catch { }
    }
    return $dirs
}

$targets = @(
    # Microsoft Edge
    @{
        Category  = 'cleanEdge'
        Enabled   = $cleanEdge
        Name      = "Microsoft Edge"
        Processes = @('msedge')
        Paths     = @(
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\*\Cache\Cache_Data",
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\*\Code Cache",
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\*\GPUCache"
        )
    },
    # Google Chrome
    @{
        Category  = 'cleanChrome'
        Enabled   = $cleanChrome
        Name      = "Google Chrome"
        Processes = @('chrome')
        Paths     = @(
            "$env:LOCALAPPDATA\Google\Chrome\User Data\*\Cache\Cache_Data",
            "$env:LOCALAPPDATA\Google\Chrome\User Data\*\Code Cache",
            "$env:LOCALAPPDATA\Google\Chrome\User Data\*\GPUCache"
        )
    },
    # Mozilla Firefox
    @{
        Category  = 'cleanFirefox'
        Enabled   = $cleanFirefox
        Name      = "Mozilla Firefox"
        Processes = @('firefox')
        Paths     = @(
            "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\cache2\entries",
            "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\startupCache"
        )
    },
    # LibreWolf
    @{
        Category  = 'cleanFirefox'
        Enabled   = $cleanFirefox
        Name      = "LibreWolf"
        Processes = @('librewolf')
        Paths     = @(
            "$env:LOCALAPPDATA\LibreWolf\Profiles\*\cache2\entries"
        )
    },
    # Brave
    @{
        Category  = 'cleanBrave'
        Enabled   = $cleanBrave
        Name      = "Brave Browser"
        Processes = @('brave')
        Paths     = @(
            "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\*\Cache\Cache_Data",
            "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\*\Code Cache",
            "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\*\GPUCache"
        )
    },
    # Vivaldi
    @{
        Category  = 'cleanBrave'
        Enabled   = $cleanBrave
        Name      = "Vivaldi"
        Processes = @('vivaldi')
        Paths     = @(
            "$env:LOCALAPPDATA\Vivaldi\User Data\*\Cache\Cache_Data"
        )
    },
    # Opera
    @{
        Category  = 'cleanBrave'
        Enabled   = $cleanBrave
        Name      = "Opera"
        Processes = @('opera')
        Paths     = @(
            "$env:LOCALAPPDATA\Opera Software\Opera Stable\Cache\Cache_Data"
        )
    },
    # Discord
    @{
        Category  = 'cleanDesktopApps'
        Enabled   = $cleanDesktopApps
        Name      = "Discord"
        Processes = @('Discord')
        Paths     = @(
            "$env:APPDATA\discord\Cache\Cache_Data",
            "$env:APPDATA\discord\Code Cache",
            "$env:APPDATA\discord\GPUCache"
        )
    },
    # Microsoft Teams
    @{
        Category  = 'cleanDesktopApps'
        Enabled   = $cleanDesktopApps
        Name      = "Microsoft Teams"
        Processes = @('ms-teams', 'Teams')
        Paths     = @(
            "$env:LOCALAPPDATA\Packages\MSTeams_*\LocalCache\Microsoft\MSTeams\EBWebView\Default\Cache\Cache_Data",
            "$env:APPDATA\Microsoft\Teams\Cache"
        )
    },
    # Slack
    @{
        Category  = 'cleanDesktopApps'
        Enabled   = $cleanDesktopApps
        Name      = "Slack"
        Processes = @('slack')
        Paths     = @(
            "$env:APPDATA\Slack\Cache\Cache_Data",
            "$env:APPDATA\Slack\Code Cache",
            "$env:APPDATA\Slack\GPUCache"
        )
    },
    # Spotify
    @{
        Category  = 'cleanDesktopApps'
        Enabled   = $cleanDesktopApps
        Name      = "Spotify"
        Processes = @('Spotify')
        Paths     = @(
            "$env:LOCALAPPDATA\Spotify\Data",
            "$env:LOCALAPPDATA\Spotify\Browser\Cache",
            "$env:LOCALAPPDATA\Spotify\Browser\GPUCache",
            "$env:LOCALAPPDATA\Spotify\Browser\Code Cache"
        )
    },
    # Steam
    @{
        Category  = 'cleanDesktopApps'
        Enabled   = $cleanDesktopApps
        Name      = "Steam"
        Processes = @('steam')
        Paths     = @(
            "$env:LOCALAPPDATA\Steam\htmlcache\Cache\Cache_Data",
            "$env:LOCALAPPDATA\Steam\htmlcache\Code Cache",
            "$env:LOCALAPPDATA\Steam\htmlcache\GPUCache"
        )
    },
    # VS Code
    @{
        Category  = 'cleanDesktopApps'
        Enabled   = $cleanDesktopApps
        Name      = "Visual Studio Code"
        Processes = @('Code')
        Paths     = @(
            "$env:APPDATA\Code\Cache\Cache_Data",
            "$env:APPDATA\Code\CachedData",
            "$env:APPDATA\Code\Code Cache",
            "$env:APPDATA\Code\GPUCache"
        )
    }
)

$totalBytes = 0
$totalFreedFiles = 0
$reportedAny = $false

foreach ($target in $targets) {
    if (-not $target.Enabled) { continue }

    $appName = $target.Name

    # Check if application is currently open
    if (Test-AppRunning -ProcessNames $target.Processes) {
        Write-Host "  [-] Skipped $appName (Application is currently open)." -ForegroundColor Yellow
        continue
    }

    $dirs = Get-TargetDirectories -PathPatterns $target.Paths
    if ($dirs.Count -eq 0) { continue }

    # Find files older than threshold
    $files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    foreach ($d in $dirs) {
        $found = Get-ChildItem -LiteralPath $d.FullName -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object {
            $_.LastWriteTime -lt $cutoff
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
                # File locked or access denied; skip safely
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
        Write-Host "`nTotal browser & app cache freed: $summaryMb MB ($totalFreedFiles files)." -ForegroundColor Green
        if ($LogFile) { Add-Content -Path $LogFile -Value "Total browser & app cache freed: $summaryMb MB ($totalFreedFiles files)" -Encoding UTF8 }
    } else {
        Write-Host "`nNo expired browser or app cache files needed cleanup (threshold: >$minAgeDays days)." -ForegroundColor Gray
    }
} else {
    if ($totalBytes -gt 0) {
        Write-Host "`nTotal reclaimable browser & app cache: $summaryMb MB ($totalFreedFiles files)." -ForegroundColor Green
    } else {
        Write-Host "`nNo expired browser or app cache files found (threshold: >$minAgeDays days)." -ForegroundColor Gray
    }
}
