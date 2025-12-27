/**
 * Automated Simulcast Browser Test using Playwright
 *
 * Tests WebRTC simulcast SDP negotiation:
 * - Browser sends VP8 video to Dart
 * - Verifies simulcast is negotiated in SDP (rid, simulcast attributes)
 * - Records video successfully
 *
 * Note: Full simulcast (multiple layers) requires browser to send multiple
 * encodings, which needs specific SDP configuration. This test verifies
 * simulcast negotiation capability.
 *
 * Usage:
 *   # First, start the Dart server in another terminal:
 *   dart run interop/automated/simulcast_server.dart
 *
 *   # Then run browser tests:
 *   node interop/automated/simulcast_test.mjs [chrome|firefox|webkit|all]
 */

import {
  getBrowserArg,
  getBrowserType,
  launchBrowser,
  closeBrowser,
  setupConsoleLogging,
  checkServer,
} from './browser_utils.mjs';

const SERVER_URL = 'http://localhost:8780';

async function runBrowserTest(browserName) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`Testing Simulcast: ${browserName}`);
  console.log('='.repeat(60));

  const { browser, context, page } = await launchBrowser(browserName, { headless: true });
  setupConsoleLogging(page, browserName);

  try {
    console.log(`[${browserName}] Loading test page...`);
    await page.goto(SERVER_URL, { timeout: 10000 });

    console.log(`[${browserName}] Running simulcast test (5 seconds)...`);
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
        setTimeout(() => resolve({ success: false, error: 'Test timeout' }), 60000);
      });
    });

    console.log(`\n[${browserName}] Test Result:`);
    console.log(`  Success: ${result.success}`);
    console.log(`  Simulcast Negotiated: ${result.simulcastNegotiated}`);
    console.log(`  Packets Received: ${result.packetsReceived || 0}`);
    console.log(`  File Size: ${result.fileSize || 0} bytes`);
    console.log(`  Output File: ${result.outputFile || 'none'}`);
    if (result.connectionTimeMs) {
      console.log(`  Connection time: ${result.connectionTimeMs}ms`);
    }
    if (result.simulcastSdpInfo) {
      console.log(`  Simulcast SDP Info:\n${result.simulcastSdpInfo}`);
    }
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

  console.log('WebRTC Simulcast Browser Test');
  console.log('=============================');
  console.log(`Server: ${SERVER_URL}`);
  console.log(`Browser: ${browserArg}`);

  await checkServer(SERVER_URL, 'dart run interop/automated/simulcast_server.dart');

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
  console.log('SIMULCAST TEST SUMMARY');
  console.log('='.repeat(60));

  for (const result of results) {
    if (result.skipped) {
      console.log(`- SKIP - ${result.browser} (${result.error})`);
      continue;
    }
    const status = result.success ? '✓ PASS' : '✗ FAIL';
    console.log(`${status} - ${result.browser}`);
    if (result.success) {
      console.log(`       Simulcast: ${result.simulcastNegotiated ? 'YES' : 'NO'}`);
      console.log(`       Packets: ${result.packetsReceived || 0}`);
      console.log(`       File: ${result.fileSize || 0} bytes`);
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
    console.log(`\nAll tested browsers PASSED! (${passed}/${total})`);
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
