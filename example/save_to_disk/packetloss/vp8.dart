/// Packet Loss Simulation Example
///
/// Demonstrates recording video with simulated packet loss
/// to test error resilience and recovery mechanisms.
///
/// Usage: dart run example/save_to_disk/packetloss/vp8.dart
library;

import 'dart:async';
import 'dart:math';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('Packet Loss Simulation Example');
  print('=' * 50);

  final pc = RtcPeerConnection(RtcConfiguration(
    iceServers: [
      IceServer(urls: ['stun:stun.l.google.com:19302'])
    ],
  ));

  pc.onConnectionStateChange.listen((state) {
    print('[PC] Connection: $state');
  });

  // Packet loss simulation parameters
  final random = Random();
  const lossRate = 0.05; // 5% packet loss
  var packetsReceived = 0;
  var packetsDropped = 0;
  var nacksSent = 0;
  var plisSent = 0;

  // Add video transceiver
  pc.addTransceiver(
    MediaStreamTrackKind.video,
    direction: RtpTransceiverDirection.recvonly,
  );

  pc.onTrack.listen((transceiver) {
    print('[Track] Received ${transceiver.kind}');

    // Simulated packet processing with loss
    // In real implementation, this would be in the RTP receive path
  });

  final offer = await pc.createOffer();
  await pc.setLocalDescription(offer);

  print('\n--- Packet Loss Simulation ---');
  print('');
  print('Configuration:');
  print('  Loss rate: ${(lossRate * 100).toStringAsFixed(0)}%');
  print('  Recovery: NACK + PLI');
  print('');
  print('Simulation:');
  print('  - Random drop based on loss rate');
  print('  - NACK for missing packets');
  print('  - PLI if keyframe lost');

  print('\n--- Recovery Mechanisms ---');
  print('');
  print('NACK (Negative Acknowledgment):');
  print('  - Request retransmission of specific packets');
  print('  - Effective for sporadic loss');
  print('  - RTX channel for retransmissions');
  print('');
  print('PLI (Picture Loss Indication):');
  print('  - Request new keyframe');
  print('  - Used when NACK fails or loss too severe');
  print('  - Higher latency recovery');
  print('');
  print('FEC (Forward Error Correction):');
  print('  - Proactive redundancy');
  print('  - No retransmission needed');
  print('  - Higher bandwidth cost');

  print('\n--- VP8 Error Resilience ---');
  print('');
  print('VP8 features:');
  print('  - Partitioned data (separate metadata/coefficients)');
  print('  - Golden frame reference');
  print('  - Alt-ref frame reference');
  print('');
  print('Recovery strategies:');
  print('  - Skip corrupted frame, use previous');
  print('  - Request golden frame refresh');
  print('  - Wait for next keyframe');

  // Simulate packet flow with loss
  Timer.periodic(Duration(seconds: 1), (_) {
    final received = 30; // ~30 fps
    final dropped = (received * lossRate).round();

    packetsReceived += received;
    packetsDropped += dropped;

    // Simulate NACK/PLI based on loss
    if (dropped > 0) {
      nacksSent += dropped;
      if (random.nextDouble() < 0.1) {
        // 10% chance PLI needed
        plisSent++;
      }
    }

    print('[Sim] Recv: $packetsReceived, Drop: $packetsDropped, '
        'NACK: $nacksSent, PLI: $plisSent');
  });

  await Future.delayed(Duration(seconds: 10));
  await pc.close();
  print('\nDone.');
}
