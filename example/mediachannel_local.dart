/// Local MediaChannel Example
///
/// This example creates two peer connections locally and establishes
/// media transceivers between them for send/receive scenarios.
///
/// Note: This is a structural example demonstrating the API patterns.
/// For actual media flow, you would need to connect to real media sources.
///
/// Usage: dart run examples/mediachannel_local.dart
library;

import 'dart:async';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('Starting local mediachannel example...\n');

  // Create two peer connections
  final pcOffer = RtcPeerConnection();
  final pcAnswer = RtcPeerConnection();

  // Set up completers for state tracking
  final iceCompleted = Completer<void>();
  var offerIceComplete = false;
  var answerIceComplete = false;

  final transportConnected = Completer<void>();
  var offerTransportReady = false;
  var answerTransportReady = false;

  // Set up connection state monitoring
  pcOffer.onConnectionStateChange.listen((state) {
    print('[Offer] Connection state: $state');
    if (state == PeerConnectionState.connected) {
      offerTransportReady = true;
      if (answerTransportReady && !transportConnected.isCompleted) {
        transportConnected.complete();
      }
    }
  });

  pcAnswer.onConnectionStateChange.listen((state) {
    print('[Answer] Connection state: $state');
    if (state == PeerConnectionState.connected) {
      answerTransportReady = true;
      if (offerTransportReady && !transportConnected.isCompleted) {
        transportConnected.complete();
      }
    }
  });

  // Set up ICE state change monitoring
  pcOffer.onIceConnectionStateChange.listen((state) {
    print('[Offer] ICE state: $state');
    if (state == IceConnectionState.completed ||
        state == IceConnectionState.connected) {
      offerIceComplete = true;
      if (answerIceComplete && !iceCompleted.isCompleted) {
        iceCompleted.complete();
      }
    }
  });

  pcAnswer.onIceConnectionStateChange.listen((state) {
    print('[Answer] ICE state: $state');
    if (state == IceConnectionState.completed ||
        state == IceConnectionState.connected) {
      answerIceComplete = true;
      if (offerIceComplete && !iceCompleted.isCompleted) {
        iceCompleted.complete();
      }
    }
  });

  // Set up ICE candidate exchange
  pcOffer.onIceCandidate.listen((candidate) async {
    await pcAnswer.addIceCandidate(candidate);
  });

  pcAnswer.onIceCandidate.listen((candidate) async {
    await pcOffer.addIceCandidate(candidate);
  });

  // Handle incoming tracks
  pcOffer.onTrack.listen((transceiver) {
    print('[Offer] Received track: kind=${transceiver.kind}, mid=${transceiver.mid}');
  });

  pcAnswer.onTrack.listen((transceiver) {
    print('[Answer] Received track: kind=${transceiver.kind}, mid=${transceiver.mid}');
  });

  // Create audio and video tracks for offer side
  final offerAudioTrack = AudioStreamTrack(
    id: 'offer-audio',
    label: 'Offer Audio',
  );
  final offerVideoTrack = VideoStreamTrack(
    id: 'offer-video',
    label: 'Offer Video',
  );

  // Add tracks to offer peer connection
  print('\nAdding tracks to offer side...');
  pcOffer.addTrack(offerAudioTrack);
  pcOffer.addTrack(offerVideoTrack);
  print('Added audio and video tracks');

  print('\nPerforming offer/answer exchange...');

  // Create and exchange offer
  final offer = await pcOffer.createOffer();
  print('[Offer] Created offer SDP (${offer.sdp.length} bytes)');

  // Print SDP summary
  final offerLines = offer.sdp.split('\n');
  final audioLine = offerLines.firstWhere((l) => l.startsWith('m=audio'), orElse: () => '');
  final videoLine = offerLines.firstWhere((l) => l.startsWith('m=video'), orElse: () => '');
  if (audioLine.isNotEmpty) print('   Audio: $audioLine');
  if (videoLine.isNotEmpty) print('   Video: $videoLine');

  await pcOffer.setLocalDescription(offer);
  await pcAnswer.setRemoteDescription(offer);

  // Create and exchange answer
  final answer = await pcAnswer.createAnswer();
  print('[Answer] Created answer SDP (${answer.sdp.length} bytes)');

  await pcAnswer.setLocalDescription(answer);
  await pcOffer.setRemoteDescription(answer);

  // Wait for ICE to complete
  print('\nWaiting for ICE connection...');
  try {
    await iceCompleted.future.timeout(Duration(seconds: 10));
    print('✓ ICE connection established!');
  } catch (e) {
    print('✗ ICE connection timeout');
  }

  // Wait for full transport connection
  print('\nWaiting for DTLS handshake...');
  try {
    await transportConnected.future.timeout(Duration(seconds: 10));
    print('✓ Transport connected!\n');
  } catch (e) {
    print('✗ Transport connection timeout\n');
  }

  // Display transceiver information
  print('\n--- Transceivers ---');
  print('Offer transceivers: ${pcOffer.transceivers.length}');
  for (final t in pcOffer.transceivers) {
    print('  - mid=${t.mid}, kind=${t.kind}, direction=${t.direction}');
  }
  print('Answer transceivers: ${pcAnswer.transceivers.length}');
  for (final t in pcAnswer.transceivers) {
    print('  - mid=${t.mid}, kind=${t.kind}, direction=${t.direction}');
  }

  // Summary
  print('\n--- Summary ---');
  print('Offer signaling state: ${pcOffer.signalingState.name}');
  print('Answer signaling state: ${pcAnswer.signalingState.name}');
  print('Offer connection state: ${pcOffer.connectionState.name}');
  print('Answer connection state: ${pcAnswer.connectionState.name}');
  print('Offer ICE state: ${pcOffer.iceConnectionState.name}');
  print('Answer ICE state: ${pcAnswer.iceConnectionState.name}');

  if (pcOffer.connectionState == PeerConnectionState.connected &&
      pcAnswer.connectionState == PeerConnectionState.connected) {
    print('\n✅ SUCCESS: Media channel connection established!');
    print('   The peer connections are ready to exchange media.');
  } else {
    print('\n⚠️  WARNING: Connection not fully established');
  }

  // Cleanup
  print('\nClosing connections...');
  await pcOffer.close();
  await pcAnswer.close();

  print('Connections closed.');
}
