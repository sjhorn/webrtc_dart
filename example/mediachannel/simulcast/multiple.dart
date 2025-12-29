/// Simulcast Multiple Transceivers Example
///
/// This example matches werift's mediachannel/simulcast/multiple.ts:
/// - WebSocket server for signaling
/// - Two recvonly video transceivers, each with simulcast layers (high, low)
/// - Uses RID header extensions (sdes:rtp-stream-id, repaired-rtp-stream-id)
///
/// Usage:
///   dart run example/mediachannel/simulcast/multiple.dart
///   Then open a browser with simulcast video
library;

import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';

/// WebSocket server for browser signaling
class SimulcastMultipleServer {
  HttpServer? _httpServer;

  Future<void> start({int port = 8888}) async {
    _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('Simulcast Multiple Transceivers Server');
    print('=' * 50);
    print('WebSocket: ws://localhost:$port');
    print('');

    await for (final request in _httpServer!) {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        _handleWebSocket(request);
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    }
  }

  Future<void> _handleWebSocket(HttpRequest request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    print('[Server] Client connected');

    // Create PeerConnection with RID header extensions and VP8 codec (like werift)
    final pc = RtcPeerConnection(RtcConfiguration(
      codecs: RtcCodecs(
        video: [
          RtpCodecParameters(
            mimeType: 'video/VP8',
            clockRate: 90000,
            payloadType: 96,
            rtcpFeedback: [
              RtcpFeedback(type: 'nack'),
              RtcpFeedback(type: 'nack', parameter: 'pli'),
              RtcpFeedback(type: 'goog-remb'),
            ],
          ),
        ],
      ),
    ));

    // Track connection state
    pc.onIceConnectionStateChange.listen((state) {
      print('[Server] ICE state: $state');
    });

    pc.onConnectionStateChange.listen((state) {
      print('[Server] Connection state: $state');
    });

    // Track received packets per transceiver
    final ridPacketsA = <String, int>{};
    final ridPacketsB = <String, int>{};

    // First recvonly transceiver with simulcast (like werift)
    final transceiverA = pc.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.recvonly,
    );

    // Add simulcast layers for receiving (high, low)
    transceiverA.addSimulcastLayer(
      RTCRtpSimulcastParameters(rid: 'high', direction: SimulcastDirection.recv),
    );
    transceiverA.addSimulcastLayer(
      RTCRtpSimulcastParameters(rid: 'low', direction: SimulcastDirection.recv),
    );
    print('[Server] Added transceiverA with simulcast (high, low)');

    // Handle tracks from transceiver A
    transceiverA.receiver.onTrack = (track) {
      print('[Server] TransceiverA track: ${track.id}, RID: ${track.rid}');
      track.onReceiveRtp.listen((rtp) {
        final rid = track.rid ?? 'default';
        ridPacketsA[rid] = (ridPacketsA[rid] ?? 0) + 1;
        if (ridPacketsA[rid]! % 100 == 0) {
          print('[Server] TransceiverA RID $rid: ${ridPacketsA[rid]} packets');
        }
      });
    };

    // Second recvonly transceiver with simulcast (like werift)
    final transceiverB = pc.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.recvonly,
    );

    // Add simulcast layers for receiving (high, low)
    transceiverB.addSimulcastLayer(
      RTCRtpSimulcastParameters(rid: 'high', direction: SimulcastDirection.recv),
    );
    transceiverB.addSimulcastLayer(
      RTCRtpSimulcastParameters(rid: 'low', direction: SimulcastDirection.recv),
    );
    print('[Server] Added transceiverB with simulcast (high, low)');

    // Handle tracks from transceiver B
    transceiverB.receiver.onTrack = (track) {
      print('[Server] TransceiverB track: ${track.id}, RID: ${track.rid}');
      track.onReceiveRtp.listen((rtp) {
        final rid = track.rid ?? 'default';
        ridPacketsB[rid] = (ridPacketsB[rid] ?? 0) + 1;
        if (ridPacketsB[rid]! % 100 == 0) {
          print('[Server] TransceiverB RID $rid: ${ridPacketsB[rid]} packets');
        }
      });
    };

    // Also listen via pc.onTrack (fires for both)
    pc.onTrack.listen((transceiver) {
      final track = transceiver.receiver.track;
      print('[Server] pc.onTrack: ${track.id}, RID: ${track.rid}');
    });

    // Create offer and send to browser (like werift)
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    print('[Server] Created offer');

    // Log simulcast-related SDP lines
    for (final line in offer.sdp.split('\n')) {
      if (line.contains('a=rid') || line.contains('a=simulcast')) {
        print('[Server] SDP: ${line.trim()}');
      }
    }

    // Send offer as JSON (like werift)
    socket.add(jsonEncode({
      'type': offer.type,
      'sdp': offer.sdp,
    }));
    print('[Server] Sent offer to browser');

    // Handle messages from browser
    socket.listen(
      (data) async {
        try {
          final msg = jsonDecode(data as String) as Map<String, dynamic>;

          if (msg['type'] == 'answer') {
            print('[Server] Received answer');
            await pc.setRemoteDescription(
              SessionDescription(type: 'answer', sdp: msg['sdp'] as String),
            );
            print('[Server] Remote description set');
          }
        } catch (e) {
          print('[Server] Message error: $e');
        }
      },
      onDone: () async {
        print('[Server] Client disconnected');
        print('[Server] TransceiverA final RID counts: $ridPacketsA');
        print('[Server] TransceiverB final RID counts: $ridPacketsB');
        await pc.close();
      },
    );
  }
}

void main() async {
  final server = SimulcastMultipleServer();
  await server.start(port: 8888);
}
