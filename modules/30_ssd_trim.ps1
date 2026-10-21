# Name: SSD TRIM Optimization
# Default: True
# Description: Sends native NVMe/SATA TRIM hints to the operating system SSD volume (never defrags)

param(
    [PSCustomObject]$Config,
    [string]$LogFile
)

Write-Host "`n--- [Module 30] SSD TRIM Optimization ---" -ForegroundColor Cyan

try {
    $out = Optimize-Volume -DriveLetter C -ReTrim -Verbose 4>&1
    $out | Out-Host
    if ($LogFile) { $out | Add-Content -Path $LogFile -Encoding UTF8 }
    Write-Host "SSD TRIM completed successfully." -ForegroundColor Green
    if ($LogFile) { Add-Content -Path $LogFile -Value "SSD TRIM completed successfully." -Encoding UTF8 }
} catch {
    Write-Host "Error during SSD TRIM: $($_.Exception.Message)" -ForegroundColor Yellow
    if ($LogFile) { Add-Content -Path $LogFile -Value "Error during SSD TRIM: $($_.Exception.Message)" -Encoding UTF8 }
}
