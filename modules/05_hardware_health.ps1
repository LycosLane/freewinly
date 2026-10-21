<#
.SYNOPSIS
    FreeWinly Hardware & Driver Diagnostics Module.
.DESCRIPTION
    100% self-contained read-only hardware scanner.
    Queries Windows PnP and Device Manager for devices reporting errors, missing drivers,
    or hardware faults, providing human-actionable troubleshooting advice.
.PARAMETER Action
    'Info'  - Returns module metadata object.
    'Check' - Scans hardware devices and displays status and remediation advice.
    'Run'   - Scans and logs hardware status to the session log.
.PARAMETER Config
    Optional PSCustomObject loaded from config.json.
.PARAMETER LogFile
    Optional path to the execution log file.
.PARAMETER Options
    Optional hashtable of module-specific options.
.EXAMPLE
    .\modules\05_hardware_health.ps1 -Action Info
.EXAMPLE
    .\modules\05_hardware_health.ps1 -Action Check
.EXAMPLE
    .\modules\05_hardware_health.ps1 -Action Run
#>
[CmdletBinding()]
param(
    [ValidateSet('Info', 'Check', 'Run')]
    [string]$Action = 'Run',

    [PSCustomObject]$Config = $null,
    [string]$LogFile = $null,
    [hashtable]$Options = @{}
)

if ($Action -eq 'Info') {
    return [PSCustomObject]@{
        Id            = "05_hardware_health"
        Name          = "Hardware & Driver Health"
        Description   = "Scans Windows Device Manager for hardware faults and missing drivers with actionable advice"
        Default       = $true
        RequiresAdmin = $false
        Options       = @{}
    }
}

Write-Host "`n--- [Module 05] Hardware & Driver Health [$Action] ---" -ForegroundColor Cyan

function Get-ProblemAdvice {
    param([int]$Code)
    switch ($Code) {
        1  { return "Device is not configured correctly. Update or reinstall driver." }
        10 { return "Device cannot start. Try unplugging/replugging, updating driver, or restarting PC." }
        14 { return "Device requires a computer restart to complete driver installation." }
        22 { return "Device is disabled. Enable it in Windows Device Manager if needed." }
        28 { return "Driver missing. Check Windows Update -> Advanced -> Optional Updates, or download from manufacturer." }
        31 { return "Device is not working properly because Windows cannot load required drivers." }
        43 { return "Device stopped because it reported problems (hardware crash or driver fault)." }
        default { return "Windows reported status error code $Code. Check Device Manager properties." }
    }
}

$problemDevices = [System.Collections.Generic.List[PSCustomObject]]::new()

try {
    # Query WMI PnPEntity which natively provides ConfigManagerErrorCode
    $entities = Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
                Where-Object { $_.ConfigManagerErrorCode -ne 0 -and $_.ConfigManagerErrorCode -ne 22 }
                # Exclude Code 22 (intentionally disabled by user) from being treated as critical hardware failure

    foreach ($e in $entities) {
        $problemDevices.Add([PSCustomObject]@{
            Name        = if ($e.Name) { $e.Name } else { $e.Description }
            Class       = $e.PNPClass
            ErrorCode   = $e.ConfigManagerErrorCode
            Actionable  = (Get-ProblemAdvice -Code $e.ConfigManagerErrorCode)
            DeviceId    = $e.DeviceID
        })
    }
} catch {
    # Resilient fallback to Get-PnpDevice
    $pnp = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'OK' }
    foreach ($p in $pnp) {
        $problemDevices.Add([PSCustomObject]@{
            Name        = $p.FriendlyName
            Class       = $p.Class
            ErrorCode   = 0
            Actionable  = "Status: $($p.Status). Check Device Manager properties."
            DeviceId    = $p.InstanceId
        })
    }
}

if ($problemDevices.Count -eq 0) {
    Write-Host "[OK] All hardware devices and drivers report healthy (Status = OK)." -ForegroundColor Green
    if ($LogFile) { Add-Content -Path $LogFile -Value "Hardware Check: All devices report Status = OK." -Encoding UTF8 }
    return
}

Write-Host "Found $($problemDevices.Count) device(s) with warnings or missing drivers:" -ForegroundColor Yellow

foreach ($d in $problemDevices) {
    Write-Host "`n  * Device: $($d.Name) [$($d.Class)]" -ForegroundColor White
    Write-Host "    Code:   $($d.ErrorCode)" -ForegroundColor Yellow
    Write-Host "    Action: $($d.Actionable)" -ForegroundColor Cyan
    if ($LogFile) {
        Add-Content -Path $LogFile -Value "Hardware Warning: $($d.Name) | Code $($d.ErrorCode) | $($d.Actionable)" -Encoding UTF8
    }
}
