#Requires -Version 5.1
<#
.SYNOPSIS
    Cleans temporary files and caches older than a configured threshold.
.DESCRIPTION
    Scans and purges user temp files, Windows temp directories, WinGet download caches,
    DirectX shader caches, and local crash dump archives. Files newer than the minimum
    age threshold (default: 7 days) are preserved to avoid disrupting running processes.
.PARAMETER Action
    'Info'  - Outputs module metadata (name, description, admin requirements).
    'Check' - Calculates files and reclaimable bytes without deleting anything.
    'Run'   - Deletes files meeting the age criteria.
.PARAMETER Config
    Optional PSCustomObject loaded from config.json (reads cleanupTempMinAgeDays).
.PARAMETER LogFile
    Optional file path to append cleanup statistics.
.PARAMETER Options
    Optional hashtable of module-specific parameters.
.EXAMPLE
    .\modules\30_cache_cleanup.ps1 -Action Check
.EXAMPLE
    .\modules\30_cache_cleanup.ps1 -Action Run
#>
[CmdletBinding()]
param(
    [ValidateSet('Info', 'Check', 'Run')]
    [string]$Action = 'Run',

    [PSCustomObject]$Config = $null,
    [string]$LogFile = $null,
    [hashtable]$Options = @{}
)

$minAgeDays = if ($Config -and $Config.cleanupTempMinAgeDays) { $Config.cleanupTempMinAgeDays } else { 7 }

if ($Action -eq 'Info') {
    return [PSCustomObject]@{
        Name          = "Safe Cache & Temp Cleanup (>$minAgeDays days)"
        Description   = "Safely purges temporary user & system files, installer caches, crash dumps and shader caches older than $minAgeDays days"
        Default       = $true
        RequiresAdmin = $false
        Options       = @{
            MinAgeDays      = $minAgeDays
            CleanRecycleBin = if ($Config -and $Config.cleanRecycleBin) { [bool]$Config.cleanRecycleBin } else { $false }
        }
    }
}

Write-Host "`n--- [Module 30] Safe Cache & Temp Cleanup [$Action] ---" -ForegroundColor Cyan

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
if ($Config -and $Config.cleanRecycleBin -eq $true) {
    Write-Host "Emptying Recycle Bin..." -ForegroundColor Gray
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    Write-Host "Recycle Bin emptied." -ForegroundColor Green
    if ($LogFile) { Add-Content -Path $LogFile -Value "Recycle Bin emptied." -Encoding UTF8 }
}

$totalMB = [math]::Round($totalBytes / 1MB, 1)
Write-Host "Total Cache Freed: $totalMB MB" -ForegroundColor Green
if ($LogFile) { Add-Content -Path $LogFile -Value "Total Cache Freed: $totalMB MB" -Encoding UTF8 }
