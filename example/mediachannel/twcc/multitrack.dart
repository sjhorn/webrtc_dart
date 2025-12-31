/// TWCC Multi-Track Example
///
/// Demonstrates Transport-Wide Congestion Control with
/// multiple video tracks sharing bandwidth estimation.
///
/// Usage: dart run example/mediachannel/twcc/multitrack.dart
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';
import 'package:webrtc_dart/src/nonstandard/media/track.dart' as nonstandard;

void main() async {
  print('TWCC Multi-Track Example');
  print('=' * 50);

  // WebSocket signaling
  final wsServer = await HttpServer.bind(InternetAddress.anyIPv4, 8888);
  print('WebSocket server listening on ws://localhost:8888');

  wsServer.transform(WebSocketTransformer()).listen((WebSocket socket) async {
    print('[WS] Client connected');

    final pc = RtcPeerConnection(RtcConfiguration(
      iceServers: [
        IceServer(urls: ['stun:stun.l.google.com:19302'])
      ],
    ));

    pc.onConnectionStateChange.listen((state) {
      print('[PC] Connection: $state');
    });

    // Create multiple video tracks
    final tracks = <nonstandard.MediaStreamTrack>[];
    for (var i = 0; i < 3; i++) {
      final track =
          nonstandard.MediaStreamTrack(kind: nonstandard.MediaKind.video);
      tracks.add(track);

      pc.addTransceiver(
        track,
        direction: RtpTransceiverDirection.sendonly,
      );
      print('[Track] Added video track $i');
    }

    // TWCC feedback handler simulation
    var estimatedBandwidth = 2500000; // 2.5 Mbps initial estimate

    Timer.periodic(Duration(seconds: 2), (_) {
      print('[TWCC] Estimated bandwidth: ${estimatedBandwidth ~/ 1000} kbps');
      print(
          '[TWCC] Per-track allocation: ${estimatedBandwidth ~/ tracks.length ~/ 1000} kbps');
    });

    // Create and send offer
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
    });
  });

  print('\n--- TWCC with Multiple Tracks ---');
  print('');
  print('Transport-Wide CC provides:');
  print('  - Single bandwidth estimate for all tracks');
  print('  - Coordinated rate allocation');
  print('  - Better congestion response');
  print('');
  print('Alternative to per-track REMB:');
  print('  REMB: Each track estimates independently');
  print('  TWCC: Shared estimate, coordinated adaptation');
  print('');
  print(
      'SDP extension: a=extmap:5 http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01');

  print('\nWaiting for browser connection...');
}
