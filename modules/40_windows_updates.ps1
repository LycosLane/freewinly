# Name: Windows OS & Security Updates
# Default: False
# Description: Scans, downloads, and installs pending Windows Updates and Microsoft Defender definitions via native COM API

param(
    [PSCustomObject]$Config,
    [string]$LogFile
)

Write-Host "`n--- [Module 40] Windows OS & Security Updates ---" -ForegroundColor Cyan

try {
    $Session = New-Object -ComObject Microsoft.Update.Session
    $Searcher = $Session.CreateUpdateSearcher()
    $SearchResult = $Searcher.Search("IsInstalled=0 and IsHidden=0")

    if ($SearchResult.Updates.Count -eq 0) {
        Write-Host "No pending Windows Updates found." -ForegroundColor Green
        if ($LogFile) { Add-Content -Path $LogFile -Value "No pending Windows Updates found." -Encoding UTF8 }
    } else {
        $UpdatesToDownload = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($u in $SearchResult.Updates) {
            Write-Host "Queued: $($u.Title) ($([math]::Round($u.MaxDownloadSize/1MB,1)) MB)" -ForegroundColor White
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
    }
} catch {
    Write-Host "Error during Windows Update: $($_.Exception.Message)" -ForegroundColor Red
    if ($LogFile) { Add-Content -Path $LogFile -Value "Error during Windows Update: $($_.Exception.Message)" -Encoding UTF8 }
}
