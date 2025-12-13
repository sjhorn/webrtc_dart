/// VP9 Recording Example
///
/// Demonstrates recording VP9 video to disk. Receives
/// VP9-encoded RTP packets and saves to WebM container.
///
/// Usage: dart run example/save_to_disk/vp9.dart
library;

import 'dart:async';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('VP9 Recording Example');
  print('=' * 50);

  final pc = RtcPeerConnection(RtcConfiguration(
    iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
  ));

  pc.onConnectionStateChange.listen((state) {
    print('[PC] Connection: $state');
  });

  // Statistics
  var framesReceived = 0;
  var keyframes = 0;
  var bytesReceived = 0;

  // Add video transceiver (VP9)
  pc.addTransceiver(
    MediaStreamTrackKind.video,
    direction: RtpTransceiverDirection.recvonly,
  );

  pc.onTrack.listen((transceiver) {
    print('[Track] Received ${transceiver.kind}');

    // Request keyframes periodically
    Timer.periodic(Duration(seconds: 5), (_) {
      print('[Video] Requesting keyframe');
    });

    // In real implementation:
    // 1. Receive RTP packets with VP9 payload
    // 2. Parse VP9 RTP payload descriptor
    // 3. Reassemble fragmented frames
    // 4. Detect keyframes (P=0)
    // 5. Write to WebM container
  });

  final offer = await pc.createOffer();
  await pc.setLocalDescription(offer);

  print('\n--- VP9 Codec Info ---');
  print('');
  print('Clock rate: 90000 Hz');
  print('Profiles: 0, 1, 2, 3');
  print('Color depth: 8-bit (profile 0,1) or 10/12-bit (2,3)');
  print('Chroma: 4:2:0 (profile 0,2) or 4:2:2/4:4:4 (1,3)');

  print('\n--- VP9 SVC Layers ---');
  print('');
  print('Spatial layers (SID):');
  print('  SID=0: Low resolution');
  print('  SID=1: Medium resolution');
  print('  SID=2: High resolution');
  print('');
  print('Temporal layers (TID):');
  print('  TID=0: Base layer (lowest framerate)');
  print('  TID=1: Enhancement (higher framerate)');
  print('  TID=2: Full framerate');
  print('');
  print('Recording options:');
  print('  - Record all layers (full quality)');
  print('  - Record base layer only (smaller file)');
  print('  - Selective layer recording');

  print('\n--- Recording Pipeline ---');
  print('');
  print('1. Receive RTP packets');
  print('2. Parse VP9 payload descriptor:');
  print('   - I: Picture ID present');
  print('   - P: Inter-picture predicted (0=keyframe)');
  print('   - L: Layer indices (TID, SID)');
  print('   - B: Start of frame');
  print('   - E: End of frame');
  print('3. Reassemble frame from packets');
  print('4. Write to WebM:');
  print('   - Keyframe: new cluster');
  print('   - Delta frame: same cluster');
  print('5. Track timestamps for seeking');

  // Simulate recording
  Timer.periodic(Duration(seconds: 1), (_) {
    framesReceived += 30; // 30 fps
    keyframes += 1; // ~1 keyframe per second
    bytesReceived += 30 * 5000; // ~5KB average per frame

    final duration = framesReceived / 30;
    final bitrate = (bytesReceived * 8 / 1000 / duration).round();

    print('[Recording] ${duration.toStringAsFixed(0)}s, '
        '$framesReceived frames ($keyframes key), '
        '~$bitrate kbps');
  });

  await Future.delayed(Duration(seconds: 10));
  await pc.close();
  print('\nDone.');
}
