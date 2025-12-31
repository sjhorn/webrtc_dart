# webrtc_dart - WebRTC for Dart

**webrtc_dart** is a pure Dart implementation of WebRTC. No native dependencies, no browser required - just add to your `pubspec.yaml` and go!

[![pub package](https://img.shields.io/pub/v/webrtc_dart.svg)](https://pub.dev/packages/webrtc_dart)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## What is webrtc_dart?

webrtc_dart lets you build WebRTC applications entirely in Dart. Whether you're creating a media server, an SFU (Selective Forwarding Unit), a signaling server, or peer-to-peer data channels - webrtc_dart has you covered.

Unlike browser-based WebRTC, webrtc_dart gives you direct access to RTP packets, making it perfect for building custom media servers, recording solutions, and real-time communication backends.

This is a complete port of [werift-webrtc](https://github.com/shinyoshiaki/werift-webrtc) (TypeScript) to Dart.

## Quick Start

### Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  webrtc_dart: ^0.22.11
```

Then run:
```bash
dart pub get
```

### Your First DataChannel

Here's a simple example of creating a peer connection and data channel:

```dart
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  // Create a new peer connection
  final pc = RtcPeerConnection(RtcConfiguration(
    iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
  ));

  // Wait for transport initialization (DTLS certificate generation)
  await Future.delayed(Duration(milliseconds: 500));

  // Create a data channel
  final dataChannel = pc.createDataChannel('chat');

  // Handle data channel events
  dataChannel.onStateChange.listen((state) {
    if (state == DataChannelState.open) {
      print('Data channel is open!');
      dataChannel.sendString('Hello from webrtc_dart!');
    }
  });

  dataChannel.onMessage.listen((message) {
    print('Received: $message');
  });

  // Handle ICE candidates
  pc.onIceCandidate.listen((candidate) {
    // Send this candidate to the remote peer via your signaling server
    print('New ICE candidate: ${candidate.toSdp()}');
  });

  // Create an offer
  final offer = await pc.createOffer();
  await pc.setLocalDescription(offer);

  // Send the offer to your remote peer via signaling...
  print('Offer SDP: ${offer.sdp}');
}
```

## Features

webrtc_dart supports a comprehensive set of WebRTC features:

| Feature | Status |
|---------|--------|
| **ICE** | STUN, TURN (UDP), Trickle ICE, ICE Restart, ICE TCP, mDNS |
| **DTLS** | DTLS-SRTP with Curve25519 and P-256 |
| **DataChannel** | Full support via SCTP (reliable/unreliable, ordered/unordered) |
| **MediaChannel** | sendonly, recvonly, sendrecv, multi-track |
| **Video Codecs** | VP8, VP9, H.264, AV1 (depacketization) |
| **Audio Codecs** | Opus |
| **RTP/RTCP** | RFC 3550, RTX, RED, NACK, PLI, FIR, REMB, TWCC |
| **Simulcast** | Receive simulcast streams with RID/MID |
| **Recording** | WebM/MP4 via MediaRecorder |
| **Stats** | Full getStats() API |

### Browser Compatibility

webrtc_dart is tested and compatible with:
- Chrome
- Firefox
- Safari
- Other WebRTC implementations (Pion, aiortc, werift)

## Examples

### Example 1: Local DataChannel Test

Connect two peer connections locally and exchange messages:

```dart
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  // Create two peer connections
  final pcOffer = RtcPeerConnection();
  final pcAnswer = RtcPeerConnection();

  // Exchange ICE candidates
  pcOffer.onIceCandidate.listen((candidate) async {
    await pcAnswer.addIceCandidate(candidate);
  });

  pcAnswer.onIceCandidate.listen((candidate) async {
    await pcOffer.addIceCandidate(candidate);
  });

  // Handle incoming data channel on answer side
  pcAnswer.onDataChannel.listen((channel) {
    channel.onMessage.listen((message) {
      print('Answer received: $message');
      channel.sendString('Hello back!');
    });
  });

  // Perform offer/answer exchange
  final offer = await pcOffer.createOffer();
  await pcOffer.setLocalDescription(offer);
  await pcAnswer.setRemoteDescription(offer);

  final answer = await pcAnswer.createAnswer();
  await pcAnswer.setLocalDescription(answer);
  await pcOffer.setRemoteDescription(answer);

  // Wait for connection
  await Future.delayed(Duration(seconds: 2));

  // Create and use data channel
  final dc = pcOffer.createDataChannel('chat');
  dc.onStateChange.listen((state) {
    if (state == DataChannelState.open) {
      dc.sendString('Hello from offer side!');
    }
  });

  dc.onMessage.listen((message) {
    print('Offer received: $message');
  });
}
```

Run this example:
```bash
dart run example/quickstart_local.dart
```

### Example 2: Receiving Media (Video/Audio)

webrtc_dart excels at receiving media streams. Here's how to set up for receiving media:

```dart
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  // Create a peer connection
  final pc = RtcPeerConnection(RtcConfiguration(
    iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
  ));

  // Listen for incoming tracks
  pc.onTrack.listen((transceiver) {
    print('Received ${transceiver.kind} track!');
    print('  mid: ${transceiver.mid}');
    print('  direction: ${transceiver.direction}');
  });

  // Create offer
  final offer = await pc.createOffer();
  await pc.setLocalDescription(offer);

  print('Peer connection ready to receive media');
  print('Offer SDP created (send to remote peer):');
  print(offer.sdp);
}
```

Run this example:
```bash
dart run example/quickstart_media.dart
```

### Example 3: Using STUN/TURN Servers

Configure ICE servers for NAT traversal:

```dart
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  final pc = RtcPeerConnection(RtcConfiguration(
    iceServers: [
      // STUN server
      IceServer(urls: ['stun:stun.l.google.com:19302']),

      // TURN server (UDP)
      IceServer(
        urls: ['turn:your-turn-server.com:3478'],
        username: 'user',
        credential: 'password',
      ),
    ],
  ));

  print('Peer connection created with STUN/TURN configuration');
  print('ICE servers configured:');
  for (final server in pc.configuration.iceServers) {
    print('  - ${server.urls}');
  }
}
```

Run this example:
```bash
dart run example/quickstart_turn.dart
```

### Example 4: ICE Restart

Reconnect without creating a new peer connection:

```dart
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  final pc = RtcPeerConnection();

  // ... after connection is established and network changes ...

  // Trigger ICE restart
  pc.restartIce();

  // Create a new offer with ICE restart flag
  final offer = await pc.createOffer();
  await pc.setLocalDescription(offer);

  // Send the new offer to the remote peer for renegotiation
  print('ICE restart triggered');
  print('New offer SDP for renegotiation:');
  print(offer.sdp);
}
```

Run this example:
```bash
dart run example/quickstart_ice_restart.dart
```

### More Examples

| Example | Description | Command |
|---------|-------------|---------|
| `datachannel_local.dart` | Local peer-to-peer data exchange | `dart run example/datachannel_local.dart` |
| `datachannel_string.dart` | String message data channels | `dart run example/datachannel_string.dart` |
| `mediachannel_local.dart` | Local audio/video tracks | `dart run example/mediachannel_local.dart` |
| `simulcast_local.dart` | Simulcast stream handling | `dart run example/simulcast_local.dart` |
| `ice_restart.dart` | ICE restart demonstration | `dart run example/ice_restart.dart` |
| `ice_trickle.dart` | Trickle ICE candidates | `dart run example/ice_trickle.dart` |
| `ice_turn.dart` | TURN server usage | `dart run example/ice_turn.dart` |
| `rtx_retransmission.dart` | RTX packet retransmission | `dart run example/rtx_retransmission.dart` |
| `twcc_congestion.dart` | Transport-wide congestion control | `dart run example/twcc_congestion.dart` |
| `red_redundancy.dart` | RED audio redundancy | `dart run example/red_redundancy.dart` |
| `save_to_disk.dart` | Save media to WebM | `dart run example/save_to_disk.dart` |
| `save_to_disk_mp4.dart` | Save media to MP4 | `dart run example/save_to_disk_mp4.dart` |
| `getstats_demo.dart` | Statistics API demo | `dart run example/getstats_demo.dart` |
| `ffmpeg_video_send.dart` | Send video via FFmpeg pipe | `dart run example/ffmpeg_video_send.dart` |
| `signaling/` | Full signaling server example | See `example/signaling/` |

## Architecture

webrtc_dart uses a layered architecture: ICE → DTLS → SRTP/SCTP → RTP/RTCP → SDP.

- **Pure Dart**: No native bindings or browser dependencies
- **Direct RTP Access**: Full control over media packets for custom processing
- **Browser-Compatible API**: Familiar `RTCPeerConnection`-style interface

See `CLAUDE.md` for detailed code structure.

## Test Coverage

**2434 tests passing** with **80% code coverage**.

```bash
# Run all tests
dart test

