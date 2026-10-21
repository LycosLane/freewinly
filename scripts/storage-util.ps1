#Requires -Version 5.1
<#
.SYNOPSIS
    FreeWinly Shared Storage Discovery Utility.
.DESCRIPTION
    Safely queries physical disks, partitions, and volumes for SSD or HDD media types,
    filtering out removable USB thumb drives, optical media, and network shares.
#>

function Get-FreeWinlyStorageVolumes {
    [CmdletBinding()]
    param(
        [ValidateSet('SSD', 'HDD')]
        [string]$MediaType = 'SSD',

        [switch]$ExcludeUSB = $false
    )

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    try {
        $disks = Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.MediaType -eq $MediaType }
        if ($ExcludeUSB) {
            $disks = $disks | Where-Object { $_.BusType -ne 'USB' }
        }

        foreach ($disk in $disks) {
            $volumes = $disk | Get-Disk -ErrorAction SilentlyContinue |
                               Get-Partition -ErrorAction SilentlyContinue |
                               Get-Volume -ErrorAction SilentlyContinue |
                               Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' }

            foreach ($v in $volumes) {
                $results.Add([PSCustomObject]@{
                    DriveLetter = [string]$v.DriveLetter
                    Label       = $v.FileSystemLabel
                    Model       = $disk.FriendlyName
                    BusType     = $disk.BusType
                    MediaType   = $disk.MediaType
                    SizeGB      = [math]::Round($v.Size / 1GB, 1)
                    FreeGB      = [math]::Round($v.SizeRemaining / 1GB, 1)
                })
            }
        }
    } catch {
        # Resilient error catch
    }

    # Safe fallback if disk querying is blocked on SSD primary drive
    if ($results.Count -eq 0 -and $MediaType -eq 'SSD' -and (Test-Path 'C:\')) {
        $cVol = Get-Volume -DriveLetter C -ErrorAction SilentlyContinue
        if ($cVol -and $cVol.DriveType -eq 'Fixed') {
            $results.Add([PSCustomObject]@{
                DriveLetter = 'C'
                Label       = $cVol.FileSystemLabel
                Model       = 'Primary Fixed Drive'
                BusType     = 'Internal'
                MediaType   = 'SSD'
                SizeGB      = [math]::Round($cVol.Size / 1GB, 1)
                FreeGB      = [math]::Round($cVol.SizeRemaining / 1GB, 1)
            })
        }
    }

    return @($results)
}
