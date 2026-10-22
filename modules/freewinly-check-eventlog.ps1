#Requires -Version 5.1
<#
.SYNOPSIS
    Analyzes Windows Application and System event logs for recurring errors.
.DESCRIPTION
    Scans the Windows Event Log over a configurable lookback window (default: 7 days)
    or custom date range (StartDate to EndDate, where EndDate defaults to today).
    Filters out background DCOM noise and provides guidance for identified error sources.
    This module is read-only and does not clear or alter event logs.
.PARAMETER Action
    'Info'  - Outputs module metadata (Name, Description, Order, Default, RequiresAdmin, DefaultSettings).
    'Check' - Inspects recent event logs and displays recurring patterns.
    'Run'   - Scans recent event logs and records findings to the log file.
.PARAMETER Settings
    Optional module settings object or hashtable (supports lookbackDays, startDate, endDate).
.PARAMETER LogFile
    Optional file path to append diagnostic results.
.PARAMETER LookbackDays
    Number of days back to inspect (alias: -Days).
.PARAMETER StartDate
    Starting timestamp or date string e.g. '2026-10-18'. If specified without -EndDate, EndDate defaults to today.
.PARAMETER EndDate
    Ending timestamp or date string e.g. '2026-10-20'. Defaults to today (current time) if omitted.
.EXAMPLE
    .\modules\freewinly-check-eventlog.ps1 -Action Check
.EXAMPLE
    .\modules\freewinly-check-eventlog.ps1 -Days 14
.EXAMPLE
    .\modules\freewinly-check-eventlog.ps1 -StartDate "2026-10-18"
.EXAMPLE
    .\modules\freewinly-check-eventlog.ps1 -StartDate "2026-10-17" -EndDate "2026-10-19"
.EXAMPLE
    .\modules\freewinly-check-eventlog.ps1 -Action Run -Settings @{ lookbackDays = 14 }
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('Info', 'Check', 'Run')]
    [string]$Action = 'Run',

    [Parameter()]
    [object]$Settings = $null,

    [Parameter()]
    [string]$LogFile = $null,

    [Parameter()]
    [Alias('Days')]
    [int]$LookbackDays = 0,

    [Parameter()]
    [Alias('Since', 'From')]
    [object]$StartDate = $null,

    [Parameter()]
    [Alias('Until', 'To')]
    [object]$EndDate = $null
)

if ($Action -eq 'Info') {
    return [PSCustomObject]@{
        Name            = "System Stability & Event Logs"
        Description     = "Scans Windows Event Logs for recurring application crashes, BSODs, and hardware errors with plain-language advice"
        Order           = 11
        Default         = $true
        RequiresAdmin   = $false
        DefaultSettings = [ordered]@{
            lookbackDays = 7
            startDate    = $null
            endDate      = $null
        }
    }
}

