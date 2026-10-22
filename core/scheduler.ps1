#Requires -Version 5.1
<#
.SYNOPSIS
    FreeWinly Windows Task Scheduler Automation.
.DESCRIPTION
    Configures, inspects, or removes a native Windows Scheduled Task to run FreeWinly
    automatically in the background. Uses Windows Task Scheduler without persistent
    background services or tray icons.
.PARAMETER Action
    'Interactive' - Opens clean interactive panel to configure schedule.
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
    .\core\scheduler.ps1
.EXAMPLE
    .\core\scheduler.ps1 -Action Weekly -DayOfWeek Sunday -At 14:00
.EXAMPLE
    .\core\scheduler.ps1 -Action Remove
#>
[CmdletBinding()]
param(
    [ValidateSet('Interactive', 'Status', 'Weekly', 'Monthly', 'Logon', 'Remove')]
    [string]$Action = 'Interactive',

    [string]$At = $null,
    [string]$DayOfWeek = $null
)

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$taskName = "FreeWinly"
$projectRoot = Split-Path -Parent $PSScriptRoot
$runnerScript = Join-Path $projectRoot "freewinly.ps1"
$configPath = Join-Path $projectRoot "config.json"

$weekdays = @('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')
$modes    = @('Weekly', 'Monthly', 'Logon')

function Get-TaskStatusInfo {
    try {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
        $state = $task.State
        $trigger = $task.Triggers[0]
        $triggerClass = $trigger.CimClass.CimClassName
        
        $schedDesc = if ($triggerClass -match 'Logon') {
            "At Logon (+5m delay)"
        } elseif ($triggerClass -match 'Weekly') {
            $timePart = if ($trigger.StartBoundary) {
                try { ([datetime]$trigger.StartBoundary).ToString("HH:mm") } catch { "12:00" }
            } else { "12:00" }

            $dayName = switch ($trigger.DaysOfWeek) {
                1 { "Sunday" }
                2 { "Monday" }
                4 { "Tuesday" }
                8 { "Wednesday" }
                16 { "Thursday" }
                32 { "Friday" }
                64 { "Saturday" }
                default { "Sunday" }
            }

            if ($trigger.WeeksInterval -eq 4) {
                "Monthly on $dayName at $timePart"
            } else {
                "Weekly on $dayName at $timePart"
            }
        } else {
            "Custom schedule"
        }

        return [PSCustomObject]@{
            Installed = $true
            State     = [string]$state
            Schedule  = $schedDesc
            Summary   = "[Installed] State: $state | Schedule: $schedDesc"
        }
    } catch {
        return [PSCustomObject]@{
            Installed = $false
            State     = "NotInstalled"
            Schedule  = "None"
            Summary   = "[Not Installed] No scheduled maintenance task currently registered."
        }
    }
}

function Show-Header {
    param([string]$StatusText)
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "       FreeWinly - Windows Task Scheduler Setup             " -ForegroundColor White
    Write-Host "       Runs on schedule without background services or icons" -ForegroundColor Gray
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "Windows Task Status: $StatusText`n" -ForegroundColor Yellow
}

function Save-ScheduleToConfig {
    param(
        [string]$Type,
        [string]$Day,
        [string]$Time
    )
    if (Test-Path $configPath) {
        try {
            $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
            $cfg | Add-Member -NotePropertyName scheduleType -NotePropertyValue $Type -Force
            $cfg | Add-Member -NotePropertyName scheduleDay -NotePropertyValue $Day -Force
            $cfg | Add-Member -NotePropertyName scheduleTime -NotePropertyValue $Time -Force
            $cfg | ConvertTo-Json -Depth 5 | Out-File -FilePath $configPath -Encoding UTF8
        } catch { }
    }
}

function Remove-ScheduleFromConfig {
    if (Test-Path $configPath) {
        try {
            $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
            $cfg | Add-Member -NotePropertyName scheduleType -NotePropertyValue "Disabled" -Force
            $cfg | ConvertTo-Json -Depth 5 | Out-File -FilePath $configPath -Encoding UTF8
        } catch { }
    }
}

