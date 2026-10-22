#Requires -Version 5.1
<#
.SYNOPSIS
    Cleans superseded Windows Update payloads and checks Windows Component Store health.
.DESCRIPTION
    Uses native Deployment Image Servicing and Management (DISM) to analyze and purge
    superseded Windows Update files inside C:\Windows\WinSxS.
    
    Optionally removes previous update baselines (/ResetBase) to reclaim additional gigabytes
    and runs System File Checker (sfc /verifyonly) to verify protected Windows system files.
.PARAMETER Action
    'Info'  - Outputs module metadata (Name, Description, Order, Default, RequiresAdmin, DefaultSettings, SettingsDescriptions).
    'Check' - Analyzes component store health and previews maintenance operations.
    'Run'   - Executes DISM component store cleanup and optional system file verification. Requires Administrator rights.
.PARAMETER Settings
    Optional module settings object or hashtable (supports verifySystemFiles and resetBase).
.PARAMETER LogFile
    Optional file path to append execution statistics.
.EXAMPLE
    .\modules\freewinly-clean-winsxs.ps1 -Action Info
.EXAMPLE
    .\modules\freewinly-clean-winsxs.ps1 -Action Check
.EXAMPLE
    .\modules\freewinly-clean-winsxs.ps1 -Action Run -Settings @{ resetBase = $true; verifySystemFiles = $true }
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('Info', 'Check', 'Run')]
    [string]$Action = 'Run',

    [Parameter()]
    [object]$Settings = $null,

    [Parameter()]
    [string]$LogFile = $null
)

$verifySystemFiles = if ($null -ne $Settings -and $null -ne $Settings.verifySystemFiles) { [bool]$Settings.verifySystemFiles } else { $false }
$resetBase         = if ($null -ne $Settings -and $null -ne $Settings.resetBase) { [bool]$Settings.resetBase } else { $false }

if ($Action -eq 'Info') {
    return [PSCustomObject]@{
        Name                 = "Windows Component Store Cleanup (DISM)"
        Description          = "Analyzes and cleans superseded Windows Update payloads in C:\Windows\WinSxS via native DISM"
        Order                = 34
        Default              = $false
        RequiresAdmin        = $true
        DefaultSettings      = [ordered]@{
            verifySystemFiles = $false
            resetBase         = $false
        }
        SettingsDescriptions = [ordered]@{
            verifySystemFiles = "Verify protected Windows system files via System File Checker (sfc /verifyonly)"
            resetBase         = "Purge all superseded update backups (/ResetBase - prevents uninstalling old updates)"
        }
    }
}

