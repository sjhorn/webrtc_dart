/**
 * Automated ICE Trickle Browser Test using Playwright
 *
 * Tests WebRTC ICE trickle functionality:
 * - Dart creates offer immediately (without waiting for all candidates)
 * - Browser adds candidates as they arrive
 * - Verifies DataChannel connectivity with ping/pong
 *
 * Usage:
 *   # First, start the Dart server in another terminal:
 *   dart run interop/automated/ice_trickle_server.dart
 *
 *   # Then run browser tests (either syntax works):
 *   BROWSER=chrome node interop/automated/ice_trickle_test.mjs
 *   node interop/automated/ice_trickle_test.mjs firefox
 */

import { chromium, firefox, webkit } from 'playwright';
import { getBrowserArg } from './test_utils.mjs';

const SERVER_URL = 'http://localhost:8781';
const TEST_TIMEOUT = 60000;

async function runBrowserTest(browserType, browserName) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`Testing ICE Trickle: ${browserName}`);
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

    console.log(`[${browserName}] Running ICE trickle test...`);
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
        }, 30000);
      });
    });

    console.log(`\n[${browserName}] Test Result:`);
    console.log(`  Success: ${result.success}`);
    console.log(`  ICE Trickle: ${result.iceTrickle ? 'YES' : 'NO'}`);
    console.log(`  Candidates Received: ${result.candidatesReceived || 0}`);
    console.log(`  Candidates Sent: ${result.candidatesSent || 0}`);
    console.log(`  Ping/Pong: ${result.pingPongSuccess ? 'YES' : 'NO'}`);
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
    if (page) await page.close().catch(() => {});
    if (context) await context.close().catch(() => {});
    if (browser) await browser.close().catch(() => {});
  }
}

async function main() {
  // Support both: BROWSER=firefox node test.mjs OR node test.mjs firefox
  const browserArg = getBrowserArg() || 'all';

  console.log('WebRTC ICE Trickle Browser Test');
  console.log('================================');
  console.log(`Server: ${SERVER_URL}`);
  console.log(`Browser: ${browserArg}`);

  try {
    const resp = await fetch(`${SERVER_URL}/status`);
    if (!resp.ok) throw new Error('Server not responding');
  } catch (e) {
    console.error('\nError: ICE Trickle server is not running!');
    console.error('Start it with: dart run interop/automated/ice_trickle_server.dart');
    process.exit(1);
  }

  const results = [];

  if (browserArg === 'all' || browserArg === 'chrome') {
    results.push(await runBrowserTest(chromium, 'chrome'));
  }

  if (browserArg === 'all' || browserArg === 'firefox') {
    results.push(await runBrowserTest(firefox, 'firefox'));
  }

  if (browserArg === 'all' || browserArg === 'webkit' || browserArg === 'safari') {
    results.push(await runBrowserTest(webkit, 'safari'));
  }

  console.log('\n' + '='.repeat(60));
  console.log('ICE TRICKLE TEST SUMMARY');
  console.log('='.repeat(60));

  for (const result of results) {
    if (result.skipped) {
      console.log(`- SKIP - ${result.browser} (${result.error})`);
      continue;
    }
    const status = result.success ? '+ PASS' : 'x FAIL';
    console.log(`${status} - ${result.browser}`);
    if (result.success) {
      console.log(`       Trickle: ${result.iceTrickle ? 'YES' : 'NO'}`);
      console.log(`       Candidates Recv: ${result.candidatesReceived || 0}`);
      console.log(`       Candidates Sent: ${result.candidatesSent || 0}`);
      console.log(`       Ping/Pong: ${result.pingPongSuccess ? 'YES' : 'NO'}`);
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
