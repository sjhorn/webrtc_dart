/// Simulcast Answer Example
///
/// Receives simulcast video from browser and forwards each layer
/// to separate outgoing tracks (SFU-style fanout).
///
/// Usage: dart run example/mediachannel/simulcast/answer.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('Simulcast Answer Example');
  print('=' * 50);

  // WebSocket signaling server
  final wsServer = await HttpServer.bind(InternetAddress.anyIPv4, 8888);
  print('WebSocket server listening on ws://localhost:8888');

  wsServer.transform(WebSocketTransformer()).listen((WebSocket socket) async {
    print('[WS] Client connected');

    final pc = RtcPeerConnection(RtcConfiguration(
      iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
    ));

    pc.onIceConnectionStateChange.listen((state) {
      print('[ICE] Connection: $state');
    });

    // Receive transceiver for incoming simulcast
    pc.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.recvonly,
    );

    // Outgoing transceivers for each simulcast layer
    pc.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.sendonly,
    );
    pc.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.sendonly,
    );
    pc.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.sendonly,
    );

    pc.onTrack.listen((transceiver) {
      print('[Track] Received simulcast layer: ${transceiver.mid}');
    });

    // Wait for offer from browser
    socket.listen((data) async {
      final msg = jsonDecode(data as String);
      final offer = SessionDescription(type: 'offer', sdp: msg['sdp']);
      await pc.setRemoteDescription(offer);
      print('[SDP] Remote description set');

      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      socket.add(jsonEncode({
        'type': 'answer',
        'sdp': answer.sdp,
      }));
      print('[SDP] Answer sent');
    });
  });

  print('\n--- Simulcast SFU Architecture ---');
  print('');
  print('Browser sends simulcast:');
  print('  high (1080p) ─┐');
  print('  mid  (720p)  ─┼─> Dart SFU');
  print('  low  (360p)  ─┘');
  print('');
  print('SFU forwards to subscribers:');
  print('  Dart SFU ─┬─> high track -> Viewer 1');
  print('            ├─> mid track  -> Viewer 2');
  print('            └─> low track  -> Viewer 3');

  print('\nWaiting for browser to send offer...');
}
