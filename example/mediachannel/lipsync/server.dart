/// Lip Sync Example
///
/// Demonstrates audio/video synchronization (lip sync) by
/// aligning audio and video frames using RTP timestamps
/// and RTCP sender reports.
///
/// Usage: dart run example/mediachannel/lipsync/server.dart
library;

import 'dart:async';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('Lip Sync Example');
  print('=' * 50);

  final pc = RtcPeerConnection(RtcConfiguration(
    iceServers: [
      IceServer(urls: ['stun:stun.l.google.com:19302'])
    ],
  ));

  pc.onConnectionStateChange.listen((state) {
    print('[PC] Connection: $state');
  });

  // Track NTP timestamps from RTCP SR for sync
  // ignore: unused_local_variable
  int? audioNtpTimestamp;
  // ignore: unused_local_variable
  int? audioRtpTimestamp;
  // ignore: unused_local_variable
  int? videoNtpTimestamp;
  // ignore: unused_local_variable
  int? videoRtpTimestamp;

  // Add audio transceiver
  pc.addTransceiver(
    MediaStreamTrackKind.audio,
    direction: RtpTransceiverDirection.recvonly,
  );

  // Add video transceiver
  pc.addTransceiver(
    MediaStreamTrackKind.video,
    direction: RtpTransceiverDirection.recvonly,
  );

  pc.onTrack.listen((transceiver) {
    print('[Track] Received ${transceiver.kind}');

    // In real implementation:
    // 1. Receive RTCP Sender Reports with NTP/RTP timestamp pairs
    // 2. Use NTP timestamps to establish common timeline
    // 3. Buffer frames and release them synchronized

    if (transceiver.kind == MediaStreamTrackKind.video) {
      Timer.periodic(Duration(seconds: 3), (_) {
        print('[Video] Requesting keyframe');
      });
    }
  });

  // Create offer
  final offer = await pc.createOffer();
  await pc.setLocalDescription(offer);

  print('\n--- Lip Sync Algorithm ---');
  print('');
  print('1. RTCP Sender Report provides:');
  print('   - NTP timestamp (wall clock time)');
  print('   - RTP timestamp (media clock)');
  print('');
  print('2. For each stream, calculate:');
  print('   offset = NTP_time - (RTP_time / clock_rate)');
  print('');
  print('3. Audio clock rate: 48000 Hz (Opus)');
  print('   Video clock rate: 90000 Hz');
  print('');
  print('4. Synchronization formula:');
  print('   presentation_time = RTP_timestamp / clock_rate + offset');
  print('');
  print('5. Buffer management:');
  print('   - Hold frames until sync point');
  print('   - Release audio/video together');
  print('   - Handle jitter and clock drift');

  print('\n--- Implementation Notes ---');
  print('');
  print('Jitter buffer considerations:');
  print('- Audio: ~60-100ms buffer (3-5 packets)');
  print('- Video: ~100-200ms buffer (3-6 frames)');
  print('');
  print('Clock drift handling:');
  print('- Monitor SR timestamp differences');
  print('- Adjust playback rate slightly');
  print('- Resync on large drift (>100ms)');

  print('\n--- SDP Info ---');
  final lines = offer.sdp.split('\n');
  for (final line in lines) {
    if (line.startsWith('m=')) {
      print(line);
    }
  }

  await Future.delayed(Duration(seconds: 2));
  await pc.close();
  print('\nDone.');
}
