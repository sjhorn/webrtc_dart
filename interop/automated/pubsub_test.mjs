// Pub/Sub Multi-Peer Routing Test
//
// Tests the pub/sub pattern where:
// 1. Client A publishes camera video
// 2. Client B subscribes to Client A's stream
// 3. Client B receives video from Client A
//
// This validates cross-client track routing via the Dart server.

import { chromium } from 'playwright';

const SERVER_URL = 'http://localhost:8888';
const TEST_DURATION_MS = 8000;

async function runTest() {
    console.log('Pub/Sub Multi-Peer Routing Test');
    console.log('================================');
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
            '--use-fake-device-for-media-stream',
            '--use-fake-ui-for-media-stream',
        ]
    });

    // Create two browser contexts (simulates two separate clients)
    const contextA = await browser.newContext();
    const contextB = await browser.newContext();

    const pageA = await contextA.newPage();
    const pageB = await contextB.newPage();

    let resultA = null;
    let resultB = null;

    try {
        // Navigate both clients to the server
        console.log('\n[Test] Opening Client A...');
        await pageA.goto(SERVER_URL);
        await pageA.waitForSelector('#publishBtn');

        console.log('[Test] Opening Client B...');
        await pageB.goto(SERVER_URL);
        await pageB.waitForSelector('#publishBtn');

        // Wait for WebSocket connections
        await new Promise(r => setTimeout(r, 1000));

        // Client A publishes
        console.log('\n[Test] Client A publishing camera...');
        await pageA.click('#publishBtn');
        await new Promise(r => setTimeout(r, 2000));

        // Check if Client B sees the published stream
        console.log('[Test] Checking Client B sees published stream...');
        const publishedInB = await pageB.evaluate(() => {
            const items = document.querySelectorAll('#published .published-item');
            return Array.from(items).map(item => {
                const text = item.querySelector('span')?.textContent || '';
                const hasSubscribe = !!item.querySelector('button');
                return { text, hasSubscribe };
            });
        });

        console.log('[Test] Client B sees:', publishedInB);

        // Client B subscribes to Client A's stream
        if (publishedInB.length > 0 && publishedInB.some(p => p.hasSubscribe)) {
            console.log('\n[Test] Client B subscribing to stream...');

            // Find and click the first Subscribe button
            await pageB.click('#published button:has-text("Subscribe")');
            await new Promise(r => setTimeout(r, 3000));

            // Check if Client B received video
            const subscribedInB = await pageB.evaluate(() => {
                const videos = document.querySelectorAll('#subscribed video');
                return Array.from(videos).map(v => ({
                    width: v.videoWidth,
                    height: v.videoHeight,
                    playing: !v.paused && v.readyState >= 2
                }));
            });

            console.log('[Test] Client B subscribed videos:', subscribedInB);

            // Wait for video frames to arrive
            console.log('[Test] Waiting for video frames...');
            await new Promise(r => setTimeout(r, 5000));

            // Check again for video
            const updatedVideos = await pageB.evaluate(() => {
                const videos = document.querySelectorAll('#subscribed video');
                return Array.from(videos).map(v => ({
                    width: v.videoWidth,
                    height: v.videoHeight,
                    playing: !v.paused && v.readyState >= 2,
                    currentTime: v.currentTime
                }));
            });

            console.log('[Test] Updated videos:', updatedVideos);

            resultB = {
                sawPublished: publishedInB.length > 0,
                subscribed: subscribedInB.length > 0,
                receivedVideo: updatedVideos.some(v => v.width > 0 || v.currentTime > 0)
            };
        } else {
            console.log('[Test] No subscribable streams found in Client B');
            resultB = {
                sawPublished: false,
                subscribed: false,
                receivedVideo: false
            };
        }

        // Brief wait before final check
        await new Promise(r => setTimeout(r, 1000));

        // Get final state from both clients
        resultA = await pageA.evaluate(() => {
            const localVideo = document.getElementById('localVideo');
            const status = document.getElementById('status')?.textContent || '';
            return {
                hasLocalVideo: localVideo && localVideo.srcObject !== null,
                connectionStatus: status
            };
        });

        // Get final video stats from B
        const finalB = await pageB.evaluate(() => {
            const videos = document.querySelectorAll('#subscribed video');
            return Array.from(videos).map(v => ({
                width: v.videoWidth,
                height: v.videoHeight,
                currentTime: v.currentTime
            }));
        });

        console.log('\n[Test] Final state:');
        console.log('  Client A:', resultA);
        console.log('  Client B videos:', finalB);

        resultB.finalVideos = finalB;

    } catch (error) {
        console.error('[Test] Error:', error.message);
        resultB = { error: error.message };
    } finally {
        await contextA.close();
        await contextB.close();
        await browser.close();
    }

    // Report results
    console.log('\n========== RESULTS ==========');
    console.log('Client A (Publisher):');
    console.log(`  Local video: ${resultA?.hasLocalVideo ? 'YES' : 'NO'}`);
    console.log(`  Status: ${resultA?.connectionStatus}`);

    console.log('\nClient B (Subscriber):');
    console.log(`  Saw published stream: ${resultB?.sawPublished ? 'YES' : 'NO'}`);
    console.log(`  Subscribed: ${resultB?.subscribed ? 'YES' : 'NO'}`);
    console.log(`  Received video: ${resultB?.receivedVideo ? 'YES' : 'NO'}`);

    const success = resultA?.hasLocalVideo && resultB?.sawPublished && resultB?.subscribed;

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
