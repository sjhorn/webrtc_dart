# This is an improved README for the original typescript werift-webrtc library
# 🌐 werift - WebRTC for Node.js

**werift** (WebRTC Implementation for TypeScript) is a pure TypeScript implementation of WebRTC for Node.js. No native dependencies, no browser required — just install and go!

[![npm version](https://img.shields.io/npm/v/werift.svg)](https://www.npmjs.com/package/werift)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## ✨ What is werift?

werift lets you build WebRTC applications entirely in Node.js. Whether you're creating a media server, an SFU (Selective Forwarding Unit), a signaling server, or peer-to-peer data channels — werift has you covered.

Unlike browser-based WebRTC, werift gives you direct access to RTP packets, making it perfect for building custom media servers, recording solutions, and real-time communication backends.

## 🚀 Quick Start

### Installation

```bash
npm install werift
```

> **Requirements:** Node.js 16 or higher

### Your First DataChannel

Here's a simple example of creating a peer connection and data channel:

```typescript
import { RTCPeerConnection } from "werift";

// Create a new peer connection
const pc = new RTCPeerConnection({
  iceServers: [{ urls: "stun:stun.l.google.com:19302" }],
});

// Create a data channel
const dataChannel = pc.createDataChannel("chat");

// Handle data channel events
dataChannel.onopen = () => {
  console.log("Data channel is open!");
  dataChannel.send("Hello from werift! 👋");
};

dataChannel.onmessage = (event) => {
  console.log("Received:", event.data);
};

// Handle ICE candidates
pc.onicecandidate = (event) => {
  if (event.candidate) {
    // Send this candidate to the remote peer via your signaling server
    console.log("New ICE candidate:", event.candidate);
  }
};

// Create an offer
const offer = await pc.createOffer();
await pc.setLocalDescription(offer);

// Send the offer to your remote peer via signaling...
console.log("Offer SDP:", pc.localDescription?.sdp);
```

## 📡 Features

werift supports a comprehensive set of WebRTC features:

| Feature | Status |
|---------|--------|
| **ICE** | ✅ STUN, TURN (UDP), Vanilla ICE, Trickle ICE, ICE-Lite, ICE Restart |
| **DTLS** | ✅ DTLS-SRTP with Curve25519 and P-256 |
| **DataChannel** | ✅ Full support via SCTP |
| **MediaChannel** | ✅ sendonly, recvonly, sendrecv, multi-track |
| **Video Codecs** | ✅ VP8, VP9, H264, AV1 (parsing) |
| **Audio Codecs** | ✅ OPUS |
| **RTP/RTCP** | ✅ RFC 3550, RTX, RED, NACK, PLI, REMB, Transport-Wide CC |
| **Simulcast** | ✅ Receive simulcast streams |
| **Recording** | ✅ WebM/MP4 via MediaRecorder |

### Browser Compatibility

werift is tested and compatible with:
- ✅ Chrome
- ✅ Safari
- ✅ Firefox
- ✅ Pion (Go)
- ✅ aiortc (Python)
- ✅ sipsorcery (.NET)
- ✅ webrtc-rs (Rust)

## 📖 Examples

### Example 1: Simple Signaling with DataChannel

This example shows both the **offer** side (initiator) and **answer** side (responder).

**Offer Side (Server/Initiator):**

```typescript
import { RTCPeerConnection } from "werift";

async function createOffer() {
  const pc = new RTCPeerConnection();

  // Create data channel BEFORE creating the offer
  const channel = pc.createDataChannel("messages");
  
  channel.onopen = () => {
    console.log("Channel open! Sending message...");
    channel.send("Hello from the offer side!");
  };

  channel.onmessage = (e) => {
    console.log("Received:", e.data);
  };

  // Gather ICE candidates
  const candidates: any[] = [];
  pc.onicecandidate = (e) => {
    if (e.candidate) {
      candidates.push(e.candidate);
    }
  };

  // Create and set the offer
  const offer = await pc.createOffer();
  await pc.setLocalDescription(offer);

  // Wait for ICE gathering to complete
  await new Promise<void>((resolve) => {
    if (pc.iceGatheringState === "complete") {
      resolve();
    } else {
      pc.onicegatheringstatechange = () => {
        if (pc.iceGatheringState === "complete") resolve();
      };
    }
  });

  // Return the offer and candidates to send to the answer side
  return {
    sdp: pc.localDescription,
    candidates,
    pc,
  };
}
```

**Answer Side (Client/Responder):**

```typescript
import { RTCPeerConnection } from "werift";

async function createAnswer(remoteSdp: any, remoteCandidates: any[]) {
  const pc = new RTCPeerConnection();

  // Handle incoming data channels
  pc.ondatachannel = (event) => {
    const channel = event.channel;
    
    channel.onopen = () => {
      console.log("Channel open! Sending reply...");
      channel.send("Hello back from the answer side!");
    };

    channel.onmessage = (e) => {
      console.log("Received:", e.data);
    };
  };

  // Set remote description (the offer)
  await pc.setRemoteDescription(remoteSdp);

  // Add remote ICE candidates
  for (const candidate of remoteCandidates) {
    await pc.addIceCandidate(candidate);
  }

  // Create and set the answer
  const answer = await pc.createAnswer();
  await pc.setLocalDescription(answer);

  // Wait for ICE gathering
  await new Promise<void>((resolve) => {
    if (pc.iceGatheringState === "complete") {
      resolve();
    } else {
      pc.onicegatheringstatechange = () => {
        if (pc.iceGatheringState === "complete") resolve();
      };
    }
  });

  return {
    sdp: pc.localDescription,
    pc,
  };
}
```

### Example 2: Receiving Media (Video/Audio)

werift doesn't implement media capture (no `getUserMedia`), but it excels at **receiving** media streams. Here's how to receive video from a browser:

```typescript
import { RTCPeerConnection, RTCRtpCodecParameters } from "werift";

const pc = new RTCPeerConnection({
  codecs: {
    video: [
      new RTCRtpCodecParameters({
        mimeType: "video/VP8",
        clockRate: 90000,
      }),
      new RTCRtpCodecParameters({
        mimeType: "video/H264",
        clockRate: 90000,
      }),
    ],
    audio: [
      new RTCRtpCodecParameters({
        mimeType: "audio/opus",
        clockRate: 48000,
        channels: 2,
      }),
    ],
  },
});

// Listen for incoming tracks
pc.ontrack = (event) => {
  const track = event.track;
  const transceiver = event.transceiver;
  
  console.log(`Received ${track.kind} track!`);

  // Access raw RTP packets
  transceiver.receiver.onPacketReceived = (packet) => {
    // packet contains the raw RTP data
    // You can process, forward, or record this
    console.log(`RTP packet: seq=${packet.header.sequenceNumber}`);
  };
};

// Add transceivers to receive media
pc.addTransceiver("video", { direction: "recvonly" });
pc.addTransceiver("audio", { direction: "recvonly" });

// Create offer to receive media
const offer = await pc.createOffer();
await pc.setLocalDescription(offer);
```

### Example 3: Sending Media (RTP Packets)

To send media, you provide raw RTP packets directly:

```typescript
import { 
  RTCPeerConnection, 
  RTCRtpCodecParameters,
  MediaStreamTrack 
} from "werift";

const pc = new RTCPeerConnection({
  codecs: {
    video: [
      new RTCRtpCodecParameters({
        mimeType: "video/VP8",
        clockRate: 90000,
      }),
    ],
  },
});

// Create a media track for sending
const track = new MediaStreamTrack({ kind: "video" });
const transceiver = pc.addTransceiver(track, { direction: "sendonly" });

// After connection is established, send RTP packets
pc.onconnectionstatechange = () => {
  if (pc.connectionState === "connected") {
    // Get the sender
    const sender = transceiver.sender;
    
    // Send RTP packets (you need to create/obtain these from your source)
    // sender.sendRtp(rtpPacket);
  }
};
```

### Example 4: Recording with MediaRecorder

werift includes a built-in MediaRecorder for saving streams to WebM:

```typescript
import { RTCPeerConnection, MediaRecorder } from "werift";
import * as fs from "fs";

const pc = new RTCPeerConnection();

pc.ontrack = (event) => {
  const track = event.track;
  
  if (track.kind === "video") {
    // Create a recorder
    const recorder = new MediaRecorder({
      path: "./recording.webm",
      width: 1280,
      height: 720,
    });

    // Pipe the track to the recorder
    event.transceiver.receiver.onPacketReceived = (packet) => {
      recorder.addPacket(packet);
    };

    // Stop recording after 30 seconds
    setTimeout(() => {
      recorder.stop();
      console.log("Recording saved!");
    }, 30000);
  }
};
```

### Example 5: Using STUN/TURN Servers

Configure ICE servers for NAT traversal:

```typescript
import { RTCPeerConnection } from "werift";

const pc = new RTCPeerConnection({
  iceServers: [
    // STUN server
    { urls: "stun:stun.l.google.com:19302" },
    
    // TURN server (UDP)
    {
      urls: "turn:your-turn-server.com:3478",
      username: "user",
      credential: "password",
    },
  ],
});
```

### Example 6: ICE Restart

Reconnect without creating a new peer connection:

```typescript
import { RTCPeerConnection } from "werift";

const pc = new RTCPeerConnection();

// ... after connection is established and network changes ...

// Trigger ICE restart
pc.restartIce();

// Create a new offer with ICE restart flag
const offer = await pc.createOffer();
await pc.setLocalDescription(offer);

// Send the new offer to the remote peer for renegotiation
```

## 🏗️ Architecture

werift is designed with a modular architecture:

```
werift
├── ICE      - Interactive Connectivity Establishment
├── DTLS     - Datagram Transport Layer Security  
├── SCTP     - Stream Control Transmission Protocol (DataChannels)
├── RTP      - Real-time Transport Protocol (Media)
├── RTCP     - RTP Control Protocol
├── SRTP     - Secure RTP
└── SDP      - Session Description Protocol
```

### Design Philosophy

- **Pure TypeScript**: No native bindings or browser dependencies
- **Direct RTP Access**: Full control over media packets for custom processing
- **Browser-Compatible API**: Familiar `RTCPeerConnection` interface
- **Modular**: Use only what you need

## 🔧 Configuration Options

```typescript
import { RTCPeerConnection, RTCRtpCodecParameters } from "werift";

const pc = new RTCPeerConnection({
  // Custom certificates (optional)
  privateKey: "...",
  certificate: "...",
  
  // Supported codecs
  codecs: {
    video: [
      new RTCRtpCodecParameters({
        mimeType: "video/VP8",
        clockRate: 90000,
      }),
    ],
    audio: [
      new RTCRtpCodecParameters({
        mimeType: "audio/opus",
        clockRate: 48000,
        channels: 2,
      }),
    ],
  },
  
  // RTP header extensions
  headerExtensions: {
    video: [/* ... */],
    audio: [/* ... */],
  },
  
  // ICE configuration
  iceServers: [
    { urls: "stun:stun.l.google.com:19302" },
  ],
});
```

## 📚 Related Projects

- **[node-sfu](https://github.com/shinyoshiaki/node-sfu)** - A complete SFU (Selective Forwarding Unit) built with werift
- **[webrtc-echoes](https://github.com/sipsorcery/webrtc-echoes)** - Interoperability tests with other WebRTC implementations

## 🤝 Contributing

Contributions are welcome! Check out the [examples directory](https://github.com/shinyoshiaki/werift-webrtc/tree/master/examples) for more usage patterns.

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

## 🙏 Acknowledgments

werift is inspired by and references:
- [aiortc](https://github.com/aiortc/aiortc) - Python WebRTC implementation
- [pion/webrtc](https://github.com/pion/webrtc) - Go WebRTC implementation

---

**Made with ❤️ by [shinyoshiaki](https://github.com/shinyoshiaki)**

[Website](https://shinyoshiaki.github.io/werift-webrtc) • [API Reference](https://shinyoshiaki.github.io/werift-webrtc/website/build/docs/api/) • [Examples](https://github.com/shinyoshiaki/werift-webrtc/tree/master/examples) • [npm](https://www.npmjs.com/package/werift)