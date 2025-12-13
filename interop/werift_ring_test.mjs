/**
 * Browser test for werift Ring video server (TypeScript).
 * Runs the same test as the Dart server to compare Firefox behavior.
 *
 * Usage:
 *   node werift_ring_test.mjs [chrome|firefox|webkit]
 */

import { chromium, firefox, webkit } from "playwright";

const browser_name = process.argv[2] || "chrome";
const PORT = 8080;

async function runTest() {
  console.log(`\n${"=".repeat(60)}`);
  console.log("werift Ring Video Streaming Browser Test (TypeScript)");
  console.log(`Browser: ${browser_name}`);
  console.log("=".repeat(60) + "\n");

  // Select browser
  let browserType;
  switch (browser_name) {
    case "firefox":
      browserType = firefox;
      break;
    case "webkit":
    case "safari":
      browserType = webkit;
      break;
    case "chrome":
    case "chromium":
    default:
      browserType = chromium;
      break;
  }

  const browser = await browserType.launch({
    headless: true,
    args: browser_name === "chrome" ? ["--use-fake-ui-for-media-stream"] : [],
  });

  // Firefox doesn't support camera/microphone permissions in Playwright
  // For receive-only video, we don't need these permissions anyway
  const context = await browser.newContext({
    permissions: browser_name === "chrome" ? ["camera", "microphone"] : [],
  });

  const page = await context.newPage();

  // Log console messages from browser
  page.on("console", (msg) => {
    const text = msg.text();
    console.log(`[${browser_name}] ${text}`);
  });

  try {
    console.log(`[${browser_name}] Launching browser...`);
    console.log(`[${browser_name}] Loading test page...`);

    await page.goto(`http://localhost:${PORT}/`, {
      waitUntil: "domcontentloaded",
      timeout: 30000,
    });

    console.log(`[${browser_name}] Running video streaming test...`);

    // Wait for test to complete
    const result = await page.waitForFunction(
      () => window.testResult !== undefined,
      { timeout: 60000 }
    );

    const testResult = await page.evaluate(() => window.testResult);

    console.log(`\n[${browser_name}] Test Result:`);
    console.log(`  Success: ${testResult.success}`);
    console.log(`  Video frames received: ${testResult.videoFrameCount}`);
    console.log(`  Connection state: ${testResult.connectionState}`);
    if (testResult.error) {
      console.log(`  Error: ${testResult.error}`);
    }

    await browser.close();

    if (testResult.success) {
      console.log(`\n✓ PASS - ${browser_name} (${testResult.videoFrameCount} frames)`);
      return { success: true, frames: testResult.videoFrameCount };
    } else {
      console.log(`\n✗ FAIL - ${browser_name}`);
      return { success: false, frames: testResult.videoFrameCount };
    }
  } catch (error) {
    console.error(`[${browser_name}] Test error:`, error.message);
    await browser.close();
    return { success: false, error: error.message };
  }
}

runTest().then((result) => {
  console.log("\n" + "=".repeat(60));
  console.log("SUMMARY");
  console.log("=".repeat(60));
  if (result.success) {
    console.log(`✓ PASS - ${browser_name} (${result.frames} frames)`);
    process.exit(0);
  } else {
    console.log(`✗ FAIL - ${browser_name}`);
    process.exit(1);
  }
});
