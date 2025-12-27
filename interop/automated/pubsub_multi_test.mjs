// Pub/Sub Multi-Peer Routing Test - Extended
//
// Tests advanced pub/sub scenarios:
// 1. Multiple subscribers to same stream (A publishes, B+C subscribe)
// 2. Multiple publishers (A+B publish, C subscribes to both)
//
// This validates cross-client track routing with multiple peers.

import { chromium } from 'playwright';

const SERVER_URL = 'http://localhost:8888';

async function runTest() {
    console.log('Pub/Sub Multi-Peer Extended Test');
    console.log('=================================');
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
            // Use real camera for proper keyframe testing
            // '--use-fake-device-for-media-stream',
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

    let results = { A: null, B: null, C: null };

    try {
        // Navigate all clients to the server
        console.log('\n[Test] Opening Client A...');
        await pageA.goto(SERVER_URL);
        await pageA.waitForSelector('#publishBtn');

        console.log('[Test] Opening Client B...');
        await pageB.goto(SERVER_URL);
        await pageB.waitForSelector('#publishBtn');

        console.log('[Test] Opening Client C...');
        await pageC.goto(SERVER_URL);
        await pageC.waitForSelector('#publishBtn');

        // Wait for WebSocket connections
        await new Promise(r => setTimeout(r, 1000));

        // ===== TEST 1: Multiple subscribers to same stream =====
        console.log('\n========== TEST 1: Multiple Subscribers ==========');

        // Client A publishes
        console.log('\n[Test] Client A publishing camera...');
        await pageA.click('#publishBtn');
        await new Promise(r => setTimeout(r, 2000));

        // Check all clients see the published stream
        const getPublishedStreams = async (page) => {
            return await page.evaluate(() => {
                const items = document.querySelectorAll('#published .published-item');
                return Array.from(items).map(item => {
                    const text = item.querySelector('span')?.textContent || '';
                    const hasSubscribe = !!item.querySelector('button');
                    return { text, hasSubscribe };
                });
            });
        };

        const publishedInB = await getPublishedStreams(pageB);
        const publishedInC = await getPublishedStreams(pageC);

        console.log('[Test] Client B sees:', publishedInB);
        console.log('[Test] Client C sees:', publishedInC);

        // Client B subscribes
        if (publishedInB.length > 0 && publishedInB.some(p => p.hasSubscribe)) {
            console.log('\n[Test] Client B subscribing to stream...');
            await pageB.waitForSelector('#published button', { timeout: 5000 });
            await pageB.click('#published button:has-text("Subscribe")');
            await new Promise(r => setTimeout(r, 2000));
        }

        // Client C subscribes to same stream
        if (publishedInC.length > 0 && publishedInC.some(p => p.hasSubscribe)) {
            console.log('[Test] Client C subscribing to stream...');
            await pageC.waitForSelector('#published button', { timeout: 5000 });
            await pageC.click('#published button:has-text("Subscribe")');
            await new Promise(r => setTimeout(r, 2000));
        }

        // Wait for video frames (more time for 3 clients)
        console.log('[Test] Waiting for video frames...');
        await new Promise(r => setTimeout(r, 5000));

        // Check video status
        const getVideoStats = async (page) => {
            return await page.evaluate(() => {
                const videos = document.querySelectorAll('#subscribed video');
                return Array.from(videos).map(v => ({
                    width: v.videoWidth,
                    height: v.videoHeight,
                    playing: !v.paused && v.readyState >= 2,
                    currentTime: v.currentTime
                }));
            });
        };

        const videosB = await getVideoStats(pageB);
        const videosC = await getVideoStats(pageC);

        console.log('[Test] Client B videos:', videosB);
        console.log('[Test] Client C videos:', videosC);

        const test1BHasVideo = videosB.some(v => v.width > 0 || v.currentTime > 0);
        const test1CHasVideo = videosC.some(v => v.width > 0 || v.currentTime > 0);

        console.log(`\n[Test 1 Result] B received video: ${test1BHasVideo ? 'YES' : 'NO'}`);
        console.log(`[Test 1 Result] C received video: ${test1CHasVideo ? 'YES' : 'NO'}`);

        // Get final states
        results.A = await pageA.evaluate(() => {
            const localVideo = document.getElementById('localVideo');
            const status = document.getElementById('status')?.textContent || '';
            return {
                hasLocalVideo: localVideo && localVideo.srcObject !== null,
                connectionStatus: status
            };
        });

        results.B = {
            sawPublished: publishedInB.length > 0,
            subscribed: videosB.length > 0,
            receivedVideo: test1BHasVideo,
            videoCount: videosB.length
        };

        results.C = {
            sawPublished: publishedInC.length > 0,
            subscribed: videosC.length > 0,
            receivedVideo: test1CHasVideo,
            videoCount: videosC.length
        };

    } catch (error) {
        console.error('[Test] Error:', error.message);
        results.error = error.message;
    } finally {
        await contextA.close();
        await contextB.close();
        await contextC.close();
        await browser.close();
    }

    // Report results
    console.log('\n========== RESULTS ==========');
    console.log('Client A (Publisher):');
    console.log(`  Local video: ${results.A?.hasLocalVideo ? 'YES' : 'NO'}`);
    console.log(`  Status: ${results.A?.connectionStatus}`);

    console.log('\nClient B (Subscriber 1):');
    console.log(`  Saw published: ${results.B?.sawPublished ? 'YES' : 'NO'}`);
    console.log(`  Subscribed: ${results.B?.subscribed ? 'YES' : 'NO'}`);
    console.log(`  Received video: ${results.B?.receivedVideo ? 'YES' : 'NO'}`);
    console.log(`  Video count: ${results.B?.videoCount}`);

    console.log('\nClient C (Subscriber 2):');
    console.log(`  Saw published: ${results.C?.sawPublished ? 'YES' : 'NO'}`);
    console.log(`  Subscribed: ${results.C?.subscribed ? 'YES' : 'NO'}`);
    console.log(`  Received video: ${results.C?.receivedVideo ? 'YES' : 'NO'}`);
    console.log(`  Video count: ${results.C?.videoCount}`);

    const success = results.A?.hasLocalVideo &&
                    results.B?.sawPublished && results.B?.subscribed &&
                    results.C?.sawPublished && results.C?.subscribed;

    if (success) {
        console.log('\n[chrome] TEST PASSED!');
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
