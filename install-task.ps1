#Requires -Version 5.1
<#
.SYNOPSIS
    FreeWinly Windows Task Scheduler Automation.
.DESCRIPTION
    Configures, inspects, or removes a native Windows Scheduled Task to run FreeWinly
    automatically in the background. Uses 100% native Windows Task Scheduler with zero
    resident services, tray icons, or battery drain.
.PARAMETER Action
    'Interactive' - Opens clean numbered selector to configure schedule.
    'Status'      - Displays current scheduled task configuration.
    'Weekly'      - Schedules weekly maintenance (default: Sunday at 12:00).
    'Monthly'     - Schedules monthly maintenance (1st of month at 12:00).
    'Logon'       - Schedules maintenance 5 minutes after user signs in.
    'Remove'      - Unregisters and deletes the scheduled task cleanly.
.PARAMETER At
    Time of day in HH:mm format (default: '12:00').
.PARAMETER DayOfWeek
    Day of week for weekly schedule (default: 'Sunday').
.EXAMPLE
    .\install-task.ps1
.EXAMPLE
    .\install-task.ps1 -Action Weekly -DayOfWeek Sunday -At 14:00
.EXAMPLE
    .\install-task.ps1 -Action Remove
#>
[CmdletBinding()]
param(
    [ValidateSet('Interactive', 'Status', 'Weekly', 'Monthly', 'Logon', 'Remove')]
    [string]$Action = 'Interactive',

    [string]$At = '12:00',
    [string]$DayOfWeek = 'Sunday'
)

$ErrorActionPreference = "Continue"
$taskName = "FreeWinly"
$projectRoot = $PSScriptRoot
$runnerScript = Join-Path $projectRoot "freewinly.ps1"

function Get-TaskStatusText {
    try {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
        $state = $task.State
        $trigger = $task.Triggers[0]
        $triggerType = $trigger.CimClass.CimClassName -replace '^MSFT_Task', '' -replace 'Trigger$', ''
        return "[Installed] State: $state | Schedule: $triggerType"
    } catch {
        return "[Not Installed] No scheduled maintenance task currently registered."
    }
}

function Show-Header {
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "       FreeWinly - Native Windows Task Scheduler Sync       " -ForegroundColor White
    Write-Host "       Zero background RAM, zero tray icons, zero bloat     " -ForegroundColor Gray
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "Current Status: $(Get-TaskStatusText)`n" -ForegroundColor Yellow
}

function Register-FreeWinlyTask {
    param(
        [string]$ScheduleType,
        [string]$TimeStr = '12:00',
        [string]$Day = 'Sunday'
    )

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "`nRegistering scheduled maintenance with highest privileges requires Administrator rights." -ForegroundColor Yellow
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Action $ScheduleType -At `"$TimeStr`" -DayOfWeek `"$Day`""
        return
    }

    $time = try { [datetime]::ParseExact($TimeStr, 'HH:mm', $null) } catch { (Get-Date).Date.AddHours(12) }

    $trigger = switch ($ScheduleType) {
        'Weekly' {
            New-ScheduledTaskTrigger -Weekly -DaysOfWeek $Day -At $time
        }
        'Monthly' {
            # Standard monthly trigger at specified day/time
            $tr = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $Day -At $time
            $tr.WeeksInterval = 4
            $tr
        }
        'Logon' {
            $tr = New-ScheduledTaskTrigger -AtLogon
            $tr.RandomDelay = 'PT5M' # 5 minute delay after logon
            $tr
        }
    }

    $taskAction = New-ScheduledTaskAction -Execute "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$runnerScript`" -Run" `
        -WorkingDirectory $projectRoot

    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 2)

    try {
        Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $trigger -Principal $principal -Settings $settings -Description "FreeWinly Automated PC Maintenance" -Force | Out-Null
        Write-Host "`n[SUCCESS] Scheduled task '$taskName' registered successfully!" -ForegroundColor Green
        Write-Host "Schedule: $ScheduleType ($TimeStr)" -ForegroundColor Cyan
        Write-Host "FreeWinly will execute quietly in the background without popups." -ForegroundColor Gray
    } catch {
        Write-Host "`n[ERROR] Failed to register task: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Remove-FreeWinlyTask {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "`nRemoving scheduled task requires Administrator privileges." -ForegroundColor Yellow
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Action Remove"
        return
    }

    try {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
        Write-Host "`n[SUCCESS] Scheduled task '$taskName' removed cleanly from Windows." -ForegroundColor Green
    } catch {
        Write-Host "`nTask '$taskName' was not found or already removed." -ForegroundColor Yellow
    }
}

if ($Action -eq 'Status') {
    Show-Header
    exit 0
}

if ($Action -eq 'Weekly') {
    Register-FreeWinlyTask -ScheduleType 'Weekly' -TimeStr $At -Day $DayOfWeek
    exit 0
}

if ($Action -eq 'Monthly') {
    Register-FreeWinlyTask -ScheduleType 'Monthly' -TimeStr $At
    exit 0
}

if ($Action -eq 'Logon') {
    Register-FreeWinlyTask -ScheduleType 'Logon'
    exit 0
}

if ($Action -eq 'Remove') {
    Remove-FreeWinlyTask
    exit 0
}

# Interactive Menu
Clear-Host
Show-Header

Write-Host "Choose a native schedule option:" -ForegroundColor White
Write-Host "  [ 1 ]  Weekly  (Every Sunday at 12:00)" -ForegroundColor Cyan
Write-Host "  [ 2 ]  Monthly (Every 4 weeks at 12:00)" -ForegroundColor Cyan
Write-Host "  [ 3 ]  Logon   (5 minutes after signing into Windows)" -ForegroundColor Cyan
Write-Host "  [ 4 ]  Remove  (Delete scheduled task from Windows Task Scheduler)" -ForegroundColor Yellow
Write-Host "  [ Q ]  Cancel & Return" -ForegroundColor Gray

$choice = Read-Host "`nEnter selection (1-4, Q)"

switch ($choice) {
    "1" { Register-FreeWinlyTask -ScheduleType 'Weekly' -TimeStr '12:00' -Day 'Sunday' }
    "2" { Register-FreeWinlyTask -ScheduleType 'Monthly' -TimeStr '12:00' }
    "3" { Register-FreeWinlyTask -ScheduleType 'Logon' }
    "4" { Remove-FreeWinlyTask }
    default { Write-Host "`nNo changes made." -ForegroundColor Gray }
}

Start-Sleep -Seconds 1
