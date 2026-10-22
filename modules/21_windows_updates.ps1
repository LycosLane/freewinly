#Requires -Version 5.1
<#
.SYNOPSIS
    FreeWinly Windows OS & Security Updates Module.
.DESCRIPTION
    Scans, previews, downloads, and installs pending Windows OS Updates and Microsoft Defender definitions via native COM API.
.PARAMETER Action
    'Info'  - Returns module metadata object (Name, Description, Default, RequiresAdmin).
    'Check' - Searches for pending updates and displays titles/sizes without downloading or installing.
    'Run'   - Searches, downloads, and installs pending updates.
.PARAMETER Config
    Optional PSCustomObject loaded from config.json.
.PARAMETER LogFile
    Optional path to the execution log file.
.PARAMETER Options
    Optional hashtable of module-specific options.
.EXAMPLE
    .\modules\21_windows_updates.ps1 -Action Info
.EXAMPLE
    .\modules\21_windows_updates.ps1 -Action Check
.EXAMPLE
    .\modules\21_windows_updates.ps1 -Action Run
#>
[CmdletBinding()]
param(
    [ValidateSet('Info', 'Check', 'Run')]
    [string]$Action = 'Run',

    [PSCustomObject]$Config = $null,
    [string]$LogFile = $null,
    [hashtable]$Options = @{}
)

if ($Action -eq 'Info') {
    return [PSCustomObject]@{
        Name          = "Windows OS & Security Updates"
        Description   = "Scans, downloads, and installs pending Windows Updates and Microsoft Defender definitions via native COM API"
        Default       = $false
        RequiresAdmin = $true
        Options       = @{}
    }
}

Write-Host "`n--- [Module 21] Windows OS & Security Updates [$Action] ---" -ForegroundColor Cyan

try {
    $Session = New-Object -ComObject Microsoft.Update.Session
    $Searcher = $Session.CreateUpdateSearcher()
    Write-Host "Searching for pending Windows updates..." -ForegroundColor Gray
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
        $cbsReboot = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
        $wuReboot  = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
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
