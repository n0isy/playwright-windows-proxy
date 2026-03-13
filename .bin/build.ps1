param(
    [Parameter(Mandatory)][string]$PwVersion
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Bin = $PSScriptRoot
$Dist = Join-Path $Bin "dist"
$Output = Join-Path $Bin "playwright-proxy.exe"
$PwPlatform = "win32_x64"
$WrappeVersion = "1.0.4"
$WrappeCdn = "https://github.com/Systemcluster/wrappe/releases/download/v$WrappeVersion"

# Alpha builds are under /next/, stable under /driver/
if ($PwVersion -match 'alpha') {
    $PwCdn = "https://playwright.azureedge.net/builds/driver/next"
} else {
    $PwCdn = "https://playwright.azureedge.net/builds/driver"
}

Write-Host "[1/6] Cleaning..." -ForegroundColor Cyan
if (Test-Path $Dist) { Remove-Item $Dist -Recurse -Force }
New-Item $Dist -ItemType Directory | Out-Null

$DriverZip = Join-Path $Bin "pw-driver.zip"
Write-Host "[2/6] Downloading Playwright driver v$PwVersion..." -ForegroundColor Cyan
Write-Host "      CDN: $PwCdn" -ForegroundColor DarkGray
curl.exe -L -o $DriverZip "$PwCdn/playwright-$PwVersion-$PwPlatform.zip"
if ($LASTEXITCODE -ne 0) { throw "Failed to download Playwright driver" }

Write-Host "[3/6] Extracting driver..." -ForegroundColor Cyan
Expand-Archive -Path $DriverZip -DestinationPath $Dist -Force
Copy-Item (Join-Path $Root "pw-server.js") (Join-Path $Dist "pw-server.js")

Write-Host "[4/6] Installing playwright npm package for MCP modules..." -ForegroundColor Cyan
$TmpNpm = Join-Path $Bin "npm-tmp"
if (Test-Path $TmpNpm) { Remove-Item $TmpNpm -Recurse -Force }
New-Item $TmpNpm -ItemType Directory | Out-Null
Push-Location $TmpNpm
npm init -y 2>&1 | Out-Null
npm install "playwright@$PwVersion" --ignore-scripts 2>&1
if ($LASTEXITCODE -ne 0) { throw "Failed to install playwright npm package" }
Pop-Location

# Set up node_modules so require() paths resolve:
#   require("playwright-core") → dist/package/ (the driver already has it)
#   require("playwright/...")  → playwright npm package (for MCP + helpers)
$NodeModules = Join-Path $Dist "node_modules"
New-Item $NodeModules -ItemType Directory | Out-Null

# Symlink playwright-core → the driver's package/ dir (avoid duplicating 13MB)
$PcSrc = Join-Path $Dist "package"
$PcDst = Join-Path $NodeModules "playwright-core"
Copy-Item $PcSrc $PcDst -Recurse

# Copy the full playwright npm package (4MB — has MCP, reporters, etc.)
$PlSrc = Join-Path (Join-Path $TmpNpm "node_modules") "playwright"
$PlDst = Join-Path $NodeModules "playwright"
Copy-Item $PlSrc $PlDst -Recurse

# Patch playwright package.json to allow all subpath imports
$PlPkgJson = Join-Path $PlDst "package.json"
$PlPkg = Get-Content $PlPkgJson -Raw | ConvertFrom-Json
$PlPkg.exports | Add-Member -NotePropertyName "./*" -NotePropertyValue "./*" -Force
$PlPkg | ConvertTo-Json -Depth 10 | Set-Content $PlPkgJson

# Also patch playwright-core package.json exports
$PcPkgJson = Join-Path $PcDst "package.json"
if (Test-Path $PcPkgJson) {
    $PcPkg = Get-Content $PcPkgJson -Raw | ConvertFrom-Json
    if ($PcPkg.exports) {
        $PcPkg.exports | Add-Member -NotePropertyName "./*" -NotePropertyValue "./*" -Force
        $PcPkg | ConvertTo-Json -Depth 10 | Set-Content $PcPkgJson
    }
}

# Clean up temp npm dir
Remove-Item $TmpNpm -Recurse -Force

$Wrappe = Join-Path $Bin "wrappe.exe"
Write-Host "[5/6] Downloading wrappe v$WrappeVersion..." -ForegroundColor Cyan
if (-not (Test-Path $Wrappe)) {
    curl.exe -L -o $Wrappe "$WrappeCdn/wrappe.exe"
    if ($LASTEXITCODE -ne 0) { throw "Failed to download wrappe" }
}

Write-Host "[6/6] Packing into single exe..." -ForegroundColor Cyan
& $Wrappe $Dist node.exe $Output --compression 16 --console always --current-dir unpack -- pw-server.js
if ($LASTEXITCODE -ne 0) { throw "Failed to pack executable" }

$Size = (Get-Item $Output).Length / 1MB
Write-Host "`nDone! Output: $Output ($([math]::Round($Size, 1)) MB)" -ForegroundColor Green
