<#
.SYNOPSIS
    FreeWinly Windows Event Log Stability Module.
.DESCRIPTION
    100% self-contained read-only stability inspector.
    Analyzes Application and System event logs for crashes, dirty shutdowns, and hardware warnings
    over the lookback period (default: 7 days), filtering out benign DCOM noise and presenting
    actionable troubleshooting steps.
.PARAMETER Action
    'Info'  - Returns module metadata object.
    'Check' - Inspects recent crashes and logs, displaying findings and actionable advice.
    'Run'   - Logs stability summary to the session log file.
.PARAMETER Config
    Optional PSCustomObject loaded from config.json.
.PARAMETER LogFile
    Optional path to the execution log file.
.PARAMETER Options
    Optional hashtable of module-specific options.
.EXAMPLE
    .\modules\06_event_log_health.ps1 -Action Info
.EXAMPLE
    .\modules\06_event_log_health.ps1 -Action Check
.EXAMPLE
    .\modules\06_event_log_health.ps1 -Action Run
#>
[CmdletBinding()]
param(
    [ValidateSet('Info', 'Check', 'Run')]
    [string]$Action = 'Run',

    [PSCustomObject]$Config = $null,
    [string]$LogFile = $null,
    [hashtable]$Options = @{}
)

$days = if ($Config -and $Config.eventLogLookbackDays) { [int]$Config.eventLogLookbackDays } else { 7 }

if ($Action -eq 'Info') {
    return [PSCustomObject]@{
        Name          = "System Stability & Event Logs (Last $days days)"
        Description   = "Scans Windows Event Logs for recurring application crashes, BSODs, and hardware errors with plain-language advice"
        Default       = $true
        RequiresAdmin = $false
        Options       = @{
            LookbackDays = $days
        }
    }
}

Write-Host "`n--- [Module 06] System Stability & Event Logs [$Action] ---" -ForegroundColor Cyan
Write-Host "Lookback window: Last $days day(s) (Application & System error logs)" -ForegroundColor Gray

$start = (Get-Date).AddDays(-$days)
$events = [System.Collections.Generic.List[object]]::new()

try {
    $rawEvents = Get-WinEvent -FilterHashtable @{LogName='System','Application'; Level=1,2; StartTime=$start} -ErrorAction SilentlyContinue |
                 Where-Object { $_.ProviderName -ne 'Microsoft-Windows-DistributedCOM' }

    if ($rawEvents) {
        $grouped = $rawEvents | Group-Object ProviderName, Id | Sort-Object Count -Descending | Select-Object -First 10
        foreach ($g in $grouped) {
            $first = $g.Group[0]
            $msg = ($first.Message -replace '\r?\n',' ')
            
            # Actionable insight extraction based on standard Windows Event signatures
            $advice = "Review event details in Windows Event Viewer under $($first.LogName)."
            if ($first.Id -eq 1000 -and $first.ProviderName -match 'Application Error') {
                if ($first.Message -match 'Faulting application name:\s*([^,\r\n]+)') {
                    $app = $matches[1].Trim()
                    $advice = "Application '$app' is crashing repeatedly. Consider checking for updates, repairing, or uninstalling it."
                }
            } elseif ($first.Id -eq 1002) {
                $advice = "Application hung and was terminated by Windows. Check for resource contention or corrupted app files."
            } elseif ($first.Id -eq 41 -and $first.ProviderName -match 'Kernel-Power') {
                $advice = "System lost power or rebooted without clean shutdown (possible power cut, forced reset, or BSOD crash)."
            } elseif ($first.ProviderName -match 'Disk|Ntfs|volmgr|stornvme|iaStor') {
                $advice = "Storage controller or disk warning detected! Verify SATA/NVMe connections and check drive SMART health."
            } elseif ($first.Id -in @(7000, 7009)) {
                $advice = "A background Windows service timed out or failed to launch. Verify service dependencies."
            }

            if ($msg.Length -gt 110) { $msg = $msg.Substring(0, 107) + '...' }

            $events.Add([PSCustomObject]@{
                Count    = $g.Count
                Provider = $first.ProviderName
                EventId  = $first.Id
                Advice   = $advice
                Sample   = $msg
            })
        }
    }
} catch {
    Write-Host "Could not query Windows Event Logs: $($_.Exception.Message)" -ForegroundColor Yellow
}

if ($events.Count -eq 0) {
    Write-Host "[OK] Clean stability record. No recurring crashes or critical warnings in the last $days day(s)." -ForegroundColor Green
    if ($LogFile) { Add-Content -Path $LogFile -Value "Event Log Health: Clean record over last $days days." -Encoding UTF8 }
    return
}

Write-Host "Found $($events.Count) recurring error pattern(s) in the last $days days:" -ForegroundColor Yellow

foreach ($ev in $events) {
    Write-Host "`n  * [$($ev.Count)x] $($ev.Provider) (Event ID $($ev.EventId))" -ForegroundColor White
    Write-Host "    Advice: $($ev.Advice)" -ForegroundColor Cyan
    Write-Host "    Sample: $($ev.Sample)" -ForegroundColor Gray
    if ($LogFile) {
        Add-Content -Path $LogFile -Value "Event Warning [$($ev.Count)x]: $($ev.Provider) ID $($ev.EventId) | $($ev.Advice)" -Encoding UTF8
    }
}
