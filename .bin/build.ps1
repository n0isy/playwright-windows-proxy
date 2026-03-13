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

# Shim playwright-core → reuse driver's package/ (avoid duplicating 13MB)
$PcDst = Join-Path $NodeModules "playwright-core"
New-Item $PcDst -ItemType Directory | Out-Null
Set-Content (Join-Path $PcDst "index.js") "module.exports = require('../../package');"
# Build a minimal package.json (no exports → Node uses filesystem resolution)
$PcPkgOrig = Get-Content (Join-Path (Join-Path $Dist "package") "package.json") -Raw | ConvertFrom-Json
$PcPkgShim = @{}
$PcPkgShim["name"] = $PcPkgOrig.name
$PcPkgShim["version"] = $PcPkgOrig.version
$PcPkgShim["main"] = "./index.js"
$PcPkgShim | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $PcDst "package.json")
# Create lib/ shims for subpath requires (e.g. require('playwright-core/lib/mcpBundle'))
$PcLibDst = Join-Path $PcDst "lib"
New-Item $PcLibDst -ItemType Directory | Out-Null
$PcLibSrc = Join-Path (Join-Path $Dist "package") "lib"
Get-ChildItem $PcLibSrc -Filter "*.js" | ForEach-Object {
    Set-Content (Join-Path $PcLibDst $_.Name) "module.exports = require('../../../package/lib/$($_.Name)');"
}
# Also shim lib/server/ subdirectory
$PcServerSrc = Join-Path $PcLibSrc "server"
if (Test-Path $PcServerSrc) {
    $PcServerDst = Join-Path $PcLibDst "server"
    New-Item $PcServerDst -ItemType Directory | Out-Null
    Get-ChildItem $PcServerSrc -Filter "*.js" | ForEach-Object {
        Set-Content (Join-Path $PcServerDst $_.Name) "module.exports = require('../../../../package/lib/server/$($_.Name)');"
    }
    # Also shim lib/server/registry/
    $PcRegSrc = Join-Path $PcServerSrc "registry"
    if (Test-Path $PcRegSrc) {
        $PcRegDst = Join-Path $PcServerDst "registry"
        New-Item $PcRegDst -ItemType Directory | Out-Null
        Get-ChildItem $PcRegSrc -Filter "*.js" | ForEach-Object {
            Set-Content (Join-Path $PcRegDst $_.Name) "module.exports = require('../../../../../package/lib/server/registry/$($_.Name)');"
        }
    }
}

# Copy the full playwright npm package (4MB — has MCP, reporters, etc.)
$PlSrc = Join-Path (Join-Path $TmpNpm "node_modules") "playwright"
$PlDst = Join-Path $NodeModules "playwright"
Copy-Item $PlSrc $PlDst -Recurse

# Patch playwright package.json to allow all subpath imports
$PlPkgJson = Join-Path $PlDst "package.json"
$PlPkg = Get-Content $PlPkgJson -Raw | ConvertFrom-Json
$PlPkg.exports | Add-Member -NotePropertyName "./*" -NotePropertyValue "./*" -Force
$PlPkg | ConvertTo-Json -Depth 10 | Set-Content $PlPkgJson

# Patch browserContextFactory.js: reuse existing context + don't close shared remote context
$BcfPath = Join-Path (Join-Path (Join-Path (Join-Path $PlDst "lib") "mcp") "browser") "browserContextFactory.js"
$Bcf = Get-Content $BcfPath -Raw

# Patch 1: RemoteContextFactory._doCreateContext — reuse existing context instead of newContext()
$OldCreate = @'
  async _doCreateContext(browser) {
    return browser.newContext();
  }
}
class PersistentContextFactory
'@
$NewCreate = @'
  async _doCreateContext(browser) {
    const contexts = browser.contexts();
    if (contexts.length > 0)
      return contexts[0];
    return browser.newContext();
  }
}
class PersistentContextFactory
'@
if ($Bcf.Contains($OldCreate)) {
    $Bcf = $Bcf.Replace($OldCreate, $NewCreate)
    Write-Host "      Patched: RemoteContextFactory._doCreateContext" -ForegroundColor DarkGray
} else {
    throw "Patch 1 failed: could not find RemoteContextFactory._doCreateContext target"
}

# Patch 2: BaseContextFactory._closeBrowserContext — don't close shared remote contexts
$OldClose = @'
  async _closeBrowserContext(browserContext, browser) {
    (0, import_log.testDebug)(`close browser context (${this._logName})`);
    if (browser.contexts().length === 1)
      this._browserPromise = void 0;
    await browserContext.close().catch(import_log.logUnhandledError);
    if (browser.contexts().length === 0) {
      (0, import_log.testDebug)(`close browser (${this._logName})`);
      await browser.close().catch(import_log.logUnhandledError);
    }
  }
'@
$NewClose = @'
  async _closeBrowserContext(browserContext, browser) {
    (0, import_log.testDebug)(`close browser context (${this._logName})`);
    if (this._logName === "remote") {
      this._browserPromise = void 0;
      await browser.close().catch(import_log.logUnhandledError);
      return;
    }
    if (browser.contexts().length === 1)
      this._browserPromise = void 0;
    await browserContext.close().catch(import_log.logUnhandledError);
    if (browser.contexts().length === 0) {
      (0, import_log.testDebug)(`close browser (${this._logName})`);
      await browser.close().catch(import_log.logUnhandledError);
    }
  }
'@
if ($Bcf.Contains($OldClose)) {
    $Bcf = $Bcf.Replace($OldClose, $NewClose)
    Write-Host "      Patched: BaseContextFactory._closeBrowserContext" -ForegroundColor DarkGray
} else {
    throw "Patch 2 failed: could not find BaseContextFactory._closeBrowserContext target"
}

Set-Content $BcfPath $Bcf -NoNewline

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
