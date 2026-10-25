#Requires -Version 5.1
<#
.SYNOPSIS
    FreeWinly v1.5.1 Interactive TUI & Keyboard Event Dispatcher.
.DESCRIPTION
    Provides the pure 7-bit ASCII interactive terminal user interface for
    FreeWinly. Features expandable tree-view sub-options, per-drive and
    per-app toggles, preset cycling, countdown auto-start, and hotkeys.
.NOTES
    Part of the FreeWinly Core Toolchain (Windows 11 Native).
#>

function Step-SubOptionValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Item,
        [Parameter(Mandatory = $true)]
        [ValidateSet('Toggle', 'StepLeft', 'StepRight')][string]$Direction
    )

    $mod = $Item.Module
    if (-not $mod) { return }

    switch ($Item.ValueType) {
        'drive' {
            Toggle-DriveSubOption -Item $Item
        }
        'customApp' {
            $custObj = if ($mod.Settings.customApps -is [System.Collections.IDictionary]) {
                $mod.Settings.customApps[$Item.CustomAppName]
            } else {
                $mod.Settings.customApps.$($Item.CustomAppName)
            }
            if ($custObj -is [bool]) {
                if ($mod.Settings.customApps -is [System.Collections.IDictionary]) {
                    $mod.Settings.customApps[$Item.CustomAppName] = -not $custObj
                } else {
                    $mod.Settings.customApps.$($Item.CustomAppName) = -not $custObj
                }
            } elseif ($null -ne $custObj -and $null -ne $custObj.enabled) {
                $custObj.enabled = -not [bool]$custObj.enabled
            }
        }
        'bool' {
            if ($mod.BaseName -eq 'freewinly-clean-apps' -and $null -ne $mod.Settings.$($Item.SubKey) -and -not ($mod.Settings.$($Item.SubKey) -is [bool])) {
                $mod.Settings.$($Item.SubKey).enabled = -not [bool]$mod.Settings.$($Item.SubKey).enabled
            } else {
                $mod.Settings.$($Item.SubKey) = -not [bool]$mod.Settings.$($Item.SubKey)
            }
            Update-ModuleDynamicProps -Module $mod
        }
        'int' {
            $presets = Get-IntPresets -Key $Item.SubKey
            $curVal  = [int]$mod.Settings.$($Item.SubKey)
            $idx     = $presets.IndexOf($curVal)
            $nextVal = switch ($Direction) {
                'StepLeft' {
                    if ($idx -gt 0) { $presets[$idx - 1] } else { $presets[0] }
                }
                'StepRight' {
                    if ($idx -ge 0 -and $idx -lt ($presets.Count - 1)) { $presets[$idx + 1] } else { $presets[-1] }
                }
                'Toggle' {
                    $nextIdx = if ($idx -ge 0 -and $idx -lt ($presets.Count - 1)) { $idx + 1 } else { 0 }
                    $presets[$nextIdx]
                }
            }
            $mod.Settings.$($Item.SubKey) = $nextVal
            Update-ModuleDynamicProps -Module $mod
        }
    }
}

