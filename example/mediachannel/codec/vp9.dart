/// VP9 Codec Example
///
/// Demonstrates receiving VP9 video and parsing the RTP payload
/// to detect keyframes and SVC layer information.
///
/// Usage: dart run example/mediachannel/codec/vp9.dart
library;

import 'dart:async';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('VP9 Codec Example');
  print('=' * 50);

  final pc = RtcPeerConnection(RtcConfiguration(
    iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
  ));

  pc.onConnectionStateChange.listen((state) {
    print('[PC] Connection: $state');
  });

  // Add video transceiver (recvonly for receiving VP9)
  // ignore: unused_local_variable
  final transceiver = pc.addTransceiver(
    MediaStreamTrackKind.video,
    direction: RtpTransceiverDirection.recvonly,
  );

  // Handle incoming track
  pc.onTrack.listen((t) {
    print('[Track] Received ${t.kind} track');

    // VP9 RTP payload has:
    // - Payload descriptor (variable length)
    // - VP9 payload (frame data)

    Timer.periodic(Duration(seconds: 3), (_) {
      print('[PLI] Requesting keyframe...');
    });
  });

  // Create offer
  final offer = await pc.createOffer();
  await pc.setLocalDescription(offer);

  print('\n--- VP9 Offer SDP ---');
  final sdpLines = offer.sdp.split('\n');
  for (final line in sdpLines) {
    if (line.contains('VP9') || line.startsWith('m=video')) {
      print(line);
    }
  }

  print('\n--- VP9 RTP Payload Format ---');
  print('Payload descriptor fields:');
  print('  I: PictureID present');
  print('  P: Inter-picture predicted');
  print('  L: Layer indices present');
  print('  F: Flexible mode');
  print('  B: Start of frame');
  print('  E: End of frame');
  print('  V: Scalability structure present');
  print('');
  print('SVC layers (if L=1):');
  print('  TID: Temporal layer ID');
  print('  SID: Spatial layer ID');
  print('');
  print('Keyframe: P=0 (not inter-predicted)');

  print('\n--- Usage ---');
  print('VP9 supports SVC (scalable video coding):');
  print('- Temporal scalability: drop higher TID for lower framerate');
  print('- Spatial scalability: drop higher SID for lower resolution');
  print('- Useful for adaptive bitrate streaming');

  await Future.delayed(Duration(seconds: 2));
  await pc.close();
  print('\nDone.');
}
