#Requires -Version 5.1
<#
.SYNOPSIS
    FreeWinly Configuration I/O, Atomic Writer & Backup Manager.
.DESCRIPTION
    Provides atomic JSON file writes, rolling backups (config.previous.json),
    verified last-good state preservation (config.last-good.json), and safe
    recovery mechanisms for corrupted configuration files.
#>

function Get-ConfigFileHash {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        try {
            return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
        } catch { }
    }
    return $null
}

function Save-AtomicConfigFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [object]$Config,

        [int]$Depth = 6
    )

    $fullPath = if (Test-Path -LiteralPath $Path) {
        (Resolve-Path -LiteralPath $Path).Path
    } else {
        [System.IO.Path]::GetFullPath($Path)
    }

    $dir = Split-Path -Parent $fullPath
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $jsonContent = if ($Config -is [string]) {
        $Config
    } else {
        $Config | ConvertTo-Json -Depth $Depth
    }

    # Normalize trailing newline
    if (-not $jsonContent.EndsWith("`r`n") -and -not $jsonContent.EndsWith("`n")) {
        $jsonContent += "`r`n"
    }

    $targetExists = Test-Path -LiteralPath $fullPath
    $prevPath = Join-Path $dir "config.previous.json"

    if ($targetExists) {
        # Check if content actually changed before backing up
        $existingContent = Get-Content -LiteralPath $fullPath -Raw -ErrorAction SilentlyContinue
        if ($existingContent -ne $jsonContent) {
            # Update single rolling copy of config.previous.json
            try {
                Copy-Item -LiteralPath $fullPath -Destination $prevPath -Force -ErrorAction Stop
            } catch {
                Write-Warning "Could not update config.previous.json: $($_.Exception.Message)"
            }
        }
    }

    # Write new content to temporary file in the same directory
    $tmpFile = Join-Path $dir ([System.IO.Path]::GetRandomFileName() + ".tmp")
    try {
        [System.IO.File]::WriteAllText($tmpFile, $jsonContent, [System.Text.Encoding]::UTF8)

        if ($targetExists) {
            try {
                [System.IO.File]::Replace($tmpFile, $fullPath, $null)
            } catch {
                # Fallback to Move-Item -Force if Replace fails (e.g. filesystem quirk)
                Move-Item -LiteralPath $tmpFile -Destination $fullPath -Force -ErrorAction Stop
            }
        } else {
            Move-Item -LiteralPath $tmpFile -Destination $fullPath -Force -ErrorAction Stop
        }
    } catch {
        if (Test-Path -LiteralPath $tmpFile) {
            Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
        }
        throw "Failed to atomically save configuration to '$fullPath': $($_.Exception.Message)"
    }
}

function Update-LastGoodConfigFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) { return }

    $fullPath = (Resolve-Path -LiteralPath $Path).Path
    $dir = Split-Path -Parent $fullPath
    $lastGoodPath = Join-Path $dir "config.last-good.json"

    $currentHash = Get-ConfigFileHash -Path $fullPath
    if (-not $currentHash) { return }

    $lastGoodHash = Get-ConfigFileHash -Path $lastGoodPath

    if ($currentHash -ne $lastGoodHash) {
        try {
            Copy-Item -LiteralPath $fullPath -Destination $lastGoodPath -Force -ErrorAction Stop
        } catch {
            Write-Warning "Failed to update config.last-good.json: $($_.Exception.Message)"
        }
    }
}

