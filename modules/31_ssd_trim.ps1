#Requires -Version 5.1
<#
.SYNOPSIS
    Sends native TRIM commands to internal solid-state drives (SSDs).
.DESCRIPTION
    Detects fixed NVMe and SATA SSDs using Windows storage cmdlets, excluding external
    USB drives and mechanical hard drives. Executes Optimize-Volume with the -ReTrim
    parameter to maintain flash memory performance and endurance.
.PARAMETER Action
    'Info'  - Outputs module metadata and detected SSD drive letters.
    'Check' - Displays detected SSD partitions and TRIM support status without trimming.
    'Run'   - Issues TRIM commands to eligible SSD volumes. Requires Administrator rights.
.PARAMETER Config
    Optional PSCustomObject loaded from config.json (reads trimDrives).
.PARAMETER LogFile
    Optional file path to append TRIM results.
.PARAMETER Options
    Optional hashtable of module-specific parameters (e.g. @{ Drives = @('C', 'D') }).
.EXAMPLE
    .\modules\31_ssd_trim.ps1 -Action Check
.EXAMPLE
    .\modules\31_ssd_trim.ps1 -Action Run
.EXAMPLE
    .\modules\31_ssd_trim.ps1 -Action Run -Options @{ Drives = @('C') }
#>
[CmdletBinding()]
param(
    [ValidateSet('Info', 'Check', 'Run')]
    [string]$Action = 'Run',

    [PSCustomObject]$Config = $null,
    [string]$LogFile = $null,
    [hashtable]$Options = @{}
)

function Get-InstalledFixedSSDs {
    $found = [System.Collections.Generic.List[PSCustomObject]]::new()
    $allDisks = @()
    try {
        $allDisks = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)
        # Query physical SSDs (excluding USB) plus thin-provisioned Virtual Machine disks
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

    # Only fall back to C: if Get-PhysicalDisk returned no disks at all (WMI storage provider unavailable).
    # Never fall back if Get-PhysicalDisk succeeded and confirmed the system only has mechanical HDDs.
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

$detectedDrives = Get-InstalledFixedSSDs
$detectedDriveLetters = @($detectedDrives | Select-Object -ExpandProperty DriveLetter)

if ($Action -eq 'Info') {
    return [PSCustomObject]@{
        Name          = "SSD TRIM Optimization"
        Description   = "Sends native NVMe/SATA TRIM hints to SSD volumes (never defrags)"
        Default       = $true
        RequiresAdmin = $true
        Options       = @{
            DetectedDrives = $detectedDriveLetters
            DrivesDetail   = $detectedDrives
        }
    }
}

Write-Host "`n--- [Module 31] SSD TRIM Optimization [$Action] ---" -ForegroundColor Cyan

# Resolve target drives to trim (Options > Config > All detected)
$targetDriveLetters = if ($Options -and $Options.ContainsKey('Drives') -and $Options['Drives']) {
    @($Options['Drives'])
} elseif ($Config -and $Config.trimDrives) {
    @($Config.trimDrives)
} else {
    $detectedDriveLetters
}

if ($targetDriveLetters.Count -eq 0) {
    Write-Host "No fixed SSD drives found to optimize." -ForegroundColor Yellow
    return
}

if ($Action -eq 'Check') {
    Write-Host "[Check Mode] Querying operating system TRIM support..." -ForegroundColor Gray
    try {
        & fsutil behavior query DisableDeleteNotify
    } catch {
        Write-Host "Could not query fsutil DisableDeleteNotify." -ForegroundColor Gray
    }

    Write-Host "`nDetected SSD Physical Drives & Partitions (Removable USB excluded):" -ForegroundColor Yellow
    $detectedDrives | Format-Table DriveLetter, Label, Model, BusType, SizeGB, FreeGB -AutoSize

    Write-Host "Configured target drives for TRIM: $($targetDriveLetters -join ', ')" -ForegroundColor Cyan
    Write-Host "Dry run complete. No TRIM commands were sent." -ForegroundColor Green
    return
}

# Run execution
Write-Host "Executing TRIM on $( $targetDriveLetters.Count ) drive(s): $( $targetDriveLetters -join ', ' )" -ForegroundColor Cyan

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
