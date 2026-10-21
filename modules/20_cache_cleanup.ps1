<#
.SYNOPSIS
    FreeWinly Safe Cache & Temp Cleanup Module.
.DESCRIPTION
    Safely purges temporary user & system files, installer caches, crash dumps, and shader caches older than 7 days.
.PARAMETER Action
    'Info'  - Returns module metadata object (Name, Description, Default, RequiresAdmin, Options).
    'Check' - Calculates files and bytes eligible for cleanup without deleting anything.
    'Run'   - Deletes files older than the configured age threshold.
.PARAMETER Config
    Optional PSCustomObject loaded from config.json.
.PARAMETER LogFile
    Optional path to the execution log file.
.PARAMETER Options
    Optional hashtable of module-specific options.
.EXAMPLE
    .\modules\20_cache_cleanup.ps1 -Action Info
.EXAMPLE
    .\modules\20_cache_cleanup.ps1 -Action Check
.EXAMPLE
    .\modules\20_cache_cleanup.ps1 -Action Run
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
        Id            = "20_cache_cleanup"
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

Write-Host "`n--- [Module 20] Safe Cache & Temp Cleanup [$Action] ---" -ForegroundColor Cyan

$cutoff = (Get-Date).AddDays(-$minAgeDays)
Write-Host "Age threshold: files older than $minAgeDays days (before $($cutoff.ToString('yyyy-MM-dd HH:mm')))" -ForegroundColor Gray

$targets = [ordered]@{
    'UserTemp'               = $env:TEMP
    'WindowsTemp'            = 'C:\Windows\Temp'
    'WinGetCache'            = "$env:LOCALAPPDATA\Temp\WinGet"
    'WindowsUpdateCache'     = 'C:\Windows\SoftwareDistribution\Download'
    'DirectXShaderCache'     = "$env:LOCALAPPDATA\D3DSCache"
    'LocalCrashDumps'        = "$env:LOCALAPPDATA\CrashDumps"
    'WindowsErrorReporting'  = "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive"
}

$totalBytes = 0
$results = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($k in $targets.Keys) {
    $p = $targets[$k]
    if (Test-Path $p) {
        $files = Get-ChildItem $p -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoff }
        $count = ($files | Measure-Object).Count
        $bytes = ($files | Measure-Object Length -Sum).Sum
        if ($bytes -gt 0) {
            $totalBytes += $bytes
            $mb = [math]::Round($bytes / 1MB, 1)

            if ($Action -eq 'Run') {
                $files | Remove-Item -Force -ErrorAction SilentlyContinue
                Write-Host "Cleaned $k ($count files) -> Freed $mb MB" -ForegroundColor Green
                if ($LogFile) { Add-Content -Path $LogFile -Value "Cleaned $k ($p): $count files -> Freed $mb MB" -Encoding UTF8 }
            } else {
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
