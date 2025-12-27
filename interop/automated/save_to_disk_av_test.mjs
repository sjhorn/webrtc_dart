/**
 * Automated Save to Disk Audio+Video Browser Test using Playwright
 *
 * Tests WebRTC Audio+Video recording:
 * - Browser sends VP8 camera video + Opus microphone audio to Dart
 * - Dart records to WebM file using MediaRecorder with lip sync
 * - Verifies file was created with non-zero size
 *
 * Usage:
 *   # First, start the Dart server in another terminal:
 *   dart run interop/automated/save_to_disk_av_server.dart
 *
 *   # Then run browser tests:
 *   node interop/automated/save_to_disk_av_test.mjs [chrome|firefox|webkit|all]
 *
 * Note: Firefox is skipped by default due to known ICE issues when Dart is offerer.
 */

import {
  getBrowserArg,
  launchBrowser,
  closeBrowser,
  setupConsoleLogging,
  checkServer,
} from './browser_utils.mjs';

const SERVER_URL = 'http://localhost:8773';

async function runBrowserTest(browserName) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`Testing Save to Disk A/V: ${browserName}`);
  console.log('='.repeat(60));

  const { browser, context, page } = await launchBrowser(browserName, { headless: true });
  setupConsoleLogging(page, browserName);

  try {
    // Navigate to test page
    console.log(`[${browserName}] Loading test page...`);
    await page.goto(SERVER_URL, { timeout: 10000 });

    // Wait for test to complete
    console.log(`[${browserName}] Running A/V test (recording for 5 seconds)...`);
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

        // Timeout after 60 seconds
        setTimeout(() => {
          resolve({ success: false, error: 'Test timeout' });
        }, 60000);
      });
    });

    // Print results
    console.log(`\n[${browserName}] Test Result:`);
    console.log(`  Success: ${result.success}`);
    console.log(`  Codec: ${result.codec || 'unknown'}`);
    console.log(`  Video Packets: ${result.videoPacketsReceived || 0}`);
    console.log(`  Audio Packets: ${result.audioPacketsReceived || 0}`);
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

  console.log('WebRTC Save to Disk A/V Browser Test');
  console.log('====================================');
  console.log(`Server: ${SERVER_URL}`);
  console.log(`Browser: ${browserArg}`);

  await checkServer(SERVER_URL, 'dart run interop/automated/save_to_disk_av_server.dart');

  const results = [];

  // Run tests based on argument
  if (browserArg === 'all' || browserArg === 'chrome') {
    results.push(await runBrowserTest('chrome'));
  }

  // Skip Firefox by default
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

  // Print summary
  console.log('\n' + '='.repeat(60));
  console.log('SAVE TO DISK A/V TEST SUMMARY');
  console.log('='.repeat(60));

  for (const result of results) {
    if (result.skipped) {
      console.log(`- SKIP - ${result.browser} (${result.error})`);
      continue;
    }
    const status = result.success ? '\u2713 PASS' : '\u2717 FAIL';
    console.log(`${status} - ${result.browser}`);
    if (result.success) {
      console.log(`       Video: ${result.videoPacketsReceived || 0} packets`);
      console.log(`       Audio: ${result.audioPacketsReceived || 0} packets`);
      console.log(`       File: ${result.fileSize || 0} bytes`);
    }
    if (!result.success && !result.skipped) {
      if (result.error) {
        console.log(`       Error: ${result.error}`);
      }
    }
  }

  console.log('='.repeat(60));

  // Don't count skipped tests as failures
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
