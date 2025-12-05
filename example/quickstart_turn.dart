/// Quick Start: Using STUN/TURN Servers
///
/// This example shows how to configure ICE servers for NAT traversal.
/// It matches the "Example 3: Using STUN/TURN Servers" snippet in README.md.
///
/// Usage: dart run example/quickstart_turn.dart
library;

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
