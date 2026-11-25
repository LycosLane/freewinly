#Requires -Version 5.1
<#
.SYNOPSIS
    Cleans temporary files and caches older than a configured threshold.
.DESCRIPTION
    Scans and purges user temp files, Windows temp directories, WinGet download caches,
    DirectX shader caches, and local crash dump archives. Files newer than the minimum
    age threshold (default: 7 days) are preserved to avoid disrupting running processes.
.PARAMETER Action
    'Info'  - Outputs module metadata (Name, Description, Order, Default, RequiresAdmin, DefaultSettings).
    'Check' - Calculates files and reclaimable bytes without deleting anything.
    'Run'   - Deletes files meeting the age criteria.
.PARAMETER Settings
    Optional module settings object or hashtable (supports minAgeDays and cleanRecycleBin).
.PARAMETER LogFile
    Optional file path to append cleanup statistics.
.EXAMPLE
    .\modules\freewinly-clean-cache.ps1 -Action Check
.EXAMPLE
    .\modules\freewinly-clean-cache.ps1 -Action Run -Settings @{ minAgeDays = 14 }
#>
[CmdletBinding()]
param(
    [ValidateSet('Info', 'Check', 'Run')]
    [string]$Action = 'Run',

    [object]$Settings = $null,
    [string]$LogFile = $null
)

$parsedMinAge     = 0
$minAgeDays       = if ($null -ne $Settings -and [int]::TryParse([string]$Settings.minAgeDays, [ref]$parsedMinAge)) { [math]::Max(0, $parsedMinAge) } else { 7 }
$cleanShaderCache = if ($null -ne $Settings -and $null -ne $Settings.cleanShaderCache) { [bool]$Settings.cleanShaderCache } else { $false }

if ($Action -eq 'Info') {
    return [PSCustomObject]@{
        Name                 = "Safe Cache & Temp Cleanup (>$minAgeDays days)"
        Description          = "Safely purges temporary user & system files, installer caches, crash dumps and shader caches"
        Order                = 30
        Default              = $true
        RequiresAdmin        = $false
        DefaultSettings      = [ordered]@{
            minAgeDays       = 7
            cleanRecycleBin  = $false
            cleanShaderCache = $false
        }
        SettingsDescriptions = [ordered]@{
            minAgeDays       = "Minimum file age in days before deleting temp files"
            cleanRecycleBin  = "Empty Windows Recycle Bin during cleanup"
            cleanShaderCache = "DirectX Shader Cache (recompiling can cause temporary in-game stutter)"
        }
    }
}

Write-Host "`n--- [freewinly-clean-cache] Safe Cache & Temp Cleanup [$Action] ---" -ForegroundColor Cyan

$cutoff = (Get-Date).AddDays(-$minAgeDays)
$wuCutoff = (Get-Date).AddDays(-([math]::Max($minAgeDays, 14)))
Write-Host "Age threshold: files older than $minAgeDays days (before $($cutoff.ToString('yyyy-MM-dd HH:mm')))" -ForegroundColor Gray

$wingetCachePath = Join-Path $env:LOCALAPPDATA "Temp\WinGet"

$targets = [ordered]@{
    'UserTemp'               = $env:TEMP
    'WindowsTemp'            = "$env:SystemRoot\Temp"
    'WinGetCache'            = $wingetCachePath
    'WindowsUpdateCache'     = "$env:SystemRoot\SoftwareDistribution\Download"
    'LocalCrashDumps'        = "$env:LOCALAPPDATA\CrashDumps"
    'WindowsErrorReporting'  = "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive"
}

if ($cleanShaderCache) {
    $targets['DirectXShaderCache'] = "$env:LOCALAPPDATA\D3DSCache"
}

