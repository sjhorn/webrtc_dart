/**
 * Automated DataChannel Answer Browser Test using Playwright
 *
 * Tests Dart as ANSWERER (browser is offerer):
 * - Browser creates PeerConnection + DataChannel, creates offer
 * - Dart receives offer and creates answer
 * - DataChannel opens and they exchange ping/pong messages
 *
 * This is the opposite pattern from most tests and may work with Firefox
 * since Firefox ICE issues were observed when Dart was the offerer.
 *
 * Usage:
 *   # First, start the Dart server in another terminal:
 *   dart run interop/automated/datachannel_answer_server.dart
 *
 *   # Then run browser tests:
 *   node interop/automated/datachannel_answer_test.mjs [chrome|firefox|webkit|all]
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

const SERVER_URL = 'http://localhost:8775';

async function runBrowserTest(browserName) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`Testing DataChannel Answer: ${browserName}`);
  console.log('='.repeat(60));

  const { browser, context, page } = await launchBrowser(browserName, { headless: true });
  setupConsoleLogging(page, browserName);

  try {
    console.log(`[${browserName}] Loading test page...`);
    await page.goto(SERVER_URL, { timeout: 10000 });

    console.log(`[${browserName}] Running DataChannel answer test...`);
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
        setTimeout(() => resolve({ success: false, error: 'Test timeout' }), 40000);
      });
    });

    console.log(`\n[${browserName}] Test Result:`);
    console.log(`  Success: ${result.success}`);
    console.log(`  DC Opened: ${result.dcOpened}`);
    console.log(`  Messages Sent: ${result.messagesSent || 0}`);
    console.log(`  Messages Received: ${result.messagesReceived || 0}`);
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

  console.log('WebRTC DataChannel Answer Browser Test');
  console.log('======================================');
  console.log(`Server: ${SERVER_URL}`);
  console.log(`Browser: ${browserArg}`);
  console.log('Pattern: Browser=Offerer, Dart=Answerer');

  await checkServer(SERVER_URL, 'dart run interop/automated/datachannel_answer_server.dart');

  const results = [];

  if (browserArg === 'all') {
    for (const { browserName } of getAllBrowsers()) {
      if (browserName === 'firefox') {
        console.log('\n[firefox] Testing Firefox (browser is offerer - may work!)');
      }
      results.push(await runBrowserTest(browserName));
      await new Promise(r => setTimeout(r, 1000));
    }
  } else {
    const { browserName } = getBrowserType(browserArg);
    if (browserName === 'firefox') {
      console.log('\n[firefox] Testing Firefox (browser is offerer - may work!)');
    }
    results.push(await runBrowserTest(browserName));
  }

  console.log('\n' + '='.repeat(60));
  console.log('DATACHANNEL ANSWER TEST SUMMARY');
  console.log('='.repeat(60));

  for (const result of results) {
    const status = result.success ? '✓ PASS' : '✗ FAIL';
    console.log(`${status} - ${result.browser}`);
    if (result.success) {
      console.log(`       Sent: ${result.messagesSent}, Received: ${result.messagesReceived}`);
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
