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

import { chromium, firefox, webkit } from 'playwright';
import { getBrowserArg } from './test_utils.mjs';

const SERVER_URL = 'http://localhost:8773';
const TEST_TIMEOUT = 60000;

async function runBrowserTest(browserType, browserName) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`Testing Save to Disk A/V: ${browserName}`);
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

    // Grant camera and microphone permissions (Chrome only - Firefox uses prefs above)
    const contextOptions = {
      permissions: browserName === 'chrome' ? ['camera', 'microphone'] : [],
    };

    context = await browser.newContext(contextOptions);
    page = await context.newPage();

    // Listen for console messages
    page.on('console', msg => {
      const text = msg.text();
      if (!text.startsWith('TEST_RESULT:')) {
        console.log(`[${browserName}] ${text}`);
      }
    });

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
    if (page) await page.close().catch(() => {});
    if (context) await context.close().catch(() => {});
    if (browser) await browser.close().catch(() => {});
  }
}

async function main() {
  // Support both: BROWSER=firefox node test.mjs OR node test.mjs firefox
  const browserArg = getBrowserArg() || 'all';

  console.log('WebRTC Save to Disk A/V Browser Test');
  console.log('====================================');
  console.log(`Server: ${SERVER_URL}`);
  console.log(`Browser: ${browserArg}`);

  // Check server is running
  try {
    const resp = await fetch(`${SERVER_URL}/status`);
    if (!resp.ok) throw new Error('Server not responding');
  } catch (e) {
    console.error('\nError: Save to disk A/V server is not running!');
    console.error('Start it with: dart run interop/automated/save_to_disk_av_server.dart');
    process.exit(1);
  }

  const results = [];

  // Run tests based on argument
  if (browserArg === 'all' || browserArg === 'chrome') {
    results.push(await runBrowserTest(chromium, 'chrome'));
  }

  // Skip Firefox by default
  if (browserArg === 'firefox') {
    console.log('\n[firefox] Note: Firefox has known ICE issues when Dart is offerer');
    results.push(await runBrowserTest(firefox, 'firefox'));
  } else if (browserArg === 'all') {
    console.log('\n[firefox] Skipping Firefox (known ICE issue when Dart is offerer)');
    results.push({ browser: 'firefox', success: false, error: 'Skipped - ICE issue', skipped: true });
  }

  if (browserArg === 'all' || browserArg === 'webkit' || browserArg === 'safari') {
    results.push(await runBrowserTest(webkit, 'safari'));
  }

  // Print summary
  console.log('\n' + '='.repeat(60));
  console.log('SAVE TO DISK A/V TEST SUMMARY');
  console.log('='.repeat(60));

  let allPassed = true;
  for (const result of results) {
    if (result.skipped) {
      console.log(`- SKIP - ${result.browser} (${result.error})`);
      continue;
    }
    const status = result.success ? '+ PASS' : 'x FAIL';
    console.log(`${status} - ${result.browser}`);
    if (result.success) {
      console.log(`       Video: ${result.videoPacketsReceived || 0} packets`);
      console.log(`       Audio: ${result.audioPacketsReceived || 0} packets`);
      console.log(`       File: ${result.fileSize || 0} bytes`);
    }
    if (!result.success && !result.skipped) {
      allPassed = false;
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
