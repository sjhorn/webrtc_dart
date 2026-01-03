/**
 * Automated Save to Disk AV1 Browser Test using Playwright
 *
 * Tests WebRTC AV1 video recording:
 * - Browser sends AV1 camera video to Dart
 * - Dart records to WebM file using MediaRecorder
 * - Verifies file was created with non-zero size
 *
 * Usage:
 *   # First, start the Dart server in another terminal:
 *   dart run interop/automated/save_to_disk_av1_server.dart
 *
 *   # Then run browser tests:
 *   node interop/automated/save_to_disk_av1_test.mjs [chrome|all]
 *
 * Note: AV1 is only supported by Chrome. Safari and Firefox do not support AV1.
 */

import {
  getBrowserArg,
  launchBrowser,
  closeBrowser,
  setupConsoleLogging,
  checkServer,
} from './browser_utils.mjs';

const SERVER_URL = 'http://localhost:8796';

async function runBrowserTest(browserName) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`Testing Save to Disk AV1: ${browserName}`);
  console.log('='.repeat(60));

  const { browser, context, page } = await launchBrowser(browserName, { headless: true });
  setupConsoleLogging(page, browserName);

  try {
    console.log(`[${browserName}] Loading test page...`);
    await page.goto(SERVER_URL, { timeout: 10000 });

    console.log(`[${browserName}] Running AV1 test (5 seconds)...`);
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
        }, 60000);
      });
    });

    console.log(`\n[${browserName}] Test Result:`);
    console.log(`  Success: ${result.success}`);
    console.log(`  Codec: ${result.codec || 'unknown'}`);
    console.log(`  Packets Received: ${result.packetsReceived || 0}`);
    console.log(`  Keyframes Received: ${result.keyframesReceived || 0}`);
    console.log(`  File Size: ${result.fileSize || 0} bytes`);
    console.log(`  Output File: ${result.outputFile || 'none'}`);
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

  console.log('WebRTC Save to Disk AV1 Browser Test');
  console.log('====================================');
  console.log(`Server: ${SERVER_URL}`);
  console.log(`Browser: ${browserArg}`);
  console.log('Note: AV1 is only supported by Chrome');

  await checkServer(SERVER_URL, 'dart run interop/automated/save_to_disk_av1_server.dart');

  const results = [];

  // AV1 only works with Chrome
  if (browserArg === 'all' || browserArg === 'chrome') {
    results.push(await runBrowserTest('chrome'));
  }

  // Skip Firefox - AV1 not supported
  if (browserArg === 'firefox') {
    console.log('\n[firefox] AV1 is not supported by Firefox');
    results.push({ browser: 'firefox', success: false, error: 'AV1 not supported', skipped: true });
  } else if (browserArg === 'all') {
    console.log('\n[firefox] Skipping Firefox (AV1 not supported)');
    results.push({ browser: 'firefox', success: false, error: 'AV1 not supported', skipped: true });
  }

  // Skip Safari - AV1 not supported
  if (browserArg === 'webkit' || browserArg === 'safari') {
    console.log('\n[safari] AV1 is not supported by Safari');
    results.push({ browser: 'safari', success: false, error: 'AV1 not supported', skipped: true });
  } else if (browserArg === 'all') {
    console.log('\n[safari] Skipping Safari (AV1 not supported)');
    results.push({ browser: 'safari', success: false, error: 'AV1 not supported', skipped: true });
  }

  console.log('\n' + '='.repeat(60));
  console.log('SAVE TO DISK AV1 TEST SUMMARY');
  console.log('='.repeat(60));

  for (const result of results) {
    if (result.skipped) {
      console.log(`- SKIP - ${result.browser} (${result.error})`);
      continue;
    }
    const status = result.success ? '\u2713 PASS' : '\u2717 FAIL';
    console.log(`${status} - ${result.browser}`);
    if (result.success) {
      console.log(`       Packets: ${result.packetsReceived || 0}`);
      console.log(`       Keyframes: ${result.keyframesReceived || 0}`);
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
