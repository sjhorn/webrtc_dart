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

import { chromium, firefox, webkit } from 'playwright';
import { getBrowserArg } from './test_utils.mjs';

const SERVER_URL = 'http://localhost:8777';
const TEST_TIMEOUT = 60000;

async function runBrowserTest(browserType, browserName) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`Testing Sendrecv Answer (Echo): ${browserName}`);
  console.log('='.repeat(60));

  let browser;
  let context;
  let page;

  try {
    console.log(`[${browserName}] Launching browser...`);

    // Browser-specific launch args
    // Note: Removed fake device flags as they interfere with video echo detection
    const launchArgs = browserName === 'chrome' ? [
      '--autoplay-policy=no-user-gesture-required',
    ] : [];

    // Note: headless: false required for video decoding to work properly
    browser = await browserType.launch({
      headless: false,
      args: launchArgs,
    });

    // Only Chrome supports permission grants in Playwright this way
    const contextOptions = browserName === 'chrome'
      ? { permissions: ['microphone', 'camera'] }
      : {};

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

        // Timeout after 50 seconds
        setTimeout(() => {
          resolve({ success: false, error: 'Test timeout' });
        }, 50000);
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

  console.log('WebRTC Sendrecv Answer (Echo) Browser Test');
  console.log('==========================================');
  console.log(`Server: ${SERVER_URL}`);
  console.log(`Browser: ${browserArg}`);
  console.log('Pattern: Browser=Offerer, Dart=Answerer (Echo)');

  // Check if server is running
  try {
    const resp = await fetch(`${SERVER_URL}/status`);
    if (!resp.ok) throw new Error('Server not responding');
  } catch (e) {
    console.error('\nError: Sendrecv Answer server is not running!');
    console.error('Start it with: dart run interop/automated/sendrecv_answer_server.dart');
    process.exit(1);
  }

  const results = [];

  if (browserArg === 'all' || browserArg === 'chrome') {
    results.push(await runBrowserTest(chromium, 'chrome'));
    await new Promise(r => setTimeout(r, 2000)); // Increased delay for server cleanup
  }

  // Firefox - ICE fails with our implementation (known issue)
  // Still run in 'all' mode to verify cleanup works between tests
  if (browserArg === 'all' || browserArg === 'firefox') {
    console.log('\n[firefox] Note: Firefox ICE typically fails with Dart implementation');
    results.push(await runBrowserTest(firefox, 'firefox'));
    await new Promise(r => setTimeout(r, 2000));
  }

  if (browserArg === 'all' || browserArg === 'webkit' || browserArg === 'safari') {
    results.push(await runBrowserTest(webkit, 'safari'));
  }

  console.log('\n' + '='.repeat(60));
  console.log('SENDRECV ANSWER (ECHO) TEST SUMMARY');
  console.log('='.repeat(60));

  for (const result of results) {
    const status = result.success ? '+ PASS' : 'x FAIL';
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
