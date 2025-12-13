// Ring Video Test - Browser automation
import { chromium } from 'playwright';

async function runTest() {
  console.log('Launching browser...');
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();

  page.on('console', msg => console.log('[Browser]', msg.text()));

  console.log('Navigating to http://localhost:8080...');
  await page.goto('http://localhost:8080');

  // Wait for test result (max 60 seconds)
  console.log('Waiting for test result...');
  try {
    await page.waitForFunction(() => window.testResult !== undefined, { timeout: 60000 });
    const result = await page.evaluate(() => window.testResult);
    console.log('Test result:', JSON.stringify(result, null, 2));
  } catch (e) {
    console.log('Timeout waiting for test result');
    // Get status from page
    const status = await page.evaluate(() => document.getElementById('status').textContent);
    console.log('Final status:', status);
  }

  await browser.close();
}

runTest().catch(console.error);
