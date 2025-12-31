/// Send/Receive Answer Example
///
/// Answers browser offers for bidirectional media exchange.
/// Browser sends video, server echoes it back.
///
/// Usage: dart run example/mediachannel/sendrecv/answer.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('Send/Receive Answer Example');
  print('=' * 50);

  // WebSocket signaling server
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

    // Handle incoming tracks
    pc.onTrack.listen((transceiver) {
      print('[Track] Received ${transceiver.kind}');
    });

    // Wait for offer from browser
    socket.listen((data) async {
      final msg = jsonDecode(data as String);

      if (msg['type'] == 'offer') {
        final offer = SessionDescription(type: 'offer', sdp: msg['sdp']);
        await pc.setRemoteDescription(offer);
        print('[SDP] Remote description set');

        // Add sendrecv transceiver for echo
        pc.addTransceiver(
          MediaStreamTrackKind.video,
          direction: RtpTransceiverDirection.sendrecv,
        );

        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        socket.add(jsonEncode({
          'type': 'answer',
          'sdp': answer.sdp,
        }));
        print('[SDP] Answer sent');
      } else if (msg['candidate'] != null) {
        final candidate = Candidate.fromSdp(msg['candidate']);
        await pc.addIceCandidate(candidate);
      }
    }, onDone: () {
      print('[WS] Client disconnected');
      pc.close();
    });
  });

  print('\n--- Echo Server ---');
  print('');
  print('Browser sends video, server echoes it back:');
  print('  Browser Camera -> Server -> Browser Display');
  print('');
  print('Useful for:');
  print('  - Testing round-trip latency');
  print('  - Verifying bidirectional media');
  print('  - Debugging codec negotiation');

  print('\nWaiting for browser to send offer...');
}
