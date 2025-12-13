/**
 * TypeScript werift server for Ring video streaming to browser.
 * This is a comparison test to check Firefox behavior against our Dart implementation.
 *
 * Usage:
 *   cd werift-webrtc && npx ts-node ../interop/werift_ring_server.ts
 */

import { RingApi } from "ring-client-api";
import { Server } from "ws";
import { createServer } from "http";
import {
  MediaStreamTrack,
  RTCPeerConnection,
  RTCRtpCodecParameters,
} from "./packages/webrtc/src";

// Import CustomPeerConnection from ring example
import { CustomPeerConnection } from "./examples/ring/peer";

const PORT_HTTP = 8080;
const PORT_WS = 8888;

const html = `<!DOCTYPE html>
<html>
<head>
  <title>werift Ring Video Test</title>
  <style>
    body { font-family: monospace; padding: 20px; background: #1a1a2e; color: #eee; }
    video { width: 640px; height: 480px; background: #000; border: 2px solid #333; }
    #log { height: 300px; overflow-y: auto; background: #0d0d1a; padding: 10px; margin-top: 20px; font-size: 12px; }
    .success { color: #4caf50; }
    .error { color: #f44336; }
    .info { color: #2196f3; }
    #status { font-size: 18px; margin-bottom: 20px; }
  </style>
</head>
<body>
  <h1>werift Ring Video Test (TypeScript)</h1>
  <div id="status">Status: Initializing...</div>
  <video id="video" autoplay playsinline muted></video>
  <div id="log"></div>

  <script>
    let pc;
    let videoFrameCount = 0;
    let testStartTime = Date.now();

    function log(msg, className = 'info') {
      const logDiv = document.getElementById('log');
      const line = document.createElement('div');
      line.className = className;
      line.textContent = '[' + new Date().toISOString().substr(11, 12) + '] ' + msg;
      logDiv.appendChild(line);
      logDiv.scrollTop = logDiv.scrollHeight;
      console.log(msg);
    }

    function setStatus(msg) {
      document.getElementById('status').textContent = 'Status: ' + msg;
    }

    async function runTest() {
      try {
        log('Starting werift Ring video test...');
        setStatus('Connecting to WebSocket...');

        // Connect to WebSocket
        const socket = new WebSocket('ws://localhost:${PORT_WS}');
        await new Promise((resolve, reject) => {
          socket.onopen = resolve;
          socket.onerror = reject;
          setTimeout(() => reject(new Error('WebSocket timeout')), 10000);
        });
        log('WebSocket connected', 'success');

        // Wait for offer from server
        setStatus('Waiting for offer...');
        const offer = await new Promise((resolve, reject) => {
          socket.onmessage = (e) => resolve(JSON.parse(e.data));
          setTimeout(() => reject(new Error('Offer timeout')), 30000);
        });
        log('Received offer from werift server');

        // Create peer connection (empty iceServers for local testing)
        pc = new RTCPeerConnection({ iceServers: [] });

        pc.oniceconnectionstatechange = () => {
          log('ICE state: ' + pc.iceConnectionState,
              pc.iceConnectionState === 'connected' ? 'success' : 'info');
        };

        pc.onconnectionstatechange = () => {
          log('Connection state: ' + pc.connectionState,
              pc.connectionState === 'connected' ? 'success' : 'info');
        };

        // Handle incoming video track
        pc.ontrack = (e) => {
          log('Received video track!', 'success');
          const video = document.getElementById('video');
          video.srcObject = e.streams[0];

          // Monitor video frames
          if (video.requestVideoFrameCallback) {
            const countFrames = () => {
              videoFrameCount++;
              if (videoFrameCount % 30 === 0) {
                log('Video frames received: ' + videoFrameCount, 'info');
              }
              video.requestVideoFrameCallback(countFrames);
            };
            video.requestVideoFrameCallback(countFrames);
          }
        };

        // Log ICE events
        pc.onicecandidate = (e) => {
          if (e.candidate) {
            log('ICE candidate: ' + e.candidate.candidate.substr(0, 60) + '...');
          } else {
            log('ICE gathering complete');
          }
        };

        // Set remote description (offer)
        setStatus('Processing offer...');
        await pc.setRemoteDescription(new RTCSessionDescription(offer));
        log('Remote description set');

        // Create answer
        setStatus('Creating answer...');
        const answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        log('Local description set (answer)');

        // Wait for ICE gathering to complete
        await new Promise((resolve) => {
          if (pc.iceGatheringState === 'complete') {
            resolve();
          } else {
            pc.onicegatheringstatechange = () => {
              log('ICE gathering state: ' + pc.iceGatheringState);
              if (pc.iceGatheringState === 'complete') {
                resolve();
              }
            };
          }
          setTimeout(resolve, 5000);
        });

        log('ICE gathering done, sending answer');
        socket.send(JSON.stringify(pc.localDescription));
        log('Sent answer to server');

        setStatus('Waiting for video...');

        // Wait for video frames (timeout after 30 seconds)
        const videoReceived = await new Promise((resolve) => {
          const startWait = Date.now();
          const check = () => {
            if (videoFrameCount > 0) {
              resolve(true);
            } else if (Date.now() - startWait > 30000) {
              resolve(false);
            } else {
              setTimeout(check, 100);
            }
          };
          check();
        });

        // Wait for stability
        if (videoReceived) {
          log('Video streaming detected, waiting for stability...');
          await new Promise(r => setTimeout(r, 5000));
        }

        // Report results
        const testDuration = Date.now() - testStartTime;
        const result = {
          success: videoFrameCount > 10,
          videoFrameCount,
          testDurationMs: testDuration,
          connectionState: pc.connectionState,
          iceConnectionState: pc.iceConnectionState,
        };

        if (result.success) {
          log('TEST PASSED - Received ' + videoFrameCount + ' video frames!', 'success');
          setStatus('PASSED - ' + videoFrameCount + ' frames');
        } else {
          log('TEST FAILED - Only received ' + videoFrameCount + ' video frames', 'error');
          setStatus('FAILED - ' + videoFrameCount + ' frames');
        }

        log('Test Result:');
        log('  Success: ' + result.success);
        log('  Video frames received: ' + result.videoFrameCount);
        log('  Connection state: ' + result.connectionState);

        window.testResult = result;

      } catch (error) {
        log('Error: ' + error.message, 'error');
        setStatus('Error: ' + error.message);
        window.testResult = { success: false, error: error.message };
      }
    }

    runTest();
  </script>
</body>
</html>`;

