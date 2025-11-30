/**
 * Automated Browser Interop Test using Playwright
 *
 * This test:
 * 1. Starts the Dart signaling server
 * 2. Launches Chrome with Playwright
 * 3. Connects browser WebRTC to Dart peer
 * 4. Verifies DataChannel message exchange
 *
 * Prerequisites:
 *   npm install playwright
 *   npx playwright install chromium
 *
 * Usage:
 *   node interop/browser/test_browser.mjs
 */

import { chromium } from 'playwright';
import { spawn } from 'child_process';
import { setTimeout as sleep } from 'timers/promises';

const SERVER_PORT = 8080;
const SERVER_URL = `http://localhost:${SERVER_PORT}`;

async function main() {
    console.log('[Test] Starting Dart signaling server...');

    // Start Dart server
    const serverProcess = spawn('dart', ['run', 'interop/browser/server.dart'], {
        stdio: ['ignore', 'pipe', 'pipe'],
        cwd: process.cwd()
    });

    let serverOutput = '';
    serverProcess.stdout.on('data', (data) => {
        const text = data.toString();
        serverOutput += text;
        process.stdout.write(`[Server] ${text}`);
    });
    serverProcess.stderr.on('data', (data) => {
        process.stderr.write(`[Server ERR] ${data}`);
    });

    // Wait for server to start
    await sleep(3000);

    if (!serverOutput.includes('Listening on')) {
        console.error('[Test] Server failed to start');
        serverProcess.kill();
        process.exit(1);
    }

    console.log('[Test] Server started, launching browser...');

    let browser;
    try {
        // Launch browser
        // Disable mDNS ICE candidates to expose real IP addresses for local testing
        browser = await chromium.launch({
            headless: true,
            args: [
                '--use-fake-ui-for-media-stream',
                '--use-fake-device-for-media-stream',
                '--allow-insecure-localhost',
                '--disable-features=WebRtcHideLocalIpsWithMdns'
            ]
        });

        const context = await browser.newContext();
        const page = await context.newPage();

        // Collect console logs
        const logs = [];
        page.on('console', msg => {
            const text = msg.text();
            logs.push(text);
            console.log(`[Browser] ${text}`);
        });

        // Navigate to test page
        console.log('[Test] Loading test page...');
        await page.goto(SERVER_URL);
        await sleep(1000);

        // Click connect button
        console.log('[Test] Clicking Connect...');
        await page.click('#connectBtn');

        // Wait for connection and messages
        // Allow extra time for ICE retry rounds (3 rounds * 2s delay + 3s check each)
        console.log('[Test] Waiting for DataChannel to open...');

        const timeout = 45000;
        const startTime = Date.now();
        let dataChannelOpen = false;
        let messageReceived = false;
        let dartGreetingReceived = false;

        while (Date.now() - startTime < timeout) {
            await sleep(500);

            // Check logs for success indicators
            if (logs.some(l => l.includes('DataChannel OPEN'))) {
                dataChannelOpen = true;
                console.log('[Test] DataChannel opened!');
            }
            if (logs.some(l => l.includes('Received: Hello from Dart'))) {
                dartGreetingReceived = true;
                console.log('[Test] Received greeting from Dart!');
            }
            if (logs.some(l => l.includes('Received: Echo:'))) {
                messageReceived = true;
                console.log('[Test] Received echo from Dart!');
            }

            if (dataChannelOpen && dartGreetingReceived) {
                // Send a test message
                console.log('[Test] Sending test message...');
                await page.fill('#messageInput', 'Test message from browser');
                await page.click('#sendBtn');
                await sleep(2000);

                if (logs.some(l => l.includes('Echo: Test message'))) {
                    messageReceived = true;
                }
                break;
            }
        }

        // Results
        console.log('\n[Test] === Results ===');
        console.log(`[Test] DataChannel opened: ${dataChannelOpen ? 'YES' : 'NO'}`);
        console.log(`[Test] Dart greeting received: ${dartGreetingReceived ? 'YES' : 'NO'}`);
        console.log(`[Test] Echo message received: ${messageReceived ? 'YES' : 'NO'}`);

        if (dataChannelOpen && dartGreetingReceived && messageReceived) {
            console.log('\n[Test] SUCCESS: Browser <-> Dart WebRTC interop working!');
            process.exitCode = 0;
        } else {
            console.log('\n[Test] FAILURE: Interop test did not complete successfully');
            console.log('[Test] Browser logs:', logs);
            process.exitCode = 1;
        }

    } catch (e) {
        console.error('[Test] Error:', e);
        process.exitCode = 1;
    } finally {
        if (browser) {
            await browser.close();
        }
        serverProcess.kill();
        console.log('[Test] Cleanup complete');
    }
}

main().catch(e => {
    console.error('[Test] Fatal error:', e);
    process.exit(1);
});
