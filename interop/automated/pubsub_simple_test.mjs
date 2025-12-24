// Simple Pub/Sub Test - Single Client
// Tests that a single client can publish and see its own stream

import { chromium } from 'playwright';

const SERVER_URL = 'http://localhost:8888';

async function runTest() {
    console.log('Pub/Sub Simple Test - Single Client');
    console.log('====================================');

    const browser = await chromium.launch({
        headless: false,
        args: [
            '--use-fake-device-for-media-stream',
            '--use-fake-ui-for-media-stream',
        ]
    });

    const page = await browser.newPage();

    // Enable console logging
    page.on('console', msg => console.log(`[Browser] ${msg.text()}`));

    try {
        await page.goto(SERVER_URL);
        await page.waitForSelector('#publishBtn');

        console.log('[Test] Publishing camera...');
        await page.click('#publishBtn');

        // Wait for connection and track
        console.log('[Test] Waiting 5 seconds for media flow...');
        await new Promise(r => setTimeout(r, 5000));

        // Check state
        const state = await page.evaluate(() => {
            const status = document.getElementById('status')?.textContent || '';
            const localVideo = document.getElementById('localVideo');
            const published = document.querySelectorAll('#published .published-item');
            return {
                status,
                hasLocalVideo: localVideo && localVideo.srcObject !== null,
                localVideoWidth: localVideo?.videoWidth || 0,
                publishedCount: published.length,
                publishedItems: Array.from(published).map(p => p.textContent)
            };
        });

        console.log('[Test] State:', state);

        // Wait more
        await new Promise(r => setTimeout(r, 3000));

    } finally {
        await browser.close();
    }
}

runTest().catch(console.error);
