#Requires -Version 5.1
<#
.SYNOPSIS
    FreeWinly Opt-In Self-Updater.
.DESCRIPTION
    Explicitly checks GitHub Releases for a newer version of FreeWinly and updates
    the local installation cleanly according to its install type (Standalone ZIP,
    Scoop package, or Git clone). Never runs silently in the background.

    Preserves user configuration (config.json, config.*.json backups), logs/,
    and any custom modules when updating Standalone ZIP installations, then
    restarts FreeWinly in a fresh PowerShell session.
.PARAMETER Action
    'Interactive' - Checks for updates and prompts before updating and restarting.
    'Check'       - Checks for updates and prints status without modifying files.
    'Update'      - Checks for updates and applies them (prompts unless -Force).
.PARAMETER Force
    Skips the interactive confirmation prompt when an update is available.
.PARAMETER NoRestart
    Does not launch a new FreeWinly process directly; instead exits with code 42
    after a successful update so a parent TUI caller can handle the restart.
.EXAMPLE
    .\core\freewinly-self-update.ps1 -Action Check
.EXAMPLE
    .\core\freewinly-self-update.ps1 -Action Update -Force
#>
[CmdletBinding()]
param(
    [ValidateSet('Interactive', 'Check', 'Update')]
    [string]$Action = 'Interactive',

    [switch]$Force = $false,
    [switch]$NoRestart = $false
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$projectRoot  = Split-Path -Parent $PSScriptRoot
$runnerScript = Join-Path $projectRoot "freewinly.ps1"

. (Join-Path $PSScriptRoot "freewinly-version.ps1")

function Get-FreeWinlyInstallType {
    if ($projectRoot -match '\\scoop\\apps\\freewinly\\' -or (Test-Path -LiteralPath (Join-Path $projectRoot 'manifest.json'))) {
        return 'Scoop'
    }
    if (Test-Path -LiteralPath (Join-Path $projectRoot '.git')) {
        return 'Git'
    }
    return 'Standalone'
}

function Get-LatestFreeWinlyRelease {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $apiUrl = "https://api.github.com/repos/LycosLane/freewinly/releases/latest"
    $headers = @{
        "User-Agent" = "FreeWinly/$FreeWinlyVersion"
        "Accept"     = "application/vnd.github+json"
    }

    $rel = Invoke-RestMethod -Uri $apiUrl -Headers $headers -TimeoutSec 15 -ErrorAction Stop
    if (-not $rel -or -not $rel.tag_name -or ($rel.tag_name -notmatch '^v(\d+\.\d+\.\d+)$')) {
        throw "Unexpected release metadata returned by GitHub API."
    }

    $latestVer = $matches[1]
    $hasSkill  = Test-Path -LiteralPath (Join-Path $projectRoot 'SKILL.md')
    $zipName   = if ($hasSkill) { 'FreeWinly4LLM.zip' } else { 'FreeWinly.zip' }

    $zipAsset  = $rel.assets | Where-Object { $_.name -eq $zipName } | Select-Object -First 1
    $sumsAsset = $rel.assets | Where-Object { $_.name -eq 'SHA256SUMS.txt' } | Select-Object -First 1

    $zipUrl = if ($zipAsset) { [string]$zipAsset.browser_download_url } else { $null }
    if ($zipUrl -and $zipUrl -notmatch '^https://github\.com/LycosLane/freewinly/releases/download/') {
        throw "Rejected untrusted download URL: $zipUrl"
    }

    $sumsUrl = if ($sumsAsset) { [string]$sumsAsset.browser_download_url } else { $null }
    if ($sumsUrl -and $sumsUrl -notmatch '^https://github\.com/LycosLane/freewinly/releases/download/') {
        $sumsUrl = $null
    }

    $currentSemVer = if ($FreeWinlyVersion -match '^(\d+\.\d+\.\d+)') { [version]$matches[1] } else { [version]'0.0.0' }
    $updateAvail = ([version]$latestVer -gt $currentSemVer)

    return [PSCustomObject]@{
        LatestVersion   = $latestVer
        TagName         = [string]$rel.tag_name
        HtmlUrl         = [string]$rel.html_url
        Body            = [string]$rel.body
        ZipAssetName    = $zipName
        ZipUrl          = $zipUrl
        ChecksumsUrl    = $sumsUrl
        UpdateAvailable = $updateAvail
    }
}

function Update-StandaloneInstall {
    param([PSCustomObject]$ReleaseInfo)

    if (-not $ReleaseInfo.ZipUrl) {
        throw "Release $($ReleaseInfo.TagName) does not contain asset '$($ReleaseInfo.ZipAssetName)'."
    }

    $tempDir = Join-Path $env:TEMP ("freewinly-update-" + [System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        $zipPath = Join-Path $tempDir $ReleaseInfo.ZipAssetName
        Write-Host "Downloading $($ReleaseInfo.ZipAssetName) ($($ReleaseInfo.TagName))..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $ReleaseInfo.ZipUrl -OutFile $zipPath -TimeoutSec 60 -UseBasicParsing -ErrorAction Stop

        if (-not $ReleaseInfo.ChecksumsUrl) {
            throw "Release $($ReleaseInfo.TagName) is missing SHA256SUMS.txt; aborting unverified download."
        }
        $sumsPath = Join-Path $tempDir "SHA256SUMS.txt"
        Invoke-WebRequest -Uri $ReleaseInfo.ChecksumsUrl -OutFile $sumsPath -TimeoutSec 20 -UseBasicParsing -ErrorAction Stop
        $sumsLines = Get-Content -LiteralPath $sumsPath -Encoding UTF8 -ErrorAction Stop
        $expectedHash = $null
        foreach ($line in $sumsLines) {
            if ($line -match '^\s*([A-Fa-f0-9]{64})\s+\*?(.+?)\s*$') {
                if ($matches[2].Trim() -eq $ReleaseInfo.ZipAssetName) {
                    $expectedHash = $matches[1].ToUpperInvariant()
                    break
                }
            }
        }
        if (-not $expectedHash) {
            throw "No SHA-256 checksum entry found for $($ReleaseInfo.ZipAssetName) in SHA256SUMS.txt."
        }
        $actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
        if ($actualHash -ne $expectedHash) {
            throw "Checksum verification failed for $($ReleaseInfo.ZipAssetName) (expected $expectedHash, got $actualHash)."
        }
        Write-Host "[OK] SHA-256 checksum verified." -ForegroundColor Green

        $stageDir = Join-Path $tempDir "stage"
        Expand-Archive -LiteralPath $zipPath -DestinationPath $stageDir -Force -ErrorAction Stop

        if (-not (Test-Path -LiteralPath (Join-Path $stageDir "freewinly.ps1")) -or -not (Test-Path -LiteralPath (Join-Path $stageDir "VERSION"))) {
            throw "Downloaded archive is missing core FreeWinly files."
        }

        Write-Host "Applying update while preserving config.json, backups, and logs..." -ForegroundColor Cyan
        $preservedTopDirs  = @('logs')
        $preservedTopFiles = @('config.json', 'config.previous.json', 'config.last-good.json')

        foreach ($item in (Get-ChildItem -LiteralPath $stageDir -Force)) {
            if ($item.PSIsContainer) {
                if ($preservedTopDirs -contains $item.Name.ToLowerInvariant()) { continue }
                $destSub = Join-Path $projectRoot $item.Name
                if (-not (Test-Path -LiteralPath $destSub)) {
                    New-Item -ItemType Directory -Path $destSub -Force | Out-Null
                }
                Copy-Item -Path (Join-Path $item.FullName '*') -Destination $destSub -Recurse -Force -ErrorAction Stop
            } else {
                if ($preservedTopFiles -contains $item.Name.ToLowerInvariant()) { continue }
                Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $projectRoot $item.Name) -Force -ErrorAction Stop
            }
        }
    } finally {
        if (Test-Path -LiteralPath $tempDir) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "          FreeWinly v$FreeWinlyVersion - Update Checker               " -ForegroundColor White
Write-Host "============================================================`n" -ForegroundColor Cyan

$installType = Get-FreeWinlyInstallType
Write-Host "Installed Version: v$FreeWinlyVersion" -ForegroundColor White
Write-Host "Install Type:      $installType" -ForegroundColor Gray
Write-Host "Checking GitHub Releases (opt-in)..." -ForegroundColor Gray

try {
    $release = Get-LatestFreeWinlyRelease
} catch {
    Write-Host "`n[Error] Could not check for updates: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "Latest Version:    v$($release.LatestVersion)" -ForegroundColor White

if (-not $release.UpdateAvailable) {
    Write-Host "`n[OK] FreeWinly v$FreeWinlyVersion is already up to date." -ForegroundColor Green
    exit 0
}

Write-Host "`n[Update Available] v$FreeWinlyVersion -> v$($release.LatestVersion)" -ForegroundColor Yellow
Write-Host "Release Page: $($release.HtmlUrl)" -ForegroundColor Gray

if ($Action -eq 'Check') {
    Write-Host "`nRun '.\core\freewinly-self-update.ps1 -Action Update' to install this update." -ForegroundColor Cyan
    exit 0
}

if (-not $Force) {
    $confirm = Read-Host "`nUpdate FreeWinly from v$FreeWinlyVersion to v$($release.LatestVersion) now? (y/N)"
    if ($confirm -notmatch '^[Yy]$') {
        Write-Host "`nUpdate cancelled. No files were changed." -ForegroundColor Yellow
        exit 0
    }
}

try {
    switch ($installType) {
        'Scoop' {
            if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
                throw "Scoop CLI was not found on PATH."
            }
            Write-Host "`nUpdating via Scoop ('scoop update freewinly')..." -ForegroundColor Cyan
            & scoop update freewinly
            if ($LASTEXITCODE -ne 0) {
                throw "scoop update freewinly exited with code $LASTEXITCODE."
            }
        }
        'Git' {
            if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
                throw "Git CLI was not found on PATH."
            }
            $dirty = git -C $projectRoot status --porcelain
            if ($dirty) {
                throw "Local Git working tree has uncommitted changes. Commit or stash them before updating."
            }
            Write-Host "`nUpdating Git repository ('git pull --ff-only')..." -ForegroundColor Cyan
            git -C $projectRoot pull --ff-only
            if ($LASTEXITCODE -ne 0) {
                throw "git pull --ff-only exited with code $LASTEXITCODE."
            }
        }
        'Standalone' {
            Update-StandaloneInstall -ReleaseInfo $release
        }
    }
} catch {
    Write-Host "`n[Error] Update failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "`n[OK] FreeWinly updated to v$($release.LatestVersion)!" -ForegroundColor Green

if ($NoRestart) {
    exit 42
}

Write-Host "Restarting FreeWinly..." -ForegroundColor Cyan
$psHost = try { (Get-Process -Id $PID).Path } catch { $null }
if (-not $psHost -or -not (Test-Path $psHost)) { $psHost = 'powershell.exe' }
& $psHost -NoProfile -ExecutionPolicy Bypass -File $runnerScript
exit $LASTEXITCODE
