/// Quick Start: ICE Restart
///
/// This example shows how to restart ICE without creating a new peer connection.
/// It matches the "Example 4: ICE Restart" snippet in README.md.
///
/// Usage: dart run example/quickstart_ice_restart.dart
library;

import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  final pc = RTCPeerConnection();

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
