/// TWCC (Transport-Wide Congestion Control) Example
///
/// This example demonstrates TWCC which enables bandwidth estimation
/// and congestion control by tracking packet arrival times across
/// the entire transport (not just individual streams).
///
/// Usage: dart run examples/twcc_congestion.dart
library;

import 'dart:async';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('TWCC (Transport-Wide Congestion Control) Example');
  print('=' * 50);
  print('');

  // Create two peer connections
  final sender = RtcPeerConnection();
  final receiver = RtcPeerConnection();

  // Track connection ready
  final connected = Completer<void>();
  var senderConnected = false;
  var receiverConnected = false;

  // Monitor connection states
  sender.onConnectionStateChange.listen((state) {
    print('[Sender] Connection state: $state');
    if (state == PeerConnectionState.connected) {
      senderConnected = true;
      if (receiverConnected && !connected.isCompleted) {
        connected.complete();
      }
    }
  });

  receiver.onConnectionStateChange.listen((state) {
    print('[Receiver] Connection state: $state');
    if (state == PeerConnectionState.connected) {
      receiverConnected = true;
      if (senderConnected && !connected.isCompleted) {
        connected.complete();
      }
    }
  });

  // Set up ICE candidate exchange
  sender.onIceCandidate.listen((candidate) async {
    await receiver.addIceCandidate(candidate);
  });

  receiver.onIceCandidate.listen((candidate) async {
    await sender.addIceCandidate(candidate);
  });

  // Create video track
  print('Creating video track with TWCC support...');
  final videoTrack = VideoStreamTrack(
    id: 'twcc-video',
    label: 'TWCC Video',
  );

  // Add track to sender
  sender.addTrack(videoTrack);

  // Handle incoming tracks on receiver
  receiver.onTrack.listen((transceiver) {
    print('[Receiver] Received track: kind=${transceiver.kind}, mid=${transceiver.mid}');
  });

  // Perform offer/answer exchange
  print('');
  print('Performing offer/answer exchange...');

  final offer = await sender.createOffer();
  print('[Sender] Created offer');

  // Log TWCC-related SDP lines
  print('');
  print('--- TWCC in SDP ---');
  final sdpLines = offer.sdp.split('\n');
  for (final line in sdpLines) {
    if (line.contains('transport-cc') ||
        line.contains('transport-wide-cc') ||
        line.contains('abs-send-time')) {
      print('  $line');
    }
  }

  await sender.setLocalDescription(offer);
  await receiver.setRemoteDescription(offer);

  final answer = await receiver.createAnswer();
  await receiver.setLocalDescription(answer);
  await sender.setRemoteDescription(answer);

  // Wait for connection
  print('');
  print('Waiting for connection...');
  try {
    await connected.future.timeout(Duration(seconds: 10));
    print('Connection established!');
  } catch (e) {
    print('Connection timeout');
  }

  // Explain TWCC mechanism
  print('');
  print('--- TWCC Mechanism ---');
  print('Transport-Wide Congestion Control enables:');
  print('');
  print('1. Transport-wide sequence numbers:');
  print('   - Each RTP packet gets a transport-wide seq number');
  print('   - Tracked across all streams (audio + video)');
  print('');
  print('2. Receiver feedback (RTCP):');
  print('   - Receiver sends TWCC feedback packets');
  print('   - Reports packet arrival times and losses');
  print('   - Uses run-length and status vector encoding');
  print('');
  print('3. Sender bandwidth estimation:');
  print('   - Sender uses feedback to estimate bandwidth');
  print('   - Detects congestion via delay increases');
  print('   - Adjusts sending rate accordingly');
  print('');
  print('SDP negotiation includes:');
  print('  - a=rtcp-fb:<PT> transport-cc');
  print('  - a=extmap:<ID> transport-wide-cc-02 (RTP header extension)');
  print('  - a=extmap:<ID> abs-send-time (absolute send timestamp)');

  // Summary
  print('');
  print('--- Summary ---');
  print('Sender connection: ${sender.connectionState}');
  print('Receiver connection: ${receiver.connectionState}');

  if (sender.connectionState == PeerConnectionState.connected) {
    print('');
    print('SUCCESS: TWCC-capable connection established!');
  }

  // Cleanup
  print('');
  print('Closing connections...');
  await sender.close();
  await receiver.close();
  print('Done.');
}
