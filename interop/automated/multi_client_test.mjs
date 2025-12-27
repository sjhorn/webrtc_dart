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

import {
  getBrowserArg,
  launchBrowser,
  closeBrowser,
  setupConsoleLogging,
  checkServer,
} from './browser_utils.mjs';

const SERVER_URL = 'http://localhost:8783';

async function runBrowserTest(browserName) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`Testing Multi-Client: ${browserName}`);
  console.log('='.repeat(60));

  const { browser, context, page } = await launchBrowser(browserName, { headless: true });
  setupConsoleLogging(page, browserName);

  try {
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
    await closeBrowser({ browser, context, page });
  }
}

async function main() {
  // Support both: BROWSER=firefox node test.mjs OR node test.mjs firefox
  const browserArg = getBrowserArg() || 'all';

  console.log('WebRTC Multi-Client Browser Test');
  console.log('=================================');
  console.log(`Server: ${SERVER_URL}`);
  console.log(`Browser: ${browserArg}`);

  await checkServer(SERVER_URL, 'dart run interop/automated/multi_client_server.dart');

  const results = [];

  if (browserArg === 'all' || browserArg === 'chrome') {
    results.push(await runBrowserTest('chrome'));
  }

  // Skip Firefox by default due to ICE issue when Dart is offerer
  if (browserArg === 'firefox') {
    console.log('\n[firefox] Note: Firefox has known ICE issues when Dart is offerer');
    results.push(await runBrowserTest('firefox'));
  } else if (browserArg === 'all') {
    console.log('\n[firefox] Skipping Firefox (known ICE issue when Dart is offerer)');
    results.push({ browser: 'firefox', success: false, error: 'Skipped - ICE issue', skipped: true });
  }

  if (browserArg === 'all' || browserArg === 'webkit' || browserArg === 'safari') {
    results.push(await runBrowserTest('safari'));
  }

  console.log('\n' + '='.repeat(60));
  console.log('MULTI-CLIENT TEST SUMMARY');
  console.log('='.repeat(60));

  for (const result of results) {
    if (result.skipped) {
      console.log(`- SKIP - ${result.browser} (${result.error})`);
      continue;
    }
    const status = result.success ? '\u2713 PASS' : '\u2717 FAIL';
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
