/// ICE Trickle with DataChannel Example
///
/// This example demonstrates ICE trickle (gradual candidate exchange)
/// with a DataChannel connection. Uses HTTP-style endpoints for
/// offer/answer/candidate exchange.
///
/// Usage: dart run example/ice/trickle/dc.dart
library;

import 'dart:async';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('ICE Trickle with DataChannel Example');
  print('=' * 50);

  // Create peer connection
  final pc = RtcPeerConnection();

  // Track ICE candidates for trickle
  final candidates = <Candidate>[];

  pc.onIceCandidate.listen((candidate) {
    print('[ICE] New candidate: ${candidate.type} ${candidate.host}:${candidate.port}');
    candidates.add(candidate);
  });

  pc.onIceGatheringStateChange.listen((state) {
    print('[ICE] Gathering state: $state');
  });

  pc.onIceConnectionStateChange.listen((state) {
    print('[ICE] Connection state: $state');
  });

  // Create datachannel
  final dc = pc.createDataChannel('chat');
  dc.onStateChange.listen((state) {
    print('[DC] State: $state');
    if (state == DataChannelState.open) {
      print('[DC] Channel open - ready for messages');
    }
  });

  var msgIndex = 0;
  dc.onMessage.listen((data) {
    print('[DC] Received: ${String.fromCharCodes(data)}');
    dc.sendString('pong${msgIndex++}');
  });

  // Create offer (candidates will trickle in)
  print('\nCreating offer...');
  await pc.setLocalDescription(await pc.createOffer());

  print('\n--- Simulated HTTP Endpoints ---');
  print('GET /connection -> returns offer SDP');
  print('POST /answer -> accepts answer SDP');
  print('POST /candidate -> accepts trickled candidate');

  // Display the offer
  print('\n--- Offer SDP ---');
  print('Type: ${pc.localDescription?.type}');
  print('SDP length: ${pc.localDescription?.sdp.length} chars');

  // Wait for some candidates to trickle
  print('\nWaiting for ICE candidates to trickle...');
  await Future.delayed(Duration(seconds: 2));

  print('\n--- Trickled Candidates ---');
  print('Total candidates gathered: ${candidates.length}');
  for (var i = 0; i < candidates.length && i < 3; i++) {
    final c = candidates[i];
    print('  [$i] ${c.type} ${c.host}:${c.port} (priority=${c.priority})');
  }
  if (candidates.length > 3) {
    print('  ... and ${candidates.length - 3} more');
  }

  print('\n--- Usage ---');
  print('In a real app:');
  print('1. Send offer to remote peer via signaling');
  print('2. Trickle candidates as they arrive');
  print('3. Remote peer sends answer + their candidates');
  print('4. Connection establishes when paths found');

  // Cleanup
  await pc.close();
  print('\nDone.');
}