Write-Host "`n--- [freewinly-clean-winsxs] Windows Component Store Cleanup (DISM) [$Action] ---" -ForegroundColor Cyan

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($Action -eq 'Check') {
    if (-not $isAdmin) {
        Write-Host "  [-] Running in unelevated mode. Note: DISM /CheckHealth and /StartComponentCleanup require Administrator privileges." -ForegroundColor Yellow
        Write-Host "`n  [+] Action Plan for '-Action Run' (as Administrator):" -ForegroundColor White
        Write-Host "      - Executes 'dism.exe /Online /Cleanup-Image /StartComponentCleanup' to purge superseded Windows Update components." -ForegroundColor Gray
        if ($resetBase) {
            Write-Host "      - Includes '/ResetBase' to permanently purge older update versions (reclaims maximum disk space)." -ForegroundColor Yellow
        }
        if ($verifySystemFiles) {
            Write-Host "      - Executes 'sfc.exe /verifyonly' to verify protected system file integrity." -ForegroundColor Gray
        }
        return
    }

    Write-Host "Checking Windows Component Store health via DISM..." -ForegroundColor Gray
    try {
        $checkHealthOut = & dism.exe /Online /Cleanup-Image /CheckHealth 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [+] Component Store Health: Healthy (no corruption detected; exit code 0)." -ForegroundColor Green
        } else {
            Write-Host "  [-] Component Store Health Status (exit code $LASTEXITCODE):" -ForegroundColor Yellow
            $checkHealthOut.Trim().Split("`n") | ForEach-Object {
                $line = $_.Trim()
                if ($line) { Write-Host "      $line" -ForegroundColor Gray }
            }
        }
    } catch {
        Write-Host "  [-] DISM CheckHealth failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    Write-Host "`n  [+] Component Store Cleanup Preview:" -ForegroundColor White
    Write-Host "      - Will execute 'dism.exe /Online /Cleanup-Image /StartComponentCleanup' to safely purge superseded payloads." -ForegroundColor Gray
    if ($resetBase) {
        Write-Host "      - With 'resetBase' enabled: will append '/ResetBase' to delete historical baselines (saves extra GBs)." -ForegroundColor Yellow
    }
    if ($verifySystemFiles) {
        Write-Host "      - With 'verifySystemFiles' enabled: will execute 'sfc.exe /verifyonly' for file integrity validation." -ForegroundColor Gray
    }
    return
}

# Action -eq 'Run'
if (-not $isAdmin) {
    Write-Host "  [-] Error: Windows Component Store cleanup requires Administrator privileges. Skipping." -ForegroundColor Red
    if ($LogFile) { Add-Content -Path $LogFile -Value "DISM cleanup skipped: Administrator privileges required." -Encoding UTF8 }
    return
}

$dismArgs = @('/Online', '/Cleanup-Image', '/StartComponentCleanup')
if ($resetBase) {
    $dismArgs += '/ResetBase'
}

Write-Host "Running DISM Component Store cleanup: dism.exe $($dismArgs -join ' ')..." -ForegroundColor Cyan
Write-Host "Note: DISM execution typically takes 1 to 5 minutes. Please wait..." -ForegroundColor Gray

try {
    $dismProcess = Start-Process -FilePath "dism.exe" -ArgumentList $dismArgs -NoNewWindow -Wait -PassThru
    if ($dismProcess.ExitCode -eq 0) {
        Write-Host "  [+] DISM Component Store cleanup completed successfully." -ForegroundColor Green
        if ($LogFile) { Add-Content -Path $LogFile -Value "DISM Component Store cleanup completed successfully (ResetBase: $resetBase)" -Encoding UTF8 }
    } else {
        Write-Host "  [-] DISM completed with exit code $($dismProcess.ExitCode)." -ForegroundColor Yellow
        if ($LogFile) { Add-Content -Path $LogFile -Value "DISM finished with exit code $($dismProcess.ExitCode)" -Encoding UTF8 }
    }
} catch {
    Write-Host "  [-] Failed to start DISM: $($_.Exception.Message)" -ForegroundColor Red
    if ($LogFile) { Add-Content -Path $LogFile -Value "DISM failed: $($_.Exception.Message)" -Encoding UTF8 }
}

if ($verifySystemFiles) {
    Write-Host "`nRunning System File Checker verification (sfc.exe /verifyonly)..." -ForegroundColor Cyan
    try {
        $sfcProcess = Start-Process -FilePath "sfc.exe" -ArgumentList "/verifyonly" -NoNewWindow -Wait -PassThru
        if ($sfcProcess.ExitCode -eq 0) {
            Write-Host "  [+] System file verification completed. No integrity violations found." -ForegroundColor Green
            if ($LogFile) { Add-Content -Path $LogFile -Value "SFC verification passed: No integrity violations." -Encoding UTF8 }
        } else {
            Write-Host "  [-] System file verification finished with code $($sfcProcess.ExitCode). Check CBS.log if issues occurred." -ForegroundColor Yellow
            if ($LogFile) { Add-Content -Path $LogFile -Value "SFC verification finished with exit code $($sfcProcess.ExitCode)" -Encoding UTF8 }
        }
    } catch {
        Write-Host "  [-] Failed to start SFC: $($_.Exception.Message)" -ForegroundColor Red
        if ($LogFile) { Add-Content -Path $LogFile -Value "SFC failed: $($_.Exception.Message)" -Encoding UTF8 }
    }
}
