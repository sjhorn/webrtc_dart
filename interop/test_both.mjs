import { chromium } from 'playwright';

const TEST_TIMEOUT = 30000;

async function testServer(url, name) {
  console.log(`\n=== Testing ${name} ===`);
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const context = await browser.newContext();
    const page = await context.newPage();

    page.on('console', msg => {
      const text = msg.text();
      if (!text.startsWith('TEST_RESULT:')) {
        console.log(`[${name}] ${text}`);
      }
    });

    await page.goto(url, { timeout: 10000 });

    const result = await page.evaluate(async () => {
      return new Promise((resolve) => {
        const check = () => {
          if (window.testResult) resolve(window.testResult);
          else setTimeout(check, 100);
        };
        check();
        setTimeout(() => resolve({ success: false, error: 'Timeout' }), 25000);
      });
    });

    console.log(`[${name}] Result: ${result.success ? 'PASS' : 'FAIL'}`);
    if (result.error) console.log(`[${name}] Error: ${result.error}`);
    return result.success;
  } catch (e) {
    console.log(`[${name}] Exception: ${e.message}`);
    return false;
  } finally {
    if (browser) await browser.close();
  }
}

async function main() {
  // Test 1: PC created in /start (should work)
  const test1 = await testServer('http://localhost:8786', 'PC-in-start');

  // Test 2: PC created in /connect (may fail)
  const test2 = await testServer('http://localhost:8787', 'PC-in-connect');

  console.log('\n=== SUMMARY ===');
  console.log(`PC-in-start:   ${test1 ? 'PASS' : 'FAIL'}`);
  console.log(`PC-in-connect: ${test2 ? 'PASS' : 'FAIL'}`);

  process.exit(test1 && test2 ? 0 : 1);
}

main();
