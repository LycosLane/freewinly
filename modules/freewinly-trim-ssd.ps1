#Requires -Version 5.1
<#
.SYNOPSIS
    Sends native TRIM commands to internal solid-state drives (SSDs).
.DESCRIPTION
    Detects fixed NVMe and SATA SSDs using Windows storage cmdlets, excluding external
    USB drives and mechanical hard drives. Executes Optimize-Volume with the -ReTrim
    parameter to maintain flash memory performance and endurance.
.PARAMETER Action
    'Info'  - Outputs module metadata (Name, Description, Order, Default, RequiresAdmin, DefaultSettings).
    'Check' - Displays detected SSD partitions and TRIM support status without trimming.
    'Run'   - Issues TRIM commands to eligible SSD volumes. Requires Administrator rights.
.PARAMETER Settings
    Optional module settings object or hashtable (supports excludedDrives, minIntervalDays, lastRun).
.PARAMETER LogFile
    Optional file path to append TRIM results.
.EXAMPLE
    .\modules\freewinly-trim-ssd.ps1 -Action Check
.EXAMPLE
    .\modules\freewinly-trim-ssd.ps1 -Action Run -Settings @{ excludedDrives = @('D') }
#>
[CmdletBinding()]
param(
    [ValidateSet('Info', 'Check', 'Run')]
    [string]$Action = 'Run',

    [object]$Settings = $null,
    [string]$LogFile = $null
)

if ($Action -eq 'Info') {
    return [PSCustomObject]@{
        Name                 = "SSD TRIM Optimization"
        Description          = "Sends native NVMe/SATA TRIM hints to SSD volumes (never defrags)"
        Order                = 34
        Default              = $true
        RequiresAdmin        = $true
        DefaultSettings      = [ordered]@{
            excludedDrives  = @()
            minIntervalDays = 0
            lastRun         = $null
        }
        SettingsDescriptions = [ordered]@{
            minIntervalDays = "Minimum days between SSD TRIM runs (0 = every run)"
        }
    }
}

function Get-InstalledFixedSSDs {
    $found = [System.Collections.Generic.List[PSCustomObject]]::new()
    $allDisks = @()
    try {
        $allDisks = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)
        $disks = $allDisks | Where-Object {
            ($_.MediaType -eq 'SSD' -and $_.BusType -ne 'USB') -or
            ($_.MediaType -eq 'Unspecified' -and ($_.BusType -eq 'Virtual' -or $_.FriendlyName -match 'Virtual|VBOX|VMware|QEMU|VirtIO|Msft'))
        }
        foreach ($disk in $disks) {
            $volumes = $disk | Get-Disk -ErrorAction SilentlyContinue |
                               Get-Partition -ErrorAction SilentlyContinue |
                               Get-Volume -ErrorAction SilentlyContinue |
                               Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' }
            foreach ($v in $volumes) {
                $found.Add([PSCustomObject]@{
                    DriveLetter = [string]$v.DriveLetter
                    Label       = $v.FileSystemLabel
                    Model       = $disk.FriendlyName
                    BusType     = $disk.BusType
                    SizeGB      = [math]::Round($v.Size / 1GB, 1)
                    FreeGB      = [math]::Round($v.SizeRemaining / 1GB, 1)
                })
            }
        }
    } catch { }

    if ($found.Count -eq 0 -and $allDisks.Count -eq 0 -and (Test-Path 'C:\')) {
        $cVol = Get-Volume -DriveLetter C -ErrorAction SilentlyContinue
        if ($cVol -and $cVol.DriveType -eq 'Fixed') {
            $found.Add([PSCustomObject]@{
                DriveLetter = 'C'
                Label       = $cVol.FileSystemLabel
                Model       = 'Primary Fixed Drive'
                BusType     = 'Internal'
                SizeGB      = [math]::Round($cVol.Size / 1GB, 1)
                FreeGB      = [math]::Round($cVol.SizeRemaining / 1GB, 1)
            })
        }
    }
    return @($found)
}

Write-Host "`n--- [freewinly-trim-ssd] SSD TRIM Optimization [$Action] ---" -ForegroundColor Cyan

$detectedDrives = Get-InstalledFixedSSDs
$detectedDriveLetters = @($detectedDrives | Select-Object -ExpandProperty DriveLetter)

if ($detectedDriveLetters.Count -eq 0) {
    Write-Host "No fixed SSD drives detected on this PC." -ForegroundColor Yellow
    return
}

# Resolve excluded drives and target drives
$excludedLetters = @()
if ($Settings -and $Settings.excludedDrives) {
    $excludedLetters = @($Settings.excludedDrives | ForEach-Object { ([string]$_).TrimEnd(':').ToUpper() })
}

