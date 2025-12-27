/**
 * Automated Save to Disk Browser Test using Playwright
 *
 * Tests WebRTC video recording:
 * - Browser sends camera video to Dart
 * - Dart records to WebM file using MediaRecorder
 * - Verifies file was created with non-zero size
 *
 * Usage:
 *   # First, start the Dart server in another terminal:
 *   dart run interop/automated/save_to_disk_server.dart
 *
 *   # Then run browser tests (either syntax works):
 *   BROWSER=chrome node interop/automated/save_to_disk_test.mjs
 *   node interop/automated/save_to_disk_test.mjs firefox
 *
 * Note: Firefox headless doesn't support getUserMedia (camera tests skip Firefox).
 */

import {
  getBrowserArg,
  getBrowserType,
  launchBrowser,
  closeBrowser,
  setupConsoleLogging,
  checkServer,
} from './browser_utils.mjs';

const SERVER_URL = 'http://localhost:8769';

async function runBrowserTest(browserName) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`Testing Save to Disk: ${browserName}`);
  console.log('='.repeat(60));

  const { browser, context, page } = await launchBrowser(browserName, { headless: true });
  setupConsoleLogging(page, browserName);

  try {
    console.log(`[${browserName}] Loading test page...`);
    await page.goto(SERVER_URL, { timeout: 10000 });

    console.log(`[${browserName}] Running test (recording for 5 seconds)...`);
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
    console.log(`  Packets Received: ${result.packetsReceived || 0}`);
    console.log(`  File Size: ${result.fileSize || 0} bytes`);
    console.log(`  Output File: ${result.outputFile || 'none'}`);
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

  console.log('WebRTC Save to Disk Browser Test');
  console.log('=================================');
  console.log(`Server: ${SERVER_URL}`);
  console.log(`Browser: ${browserArg}`);

  await checkServer(SERVER_URL, 'dart run interop/automated/save_to_disk_server.dart');

  const results = [];

  if (browserArg === 'all' || browserArg === 'chrome') {
    results.push(await runBrowserTest('chrome'));
  }

  // Skip Firefox - getUserMedia not supported in headless Playwright Firefox
  if (browserArg === 'firefox') {
    console.log('\n[firefox] Note: getUserMedia may not work in headless Firefox');
    results.push(await runBrowserTest('firefox'));
  } else if (browserArg === 'all') {
    console.log('\n[firefox] Skipping Firefox (getUserMedia not supported in headless)');
    results.push({ browser: 'firefox', success: false, error: 'Skipped - no getUserMedia', skipped: true });
  }

  if (browserArg === 'all' || browserArg === 'webkit' || browserArg === 'safari') {
    results.push(await runBrowserTest('safari'));
  }

  // Print summary
  console.log('\n' + '='.repeat(60));
  console.log('SAVE TO DISK TEST SUMMARY');
  console.log('='.repeat(60));

  for (const result of results) {
    if (result.skipped) {
      console.log(`- SKIP - ${result.browser} (${result.error})`);
      continue;
    }
    const status = result.success ? '✓ PASS' : '✗ FAIL';
    console.log(`${status} - ${result.browser}`);
    if (result.success) {
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
