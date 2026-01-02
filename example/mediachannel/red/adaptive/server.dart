/// Adaptive RED (Redundant Encoding) Example
///
/// Demonstrates adaptive redundancy based on network conditions.
/// Increases redundancy when packet loss is detected, decreases
/// when network is stable to save bandwidth.
///
/// Usage: dart run example/mediachannel/red/adaptive/server.dart
library;

import 'dart:async';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('Adaptive RED Example');
  print('=' * 50);

  final pc = RTCPeerConnection(RtcConfiguration(
    iceServers: [
      IceServer(urls: ['stun:stun.l.google.com:19302'])
    ],
  ));

  pc.onConnectionStateChange.listen((state) {
    print('[PC] Connection: $state');
  });

  // Track packet loss statistics
  var packetsReceived = 0;
  var packetsLost = 0;
  var redundancyLevel = 1; // 1 = no redundancy, 2 = 1 redundant copy, etc.

  // Add audio transceiver with RED support
  pc.addTransceiver(
    MediaStreamTrackKind.audio,
    direction: RtpTransceiverDirection.sendrecv,
  );

  pc.onTrack.listen((transceiver) {
    print('[Track] Received ${transceiver.kind}');

    // Monitor packet loss via RTCP RR
    // Adjust redundancy based on loss rate
  });

  // Periodically evaluate and adjust redundancy
  Timer.periodic(Duration(seconds: 5), (_) {
    final lossRate =
        packetsReceived > 0 ? (packetsLost / packetsReceived * 100) : 0.0;

    print('[Stats] Loss rate: ${lossRate.toStringAsFixed(1)}%');

    // Adaptive logic
    if (lossRate > 5.0 && redundancyLevel < 3) {
      redundancyLevel++;
      print('[Adaptive] Increasing redundancy to $redundancyLevel');
    } else if (lossRate < 1.0 && redundancyLevel > 1) {
      redundancyLevel--;
      print('[Adaptive] Decreasing redundancy to $redundancyLevel');
    }
  });

  final offer = await pc.createOffer();
  await pc.setLocalDescription(offer);

  print('\n--- Adaptive RED Algorithm ---');
  print('');
  print('Redundancy levels:');
  print('  1: No redundancy (normal operation)');
  print('  2: 1 redundant copy (previous packet)');
  print('  3: 2 redundant copies (2 previous packets)');
  print('');
  print('Adaptation thresholds:');
  print('  Loss > 5%: Increase redundancy');
  print('  Loss < 1%: Decrease redundancy');
  print('');
  print('Bandwidth impact:');
  print('  Level 1: 1x bandwidth');
  print('  Level 2: ~1.5x bandwidth');
  print('  Level 3: ~2x bandwidth');

  print('\n--- RED Packet Format ---');
  print('');
  print('RED header (RFC 2198):');
  print('  F (1 bit): Follow bit (1 = more blocks)');
  print('  Block PT (7 bits): Payload type of block');
  print('  Timestamp offset (14 bits): Offset from RTP timestamp');
  print('  Block length (10 bits): Length of block');
  print('');
  print('Example with 1 redundant copy:');
  print('  [RED hdr: F=1, PT=111] [Offset, Len] [Previous audio]');
  print('  [RED hdr: F=0, PT=111] [Current audio]');

  await Future.delayed(Duration(seconds: 2));
  await pc.close();
  print('\nDone.');
}
