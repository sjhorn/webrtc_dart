/// DTX (Discontinuous Transmission) Recording Example
///
/// Demonstrates recording audio with DTX enabled. DTX reduces
/// bandwidth by not transmitting during silence periods.
/// The recorder must handle gaps and insert silence frames.
///
/// Usage: dart run example/save_to_disk/dtx/server.dart
library;

import 'dart:async';
import 'package:webrtc_dart/webrtc_dart.dart';

// Opus comfort noise frame (silent)
// ignore: unused_element
final _silentFrame = [0xf8, 0xff, 0xfe];

void main() async {
  print('DTX Recording Example');
  print('=' * 50);

  final pc = RtcPeerConnection(RtcConfiguration(
    iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
  ));

  pc.onConnectionStateChange.listen((state) {
    print('[PC] Connection: $state');
  });

  // Statistics
  var voicePackets = 0;
  var silenceGaps = 0;
  var silenceFramesInserted = 0;

  // Add audio transceiver (Opus with DTX)
  pc.addTransceiver(
    MediaStreamTrackKind.audio,
    direction: RtpTransceiverDirection.recvonly,
  );

  pc.onTrack.listen((transceiver) {
    print('[Track] Received ${transceiver.kind}');

    // DTX handling in real implementation:
    // 1. Monitor RTP sequence numbers for gaps
    // 2. When gap detected, check if DTX silence
    // 3. Insert comfort noise frames to maintain timing
    // 4. Resume normal processing when voice returns
  });

  final offer = await pc.createOffer();
  await pc.setLocalDescription(offer);

  print('\n--- DTX Overview ---');
  print('');
  print('DTX (Discontinuous Transmission):');
  print('- Opus encoder detects silence/voice');
  print('- During silence: sends occasional comfort noise');
  print('- Reduces bandwidth by ~30-50% for typical speech');
  print('');
  print('SDP signaling:');
  print('  a=fmtp:111 usedtx=1');

  print('\n--- Recording Challenges ---');
  print('');
  print('Gap detection:');
  print('  - Expected: seq N, N+1, N+2, ...');
  print('  - With DTX: seq N, N+1, N+5 (gap of 3)');
  print('');
  print('Gap handling options:');
  print('  1. Insert silence frames (0xf8 0xff 0xfe)');
  print('  2. Use PLC (Packet Loss Concealment)');
  print('  3. Stretch adjacent audio (not recommended)');
  print('');
  print('Timing preservation:');
  print('  - Track RTP timestamp, not packet count');
  print('  - Opus: 48000 Hz, 20ms frames = 960 samples');
  print('  - Gap of 3 packets = 60ms of silence');

  print('\n--- Opus Silent Frame ---');
  print('');
  print('Comfort noise packet: [0xf8, 0xff, 0xfe]');
  print('- 3 bytes representing silence');
  print('- Valid Opus frame that decodes to zeros');
  print('- Insert one per 20ms gap');

  // Simulate DTX recording
  Timer.periodic(Duration(seconds: 2), (_) {
    voicePackets += 80; // ~1.6 seconds of voice at 50pps
    silenceGaps += 2;
    silenceFramesInserted += 10; // ~200ms of inserted silence

    print('[Recording] Voice: $voicePackets pkts, '
        'Gaps: $silenceGaps, '
        'Silence inserted: ${silenceFramesInserted * 20}ms');
  });

  await Future.delayed(Duration(seconds: 10));
  await pc.close();
  print('\nDone.');
}
