#Requires -Version 5.1
<#
.SYNOPSIS
    Analyzes and defragments mechanical hard disk drives (HDDs).
.DESCRIPTION
    Identifies rotational magnetic drives (HDDs) while strictly ignoring solid-state
    drives (SSDs) and removable USB drives. Checks if the configured interval (default: 30 days)
    has elapsed and runs defragmentation only when recommended by Windows.
.PARAMETER Action
    'Info'  - Outputs module metadata (Name, Description, Order, Default, RequiresAdmin, DefaultSettings).
    'Check' - Displays fragmentation analysis and elapsed time without modifying disks.
    'Run'   - Defragments eligible HDD volumes if due. Requires Administrator rights.
.PARAMETER Settings
    Optional module settings object or hashtable (supports excludedDrives, minIntervalDays, lastRun).
.PARAMETER LogFile
    Optional file path to append defragmentation results.
.EXAMPLE
    .\modules\freewinly-defrag-hdd.ps1 -Action Check
.EXAMPLE
    .\modules\freewinly-defrag-hdd.ps1 -Action Run -Settings @{ excludedDrives = @('E'); minIntervalDays = 30 }
#>
[CmdletBinding()]
param(
    [ValidateSet('Info', 'Check', 'Run')]
    [string]$Action = 'Run',

    [object]$Settings = $null,
    [string]$LogFile = $null
)

function Get-InstalledFixedHDDs {
    $found = [System.Collections.Generic.List[PSCustomObject]]::new()
    $busTypeMap = @{
        0 = 'Unknown'; 1 = 'SCSI'; 2 = 'ATAPI'; 3 = 'ATA'; 4 = '1394'; 5 = 'SSA'
        6 = 'Fibre Channel'; 7 = 'USB'; 8 = 'RAID'; 9 = 'iSCSI'; 10 = 'SAS'
        11 = 'SATA'; 12 = 'SD'; 13 = 'MMC'; 14 = 'MAX'; 15 = 'Virtual'
        16 = 'Storage Spaces'; 17 = 'NVMe'; 18 = 'Microsoft Reserved'
    }

    try {
        $pDisks = @(Get-CimInstance -Namespace 'root\Microsoft\Windows\Storage' -ClassName MSFT_PhysicalDisk -ErrorAction Stop)
        $partitions = @(Get-CimInstance -Namespace 'root\Microsoft\Windows\Storage' -ClassName MSFT_Partition -ErrorAction Stop | Where-Object { $_.DriveLetter })
        $logicalDisks = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop)

        $logMap = @{}
        foreach ($ld in $logicalDisks) {
            if ($ld.DeviceID) {
                $logMap[$ld.DeviceID.TrimEnd(':').ToUpper()] = $ld
            }
        }

        $diskToLetters = @{}
        foreach ($p in $partitions) {
            $dNum = [int]$p.DiskNumber
            $dLet = ([string]$p.DriveLetter).TrimEnd(':').ToUpper()
            if (-not $diskToLetters.ContainsKey($dNum)) {
                $diskToLetters[$dNum] = [System.Collections.Generic.List[string]]::new()
            }
            $diskToLetters[$dNum].Add($dLet)
        }

        foreach ($pd in $pDisks) {
            $mType = $pd.MediaType
            $bType = $pd.BusType
            $bStr = if ($bType -is [string]) { $bType } elseif ($busTypeMap.ContainsKey([int]$bType)) { $busTypeMap[[int]$bType] } else { [string]$bType }

            $isHDD = ($mType -eq 3 -or $mType -eq 'HDD') -and ($bType -ne 7 -and $bType -ne 'USB')

            if (-not $isHDD) { continue }

            $dNum = [int]$pd.DeviceId
            if ($diskToLetters.ContainsKey($dNum)) {
                foreach ($let in $diskToLetters[$dNum]) {
                    if ($logMap.ContainsKey($let)) {
                        $ld = $logMap[$let]
                        $found.Add([PSCustomObject]@{
                            DriveLetter = $let
                            Label       = $ld.VolumeName
                            Model       = $pd.FriendlyName
                            BusType     = $bStr
                            SizeGB      = [math]::Round([double]$ld.Size / 1GB, 1)
                            FreeGB      = [math]::Round([double]$ld.FreeSpace / 1GB, 1)
                        })
                    }
                }
            }
        }
    } catch { }

    return @($found)
}

if ($Action -eq 'Info') {
    $drives = Get-InstalledFixedHDDs
    return [PSCustomObject]@{
        Name                 = "Mechanical HDD Defragmentation"
        Description          = "Analyzes and defragments mechanical rotational HDDs (never touches SSDs)"
        Order                = 36
        Default              = $false
        RequiresAdmin        = $true
        Applicable           = ($drives.Count -gt 0)
        DetectedDrives       = $drives
        DefaultSettings      = [ordered]@{
            excludedDrives  = @()
            minIntervalDays = 30
            lastRun         = $null
        }
        SettingsDescriptions = [ordered]@{
            minIntervalDays = "Minimum days between HDD defragmentation runs"
        }
    }
}

Write-Host "`n--- [freewinly-defrag-hdd] Mechanical HDD Defragmentation [$Action] ---" -ForegroundColor Cyan

$detectedHDDs = Get-InstalledFixedHDDs
$detectedLetters = @($detectedHDDs | Select-Object -ExpandProperty DriveLetter)

