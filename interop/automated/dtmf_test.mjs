/**
 * Automated DTMF (Dual-Tone Multi-Frequency) Browser Test using Playwright
 *
 * Tests RTCDTMFSender functionality:
 * - Browser creates audio offer
 * - Dart answers and gets RTCRtpSender with DTMF support
 * - Dart inserts DTMF tones (123*#)
 * - Verifies ontonechange events fire correctly
 *
 * This tests RFC 4733 telephone-event RTP payload implementation.
 *
 * Usage:
 *   # First, start the Dart server in another terminal:
 *   dart run interop/automated/dtmf_server.dart
 *
 *   # Then run browser tests:
 *   node interop/automated/dtmf_test.mjs [chrome|firefox|webkit|all]
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

const SERVER_URL = 'http://localhost:8776';

async function runBrowserTest(browserName) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`Testing DTMF: ${browserName}`);
  console.log('='.repeat(60));

  // Safari headless has issues with audio - skip or use special handling
  const launchOptions = { headless: true };
  if (browserName === 'webkit') {
    // Safari/WebKit needs special audio handling
    console.log(`[${browserName}] Note: WebKit may have limited DTMF support in headless`);
  }

  const { browser, context, page } = await launchBrowser(browserName, launchOptions);
  setupConsoleLogging(page, browserName);

  try {
    console.log(`[${browserName}] Loading test page...`);
    await page.goto(SERVER_URL, { timeout: 10000 });

    console.log(`[${browserName}] Running DTMF test...`);
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
        // DTMF takes time: 5 tones * (100ms + 70ms) + connection time
        setTimeout(() => resolve({ success: false, error: 'Test timeout' }), 45000);
      });
    });

    console.log(`\n[${browserName}] Test Result:`);
    console.log(`  Success: ${result.success}`);
    console.log(`  DTMF Supported: ${result.dtmfSupported}`);
    console.log(`  Requested Tones: "${result.requestedTones || ''}"`);
    console.log(`  Sent Tones: "${result.sentTones || ''}"`);
    console.log(`  Tone Events: ${JSON.stringify(result.toneChangeEvents || [])}`);
    console.log(`  Connection Time: ${result.connectionTimeMs || 0}ms`);
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

  console.log('WebRTC DTMF (RTCDTMFSender) Browser Test');
  console.log('========================================');
  console.log(`Server: ${SERVER_URL}`);
  console.log(`Browser: ${browserArg}`);
  console.log('Tests: RFC 4733 telephone-event (DTMF tones)');

  await checkServer(SERVER_URL, 'dart run interop/automated/dtmf_server.dart');

  const results = [];

  if (browserArg === 'all') {
    for (const { browserName } of getAllBrowsers()) {
      results.push(await runBrowserTest(browserName));
      await new Promise(r => setTimeout(r, 1000));
    }
  } else {
    const { browserName } = getBrowserType(browserArg);
    results.push(await runBrowserTest(browserName));
  }

  console.log('\n' + '='.repeat(60));
  console.log('DTMF TEST SUMMARY');
  console.log('='.repeat(60));

  for (const result of results) {
    const status = result.success ? '✓ PASS' : '✗ FAIL';
    console.log(`${status} - ${result.browser}`);
    if (result.success) {
      console.log(`       Tones: "${result.sentTones}"`);
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
