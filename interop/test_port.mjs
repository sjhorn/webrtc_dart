import { chromium } from 'playwright';

const port = process.argv[2] || '8788';
const SERVER_URL = `http://localhost:${port}`;
const TEST_TIMEOUT = 45000;

async function runTest() {
  console.log(`Testing: ${SERVER_URL}`);
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext();
  const page = await context.newPage();

  let testResult = null;
  page.on('console', msg => {
    const text = msg.text();
    console.log(`[Browser] ${text}`);
    if (text.startsWith('TEST_RESULT:')) {
      testResult = JSON.parse(text.substring('TEST_RESULT:'.length));
    }
  });

  await page.goto(SERVER_URL);
  
  const startTime = Date.now();
  while (!testResult && (Date.now() - startTime) < TEST_TIMEOUT) {
    await page.waitForTimeout(500);
  }

  await browser.close();

  if (testResult?.success) {
    console.log('\n✅ TEST PASSED');
    process.exit(0);
  } else {
    console.log('\n❌ TEST FAILED');
    console.log(JSON.stringify(testResult, null, 2));
    process.exit(1);
  }
}

runTest();
