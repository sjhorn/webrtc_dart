/**
 * Quick comparison test between passing and failing servers
 */

import { chromium } from 'playwright';

const PASS_URL = 'http://localhost:8786';
const FAIL_URL = 'http://localhost:8787';
const TEST_TIMEOUT = 30000;

async function runTest(serverUrl, testName) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`Testing: ${testName} at ${serverUrl}`);
  console.log('='.repeat(60));

  let browser;
  let page;
  let result = { success: false, error: null };

  try {
    browser = await chromium.launch({ headless: true });
    const context = await browser.newContext();
    page = await context.newPage();

    // Capture console messages
    page.on('console', msg => {
      console.log(`[Browser] ${msg.text()}`);
    });

    // Navigate to test page
    console.log(`[${testName}] Loading page...`);
    await page.goto(serverUrl);

    // Wait for test to complete
    console.log(`[${testName}] Waiting for test result...`);

    try {
      await page.waitForFunction(() => window.testResult !== undefined, {
        timeout: TEST_TIMEOUT
      });

      result = await page.evaluate(() => window.testResult);
      console.log(`[${testName}] Result:`, result);
    } catch (e) {
      result.error = `Timeout waiting for test result: ${e.message}`;
      console.log(`[${testName}] Error:`, result.error);

      // Try to get any partial result
      const partialResult = await page.evaluate(() => ({
        connectionState: window.pc?.connectionState,
        dcState: window.dc?.readyState,
        dcLabel: window.dc?.label
      }));
      console.log(`[${testName}] Partial state:`, partialResult);
    }

  } catch (e) {
    result.error = e.message;
    console.log(`[${testName}] Test error:`, e.message);
  } finally {
    if (browser) await browser.close();
  }

  return result;
}

async function main() {
  console.log('Comparison Test: PC in /start vs PC in /connect');
  console.log('================================================\n');

  // Test passing server (PC in /start)
  const passResult = await runTest(PASS_URL, 'PC_in_start');

  // Test failing server (PC in /connect)
  const failResult = await runTest(FAIL_URL, 'PC_in_connect');

  // Summary
  console.log('\n' + '='.repeat(60));
  console.log('SUMMARY');
  console.log('='.repeat(60));
  console.log(`PC in /start:   ${passResult.success ? 'PASS' : 'FAIL'}`);
  console.log(`PC in /connect: ${failResult.success ? 'PASS' : 'FAIL'}`);
}

main().catch(console.error);
