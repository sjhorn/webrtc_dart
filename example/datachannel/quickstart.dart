/// Quick Start: Local RTCDataChannel Test
///
/// This example creates two peer connections locally and exchanges messages.
/// It matches the "Example 1: Local RTCDataChannel Test" snippet in README.md.
///
/// Usage: dart run example/quickstart_local.dart
library;

import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  // Create two peer connections
  final pcOffer = RTCPeerConnection();
  final pcAnswer = RTCPeerConnection();

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
