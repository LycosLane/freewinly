#Requires -Version 5.1
<#
.SYNOPSIS
    Queries and installs application updates using Microsoft WinGet.
.DESCRIPTION
    Checks installed software packages against the configured WinGet repositories.
    Supports excluding specific package identifiers, including temporary postponements
    with expiration dates configured in config.json.
.PARAMETER Action
    'Info'  - Outputs module metadata (Name, Description, Order, Default, RequiresAdmin, DefaultSettings).
    'Check' - Lists available software updates without installing them.
    'Run'   - Downloads and installs eligible updates sequentially.
.PARAMETER Settings
    Optional module settings object or hashtable (supports excluded list).
.PARAMETER LogFile
    Optional file path to append update results.
.EXAMPLE
    .\modules\freewinly-update-software.ps1 -Action Check
.EXAMPLE
    .\modules\freewinly-update-software.ps1 -Action Run
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
        Name                 = "Software Updates (Winget)"
        Description          = "Checks and installs pending Winget application updates (skipping excluded packages)"
        Order                = 20
        Default              = $true
        RequiresAdmin        = $false
        DefaultSettings      = [ordered]@{
            excluded = @()
        }
        SettingsDescriptions = [ordered]@{}
    }
}

Write-Host "`n--- [freewinly-update-software] Software Updates (Winget) [$Action] ---" -ForegroundColor Cyan

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host "Winget CLI is not available on this system. Skipping." -ForegroundColor Yellow
    if ($LogFile) { Add-Content -Path $LogFile -Value "Winget CLI not available on this system." -Encoding UTF8 }
    return
}

$today = (Get-Date).Date
$activeExcludes = [System.Collections.Generic.List[string]]::new()
$cleanExcludes  = [System.Collections.Generic.List[object]]::new()
$excludedSource = if ($Settings -and $Settings.excluded) { $Settings.excluded } else { @() }
$excludesModified = $false

foreach ($item in $excludedSource) {
    if ($item -is [string]) {
        $activeExcludes.Add($item)
        $cleanExcludes.Add($item)
    } elseif ($item.id -and $item.until) {
        $untilDate = try { [datetime]$item.until } catch { $null }
        if ($untilDate -and $today -le $untilDate) {
            $activeExcludes.Add($item.id)
            $cleanExcludes.Add($item)
            Write-Host "Exclusion active (postponed until $($item.until)): $($item.id)" -ForegroundColor Gray
        } else {
            Write-Host "Expired postponement removed: $($item.id)" -ForegroundColor Yellow
            $excludesModified = $true
        }
    }
}

if ($excludesModified -and $Settings -is [PSCustomObject]) {
    $Settings | Add-Member -NotePropertyName excluded -NotePropertyValue @($cleanExcludes) -Force
}

if ($activeExcludes.Count -gt 0) {
    Write-Host "Excluded IDs: $($activeExcludes -join ', ')" -ForegroundColor Gray
}

if ($Action -eq 'Run') {
    Write-Host "Syncing Winget package catalogs..." -ForegroundColor Gray
    & winget source update --disable-interactivity 2>&1 | Out-Null
}

$lines = & winget upgrade --include-unknown --accept-source-agreements | Out-String -Stream
$sepIdx = [array]::FindIndex($lines, [Predicate[string]]{ param($l) $l -match '^-{20,}' })

$packages = [System.Collections.Generic.List[PSCustomObject]]::new()
if ($sepIdx -ge 1) {
    $header     = $lines[$sepIdx - 1]
    $colMatches = [regex]::Matches($header, '(?<=^|\s{2,})\S+')
    if ($colMatches.Count -ge 3) {
        $idStart  = $colMatches[1].Index
        $verStart = $colMatches[2].Index
        for ($i = $sepIdx + 1; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ($line.Length -gt $verStart) {
                $name = $line.Substring(0, $idStart).Trim()
                $id   = $line.Substring($idStart, $verStart - $idStart).Trim()
                if ($id -match '^[A-Za-z0-9\._-]+\.[A-Za-z0-9\._-]+$') {
                    $packages.Add([PSCustomObject]@{ Id = $id; Name = $name })
                }
            }
        }
    }
}

$toUpdate = [System.Collections.Generic.List[PSCustomObject]]::new()
$skipped  = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($pkg in $packages) {
    $isExcluded = $false
    foreach ($ex in $activeExcludes) {
        if ($pkg.Id -eq $ex -or $pkg.Name -match [regex]::Escape($ex)) {
            $isExcluded = $true
            break
        }
    }
    if ($isExcluded) {
        $skipped.Add($pkg)
    } else {
        $toUpdate.Add($pkg)
    }
}

foreach ($s in $skipped) {
    Write-Host "SKIPPED: $($s.Name) ($($s.Id))" -ForegroundColor Yellow
    if ($LogFile) { Add-Content -Path $LogFile -Value "SKIPPED: $($s.Name) ($($s.Id))" -Encoding UTF8 }
}

if ($toUpdate.Count -eq 0) {
    Write-Host "All non-excluded packages are up to date." -ForegroundColor Green
    if ($LogFile) { Add-Content -Path $LogFile -Value "All non-excluded packages are up to date." -Encoding UTF8 }
    return
}

if ($Action -eq 'Check') {
    Write-Host "`n[Check Mode] Found $($toUpdate.Count) pending application update(s):" -ForegroundColor Yellow
    foreach ($pkg in $toUpdate) {
        Write-Host "  -> $($pkg.Name) ($($pkg.Id))" -ForegroundColor White
    }
    Write-Host "Dry run complete. No packages were modified." -ForegroundColor Green
    return
}

Write-Host "Updating $($toUpdate.Count) package(s) one by one..." -ForegroundColor Cyan
$idx = 0
foreach ($pkg in $toUpdate) {
    $idx++
    $id = $pkg.Id
    Write-Host "[$idx/$($toUpdate.Count)] Updating $($pkg.Name) ($id) ..." -ForegroundColor Cyan
    $out = & winget upgrade --id $id --exact --silent --accept-package-agreements --accept-source-agreements 2>&1
    $exitCode = $LASTEXITCODE
    $out | Out-Host
    if ($LogFile) {
        $out | Add-Content -Path $LogFile -Encoding UTF8
        Add-Content -Path $LogFile -Value "RESULT: $id => ExitCode $exitCode" -Encoding UTF8
    }
    if ($exitCode -eq 0) {
        Write-Host "RESULT: $id => SUCCESS" -ForegroundColor Green
    } else {
        Write-Host "RESULT: $id => FAILED/SKIPPED (ExitCode $exitCode)" -ForegroundColor Yellow
    }
}
