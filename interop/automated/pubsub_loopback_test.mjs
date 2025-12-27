/**
 * Test Dart pub/sub with loopback (same client publishes and subscribes)
 * This mirrors how werift's example works.
 */

import { chromium } from 'playwright';

const SERVER_URL = 'http://localhost:8888';

async function testLoopback() {
  console.log('Pub/Sub Loopback Test');
  console.log('='.repeat(40));
  console.log(`Server: ${SERVER_URL}`);
  console.log();

  // Check if server is running
  try {
    await fetch(SERVER_URL);
  } catch (e) {
    console.log('Error: Pub/Sub server is not running!');
    console.log('Start it with: dart run example/mediachannel/pubsub/offer.dart');
    process.exit(1);
  }

  const browser = await chromium.launch({
    headless: true,
    args: [
      '--use-fake-ui-for-media-stream',
      '--use-fake-device-for-media-stream',
    ],
  });

  try {
    const context = await browser.newContext({
      permissions: ['camera'],
    });

    const page = await context.newPage();

    // Listen for console messages
    page.on('console', msg => console.log(`[Browser] ${msg.text()}`));

    // Open the page
    console.log('[Test] Opening page...');
    await page.goto(SERVER_URL);
    await page.waitForTimeout(2000);

    // Publish camera
    console.log('[Test] Publishing camera...');
    await page.click('#publishBtn');
    await page.waitForTimeout(3000);

    // Check for published stream
    const published = await page.$eval('#published', el => el.textContent);
    console.log('[Test] Published content:', published);

    // Subscribe to own stream (loopback)
    console.log('[Test] Subscribing to own stream (loopback)...');
    const subscribeBtn = await page.$('button:has-text("Subscribe")');
    if (subscribeBtn) {
      await subscribeBtn.click();
    } else {
      console.log('[Test] No subscribe button found');
      return;
    }
    await page.waitForTimeout(3000);

    // Check video elements
    const videos = await page.$$eval('#subscribed video', videos =>
      videos.map(v => ({
        width: v.videoWidth,
        height: v.videoHeight,
        currentTime: v.currentTime,
        readyState: v.readyState
      }))
    );
    console.log('[Test] Loopback videos:', JSON.stringify(videos, null, 2));

    // Wait for playback
    console.log('[Test] Waiting 10 seconds for video playback...');
    await page.waitForTimeout(5000);

    // Check WebRTC stats to see if packets are being received
    const rtcStats = await page.evaluate(() => {
      return new Promise(async (resolve) => {
        const stats = await pc.getStats();
        const result = {};
        stats.forEach(report => {
          if (report.type === 'inbound-rtp' && report.kind === 'video') {
            result.inbound = {
              packetsReceived: report.packetsReceived,
              bytesReceived: report.bytesReceived,
              framesDecoded: report.framesDecoded,
              framesReceived: report.framesReceived,
              keyFramesDecoded: report.keyFramesDecoded,
              frameWidth: report.frameWidth,
              frameHeight: report.frameHeight,
              packetsLost: report.packetsLost,
              pliCount: report.pliCount,
              firCount: report.firCount,
              nackCount: report.nackCount,
              decoderImplementation: report.decoderImplementation,
              codecId: report.codecId
            };
          }
          if (report.type === 'codec') {
            result.codec = result.codec || [];
            result.codec.push({
              id: report.id,
              mimeType: report.mimeType,
              payloadType: report.payloadType
            });
          }
        });
        resolve(result);
      });
    });
    console.log('[Test] WebRTC Stats:', JSON.stringify(rtcStats, null, 2));

    await page.waitForTimeout(5000);

    const videosAfter = await page.$$eval('#subscribed video', videos =>
      videos.map(v => ({
        width: v.videoWidth,
        height: v.videoHeight,
        currentTime: v.currentTime,
        readyState: v.readyState
      }))
    );
    console.log('[Test] Loopback videos after wait:', JSON.stringify(videosAfter, null, 2));

    // Determine result
    const hasPlayingVideo = videosAfter.some(v => v.currentTime > 0 && v.width > 0);
    console.log();
    console.log('='.repeat(40));
    console.log(`Dart Loopback Result: ${hasPlayingVideo ? 'VIDEO PLAYS' : 'VIDEO DOES NOT PLAY'}`);
    console.log('='.repeat(40));

  } finally {
    await browser.close();
  }
}

testLoopback().catch(console.error);
