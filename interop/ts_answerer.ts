/**
 * TypeScript Answerer (werift-webrtc)
 * Waits for offer.json, creates answer, writes answer.json
 * Receives datachannel messages and echoes them back
 */

import { RTCPeerConnection } from "../werift-webrtc/packages/webrtc/lib/index.mjs";
import * as fs from "fs";
import * as path from "path";

const SIGNALS_DIR = path.join(__dirname, "signals");
const OFFER_FILE = path.join(SIGNALS_DIR, "offer.json");
const ANSWER_FILE = path.join(SIGNALS_DIR, "answer.json");
const CANDIDATES_FILE = path.join(SIGNALS_DIR, "candidates_ts.json");

console.log("[TS Answerer] Starting...");
console.log("[TS Answerer] Waiting for offer at:", OFFER_FILE);

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
    const offerData = fs.readFileSync(OFFER_FILE, "utf8");
    const offer = JSON.parse(offerData);
    console.log("[TS Answerer] Received offer");
    console.log("[TS Answerer] Offer SDP:\n", offer.sdp);

    const pc = new RTCPeerConnection({});

    // Handle ICE candidates
    pc.onIceCandidate.subscribe((candidate) => {
      if (candidate) {
        console.log("[TS Answerer] ICE candidate:", candidate.candidate);
      }
      // For file-based signaling, we'll just log them
      // In a real scenario, these would be sent to the other peer
    });

    // Handle connection state changes
    pc.connectionStateChange.subscribe((state) => {
      console.log("[TS Answerer] Connection state:", state);
    });

    // Handle ICE connection state changes
    pc.iceConnectionStateChange.subscribe((state) => {
      console.log("[TS Answerer] ICE connection state:", state);
    });

    // Handle incoming datachannel
    pc.onDataChannel.subscribe((channel) => {
      console.log("[TS Answerer] DataChannel opened:", channel.label);

      channel.stateChanged.subscribe((state) => {
        console.log("[TS Answerer] DataChannel state:", state);
        if (state === "open") {
          console.log("[TS Answerer] Sending initial message");
          channel.send(Buffer.from("Hello from TypeScript!"));
        }
      });

      channel.onMessage.subscribe((data) => {
        const message = data.toString();
        console.log("[TS Answerer] Received message:", message);

        // Echo back
        const response = `Echo: ${message}`;
        console.log("[TS Answerer] Sending response:", response);
        channel.send(Buffer.from(response));
      });
    });

    // Set remote description and create answer
    await pc.setRemoteDescription(offer);
    console.log("[TS Answerer] Remote description set");

    const answerPromise = pc.createAnswer()!;
    const answer = await answerPromise;
    await pc.setLocalDescription(answer);
    console.log("[TS Answerer] Local description set");
    console.log("[TS Answerer] Answer SDP:\n", answer.sdp);

    // Write answer to file
    fs.writeFileSync(ANSWER_FILE, JSON.stringify(answer, null, 2));
    console.log("[TS Answerer] Answer written to:", ANSWER_FILE);

    // Keep alive
    console.log("[TS Answerer] Ready to receive messages...");
  } catch (error) {
    console.error("[TS Answerer] Error:", error);
    process.exit(1);
  }
}

checkOffer();
