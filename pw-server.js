const path = require('path');

// Bundled playwright-core (the driver's package/)
const playwrightCore = require(path.join(__dirname, 'package'));

// MCP modules — use direct paths to bypass package.json exports restrictions
const mcpDir = path.join(__dirname, 'node_modules', 'playwright', 'lib', 'mcp');
const { createConnection } = require(path.join(mcpDir, 'index'));
const { start } = require(path.join(mcpDir, 'sdk', 'server'));
const { resolveConfig } = require(path.join(mcpDir, 'browser', 'config'));
const { contextFactory } = require(path.join(mcpDir, 'browser', 'browserContextFactory'));
const { BrowserServerBackend } = require(path.join(mcpDir, 'browser', 'browserServerBackend'));

const WS_PORT = parseInt(process.env.PW_PORT) || 9223;
const MCP_PORT = parseInt(process.env.MCP_PORT) || 19223;
const HOST = process.env.PW_HOST || '127.0.0.1';
const HEADLESS = process.env.PW_HEADLESS === '1';
const START_URL = process.env.PW_START_URL || 'about:blank';

(async () => {
  try {
    // 1. Launch shared browser server
    const server = await playwrightCore.chromium.launchServer({
      channel: 'chrome',
      headless: HEADLESS,
      port: WS_PORT,
      host: HOST,
      wsPath: '/ws',
      _sharedBrowser: true,
    });

    const ws = server.wsEndpoint();
    console.log('Browser WS:', ws);

    // 2. Open a visible startup page
    const browser = await playwrightCore.chromium.connect(ws);
    const context = await browser.newContext();
    const page = await context.newPage();
    await page.goto(START_URL);

    // 3. Build MCP backend that connects to our browser
    const config = await resolveConfig({
      browser: { remoteEndpoint: ws },
      sharedBrowserContext: true,
    });
    const factory = contextFactory(config);

    const packageJSON = require(path.join(__dirname, 'node_modules', 'playwright', 'package.json'));

    const serverBackendFactory = {
      name: 'Playwright',
      nameInConfig: 'playwright',
      version: packageJSON.version || '0.0.0',
      create: () => new BrowserServerBackend(config, factory),
    };

    // 4. Start MCP HTTP server (SSE + Streamable HTTP)
    await start(serverBackendFactory, { port: MCP_PORT, host: HOST });

    console.log(`\nMCP server ready:`);
    console.log(`  SSE:        http://${HOST}:${MCP_PORT}/sse`);
    console.log(`  Streamable: http://${HOST}:${MCP_PORT}/mcp`);
    console.log('\nPress Ctrl+C to stop.');

    const shutdown = async () => {
      console.log('\nShutting down...');
      await server.close();
      process.exit();
    };

    process.on('SIGINT', shutdown);
    process.on('SIGTERM', shutdown);
  } catch (err) {
    console.error('Failed to start:', err.message);
    process.exit(1);
  }
})();
