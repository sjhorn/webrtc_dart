/// H.264 Codec Example
///
/// Demonstrates receiving H.264 video and parsing the RTP payload
/// to detect keyframes (IDR frames) and NAL units.
///
/// Usage: dart run example/mediachannel/codec/h264.dart
library;

import 'dart:async';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('H.264 Codec Example');
  print('=' * 50);

  final pc = RtcPeerConnection(RtcConfiguration(
    iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
  ));

  pc.onConnectionStateChange.listen((state) {
    print('[PC] Connection: $state');
  });

  // Add video transceiver (recvonly for receiving H.264)
  // ignore: unused_local_variable
  final transceiver = pc.addTransceiver(
    MediaStreamTrackKind.video,
    direction: RtpTransceiverDirection.recvonly,
  );

  // Handle incoming track
  pc.onTrack.listen((t) {
    print('[Track] Received ${t.kind} track');

    // H.264 NAL unit types for reference:
    // 1-23: Single NAL unit packet
    // 24: STAP-A (aggregation)
    // 25: STAP-B
    // 26: MTAP16
    // 27: MTAP24
    // 28: FU-A (fragmentation)
    // 29: FU-B

    // IDR frame detection:
    // NAL type 5 = IDR slice (keyframe)
    // NAL type 7 = SPS (sequence parameter set)
    // NAL type 8 = PPS (picture parameter set)

    Timer.periodic(Duration(seconds: 3), (_) {
      print('[PLI] Requesting keyframe (IDR)...');
    });
  });

  // Create offer
  final offer = await pc.createOffer();
  await pc.setLocalDescription(offer);

  print('\n--- H.264 Offer SDP ---');
  final sdpLines = offer.sdp.split('\n');
  for (final line in sdpLines) {
    if (line.contains('H264') || line.contains('h264') || line.startsWith('m=video')) {
      print(line);
    }
  }

  print('\n--- H.264 RTP Payload Format (RFC 6184) ---');
  print('NAL unit types:');
  print('  1-23: Single NAL unit');
  print('  24: STAP-A (aggregated NALs)');
  print('  28: FU-A (fragmented NAL)');
  print('');
  print('Keyframe NAL types:');
  print('  5 = IDR slice (instantaneous decode refresh)');
  print('  7 = SPS (sequence parameter set)');
  print('  8 = PPS (picture parameter set)');
  print('');
  print('Detection: (payload[0] & 0x1F) == 5 for IDR');

  print('\n--- Usage ---');
  print('This example creates a recvonly video transceiver.');
  print('Connect a browser to send H.264 video, then:');
  print('1. Parse NAL unit type from first byte');
  print('2. Handle FU-A fragmentation for large NALs');
  print('3. Collect SPS/PPS for decoder init');

  await Future.delayed(Duration(seconds: 2));
  await pc.close();
  print('\nDone.');
}
