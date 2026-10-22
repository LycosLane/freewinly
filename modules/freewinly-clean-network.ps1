#Requires -Version 5.1
<#
.SYNOPSIS
    Flushes network caches, tests connectivity, and optimizes Windows networking.
.DESCRIPTION
    Inspects active network adapters, verifies default gateway reachability, measures
    DNS resolution speed, flushes the Windows DNS Resolver cache, and clears stale ARP
    neighbor entries.
    
    Optionally purges NetBIOS name caches and resets the Windows Socket catalog (Winsock).
.PARAMETER Action
    'Info'  - Outputs module metadata (Name, Description, Order, Default, RequiresAdmin, DefaultSettings, SettingsDescriptions).
    'Check' - Tests connectivity, inspects adapters, and previews network cache maintenance.
    'Run'   - Flushes caches and performs requested network maintenance tasks.
.PARAMETER Settings
    Optional module settings object or hashtable.
.PARAMETER LogFile
    Optional file path to append execution statistics.
.EXAMPLE
    .\modules\freewinly-clean-network.ps1 -Action Info
.EXAMPLE
    .\modules\freewinly-clean-network.ps1 -Action Check
.EXAMPLE
    .\modules\freewinly-clean-network.ps1 -Action Run
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

$flushDns          = if ($null -ne $Settings -and $null -ne $Settings.flushDns) { [bool]$Settings.flushDns } else { $true }
$clearArpCache     = if ($null -ne $Settings -and $null -ne $Settings.clearArpCache) { [bool]$Settings.clearArpCache } else { $false }
$checkConnectivity = if ($null -ne $Settings -and $null -ne $Settings.checkConnectivity) { [bool]$Settings.checkConnectivity } else { $true }
$clearNetBios      = if ($null -ne $Settings -and $null -ne $Settings.clearNetBios) { [bool]$Settings.clearNetBios } else { $false }
$resetWinsock      = if ($null -ne $Settings -and $null -ne $Settings.resetWinsock) { [bool]$Settings.resetWinsock } else { $false }

if ($Action -eq 'Info') {
    return [PSCustomObject]@{
        Name                 = "Network Cache & Connectivity"
        Description          = "Flushes DNS/ARP caches, checks gateway & DNS latency, and optionally resets Winsock"
        Order                = 32
        Default              = $true
        RequiresAdmin        = $false
        DefaultSettings      = [ordered]@{
            flushDns          = $true
            clearArpCache     = $false
            checkConnectivity = $true
            clearNetBios      = $false
            resetWinsock      = $false
        }
        SettingsDescriptions = [ordered]@{
            flushDns          = "Flush DNS Resolver Cache (Clear-DnsClientCache / ipconfig /flushdns)"
            clearArpCache     = "Clear stale local LAN routing entries (ARP neighbor cache) [Admin]"
            checkConnectivity = "Test default gateway reachability, DNS resolution speed & active adapters"
            clearNetBios      = "Purge and reload NetBIOS name cache (nbtstat -R) [Admin]"
            resetWinsock      = "Reset Windows Socket catalog (netsh winsock reset - requires restart) [Admin]"
        }
    }
}

