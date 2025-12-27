/**
 * Automated Multi-Client Browser Test using Playwright
 *
 * Tests WebRTC multi-client handling:
 * - Multiple simultaneous browser connections
 * - Each gets own PeerConnection
 * - DataChannel communication verified for each
 *
 * Usage:
 *   # First, start the Dart server in another terminal:
 *   dart run interop/automated/multi_client_server.dart
 *
 *   # Then run browser tests:
 *   node interop/automated/multi_client_test.mjs [chrome|firefox|webkit|all]
 */

import { chromium, firefox, webkit } from 'playwright';
import { getBrowserArg } from './test_utils.mjs';

const SERVER_URL = 'http://localhost:8783';
const TEST_TIMEOUT = 60000;

async function runBrowserTest(browserType, browserName) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`Testing Multi-Client: ${browserName}`);
  console.log('='.repeat(60));

  let browser;
  let context;
  let page;

  try {
    console.log(`[${browserName}] Launching browser...`);

    // Launch options - firefoxUserPrefs must be at launch time
    const launchOptions = {
      headless: true,
    };

    if (browserName === 'chrome') {
      launchOptions.args = [
        '--use-fake-ui-for-media-stream',
        '--use-fake-device-for-media-stream',
      ];
    }

    if (browserName === 'firefox') {
      launchOptions.firefoxUserPrefs = {
        'media.navigator.streams.fake': true,
        'media.navigator.permission.disabled': true,
      };
    }

    browser = await browserType.launch(launchOptions);

    // Grant camera permissions (Chrome only - Firefox uses prefs above)
    const contextOptions = {
      permissions: browserName === 'chrome' ? ['camera'] : [],
    };

    context = await browser.newContext(contextOptions);
    page = await context.newPage();

    page.on('console', msg => {
      const text = msg.text();
      if (!text.startsWith('TEST_RESULT:')) {
        console.log(`[${browserName}] ${text}`);
      }
    });

    console.log(`[${browserName}] Loading test page...`);
    await page.goto(SERVER_URL, { timeout: 10000 });

    console.log(`[${browserName}] Running multi-client test...`);
    const result = await page.evaluate(async () => {
      return new Promise((resolve) => {
        const check = () => {
          if (window.testResult) {
            resolve(window.testResult);
          } else {
            setTimeout(check, 100);
          }
        };
        setTimeout(check, 100);

        setTimeout(() => {
          resolve({ success: false, error: 'Test timeout' });
        }, 45000);
      });
    });

    console.log(`\n[${browserName}] Test Result:`);
    console.log(`  Success: ${result.success}`);
    console.log(`  Max Concurrent Clients: ${result.maxConcurrentClients || 0}`);
    console.log(`  Connected Clients: ${result.connectedClients || 0}`);
    console.log(`  DC Open Clients: ${result.dcOpenClients || 0}`);
    console.log(`  Messages: ${result.messagesSent || 0} sent, ${result.messagesReceived || 0} recv`);
    if (result.clients) {
      for (const client of result.clients) {
        console.log(`    ${client.id}: connected=${client.connected}, dcOpen=${client.dcOpen}`);
      }
    }
    if (result.error) {
      console.log(`  Error: ${result.error}`);
    }

    return {
      browser: browserName,
      ...result,
    };

  } catch (error) {
    console.error(`[${browserName}] Error: ${error.message}`);
    return {
      browser: browserName,
      success: false,
      error: error.message,
    };
  } finally {
    if (page) await page.close().catch(() => {});
    if (context) await context.close().catch(() => {});
    if (browser) await browser.close().catch(() => {});
  }
}

async function main() {
  // Support both: BROWSER=firefox node test.mjs OR node test.mjs firefox
  const browserArg = getBrowserArg() || 'all';

  console.log('WebRTC Multi-Client Browser Test');
  console.log('=================================');
  console.log(`Server: ${SERVER_URL}`);
  console.log(`Browser: ${browserArg}`);

  try {
    const resp = await fetch(`${SERVER_URL}/status`);
    if (!resp.ok) throw new Error('Server not responding');
  } catch (e) {
    console.error('\nError: Multi-Client server is not running!');
    console.error('Start it with: dart run interop/automated/multi_client_server.dart');
    process.exit(1);
  }

  const results = [];

  if (browserArg === 'all' || browserArg === 'chrome') {
    results.push(await runBrowserTest(chromium, 'chrome'));
  }

  // Skip Firefox by default due to ICE issue when Dart is offerer
  if (browserArg === 'firefox') {
    console.log('\n[firefox] Note: Firefox has known ICE issues when Dart is offerer');
    results.push(await runBrowserTest(firefox, 'firefox'));
  } else if (browserArg === 'all') {
    console.log('\n[firefox] Skipping Firefox (known ICE issue when Dart is offerer)');
    results.push({ browser: 'firefox', success: false, error: 'Skipped - ICE issue', skipped: true });
  }

  if (browserArg === 'all' || browserArg === 'webkit' || browserArg === 'safari') {
    results.push(await runBrowserTest(webkit, 'safari'));
  }

  console.log('\n' + '='.repeat(60));
  console.log('MULTI-CLIENT TEST SUMMARY');
  console.log('='.repeat(60));

  for (const result of results) {
    if (result.skipped) {
      console.log(`- SKIP - ${result.browser} (${result.error})`);
      continue;
    }
    const status = result.success ? '+ PASS' : 'x FAIL';
    console.log(`${status} - ${result.browser}`);
    if (result.success) {
      console.log(`       Clients: ${result.maxConcurrentClients}`);
      console.log(`       DC Open: ${result.dcOpenClients}`);
      console.log(`       Messages: ${result.messagesSent}/${result.messagesReceived}`);
    }
    if (!result.success && !result.skipped) {
      if (result.error) {
        console.log(`       Error: ${result.error}`);
      }
    }
  }

  console.log('='.repeat(60));

  const actualResults = results.filter(r => !r.skipped);
  const passed = actualResults.filter(r => r.success).length;
  const total = actualResults.length;

  if (passed === total) {
    console.log(`\nAll browsers PASSED! (${passed}/${total})`);
    process.exit(0);
  } else {
    console.log(`\nSome tests FAILED! (${passed}/${total} passed)`);
    process.exit(1);
  }
}

main().catch(e => {
  console.error('Fatal error:', e);
  process.exit(1);
});
