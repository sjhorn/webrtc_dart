/**
 * Automated Media Answer Browser Test using Playwright
 *
 * Tests Dart as ANSWERER for media (browser is offerer):
 * - Browser creates PeerConnection with sendonly video track
 * - Browser creates offer and sends to Dart
 * - Dart creates answer with recvonly video
 * - Dart receives video from browser and counts packets
 *
 * This is the opposite pattern from most media tests and may work with Firefox
 * since Firefox ICE issues were observed when Dart was the offerer.
 *
 * Usage:
 *   # First, start the Dart server in another terminal:
 *   dart run interop/automated/media_answer_server.dart
 *
 *   # Then run browser tests:
 *   node interop/automated/media_answer_test.mjs [chrome|firefox|webkit|all]
 */

import {
  getBrowserArg,
  launchBrowser,
  closeBrowser,
  setupConsoleLogging,
  checkServer,
} from './browser_utils.mjs';

const SERVER_URL = 'http://localhost:8776';

async function runBrowserTest(browserName) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`Testing Media Answer: ${browserName}`);
  console.log('='.repeat(60));

  const { browser, context, page } = await launchBrowser(browserName, { headless: true });
  setupConsoleLogging(page, browserName);

  try {
    console.log(`[${browserName}] Loading test page...`);
    await page.goto(SERVER_URL, { timeout: 10000 });

    console.log(`[${browserName}] Running media answer test...`);
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

        // Timeout after 45 seconds
        setTimeout(() => {
          resolve({ success: false, error: 'Test timeout' });
        }, 45000);
      });
    });

    console.log(`\n[${browserName}] Test Result:`);
    console.log(`  Success: ${result.success}`);
    console.log(`  Track Received: ${result.trackReceived || false}`);
    console.log(`  Packets Received: ${result.packetsReceived || 0}`);
    console.log(`  Connection Time: ${result.connectionTimeMs || 0}ms`);
    console.log(`  Pattern: ${result.pattern || 'unknown'}`);
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

  console.log('WebRTC Media Answer Browser Test');
  console.log('================================');
  console.log(`Server: ${SERVER_URL}`);
  console.log(`Browser: ${browserArg}`);
  console.log('Pattern: Browser=Offerer, Dart=Answerer');

  await checkServer(SERVER_URL, 'dart run interop/automated/media_answer_server.dart');

  const results = [];

  if (browserArg === 'all' || browserArg === 'chrome') {
    results.push(await runBrowserTest('chrome'));
    await new Promise(r => setTimeout(r, 1000));
  }

  // Try Firefox! This pattern (browser=offerer) might work
  if (browserArg === 'all' || browserArg === 'firefox') {
    console.log('\n[firefox] Testing Firefox (browser is offerer - may work!)');
    results.push(await runBrowserTest('firefox'));
    await new Promise(r => setTimeout(r, 1000));
  }

  if (browserArg === 'all' || browserArg === 'webkit' || browserArg === 'safari') {
    results.push(await runBrowserTest('safari'));
  }

  console.log('\n' + '='.repeat(60));
  console.log('MEDIA ANSWER TEST SUMMARY');
  console.log('='.repeat(60));

  for (const result of results) {
    const status = result.success ? '\u2713 PASS' : '\u2717 FAIL';
    console.log(`${status} - ${result.browser}`);
    if (result.success) {
      console.log(`       Packets: ${result.packetsReceived}`);
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
