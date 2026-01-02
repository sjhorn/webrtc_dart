/// RTX Simulcast Answer Example
///
/// Receives simulcast video with RTX and handles retransmission
/// requests for lost packets on each layer.
///
/// Usage: dart run example/mediachannel/rtx/simulcast_answer.dart
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('RTX Simulcast Answer Example');
  print('=' * 50);

  // WebSocket signaling
  final wsServer = await HttpServer.bind(InternetAddress.anyIPv4, 8888);
  print('WebSocket server listening on ws://localhost:8888');

  wsServer.transform(WebSocketTransformer()).listen((WebSocket socket) async {
    print('[WS] Client connected');

    final pc = RTCPeerConnection(RtcConfiguration(
      iceServers: [
        IceServer(urls: ['stun:stun.l.google.com:19302'])
      ],
    ));

    pc.onConnectionStateChange.listen((state) {
      print('[PC] Connection: $state');
    });

    // Track stats per layer
    final layerStats = <String, _LayerStats>{};
    var lastSeq = -1;

    // Add receive transceiver
    final transceiver = pc.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.recvonly,
    );

    pc.onTrack.listen((t) {
      final rid = t.mid ?? 'unknown';
      print('[Track] Received layer: $rid');
      layerStats[rid] = _LayerStats();
    });

    // Listen for RTP on the receiver track
    transceiver.receiver.track.onReceiveRtp.listen((rtp) {
      final rid = transceiver.mid ?? 'unknown';
      if (!layerStats.containsKey(rid)) {
        layerStats[rid] = _LayerStats();
      }
      final stats = layerStats[rid]!;
      stats.packetsReceived++;

      // Detect gaps (potential packet loss)
      if (lastSeq >= 0) {
        final expectedSeq = (lastSeq + 1) & 0xFFFF;
        if (rtp.sequenceNumber != expectedSeq) {
          final gap = (rtp.sequenceNumber - lastSeq) & 0xFFFF;
          stats.gaps++;
          print(
              '[$rid] Gap detected: expected $expectedSeq, got ${rtp.sequenceNumber} (gap: $gap)');
        }
      }
      lastSeq = rtp.sequenceNumber;
    });

    // Stats timer
    Timer.periodic(Duration(seconds: 5), (_) {
      for (final entry in layerStats.entries) {
        print(
            '[Stats] ${entry.key}: ${entry.value.packetsReceived} pkts, ${entry.value.gaps} gaps');
      }
    });

    // Wait for offer from browser
    socket.listen((data) async {
      final msg = jsonDecode(data as String);
      final offer = RTCSessionDescription(type: 'offer', sdp: msg['sdp']);
      await pc.setRemoteDescription(offer);
      print('[SDP] Remote description set');

      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      socket.add(jsonEncode({
        'type': 'answer',
        'sdp': answer.sdp,
      }));
      print('[SDP] Answer sent');
    }, onDone: () {
      pc.close();
    });
  });

  print('\n--- RTX Recovery Flow ---');
  print('');
  print('1. Sender transmits simulcast layers');
  print('2. Receiver detects sequence gaps');
  print('3. Receiver sends NACK for missing packets');
  print('4. Sender retransmits via RTX stream');
  print('');
  print('Stats printed every 5 seconds');

  print('\nWaiting for browser to send offer...');
}

class _LayerStats {
  int packetsReceived = 0;
  int gaps = 0;
}
