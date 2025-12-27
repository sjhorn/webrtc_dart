/**
 * Automated Save to Disk MP4 Opus Browser Test using Playwright
 *
 * Tests WebRTC Opus audio recording to fragmented MP4:
 * - Browser sends Opus microphone audio to Dart server
 * - Dart writes Opus frames to fMP4 container
 * - Verifies MP4 file is created with valid size
 *
 * Usage:
 *   # First, start the Dart server in another terminal:
 *   dart run interop/automated/save_to_disk_mp4_opus_server.dart
 *
 *   # Then run browser tests:
 *   node interop/automated/save_to_disk_mp4_opus_test.mjs [chrome|firefox|webkit|all]
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
  console.log(`Testing Save to Disk MP4 Opus: ${browserName}`);
  console.log('='.repeat(60));

  const { browser, context, page } = await launchBrowser(browserName, { headless: true });
  setupConsoleLogging(page, browserName);

  try {
    console.log(`[${browserName}] Loading test page...`);
    await page.goto(SERVER_URL, { timeout: 10000 });

    console.log(`[${browserName}] Running save to disk MP4 Opus test...`);
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
    console.log(`  Packets Received: ${result.packetsReceived || 0}`);
    console.log(`  Frames Written: ${result.framesWritten || 0}`);
    console.log(`  File Size: ${result.fileSize || 0} bytes`);
    console.log(`  Codec: ${result.codec || 'unknown'}`);
    console.log(`  Container: ${result.container || 'unknown'}`);
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

  console.log('WebRTC Save to Disk MP4 Opus Browser Test');
  console.log('=========================================');
  console.log(`Server: ${SERVER_URL}`);
  console.log(`Browser: ${browserArg}`);

  await checkServer(SERVER_URL, 'dart run interop/automated/save_to_disk_mp4_opus_server.dart');

  const results = [];

  if (browserArg === 'all' || browserArg === 'chrome') {
    results.push(await runBrowserTest('chrome'));
    await new Promise(r => setTimeout(r, 1000));
  }

  // Skip Firefox - has known ICE issues when Dart is offerer
  if (browserArg === 'firefox') {
    console.log('\n[firefox] Note: Firefox has known ICE issues when Dart is offerer');
    results.push(await runBrowserTest('firefox'));
    await new Promise(r => setTimeout(r, 1000));
  } else if (browserArg === 'all') {
    console.log('\n[firefox] Skipping Firefox (known ICE issue when Dart is offerer)');
    results.push({ browser: 'firefox', success: false, error: 'Skipped - ICE issue', skipped: true });
  }

  if (browserArg === 'all' || browserArg === 'webkit' || browserArg === 'safari') {
    results.push(await runBrowserTest('safari'));
  }

  console.log('\n' + '='.repeat(60));
  console.log('SAVE TO DISK MP4 OPUS TEST SUMMARY');
  console.log('='.repeat(60));

  for (const result of results) {
    if (result.skipped) {
      console.log(`- SKIP - ${result.browser} (${result.error})`);
      continue;
    }
    const status = result.success ? '\u2713 PASS' : '\u2717 FAIL';
    console.log(`${status} - ${result.browser}`);
    if (result.success) {
      console.log(`       Packets: ${result.packetsReceived}`);
      console.log(`       Frames: ${result.framesWritten}`);
      console.log(`       File Size: ${result.fileSize} bytes`);
    }
    if (!result.success && !result.skipped && result.error) {
      console.log(`       Error: ${result.error}`);
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
