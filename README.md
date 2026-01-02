# webrtc_dart

Pure Dart WebRTC implementation. No native dependencies - works on any Dart platform.

[![pub package](https://img.shields.io/pub/v/webrtc_dart.svg)](https://pub.dev/packages/webrtc_dart)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Features

- **W3C WebRTC API** - Standard RTCPeerConnection interface
- **DataChannels** - Reliable/unreliable, ordered/unordered
- **Media streaming** - Video (VP8, VP9, H.264, AV1) and Audio (Opus)
- **Full RTP/RTCP** - NACK, PLI, FIR, REMB, TWCC, RTX, Simulcast
- **NAT traversal** - ICE, STUN, TURN with TCP/UDP support
- **Secure** - DTLS-SRTP with modern cipher suites

## Installation

```yaml
dependencies:
  webrtc_dart: ^0.23.0
```

## Quick Start

### DataChannel

```dart
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  final pc = RTCPeerConnection(RtcConfiguration(
    iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
  ));

  // Create data channel
  final channel = pc.createDataChannel('chat');

  channel.onOpen.listen((_) {
    channel.sendString('Hello!');
  });

  channel.onMessage.listen((message) {
    print('Received: $message');
  });

  // Handle ICE candidates
  pc.onIceCandidate.listen((candidate) {
    // Send to remote peer via signaling
  });

  // Create and send offer
  final offer = await pc.createOffer();
  await pc.setLocalDescription(offer);
}
```

### Receiving Media

```dart
final pc = RTCPeerConnection();

pc.onTrack.listen((transceiver) {
  print('Received ${transceiver.receiver.track.kind} track');

  // Access RTP packets directly
  transceiver.receiver.onRtp = (packet) {
    // Process video/audio packets
  };
});
```

### Using TURN

```dart
final pc = RTCPeerConnection(RtcConfiguration(
  iceServers: [
    IceServer(urls: ['stun:stun.l.google.com:19302']),
    IceServer(
      urls: ['turn:turn.example.com:3478'],
      username: 'user',
      credential: 'pass',
    ),
  ],
));
```

## API Overview

| Class | Purpose |
|-------|---------|
| `RTCPeerConnection` | Main WebRTC connection |
| `RTCDataChannel` | Data messaging |
| `RTCRtpTransceiver` | Media track handling |
| `RTCRtpSender` | Send media + DTMF |
| `RTCRtpReceiver` | Receive media |
| `RTCIceCandidate` | ICE connectivity |
| `RTCSessionDescription` | SDP offer/answer |

## Browser Compatibility

Tested with Chrome, Firefox, and Safari via automated Playwright tests.

## Examples

See [`example/`](example/) for comprehensive examples:

- `datachannel/` - Data channel patterns
- `mediachannel/` - Media streaming (sendonly, recvonly, sendrecv)
- `save_to_disk/` - Recording to WebM/MP4
- `telephony/` - DTMF tones

## Test Coverage

**2587 tests passing** with browser interop validation.

```bash
dart test                    # Run all tests
dart test test/ice/          # Run specific suite
```

## Contributing

```bash
dart format .     # Format code
dart analyze      # Check for issues
dart test         # Run tests
```

## Acknowledgments

Port of [werift-webrtc](https://github.com/shinyoshiaki/werift-webrtc) by Yuki Shindo.

## License

MIT
