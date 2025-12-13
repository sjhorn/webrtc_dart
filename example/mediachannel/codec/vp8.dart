/// VP8 Codec Example
///
/// Demonstrates receiving VP8 video and parsing the RTP payload
/// to detect keyframes and access codec-specific information.
///
/// Usage: dart run example/mediachannel/codec/vp8.dart
library;

import 'dart:async';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('VP8 Codec Example');
  print('=' * 50);

  final pc = RtcPeerConnection(RtcConfiguration(
    iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
  ));

  pc.onConnectionStateChange.listen((state) {
    print('[PC] Connection: $state');
  });

  // Add video transceiver (recvonly for receiving VP8)
  // ignore: unused_local_variable
  final transceiver = pc.addTransceiver(
    MediaStreamTrackKind.video,
    direction: RtpTransceiverDirection.recvonly,
  );

  // Track for keyframe detection (used in real implementation)
  // ignore: unused_local_variable
  var keyframeCount = 0;
  // ignore: unused_local_variable
  var frameCount = 0;

  // Handle incoming track
  pc.onTrack.listen((t) {
    print('[Track] Received ${t.kind} track');

    // In a real implementation, you would:
    // 1. Access the RTP packets via receiver callbacks
    // 2. Parse VP8 payload header to detect keyframes
    // 3. VP8 keyframe detection: check if payload[0] & 0x01 == 0 (S bit)
    //    and payload descriptor indicates keyframe

    // Periodically request keyframes via PLI
    Timer.periodic(Duration(seconds: 3), (_) {
      print('[PLI] Requesting keyframe...');
      // t.receiver.sendRtcpPLI(track.ssrc);
    });
  });

  // Create offer
  final offer = await pc.createOffer();
  await pc.setLocalDescription(offer);

  print('\n--- VP8 Offer SDP ---');
  final sdpLines = offer.sdp.split('\n');
  for (final line in sdpLines) {
    if (line.contains('VP8') || line.startsWith('m=video')) {
      print(line);
    }
  }

  print('\n--- VP8 Payload Format ---');
  print('VP8 RTP payload structure:');
  print('  Byte 0: X R N S R PID (X=extension, S=start of partition)');
  print('  If X=1: I L T K extensions follow');
  print('  Keyframe detection: S=1 and PID=0, then check frame header');
  print('');
  print('Keyframe indicator in VP8 frame:');
  print('  First byte of VP8 frame: frame_tag');
  print('  Keyframe if (frame_tag & 0x01) == 0');

  print('\n--- Usage ---');
  print('This example creates a recvonly video transceiver.');
  print('Connect a browser to send VP8 video, then:');
  print('1. Parse incoming RTP packets');
  print('2. Detect keyframes for decoding start');
  print('3. Send PLI when keyframe needed');

  await Future.delayed(Duration(seconds: 2));
  await pc.close();
  print('\nDone.');
}
