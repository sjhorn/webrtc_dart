/**
 * Automated Sendrecv Answer Browser Test using Playwright
 *
 * Tests Dart as ANSWERER for sendrecv media (browser is offerer):
 * - Browser creates PeerConnection with sendrecv video track
 * - Browser creates offer and sends to Dart
 * - Dart creates answer with sendrecv video
 * - Dart receives video from browser and echoes it back
 *
 * This is the opposite pattern from most media tests and may work with Firefox
 * since Firefox ICE issues were observed when Dart was the offerer.
 *
 * Usage:
 *   # First, start the Dart server in another terminal:
 *   dart run interop/automated/sendrecv_answer_server.dart
 *
 *   # Then run browser tests:
 *   node interop/automated/sendrecv_answer_test.mjs [chrome|firefox|webkit|all]
 */

import {
  getBrowserArg,
  getBrowserType,
  getAllBrowsers,
  launchBrowser,
  closeBrowser,
  setupConsoleLogging,
  checkServer,
} from './browser_utils.mjs';

const SERVER_URL = 'http://localhost:8777';

async function runBrowserTest(browserName) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`Testing Sendrecv Answer (Echo): ${browserName}`);
  console.log('='.repeat(60));

  const { browser, context, page } = await launchBrowser(browserName, { headless: true });
  setupConsoleLogging(page, browserName);

  try {
    console.log(`[${browserName}] Loading test page...`);
    await page.goto(SERVER_URL, { timeout: 10000 });

    console.log(`[${browserName}] Running sendrecv answer test...`);
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
        setTimeout(() => resolve({ success: false, error: 'Test timeout' }), 50000);
      });
    });

    console.log(`\n[${browserName}] Test Result:`);
    console.log(`  Success: ${result.success}`);
    console.log(`  Track Received: ${result.trackReceived || false}`);
    console.log(`  Packets Received: ${result.packetsReceived || 0}`);
    console.log(`  Packets Echoed: ${result.packetsEchoed || 0}`);
    console.log(`  Echo Frames: ${result.echoFramesReceived || 0}`);
    console.log(`  Connection Time: ${result.connectionTimeMs || 0}ms`);
    console.log(`  Pattern: ${result.pattern || 'unknown'}`);
    if (result.error) {
      console.log(`  Error: ${result.error}`);
    }

    return { browser: browserName, ...result };

  } catch (error) {
    console.error(`[${browserName}] Error: ${error.message}`);
    return { browser: browserName, success: false, error: error.message };
  } finally {
    await closeBrowser({ browser, context, page });
  }
}

async function main() {
  const browserArg = getBrowserArg();

  console.log('WebRTC Sendrecv Answer (Echo) Browser Test');
  console.log('==========================================');
  console.log(`Server: ${SERVER_URL}`);
  console.log(`Browser: ${browserArg}`);
  console.log('Pattern: Browser=Offerer, Dart=Answerer (Echo)');

  await checkServer(SERVER_URL, 'dart run interop/automated/sendrecv_answer_server.dart');

  const results = [];

  if (browserArg === 'all') {
    for (const { browserName } of getAllBrowsers()) {
      if (browserName === 'firefox') {
        console.log('\n[firefox] Note: Firefox ICE typically fails with Dart implementation');
      }
      results.push(await runBrowserTest(browserName));
      await new Promise(r => setTimeout(r, 2000));
    }
  } else {
    const { browserName } = getBrowserType(browserArg);
    if (browserName === 'firefox') {
      console.log('\n[firefox] Note: Firefox ICE typically fails with Dart implementation');
    }
    results.push(await runBrowserTest(browserName));
  }

  console.log('\n' + '='.repeat(60));
  console.log('SENDRECV ANSWER (ECHO) TEST SUMMARY');
  console.log('='.repeat(60));

  for (const result of results) {
    const status = result.success ? '✓ PASS' : '✗ FAIL';
    console.log(`${status} - ${result.browser}`);
    if (result.success) {
      console.log(`       Recv: ${result.packetsReceived}, Echo: ${result.packetsEchoed}`);
      console.log(`       Echo Frames: ${result.echoFramesReceived}`);
      console.log(`       Connection: ${result.connectionTimeMs}ms`);
    }
    if (!result.success && result.error) {
      console.log(`       Error: ${result.error}`);
    }
  }

  console.log('='.repeat(60));

  const passed = results.filter(r => r.success).length;
  const total = results.length;

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
