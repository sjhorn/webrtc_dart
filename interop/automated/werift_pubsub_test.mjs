/**
 * Test werift's pub/sub example to compare with our implementation.
 *
 * Prerequisites:
 * 1. Start werift server: cd werift-webrtc && npx ts-node examples/mediachannel/pubsub/offer.ts
 * 2. Start HTTP server: cd werift-webrtc/examples/mediachannel/pubsub && python3 -m http.server 9999
 */

import { chromium } from 'playwright';

const HTTP_URL = 'http://localhost:9999/answer.html';
const WS_URL = 'ws://localhost:8888';

async function testWeriftPubSub() {
  console.log('werift Pub/Sub Test');
  console.log('='.repeat(40));
  console.log(`HTML: ${HTTP_URL}`);
  console.log(`WebSocket: ${WS_URL}`);
  console.log();

  // Launch with fake video device
  const browser = await chromium.launch({
    headless: true,
    args: [
      '--use-fake-ui-for-media-stream',
      '--use-fake-device-for-media-stream',
    ],
  });

  try {
    // Create two browser contexts (simulating two users)
    const contextA = await browser.newContext({
      permissions: ['camera'],
    });
    const contextB = await browser.newContext({
      permissions: ['camera'],
    });

    const pageA = await contextA.newPage();
    const pageB = await contextB.newPage();

    // Listen for console messages
    pageA.on('console', msg => console.log(`[A] ${msg.text()}`));
    pageB.on('console', msg => console.log(`[B] ${msg.text()}`));

    // Open Client A
    console.log('[Test] Opening Client A...');
    await pageA.goto(HTTP_URL);
    await pageA.waitForTimeout(2000);

    // Open Client B
    console.log('[Test] Opening Client B...');
    await pageB.goto(HTTP_URL);
    await pageB.waitForTimeout(2000);

    // Client A publishes
    console.log('[Test] Client A publishing...');
    await pageA.click('button:has-text("publish")');
    await pageA.waitForTimeout(3000);

    // Check if Client A sees the published stream (werift is single-client loopback!)
    const publishedItems = await pageA.$$eval('button:has-text("subscribe")', buttons =>
      buttons.map(b => b.parentElement?.textContent || '')
    );
    console.log('[Test] Client A sees published streams:', publishedItems);

    if (publishedItems.length === 0) {
      console.log('[Test] FAIL: Client A does not see any published streams');
      return;
    }

    // Client A subscribes to its OWN stream (loopback test)
    console.log('[Test] Client A subscribing to own stream (loopback)...');
    const subscribeBtn = await pageA.$('button:has-text("subscribe")');
    if (subscribeBtn) {
      await subscribeBtn.click();
    }
    await pageA.waitForTimeout(3000);

    // Check video elements on Client A
    const videos = await pageA.$$eval('video', videos =>
      videos.map(v => ({
        width: v.videoWidth,
        height: v.videoHeight,
        currentTime: v.currentTime,
        readyState: v.readyState
      }))
    );
    console.log('[Test] Client A loopback videos:', JSON.stringify(videos, null, 2));

    // Wait more for video to potentially play
    console.log('[Test] Waiting 10 seconds for video playback...');
    await pageA.waitForTimeout(10000);

    const videosAfter = await pageA.$$eval('video', videos =>
      videos.map(v => ({
        width: v.videoWidth,
        height: v.videoHeight,
        currentTime: v.currentTime,
        readyState: v.readyState
      }))
    );
    console.log('[Test] Client A loopback videos after wait:', JSON.stringify(videosAfter, null, 2));

    // Determine result
    const hasPlayingVideo = videosAfter.some(v => v.currentTime > 0 && v.width > 0);
    console.log();
    console.log('='.repeat(40));
    console.log(`werift Result: ${hasPlayingVideo ? 'VIDEO PLAYS' : 'VIDEO DOES NOT PLAY (currentTime=0)'}`);
    console.log('='.repeat(40));

  } finally {
    await browser.close();

    // Clean up
    console.log('\nCleaning up...');
  }
}

testWeriftPubSub().catch(console.error);
