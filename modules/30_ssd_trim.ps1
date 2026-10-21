<#
.SYNOPSIS
    FreeWinly SSD TRIM Optimization Module.
.DESCRIPTION
    Sends native NVMe/SATA TRIM hints to SSD volumes. Automatically detects all solid-state drives
    installed on the system and skips traditional rotational HDDs.
.PARAMETER Action
    'Info'  - Returns module metadata object including detected SSD drives.
    'Check' - Inspects TRIM status and lists target drives without trimming.
    'Run'   - Executes native volume retrim on target SSD drives.
.PARAMETER Config
    Optional PSCustomObject loaded from config.json.
.PARAMETER LogFile
    Optional path to the execution log file.
.PARAMETER Options
    Optional hashtable of module-specific options (e.g. @{ Drives = @('C', 'D') }).
.EXAMPLE
    .\modules\30_ssd_trim.ps1 -Action Info
.EXAMPLE
    .\modules\30_ssd_trim.ps1 -Action Check
.EXAMPLE
    .\modules\30_ssd_trim.ps1 -Action Run
.EXAMPLE
    .\modules\30_ssd_trim.ps1 -Action Run -Options @{ Drives = @('C') }
#>
[CmdletBinding()]
param(
    [ValidateSet('Info', 'Check', 'Run')]
    [string]$Action = 'Run',

    [PSCustomObject]$Config = $null,
    [string]$LogFile = $null,
    [hashtable]$Options = @{}
)

function Get-InstalledSSDDrives {
    $found = [System.Collections.Generic.List[PSCustomObject]]::new()
    try {
        $ssds = Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object MediaType -eq 'SSD'
        foreach ($ssd in $ssds) {
            $vols = $ssd | Get-Disk -ErrorAction SilentlyContinue |
                           Get-Partition -ErrorAction SilentlyContinue |
                           Get-Volume -ErrorAction SilentlyContinue |
                           Where-Object DriveLetter
            foreach ($v in $vols) {
                $found.Add([PSCustomObject]@{
                    DriveLetter = [string]$v.DriveLetter
                    Label       = $v.FileSystemLabel
                    Model       = $ssd.FriendlyName
                    BusType     = $ssd.BusType
                    SizeGB      = [math]::Round($v.Size / 1GB, 1)
                    FreeGB      = [math]::Round($v.SizeRemaining / 1GB, 1)
                })
            }
        }
    } catch {
        # Fallback to C: if disk querying encounters unexpected permission locks
    }

    if ($found.Count -eq 0 -and (Test-Path 'C:\')) {
        $found.Add([PSCustomObject]@{
            DriveLetter = 'C'
            Label       = 'System'
            Model       = 'Primary SSD'
            BusType     = 'Unknown'
            SizeGB      = 0
            FreeGB      = 0
        })
    }
    return $found
}

$detectedDrives = Get-InstalledSSDDrives
$detectedDriveLetters = @($detectedDrives | Select-Object -ExpandProperty DriveLetter)

if ($Action -eq 'Info') {
    return [PSCustomObject]@{
        Id            = "30_ssd_trim"
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

Write-Host "`n--- [Module 30] SSD TRIM Optimization [$Action] ---" -ForegroundColor Cyan

# Resolve target drives to trim (Options > Config > All detected)
$targetDriveLetters = if ($Options -and $Options.ContainsKey('Drives') -and $Options['Drives']) {
    @($Options['Drives'])
} elseif ($Config -and $Config.trimDrives) {
    @($Config.trimDrives)
} else {
    $detectedDriveLetters
}

if ($Action -eq 'Check') {
    Write-Host "[Check Mode] Querying operating system TRIM support..." -ForegroundColor Gray
    try {
        & fsutil behavior query DisableDeleteNotify
    } catch {
        Write-Host "Could not query fsutil DisableDeleteNotify." -ForegroundColor Gray
    }

    Write-Host "`nDetected SSD Physical Drives & Partitions:" -ForegroundColor Yellow
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
        $out = Optimize-Volume -DriveLetter $dl -ReTrim -Verbose 4>&1
        $out | Out-Host
        if ($LogFile) { $out | Add-Content -Path $LogFile -Encoding UTF8 }
        Write-Host "Drive $dl`: TRIM completed successfully." -ForegroundColor Green
        if ($LogFile) { Add-Content -Path $LogFile -Value "Drive $dl`: TRIM completed successfully." -Encoding UTF8 }
    } catch {
        Write-Host "Error during TRIM for Drive $dl`: $($_.Exception.Message)" -ForegroundColor Red
        if ($LogFile) { Add-Content -Path $LogFile -Value "Error during TRIM for Drive $dl`: $($_.Exception.Message)" -Encoding UTF8 }
    }
}