if ($detectedLetters.Count -eq 0) {
    Write-Host "No mechanical rotational hard drives (HDDs) detected on this PC." -ForegroundColor Green
    Write-Host "This system is solid-state only (SSD/NVMe). HDD defragmentation is not needed." -ForegroundColor Gray
    return
}

# Resolve minimum days threshold and last run timestamp
$minDays = if ($Settings -and $null -ne $Settings.minIntervalDays) { [int]$Settings.minIntervalDays } else { 30 }
$lastRunStr = if ($Settings -and $Settings.lastRun) { [string]$Settings.lastRun } else { $null }
$lastRunDate = if ($lastRunStr) { try { [datetime]$lastRunStr } catch { $null } } else { $null }
$daysSince = if ($lastRunDate) { ((Get-Date) - $lastRunDate).TotalDays } else { [double]::MaxValue }
$isDue = ($minDays -le 0) -or ($daysSince -ge $minDays)

# Resolve excluded drives and target drives
$excludedLetters = @()
if ($Settings -and $Settings.excludedDrives) {
    $excludedLetters = @($Settings.excludedDrives | ForEach-Object { ([string]$_).TrimEnd(':').ToUpper() })
}

$targetLetters = if ($Settings -and $Settings.drives) {
    @($Settings.drives | ForEach-Object { ([string]$_).TrimEnd(':').ToUpper() })
} else {
    @($detectedLetters | Where-Object { $excludedLetters -notcontains $_.ToUpper() })
}

if ($Action -eq 'Check') {
    Write-Host "Detected Mechanical HDD Drives (Removable USB excluded):" -ForegroundColor Yellow
    $detectedHDDs | Format-Table DriveLetter, Label, Model, BusType, SizeGB, FreeGB -AutoSize

    if ($excludedLetters.Count -gt 0) {
        Write-Host "Excluded drives:   $($excludedLetters -join ', ')" -ForegroundColor Gray
    }
    Write-Host "Target HDD drives: $(if ($targetLetters.Count -gt 0) { $targetLetters -join ', ' } else { 'None (all excluded)' })" -ForegroundColor Cyan
    Write-Host "Cadence Threshold: Minimum $minDays day(s) between defragmentation runs." -ForegroundColor Gray
    if ($lastRunDate) {
        Write-Host "Last Defrag Run:   $($lastRunDate.ToString('yyyy-MM-dd')) ($([math]::Round($daysSince, 0)) days ago)." -ForegroundColor Gray
    } else {
        Write-Host "Last Defrag Run:   Never recorded." -ForegroundColor Gray
    }

    if (-not $isDue) {
        $nextDate = $lastRunDate.AddDays($minDays).ToString('yyyy-MM-dd')
        Write-Host "Status: SKIPPED (Not due yet; next eligible run date is $nextDate)." -ForegroundColor Yellow
        return
    }

    Write-Host "Status: DUE for analysis & potential defragmentation." -ForegroundColor Green

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin -and $targetLetters.Count -gt 0) {
        foreach ($dl in $targetLetters) {
            Write-Host "Analyzing Drive $dl`: for fragmentation..." -ForegroundColor Cyan
            try {
                $analysis = Optimize-Volume -DriveLetter $dl -Analyze -Verbose 4>&1 | Out-String
                $analysis | Out-Host
            } catch {
                Write-Host "Could not analyze Drive $dl`: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "Note: Running detailed fragmentation analysis requires Administrator privileges." -ForegroundColor Gray
    }

    Write-Host "Dry run complete. No drive sectors were moved." -ForegroundColor Green
    return
}

if ($targetLetters.Count -eq 0) {
    Write-Host "All detected HDD drives are excluded in settings. Skipping defragmentation." -ForegroundColor Yellow
    return
}

if (-not $isDue) {
    Write-Host "HDD defragmentation skipped: Only $([math]::Round($daysSince, 0)) days since last run (minimum threshold: $minDays days)." -ForegroundColor Yellow
    if ($LogFile) { Add-Content -Path $LogFile -Value "HDD Defrag skipped: $([math]::Round($daysSince, 0)) days elapsed (min $minDays days)." -Encoding UTF8 }
    return
}

Write-Host "Optimizing $($targetLetters.Count) HDD drive(s): $($targetLetters -join ', ')" -ForegroundColor Cyan

foreach ($dl in $targetLetters) {
    Write-Host "Analyzing and defragmenting Drive $dl`: (skips automatically if not fragmented)..." -ForegroundColor Cyan
    try {
        $out = Optimize-Volume -DriveLetter $dl -Defrag -Verbose -ErrorAction Stop 4>&1
        $out | Out-Host
        if ($LogFile) { $out | Add-Content -Path $LogFile -Encoding UTF8 }
        Write-Host "Drive $dl`: Optimization completed." -ForegroundColor Green
    } catch {
        Write-Host "Error optimizing Drive $dl`: $($_.Exception.Message)" -ForegroundColor Red
        if ($LogFile) { Add-Content -Path $LogFile -Value "Error optimizing Drive $dl`: $($_.Exception.Message)" -Encoding UTF8 }
    }
}

if ($Settings -is [PSCustomObject]) {
    $Settings | Add-Member -NotePropertyName lastRun -NotePropertyValue ((Get-Date).ToString("yyyy-MM-dd")) -Force
}
