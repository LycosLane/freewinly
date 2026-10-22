#Requires -Version 5.1
<#
.SYNOPSIS
    Analyzes and defragments mechanical hard disk drives (HDDs).
.DESCRIPTION
    Identifies rotational magnetic drives (HDDs) while strictly ignoring solid-state
    drives (SSDs) and removable USB drives. Checks if the configured interval (default: 30 days)
    has elapsed and runs defragmentation only when recommended by Windows.
.PARAMETER Action
    'Info'  - Outputs module metadata and detected HDD drive letters.
    'Check' - Displays fragmentation analysis and elapsed time without modifying disks.
    'Run'   - Defragments eligible HDD volumes if due. Requires Administrator rights.
.PARAMETER Config
    Optional PSCustomObject loaded from config.json (reads hddDefragMinDays and hddDefragLastRun).
.PARAMETER LogFile
    Optional file path to append defragmentation results.
.PARAMETER Options
    Optional hashtable of module-specific parameters (e.g. @{ Drives = @('D') }).
.EXAMPLE
    .\modules\32_hdd_defrag.ps1 -Action Check
.EXAMPLE
    .\modules\32_hdd_defrag.ps1 -Action Run
#>
[CmdletBinding()]
param(
    [ValidateSet('Info', 'Check', 'Run')]
    [string]$Action = 'Run',

    [PSCustomObject]$Config = $null,
    [string]$LogFile = $null,
    [hashtable]$Options = @{}
)

function Get-InstalledFixedHDDs {
    $found = [System.Collections.Generic.List[PSCustomObject]]::new()
    try {
        $disks = Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.MediaType -eq 'HDD' }
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
    return @($found)
}

$detectedHDDs = Get-InstalledFixedHDDs
$detectedLetters = @($detectedHDDs | Select-Object -ExpandProperty DriveLetter)

if ($Action -eq 'Info') {
    return [PSCustomObject]@{
        Name          = "Mechanical HDD Defragmentation"
        Description   = "Analyzes and defragments mechanical rotational HDDs (never touches SSDs)"
        Default       = $false
        RequiresAdmin = $true
        Options       = @{
            DetectedDrives = $detectedLetters
            DrivesDetail   = $detectedHDDs
        }
    }
}

Write-Host "`n--- [Module 32] Mechanical HDD Defragmentation [$Action] ---" -ForegroundColor Cyan

if ($detectedLetters.Count -eq 0) {
    Write-Host "No mechanical rotational hard drives (HDDs) detected on this PC." -ForegroundColor Green
    Write-Host "This system is solid-state only (SSD/NVMe). HDD defragmentation is not needed." -ForegroundColor Gray
    return
}

# Resolve minimum days threshold and last run timestamp
$minDays = if ($Config -and $Config.hddDefragMinDays) { [int]$Config.hddDefragMinDays } else { 30 }
$lastRunStr = if ($Config -and $Config.hddDefragLastRun) { [string]$Config.hddDefragLastRun } else { $null }

$lastRunDate = $null
if ($lastRunStr) {
    try { $lastRunDate = [datetime]$lastRunStr } catch {}
}

$daysSince = if ($lastRunDate) { ((Get-Date) - $lastRunDate).TotalDays } else { [double]::MaxValue }
$isDue = ($daysSince -ge $minDays)

# Target drives (Options > Config > Detected)
$targetLetters = if ($Options -and $Options.ContainsKey('Drives') -and $Options['Drives']) {
    @($Options['Drives'])
} elseif ($Config -and $Config.hddDefragDrives) {
    @($Config.hddDefragDrives)
} else {
    $detectedLetters
}

if ($Action -eq 'Check') {
    Write-Host "Detected Mechanical HDD Drives (Removable USB excluded):" -ForegroundColor Yellow
    $detectedHDDs | Format-Table DriveLetter, Label, Model, BusType, SizeGB, FreeGB -AutoSize

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
    if ($isAdmin) {
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

# Run Action
if (-not $isDue) {
    Write-Host "HDD defragmentation skipped: Only $([math]::Round($daysSince, 0)) days since last run (minimum threshold: $minDays days)." -ForegroundColor Yellow
    if ($LogFile) { Add-Content -Path $LogFile -Value "HDD Defrag skipped: $daysSince days elapsed (min $minDays days)." -Encoding UTF8 }
    return
}

Write-Host "Optimizing $( $targetLetters.Count ) HDD drive(s): $( $targetLetters -join ', ' )" -ForegroundColor Cyan

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

# Update timestamp in config (in-memory for runner, or on disk if run standalone)
$todayStr = (Get-Date).ToString("yyyy-MM-dd")
if ($Config) {
    $Config | Add-Member -NotePropertyName hddDefragLastRun -NotePropertyValue $todayStr -Force
} else {
    $defaultCfgPath = Join-Path (Split-Path -Parent $PSScriptRoot) "config.json"
    if (Test-Path $defaultCfgPath) {
        try {
            $diskCfg = Get-Content $defaultCfgPath -Raw | ConvertFrom-Json
            $diskCfg | Add-Member -NotePropertyName hddDefragLastRun -NotePropertyValue $todayStr -Force
            $diskCfg | ConvertTo-Json -Depth 5 | Out-File -FilePath $defaultCfgPath -Encoding UTF8
        } catch { }
    }
}
