#Requires -Version 5.1
<#
.SYNOPSIS
    FreeWinly v1.5.0 Module Discovery & AST Contract Gatekeeper.
.DESCRIPTION
    Scans the modules directory, validates each maintenance module against
    the FreeWinly AST contract, reconciles execution order with config.json,
    discovers hardware-specific applicability (SSD/HDD), builds sub-options,
    and resolves dynamic module properties.
.NOTES
    Part of the FreeWinly Core Toolchain (Windows 11 Native).
#>

function Get-IntPresets {
    param([string]$Key)
    if ($Key -in @('minAgeDays', 'lookbackDays')) {
        return @(1, 3, 7, 14, 30, 60, 90)
    }
    return @(0, 1, 3, 7, 14, 30, 60, 90)
}

function Update-ModuleDynamicProps {
    param([PSCustomObject]$Module)
    if (-not $Module) { return }
    # 1. Dynamic Admin requirement (e.g. freewinly-clean-network if clearNetBios, resetWinsock, or clearArpCache is enabled)
    if ($Module.BaseName -eq 'freewinly-clean-network') {
        $hasAdminOption = [bool]($Module.Settings.clearNetBios -or $Module.Settings.resetWinsock -or $Module.Settings.clearArpCache)
        $Module.RequiresAdmin = $hasAdminOption
    }
    # 2. Dynamic title updates
    if ($Module.BaseName -eq 'freewinly-clean-cache' -and $null -ne $Module.Settings.minAgeDays) {
        $Module.Name = "Safe Cache & Temp Cleanup (>$($Module.Settings.minAgeDays) days)"
    } elseif ($Module.BaseName -eq 'freewinly-check-eventlog') {
        if ($Module.Settings.startDate) {
            $endLabel = if ($Module.Settings.endDate) { $Module.Settings.endDate } else { "Today" }
            $Module.Name = "System Stability & Event Logs ($($Module.Settings.startDate) to $endLabel)"
        } elseif ($Module.Settings.lookbackDays) {
            $Module.Name = "System Stability & Event Logs (Last $($Module.Settings.lookbackDays)d)"
        }
    }
}

function Toggle-DriveSubOption {
    param($Item)
    if (-not $Item -or -not $Item.Module -or -not $Item.DriveLetter) { return }
    $mod = $Item.Module
    $dl = ([string]$Item.DriveLetter).TrimEnd(':').ToUpper()
    $curExcl = @()
    if ($mod.Settings.excludedDrives) {
        $curExcl = @($mod.Settings.excludedDrives | ForEach-Object { ([string]$_).TrimEnd(':').ToUpper() })
    }
    if ($curExcl -contains $dl) {
        $newExcl = @($curExcl | Where-Object { $_ -ne $dl })
    } else {
        $newExcl = @($curExcl) + @($dl)
    }
    $mod.Settings.excludedDrives = [string[]]$newExcl
    Update-ModuleDynamicProps -Module $mod
}

function Refresh-CleanAppsSubOptions {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Module,
        [Parameter()]
        [hashtable]$ValidFileMap = $null
    )
    if (-not $Module -or $Module.BaseName -ne 'freewinly-clean-apps') { return }
    $entry = if ($ValidFileMap -and $ValidFileMap.ContainsKey('freewinly-clean-apps')) {
        $ValidFileMap['freewinly-clean-apps']
    } elseif ($script:validFileMap -and $script:validFileMap.ContainsKey('freewinly-clean-apps')) {
        $script:validFileMap['freewinly-clean-apps']
    } else {
        $null
    }
    if (-not $entry) { return }
    $info = $entry.Info
    $newSubs = [System.Collections.Generic.List[PSCustomObject]]::new()
    if ($info.SettingsDescriptions) {
        $descKeys = if ($info.SettingsDescriptions -is [System.Collections.IDictionary]) {
            $info.SettingsDescriptions.Keys
        } else {
            $info.SettingsDescriptions.PSObject.Properties.Name
        }
        foreach ($sk in $descKeys) {
            $valType = if ($sk -match 'Days') { 'int' } else { 'bool' }
            $newSubs.Add([PSCustomObject]@{
                Key       = $sk
                Label     = [string]$info.SettingsDescriptions[$sk]
                ValueType = $valType
            })
        }
    }
    if ($Module.Settings.customApps) {
        $cKeys = if ($Module.Settings.customApps -is [System.Collections.IDictionary]) {
            $Module.Settings.customApps.Keys
        } else {
            $Module.Settings.customApps.PSObject.Properties.Name
        }
        foreach ($ck in $cKeys) {
            $newSubs.Add([PSCustomObject]@{
                Key           = "customApp_$ck"
                CustomAppName = $ck
                Label         = "$ck cache (custom)"
                ValueType     = 'customApp'
            })
        }
    }
    $newSubs.Add([PSCustomObject]@{
        Key       = "add_new_app"
        Label     = "[ + Add new app... ]"
        ValueType = 'addApp'
    })
    $Module.SubOptions = $newSubs
}

