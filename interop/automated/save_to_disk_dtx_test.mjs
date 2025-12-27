/**
 * Automated Save to Disk DTX (Discontinuous Transmission) Browser Test
 *
 * Tests WebRTC audio recording with DTX enabled:
 * - VP8 video + Opus audio with usedtx=1 parameter
 * - Browser sends camera + microphone to Dart
 * - Dart uses DtxProcessor to detect and fill gaps in audio
 * - Records to WebM file with DTX statistics
 *
 * Usage:
 *   # First, start the Dart server in another terminal:
 *   dart run interop/automated/save_to_disk_dtx_server.dart
 *
 *   # Then run browser tests:
 *   node interop/automated/save_to_disk_dtx_test.mjs [chrome|firefox|webkit|all]
 */

import { chromium, firefox, webkit } from 'playwright';
import { getBrowserArg } from './test_utils.mjs';

const SERVER_URL = 'http://localhost:8775';
const TEST_TIMEOUT = 90000;

async function runBrowserTest(browserType, browserName) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`Testing DTX Save to Disk: ${browserName}`);
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

    // Grant permissions (Chrome only - Firefox uses prefs above)
    const contextOptions = {
      permissions: browserName === 'chrome' ? ['camera', 'microphone'] : [],
    };

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

    console.log(`[${browserName}] Running DTX test (10 seconds)...`);
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
        }, 90000);
      });
    });

    console.log(`\n[${browserName}] Test Result:`);
    console.log(`  Success: ${result.success}`);
    console.log(`  Codec: ${result.codec || 'unknown'}`);
    console.log(`  Video Packets: ${result.videoPacketsReceived || 0}`);
    console.log(`  Audio Packets: ${result.audioPacketsReceived || 0}`);
    console.log(`  Speech Frames: ${result.speechFrames || 0}`);
    console.log(`  Comfort Noise Frames: ${result.comfortNoiseFrames || 0}`);
    console.log(`  DTX Frames Inserted: ${result.dtxFramesInserted || 0}`);
    console.log(`  DTX Periods: ${result.dtxPeriods || 0}`);
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

  console.log('WebRTC DTX Save to Disk Browser Test');
  console.log('====================================');
  console.log(`Server: ${SERVER_URL}`);
  console.log(`Browser: ${browserArg}`);

  try {
    const resp = await fetch(`${SERVER_URL}/status`);
    if (!resp.ok) throw new Error('Server not responding');
  } catch (e) {
    console.error('\nError: DTX server is not running!');
    console.error('Start it with: dart run interop/automated/save_to_disk_dtx_server.dart');
    process.exit(1);
  }

  const results = [];

  if (browserArg === 'all' || browserArg === 'chrome') {
    results.push(await runBrowserTest(chromium, 'chrome'));
  }

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

  console.log('\n' + '='.repeat(60));
  console.log('DTX SAVE TO DISK TEST SUMMARY');
  console.log('='.repeat(60));

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
      console.log(`       DTX: speech=${result.speechFrames || 0}, inserted=${result.dtxFramesInserted || 0}`);
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