function Invoke-InteractiveMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[PSCustomObject]]$DiscoveredModules,
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config,
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,
        [Parameter(Mandatory = $true)]
        [string]$CoreDir,
        [Parameter(Mandatory = $true)]
        [string]$LogFile,
        [Parameter()]
        [int]$Countdown = 10,
        [Parameter()]
        [string]$SubmenuView = "Hidden",
        [Parameter()]
        [System.Collections.Generic.List[string]]$IgnoredWarnings,
        [Parameter()]
        [hashtable]$ValidFileMap,
        [Parameter()]
        [System.Collections.Generic.List[string]]$OrderedBaseNames,
        [Parameter()]
        [bool]$IsInteractiveSession = $true,
        [Parameter()]
        [bool]$ConfigWasCorrupted = $false,
        [Parameter()]
        [PSCustomObject]$DefaultConfigTemplate = $null,
        [Parameter(Mandatory = $true)]
        [scriptblock]$SaveConfigCallback,
        [Parameter(Mandatory = $true)]
        [scriptblock]$DryRunCallback
    )

    Clear-Host
    Show-Banner
    if ($IgnoredWarnings -and $IgnoredWarnings.Count -gt 0) {
        Write-Host ""
        foreach ($w in $IgnoredWarnings) { Write-Host "  $w" -ForegroundColor Yellow }
    }
    Write-Host "`nScheduled Tasks to Run (in execution order):" -ForegroundColor Yellow

    foreach ($m in $DiscoveredModules) {
        $mark  = if ($m.Enabled) { "[x]" } else { "[ ]" }
        $admin = if ($m.RequiresAdmin) { " [Admin]" } else { "" }
        $col   = if ($m.Enabled) { "Green" } else { "DarkGray" }
        Write-Host "  $mark $($m.Name)$admin" -ForegroundColor $col
    }

    $openMenu = $false

    if ($Countdown -gt 0) {
        Write-Host "`nStarting in " -NoNewline -ForegroundColor Gray
        try {
            for ($sec = $Countdown; $sec -gt 0; $sec--) {
                Write-Host "$sec... " -NoNewline -ForegroundColor Cyan
                for ($sub = 0; $sub -lt 10; $sub++) {
                    Start-Sleep -Milliseconds 100
                    if ([Console]::KeyAvailable) {
                        [Console]::ReadKey($true) | Out-Null
                        $openMenu = $true
                        break
                    }
                }
                if ($openMenu) { break }
            }
        } catch {
            $openMenu = $false
        }
    }

    if (-not $openMenu -and $Countdown -gt 0) {
        return @{ Action = 'Run'; Countdown = $Countdown; SubmenuView = $SubmenuView }
    }

    $selectedIndex = 0
    $timerPresets = @(0, 3, 5, 10, 20, 30)
    $running = $true
    $anchorModule = $null

    while ($running) {
        # Build flat list of visible items (Modules and currently expanded SubOptions)
        $visibleItems = [System.Collections.Generic.List[hashtable]]::new()
        for ($i = 0; $i -lt $DiscoveredModules.Count; $i++) {
            $m = $DiscoveredModules[$i]
            $visibleItems.Add(@{
                Type        = 'Module'
                Module      = $m
                ModuleIndex = $i
            })
            $hasSubs = ($m.SubOptions -and $m.SubOptions.Count -gt 0)
            if ($m.Expanded -and $hasSubs) {
                foreach ($sub in $m.SubOptions) {
                    $visibleItems.Add(@{
                        Type          = 'SubOption'
                        Module        = $m
                        ModuleIndex   = $i
                        SubKey        = $sub.Key
                        DriveLetter   = $sub.DriveLetter
                        CustomAppName = $sub.CustomAppName
                        Label         = $sub.Label
                        ValueType     = $sub.ValueType
                    })
                }
            }
        }

        if ($anchorModule) {
            for ($v = 0; $v -lt $visibleItems.Count; $v++) {
                if ($visibleItems[$v].Type -eq 'Module' -and $visibleItems[$v].Module.BaseName -eq $anchorModule) {
                    $selectedIndex = $v
                    break
                }
            }
            $anchorModule = $null
        }

        $timerText = if ($Countdown -eq 0) { "0s (Instant)" } else { "${Countdown}s" }
        $schedSummary = if ($Config.scheduleType -and $Config.scheduleType -ne "Disabled") {
            if ($Config.scheduleType -eq "Logon") { "Logon (+5m)" }
            else { "$($Config.scheduleType) on $($Config.scheduleDay) at $($Config.scheduleTime)" }
        } else {
            "Disabled"
        }
        $pathStatus = if (Test-UserPathRegistered) { "Enabled" } else { "Disabled" }
        $submenuViewText = switch ($SubmenuView) {
            'Expanded' { 'Expanded' }
            'Custom'   { 'Custom' }
            default    { 'Hidden' }
        }

        $actions = @(
            @{ Label = "[ Enter ]  Run All Checked Tasks [x]"; Key = "Run" },
            @{ Label = "[   C   ]  Dry-Run Check / Diagnostic Audit (No changes)"; Key = "C" },
            @{ Label = "[   E   ]  Sub-Options View: [ $submenuViewText ] (Press E: Hidden, Custom, Expanded)"; Key = "E" },
            @{ Label = "[   T   ]  Auto-Start Countdown: [ $timerText ] (Press T to cycle)"; Key = "T" },
            @{ Label = "[   W   ]  Task Scheduler: [ $schedSummary ] (Press W to configure)"; Key = "W" },
            @{ Label = "[   P   ]  User PATH CLI Auto-Complete: [ $pathStatus ] (Press P to toggle)"; Key = "P" },
            @{ Label = "[   S   ]  Save Selection & Order as Default"; Key = "S" },
            @{ Label = "[   O   ]  Run Configuration & Exclusion Wizard"; Key = "O" },
            @{ Label = "[   I   ]  Install / Update Start Menu Launcher"; Key = "I" },
            @{ Label = "[   U   ]  Clean Windows Integrations & Shortcuts"; Key = "U" },
            @{ Label = "[   Q   ]  Quit Without Running"; Key = "Q" }
        )
        $totalOptions = $visibleItems.Count + $actions.Count
        if ($selectedIndex -ge $totalOptions) { $selectedIndex = $totalOptions - 1 }
        if ($selectedIndex -lt 0) { $selectedIndex = 0 }

        Clear-Host
        Show-Banner
        if ($IgnoredWarnings -and $IgnoredWarnings.Count -gt 0) {
            foreach ($w in $IgnoredWarnings) { Write-Host "  $w" -ForegroundColor Yellow }
        }
        Write-Host "Use [Up/Down] to navigate, [Space] to toggle, [Tab/Arrows] for sub-options, [+/-] to reorder:`n" -ForegroundColor Gray

        for ($v = 0; $v -lt $visibleItems.Count; $v++) {
            $item = $visibleItems[$v]
            $isSelected = ($v -eq $selectedIndex)
            $pointer = if ($isSelected) { "> " } else { "  " }

            if ($item.Type -eq 'Module') {
                $m = $item.Module
                $hasSubs = ($m.SubOptions -and $m.SubOptions.Count -gt 0)
                $expandMark = if ($hasSubs) {
                    if ($m.Expanded) { "[-] " } else { "[+] " }
                } else {
                    "    "
                }
                $checkMark = if ($m.Enabled) { "[x]" } else { "[ ]" }
                $admin = if ($m.RequiresAdmin) { " [Admin]" } else { "" }
                $color = if ($isSelected) { "Cyan" } elseif ($m.Enabled) { "Green" } else { "DarkGray" }
                Write-Host "$pointer$checkMark $expandMark$($m.Name)$admin" -ForegroundColor $color
            } else {
                $m = $item.Module
                if ($item.ValueType -eq 'bool') {
                    $subVal = [bool]$m.Settings.$($item.SubKey)
                    $subCheck = if ($subVal) { "[x]" } else { "[ ]" }
                    $line = "$pointer      $subCheck $($item.Label)"
                    $color = if ($isSelected) { "Cyan" } elseif ($m.Enabled -and $subVal) { "Green" } else { "DarkGray" }
                    Write-Host $line -ForegroundColor $color
                } elseif ($item.ValueType -eq 'drive') {
                    $excl = @()
                    if ($m.Settings.excludedDrives) {
                        $excl = @($m.Settings.excludedDrives | ForEach-Object { ([string]$_).TrimEnd(':').ToUpper() })
                    }
                    $isDriveEnabled = ($excl -notcontains $item.DriveLetter)
                    $subCheck = if ($isDriveEnabled) { "[x]" } else { "[ ]" }
                    $line = "$pointer      $subCheck $($item.Label)"
                    $color = if ($isSelected) { "Cyan" } elseif ($m.Enabled -and $isDriveEnabled) { "Green" } else { "DarkGray" }
                    Write-Host $line -ForegroundColor $color
                } elseif ($item.ValueType -eq 'customApp') {
                    $custObj = if ($m.Settings.customApps -is [System.Collections.IDictionary]) {
                        $m.Settings.customApps[$item.CustomAppName]
                    } else {
                        $m.Settings.customApps.$($item.CustomAppName)
                    }
                    $subVal = if ($custObj -is [bool]) { $custObj } elseif ($null -ne $custObj -and $null -ne $custObj.enabled) { [bool]$custObj.enabled } else { $true }
                    $subCheck = if ($subVal) { "[x]" } else { "[ ]" }
                    $line = "$pointer      $subCheck $($item.Label)  [Del to remove]"
                    $color = if ($isSelected) { "Cyan" } elseif ($m.Enabled -and $subVal) { "Green" } else { "DarkGray" }
                    Write-Host $line -ForegroundColor $color
                } elseif ($item.ValueType -eq 'addApp') {
                    $line = "$pointer      $($item.Label)"
                    $color = if ($isSelected) { "Cyan" } else { "Yellow" }
                    Write-Host $line -ForegroundColor $color
                } else {
                    $intVal = [int]$m.Settings.$($item.SubKey)
                    $line = "$pointer      < ${intVal}d > $($item.Label)"
                    $color = if ($isSelected) { "Cyan" } elseif ($m.Enabled) { "White" } else { "DarkGray" }
                    Write-Host $line -ForegroundColor $color
                }
            }
        }

        Write-Host "`n------------------------------------------------------------" -ForegroundColor DarkGray

        for ($j = 0; $j -lt $actions.Count; $j++) {
            $actionIdx = $visibleItems.Count + $j
            $pointer = if ($actionIdx -eq $selectedIndex) { "> " } else { "  " }
            $color   = if ($actionIdx -eq $selectedIndex) { "Yellow" } else { "White" }
            Write-Host "$pointer$($actions[$j].Label)" -ForegroundColor $color
        }

        $key = [Console]::ReadKey($true)
        $cmdKey = $key.Key.ToString()

        # Reorder module up/down with [+] / [-]
        if ($selectedIndex -lt $visibleItems.Count) {
            $curItem = $visibleItems[$selectedIndex]
            $targetMod = $curItem.Module
            $modIdx = $DiscoveredModules.IndexOf($targetMod)

            if ($key.KeyChar -eq '-' -or $key.Key -eq 'Subtract' -or $key.Key -eq 'OemMinus') {
                if ($modIdx -gt 0) {
                    $temp = $DiscoveredModules[$modIdx - 1]
                    $DiscoveredModules[$modIdx - 1] = $DiscoveredModules[$modIdx]
                    $DiscoveredModules[$modIdx] = $temp
                    $anchorModule = $targetMod.BaseName
                }
                continue
            } elseif ($key.KeyChar -eq '+' -or $key.Key -eq 'Add' -or $key.KeyChar -eq '=' -or $key.Key -eq 'OemPlus') {
                if ($modIdx -lt ($DiscoveredModules.Count - 1)) {
                    $temp = $DiscoveredModules[$modIdx + 1]
                    $DiscoveredModules[$modIdx + 1] = $DiscoveredModules[$modIdx]
                    $DiscoveredModules[$modIdx] = $temp
                    $anchorModule = $targetMod.BaseName
                }
                continue
            }
        }

        if ($cmdKey -eq "Enter") {
            if ($selectedIndex -lt $visibleItems.Count) {
                $cmdKey = "Spacebar"
            } else {
                $cmdKey = $actions[$selectedIndex - $visibleItems.Count].Key
            }
        }

        switch ($cmdKey) {
            "UpArrow" {
                $selectedIndex--
                if ($selectedIndex -lt 0) { $selectedIndex = $totalOptions - 1 }
            }
            "DownArrow" {
                $selectedIndex++
                if ($selectedIndex -ge $totalOptions) { $selectedIndex = 0 }
            }
            "Tab" {
                if ($selectedIndex -lt $visibleItems.Count) {
                    $item = $visibleItems[$selectedIndex]
                    $targetMod = $item.Module
                    $hasSubs = ($targetMod.SubOptions -and $targetMod.SubOptions.Count -gt 0)
                    if ($hasSubs) {
                        $targetMod.Expanded = -not $targetMod.Expanded
                        if ($SubmenuView -ne "Custom") { $SubmenuView = "Custom" }
                        if (-not $targetMod.Expanded -and $item.Type -eq 'SubOption') {
                            for ($k = $selectedIndex; $k -ge 0; $k--) {
                                if ($visibleItems[$k].Type -eq 'Module' -and $visibleItems[$k].Module.BaseName -eq $targetMod.BaseName) {
                                    $selectedIndex = $k
                                    break
                                }
                            }
                        }
                    }
                }
            }
            "LeftArrow" {
                if ($selectedIndex -lt $visibleItems.Count) {
                    $item = $visibleItems[$selectedIndex]
                    if ($item.Type -eq 'Module') {
                        if ($item.Module.Expanded) {
                            $item.Module.Expanded = $false
                            if ($SubmenuView -ne "Custom") { $SubmenuView = "Custom" }
                        }
                    } elseif ($item.Type -eq 'SubOption') {
                        Step-SubOptionValue -Item $item -Direction 'StepLeft'
                    }
                }
            }
            "RightArrow" {
                if ($selectedIndex -lt $visibleItems.Count) {
                    $item = $visibleItems[$selectedIndex]
                    if ($item.Type -eq 'Module') {
                        $hasSubs = ($item.Module.SubOptions -and $item.Module.SubOptions.Count -gt 0)
                        if ($hasSubs -and -not $item.Module.Expanded) {
                            $item.Module.Expanded = $true
                            if ($SubmenuView -ne "Custom") { $SubmenuView = "Custom" }
                        }
                    } elseif ($item.Type -eq 'SubOption') {
                        Step-SubOptionValue -Item $item -Direction 'StepRight'
                    }
                }
            }
            "Spacebar" {
                if ($selectedIndex -lt $visibleItems.Count) {
                    $item = $visibleItems[$selectedIndex]
                    if ($item.Type -eq 'Module') {
                        $item.Module.Enabled = -not $item.Module.Enabled
                        $item.Module.ConfigEnabled = $item.Module.Enabled
                    } elseif ($item.Type -eq 'SubOption') {
                        $mod = $item.Module
                        if ($item.ValueType -eq 'addApp') {
                            Clear-Host
                            & (Join-Path $CoreDir "freewinly-add-app.ps1") -ConfigPath $ConfigPath
                            $configLoad = Get-SafeConfigFile -Path $ConfigPath -IsInteractive $IsInteractiveSession -DefaultConfig $DefaultConfigTemplate
                            $Config = $configLoad.Config
                            if ($Config.modulesExecutionOrder -and $Config.modulesExecutionOrder.'freewinly-clean-apps') {
                                $mod.Settings.customApps = $Config.modulesExecutionOrder.'freewinly-clean-apps'.customApps
                            }
                            Refresh-CleanAppsSubOptions -Module $mod -ValidFileMap $ValidFileMap
                        } else {
                            Step-SubOptionValue -Item $item -Direction 'Toggle'
                        }
                    }
                }
            }
            { $_ -in @("Delete", "Back") } {
                if ($selectedIndex -lt $visibleItems.Count) {
                    $delItem = $visibleItems[$selectedIndex]
                    if ($delItem.Type -eq 'SubOption' -and $delItem.ValueType -eq 'customApp') {
                        $appName = $delItem.CustomAppName
                        Write-Host ""
                        $delConfirm = Read-Host "Are you sure you want to remove custom app '$appName'? (y/N)"
                        if ($delConfirm -match '^[Yy]$') {
                            & (Join-Path $CoreDir "freewinly-add-app.ps1") -Remove $appName -ConfigPath $ConfigPath
                            $configLoad = Get-SafeConfigFile -Path $ConfigPath -IsInteractive $IsInteractiveSession -DefaultConfig $DefaultConfigTemplate
                            $Config = $configLoad.Config
                            if ($Config.modulesExecutionOrder -and $Config.modulesExecutionOrder.'freewinly-clean-apps') {
                                $delItem.Module.Settings.customApps = $Config.modulesExecutionOrder.'freewinly-clean-apps'.customApps
                            }
                            Refresh-CleanAppsSubOptions -Module $delItem.Module -ValidFileMap $ValidFileMap
                            if ($selectedIndex -ge $visibleItems.Count) {
                                $selectedIndex = [math]::Max(0, $visibleItems.Count - 1)
                            }
                        }
                    }
                }
            }
            "Run" {
                $running = $false
            }
            { $_ -in @("C", "A") } {
                Clear-Host
                $targetModules = @($DiscoveredModules | Where-Object { $_.Enabled })
                & $DryRunCallback -TargetModules $targetModules
                Read-Host "`nPress Enter to return to menu"
            }
            "E" {
                $SubmenuView = switch ($SubmenuView) {
                    "Hidden"   { "Custom" }
                    "Custom"   { "Expanded" }
                    "Expanded" { "Hidden" }
                    default    { "Hidden" }
                }
                switch ($SubmenuView) {
                    "Hidden" {
                        foreach ($m in $DiscoveredModules) { $m.Expanded = $false }
                    }
                    "Expanded" {
                        foreach ($m in $DiscoveredModules) {
                            $m.Expanded = ($m.SubOptions -and $m.SubOptions.Count -gt 0)
                        }
                    }
                    "Custom" {
                        $savedExpanded = if ($Config.expandedModules) { @($Config.expandedModules) } else { @() }
                        foreach ($m in $DiscoveredModules) {
                            $m.Expanded = ($m.SubOptions -and $m.SubOptions.Count -gt 0) -and ($savedExpanded -contains $m.BaseName)
                        }
                    }
                }
            }
            "T" {
                $curIdx = $timerPresets.IndexOf($Countdown)
                $nextIdx = if ($curIdx -ge 0 -and $curIdx -lt ($timerPresets.Count - 1)) { $curIdx + 1 } else { 0 }
                $Countdown = $timerPresets[$nextIdx]
                & $SaveConfigCallback
            }
            "W" {
                Clear-Host
                & (Join-Path $CoreDir "freewinly-setup-schedule.ps1")
                $configLoad = Get-SafeConfigFile -Path $ConfigPath -IsInteractive $IsInteractiveSession -DefaultConfig $DefaultConfigTemplate
                $Config = $configLoad.Config
            }
            "P" {
                & (Join-Path $CoreDir "freewinly-setup-path.ps1") -Action Toggle
                Start-Sleep -Milliseconds 900
            }
            "S" {
                & $SaveConfigCallback
                Write-Host "`n  -> Module selection, order, sub-options, and view saved to config.json!" -ForegroundColor Green
                Start-Sleep -Milliseconds 800
            }
            "O" {
                & (Join-Path $CoreDir "freewinly-init-config.ps1") -ConfigPath $ConfigPath
                $configLoad = Get-SafeConfigFile -Path $ConfigPath -IsInteractive $IsInteractiveSession -DefaultConfig $DefaultConfigTemplate
                $Config = $configLoad.Config
            }
            "I" {
                & (Join-Path $CoreDir "freewinly-setup-launcher.ps1")
                Read-Host "`nPress Enter to return to menu"
            }
            "U" {
                Clear-Host
                & (Join-Path $CoreDir "freewinly-uninstall.ps1")
                Read-Host "`nPress Enter to return to menu"
            }
            { $_ -in @("Q", "Escape") } {
                Write-Host "`nExiting FreeWinly." -ForegroundColor Yellow
                exit 0
            }
        }
    }

    return @{
        Action      = 'Run'
        Countdown   = $Countdown
        SubmenuView = $SubmenuView
    }
}