async function main() {
  console.log("[werift] Starting Ring video server...");

  // Get Ring refresh token from environment
  const refreshToken = process.env.RING_REFRESH_TOKEN;
  if (!refreshToken) {
    console.error("ERROR: RING_REFRESH_TOKEN environment variable not set");
    console.error("Usage: RING_REFRESH_TOKEN='...' npx ts-node werift_ring_server.ts");
    process.exit(1);
  }

  // Initialize Ring API
  console.log("[werift] Connecting to Ring API...");
  const ringApi = new RingApi({
    refreshToken,
    debug: false,
  });

  const cameras = await ringApi.getCameras();
  if (cameras.length === 0) {
    console.error("[werift] No cameras found");
    process.exit(1);
  }

  const camera = cameras[0];
  console.log(`[werift] Found camera: ${camera.name}`);

  // Create video track for forwarding
  const track = new MediaStreamTrack({ kind: "video" });
  let rtpPacketCount = 0;

  // Create Ring peer connection
  const ring = new CustomPeerConnection();
  ring.onVideoRtp.subscribe((rtp) => {
    rtpPacketCount++;
    track.writeRtp(rtp);
    if (rtpPacketCount <= 5 || rtpPacketCount % 100 === 0) {
      console.log(`[werift] Ring RTP packets: ${rtpPacketCount}`);
    }
  });

  // Start Ring live call
  console.log("[werift] Starting Ring live call...");
  await camera.startLiveCall({
    createPeerConnection: () => ring,
  });

  // HTTP server for test page
  const httpServer = createServer((req, res) => {
    if (req.url === "/" || req.url === "/index.html") {
      res.writeHead(200, { "Content-Type": "text/html" });
      res.end(html);
    } else if (req.url === "/status") {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({
        ringConnected: rtpPacketCount > 0,
        rtpPacketCount,
      }));
    } else {
      res.writeHead(404);
      res.end("Not found");
    }
  });
  httpServer.listen(PORT_HTTP);
  console.log(`[werift] HTTP server on http://localhost:${PORT_HTTP}`);

  // WebSocket server for browser clients
  const wsServer = new Server({ port: PORT_WS });
  console.log(`[werift] WebSocket server on ws://localhost:${PORT_WS}`);

  wsServer.on("connection", async (socket) => {
    const clientId = Date.now();
    console.log(`[Browser:${clientId}] WebSocket connected`);

    // Create peer connection for browser
    const pc = new RTCPeerConnection({
      codecs: {
        video: [
          new RTCRtpCodecParameters({
            mimeType: "video/H264",
            clockRate: 90000,
            rtcpFeedback: [
              { type: "transport-cc" },
              { type: "ccm", parameter: "fir" },
              { type: "nack" },
              { type: "nack", parameter: "pli" },
              { type: "goog-remb" },
            ],
          }),
        ],
      },
    });

    // Add video track (sendonly to browser)
    pc.addTransceiver(track, { direction: "sendonly" });

    // Track connection state
    pc.onConnectionStateChange.subscribe((state) => {
      console.log(`[Browser:${clientId}] Connection state: ${state}`);
    });

    // Create and send offer
    await pc.setLocalDescription(await pc.createOffer());
    const offer = JSON.stringify(pc.localDescription);
    socket.send(offer);
    console.log(`[Browser:${clientId}] Sent offer`);

    // Handle answer from browser
    socket.on("message", async (data: any) => {
      try {
        const answer = JSON.parse(data.toString());
        console.log(`[Browser:${clientId}] Received answer`);
        await pc.setRemoteDescription(answer);
        console.log(`[Browser:${clientId}] Remote description set`);
      } catch (e) {
        console.error(`[Browser:${clientId}] Error:`, e);
      }
    });

    socket.on("close", () => {
      console.log(`[Browser:${clientId}] WebSocket closed`);
      pc.close();
    });
  });

  console.log("[werift] Ready. Press Ctrl+C to stop.");
}

main().catch((e) => {
  console.error("[werift] Fatal error:", e);
  process.exit(1);
});
