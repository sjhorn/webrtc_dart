/// Quick Start: Your First RTCDataChannel
///
/// This example shows basic peer connection and data channel creation.
/// It matches the "Your First RTCDataChannel" snippet in README.md.
///
/// Usage: dart run example/quickstart_datachannel.dart
library;

import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  // Create a new peer connection
  final pc = RTCPeerConnection(RtcConfiguration(
    iceServers: [
      IceServer(urls: ['stun:stun.l.google.com:19302'])
    ],
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
