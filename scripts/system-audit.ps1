#Requires -Version 5.1
<#
.SYNOPSIS
    FreeWinly Read-Only System Audit Script (100% Read-Only, No Admin Required).
    Powers diagnostic reports and AI assistant reviews without changing system state.
#>
param(
    [ValidateSet('All', 'Software', 'WindowsUpdate', 'Resources', 'EventLogs', 'HardwareSSD', 'StartupBoot', 'CleanupPreview')]
    [string]$Phase = 'All'
)

$ErrorActionPreference = "SilentlyContinue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$projectRoot = Split-Path -Parent $PSScriptRoot
$configPath  = Join-Path $projectRoot "config.json"
$config      = if (Test-Path $configPath) { Get-Content $configPath -Raw | ConvertFrom-Json } else { $null }

if ($Phase -in @('All', 'Software')) {
    Write-Host "=== [PHASE 1] SOFTWARE UPDATES (WINGET) ===" -ForegroundColor Cyan
    & winget upgrade --include-unknown --accept-source-agreements
}

if ($Phase -in @('All', 'WindowsUpdate')) {
    Write-Host "=== [PHASE 2] WINDOWS UPDATES (NATIVE COM API) ===" -ForegroundColor Cyan
    $cbsReboot = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
    $wuReboot  = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    Write-Host "RebootPending (CBS): $cbsReboot | RebootRequired (WU): $wuReboot"
    try {
        $Session  = New-Object -ComObject Microsoft.Update.Session
        $Searcher = $Session.CreateUpdateSearcher()
        $Result   = $Searcher.Search("IsInstalled=0 and IsHidden=0")
        if ($Result.Updates.Count -eq 0) {
            Write-Host "No pending Windows Updates found."
        } else {
            $Result.Updates | Select-Object Title, IsMandatory, RebootRequired,
                @{N='MaxMB';E={[math]::Round($_.MaxDownloadSize/1MB,1)}},
                @{N='Categories';E={($_.Categories | Select-Object -ExpandProperty Name) -join ', '}} |
                Format-Table -AutoSize | Out-String -Width 250
        }
    } catch {
        Write-Host "Windows Update scan error: $($_.Exception.Message)"
    }
}

if ($Phase -in @('All', 'Resources')) {
    Write-Host "=== [PHASE 3] LIVE SYSTEM LOAD & TOP PROCESSES ===" -ForegroundColor Cyan
    $os = Get-CimInstance Win32_OperatingSystem
    $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $freeGB  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $usedGB  = [math]::Round($totalGB - $freeGB, 1)
    Write-Host "RAM Used: $usedGB GB / $totalGB GB (Free: $freeGB GB) | Last Boot: $($os.LastBootUpTime)"

    Get-Process | Group-Object ProcessName | Select-Object Name, Count,
        @{N='RAM_MB';E={[math]::Round(($_.Group | Measure-Object WorkingSet64 -Sum).Sum / 1MB, 1)}},
        @{N='CPU_Sec';E={[math]::Round(($_.Group | Measure-Object CPU -Sum).Sum, 1)}} |
        Sort-Object RAM_MB -Descending | Select-Object -First 20 |
        Format-Table -AutoSize | Out-String -Width 250
}

if ($Phase -in @('All', 'EventLogs')) {
    Write-Host "=== [PHASE 4] WINDOWS EVENT LOGS (LAST 7 DAYS) ===" -ForegroundColor Cyan
    $days = if ($config -and $config.eventLogLookbackDays) { $config.eventLogLookbackDays } else { 7 }
    $start = (Get-Date).AddDays(-$days)
    Get-WinEvent -FilterHashtable @{LogName='System','Application'; Level=1,2; StartTime=$start} |
        Where-Object { $_.ProviderName -ne 'Microsoft-Windows-DistributedCOM' } |
        Group-Object ProviderName, Id |
        Select-Object Count, Name,
            @{N='Latest';E={$_.Group[0].TimeCreated}},
            @{N='SampleMessage';E={($_.Group[0].Message -replace '\r?\n',' ')}} |
        Sort-Object Count -Descending | Select-Object -First 25 |
        Format-Table -AutoSize | Out-String -Width 300
}

if ($Phase -in @('All', 'HardwareSSD')) {
    Write-Host "=== [PHASE 5] HARDWARE & SSD HEALTH ===" -ForegroundColor Cyan
    $badDevs = Get-PnpDevice | Where-Object { $_.Status -ne 'OK' }
    if (-not $badDevs) { Write-Host "All PnP devices report Status = OK." }
    else { $badDevs | Select-Object Status, Class, FriendlyName, InstanceId | Format-Table -AutoSize | Out-String -Width 250 }

    Get-PhysicalDisk | Select-Object FriendlyName, MediaType, BusType, HealthStatus, OperationalStatus, @{N='Size_GB';E={[math]::Round($_.Size/1GB,0)}} | Format-Table -AutoSize
    Get-Volume | Where-Object DriveLetter | Select-Object DriveLetter, FileSystemLabel, HealthStatus,
        @{N='Size_GB';E={[math]::Round($_.Size/1GB,1)}},
        @{N='Free_GB';E={[math]::Round($_.SizeRemaining/1GB,1)}},
        @{N='Free_Pct';E={[math]::Round(($_.SizeRemaining/$_.Size)*100,1)}} | Format-Table -AutoSize
    & fsutil behavior query DisableDeleteNotify
}

if ($Phase -in @('All', 'StartupBoot')) {
    Write-Host "=== [PHASE 6] AUTOSTART & SERVICES ===" -ForegroundColor Cyan
    Get-CimInstance Win32_StartupCommand | Select-Object Name, Location, User, Command | Format-Table -AutoSize | Out-String -Width 300
}

if ($Phase -in @('All', 'CleanupPreview')) {
    Write-Host "=== [PHASE 7] SAFE CACHE & CLEANUP PREVIEW ===" -ForegroundColor Cyan
    $targets = [ordered]@{
        'UserTemp'           = $env:TEMP
        'WindowsTemp'        = 'C:\Windows\Temp'
        'WinGetCache'        = "$env:LOCALAPPDATA\Temp\WinGet"
        'WindowsUpdateCache' = 'C:\Windows\SoftwareDistribution\Download'
        'DirectXShaderCache' = "$env:LOCALAPPDATA\D3DSCache"
        'LocalCrashDumps'    = "$env:LOCALAPPDATA\CrashDumps"
    }
    $results = foreach ($k in $targets.Keys) {
        $p = $targets[$k]
        if (Test-Path $p) {
            $files = Get-ChildItem $p -Recurse -Force -File
            $totalMB = [math]::Round(($files | Measure-Object Length -Sum).Sum / 1MB, 1)
            $oldFiles = $files | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) }
            $oldMB = [math]::Round(($oldFiles | Measure-Object Length -Sum).Sum / 1MB, 1)
            [PSCustomObject]@{ Target = $k; Path = $p; Total_MB = $totalMB; OlderThan7d_MB = $oldMB }
        }
    }
    $results | Format-Table -AutoSize
}
