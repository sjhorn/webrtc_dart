// Simulcast SFU Fanout Test
//
// Tests the SFU pattern where:
// 1. Browser sends simulcast video (high/mid/low layers)
// 2. Dart SFU receives and forwards each layer to separate senders
// 3. Browser receives forwarded video on output transceivers

import { chromium, firefox, webkit } from 'playwright';

const SERVER_URL = 'http://localhost:8781';
const TEST_DURATION_MS = 8000;

async function runTest(browserType) {
    console.log(`\n============================================================`);
    console.log(`Testing SFU Fanout: ${browserType}`);
    console.log(`============================================================`);

    const browser = browserType === 'chrome' ? chromium :
                    browserType === 'firefox' ? firefox : webkit;

    const context = await browser.launch({
        headless: true,
        args: browserType === 'chrome' ? [
            '--use-fake-device-for-media-stream',
            '--use-fake-ui-for-media-stream',
        ] : undefined
    });

    const page = await context.newPage();

    // Navigate to server HTML page first (needed for getUserMedia)
    await page.goto(`${SERVER_URL}/`);

    // Inject test logic
    const result = await page.evaluate(async ({ serverUrl, testDuration }) => {
        const log = (msg, level = 'info') => {
            console.log(`[SFU-Test] ${msg}`);
            window.testLogs = window.testLogs || [];
            window.testLogs.push({ msg, level, time: Date.now() });
        };

        try {
            // Start the server-side peer
            log('Starting SFU server...');
            const startRes = await fetch(`${serverUrl}/start?browser=${navigator.userAgent.includes('Chrome') ? 'chrome' : 'other'}`);
            if (!startRes.ok) throw new Error('Failed to start server');

            // Get offer from server
            log('Getting offer from Dart SFU...');
            const offerRes = await fetch(`${serverUrl}/offer`);
            const offerData = await offerRes.json();
            log(`Offer received, sdp length: ${offerData.sdp.length}`);

            // Check for simulcast in offer
            const hasRid = offerData.sdp.includes('a=rid:');
            const hasSimulcast = offerData.sdp.includes('a=simulcast:');
            log(`Offer has RID: ${hasRid}, Simulcast: ${hasSimulcast}`);

            // Create browser peer connection
            const pc = new RTCPeerConnection({
                iceServers: [{ urls: 'stun:stun.l.google.com:19302' }]
            });

            let iceState = 'new';
            let connectionState = 'new';
            let tracksReceived = 0;

            pc.oniceconnectionstatechange = () => {
                iceState = pc.iceConnectionState;
                log(`ICE state: ${iceState}`);
            };

            pc.onconnectionstatechange = () => {
                connectionState = pc.connectionState;
                log(`Connection state: ${connectionState}`);
            };

            pc.ontrack = (e) => {
                tracksReceived++;
                log(`Received track: kind=${e.track.kind}, id=${e.track.id}`);
            };

            // Send ICE candidates to server
            pc.onicecandidate = async (e) => {
                if (e.candidate) {
                    await fetch(`${serverUrl}/candidate`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ candidate: e.candidate.candidate })
                    });
                }
            };

            // Set remote description (offer from Dart)
            await pc.setRemoteDescription(new RTCSessionDescription(offerData));
            log('Remote description set');

            // Get camera with simulcast (with canvas fallback for Safari)
            log('Getting camera stream...');
            let stream;
            try {
                stream = await navigator.mediaDevices.getUserMedia({
                    video: { width: 1280, height: 720 }
                });
                log('Got camera stream');
            } catch (e) {
                log('Camera unavailable, using canvas fallback: ' + e.message);
                // Create canvas stream as fallback
                const canvas = document.createElement('canvas');
                canvas.width = 1280;
                canvas.height = 720;
                const ctx = canvas.getContext('2d');
                let frame = 0;
                function draw() {
                    ctx.fillStyle = '#1a1a2e';
                    ctx.fillRect(0, 0, 1280, 720);
                    const x = 640 + Math.sin(frame * 0.05) * 200;
                    const y = 360 + Math.cos(frame * 0.03) * 150;
                    ctx.beginPath();
                    ctx.arc(x, y, 50, 0, Math.PI * 2);
                    ctx.fillStyle = '#ff6b6b';
                    ctx.fill();
                    frame++;
                    requestAnimationFrame(draw);
                }
                draw();
                stream = canvas.captureStream(30);
                log('Canvas stream created');
            }

            // Add video track
            const videoTrack = stream.getVideoTracks()[0];
            const sender = pc.addTrack(videoTrack, stream);

            // Create answer
            const answer = await pc.createAnswer();
            await pc.setLocalDescription(answer);
            log('Created and set local answer');

            // Send answer to server
            await fetch(`${serverUrl}/answer`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ type: 'answer', sdp: answer.sdp })
            });
            log('Sent answer to Dart SFU');

            // Get ICE candidates from server
            await new Promise(r => setTimeout(r, 500));
            const candRes = await fetch(`${serverUrl}/candidates`);
            const candidates = await candRes.json();
            log(`Received ${candidates.length} ICE candidates from server`);
            for (const c of candidates) {
                try {
                    await pc.addIceCandidate(new RTCIceCandidate(c));
                } catch (e) {
                    log(`Failed to add candidate: ${e.message}`, 'warn');
                }
            }

            // Wait for connection
            log('Waiting for connection...');
            await new Promise((resolve, reject) => {
                const checkConnection = () => {
                    if (connectionState === 'connected') {
                        resolve();
                    } else if (connectionState === 'failed') {
                        reject(new Error('Connection failed'));
                    } else {
                        setTimeout(checkConnection, 100);
                    }
                };
                checkConnection();
                setTimeout(() => reject(new Error('Connection timeout')), 10000);
            });
            log('Connection established!');

            // Wait for test duration and poll status
            log(`Running test for ${testDuration/1000} seconds...`);
            let lastStatus = null;
            for (let i = 0; i < testDuration / 1000; i++) {
                await new Promise(r => setTimeout(r, 1000));
                const statusRes = await fetch(`${serverUrl}/status`);
                lastStatus = await statusRes.json();
                log(`Status: forwarded=${lastStatus.rtpPacketsForwarded}, layers=${JSON.stringify(lastStatus.layersReceived)}`);
            }

            // Clean up
            pc.close();
            stream.getTracks().forEach(t => t.stop());

            return {
                success: lastStatus && lastStatus.rtpPacketsForwarded > 0,
                hasRid,
                hasSimulcast,
                tracksReceived,
                packetsForwarded: lastStatus?.rtpPacketsForwarded || 0,
                layersReceived: lastStatus?.layersReceived || {},
                sfuPattern: lastStatus?.sfuPattern,
                logs: window.testLogs
            };
        } catch (error) {
            return {
                success: false,
                error: error.message,
                logs: window.testLogs
            };
        }
    }, { serverUrl: SERVER_URL, testDuration: TEST_DURATION_MS });

    await context.close();

    // Print results
    console.log(`\n[${browserType}] Test Result:`);
    console.log(`  Success: ${result.success}`);
    console.log(`  RID in offer: ${result.hasRid}`);
    console.log(`  Simulcast in offer: ${result.hasSimulcast}`);
    console.log(`  Tracks received by browser: ${result.tracksReceived}`);
    console.log(`  Packets forwarded by SFU: ${result.packetsForwarded}`);
    console.log(`  Layers received: ${JSON.stringify(result.layersReceived)}`);
    console.log(`  SFU pattern: ${result.sfuPattern}`);
    if (result.error) {
        console.log(`  Error: ${result.error}`);
    }

    return result;
}

async function main() {
    console.log('Simulcast SFU Fanout Test');
    console.log('=========================');
    console.log(`Server: ${SERVER_URL}`);

    // Check if server is running
    try {
        await fetch(`${SERVER_URL}/status`);
    } catch (e) {
        console.error('Error: SFU server is not running!');
        console.error('Start it with: dart run interop/automated/simulcast_sfu_server.dart');
        process.exit(1);
    }

    const browser = process.env.BROWSER || process.argv[2] || 'chrome';
    const result = await runTest(browser);

    if (result.success) {
        console.log(`\n[${browser}] TEST PASSED!`);
    } else {
        console.log(`\n[${browser}] TEST FAILED`);
        process.exit(1);
    }
}

main().catch(console.error);
