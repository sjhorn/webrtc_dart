// Pub/Sub Multi-Subscriber Test
//
// Tests the pub/sub pattern with multiple subscribers:
// 1. Client A publishes camera video
// 2. Client B subscribes to Client A's stream
// 3. Client C subscribes to Client A's stream
// 4. Both B and C receive video from Client A
//
// This validates multi-subscriber routing via the Dart SFU.

import { chromium } from 'playwright';

const SERVER_URL = 'http://localhost:8888';

async function runTest() {
    console.log('Pub/Sub Multi-Subscriber Test');
    console.log('==============================');
    console.log(`Server: ${SERVER_URL}`);

    // Check if server is running
    try {
        const res = await fetch(SERVER_URL);
        if (!res.ok) throw new Error('Server not responding');
    } catch (e) {
        console.error('Error: Pub/Sub server is not running!');
        console.error('Start it with: dart run example/mediachannel/pubsub/offer.dart');
        process.exit(1);
    }

    const browser = await chromium.launch({
        headless: false,
        args: [
            '--use-fake-ui-for-media-stream',
        ]
    });

    // Create three browser contexts (simulates three separate clients)
    const contextA = await browser.newContext();
    const contextB = await browser.newContext();
    const contextC = await browser.newContext();

    const pageA = await contextA.newPage();
    const pageB = await contextB.newPage();
    const pageC = await contextC.newPage();

    // Log browser console messages
    pageA.on('console', msg => console.log(`[Browser A] ${msg.text()}`));
    pageB.on('console', msg => console.log(`[Browser B] ${msg.text()}`));
    pageC.on('console', msg => console.log(`[Browser C] ${msg.text()}`));

    let resultA = null;
    let resultB = null;
    let resultC = null;

    try {
        // Navigate all clients to the server
        console.log('\n[Test] Opening Client A (Publisher)...');
        await pageA.goto(SERVER_URL);
        await pageA.waitForSelector('#publishBtn');

        console.log('[Test] Opening Client B (Subscriber 1)...');
        await pageB.goto(SERVER_URL);
        await pageB.waitForSelector('#publishBtn');

        console.log('[Test] Opening Client C (Subscriber 2)...');
        await pageC.goto(SERVER_URL);
        await pageC.waitForSelector('#publishBtn');

        // Wait for WebSocket connections
        await new Promise(r => setTimeout(r, 1000));

        // Client A publishes
        console.log('\n[Test] Client A publishing camera...');
        await pageA.click('#publishBtn');
        await new Promise(r => setTimeout(r, 2000));

        // Check if Clients B and C see the published stream
        console.log('[Test] Checking both subscribers see published stream...');

        const publishedInB = await pageB.evaluate(() => {
            const items = document.querySelectorAll('#published .published-item');
            return Array.from(items).map(item => ({
                text: item.querySelector('span')?.textContent || '',
                hasSubscribe: !!item.querySelector('button')
            }));
        });
        console.log('[Test] Client B sees:', publishedInB);

        const publishedInC = await pageC.evaluate(() => {
            const items = document.querySelectorAll('#published .published-item');
            return Array.from(items).map(item => ({
                text: item.querySelector('span')?.textContent || '',
                hasSubscribe: !!item.querySelector('button')
            }));
        });
        console.log('[Test] Client C sees:', publishedInC);

        // Both clients subscribe
        if (publishedInB.length > 0 && publishedInC.length > 0) {
            console.log('\n[Test] Client B subscribing to stream...');
            await pageB.waitForSelector('#published button', { timeout: 5000 });
            await pageB.click('#published button:has-text("Subscribe")');

            // Small delay between subscriptions
            await new Promise(r => setTimeout(r, 500));

            console.log('[Test] Client C subscribing to stream...');
            await pageC.waitForSelector('#published button', { timeout: 5000 });
            await pageC.click('#published button:has-text("Subscribe")');

            // Wait for video to arrive at both subscribers
            console.log('[Test] Waiting for video frames (12 seconds)...');

            // Check intermediate state
            await new Promise(r => setTimeout(r, 4000));
            console.log('[Test] Checking after 4s...');
            const earlyB = await pageB.evaluate(() => {
                const v = document.querySelector('#subscribed video');
                return v ? { width: v.videoWidth, height: v.videoHeight, currentTime: v.currentTime, muted: v.muted } : null;
            });
            const earlyC = await pageC.evaluate(() => {
                const v = document.querySelector('#subscribed video');
                return v ? { width: v.videoWidth, height: v.videoHeight, currentTime: v.currentTime, muted: v.muted } : null;
            });
            console.log('[Test] B after 4s:', earlyB);
            console.log('[Test] C after 4s:', earlyC);

            await new Promise(r => setTimeout(r, 8000));

            // Check video at both subscribers
            const videosB = await pageB.evaluate(() => {
                const videos = document.querySelectorAll('#subscribed video');
                return Array.from(videos).map(v => ({
                    width: v.videoWidth,
                    height: v.videoHeight,
                    playing: !v.paused && v.readyState >= 2,
                    currentTime: v.currentTime
                }));
            });
            console.log('[Test] Client B videos:', videosB);

            const videosC = await pageC.evaluate(() => {
                const videos = document.querySelectorAll('#subscribed video');
                return Array.from(videos).map(v => ({
                    width: v.videoWidth,
                    height: v.videoHeight,
                    playing: !v.paused && v.readyState >= 2,
                    currentTime: v.currentTime
                }));
            });
            console.log('[Test] Client C videos:', videosC);

            resultB = {
                sawPublished: publishedInB.length > 0,
                subscribed: videosB.length > 0,
                receivedVideo: videosB.some(v => v.width > 0 || v.currentTime > 0)
            };

            resultC = {
                sawPublished: publishedInC.length > 0,
                subscribed: videosC.length > 0,
                receivedVideo: videosC.some(v => v.width > 0 || v.currentTime > 0)
            };
        } else {
            console.log('[Test] No subscribable streams found');
            resultB = { sawPublished: false, subscribed: false, receivedVideo: false };
            resultC = { sawPublished: false, subscribed: false, receivedVideo: false };
        }

        // Get publisher state
        resultA = await pageA.evaluate(() => {
            const localVideo = document.getElementById('localVideo');
            const status = document.getElementById('status')?.textContent || '';
            return {
                hasLocalVideo: localVideo && localVideo.srcObject !== null,
                connectionStatus: status
            };
        });

    } catch (error) {
        console.error('[Test] Error:', error.message);
    } finally {
        await contextA.close();
        await contextB.close();
        await contextC.close();
        await browser.close();
    }

    // Report results
    console.log('\n========== RESULTS ==========');
    console.log('Client A (Publisher):');
    console.log(`  Local video: ${resultA?.hasLocalVideo ? 'YES' : 'NO'}`);
    console.log(`  Status: ${resultA?.connectionStatus}`);

    console.log('\nClient B (Subscriber 1):');
    console.log(`  Saw published stream: ${resultB?.sawPublished ? 'YES' : 'NO'}`);
    console.log(`  Subscribed: ${resultB?.subscribed ? 'YES' : 'NO'}`);
    console.log(`  Received video: ${resultB?.receivedVideo ? 'YES' : 'NO'}`);

    console.log('\nClient C (Subscriber 2):');
    console.log(`  Saw published stream: ${resultC?.sawPublished ? 'YES' : 'NO'}`);
    console.log(`  Subscribed: ${resultC?.subscribed ? 'YES' : 'NO'}`);
    console.log(`  Received video: ${resultC?.receivedVideo ? 'YES' : 'NO'}`);

    const success = resultA?.hasLocalVideo &&
                    resultB?.sawPublished && resultB?.subscribed && resultB?.receivedVideo &&
                    resultC?.sawPublished && resultC?.subscribed && resultC?.receivedVideo;

    if (success) {
        console.log('\n[chrome] TEST PASSED! Both subscribers received video.');
        return true;
    } else {
        console.log('\n[chrome] TEST FAILED');
        return false;
    }
}

runTest()
    .then(success => process.exit(success ? 0 : 1))
    .catch(err => {
        console.error('Fatal error:', err);
        process.exit(1);
    });
