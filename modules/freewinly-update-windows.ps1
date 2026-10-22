#Requires -Version 5.1
<#
.SYNOPSIS
    FreeWinly Windows OS & Security Updates Module.
.DESCRIPTION
    Scans, previews, downloads, and installs pending Windows OS Updates and Microsoft Defender definitions via native COM API.
.PARAMETER Action
    'Info'  - Returns module metadata object (Name, Description, Order, Default, RequiresAdmin, DefaultSettings).
    'Check' - Searches for pending updates and displays titles/sizes without downloading or installing.
    'Run'   - Searches, downloads, and installs pending updates.
.PARAMETER Settings
    Optional module settings object or hashtable.
.PARAMETER LogFile
    Optional path to the execution log file.
.EXAMPLE
    .\modules\freewinly-update-windows.ps1 -Action Info
.EXAMPLE
    .\modules\freewinly-update-windows.ps1 -Action Check
.EXAMPLE
    .\modules\freewinly-update-windows.ps1 -Action Run
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
        Name                 = "Windows OS & Security Updates"
        Description          = "Scans, downloads, and installs pending Windows Updates and Microsoft Defender definitions via native COM API"
        Order                = 21
        Default              = $false
        RequiresAdmin        = $true
        DefaultSettings      = [ordered]@{}
        SettingsDescriptions = [ordered]@{}
    }
}

Write-Host "`n--- [freewinly-update-windows] Windows OS & Security Updates [$Action] ---" -ForegroundColor Cyan

try {
    $cbsReboot = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
    $wuReboot  = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    if ($cbsReboot -or $wuReboot) {
        Write-Host "System Status: A previous update is pending restart (RebootPending: $cbsReboot | RebootRequired: $wuReboot)." -ForegroundColor Yellow
    }

    # If TrustedInstaller or TiWorker is actively running (e.g. DISM or background servicing),
    # Windows Update COM APIs will block indefinitely on the servicing mutex.
    $isServicingActive = [bool](Get-Process -Name TiWorker, TrustedInstaller -ErrorAction SilentlyContinue)
    if ($isServicingActive) {
        Write-Host "  [-] Windows Servicing (TiWorker / TrustedInstaller) is actively running." -ForegroundColor Yellow
        Write-Host "      Skipping Windows Update search to prevent lock contention." -ForegroundColor Gray
        if ($LogFile) { Add-Content -Path $LogFile -Value "Windows Update search skipped: Servicing worker actively running." -Encoding UTF8 }
        return
    }

    Write-Host "Searching for pending Windows updates..." -ForegroundColor Gray

    $Session = New-Object -ComObject Microsoft.Update.Session
    $Searcher = $Session.CreateUpdateSearcher()
    $SearchResult = $Searcher.Search("IsInstalled=0 and IsHidden=0")

    if ($SearchResult.Updates.Count -eq 0) {
        Write-Host "No pending Windows Updates found." -ForegroundColor Green
        if ($LogFile) { Add-Content -Path $LogFile -Value "No pending Windows Updates found." -Encoding UTF8 }
        return
    }

    Write-Host "Found $($SearchResult.Updates.Count) pending update(s):" -ForegroundColor Yellow
    foreach ($u in $SearchResult.Updates) {
        $sizeMB = [math]::Round($u.MaxDownloadSize / 1MB, 1)
        Write-Host "  -> $($u.Title) ($sizeMB MB)" -ForegroundColor White
    }

    if ($Action -eq 'Check') {
        Write-Host "RebootPending: $cbsReboot | RebootRequired: $wuReboot" -ForegroundColor Gray
        Write-Host "Dry run complete. No updates were downloaded or installed." -ForegroundColor Green
        return
    }

    # Run execution
    $UpdatesToDownload = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($u in $SearchResult.Updates) {
        if (-not $u.EulaAccepted) { $u.AcceptEula() }
        $UpdatesToDownload.Add($u) | Out-Null
    }

    Write-Host "Downloading $($UpdatesToDownload.Count) update(s)..." -ForegroundColor Cyan
    $Downloader = $Session.CreateUpdateDownloader()
    $Downloader.Updates = $UpdatesToDownload
    $Downloader.Download() | Out-Null

    Write-Host "Installing update(s)..." -ForegroundColor Cyan
    $Installer = $Session.CreateUpdateInstaller()
    $Installer.Updates = $UpdatesToDownload
    $InstallResult = $Installer.Install()

    Write-Host "Windows Update ResultCode: $($InstallResult.ResultCode) (RebootRequired: $($InstallResult.RebootRequired))" -ForegroundColor Green
    if ($LogFile) {
        Add-Content -Path $LogFile -Value "Windows Update ResultCode: $($InstallResult.ResultCode) | RebootRequired: $($InstallResult.RebootRequired)" -Encoding UTF8
    }
} catch {
    Write-Host "Error during Windows Update: $($_.Exception.Message)" -ForegroundColor Red
    if ($LogFile) { Add-Content -Path $LogFile -Value "Error during Windows Update: $($_.Exception.Message)" -Encoding UTF8 }
}