function Get-SafeConfigFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [bool]$IsInteractive = $false,

        [object]$DefaultConfig = $null
    )

    $fullPath = if (Test-Path -LiteralPath $Path) {
        (Resolve-Path -LiteralPath $Path).Path
    } else {
        [System.IO.Path]::GetFullPath($Path)
    }

    $dir = Split-Path -Parent $fullPath
    $lastGoodPath = Join-Path $dir "config.last-good.json"
    $prevPath     = Join-Path $dir "config.previous.json"

    if (Test-Path -LiteralPath $fullPath) {
        $raw = Get-Content -LiteralPath $fullPath -Raw -ErrorAction SilentlyContinue
        if ($raw) {
            try {
                $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
                return [PSCustomObject]@{
                    Config       = $parsed
                    IsCorrupted  = $false
                    ParseError   = $null
                    RestoredFrom = $null
                }
            } catch {
                $errMsg = $_.Exception.Message
                # Attempt to extract line number or offset if present
                $lineHint = ""
                if ($errMsg -match 'line (\d+)') {
                    $lineHint = " (near line $($matches[1]))"
                } elseif ($errMsg -match 'offset (\d+)') {
                    $lineHint = " (near offset $($matches[1]))"
                }

                # Find available backup
                $backupToUse = $null
                $backupName  = $null
                if (Test-Path -LiteralPath $lastGoodPath) {
                    $backupToUse = $lastGoodPath
                    $backupName  = "config.last-good.json"
                } elseif (Test-Path -LiteralPath $prevPath) {
                    $backupToUse = $prevPath
                    $backupName  = "config.previous.json"
                }

                if ($IsInteractive) {
                    Write-Host ""
                    Write-Host "============================================================" -ForegroundColor Red
                    Write-Host " [Config Error] Corrupted Configuration File Detected" -ForegroundColor Yellow
                    Write-Host "============================================================" -ForegroundColor Red
                    Write-Host "File: $fullPath" -ForegroundColor White
                    Write-Host "Error: $errMsg$lineHint" -ForegroundColor Red
                    Write-Host ""
                    Write-Host "Safety Guarantee: The broken configuration file has NOT been" -ForegroundColor Gray
                    Write-Host "overwritten or deleted." -ForegroundColor Gray
                    Write-Host ""

                    if ($backupToUse) {
                        Write-Host "Available backup found: $backupName" -ForegroundColor Green
                        $choice = Read-Host "Restore from '$backupName' [R] or Quit without changes [Q]? (R/q)"
                        if ($choice -match '^[Rr]$' -or [string]::IsNullOrWhiteSpace($choice)) {
                            try {
                                $backupRaw = Get-Content -LiteralPath $backupToUse -Raw -ErrorAction Stop
                                $backupParsed = $backupRaw | ConvertFrom-Json -ErrorAction Stop
                                Save-AtomicConfigFile -Path $fullPath -Config $backupRaw
                                Write-Host "`nSuccessfully restored configuration from $backupName!" -ForegroundColor Green
                                Start-Sleep -Milliseconds 900
                                return [PSCustomObject]@{
                                    Config       = $backupParsed
                                    IsCorrupted  = $false
                                    ParseError   = $null
                                    RestoredFrom = $backupName
                                }
                            } catch {
                                Write-Host "Failed to restore backup '$backupName': $($_.Exception.Message)" -ForegroundColor Red
                            }
                        }
                    } else {
                        Write-Host "No backup configuration file (config.last-good.json / config.previous.json) was found." -ForegroundColor Yellow
                        Read-Host "Press Enter to exit FreeWinly safely"
                    }
                    exit 1
                } else {
                    # Headless / Scheduled / -Run / -Check
                    Write-Warning "[Config Warning] Failed to parse '$fullPath'$($lineHint): $errMsg. Corrupted file left untouched."
                    if ($backupToUse) {
                        try {
                            $backupParsed = (Get-Content -LiteralPath $backupToUse -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
                            Write-Warning "[Config Warning] Using $backupName in memory for this session."
                            return [PSCustomObject]@{
                                Config       = $backupParsed
                                IsCorrupted  = $true
                                ParseError   = $errMsg
                                RestoredFrom = "Memory:$backupName"
                            }
                        } catch { }
                    }
                    Write-Warning "[Config Warning] Using safe in-memory defaults for this session."
                    return [PSCustomObject]@{
                        Config       = $DefaultConfig
                        IsCorrupted  = $true
                        ParseError   = $errMsg
                        RestoredFrom = "Memory:Defaults"
                    }
                }
            }
        }
    }

    return [PSCustomObject]@{
        Config       = $DefaultConfig
        IsCorrupted  = $false
        ParseError   = $null
        RestoredFrom = $null
    }
}