function Test-UserPathRegistered {
    param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))
    $userPathRaw = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not $userPathRaw) { return $false }
    $normRoot = $ProjectRoot.TrimEnd('\')
    return (($userPathRaw.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries) | Where-Object {
        $_.Trim().TrimEnd('\').Equals($normRoot, [System.StringComparison]::OrdinalIgnoreCase)
    }).Count -gt 0)
}

function Test-ModuleContract {
    param([string]$FilePath)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($FilePath, [ref]$tokens, [ref]$parseErrors)

    if ($parseErrors -and $parseErrors.Count -gt 0) {
        return [PSCustomObject]@{
            IsValid = $false
            Reason  = "Syntax error at line $($parseErrors[0].Extent.StartLineNumber): $($parseErrors[0].Message)"
            Info    = $null
        }
    }

    if (-not $ast.ParamBlock -or -not $ast.ParamBlock.Parameters) {
        return [PSCustomObject]@{
            IsValid = $false
            Reason  = "Missing param() block with required '-Action' parameter (Info, Check, Run)."
            Info    = $null
        }
    }

    $paramNames = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
    foreach ($req in @('Action', 'Settings', 'LogFile')) {
        if (-not ($paramNames -contains $req)) {
            return [PSCustomObject]@{
                IsValid = $false
                Reason  = "Missing required '-$req' parameter in param() block."
                Info    = $null
            }
        }
    }

    $info = $null
    try {
        $info = & $FilePath -Action Info -ErrorAction Stop
    } catch {
        return [PSCustomObject]@{
            IsValid = $false
            Reason  = "Execution of '-Action Info' failed: $($_.Exception.Message)"
            Info    = $null
        }
    }

    if (-not $info) {
        return [PSCustomObject]@{
            IsValid = $false
            Reason  = "'-Action Info' returned null instead of a metadata object."
            Info    = $null
        }
    }

    if (-not ($info.Name -is [string]) -or [string]::IsNullOrWhiteSpace($info.Name)) {
        return [PSCustomObject]@{
            IsValid = $false
            Reason  = "Metadata is missing a valid 'Name' string."
            Info    = $null
        }
    }

    $cleanName = $info.Name.Trim()
    if ($cleanName.Length -lt 3 -or $cleanName.Length -gt 50) {
        return [PSCustomObject]@{
            IsValid = $false
            Reason  = "Name '$($cleanName.Substring(0, [math]::Min(25, $cleanName.Length)))...' must be 3-50 characters (got $($cleanName.Length) chars)."
            Info    = $null
        }
    }

    if ($cleanName -match '[\r\n]') {
        return [PSCustomObject]@{
            IsValid = $false
            Reason  = "Name must be a single line without newline characters."
            Info    = $null
        }
    }

    if (-not ($info.Description -is [string]) -or [string]::IsNullOrWhiteSpace($info.Description)) {
        return [PSCustomObject]@{
            IsValid = $false
            Reason  = "Metadata is missing a valid 'Description' string."
            Info    = $null
        }
    }

    if ($info.Description.Trim().Length -gt 120) {
        return [PSCustomObject]@{
            IsValid = $false
            Reason  = "Description exceeds maximum length of 120 characters ($($info.Description.Trim().Length) chars)."
            Info    = $null
        }
    }

    if (-not ($info.Default -is [bool])) {
        return [PSCustomObject]@{
            IsValid = $false
            Reason  = "Metadata 'Default' property must be a boolean (`$true or `$false)."
            Info    = $null
        }
    }

    if (-not ($info.RequiresAdmin -is [bool])) {
        return [PSCustomObject]@{
            IsValid = $false
            Reason  = "Metadata 'RequiresAdmin' property must be a boolean (`$true or `$false)."
            Info    = $null
        }
    }

    return [PSCustomObject]@{
        IsValid = $true
        Reason  = $null
        Info    = $info
    }
}

