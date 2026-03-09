param(
    [string]$PwVersion = "1.58.2"
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Bin = $PSScriptRoot
$Dist = Join-Path $Bin "dist"
$Output = Join-Path $Bin "playwright-proxy.exe"
$PwPlatform = "win32_x64"
$PwCdn = "https://playwright.azureedge.net/builds/driver"
$WrappeVersion = "1.0.4"
$WrappeCdn = "https://github.com/Systemcluster/wrappe/releases/download/v$WrappeVersion"

Write-Host "[1/5] Cleaning..." -ForegroundColor Cyan
if (Test-Path $Dist) { Remove-Item $Dist -Recurse -Force }
New-Item $Dist -ItemType Directory | Out-Null

$DriverZip = Join-Path $Bin "pw-driver.zip"
Write-Host "[2/5] Downloading Playwright driver v$PwVersion..." -ForegroundColor Cyan
curl.exe -L -o $DriverZip "$PwCdn/playwright-$PwVersion-$PwPlatform.zip"
if ($LASTEXITCODE -ne 0) { throw "Failed to download Playwright driver" }

Write-Host "[3/5] Extracting driver..." -ForegroundColor Cyan
Expand-Archive -Path $DriverZip -DestinationPath $Dist -Force
Copy-Item (Join-Path $Root "pw-server.js") (Join-Path $Dist "pw-server.js")

$Wrappe = Join-Path $Bin "wrappe.exe"
Write-Host "[4/5] Downloading wrappe v$WrappeVersion..." -ForegroundColor Cyan
if (-not (Test-Path $Wrappe)) {
    curl.exe -L -o $Wrappe "$WrappeCdn/wrappe.exe"
    if ($LASTEXITCODE -ne 0) { throw "Failed to download wrappe" }
}

Write-Host "[5/5] Packing into single exe..." -ForegroundColor Cyan
& $Wrappe $Dist node.exe $Output --compression 16 --console always --current-dir unpack -- pw-server.js
if ($LASTEXITCODE -ne 0) { throw "Failed to pack executable" }

$Size = (Get-Item $Output).Length / 1MB
Write-Host "`nDone! Output: $Output ($([math]::Round($Size, 1)) MB)" -ForegroundColor Green
