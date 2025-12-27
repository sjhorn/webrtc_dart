/**
 * Automated Media Recvonly Browser Test using Playwright
 *
 * Tests WebRTC video streaming from browser to Dart:
 * - Browser uses getUserMedia to capture camera (or canvas for Safari)
 * - Dart receives RTP packets
 *
 * Usage:
 *   # First, start the Dart media server in another terminal:
 *   dart run interop/automated/media_recvonly_server.dart
 *
 *   # Then run browser tests:
 *   node interop/automated/media_recvonly_test.mjs [chrome|firefox|safari|all]
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

const SERVER_URL = 'http://localhost:8767';

async function runBrowserTest(browserName) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`Testing Media Recvonly: ${browserName}`);
  console.log('='.repeat(60));

  const { browser, context, page } = await launchBrowser(browserName, { headless: true });
  setupConsoleLogging(page, browserName);

  try {
    console.log(`[${browserName}] Loading test page...`);
    await page.goto(SERVER_URL, { timeout: 10000 });

    console.log(`[${browserName}] Running test...`);
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
        setTimeout(() => resolve({ success: false, error: 'Test timeout' }), 45000);
      });
    });

    console.log(`\n[${browserName}] Test Result:`);
    console.log(`  Success: ${result.success}`);
    console.log(`  Video Received: ${result.videoReceived || false}`);
    console.log(`  Packets Received: ${result.packetsReceived || 0}`);
    if (result.connectionTimeMs) {
      console.log(`  Connection time: ${result.connectionTimeMs}ms`);
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

  console.log('WebRTC Media Recvonly Browser Test');
  console.log('===================================');
  console.log(`Server: ${SERVER_URL}`);
  console.log(`Browser: ${browserArg}`);

  await checkServer(SERVER_URL, 'dart run interop/automated/media_recvonly_server.dart');

  const results = [];

  if (browserArg === 'all') {
    for (const { browserName } of getAllBrowsers()) {
      results.push(await runBrowserTest(browserName));
    }
  } else {
    const { browserName } = getBrowserType(browserArg);
    results.push(await runBrowserTest(browserName));
  }

  // Print summary
  console.log('\n' + '='.repeat(60));
  console.log('MEDIA RECVONLY TEST SUMMARY');
  console.log('='.repeat(60));

  let allPassed = true;
  for (const result of results) {
    const status = result.success ? '✓ PASS' : '✗ FAIL';
    console.log(`${status} - ${result.browser}`);
    if (result.success) {
      console.log(`       Packets: ${result.packetsReceived || 0}`);
    } else {
      allPassed = false;
      if (result.error) {
        console.log(`       Error: ${result.error}`);
      }
    }
  }

  console.log('='.repeat(60));

  const passed = results.filter(r => r.success).length;
  if (passed === results.length) {
    console.log(`\nAll tested browsers PASSED! (${passed}/${results.length})`);
    process.exit(0);
  } else {
    console.log(`\nSome tests FAILED! (${passed}/${results.length} passed)`);
    process.exit(1);
  }
}

main().catch(e => {
  console.error('Fatal error:', e);
  process.exit(1);
});