# Run specific test suite
dart test test/ice/
dart test test/dtls/
dart test test/peer_connection_test.dart
```

## Browser Interop Testing

Automated Playwright tests verify compatibility with Chrome, Firefox, and Safari.
See `CLAUDE.md` for test commands.

## Configuration Options

```dart
import 'package:webrtc_dart/webrtc_dart.dart';

final pc = RtcPeerConnection(RtcConfiguration(
  // ICE configuration
  iceServers: [
    IceServer(urls: ['stun:stun.l.google.com:19302']),
  ],

  // Supported codecs
  codecs: RtcCodecConfiguration(
    video: [
      RtcRtpCodecParameters(
        mimeType: 'video/VP8',
        clockRate: 90000,
      ),
    ],
    audio: [
      RtcRtpCodecParameters(
        mimeType: 'audio/opus',
        clockRate: 48000,
        channels: 2,
      ),
    ],
  ),

  // RTP header extensions
  headerExtensions: RtcHeaderExtensions(
    video: [/* ... */],
    audio: [/* ... */],
  ),
));
```

## Related Projects

- **[werift-webrtc](https://github.com/shinyoshiaki/werift-webrtc)** - The original TypeScript implementation this project is ported from
- **[node-sfu](https://github.com/shinyoshiaki/node-sfu)** - A complete SFU built with werift

## Contributing

Contributions are welcome! Check out the [examples directory](example/) for usage patterns.

```bash
# Format code
dart format .

# Analyze code
dart analyze

# Run tests
dart test
```

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

This project is a Dart port of [werift-webrtc](https://github.com/shinyoshiaki/werift-webrtc) by Yuki Shindo.

webrtc_dart is inspired by and references:
- [werift-webrtc](https://github.com/shinyoshiaki/werift-webrtc) - TypeScript WebRTC implementation
- [aiortc](https://github.com/aiortc/aiortc) - Python WebRTC implementation
- [pion/webrtc](https://github.com/pion/webrtc) - Go WebRTC implementation