function Register-FreeWinlyTask {
    param(
        [string]$ScheduleType,
        [string]$TimeStr = '12:00',
        [string]$Day = 'Sunday'
    )

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "`nRegistering scheduled maintenance requires Administrator privileges." -ForegroundColor Yellow
        Write-Host "Requesting elevation..." -ForegroundColor Cyan
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Action $ScheduleType -At `"$TimeStr`" -DayOfWeek `"$Day`""
        return
    }

    $time = try { [datetime]::ParseExact($TimeStr, 'HH:mm', $null) } catch { (Get-Date).Date.AddHours(12) }

    $trigger = switch ($ScheduleType) {
        'Weekly' {
            New-ScheduledTaskTrigger -Weekly -DaysOfWeek $Day -At $time
        }
        'Monthly' {
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

    $taskAction = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$runnerScript`" -Run" `
        -WorkingDirectory $projectRoot

    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 2)

    try {
        Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $trigger -Principal $principal -Settings $settings -Description "FreeWinly Automated PC Maintenance" -Force | Out-Null
        Save-ScheduleToConfig -Type $ScheduleType -Day $Day -Time $TimeStr
        Write-Host "`n[SUCCESS] Scheduled task '$taskName' registered / updated successfully!" -ForegroundColor Green
        Write-Host "Schedule: $ScheduleType" -ForegroundColor Cyan
        if ($ScheduleType -ne 'Logon') {
            Write-Host "Day/Time: Every $Day at $TimeStr" -ForegroundColor Cyan
        } else {
            Write-Host "Trigger:  5 minutes after logon" -ForegroundColor Cyan
        }
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
        Remove-ScheduleFromConfig
        Write-Host "`n[SUCCESS] Scheduled task '$taskName' removed cleanly from Windows." -ForegroundColor Green
    } catch {
        Write-Host "`nTask '$taskName' was not found or already removed." -ForegroundColor Yellow
    }
}

function Adjust-Hour {
    param([string]$TimeStr, [int]$Delta)
    $hour = 12
    $min  = 0
    if ($TimeStr -match '^(\d{1,2}):(\d{2})$') {
        $hour = [int]$matches[1]
        $min  = [int]$matches[2]
    }
    $newHour = ($hour + $Delta) % 24
    if ($newHour -lt 0) { $newHour += 24 }
    return ("{0:D2}:{1:D2}" -f $newHour, $min)
}

# Resolve defaults from config.json if present
$cfg = if (Test-Path $configPath) {
    try { Get-Content $configPath -Raw | ConvertFrom-Json } catch { $null }
} else { $null }

$defaultType = if ($cfg -and $cfg.scheduleType -and $cfg.scheduleType -ne "Disabled") { $cfg.scheduleType } else { "Weekly" }
$defaultDay  = if ($cfg -and $cfg.scheduleDay) { $cfg.scheduleDay } else { "Sunday" }
$defaultTime = if ($cfg -and $cfg.scheduleTime) { $cfg.scheduleTime } else { "12:00" }

if ($At) { $defaultTime = $At }
if ($DayOfWeek) { $defaultDay = $DayOfWeek }

if ($Action -eq 'Status') {
    $info = Get-TaskStatusInfo
    Show-Header -StatusText $info.Summary
    exit 0
}

if ($Action -eq 'Weekly') {
    Register-FreeWinlyTask -ScheduleType 'Weekly' -TimeStr $defaultTime -Day $defaultDay
    exit 0
}

