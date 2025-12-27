/**
 * Automated ICE Restart Browser Test using Playwright
 *
 * Tests WebRTC ICE restart functionality:
 * - Establishes initial connection with DataChannel
 * - Server triggers ICE restart (new credentials)
 * - Verifies connection maintained after restart
 * - Checks ICE credentials actually changed
 *
 * Usage:
 *   # First, start the Dart server in another terminal:
 *   dart run interop/automated/ice_restart_server.dart
 *
 *   # Then run browser tests (either syntax works):
 *   BROWSER=chrome node interop/automated/ice_restart_test.mjs
 *   node interop/automated/ice_restart_test.mjs firefox
 */

import {
  getBrowserArg,
  launchBrowser,
  closeBrowser,
  setupConsoleLogging,
  checkServer,
} from './browser_utils.mjs';

const SERVER_URL = 'http://localhost:8782';

async function runBrowserTest(browserName) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`Testing ICE Restart: ${browserName}`);
  console.log('='.repeat(60));

  const { browser, context, page } = await launchBrowser(browserName, { headless: true });
  setupConsoleLogging(page, browserName);

  try {
    console.log(`[${browserName}] Loading test page...`);
    await page.goto(SERVER_URL, { timeout: 10000 });

    console.log(`[${browserName}] Running ICE restart test...`);
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
    console.log(`  ICE Restart Triggered: ${result.iceRestartTriggered ? 'YES' : 'NO'}`);
    console.log(`  ICE Credentials Changed: ${result.iceCredentialsChanged ? 'YES' : 'NO'}`);
    console.log(`  Restart Success: ${result.restartSuccess ? 'YES' : 'NO'}`);
    console.log(`  Messages: ${result.messagesSent || 0} sent, ${result.messagesReceived || 0} recv`);
    if (result.connectionTimeMs) {
      console.log(`  Connection time: ${result.connectionTimeMs}ms`);
    }
    if (result.originalIceUfrag) {
      console.log(`  Original ice-ufrag: ${result.originalIceUfrag}`);
    }
    if (result.restartedIceUfrag) {
      console.log(`  Restarted ice-ufrag: ${result.restartedIceUfrag}`);
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

  console.log('WebRTC ICE Restart Browser Test');
  console.log('================================');
  console.log(`Server: ${SERVER_URL}`);
  console.log(`Browser: ${browserArg}`);

  await checkServer(SERVER_URL, 'dart run interop/automated/ice_restart_server.dart');

  const results = [];

  if (browserArg === 'all' || browserArg === 'chrome') {
    results.push(await runBrowserTest('chrome'));
  }

  if (browserArg === 'all' || browserArg === 'firefox') {
    results.push(await runBrowserTest('firefox'));
  }

  if (browserArg === 'all' || browserArg === 'webkit' || browserArg === 'safari') {
    results.push(await runBrowserTest('safari'));
  }

  console.log('\n' + '='.repeat(60));
  console.log('ICE RESTART TEST SUMMARY');
  console.log('='.repeat(60));

  for (const result of results) {
    if (result.skipped) {
      console.log(`- SKIP - ${result.browser} (${result.error})`);
      continue;
    }
    const status = result.success ? '\u2713 PASS' : '\u2717 FAIL';
    console.log(`${status} - ${result.browser}`);
    if (result.success) {
      console.log(`       ICE Credentials Changed: ${result.iceCredentialsChanged ? 'YES' : 'NO'}`);
      console.log(`       Restart Success: ${result.restartSuccess ? 'YES' : 'NO'}`);
      console.log(`       Messages: ${result.messagesSent || 0}/${result.messagesReceived || 0}`);
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
