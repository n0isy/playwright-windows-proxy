const path = require('path');

// Use the bundled playwright-core from ./package/
const playwrightCore = require(path.join(__dirname, 'package'));

const PORT = parseInt(process.env.PW_PORT) || 9223;
const HOST = process.env.PW_HOST || '127.0.0.1';
const HEADLESS = process.env.PW_HEADLESS === '1';

(async () => {
  try {
    const server = await playwrightCore.chromium.launchServer({
      channel: 'chrome',
      headless: HEADLESS,
      port: PORT,
      host: HOST,
    });

    const ws = server.wsEndpoint();
    console.log('Playwright WS endpoint:', ws);
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
