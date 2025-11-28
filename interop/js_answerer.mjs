/**
 * JavaScript Answerer (werift-webrtc)
 * Waits for offer.json, creates answer, writes answer.json
 * Receives datachannel messages and echoes them back
 */

import { RTCPeerConnection } from "../werift-webrtc/packages/webrtc/lib/index.mjs";
import fs from "fs";
import path from "path";
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const SIGNALS_DIR = path.join(__dirname, "signals");
const OFFER_FILE = path.join(SIGNALS_DIR, "offer.json");
const ANSWER_FILE = path.join(SIGNALS_DIR, "answer.json");
const DART_CANDIDATES_FILE = path.join(SIGNALS_DIR, "candidates_dart.jsonl");
const JS_CANDIDATES_FILE = path.join(SIGNALS_DIR, "candidates_js.jsonl");

console.log("[JS Answerer] __dirname:", __dirname);
console.log("[JS Answerer] SIGNALS_DIR:", SIGNALS_DIR);
console.log("[JS Answerer] OFFER_FILE:", OFFER_FILE);

console.log("[JS Answerer] Starting...");
console.log("[JS Answerer] Waiting for offer at:", OFFER_FILE);

// Watch for offer file
const checkOffer = () => {
  if (fs.existsSync(OFFER_FILE)) {
    handleOffer();
  } else {
    setTimeout(checkOffer, 100);
  }
};

async function handleOffer() {
  try {
    // Wait a bit to ensure file is fully written
    await new Promise(resolve => setTimeout(resolve, 100));

    const offerData = fs.readFileSync(OFFER_FILE, "utf8");
    const offer = JSON.parse(offerData);
    console.log("[JS Answerer] Received offer");
    console.log("[JS Answerer] Offer SDP:\n", offer.sdp);

    const pc = new RTCPeerConnection({});

    // Handle ICE candidates - write to file for exchange with Dart peer
    pc.onIceCandidate.subscribe((candidate) => {
      if (candidate) {
        console.log("[JS Answerer] ICE candidate:", candidate.candidate);

        // Write candidate to file (append mode, one JSON per line)
        const candidateJson = JSON.stringify({
          candidate: candidate.candidate,
          sdpMid: candidate.sdpMid,
          sdpMLineIndex: candidate.sdpMLineIndex,
          usernameFragment: candidate.usernameFragment,
        });
        fs.appendFileSync(JS_CANDIDATES_FILE, candidateJson + "\n");
      }
    });

    // Handle connection state changes
    pc.connectionStateChange.subscribe((state) => {
      console.log("[JS Answerer] Connection state:", state);
    });

    // Handle ICE connection state changes
    pc.iceConnectionStateChange.subscribe((state) => {
      console.log("[JS Answerer] ICE connection state:", state);
    });

    // Handle incoming datachannel
    pc.onDataChannel.subscribe((channel) => {
      console.log("[JS Answerer] DataChannel opened:", channel.label);

      channel.stateChanged.subscribe((state) => {
        console.log("[JS Answerer] DataChannel state:", state);
        if (state === "open") {
          console.log("[JS Answerer] Sending initial message");
          channel.send(Buffer.from("Hello from JavaScript/werift!"));
        }
      });

      channel.onMessage.subscribe((data) => {
        const message = data.toString();
        console.log("[JS Answerer] Received message:", message);

        // Echo back
        const response = `Echo: ${message}`;
        console.log("[JS Answerer] Sending response:", response);
        channel.send(Buffer.from(response));
      });
    });

    // Set remote description and create answer
    await pc.setRemoteDescription(offer);
    console.log("[JS Answerer] Remote description set");

    const answerPromise = pc.createAnswer();
    const answer = await answerPromise;
    await pc.setLocalDescription(answer);
    console.log("[JS Answerer] Local description set");
    console.log("[JS Answerer] Answer SDP:\n", answer.sdp);

    // Write answer to file
    fs.writeFileSync(ANSWER_FILE, JSON.stringify(answer, null, 2));
    console.log("[JS Answerer] Answer written to:", ANSWER_FILE);

    // Start polling for Dart candidates
    console.log("[JS Answerer] Starting to poll for Dart ICE candidates...");
    pollForCandidates(pc, DART_CANDIDATES_FILE);

    // Keep alive
    console.log("[JS Answerer] Ready to receive messages...");
  } catch (error) {
    console.error("[JS Answerer] Error:", error);
    process.exit(1);
  }
}

/**
 * Poll for ICE candidates from a file and add them to the peer connection
 */
function pollForCandidates(pc, candidatesFile) {
  let lastSize = 0;

  const interval = setInterval(async () => {
    if (!fs.existsSync(candidatesFile)) {
      return;
    }

    const content = fs.readFileSync(candidatesFile, "utf8");
    const currentSize = content.length;

    // Only process if file has grown
    if (currentSize > lastSize) {
      const lines = content.split("\n");

      // Process new lines
      for (const line of lines) {
        if (line.trim() === "") continue;

        try {
          const candidateData = JSON.parse(line);

          await pc.addIceCandidate(candidateData);
          console.log("[JS Answerer] Added remote ICE candidate:", candidateData.candidate);
        } catch (e) {
          // Ignore parse errors for incomplete lines
        }
      }

      lastSize = currentSize;
    }

    // Stop polling after connection is established
    if (pc.iceConnectionState === "connected" || pc.iceConnectionState === "completed") {
      clearInterval(interval);
      console.log("[JS Answerer] Stopped polling for candidates (connection established)");
    }
  }, 100);
}

checkOffer();