if ($Action -eq 'Monthly') {
    Register-FreeWinlyTask -ScheduleType 'Monthly' -TimeStr $defaultTime -Day $defaultDay
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

# ==================================================================
# INTERACTIVE PANEL (In-Memory Staging with Confirmation)
# ==================================================================
$selectedMode = $defaultType
$selectedDay  = $defaultDay
$selectedTime = $defaultTime

$selectedIndex = 0
$running = $true

while ($running) {
    $statusInfo = Get-TaskStatusInfo
    Clear-Host
    Show-Header -StatusText $statusInfo.Summary

    Write-Host "Staged Schedule Configuration (Use keys below to adjust):`n" -ForegroundColor White

    $dayDisplay = if ($selectedMode -eq 'Logon') { "N/A (At Logon)" } else { $selectedDay }
    $timeDisplay = if ($selectedMode -eq 'Logon') { "N/A (+5m delay)" } else { $selectedTime }

    $options = @(
        @{ Label = "Schedule Mode:    [ $selectedMode ]";  Help = "(Press Space/M to cycle: Weekly -> Monthly -> Logon)" },
        @{ Label = "Day of Week:      [ $dayDisplay ]";   Help = "(Press Space/D to cycle: Sun -> Mon -> Tue...)" },
        @{ Label = "Scheduled Time:   [ $timeDisplay ]";  Help = "(Press + / - to adjust hour)" },
        @{ Label = "[ Enter / S ]  Confirm & Apply to Windows Task Scheduler"; Help = "(Saves to config.json and updates task)" },
        @{ Label = "[     R     ]  Remove Scheduled Task from Windows";        Help = "(Deletes task from Task Scheduler)" },
        @{ Label = "[     Q     ]  Cancel & Return to Menu";                   Help = "(Discards unstaged adjustments)" }
    )

    for ($i = 0; $i -lt $options.Count; $i++) {
        $opt = $options[$i]
        $pointer = if ($i -eq $selectedIndex) { "> " } else { "  " }
        $color   = if ($i -eq $selectedIndex) { "Cyan" } elseif ($i -ge 3) { "Yellow" } else { "White" }

        if ($i -eq 3) {
            Write-Host "`n------------------------------------------------------------" -ForegroundColor DarkGray
        }

        Write-Host "$pointer$($opt.Label)  " -NoNewline -ForegroundColor $color
        Write-Host "$($opt.Help)" -ForegroundColor Gray
    }

    Write-Host "`nControls: [Up/Down] Navigate  |  [D] Next Day  |  [+] Later  |  [-] Earlier  |  [Enter] Confirm" -ForegroundColor DarkGray

    $key = [Console]::ReadKey($true)

    # Global time adjusters (+ / -)
    if ($key.KeyChar -eq '+' -or $key.Key -eq 'Add' -or $key.KeyChar -eq '=') {
        if ($selectedMode -ne 'Logon') {
            $selectedTime = Adjust-Hour -TimeStr $selectedTime -Delta 1
        }
        continue
    }
    if ($key.KeyChar -eq '-' -or $key.Key -eq 'Subtract' -or $key.KeyChar -eq '_') {
        if ($selectedMode -ne 'Logon') {
            $selectedTime = Adjust-Hour -TimeStr $selectedTime -Delta -1
        }
        continue
    }

    # Global day cycler (D)
    if ($key.Key -eq 'D') {
        if ($selectedMode -ne 'Logon') {
            $dayIdx = $weekdays.IndexOf($selectedDay)
            if ($dayIdx -lt 0) { $dayIdx = 0 }
            $dayIdx = ($dayIdx + 1) % $weekdays.Count
            $selectedDay = $weekdays[$dayIdx]
        }
        continue
    }

    # Global mode cycler (M)
    if ($key.Key -eq 'M') {
        $mIdx = $modes.IndexOf($selectedMode)
        if ($mIdx -lt 0) { $mIdx = 0 }
        $mIdx = ($mIdx + 1) % $modes.Count
        $selectedMode = $modes[$mIdx]
        continue
    }

    $actionKey = $key.Key.ToString()
    if ($actionKey -eq "Enter") {
        switch ($selectedIndex) {
            3 { $actionKey = "S" }
            4 { $actionKey = "R" }
            5 { $actionKey = "Q" }
            default { $actionKey = "RightArrow" }
        }
    } elseif ($actionKey -eq "Spacebar") {
        $actionKey = "RightArrow"
    }

    switch ($actionKey) {
        "UpArrow" {
            $selectedIndex--
            if ($selectedIndex -lt 0) { $selectedIndex = $options.Count - 1 }
        }
        "DownArrow" {
            $selectedIndex++
            if ($selectedIndex -ge $options.Count) { $selectedIndex = 0 }
        }
        "LeftArrow" {
            if ($selectedIndex -eq 0) {
                $mIdx = ($modes.IndexOf($selectedMode) - 1 + $modes.Count) % $modes.Count
                $selectedMode = $modes[$mIdx]
            } elseif ($selectedIndex -eq 1 -and $selectedMode -ne 'Logon') {
                $dayIdx = ($weekdays.IndexOf($selectedDay) - 1 + $weekdays.Count) % $weekdays.Count
                $selectedDay = $weekdays[$dayIdx]
            } elseif ($selectedIndex -eq 2 -and $selectedMode -ne 'Logon') {
                $selectedTime = Adjust-Hour -TimeStr $selectedTime -Delta -1
            }
        }
        "RightArrow" {
            if ($selectedIndex -eq 0) {
                $mIdx = ($modes.IndexOf($selectedMode) + 1) % $modes.Count
                $selectedMode = $modes[$mIdx]
            } elseif ($selectedIndex -eq 1 -and $selectedMode -ne 'Logon') {
                $dayIdx = ($weekdays.IndexOf($selectedDay) + 1) % $weekdays.Count
                $selectedDay = $weekdays[$dayIdx]
            } elseif ($selectedIndex -eq 2 -and $selectedMode -ne 'Logon') {
                $selectedTime = Adjust-Hour -TimeStr $selectedTime -Delta 1
            }
        }
        "S" {
            Save-ScheduleToConfig -Type $selectedMode -Day $selectedDay -Time $selectedTime
            Register-FreeWinlyTask -ScheduleType $selectedMode -TimeStr $selectedTime -Day $selectedDay
            Start-Sleep -Seconds 2
            $running = $false
        }
        "R" {
            Remove-FreeWinlyTask
            Start-Sleep -Seconds 2
            $running = $false
        }
        { $_ -in @("Q", "Escape") } {
            Write-Host "`nNo changes were saved." -ForegroundColor Yellow
            $running = $false
        }
    }
}