function ConvertTo-DateTimeOrNull {
    param([object]$InputVal)
    if ($null -eq $InputVal) { return $null }
    if ($InputVal -is [datetime]) { return $InputVal }
    $str = [string]$InputVal
    if ([string]::IsNullOrWhiteSpace($str)) { return $null }
    try {
        return [datetime]$str
    } catch {
        try {
            return [datetime]::ParseExact($str, @('yyyy-MM-dd', 'yyyy-MM-dd HH:mm', 'yyyy-MM-dd HH:mm:ss', 'yyyy/MM/dd'), [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None)
        } catch {
            throw "Invalid date format: '$str'. Please use 'YYYY-MM-DD' or a valid date/time string."
        }
    }
}

# 1. Resolve Start Date
$rawStart = if ($StartDate) {
    $StartDate
} elseif ($Settings -and $Settings.startDate) {
    $Settings.startDate
} elseif ($Settings -and $Settings.since) {
    $Settings.since
} else { $null }

$start = ConvertTo-DateTimeOrNull $rawStart

# 2. Resolve End Date (defaults to today/now if omitted)
$rawEnd = if ($EndDate) {
    $EndDate
} elseif ($Settings -and $Settings.endDate) {
    $Settings.endDate
} elseif ($Settings -and $Settings.until) {
    $Settings.until
} else { $null }

$end = ConvertTo-DateTimeOrNull $rawEnd

# 3. If no explicit StartDate, resolve LookbackDays (default: 7)
$days = 0
if (-not $start) {
    $days = if ($LookbackDays -gt 0) {
        $LookbackDays
    } elseif ($Settings -and $Settings.lookbackDays) {
        [int]$Settings.lookbackDays
    } else {
        7
    }
    $start = (Get-Date).AddDays(-$days)
    if (-not $end) {
        $end = (Get-Date)
    }
} else {
    # If StartDate is specified without EndDate, default EndDate to today (current time)
    if (-not $end) {
        $end = (Get-Date)
    }
}

$windowDesc = if ($days -gt 0) {
    "Last $days day(s) ($($start.ToString('yyyy-MM-dd HH:mm')) to $($end.ToString('yyyy-MM-dd HH:mm')))"
} else {
    "$($start.ToString('yyyy-MM-dd HH:mm')) to $($end.ToString('yyyy-MM-dd HH:mm'))"
}

Write-Host "`n--- [freewinly-check-eventlog] System Stability & Event Logs [$Action] ---" -ForegroundColor Cyan
Write-Host "Time window: $windowDesc (Application & System error logs)" -ForegroundColor Gray

$events = [System.Collections.Generic.List[object]]::new()

try {
    $filter = @{
        LogName   = 'System', 'Application'
        Level     = 1, 2 # Critical, Error
        StartTime = $start
        EndTime   = $end
    }

    $rawEvents = Get-WinEvent -FilterHashtable $filter -ErrorAction SilentlyContinue |
                 Where-Object { $_.ProviderName -ne 'Microsoft-Windows-DistributedCOM' }

    if ($rawEvents) {
        $grouped = $rawEvents | Group-Object ProviderName, Id | Sort-Object Count -Descending | Select-Object -First 10
        foreach ($g in $grouped) {
            $first = $g.Group[0]
            $msg = ($first.Message -replace '\r?\n',' ')
            
            # Actionable insight extraction based on standard Windows Event signatures (locale-independent via Properties first)
            $advice = "Review event details in Windows Event Viewer under $($first.LogName)."
            if ($first.Id -eq 1000 -and $first.ProviderName -match 'Application Error') {
                $app = if ($first.Properties -and $first.Properties.Count -gt 0 -and $first.Properties[0].Value) {
                    [string]$first.Properties[0].Value
                } elseif ($first.Message -match 'Faulting application name:\s*([^,\r\n]+)') {
                    $matches[1].Trim()
                } else { $null }
                if ($app) {
                    $advice = "Application '$app' is crashing repeatedly. Consider checking for updates, repairing, or uninstalling it."
                }
            } elseif ($first.Id -eq 1002) {
                $app = if ($first.Properties -and $first.Properties.Count -gt 0 -and $first.Properties[0].Value) {
                    " ('$($first.Properties[0].Value)')"
                } else { "" }
                $advice = "Application$app hung and was terminated by Windows. Check for resource contention or corrupted app files."
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
    Write-Host "[OK] Clean stability record. No recurring crashes or critical warnings in the specified window ($windowDesc)." -ForegroundColor Green
    if ($LogFile) { Add-Content -Path $LogFile -Value "Event Log Health: Clean record ($windowDesc)." -Encoding UTF8 }
    return
}

Write-Host "Found $($events.Count) recurring error pattern(s) ($windowDesc):" -ForegroundColor Yellow

foreach ($ev in $events) {
    Write-Host "`n  * [$($ev.Count)x] $($ev.Provider) (Event ID $($ev.EventId))" -ForegroundColor White
    Write-Host "    Advice: $($ev.Advice)" -ForegroundColor Cyan
    Write-Host "    Sample: $($ev.Sample)" -ForegroundColor Gray
    if ($LogFile) {
        Add-Content -Path $LogFile -Value "Event Warning [$($ev.Count)x]: $($ev.Provider) ID $($ev.EventId) | $($ev.Advice)" -Encoding UTF8
    }
}
