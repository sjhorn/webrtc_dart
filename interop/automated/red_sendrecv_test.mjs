// RED Audio Sendrecv (Echo) Playwright Test
//
// Tests RED (RFC 2198) codec negotiation and audio echo between browser and Dart
// Pattern: Dart is OFFERER (sendrecv), Browser is ANSWERER (sendrecv)
//
// Usage:
//   dart run interop/automated/red_sendrecv_server.dart &
//   BROWSER=chrome node interop/automated/red_sendrecv_test.mjs

import { chromium, firefox, webkit } from 'playwright';

const SERVER_URL = 'http://localhost:8778';
const TEST_TIMEOUT = 30000;

async function runTest(browserType, browserName) {
    console.log(`\n=== RED Audio Sendrecv Test (${browserName}) ===\n`);

    let browser;
    let context;
    let page;

    try {
        // Launch browser with permissions for microphone
        // Note: Safari headless can't access microphone, needs Web Audio API fallback
        browser = await browserType.launch({
            headless: false,
            args: browserName === 'chromium' ? [
                '--use-fake-device-for-media-stream',
                '--use-fake-ui-for-media-stream',
                '--autoplay-policy=no-user-gesture-required'
            ] : []
        });

        context = await browser.newContext({
            // Only chromium supports permissions grant
            ...(browserName === 'chromium' ? { permissions: ['microphone'] } : {}),
            // Firefox/WebKit specific settings
            ...(browserName !== 'chromium' ? {
                bypassCSP: true
            } : {})
        });

        page = await context.newPage();

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
            // Check for test result
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

        return result;

    } catch (error) {
        console.error(`\n✗ TEST ERROR (${browserName}): ${error.message}\n`);
        return { success: false, error: error.message };
    } finally {
        // Cleanup
        if (page) await page.close().catch(() => {});
        if (context) await context.close().catch(() => {});
        if (browser) await browser.close().catch(() => {});
    }
}

async function main() {
    const browserArg = process.env.BROWSER || process.argv[2] || 'chrome';

    let browserType;
    let browserName;

    switch (browserArg.toLowerCase()) {
        case 'chrome':
        case 'chromium':
            browserType = chromium;
            browserName = 'chromium';
            break;
        case 'firefox':
            browserType = firefox;
            browserName = 'firefox';
            break;
        case 'safari':
        case 'webkit':
            browserType = webkit;
            browserName = 'webkit';
            break;
        default:
            console.error(`Unknown browser: ${browserArg}`);
            process.exit(1);
    }

    console.log('RED Audio Sendrecv Test');
    console.log('=======================');
    console.log(`Server: ${SERVER_URL}`);
    console.log(`Browser: ${browserName}`);

    const result = await runTest(browserType, browserName);

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
