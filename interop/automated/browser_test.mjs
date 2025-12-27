/**
 * Automated Browser Interop Test using Playwright
 *
 * Tests WebRTC DataChannel communication between:
 * - Dart (webrtc_dart) as server/offerer
 * - Browser (Chrome/Firefox/Safari) as client/answerer
 *
 * Usage:
 *   # First, start the Dart signaling server in another terminal:
 *   dart run interop/automated/dart_signaling_server.dart
 *
 *   # Then run browser tests (either syntax works):
 *   BROWSER=chrome node interop/automated/browser_test.mjs
 *   node interop/automated/browser_test.mjs firefox
 *   node interop/automated/browser_test.mjs all
 */

import {
  getBrowserArg,
  launchBrowser,
  closeBrowser,
  setupConsoleLogging,
  checkServer,
} from './browser_utils.mjs';

const SERVER_URL = 'http://localhost:8765';

async function runBrowserTest(browserName) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`Testing: ${browserName}`);
  console.log('='.repeat(60));

  const { browser, context, page } = await launchBrowser(browserName, { headless: true });
  setupConsoleLogging(page, browserName);

  try {
    // Navigate to test page
    console.log(`[${browserName}] Loading test page...`);
    await page.goto(SERVER_URL, { timeout: 10000 });

    // Wait for test to complete
    console.log(`[${browserName}] Running test...`);
    const result = await page.evaluate(async () => {
      // Wait for test result
      return new Promise((resolve) => {
        const check = () => {
          if (window.testResult) {
            resolve(window.testResult);
          } else {
            setTimeout(check, 100);
          }
        };
        setTimeout(check, 100);

        // Timeout after 30 seconds
        setTimeout(() => {
          resolve({ success: false, error: 'Test timeout' });
        }, 30000);
      });
    });

    // Print results
    console.log(`\n[${browserName}] Test Result:`);
    console.log(`  Success: ${result.success}`);
    console.log(`  Messages sent: ${result.messagesSent || 0}`);
    console.log(`  Messages received: ${result.messagesReceived || 0}`);
    if (result.connectionTimeMs) {
      console.log(`  Connection time: ${result.connectionTimeMs}ms`);
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

  console.log('WebRTC Browser Interop Test');
  console.log('===========================');
  console.log(`Server: ${SERVER_URL}`);
  console.log(`Browser: ${browserArg}`);

  await checkServer(SERVER_URL, 'dart run interop/automated/dart_signaling_server.dart');

  const results = [];

  // Run tests based on argument
  if (browserArg === 'all' || browserArg === 'chrome') {
    results.push(await runBrowserTest('chrome'));
  }

  if (browserArg === 'all' || browserArg === 'firefox') {
    results.push(await runBrowserTest('firefox'));
  }

  if (browserArg === 'all' || browserArg === 'webkit' || browserArg === 'safari') {
    results.push(await runBrowserTest('safari'));
  }

  // Print summary
  console.log('\n' + '='.repeat(60));
  console.log('SUMMARY');
  console.log('='.repeat(60));

  let allPassed = true;
  for (const result of results) {
    const status = result.success ? '\u2713 PASS' : '\u2717 FAIL';
    console.log(`${status} - ${result.browser}`);
    if (!result.success) {
      allPassed = false;
      if (result.error) {
        console.log(`       Error: ${result.error}`);
      }
    }
  }

  console.log('='.repeat(60));

  if (allPassed) {
    console.log('\nAll browser tests PASSED!');
    process.exit(0);
  } else {
    console.log('\nSome browser tests FAILED!');
    process.exit(1);
  }
}

main().catch(e => {
  console.error('Fatal error:', e);
  process.exit(1);
});
