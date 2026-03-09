# Playwright Windows Proxy

A single portable `.exe` that launches a Playwright WebSocket server using your installed Chrome. No Node.js installation required.

Connect from any Playwright client (Node.js, Python, Go, .NET) using the full Playwright protocol — with `page.route()`, `expect()`, and everything else that `connectOverCDP` can't do.

## Quick Start

1. Download `playwright-proxy.exe` from [Releases](https://github.com/n0isy/playwright-windows-proxy/releases)
2. Run it:
   ```
   playwright-proxy.exe
   ```
3. Connect from your client:
   ```js
   const { chromium } = require('playwright');
   const browser = await chromium.connect('ws://127.0.0.1:9223');
   ```

The WebSocket endpoint (with auth token) is printed to the console on startup.

## Configuration

| Environment Variable | Default       | Description          |
|----------------------|---------------|----------------------|
| `PW_PORT`            | `9223`        | Server port          |
| `PW_HOST`            | `127.0.0.1`   | Bind address         |
| `PW_HEADLESS`        | `0`           | Set to `1` for headless mode |

Example:

```
set PW_PORT=9333
set PW_HOST=0.0.0.0
playwright-proxy.exe
```

## How It Works

The executable is a self-extracting archive (built with [wrappe](https://github.com/Systemcluster/wrappe)) containing:

- **Node.js runtime** — bundled from the official Playwright driver package
- **playwright-core** — the Playwright driver library
- **pw-server.js** — a small script that calls `chromium.launchServer()`

On launch it unpacks to a temp directory, starts the Playwright server with `channel: 'chrome'` (your system Chrome), and exposes a WebSocket endpoint.

```
┌─────────────────────────────┐
│   playwright-proxy.exe      │
│  ┌────────────────────────┐ │
│  │ node.exe               │ │    ┌──────────────────┐
│  │ playwright-core driver │ │───▶│ System Chrome     │
│  │ pw-server.js           │ │    │ (channel: chrome) │
│  └────────────────────────┘ │    └──────────────────┘
└──────────────┬──────────────┘
               │ ws://127.0.0.1:9223
               ▼
        Playwright Client
```

## Why Not `connectOverCDP`?

| Feature             | `connectOverCDP` | This proxy (`connect`) |
|---------------------|------------------|------------------------|
| Protocol            | CDP (limited)    | Full Playwright        |
| `page.route()`      | Partial          | Full support           |
| `expect()` matchers | Partial          | Full support           |
| Browser requirement | Any Chrome       | System Chrome          |

## Building from Source

Requirements: Windows, curl (included in Windows 10+).

```bat
.bin\build.bat
```

This will:
1. Download the Playwright driver (node.exe + playwright-core) from the official CDN
2. Download [wrappe](https://github.com/Systemcluster/wrappe) packer
3. Bundle everything into a single `playwright-proxy.exe`

### Changing Playwright Version

Edit `PW_VERSION` in `.bin\build.bat`:

```bat
set "PW_VERSION=1.58.2"
```

## Client Examples

### Node.js

```js
const { chromium } = require('playwright');

const browser = await chromium.connect('ws://127.0.0.1:9223');
const page = await browser.newContext().then(c => c.newPage());
await page.goto('https://example.com');
console.log(await page.title());
await browser.close();
```

### Python

```python
from playwright.sync_api import sync_playwright

with sync_playwright() as p:
    browser = p.chromium.connect("ws://127.0.0.1:9223")
    page = browser.new_context().new_page()
    page.goto("https://example.com")
    print(page.title())
    browser.close()
```

## Version Compatibility

The connecting Playwright client **must match** the server's playwright-core version (currently **1.58.2**). Mismatched versions will be rejected at connection time.

## License

MIT
