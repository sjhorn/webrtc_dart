# webrtc_dart

Server-side WebRTC in pure Dart. Build SFUs, recording servers, and media pipelines.

[![pub package](https://img.shields.io/pub/v/webrtc_dart.svg)](https://pub.dev/packages/webrtc_dart)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## What is webrtc_dart?

A **server-side** WebRTC library for Dart, similar to [Pion](https://github.com/pion/webrtc) (Go), [aiortc](https://github.com/aiortc/aiortc) (Python), and [werift](https://github.com/shinyoshiaki/werift-webrtc) (TypeScript).

**Use cases:**
- SFU (Selective Forwarding Unit)
- Recording servers (WebM/MP4)
- Media processing pipelines
- DataChannel messaging backends
- WebRTC-to-other-protocol bridges

## Features

| What we handle | Details |
|----------------|---------|
| **WebRTC Transport** | ICE, DTLS, SRTP, SCTP, RTP/RTCP |
| **DataChannels** | Reliable/unreliable, ordered/unordered |
| **RTP Processing** | NACK, PLI, FIR, REMB, TWCC, RTX, Simulcast |
| **Codec Depacketization** | VP8, VP9, H.264, AV1, Opus |
| **NAT Traversal** | STUN, TURN (UDP/TCP), ICE-TCP, mDNS |
| **Recording** | Save received streams to WebM/MP4 |

## Server-Side vs Browser WebRTC

webrtc_dart handles **transport**, not **media capture/playback**:

| Feature | Browser WebRTC | webrtc_dart |
|---------|----------------|-------------|
| Camera/mic access | Yes | No - use FFmpeg/GStreamer |
| Video encoding | Yes (hardware) | No - forward RTP packets |
| Video decoding | Yes (hardware) | No - depacketize only |
| `<video>` playback | Yes | N/A |
| Peer connections | Yes | Yes |
| DataChannels | Yes | Yes |
| RTP packet access | Limited | Full control |

## Installation

```yaml
dependencies:
  webrtc_dart: ^0.24.0
```

## Quick Start

### DataChannel

```dart
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  final pc = RTCPeerConnection(RtcConfiguration(
    iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
  ));

  final channel = pc.createDataChannel('chat');

  channel.onOpen.listen((_) => channel.sendString('Hello!'));
  channel.onMessage.listen((msg) => print('Received: $msg'));

  pc.onIceCandidate.listen((candidate) {
    // Send to remote peer via signaling
  });

  final offer = await pc.createOffer();
  await pc.setLocalDescription(offer);
}
```

### Receiving Media (SFU Pattern)

```dart
final pc = RTCPeerConnection();

pc.onTrack.listen((transceiver) {
  // Access raw RTP packets
  transceiver.receiver.onRtp = (packet) {
    // Forward to other peers, record, or process
  };
});
```

### Recording to WebM

```dart
// Record received media to file
final recorder = MediaRecorder(
  tracks: [videoTrack, audioTrack],
  path: 'output.webm',
);
await recorder.start();
// ... receive media ...
await recorder.stop();
```

## API Overview

| Class | Purpose |
|-------|---------|
| `RTCPeerConnection` | WebRTC connection management |
| `RTCDataChannel` | Data messaging |
| `RTCRtpTransceiver` | Media track handling |
| `RTCRtpSender` | Send RTP + DTMF |
| `RTCRtpReceiver` | Receive RTP |
| `RTCIceCandidate` | ICE connectivity |
| `RTCSessionDescription` | SDP offer/answer |

## Browser Interop

Tested with Chrome, Firefox, and Safari via automated Playwright tests.

## Examples

See [`example/`](example/) for the original examples ported from werift:

- `datachannel/` - Data channel patterns
- `mediachannel/` - SFU patterns (sendonly, recvonly, sendrecv)
- `save_to_disk/` - Recording to WebM/MP4
- `mediachannel/pubsub/` - Multi-peer SFU

To see additional examples comparing how to implement in either werift or webrtc_dart see [WebRTC Examples](http://blog.hornmicro.com/webrtc_examples/)

## Performance

Comparison: webrtc_dart v0.24.0 vs werift v0.22.2

Binary parsing operations are faster than werift (TypeScript). SRTP is slower due to pure Dart crypto vs Node.js native bindings.

| Operation | webrtc_dart | werift | vs werift |
|-----------|-------------|--------|-----------|
| RTP parse | 3.5M/s | 1.4M/s | **2.5x faster** |
| SDP parse | 54K/s | 22K/s | **2.5x faster** |
| STUN parse | 1.2M/s | 0.7M/s | **1.7x faster** |
| H.264 depacketize | 2.9M/s | 1.1M/s | **2.6x faster** |
| ICE candidate parse | 5.0M/s | 13M/s | 2.6x slower* |
| SRTP encrypt (1KB) | 18K/s | 550K/s | 30x slower* |

\*ICE parsing and SRTP use pure Dart; native FFI would close these gaps.

Run benchmarks: `./benchmark/run_perf_tests.sh`

## Test Coverage

**2625 tests passing** (including 38 performance regression tests) with browser interop validation.

```bash
dart test                        # Run all tests
dart test test/ice/              # Run specific suite
dart test test/performance/      # Run performance tests
```

## Acknowledgments

Port of [werift-webrtc](https://github.com/shinyoshiaki/werift-webrtc) by Yuki Shindo.

## License

MIT
