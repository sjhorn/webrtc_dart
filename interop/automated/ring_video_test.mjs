/**
 * Automated Ring Video Streaming Test using Playwright
 *
 * Tests end-to-end video streaming from Ring camera:
 * 1. Dart connects to Ring camera (bundlePolicy: disable)
 * 2. Browser receives video via WebRTC
 * 3. Verifies video frames are received
 *
 * Prerequisites:
 *   1. Set RING_REFRESH_TOKEN environment variable
 *   2. Start Dart server: cd example/ring && source .env && dart run ring_video_server.dart
 *
 * Usage:
 *   node interop/automated/ring_video_test.mjs [chrome|firefox|webkit]
 */

import {
  getBrowserArg,
  launchBrowser,
  closeBrowser,
  setupConsoleLogging,
} from './browser_utils.mjs';

const HTTP_SERVER_URL = 'http://localhost:8080';
const STATUS_URL = `${HTTP_SERVER_URL}/status`;

async function waitForRingConnection(maxWaitMs = 30000) {
  console.log('[Test] Waiting for Ring camera connection...');
  const startTime = Date.now();

  while (Date.now() - startTime < maxWaitMs) {
    try {
      const resp = await fetch(STATUS_URL);
      const status = await resp.json();

      if (status.ringReceivingVideo) {
        console.log(`[Test] Ring camera connected and streaming video (${status.rtpPacketsReceived} packets)`);
        return true;
      }

      if (status.ringConnected) {
        console.log('[Test] Ring connected, waiting for video...');
      }
    } catch (e) {
      // Server might not be ready yet
    }

    await new Promise(r => setTimeout(r, 1000));
  }

  console.log('[Test] Timeout waiting for Ring camera');
  return false;
}

async function runBrowserTest(browserName) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`Testing: ${browserName}`);
  console.log('='.repeat(60));

  try {
    // Wait for Ring camera to be streaming
    const ringReady = await waitForRingConnection();
    if (!ringReady) {
      return {
        browser: browserName,
        success: false,
        error: 'Ring camera not streaming',
      };
    }

    // Launch browser
    console.log(`[${browserName}] Launching browser...`);
    const { browser, context, page } = await launchBrowser(browserName, { headless: true });
    setupConsoleLogging(page, browserName);

    try {
      // Navigate to test page
      console.log(`[${browserName}] Loading test page...`);
      await page.goto(HTTP_SERVER_URL, { timeout: 10000 });

      // Wait for test to complete
      console.log(`[${browserName}] Running video streaming test...`);
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

          // Timeout after 45 seconds
          setTimeout(() => {
            resolve({
              success: false,
              error: 'Test timeout waiting for video',
              videoFrameCount: window.videoFrameCount || 0,
            });
          }, 45000);
        });
      });

      // Print results
      console.log(`\n[${browserName}] Test Result:`);
      console.log(`  Success: ${result.success}`);
      console.log(`  Video frames received: ${result.videoFrameCount || 0}`);
      if (result.testDurationMs) {
        console.log(`  Test duration: ${result.testDurationMs}ms`);
      }
      if (result.connectionState) {
        console.log(`  Connection state: ${result.connectionState}`);
      }
      if (result.error) {
        console.log(`  Error: ${result.error}`);
      }

      return {
        browser: browserName,
        ...result,
      };

    } finally {
      await closeBrowser({ browser, context, page });
    }

  } catch (error) {
    console.error(`[${browserName}] Error: ${error.message}`);
    return {
      browser: browserName,
      success: false,
      error: error.message,
    };
  }
}

async function checkServerRunning() {
  try {
    const resp = await fetch(STATUS_URL);
    if (!resp.ok) throw new Error('Server not responding');
    return true;
  } catch (e) {
    return false;
  }
}

async function main() {
  // Support both: BROWSER=firefox node test.mjs OR node test.mjs firefox
  const browserArg = getBrowserArg() || 'chrome';

  console.log('Ring Video Streaming Browser Test');
  console.log('==================================');
  console.log(`Server: ${HTTP_SERVER_URL}`);
  console.log(`Browser: ${browserArg}`);

  // Check server is running
  const serverRunning = await checkServerRunning();
  if (!serverRunning) {
    console.error('\nError: Ring video server is not running!');
    console.error('Start it with:');
    console.error('  export RING_REFRESH_TOKEN="your_token"');
    console.error('  dart run interop/automated/ring_video_server.dart');
    process.exit(1);
  }

  console.log('[Test] Ring video server is running');

  const results = [];

  // Run tests based on argument
  if (browserArg === 'all' || browserArg === 'chrome') {
    results.push(await runBrowserTest('chrome'));
  }

  // Firefox skipped - H264 not available in headless Playwright
  // (verified: TypeScript werift has the same issue)
  if (browserArg === 'firefox') {
    console.log('\n[Test] Skipping Firefox - H264 codec not available in headless mode');
  }

  if (browserArg === 'all' || browserArg === 'webkit' || browserArg === 'safari') {
    results.push(await runBrowserTest('safari'));
  }

  // Print summary
  console.log('\n' + '='.repeat(60));
  console.log('SUMMARY');
  console.log('='.repeat(60));

  let allPassed = true;
  for (const result of results) {
    const status = result.success ? '\u2713 PASS' : '\u2717 FAIL';
    const frames = result.videoFrameCount ? ` (${result.videoFrameCount} frames)` : '';
    console.log(`${status} - ${result.browser}${frames}`);
    if (!result.success) {
      allPassed = false;
      if (result.error) {
        console.log(`       Error: ${result.error}`);
      }
    }
  }

  console.log('='.repeat(60));

  if (allPassed) {
    console.log('\nRing video streaming test PASSED!');
    process.exit(0);
  } else {
    console.log('\nRing video streaming test FAILED!');
    process.exit(1);
  }
}

main().catch(e => {
  console.error('Fatal error:', e);
  process.exit(1);
});
