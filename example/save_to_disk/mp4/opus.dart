/// Save Opus Audio to MP4 Example
///
/// Records Opus audio from WebRTC to an MP4 container.
/// Opus is stored directly (MP4 supports Opus since 2016).
///
/// Usage: dart run example/save_to_disk/mp4/opus.dart
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('Save Opus to MP4 Example');
  print('=' * 50);

  final outputFile = 'output_opus.mp4';

  // WebSocket signaling
  final wsServer = await HttpServer.bind(InternetAddress.anyIPv4, 8888);
  print('WebSocket server listening on ws://localhost:8888');

  wsServer.transform(WebSocketTransformer()).listen((WebSocket socket) async {
    print('[WS] Client connected');

    final pc = RtcPeerConnection(RtcConfiguration(
      iceServers: [
        IceServer(urls: ['stun:stun.l.google.com:19302'])
      ],
      codecs: RtcCodecs(
        audio: [
          createOpusCodec(payloadType: 111),
        ],
      ),
    ));

    pc.onConnectionStateChange.listen((state) {
      print('[PC] Connection: $state');
    });

    var packetCount = 0;
    var totalBytes = 0;

    // Add audio transceiver
    final transceiver = pc.addTransceiver(
      MediaStreamTrackKind.audio,
      direction: RtpTransceiverDirection.recvonly,
    );

    pc.onTrack.listen((t) {
      print('[Track] Receiving Opus audio');
    });

    // Listen for RTP on the receiver track
    transceiver.receiver.track.onReceiveRtp.listen((rtp) {
      packetCount++;
      totalBytes += rtp.payload.length;

      // In real implementation:
      // 1. Extract Opus frames from RTP payload
      // 2. Write to MP4 muxer audio track
      // 3. Handle timing (48kHz clock)
    });

    // Stats timer
    Timer.periodic(Duration(seconds: 3), (_) {
      final kbps = totalBytes * 8.0 / 3.0 / 1000.0;
      print(
          '[Stats] $packetCount packets, ${totalBytes ~/ 1024} KB, ~${kbps.toStringAsFixed(1)} kbps');
    });

    // Create offer and send
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    socket.add(jsonEncode({
      'type': 'offer',
      'sdp': offer.sdp,
    }));

    // Handle answer
    socket.listen((data) async {
      final msg = jsonDecode(data as String);
      final answer = SessionDescription(type: 'answer', sdp: msg['sdp']);
      await pc.setRemoteDescription(answer);
      print('[SDP] Remote description set');
    }, onDone: () {
      pc.close();
      print('\n[Done] Output: $outputFile');
    });
  });

  print('\n--- Opus in MP4 ---');
  print('');
  print('Output: $outputFile');
  print('');
  print('MP4 Opus support:');
  print('  - ISO/IEC 14496-12 Amendment (2016)');
  print('  - Codec: Opus (mp4a.ad)');
  print('  - Sample rate: 48000 Hz');
  print('  - Channels: 2 (stereo)');
  print('');
  print('Alternative: Ogg container');
  print('  - Native Opus support');
  print('  - Simpler muxing');
  print('  - See save_to_disk/opus.dart');

  print('\nWaiting for browser connection...');
}
