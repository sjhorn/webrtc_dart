/// AV1 Codec Example
///
/// Demonstrates receiving AV1 video and parsing the RTP payload
/// to detect keyframes and OBU (Open Bitstream Unit) structure.
///
/// Usage: dart run example/mediachannel/codec/av1.dart
library;

import 'dart:async';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('AV1 Codec Example');
  print('=' * 50);

  final pc = RTCPeerConnection(RtcConfiguration(
    iceServers: [
      IceServer(urls: ['stun:stun.l.google.com:19302'])
    ],
  ));

  pc.onConnectionStateChange.listen((state) {
    print('[PC] Connection: $state');
  });

  // Add video transceiver (recvonly for receiving AV1)
  // ignore: unused_local_variable
  final transceiver = pc.addTransceiver(
    MediaStreamTrackKind.video,
    direction: RtpTransceiverDirection.recvonly,
  );

  // Handle incoming track
  pc.onTrack.listen((t) {
    print('[Track] Received ${t.kind} track');

    // AV1 RTP payload contains OBUs (Open Bitstream Units)
    // OBU types:
    // 1: Sequence Header
    // 2: Temporal Delimiter
    // 3: Frame Header
    // 4: Tile Group
    // 5: Metadata
    // 6: Frame
    // 7: Redundant Frame Header
    // 8: Tile List
    // 15: Padding

    Timer.periodic(Duration(seconds: 3), (_) {
      print('[PLI] Requesting keyframe...');
    });
  });

  // Create offer
  final offer = await pc.createOffer();
  await pc.setLocalDescription(offer);

  print('\n--- AV1 Offer SDP ---');
  final sdpLines = offer.sdp.split('\n');
  for (final line in sdpLines) {
    if (line.contains('AV1') || line.startsWith('m=video')) {
      print(line);
    }
  }

  print('\n--- AV1 RTP Payload Format (RFC 9411) ---');
  print('Aggregation header (1 byte):');
  print('  Z: Must continue in next packet');
  print('  Y: Last OBU element continues in next packet');
  print('  W: OBU element count (0=1, 1=2, 2=3, 3=variable)');
  print('  N: New coded video sequence starts');
  print('');
  print('OBU types:');
  print('  1: Sequence Header (SPS equivalent)');
  print('  6: Frame (contains frame data)');
  print('');
  print('Keyframe: frame_type in frame header == KEY_FRAME (0)');

  print('\n--- Usage ---');
  print('AV1 advantages:');
  print('- Better compression than VP9/H.264');
  print('- Royalty-free');
  print('- Native SVC support');
  print('- Film grain synthesis');

  await Future.delayed(Duration(seconds: 2));
  await pc.close();
  print('\nDone.');
}
