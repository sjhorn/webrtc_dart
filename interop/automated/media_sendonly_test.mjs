/**
 * Automated Media Sendonly Browser Test using Playwright
 *
 * Tests WebRTC video streaming from Dart to browser:
 * - Dart (webrtc_dart) sends video via FFmpeg testsrc
 * - Browser receives and displays video
 *
 * Usage:
 *   # First, start the Dart media server in another terminal:
 *   dart run interop/automated/media_sendonly_server.dart
 *
 *   # Then run browser tests:
 *   node interop/automated/media_sendonly_test.mjs [chrome|firefox|webkit|all]
 */

import { chromium, firefox, webkit } from 'playwright';

const SERVER_URL = 'http://localhost:8766';
const TEST_TIMEOUT = 60000;

async function runBrowserTest(browserType, browserName) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`Testing Media Sendonly: ${browserName}`);
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
        '--autoplay-policy=no-user-gesture-required',
      ] : [],
    });

    const contextOptions = browserName === 'chrome'
      ? { permissions: ['microphone', 'camera'] }
      : {};
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

        // Timeout after 45 seconds (video tests take longer)
        setTimeout(() => {
          resolve({ success: false, error: 'Test timeout' });
        }, 45000);
      });
    });

    // Print results
    console.log(`\n[${browserName}] Test Result:`);
    console.log(`  Success: ${result.success}`);
    console.log(`  Video Received: ${result.videoReceived || false}`);
    console.log(`  Frames Received: ${result.framesReceived || 0}`);
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
  const args = process.argv.slice(2);
  const browserArg = args[0] || 'all';

  console.log('WebRTC Media Sendonly Browser Test');
  console.log('===================================');
  console.log(`Server: ${SERVER_URL}`);
  console.log(`Browser: ${browserArg}`);

  // Check server is running
  try {
    const resp = await fetch(`${SERVER_URL}/status`);
    if (!resp.ok) throw new Error('Server not responding');
  } catch (e) {
    console.error('\nError: Media sendonly server is not running!');
    console.error('Start it with: dart run interop/automated/media_sendonly_server.dart');
    process.exit(1);
  }

  const results = [];

  // Run tests based on argument
  if (browserArg === 'all' || browserArg === 'chrome') {
    results.push(await runBrowserTest(chromium, 'chrome'));
  }

  if (browserArg === 'all' || browserArg === 'firefox') {
    results.push(await runBrowserTest(firefox, 'firefox'));
  }

  if (browserArg === 'all' || browserArg === 'webkit' || browserArg === 'safari') {
    results.push(await runBrowserTest(webkit, 'safari'));
  }

  // Print summary
  console.log('\n' + '='.repeat(60));
  console.log('MEDIA SENDONLY TEST SUMMARY');
  console.log('='.repeat(60));

  let allPassed = true;
  for (const result of results) {
    const status = result.success ? '✓ PASS' : '✗ FAIL';
    console.log(`${status} - ${result.browser}`);
    if (result.success) {
      console.log(`       Frames: ${result.framesReceived || 0}`);
    }
    if (!result.success) {
      allPassed = false;
      if (result.error) {
        console.log(`       Error: ${result.error}`);
      }
    }
  }

  console.log('='.repeat(60));

  if (allPassed) {
    console.log('\nAll media sendonly tests PASSED!');
    process.exit(0);
  } else {
    console.log('\nSome media sendonly tests FAILED!');
    process.exit(1);
  }
}

main().catch(e => {
  console.error('Fatal error:', e);
  process.exit(1);
});
