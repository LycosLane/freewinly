# Name: Safe Cache & Temp Cleanup (>7 days)
# Default: True
# Description: Safely purges temporary user & system files, installer caches, and shader caches older than 7 days

param(
    [PSCustomObject]$Config,
    [string]$LogFile
)

Write-Host "`n--- [Module 20] Safe Cache & Temp Cleanup ---" -ForegroundColor Cyan

$minAgeDays = if ($Config -and $Config.cleanupTempMinAgeDays) { $Config.cleanupTempMinAgeDays } else { 7 }
$cutoff = (Get-Date).AddDays(-$minAgeDays)

$targets = @{
    'UserTemp'           = $env:TEMP
    'WindowsTemp'        = 'C:\Windows\Temp'
    'WinGetCache'        = "$env:LOCALAPPDATA\Temp\WinGet"
    'WindowsUpdateCache' = 'C:\Windows\SoftwareDistribution\Download'
    'DirectXShaderCache' = "$env:LOCALAPPDATA\D3DSCache"
}

$totalFreedBytes = 0
foreach ($k in $targets.Keys) {
    $p = $targets[$k]
    if (Test-Path $p) {
        $files = Get-ChildItem $p -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoff }
        $bytes = ($files | Measure-Object Length -Sum).Sum
        if ($bytes -gt 0) {
            $files | Remove-Item -Force -ErrorAction SilentlyContinue
            $totalFreedBytes += $bytes
            $freedMB = [math]::Round($bytes/1MB, 1)
            Write-Host "Cleaned $k -> Freed $freedMB MB" -ForegroundColor Green
            if ($LogFile) { Add-Content -Path $LogFile -Value "Cleaned $k ($p) -> Freed $freedMB MB" -Encoding UTF8 }
        }
    }
}

$totalMB = [math]::Round($totalFreedBytes/1MB, 1)
Write-Host "Total Cache Freed: $totalMB MB" -ForegroundColor Green
if ($LogFile) { Add-Content -Path $LogFile -Value "Total Cache Freed: $totalMB MB" -Encoding UTF8 }
