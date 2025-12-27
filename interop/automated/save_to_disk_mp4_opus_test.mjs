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

import { chromium, firefox, webkit } from 'playwright';
import { getBrowserArg } from './test_utils.mjs';

const SERVER_URL = 'http://localhost:8773';
const TEST_TIMEOUT = 60000;

async function runBrowserTest(browserType, browserName) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`Testing Save to Disk MP4 Opus: ${browserName}`);
  console.log('='.repeat(60));

  let browser;
  let context;
  let page;

  try {
    console.log(`[${browserName}] Launching browser...`);
    browser = await browserType.launch({
      headless: true,
      args: browserName === 'chrome' ? [
        '--use-fake-ui-for-media-stream',
        '--use-fake-device-for-media-stream',
      ] : [],
    });

    const contextOptions = {
      permissions: browserName === 'chrome' ? ['microphone'] : [],
    };

    if (browserName === 'firefox') {
      contextOptions.firefoxUserPrefs = {
        'media.navigator.streams.fake': true,
        'media.navigator.permission.disabled': true,
      };
    }

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
    if (page) await page.close().catch(() => {});
    if (context) await context.close().catch(() => {});
    if (browser) await browser.close().catch(() => {});
  }
}

async function main() {
  // Support both: BROWSER=firefox node test.mjs OR node test.mjs firefox
  const browserArg = getBrowserArg() || 'all';

  console.log('WebRTC Save to Disk MP4 Opus Browser Test');
  console.log('=========================================');
  console.log(`Server: ${SERVER_URL}`);
  console.log(`Browser: ${browserArg}`);

  // Check if server is running
  try {
    const resp = await fetch(`${SERVER_URL}/status`);
    if (!resp.ok) throw new Error('Server not responding');
  } catch (e) {
    console.error('\nError: Save to Disk MP4 Opus server is not running!');
    console.error('Start it with: dart run interop/automated/save_to_disk_mp4_opus_server.dart');
    process.exit(1);
  }

  const results = [];

  if (browserArg === 'all' || browserArg === 'chrome') {
    results.push(await runBrowserTest(chromium, 'chrome'));
    await new Promise(r => setTimeout(r, 1000));
  }

  // Skip Firefox - has known ICE issues when Dart is offerer
  if (browserArg === 'firefox') {
    console.log('\n[firefox] Note: Firefox has known ICE issues when Dart is offerer');
    results.push(await runBrowserTest(firefox, 'firefox'));
    await new Promise(r => setTimeout(r, 1000));
  } else if (browserArg === 'all') {
    console.log('\n[firefox] Skipping Firefox (known ICE issue when Dart is offerer)');
    results.push({ browser: 'firefox', success: false, error: 'Skipped - ICE issue', skipped: true });
  }

  if (browserArg === 'all' || browserArg === 'webkit' || browserArg === 'safari') {
    results.push(await runBrowserTest(webkit, 'safari'));
  }

  console.log('\n' + '='.repeat(60));
  console.log('SAVE TO DISK MP4 OPUS TEST SUMMARY');
  console.log('='.repeat(60));

  for (const result of results) {
    if (result.skipped) {
      console.log(`- SKIP - ${result.browser} (${result.error})`);
      continue;
    }
    const status = result.success ? '+ PASS' : 'x FAIL';
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
