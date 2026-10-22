#Requires -Version 5.1
<#
.SYNOPSIS
    Queries Windows Device Manager for hardware faults and missing drivers.
.DESCRIPTION
    Inspects PnP devices using WMI/CIM and Device Manager status codes.
    Maps numeric problem codes (e.g. Code 28, Code 43) to actionable troubleshooting guidance.
    This module is read-only and does not modify drivers or hardware configuration.
.PARAMETER Action
    'Info'  - Outputs module metadata (Name, Description, Order, Default, RequiresAdmin, DefaultSettings).
    'Check' - Scans hardware devices and displays detected warnings to console.
    'Run'   - Scans hardware devices and records findings to the specified log file.
.PARAMETER Settings
    Optional module settings object or hashtable.
.PARAMETER LogFile
    Optional file path to append diagnostic results.
.EXAMPLE
    .\modules\freewinly-check-hardware.ps1 -Action Info
.EXAMPLE
    .\modules\freewinly-check-hardware.ps1 -Action Check
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
        Name                 = "Hardware & Driver Health"
        Description          = "Scans Windows Device Manager for hardware faults and missing drivers with actionable advice"
        Order                = 10
        Default              = $true
        RequiresAdmin        = $false
        DefaultSettings      = [ordered]@{}
        SettingsDescriptions = [ordered]@{}
    }
}

Write-Host "`n--- [freewinly-check-hardware] Hardware & Driver Health [$Action] ---" -ForegroundColor Cyan

$cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
$isVM = $cs -and ("$($cs.Manufacturer) $($cs.Model)" -match 'Virtual|VMware|KVM|QEMU|Bochs|Parallels|HVM|Xen|innotek')

function Get-ProblemAdvice {
    param([int]$Code)
    $vmHint = if ($isVM -and $Code -eq 28) { " (Virtual Machine detected: install or update VM Guest Tools / VirtIO drivers.)" } else { "" }
    switch ($Code) {
        1  { return "Device is not configured correctly. Update or reinstall driver." }
        10 { return "Device cannot start. Try unplugging/replugging, updating driver, or restarting PC." }
        14 { return "Device requires a computer restart to complete driver installation." }
        22 { return "Device is disabled. Enable it in Windows Device Manager if needed." }
        28 { return "Driver missing. Check Windows Update -> Advanced -> Optional Updates, or download from manufacturer.$vmHint" }
        31 { return "Device is not working properly because Windows cannot load required drivers." }
        43 { return "Device stopped because it reported problems (hardware crash or driver fault)." }
        default { return "Windows reported status error code $Code. Check Device Manager properties." }
    }
}

$problemDevices = [System.Collections.Generic.List[PSCustomObject]]::new()

try {
    $entities = Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
                Where-Object { $_.ConfigManagerErrorCode -ne 0 -and $_.ConfigManagerErrorCode -ne 22 }

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