$targetDriveLetters = if ($Settings -and $Settings.drives) {
    @($Settings.drives | ForEach-Object { ([string]$_).TrimEnd(':').ToUpper() })
} else {
    @($detectedDriveLetters | Where-Object { $excludedLetters -notcontains $_.ToUpper() })
}

# Resolve optional cadence interval
$minDays = if ($Settings -and $Settings.minIntervalDays) { [int]$Settings.minIntervalDays } else { 0 }
$lastRunStr = if ($Settings -and $Settings.lastRun) { [string]$Settings.lastRun } else { $null }
$lastRunDate = if ($lastRunStr) { try { [datetime]$lastRunStr } catch { $null } } else { $null }
$daysSince = if ($lastRunDate) { ((Get-Date) - $lastRunDate).TotalDays } else { [double]::MaxValue }
$isDue = ($minDays -le 0) -or ($daysSince -ge $minDays)

if ($Action -eq 'Check') {
    Write-Host "[Check Mode] Querying operating system TRIM support..." -ForegroundColor Gray
    try {
        & fsutil behavior query DisableDeleteNotify
    } catch {
        Write-Host "Could not query fsutil DisableDeleteNotify." -ForegroundColor Gray
    }

    Write-Host "`nDetected SSD Physical Drives & Partitions (Removable USB excluded):" -ForegroundColor Yellow
    $detectedDrives | Format-Table DriveLetter, Label, Model, BusType, SizeGB, FreeGB -AutoSize

    if ($excludedLetters.Count -gt 0) {
        Write-Host "Excluded drives: $($excludedLetters -join ', ')" -ForegroundColor Gray
    }
    Write-Host "Target drives for TRIM: $(if ($targetDriveLetters.Count -gt 0) { $targetDriveLetters -join ', ' } else { 'None (all excluded)' })" -ForegroundColor Cyan

    if ($minDays -gt 0) {
        if ($lastRunDate) {
            Write-Host "Cadence: Every $minDays day(s) | Last run: $($lastRunDate.ToString('yyyy-MM-dd')) ($([math]::Round($daysSince, 0)) days ago)." -ForegroundColor Gray
        } else {
            Write-Host "Cadence: Every $minDays day(s) | Last run: Never recorded." -ForegroundColor Gray
        }
        if (-not $isDue) {
            $nextDate = $lastRunDate.AddDays($minDays).ToString('yyyy-MM-dd')
            Write-Host "Status: SKIPPED (Next eligible run is $nextDate)." -ForegroundColor Yellow
        }
    }

    Write-Host "Dry run complete. No TRIM commands were sent." -ForegroundColor Green
    return
}

if ($targetDriveLetters.Count -eq 0) {
    Write-Host "All detected SSD drives are excluded in settings. Skipping TRIM." -ForegroundColor Yellow
    return
}

if (-not $isDue) {
    Write-Host "SSD TRIM skipped: Only $([math]::Round($daysSince, 0)) days since last run (configured interval: $minDays days)." -ForegroundColor Yellow
    if ($LogFile) { Add-Content -Path $LogFile -Value "SSD TRIM skipped: $([math]::Round($daysSince, 0)) days elapsed (min $minDays days)." -Encoding UTF8 }
    return
}

Write-Host "Executing TRIM on $($targetDriveLetters.Count) drive(s): $($targetDriveLetters -join ', ')" -ForegroundColor Cyan

foreach ($dl in $targetDriveLetters) {
    Write-Host "Sending TRIM hint to Drive $dl`: ..." -ForegroundColor White
    try {
        $out = Optimize-Volume -DriveLetter $dl -ReTrim -Verbose -ErrorAction Stop 4>&1
        $out | Out-Host
        if ($LogFile) { $out | Add-Content -Path $LogFile -Encoding UTF8 }
        Write-Host "Drive $dl`: TRIM completed successfully." -ForegroundColor Green
        if ($LogFile) { Add-Content -Path $LogFile -Value "Drive $dl`: TRIM completed successfully." -Encoding UTF8 }
    } catch {
        if ($_.Exception.Message -match '0x8900002A|not supported by the hardware') {
            Write-Host "[Info] Drive $dl`: Storage controller (or virtual disk) does not require hardware TRIM. Skipping." -ForegroundColor Gray
            if ($LogFile) { Add-Content -Path $LogFile -Value "Drive $dl`: Hardware TRIM not required/supported by storage controller." -Encoding UTF8 }
        } else {
            Write-Host "Error during TRIM for Drive $dl`: $($_.Exception.Message)" -ForegroundColor Red
            if ($LogFile) { Add-Content -Path $LogFile -Value "Error during TRIM for Drive $dl`: $($_.Exception.Message)" -Encoding UTF8 }
        }
    }
}

if ($Settings -is [PSCustomObject]) {
    $Settings | Add-Member -NotePropertyName lastRun -NotePropertyValue ((Get-Date).ToString("yyyy-MM-dd")) -Force
}
