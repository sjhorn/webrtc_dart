// RED Audio Sendrecv (Echo) Playwright Test
//
// Tests RED (RFC 2198) codec negotiation and audio echo between browser and Dart
// Pattern: Dart is OFFERER (sendrecv), Browser is ANSWERER (sendrecv)
//
// Note: This test requires headless: false because audio tests need microphone
// access which cannot use canvas fallback like video tests.
//
// Usage:
//   dart run interop/automated/red_sendrecv_server.dart &
//   BROWSER=chrome node interop/automated/red_sendrecv_test.mjs

import {
  getBrowserArg,
  getBrowserType,
  closeBrowser,
  getLaunchOptions,
  getContextOptions,
} from './browser_utils.mjs';

const SERVER_URL = 'http://localhost:8778';
const TEST_TIMEOUT = 30000;

async function runTest(browserName) {
  console.log(`\n=== RED Audio Sendrecv Test (${browserName}) ===\n`);

  // For audio tests, we need headless: false (can't use canvas for audio)
  const { browserType } = getBrowserType(browserName);
  const launchOptions = getLaunchOptions(browserName, { headless: false });
  const contextOptions = getContextOptions(browserName);

  const browser = await browserType.launch(launchOptions);
  const context = await browser.newContext(contextOptions);
  const page = await context.newPage();

  try {
    // Collect console logs
    const logs = [];
    page.on('console', msg => {
      const text = msg.text();
      logs.push(text);
      if (text.includes('[') || text.includes('TEST_RESULT')) {
        console.log(`  [Browser] ${text}`);
      }
    });

    // Navigate to test page
    console.log(`Navigating to ${SERVER_URL}...`);
    await page.goto(SERVER_URL, { timeout: 10000 });

    // Wait for test to complete
    console.log('Waiting for test to complete...');

    let result = null;
    const startTime = Date.now();

    while (Date.now() - startTime < TEST_TIMEOUT) {
      result = await page.evaluate(() => window.testResult);
      if (result) break;
      await page.waitForTimeout(500);
    }

    if (!result) {
      throw new Error('Test timed out waiting for result');
    }

    // Print result
    console.log('\n--- Test Result ---');
    console.log(`  Browser: ${result.browser || browserName}`);
    console.log(`  Success: ${result.success}`);
    console.log(`  Packets Received: ${result.packetsReceived}`);
    console.log(`  Packets Echoed: ${result.packetsEchoed}`);
    console.log(`  Connection Time: ${result.connectionTimeMs}ms`);
    console.log(`  Codec: ${result.codec}`);

    if (result.success) {
      console.log(`\n✓ TEST PASSED (${browserName})\n`);
    } else {
      console.log(`\n✗ TEST FAILED (${browserName})`);
      if (result.error) {
        console.log(`  Error: ${result.error}`);
      }
    }

    return { browser: browserName, ...result };

  } catch (error) {
    console.error(`\n✗ TEST ERROR (${browserName}): ${error.message}\n`);
    return { browser: browserName, success: false, error: error.message };
  } finally {
    await closeBrowser({ browser, context, page });
  }
}

async function main() {
  const browserArg = getBrowserArg();

  console.log('RED Audio Sendrecv Test');
  console.log('=======================');
  console.log(`Server: ${SERVER_URL}`);
  console.log(`Browser: ${browserArg}`);
  console.log('Note: Audio tests require headless: false (no canvas fallback for audio)');

  const { browserName } = getBrowserType(browserArg);
  const result = await runTest(browserName);

  // Shutdown server
  try {
    await fetch(`${SERVER_URL}/shutdown`);
  } catch (e) {
    // Server may already be closed
  }

  process.exit(result.success ? 0 : 1);
}

main().catch(error => {
  console.error('Fatal error:', error);
  process.exit(1);
});