Write-Host "`n--- [freewinly-clean-network] Network Cache & Connectivity [$Action] ---" -ForegroundColor Cyan

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# 1. Connectivity & Diagnostic Checks (Run in both Check and Run modes)
if ($checkConnectivity) {
    Write-Host "Inspecting active network connectivity..." -ForegroundColor Gray
    
    # Active network adapters
    $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
    if ($adapters.Count -gt 0) {
        foreach ($a in $adapters) {
            $speedStr = if ($a.LinkSpeed) { " - Link: $($a.LinkSpeed)" } else { "" }
            Write-Host "  [+] Active Adapter: $($a.Name) ($($a.InterfaceDescription))$speedStr" -ForegroundColor White
        }
    } else {
        Write-Host "  [-] No active network adapters detected." -ForegroundColor Yellow
    }

    # Default Gateway Reachability
    $gatewayRoute = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Select-Object -First 1
    $gateway = if ($gatewayRoute) { $gatewayRoute.NextHop } else { $null }
    if ($gateway -and $gateway -ne '0.0.0.0') {
        $gwPing = Test-Connection -ComputerName $gateway -Count 1 -Quiet -ErrorAction SilentlyContinue
        if ($gwPing) {
            Write-Host "  [+] Default Gateway: $gateway (Reachable / Ping OK)" -ForegroundColor Green
        } else {
            Write-Host "  [-] Default Gateway: $gateway (Unreachable or ICMP echo disabled)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [-] Default Gateway: Not configured or route unavailable." -ForegroundColor Yellow
    }

    # DNS Resolution Latency
    $dnsSw = [System.Diagnostics.Stopwatch]::StartNew()
    $dnsOk = $false
    try {
        $dnsRes = Resolve-DnsName -Name 'microsoft.com' -Type A -ErrorAction Stop
        $dnsSw.Stop()
        $dnsOk = $true
    } catch {
        $dnsSw.Stop()
    }

    if ($dnsOk) {
        Write-Host "  [+] DNS Resolution: 'microsoft.com' resolved in $($dnsSw.ElapsedMilliseconds) ms" -ForegroundColor Green
    } else {
        Write-Host "  [-] DNS Resolution: Failed to resolve 'microsoft.com' ($($dnsSw.ElapsedMilliseconds) ms)" -ForegroundColor Yellow
    }
}

# 2. DNS Resolver Cache Flush
if ($flushDns) {
    if ($Action -eq 'Check') {
        Write-Host "  [+] DNS Cache: Will flush Windows DNS Resolver Cache." -ForegroundColor White
    } else {
        try {
            if (Get-Command Clear-DnsClientCache -ErrorAction SilentlyContinue) {
                Clear-DnsClientCache -ErrorAction Stop
            } else {
                ipconfig /flushdns 2>&1 | Out-Null
            }
            Write-Host "  [+] DNS Resolver Cache flushed successfully." -ForegroundColor Green
            if ($LogFile) { Add-Content -Path $LogFile -Value "Flushed DNS Resolver Cache" -Encoding UTF8 }
        } catch {
            Write-Host "  [-] Failed to flush DNS cache: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# 3. ARP / Neighbor Cache Clearing
if ($clearArpCache) {
    $staleNeighbors = @(Get-NetNeighbor -ErrorAction SilentlyContinue | Where-Object { $_.State -in @('Stale', 'Unreachable') })
    if ($Action -eq 'Check') {
        $adminNote = if (-not $isAdmin) { " [Requires Admin]" } else { "" }
        Write-Host "  [+] ARP Cache: Found $($staleNeighbors.Count) stale/unreachable neighbor entry(ies) to purge.$adminNote" -ForegroundColor White
    } else {
        if ($isAdmin) {
            $count = $staleNeighbors.Count
            if ($count -gt 0) {
                $staleNeighbors | Remove-NetNeighbor -Confirm:$false -ErrorAction SilentlyContinue
                Write-Host "  [+] Stale ARP/Neighbor cache cleared ($count entries removed)." -ForegroundColor Green
                if ($LogFile) { Add-Content -Path $LogFile -Value "Cleared $count stale ARP entries" -Encoding UTF8 }
            } else {
                Write-Host "  [+] ARP cache is clean (no stale or unreachable neighbor entries)." -ForegroundColor Green
            }
        } else {
            Write-Host "  [-] ARP Cache clear skipped (Requires Administrator privileges)." -ForegroundColor Yellow
        }
    }
}

# 4. NetBIOS Name Cache (Optional, Admin)
if ($clearNetBios) {
    if ($Action -eq 'Check') {
        Write-Host "  [+] NetBIOS Cache: Will purge and reload NetBIOS name cache (nbtstat -R) [Requires Admin]." -ForegroundColor White
    } else {
        if ($isAdmin) {
            try {
                $out = nbtstat.exe -R 2>&1
                Write-Host "  [+] NetBIOS name cache purged and reloaded." -ForegroundColor Green
                if ($LogFile) { Add-Content -Path $LogFile -Value "Purged and reloaded NetBIOS name cache" -Encoding UTF8 }
            } catch {
                Write-Host "  [-] Failed to purge NetBIOS cache: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  [-] NetBIOS purge skipped (Requires Administrator privileges)." -ForegroundColor Yellow
        }
    }
}

# 5. Winsock Catalog Reset (Optional, Admin, Restart Required)
if ($resetWinsock) {
    if ($Action -eq 'Check') {
        Write-Host "  [!] Winsock: Will reset Windows Socket catalog (netsh winsock reset - system restart required) [Requires Admin]." -ForegroundColor Yellow
    } else {
        if ($isAdmin) {
            try {
                $out = netsh.exe winsock reset 2>&1
                Write-Host "  [!] Windows Socket catalog reset successfully. A system restart is required to take effect." -ForegroundColor Yellow
                if ($LogFile) { Add-Content -Path $LogFile -Value "Reset Windows Socket catalog (system restart required)" -Encoding UTF8 }
            } catch {
                Write-Host "  [-] Failed to reset Winsock catalog: $($_.Exception.Message)" -ForegroundColor Red
            }
        } else {
            Write-Host "  [-] Winsock reset skipped (Requires Administrator privileges)." -ForegroundColor Yellow
        }
    }
}
