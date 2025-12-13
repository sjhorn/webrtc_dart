/// GStreamer Recording Example
///
/// Demonstrates forwarding WebRTC media to GStreamer for
/// advanced processing, transcoding, and recording.
///
/// Usage: dart run example/save_to_disk/gst/recorder.dart
library;

import 'dart:async';
import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('GStreamer Recording Example');
  print('=' * 50);

  final pc = RtcPeerConnection(RtcConfiguration(
    iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
  ));

  pc.onConnectionStateChange.listen((state) {
    print('[PC] Connection: $state');
  });

  // Add transceivers
  pc.addTransceiver(
    MediaStreamTrackKind.audio,
    direction: RtpTransceiverDirection.recvonly,
  );
  pc.addTransceiver(
    MediaStreamTrackKind.video,
    direction: RtpTransceiverDirection.recvonly,
  );

  pc.onTrack.listen((transceiver) {
    print('[Track] Received ${transceiver.kind}');

    // In real implementation:
    // 1. Open UDP socket to GStreamer
    // 2. Forward RTP packets with proper headers
    // 3. GStreamer pipeline handles decoding/encoding
  });

  final offer = await pc.createOffer();
  await pc.setLocalDescription(offer);

  print('\n--- GStreamer Integration ---');
  print('');
  print('Architecture:');
  print('  WebRTC -> Dart -> UDP -> GStreamer -> File/Stream');
  print('');
  print('RTP forwarding:');
  print('  - Forward raw RTP packets via UDP');
  print('  - GStreamer uses rtpbin for reception');
  print('  - Handles jitter buffer, depacketization');

  print('\n--- Example GStreamer Pipelines ---');
  print('');
  print('VP8 to WebM:');
  print('  gst-launch-1.0 udpsrc port=5000 caps="application/x-rtp" \\');
  print('    ! rtpvp8depay ! vp8dec ! webmmux ! filesink location=out.webm');
  print('');
  print('H.264 to MP4:');
  print('  gst-launch-1.0 udpsrc port=5000 caps="application/x-rtp" \\');
  print('    ! rtph264depay ! h264parse ! mp4mux ! filesink location=out.mp4');
  print('');
  print('Opus to Ogg:');
  print('  gst-launch-1.0 udpsrc port=5001 caps="application/x-rtp" \\');
  print('    ! rtpopusdepay ! opusparse ! oggmux ! filesink location=out.ogg');
  print('');
  print('Combined A/V recording:');
  print('  gst-launch-1.0 \\');
  print('    udpsrc port=5000 ! queue ! rtpvp8depay ! vp8dec ! mux. \\');
  print('    udpsrc port=5001 ! queue ! rtpopusdepay ! opusdec ! mux. \\');
  print('    webmmux name=mux ! filesink location=av.webm');

  print('\n--- Dart UDP Forwarding ---');
  print('');
  print('Socket setup:');
  print('  final socket = await RawDatagramSocket.bind("127.0.0.1", 0);');
  print('  final gstAddress = InternetAddress("127.0.0.1");');
  print('');
  print('Forward RTP:');
  print('  track.onReceiveRtp.listen((rtp) {');
  print('    socket.send(rtp.serialize(), gstAddress, 5000);');
  print('  });');

  await Future.delayed(Duration(seconds: 2));
  await pc.close();
  print('\nDone.');
}
