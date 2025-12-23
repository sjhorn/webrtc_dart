/// Receive Only Dump Example
///
/// Receives video from browser and dumps RTP packets to disk.
/// Useful for debugging and analyzing video streams.
///
/// Usage: dart run example/mediachannel/recvonly/dump.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('Receive Only Dump Example');
  print('=' * 50);

  // Create output directory
  final dumpDir = Directory('dump_rtp');
  if (!dumpDir.existsSync()) {
    dumpDir.createSync();
  }

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

    var packetIndex = 0;
    var keyframeReceived = false;

    // Add receive-only video transceiver
    final transceiver = pc.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.recvonly,
    );

    pc.onTrack.listen((t) {
      print('[Track] Receiving video');
    });

    // Listen for RTP on the receiver track
    transceiver.receiver.track.onReceiveRtp.listen((rtp) {
      // Parse VP8 payload to check for keyframes
      final payload = rtp.payload;
      if (payload.isNotEmpty) {
        // VP8 keyframe detection (simplified)
        // First byte & 0x01 == 0 indicates keyframe
        final isKeyframe = (payload[0] & 0x01) == 0;

        if (isKeyframe) {
          print('[VP8] Keyframe received at packet $packetIndex');
          if (keyframeReceived) {
            print('[Done] Second keyframe received, stopping capture');
            pc.close();
            exit(0);
          }
          keyframeReceived = true;
        }
      }

      // Dump RTP packet to file
      final file = File('${dumpDir.path}/dump_$packetIndex.rtp');
      file.writeAsBytesSync(rtp.serialize());
      packetIndex++;

      if (packetIndex % 100 == 0) {
        print('[Dump] $packetIndex packets saved');
      }
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

  print('\n--- RTP Dump Pipeline ---');
  print('');
  print('Browser -> WebRTC -> Dart -> ${dumpDir.path}/dump_*.rtp');
  print('');
  print('Files can be analyzed with:');
  print('  - Wireshark (import as RTP)');
  print('  - Custom tools reading raw RTP');
  print('');
  print('Stops after receiving second keyframe.');

  print('\nWaiting for browser connection...');
}
