const path = require('path');
const fs = require('fs');

// Use the bundled playwright-core from ./package/
const playwrightCore = require(path.join(__dirname, 'package'));

const PORT = parseInt(process.env.PW_PORT) || 9223;
const HOST = process.env.PW_HOST || '127.0.0.1';
const HEADLESS = process.env.PW_HEADLESS === '1';
const START_URL = process.env.PW_START_URL || 'about:blank';

(async () => {
  try {
    const server = await playwrightCore.chromium.launchServer({
      channel: 'chrome',
      headless: HEADLESS,
      port: PORT,
      host: HOST,
      wsPath: '/ws',
      _sharedBrowser: true,
    });

    const ws = server.wsEndpoint();
    console.log('Playwright WS endpoint:', ws);

    // Write endpoint to file so external tools can read it
    fs.writeFileSync(path.join(__dirname, 'ws-endpoint.txt'), ws);

    // Open a startup page so the browser window becomes visible
    const browser = await playwrightCore.chromium.connect(ws);
    const context = await browser.newContext();
    const page = await context.newPage();
    await page.goto(START_URL);
    console.log('Opened:', START_URL);
    console.log('Press Ctrl+C to stop.');

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
