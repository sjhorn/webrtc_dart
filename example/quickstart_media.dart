/// Quick Start: Receiving Media (Video/Audio)
///
/// This example shows a basic peer connection setup that can receive media.
/// When media arrives, the onTrack callback is invoked with the transceiver.
///
/// Usage: dart run example/quickstart_media.dart
library;

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
