#Requires -Version 5.1
<#
.SYNOPSIS
    FreeWinly User PATH Environment Variable Manager.
.DESCRIPTION
    Adds, removes, toggles, or checks FreeWinly directories (root, core, and modules)
    in the current Windows User's PATH environment variable. Does not require Administrator
    privileges and enables tab-completion of all 'freewinly-*' commands in any terminal.
.PARAMETER Action
    'Install' - Adds FreeWinly directories to User PATH.
    'Remove'  - Removes FreeWinly directories from User PATH.
    'Toggle'  - Installs if not present, or removes if already present.
    'Status'  - Checks whether FreeWinly is currently registered in User PATH.
.EXAMPLE
    .\core\freewinly-setup-path.ps1 -Action Install
.EXAMPLE
    .\core\freewinly-setup-path.ps1 -Action Remove
.EXAMPLE
    .\core\freewinly-setup-path.ps1 -Action Status
#>
[CmdletBinding()]
param(
    [ValidateSet('Install', 'Add', 'Remove', 'Toggle', 'Status')]
    [string]$Action = 'Install'
)

if ($Action -eq 'Add') { $Action = 'Install' }

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$coreDir     = Join-Path $projectRoot "core"
$modulesDir  = Join-Path $projectRoot "modules"

$targetDirs = @($projectRoot, $coreDir, $modulesDir)

function Get-RawUserPath {
    $envKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $false)
    if (-not $envKey) { return "" }
    try {
        $val = $envKey.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        return [string]$val
    } finally {
        $envKey.Dispose()
    }
}

function Send-EnvironmentChange {
    try {
        if (-not ([System.Management.Automation.PSTypeName]'FreeWinly.NativeMethods').Type) {
            Add-Type -Namespace 'FreeWinly' -Name 'NativeMethods' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Auto)]
public static extern System.IntPtr SendMessageTimeout(
    System.IntPtr hWnd,
    uint Msg,
    System.UIntPtr wParam,
    string lParam,
    uint fuFlags,
    uint uTimeout,
    out System.UIntPtr lpdwResult
);
'@
        }
        $res = [System.UIntPtr]::Zero
        [void][FreeWinly.NativeMethods]::SendMessageTimeout(
            [System.IntPtr]0xffff,
            0x001A,
            [System.UIntPtr]::Zero,
            "Environment",
            0x0002,
            5000,
            [ref]$res
        )
    } catch {
        # Best-effort broadcast; never fail PATH update if window broadcast times out
    }
}

function Set-RawUserPath {
    param([string]$NewPathValue)
    $envKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    if (-not $envKey) {
        $envKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')
    }
    try {
        $kind = if ($NewPathValue -match '%[^%]+%') {
            [Microsoft.Win32.RegistryValueKind]::ExpandString
        } else {
            [Microsoft.Win32.RegistryValueKind]::String
        }
        $envKey.SetValue('Path', $NewPathValue, $kind)
    } finally {
        $envKey.Dispose()
    }
    Send-EnvironmentChange
}

$userPathRaw = Get-RawUserPath
$userPaths   = if ($userPathRaw) {
    @($userPathRaw.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim() } | Where-Object { $_ })
} else {
    @()
}

function Compare-PathEntry {
    param([string]$A, [string]$B)
    return $A.Trim().TrimEnd('\').Equals($B.Trim().TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)
}

$isInstalled = @($userPaths | Where-Object { Compare-PathEntry $_ $projectRoot }).Count -gt 0

if ($Action -eq 'Status') {
    if ($isInstalled) {
        Write-Host "User PATH integration is enabled ($projectRoot)." -ForegroundColor Green
    } else {
        Write-Host "User PATH integration is disabled." -ForegroundColor Yellow
    }
    return
}

if ($Action -eq 'Toggle') {
    $Action = if ($isInstalled) { 'Remove' } else { 'Install' }
}

if ($Action -eq 'Remove') {
    $filtered = @($userPaths | Where-Object {
        $p = $_
        @($targetDirs | Where-Object { Compare-PathEntry $p $_ }).Count -eq 0
    })
    $newPathStr = $filtered -join ';'
    Set-RawUserPath -NewPathValue $newPathStr
    $envEntries = @($env:Path.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries) | Where-Object {
        $ep = $_
        @($targetDirs | Where-Object { Compare-PathEntry $ep $_ }).Count -eq 0
    })
    $env:Path = $envEntries -join ';'
    Write-Host "`nRemoved FreeWinly from User PATH." -ForegroundColor Yellow
    return
}

# Install Action
$updatedPaths = [System.Collections.Generic.List[string]]::new()
foreach ($p in $userPaths) {
    $updatedPaths.Add($p)
}

foreach ($td in $targetDirs) {
    $exists = @($updatedPaths | Where-Object { Compare-PathEntry $_ $td }).Count -gt 0
    if (-not $exists) {
        $updatedPaths.Add($td.TrimEnd('\'))
    }
}

$newPathStr = $updatedPaths -join ';'

# Safety limit: Windows User PATH string should not exceed 2048 characters to prevent truncation
if ($newPathStr.Length -ge 2048) {
    Write-Host "`n[ERROR] Cannot add FreeWinly to User PATH:" -ForegroundColor Red
    Write-Host "Target PATH length ($($newPathStr.Length) chars) exceeds safe Windows limit (2048 chars)." -ForegroundColor Red
    Write-Host "Modifying PATH would risk truncating environment variables. Please clean unused User PATH entries first.`n" -ForegroundColor Yellow
    exit 1
}

Set-RawUserPath -NewPathValue $newPathStr
$envList = [System.Collections.Generic.List[string]]::new()
foreach ($ep in $env:Path.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)) {
    $envList.Add($ep)
}
foreach ($td in $targetDirs) {
    if (($envList | Where-Object { Compare-PathEntry $_ $td }).Count -eq 0) {
        $envList.Add($td.TrimEnd('\'))
    }
}
$env:Path = $envList -join ';'

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "       FreeWinly Added to User PATH Successfully!           " -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Registered directories in User PATH:" -ForegroundColor Green
foreach ($td in $targetDirs) {
    Write-Host "  + $td" -ForegroundColor Gray
}
Write-Host "`nYou can now run 'freewinly' and tab-complete 'freewinly-*' in any new terminal!`n" -ForegroundColor Cyan