function Get-DiscoveredModules {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModulesDir,
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config,
        [Parameter()]
        [array]$ModulesFilter = $null,
        [Parameter()]
        [hashtable]$CliSettings = $null
    )

    $moduleFiles = Get-ChildItem (Join-Path $ModulesDir "*.ps1") -ErrorAction SilentlyContinue
    $validFileMap = @{}
    $ignoredWarnings = [System.Collections.Generic.List[string]]::new()

    foreach ($mf in $moduleFiles) {
        $validation = Test-ModuleContract -FilePath $mf.FullName
        if (-not $validation.IsValid) {
            $msg = "[Module Ignored] '$($mf.Name)' was not loaded: $($validation.Reason)"
            $ignoredWarnings.Add($msg)
            Write-Host $msg -ForegroundColor Yellow
            continue
        }
        $validFileMap[$mf.BaseName] = [PSCustomObject]@{
            File = $mf
            Info = $validation.Info
        }
    }

    # Reconcile execution order:
    # 1. First in sequence defined in config.modulesExecutionOrder
    # 2. Followed by any newly added modules sorted by their Info.Order
    $orderedBaseNames = [System.Collections.Generic.List[string]]::new()
    $hasModOrderConfig = ($null -ne $Config.modulesExecutionOrder)

    if ($hasModOrderConfig) {
        $cfgKeys = if ($Config.modulesExecutionOrder -is [System.Collections.IDictionary]) {
            $Config.modulesExecutionOrder.Keys
        } else {
            $Config.modulesExecutionOrder.PSObject.Properties.Name
        }
        foreach ($k in $cfgKeys) {
            if ($validFileMap.ContainsKey($k) -and -not $orderedBaseNames.Contains($k)) {
                $orderedBaseNames.Add($k)
            }
        }
    }

    $newModules = @($validFileMap.Keys | Where-Object { -not $orderedBaseNames.Contains($_) } | ForEach-Object {
        [PSCustomObject]@{
            BaseName = $_
            Order    = if ($null -ne $validFileMap[$_].Info.Order) { [int]$validFileMap[$_].Info.Order } else { 99 }
        }
    } | Sort-Object Order, BaseName)

    foreach ($nm in $newModules) {
        $orderedBaseNames.Add($nm.BaseName)
    }

    $submenuView = if ($Config -and $Config.submenuView) { [string]$Config.submenuView } else { "Hidden" }
    $expandedCfg = if ($Config -and $Config.expandedModules) { @($Config.expandedModules) } else { @() }
    $discoveredModules = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($baseName in $orderedBaseNames) {
        $entry = $validFileMap[$baseName]
        $mf    = $entry.File
        $info  = $entry.Info

        # Build merged settings object (DefaultSettings overlaid with user config block)
        $modSettings = [ordered]@{}
        if ($info.DefaultSettings) {
            $defKeys = if ($info.DefaultSettings -is [System.Collections.IDictionary]) {
                $info.DefaultSettings.Keys
            } else {
                $info.DefaultSettings.PSObject.Properties.Name
            }
            foreach ($dk in $defKeys) {
                $modSettings[$dk] = $info.DefaultSettings[$dk]
            }
        }

        $cfgEntry = if ($hasModOrderConfig) { $Config.modulesExecutionOrder.$baseName } else { $null }
        $enabledInCfg = $null

        if ($null -ne $cfgEntry) {
            if ($cfgEntry -is [bool]) {
                $enabledInCfg = $cfgEntry
            } else {
                if ($null -ne $cfgEntry.enabled) {
                    $enabledInCfg = [bool]$cfgEntry.enabled
                }
                $uKeys = if ($cfgEntry -is [System.Collections.IDictionary]) {
                    $cfgEntry.Keys
                } else {
                    $cfgEntry.PSObject.Properties.Name
                }
                foreach ($uk in $uKeys) {
                    if ($uk -ne 'enabled') {
                        $modSettings[$uk] = $cfgEntry.$uk
                    }
                }
            }
        }

        # Overlay CLI -Settings if passed on the command line
        if ($CliSettings -and $ModulesFilter -and ($ModulesFilter -contains $baseName)) {
            foreach ($ck in $CliSettings.Keys) {
                $modSettings[$ck] = $CliSettings[$ck]
            }
        }

        # Determine if enabled:
        # - CLI -Modules override > config.modulesExecutionOrder > (if brand new unconfigured module & config exists: false, else Info.Default)
        $configEnabled = if ($null -ne $enabledInCfg) {
            [bool]$enabledInCfg
        } elseif ($hasModOrderConfig) {
            $false
        } else {
            [bool]$info.Default
        }

        $isEnabled = if ($ModulesFilter) {
            $ModulesFilter -contains $baseName
        } else {
            $configEnabled
        }

        $settingsObj = [PSCustomObject]$modSettings

        # Update dynamic title if minAgeDays or lookbackDays was customized in settings
        $displayName = $info.Name
        if ($baseName -eq 'freewinly-clean-cache' -and $null -ne $settingsObj.minAgeDays) {
            $displayName = "Safe Cache & Temp Cleanup (>$($settingsObj.minAgeDays) days)"
        } elseif ($baseName -eq 'freewinly-check-eventlog') {
            if ($settingsObj.startDate) {
                $endLabel = if ($settingsObj.endDate) { $settingsObj.endDate } else { "Today" }
                $displayName = "System Stability & Event Logs ($($settingsObj.startDate) to $endLabel)"
            } elseif ($settingsObj.lookbackDays) {
                $displayName = "System Stability & Event Logs (Last $($settingsObj.lookbackDays)d)"
            }
        }

        $isApplicable = if ($null -ne $info.Applicable) { [bool]$info.Applicable } else { $true }

        # Skip inapplicable hardware modules (e.g. HDD Defrag on SSD-only PC) from menu unless explicitly requested via -Modules
        if (-not $isApplicable -and -not ($ModulesFilter -and $ModulesFilter -contains $baseName)) {
            continue
        }

        $subOptions = [System.Collections.Generic.List[PSCustomObject]]::new()
        if ($info.SettingsDescriptions) {
            $descKeys = if ($info.SettingsDescriptions -is [System.Collections.IDictionary]) {
                $info.SettingsDescriptions.Keys
            } else {
                $info.SettingsDescriptions.PSObject.Properties.Name
            }
            foreach ($sk in $descKeys) {
                $curVal = if ($modSettings.Contains($sk)) {
                    $modSettings[$sk]
                } elseif ($info.DefaultSettings -and $info.DefaultSettings.Contains($sk)) {
                    $info.DefaultSettings[$sk]
                } else { $null }

                $valType = if ($curVal -is [bool]) {
                    'bool'
                } elseif ($curVal -is [int]) {
                    'int'
                } else {
                    if ($sk -match 'Days') { 'int' } else { 'bool' }
                }

                $subOptions.Add([PSCustomObject]@{
                    Key       = $sk
                    Label     = [string]$info.SettingsDescriptions[$sk]
                    ValueType = $valType
                })
            }
        }

        # Dynamic DetectedDrives sub-options (e.g. per-drive TRIM/Defrag targets)
        if ($info.DetectedDrives -and $info.DetectedDrives.Count -gt 0) {
            foreach ($d in $info.DetectedDrives) {
                $dl = ([string]$d.DriveLetter).TrimEnd(':').ToUpper()
                $verb = if ($baseName -eq 'freewinly-defrag-hdd') { "Defragment Drive ${dl}:" } else { "Optimize Drive ${dl}:" }
                $labelPart = if ($d.Label) { "$($d.Label) - " } else { "" }
                $modelPart = if ($d.Model) { "$($d.Model)" } else { "Fixed Disk" }
                $sizePart  = if ($d.SizeGB) { ", $($d.SizeGB) GB" } else { "" }
                $driveLabel = "$verb ($labelPart$modelPart$sizePart)"

                $subOptions.Add([PSCustomObject]@{
                    Key         = "drive_$dl"
                    DriveLetter = $dl
                    Label       = $driveLabel
                    ValueType   = 'drive'
                })
            }
        }

        # Dynamic Custom Apps & Add New App sub-options for freewinly-clean-apps
        if ($baseName -eq 'freewinly-clean-apps') {
            if ($modSettings.customApps) {
                $cKeys = if ($modSettings.customApps -is [System.Collections.IDictionary]) {
                    $modSettings.customApps.Keys
                } else {
                    $modSettings.customApps.PSObject.Properties.Name
                }
                foreach ($ck in $cKeys) {
                    $subOptions.Add([PSCustomObject]@{
                        Key           = "customApp_$ck"
                        CustomAppName = $ck
                        Label         = "$ck cache (custom)"
                        ValueType     = 'customApp'
                    })
                }
            }
            $subOptions.Add([PSCustomObject]@{
                Key       = "add_new_app"
                Label     = "[ + Add new app... ]"
                ValueType = 'addApp'
            })
        }

        $hasSubs = ($subOptions.Count -gt 0)
        $isExpanded = switch ($submenuView) {
            "Expanded" { $hasSubs }
            "Custom"   { $hasSubs -and ($expandedCfg -contains $baseName) }
            default    { $false }
        }

        $modObj = [PSCustomObject]@{
            BaseName      = $baseName
            Name          = $displayName
            Description   = $info.Description
            Path          = $mf.FullName
            Enabled       = [bool]$isEnabled
            ConfigEnabled = [bool]$configEnabled
            RequiresAdmin = [bool]$info.RequiresAdmin
            Settings      = $settingsObj
            SubOptions    = $subOptions
            Expanded      = [bool]$isExpanded
        }

        Update-ModuleDynamicProps -Module $modObj
        $discoveredModules.Add($modObj)
    }

    return [PSCustomObject]@{
        DiscoveredModules = $discoveredModules
        ValidFileMap      = $validFileMap
        OrderedBaseNames  = $orderedBaseNames
        IgnoredWarnings   = $ignoredWarnings
        SubmenuView       = $submenuView
    }
}
