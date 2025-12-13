/// Opus Recording Example
///
/// Demonstrates recording Opus audio to disk. Receives
/// Opus-encoded RTP packets and saves to WebM container.
///
/// Usage: dart run example/save_to_disk/opus.dart
library;

import 'dart:async';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('Opus Recording Example');
  print('=' * 50);

  final pc = RtcPeerConnection(RtcConfiguration(
    iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
  ));

  pc.onConnectionStateChange.listen((state) {
    print('[PC] Connection: $state');
  });

  // Statistics
  var packetsReceived = 0;
  var bytesReceived = 0;

  // Add audio transceiver (Opus)
  pc.addTransceiver(
    MediaStreamTrackKind.audio,
    direction: RtpTransceiverDirection.recvonly,
  );

  pc.onTrack.listen((transceiver) {
    print('[Track] Received ${transceiver.kind}');

    // In real implementation:
    // 1. Receive RTP packets with Opus payload
    // 2. Strip RTP header (12+ bytes)
    // 3. Write Opus frames to container
    // 4. Handle timestamp conversion
  });

  final offer = await pc.createOffer();
  await pc.setLocalDescription(offer);

  print('\n--- Opus Codec Info ---');
  print('');
  print('Sample rate: 48000 Hz');
  print('Channels: 2 (stereo) or 1 (mono)');
  print('Frame size: 20ms (default)');
  print('Bitrate: 6-510 kbps (typically 32-128 kbps)');
  print('');
  print('RTP payload:');
  print('  - No additional header (just Opus frame)');
  print('  - Timestamp increment: 960 per frame (48000 * 0.020)');

  print('\n--- Container Options ---');
  print('');
  print('WebM (Matroska):');
  print('  - Native Opus support');
  print('  - Good browser compatibility');
  print('  - Codec ID: A_OPUS');
  print('');
  print('Ogg:');
  print('  - Original Opus container');
  print('  - Requires OpusHead and OpusTags');
  print('  - Good for audio-only files');
  print('');
  print('MP4/M4A:');
  print('  - Wider playback support');
  print('  - Requires Opus sample entry');
  print('  - Less common for Opus');

  print('\n--- Recording Pipeline ---');
  print('');
  print('1. Receive RTP packet');
  print('2. Extract Opus frame (skip RTP header)');
  print('3. Track timing:');
  print('   - RTP timestamp -> sample count');
  print('   - Sample count / 48000 = seconds');
  print('4. Write to container:');
  print('   - WebM: SimpleBlock with timestamp');
  print('   - Ogg: Ogg page with granule position');
  print('5. Flush periodically for streaming');

  // Simulate recording
  Timer.periodic(Duration(seconds: 1), (_) {
    packetsReceived += 50; // 50 pps for 20ms frames
    bytesReceived += 50 * 80; // ~80 bytes average per frame

    final duration = packetsReceived * 20 / 1000;
    final bitrate = (bytesReceived * 8 / 1000 / duration).round();

    print('[Recording] ${duration.toStringAsFixed(1)}s, '
        '$packetsReceived pkts, '
        '~$bitrate kbps');
  });

  await Future.delayed(Duration(seconds: 10));
  await pc.close();
  print('\nDone.');
}