$totalBytes = 0
$results = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($k in $targets.Keys) {
    $p = $targets[$k]
    if ([string]::IsNullOrWhiteSpace($p)) { continue }
    $root = [System.IO.Path]::GetPathRoot($p)
    if ($root -and ($root.TrimEnd('\').ToUpperInvariant() -eq $p.TrimEnd('\').ToUpperInvariant())) {
        Write-Warning "Safety violation: target path '$p' is a root volume directory. Skipping."
        continue
    }
    if (Test-Path -LiteralPath $p) {
        $targetItem = Get-Item -LiteralPath $p -ErrorAction SilentlyContinue
        if ($targetItem -and ($targetItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
            Write-Host "  [-] Skipped junction / reparse point target: $p" -ForegroundColor Gray
            continue
        }
        $targetCutoff = if ($k -eq 'WindowsUpdateCache') { $wuCutoff } else { $cutoff }
        $files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
        $dirQueue = [System.Collections.Generic.Queue[System.IO.DirectoryInfo]]::new()
        if ($targetItem -and $targetItem.PSIsContainer) {
            $dirQueue.Enqueue([System.IO.DirectoryInfo]$targetItem)
        }
        while ($dirQueue.Count -gt 0) {
            $curDir = $dirQueue.Dequeue()
            if ($curDir.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
            try {
                foreach ($subDir in $curDir.GetDirectories()) {
                    if (-not ($subDir.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                        $dirQueue.Enqueue($subDir)
                    }
                }
                $wingetCachePrefix = $wingetCachePath.TrimEnd('\') + '\'
                foreach ($f in $curDir.GetFiles()) {
                    if (-not ($f.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -and
                        $f.LastWriteTime -lt $targetCutoff -and (
                            $k -ne 'UserTemp' -or -not $f.FullName.StartsWith($wingetCachePrefix, [System.StringComparison]::OrdinalIgnoreCase)
                        )) {
                        $files.Add($f)
                    }
                }
            } catch {
                if ($LogFile) { Add-Content -LiteralPath $LogFile -Value "clean-cache enumeration warning ('$($curDir.FullName)'): $($_.Exception.Message)" -Encoding UTF8 }
            }
        }
        $count = ($files | Measure-Object).Count
        $bytes = ($files | Measure-Object Length -Sum).Sum
        if ($bytes -gt 0) {
            if ($Action -eq 'Run') {
                $freedCount = 0
                $freedBytes = 0
                foreach ($f in $files) {
                    try {
                        $fLen = $f.Length
                        Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
                        $freedCount++
                        $freedBytes += $fLen
                    } catch {
                        # File is in use / locked by a running process; skip safely
                    }
                }
                if ($freedCount -gt 0) {
                    $totalBytes += $freedBytes
                    $mb = [math]::Round($freedBytes / 1MB, 1)
                    Write-Host "Cleaned $k ($freedCount files) -> Freed $mb MB" -ForegroundColor Green
                    if ($LogFile) { Add-Content -LiteralPath $LogFile -Value "Cleaned $k ($p): $freedCount files -> Freed $mb MB" -Encoding UTF8 }
                }
            } else {
                $totalBytes += $bytes
                $mb = [math]::Round($bytes / 1MB, 1)
                $results.Add([PSCustomObject]@{
                    Category  = $k
                    FileCount = $count
                    SizeMB    = $mb
                    Path      = $p
                })
            }
        }
    }
}

if ($Action -eq 'Check') {
    if ($results.Count -eq 0) {
        Write-Host "No temporary or cache files older than $minAgeDays days were found." -ForegroundColor Green
    } else {
        $tableStr = ($results | Format-Table Category, FileCount, SizeMB, Path -AutoSize | Out-String).TrimEnd()
        Write-Host $tableStr
        $totalMB = [math]::Round($totalBytes / 1MB, 1)
        Write-Host "Check preview: $totalMB MB across $($results.Count) categories eligible for cleanup." -ForegroundColor Yellow
        Write-Host "Dry run complete. No files were deleted." -ForegroundColor Green
    }
    if ($Settings -and $Settings.cleanRecycleBin -eq $true) {
        Write-Host "Recycle Bin: Will be emptied during Run." -ForegroundColor Gray
    }
    return
}

# Optional Recycle Bin Emptying (if explicitly enabled in config)
if ($Settings -and $Settings.cleanRecycleBin -eq $true) {
    Write-Host "Emptying Recycle Bin..." -ForegroundColor Gray
    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-Host "Recycle Bin emptied." -ForegroundColor Green
        if ($LogFile) { Add-Content -LiteralPath $LogFile -Value "Recycle Bin emptied." -Encoding UTF8 }
    } catch {
        Write-Host "Recycle Bin cleanup failed (see log for details)." -ForegroundColor Yellow
        if ($LogFile) { Add-Content -LiteralPath $LogFile -Value "Recycle Bin cleanup failed: $($_.Exception.Message)" -Encoding UTF8 }
    }
}

$totalMB = [math]::Round($totalBytes / 1MB, 1)
Write-Host "Total Cache Freed: $totalMB MB" -ForegroundColor Green
if ($LogFile) { Add-Content -LiteralPath $LogFile -Value "Total Cache Freed: $totalMB MB" -Encoding UTF8 }
