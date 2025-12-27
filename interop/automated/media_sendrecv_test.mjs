/**
 * Automated Media Sendrecv Browser Test using Playwright
 *
 * Tests WebRTC video echo (bidirectional):
 * - Browser sends camera video to Dart
 * - Dart receives and echoes video back
 * - Browser displays both local and echoed remote video
 *
 * Usage:
 *   # First, start the Dart media server in another terminal:
 *   dart run interop/automated/media_sendrecv_server.dart
 *
 *   # Then run browser tests:
 *   node interop/automated/media_sendrecv_test.mjs [chrome|firefox|webkit|all]
 *
 * Note: Firefox is skipped by default due to known ICE issues when Dart is offerer.
 */

import {
  getBrowserArg,
  getBrowserType,
  launchBrowser,
  closeBrowser,
  setupConsoleLogging,
  checkServer,
} from './browser_utils.mjs';

const SERVER_URL = 'http://localhost:8768';

async function runBrowserTest(browserName) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`Testing Media Sendrecv (Echo): ${browserName}`);
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
    console.log(`  Video Received by Dart: ${result.videoReceived || false}`);
    console.log(`  Packets Received by Dart: ${result.packetsReceived || 0}`);
    console.log(`  Echo Frames Received: ${result.remoteFramesReceived || 0}`);
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

  console.log('WebRTC Media Sendrecv (Echo) Browser Test');
  console.log('=========================================');
  console.log(`Server: ${SERVER_URL}`);
  console.log(`Browser: ${browserArg}`);

  await checkServer(SERVER_URL, 'dart run interop/automated/media_sendrecv_server.dart');

  const results = [];

  if (browserArg === 'all' || browserArg === 'chrome') {
    results.push(await runBrowserTest('chrome'));
  }

  // Skip Firefox by default due to ICE issues when Dart is offerer
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
  console.log('MEDIA SENDRECV (ECHO) TEST SUMMARY');
  console.log('='.repeat(60));

  for (const result of results) {
    if (result.skipped) {
      console.log(`- SKIP - ${result.browser} (${result.error})`);
      continue;
    }
    const status = result.success ? '✓ PASS' : '✗ FAIL';
    console.log(`${status} - ${result.browser}`);
    if (result.success) {
      console.log(`       Dart received: ${result.packetsReceived || 0} packets`);
      console.log(`       Echo frames: ${result.remoteFramesReceived || 0}`);
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
