/// RED Receive Example
///
/// Demonstrates receiving audio with RED (Redundant Encoding)
/// and forwarding to UDP for external processing.
///
/// Usage: dart run example/mediachannel/red/recv.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('RED Receive Example');
  print('=' * 50);

  // UDP socket for forwarding RTP
  final udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  final forwardPort = 4005;

  // WebSocket signaling server
  final wsServer = await HttpServer.bind(InternetAddress.anyIPv4, 8888);
  print('WebSocket server listening on ws://localhost:8888');

  wsServer.transform(WebSocketTransformer()).listen((WebSocket socket) async {
    print('[WS] Client connected');

    final pc = RtcPeerConnection(RtcConfiguration(
      codecs: RtcCodecs(
        audio: [
          // RED codec wraps Opus for redundancy
          RtpCodecParameters(
            mimeType: 'audio/RED',
            clockRate: 48000,
            channels: 2,
          ),
          RtpCodecParameters(
            mimeType: 'audio/OPUS',
            clockRate: 48000,
            channels: 2,
          ),
        ],
      ),
    ));

    pc.onConnectionStateChange.listen((state) {
      print('[PC] Connection: $state');
    });

    // Add receive-only audio transceiver
    final transceiver = pc.addTransceiver(
      MediaStreamTrackKind.audio,
      direction: RtpTransceiverDirection.recvonly,
    );

    pc.onTrack.listen((t) {
      print('[Track] Receiving audio with RED');
    });

    // Forward RTP packets to UDP for external processing
    transceiver.receiver.track.onReceiveRtp.listen((rtp) {
      udp.send(rtp.serialize(), InternetAddress.loopbackIPv4, forwardPort);
    });

    // Create offer and send to browser
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    socket.add(jsonEncode({
      'type': 'offer',
      'sdp': offer.sdp,
    }));

    // Handle answer from browser
    socket.listen((data) async {
      final msg = jsonDecode(data as String);
      final answer = SessionDescription(type: 'answer', sdp: msg['sdp']);
      await pc.setRemoteDescription(answer);
      print('[SDP] Remote description set');
    });
  });

  print('\n--- RED Receive Pipeline ---');
  print('');
  print('Browser -> WebRTC -> Dart -> UDP:$forwardPort');
  print('');
  print('External processing options:');
  print('  - GStreamer: udpsrc port=$forwardPort ! rtpredepay ! ...');
  print('  - FFmpeg: ffmpeg -i udp://localhost:$forwardPort ...');
  print('  - Custom decoder reading UDP packets');

  print('\nWaiting for browser connection...');
}
