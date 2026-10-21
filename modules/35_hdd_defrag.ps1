<#
.SYNOPSIS
    FreeWinly Mechanical HDD Defragmentation Module.
.DESCRIPTION
    100% self-contained script. Analyzes and defragments rotational magnetic hard drives (HDDs) only.
    Automatically skips SSDs and removable USB flash pens. Only executes if the configured minimum days
    (default: 30) have passed since the last run and Windows recommends defragmentation.
.PARAMETER Action
    'Info'  - Returns module metadata object including detected HDD drives.
    'Check' - Inspects days elapsed and fragmentation recommendation without writing changes.
    'Run'   - Defragments eligible HDDs if due and recommended by Windows.
.PARAMETER Config
    Optional PSCustomObject loaded from config.json.
.PARAMETER LogFile
    Optional path to the execution log file.
.PARAMETER Options
    Optional hashtable of module-specific options (e.g. @{ Drives = @('D') }).
.EXAMPLE
    .\modules\35_hdd_defrag.ps1 -Action Info
.EXAMPLE
    .\modules\35_hdd_defrag.ps1 -Action Check
.EXAMPLE
    .\modules\35_hdd_defrag.ps1 -Action Run
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

Write-Host "`n--- [Module 35] Mechanical HDD Defragmentation [$Action] ---" -ForegroundColor Cyan

if ($detectedLetters.Count -eq 0) {
    Write-Host "No mechanical rotational hard drives (HDDs) detected on this PC." -ForegroundColor Green
    Write-Host "This system is 100% solid-state (SSD/NVMe). HDD defragmentation is not needed." -ForegroundColor Gray
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
            $analysis = & defrag.exe "$($dl):" /A 2>&1 | Out-String
            $analysis | Out-Host
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

Write-Host "Checking $( $targetLetters.Count ) HDD drive(s): $( $targetLetters -join ', ' )" -ForegroundColor Cyan
$updatedAny = $false

foreach ($dl in $targetLetters) {
    Write-Host "Analyzing fragmentation on Drive $dl`: ..." -ForegroundColor Cyan
    $analysis = & defrag.exe "$($dl):" /A 2>&1 | Out-String
    $analysis | Out-Host

    $needsDefrag = $true
    if ($analysis -match 'You do not need to defragment this volume') {
        $needsDefrag = $false
        Write-Host "Drive $dl`: Windows reports defragmentation is not needed. Skipping." -ForegroundColor Green
        if ($LogFile) { Add-Content -Path $LogFile -Value "Drive $dl`: Defragmentation not needed." -Encoding UTF8 }
    }

    if ($needsDefrag) {
        Write-Host "Defragmenting Drive $dl`: ..." -ForegroundColor Yellow
        $out = & Optimize-Volume -DriveLetter $dl -Defrag -Verbose 4>&1
        $out | Out-Host
        if ($LogFile) { $out | Add-Content -Path $LogFile -Encoding UTF8 }
        Write-Host "Drive $dl`: Defragmentation completed." -ForegroundColor Green
        $updatedAny = $true
    }
}

# Update timestamp in config if provided
if ($Config) {
    $todayStr = (Get-Date).ToString("yyyy-MM-dd")
    $Config | Add-Member -NotePropertyName hddDefragLastRun -NotePropertyValue $todayStr -Force
}
