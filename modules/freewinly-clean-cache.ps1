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

$minAgeDays = if ($Settings -and $Settings.minAgeDays) { [int]$Settings.minAgeDays } else { 7 }

if ($Action -eq 'Info') {
    return [PSCustomObject]@{
        Name                 = "Safe Cache & Temp Cleanup (>$minAgeDays days)"
        Description          = "Safely purges temporary user & system files, installer caches, crash dumps and shader caches"
        Order                = 30
        Default              = $true
        RequiresAdmin        = $false
        DefaultSettings      = [ordered]@{
            minAgeDays      = 7
            cleanRecycleBin = $false
        }
        SettingsDescriptions = [ordered]@{
            minAgeDays      = "Minimum file age in days before deleting temp files"
            cleanRecycleBin = "Empty Windows Recycle Bin during cleanup"
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
    'DirectXShaderCache'     = "$env:LOCALAPPDATA\D3DSCache"
    'LocalCrashDumps'        = "$env:LOCALAPPDATA\CrashDumps"
    'WindowsErrorReporting'  = "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive"
}

$totalBytes = 0
$results = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($k in $targets.Keys) {
    $p = $targets[$k]
    if (Test-Path $p) {
        $targetCutoff = if ($k -eq 'WindowsUpdateCache') { $wuCutoff } else { $cutoff }
        $files = Get-ChildItem $p -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object {
            $_.LastWriteTime -lt $targetCutoff -and (
                $k -ne 'UserTemp' -or -not $_.FullName.StartsWith($wingetCachePath, [System.StringComparison]::OrdinalIgnoreCase)
            )
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
                    if ($LogFile) { Add-Content -Path $LogFile -Value "Cleaned $k ($p): $freedCount files -> Freed $mb MB" -Encoding UTF8 }
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
        $results | Format-Table Category, FileCount, SizeMB, Path -AutoSize
        $totalMB = [math]::Round($totalBytes / 1MB, 1)
        Write-Host "Check preview: $totalMB MB across $($results.Count) categories eligible for cleanup." -ForegroundColor Yellow
        Write-Host "Dry run complete. No files were deleted." -ForegroundColor Green
    }
    return
}

# Optional Recycle Bin Emptying (if explicitly enabled in config)
if ($Settings -and $Settings.cleanRecycleBin -eq $true) {
    Write-Host "Emptying Recycle Bin..." -ForegroundColor Gray
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    Write-Host "Recycle Bin emptied." -ForegroundColor Green
    if ($LogFile) { Add-Content -Path $LogFile -Value "Recycle Bin emptied." -Encoding UTF8 }
}

$totalMB = [math]::Round($totalBytes / 1MB, 1)
Write-Host "Total Cache Freed: $totalMB MB" -ForegroundColor Green
if ($LogFile) { Add-Content -Path $LogFile -Value "Total Cache Freed: $totalMB MB" -Encoding UTF8 }
