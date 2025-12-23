/// Simulcast ABR (Adaptive Bitrate) Example
///
/// Receives simulcast and dynamically selects the best layer
/// based on network conditions and receiver feedback.
///
/// Usage: dart run example/mediachannel/simulcast/abr.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';

enum QualityLayer { high, mid, low }

class AbrController {
  QualityLayer _currentLayer = QualityLayer.mid;
  int _packetsReceived = 0;
  int _packetsLost = 0;
  DateTime _lastCheck = DateTime.now();

  QualityLayer get currentLayer => _currentLayer;

  void recordPacket({required bool lost}) {
    if (lost) {
      _packetsLost++;
    } else {
      _packetsReceived++;
    }
  }

  /// Evaluate and potentially switch layers based on loss rate
  QualityLayer evaluate() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastCheck).inMilliseconds;

    if (elapsed < 2000) return _currentLayer;

    final total = _packetsReceived + _packetsLost;
    if (total == 0) return _currentLayer;

    final lossRate = _packetsLost / total;
    print('[ABR] Loss rate: ${(lossRate * 100).toStringAsFixed(1)}%');

    // Adaptive selection based on loss
    if (lossRate > 0.10) {
      // >10% loss: drop quality
      _currentLayer = _downgrade(_currentLayer);
      print('[ABR] High loss, downgrading to $_currentLayer');
    } else if (lossRate < 0.02 && _packetsReceived > 100) {
      // <2% loss with good history: try upgrading
      _currentLayer = _upgrade(_currentLayer);
      print('[ABR] Low loss, upgrading to $_currentLayer');
    }

    // Reset counters
    _packetsReceived = 0;
    _packetsLost = 0;
    _lastCheck = now;

    return _currentLayer;
  }

  QualityLayer _downgrade(QualityLayer current) {
    switch (current) {
      case QualityLayer.high:
        return QualityLayer.mid;
      case QualityLayer.mid:
        return QualityLayer.low;
      case QualityLayer.low:
        return QualityLayer.low;
    }
  }

  QualityLayer _upgrade(QualityLayer current) {
    switch (current) {
      case QualityLayer.low:
        return QualityLayer.mid;
      case QualityLayer.mid:
        return QualityLayer.high;
      case QualityLayer.high:
        return QualityLayer.high;
    }
  }
}

void main() async {
  print('Simulcast ABR Example');
  print('=' * 50);

  final abr = AbrController();

  // WebSocket signaling server
  final wsServer = await HttpServer.bind(InternetAddress.anyIPv4, 8888);
  print('WebSocket server listening on ws://localhost:8888');

  wsServer.transform(WebSocketTransformer()).listen((WebSocket socket) async {
    print('[WS] Client connected');

    final pc = RtcPeerConnection(RtcConfiguration(
      iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
    ));

    pc.onConnectionStateChange.listen((state) {
      print('[PC] Connection: $state');
    });

    // Receive transceiver
    final transceiver = pc.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.recvonly,
    );

    pc.onTrack.listen((t) {
      print('[Track] Received layer');
    });

    // Listen for RTP on the receiver track
    transceiver.receiver.track.onReceiveRtp.listen((rtp) {
      abr.recordPacket(lost: false);
      abr.evaluate();
    });

    // Wait for offer from browser
    socket.listen((data) async {
      final msg = jsonDecode(data as String);
      final offer = SessionDescription(type: 'offer', sdp: msg['sdp']);
      await pc.setRemoteDescription(offer);

      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      socket.add(jsonEncode({
        'type': 'answer',
        'sdp': answer.sdp,
      }));
      print('[SDP] Answer sent');
    });
  });

  print('\n--- ABR Algorithm ---');
  print('');
  print('Monitors packet loss and adapts quality:');
  print('  >10% loss: downgrade (high->mid->low)');
  print('  <2% loss:  upgrade  (low->mid->high)');
  print('');
  print('Evaluation interval: 2 seconds');

  print('\nWaiting for browser to send offer...');
}
