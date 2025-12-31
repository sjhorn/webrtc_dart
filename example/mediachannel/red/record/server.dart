/// RED Recording Example
///
/// Demonstrates recording audio with RED (Redundant Encoding)
/// and extracting the primary audio stream for storage.
///
/// Usage: dart run example/mediachannel/red/record/server.dart
library;

import 'dart:async';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('RED Recording Example');
  print('=' * 50);

  final pc = RtcPeerConnection(RtcConfiguration(
    iceServers: [
      IceServer(urls: ['stun:stun.l.google.com:19302'])
    ],
  ));

  pc.onConnectionStateChange.listen((state) {
    print('[PC] Connection: $state');
  });

  // Statistics
  var redPacketsReceived = 0;
  var primaryExtracted = 0;
  var redundantUsed = 0;

  // Add audio transceiver
  pc.addTransceiver(
    MediaStreamTrackKind.audio,
    direction: RtpTransceiverDirection.recvonly,
  );

  pc.onTrack.listen((transceiver) {
    print('[Track] Received ${transceiver.kind}');

    // In real implementation:
    // 1. Receive RED packets
    // 2. Parse RED header to find primary and redundant blocks
    // 3. Extract primary audio for recording
    // 4. Use redundant data to fill gaps from lost packets
    // 5. Write to output file (WebM, Ogg, etc.)
  });

  final offer = await pc.createOffer();
  await pc.setLocalDescription(offer);

  print('\n--- RED Recording Pipeline ---');
  print('');
  print('1. Receive RTP packet with RED payload');
  print('2. Check payload type (RED PT typically 127)');
  print('3. Parse RED blocks:');
  print('   - Extract primary block (last block, F=0)');
  print('   - Store redundant blocks for recovery');
  print('4. Sequence number tracking:');
  print('   - Detect missing packets');
  print('   - Use redundant data from subsequent packets');
  print('5. Write recovered audio to file');

  print('\n--- Recovery Process ---');
  print('');
  print('Normal packet received:');
  print('  -> Extract primary, store redundant');
  print('');
  print('Packet lost (gap in sequence):');
  print('  -> Wait for next packet');
  print('  -> Check if redundant block covers gap');
  print('  -> Insert recovered audio at correct position');

  print('\n--- Output Format ---');
  print('');
  print('Recording options:');
  print('  - WebM container with Opus codec');
  print('  - Ogg container with Opus codec');
  print('  - Raw PCM (after decoding)');
  print('');
  print('Timestamp handling:');
  print('  - Use RTP timestamps for timing');
  print('  - Convert to container timestamps');
  print('  - Handle timestamp wraparound');

  // Simulate recording stats
  Timer.periodic(Duration(seconds: 2), (_) {
    redPacketsReceived += 100;
    primaryExtracted += 100;
    redundantUsed += 2; // ~2% recovery rate

    print('[Recording] Packets: $redPacketsReceived, '
        'Primary: $primaryExtracted, '
        'Recovered: $redundantUsed');
  });

  print('\nRecording... (Ctrl+C to stop)');
  await Future.delayed(Duration(seconds: 10));

  await pc.close();
  print('\nRecording stopped.');
}
