/// Simulcast TWCC Example
///
/// This example matches werift's mediachannel/simulcast/twcc.ts:
/// - WebSocket server for signaling
/// - Recvonly transceiver with simulcast layers (high, low)
/// - TWCC (transport-wide CC) and abs-send-time header extensions
/// - Two sendonly transceivers for forwarding each layer
///
/// Usage:
///   dart run example/mediachannel/simulcast/twcc.dart
///   Then open a browser to send simulcast video
library;

import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';

/// WebSocket server for browser signaling
class SimulcastTwccServer {
  HttpServer? _httpServer;

  Future<void> start({int port = 8888}) async {
    _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('Simulcast TWCC Server');
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

    // Create PeerConnection with RID, abs-send-time, and TWCC header extensions
    // Plus VP8 codec with transport-cc feedback (like werift)
    final pc = RTCPeerConnection(RtcConfiguration(
      iceServers: [
        IceServer(urls: ['stun:stun.l.google.com:19302'])
      ],
      codecs: RtcCodecs(
        video: [
          RtpCodecParameters(
            mimeType: 'video/VP8',
            clockRate: 90000,
            payloadType: 96,
            rtcpFeedback: [
              RtcpFeedback(type: 'ccm', parameter: 'fir'),
              RtcpFeedback(type: 'nack'),
              RtcpFeedback(type: 'nack', parameter: 'pli'),
              RtcpFeedback(type: 'goog-remb'),
              RtcpFeedback(type: 'transport-cc'),
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

    // Track received RIDs
    final ridPackets = <String, int>{};

    // Create recvonly transceiver with simulcast layers (like werift)
    final recvTransceiver = pc.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.recvonly,
    );

    // Add simulcast layers for receiving (high, low)
    recvTransceiver.addSimulcastLayer(
      RTCRtpSimulcastParameters(
          rid: 'high', direction: SimulcastDirection.recv),
    );
    recvTransceiver.addSimulcastLayer(
      RTCRtpSimulcastParameters(rid: 'low', direction: SimulcastDirection.recv),
    );
    print('[Server] Added recvonly transceiver with simulcast (high, low)');

    // Create 2 sendonly transceivers for forwarding each layer (like werift)
    final multiCast = <String, RTCRtpTransceiver>{
      'high': pc.addTransceiver(
        MediaStreamTrackKind.video,
        direction: RtpTransceiverDirection.sendonly,
      ),
      'low': pc.addTransceiver(
        MediaStreamTrackKind.video,
        direction: RtpTransceiverDirection.sendonly,
      ),
    };
    print('[Server] Added 2 sendonly transceivers for forwarding (high, low)');

    // Handle incoming tracks - route by RID to appropriate sender (like werift)
    pc.onTrack.listen((transceiver) {
      final track = transceiver.receiver.track;
      print('[Server] Received track: ${track.id}, RID: ${track.rid}');

      // Listen for RTP packets
      track.onReceiveRtp.listen((rtp) {
        final rid = track.rid ?? 'default';
        ridPackets[rid] = (ridPackets[rid] ?? 0) + 1;

        if (ridPackets[rid]! % 100 == 0) {
          print('[Server] RID $rid: ${ridPackets[rid]} packets');
        }
      });

      // Route track to corresponding sendonly transceiver (like werift)
      final rid = track.rid;
      if (rid != null && multiCast.containsKey(rid)) {
        final sender = multiCast[rid]!;
        sender.sender.replaceTrack(track);
        print('[Server] Routing RID $rid to sendonly transceiver');
      }
    });

    // Listen for additional simulcast layer tracks
    recvTransceiver.receiver.onTrack = (simulcastTrack) {
      print(
          '[Server] New simulcast layer: ${simulcastTrack.id}, RID: ${simulcastTrack.rid}');

      simulcastTrack.onReceiveRtp.listen((rtp) {
        final rid = simulcastTrack.rid ?? 'default';
        ridPackets[rid] = (ridPackets[rid] ?? 0) + 1;

        if (ridPackets[rid]! % 100 == 0) {
          print('[Server] RID $rid: ${ridPackets[rid]} packets');
        }
      });

      final simRid = simulcastTrack.rid;
      if (simRid != null && multiCast.containsKey(simRid)) {
        final sender = multiCast[simRid]!;
        sender.sender.replaceTrack(simulcastTrack);
        print('[Server] Routing RID $simRid to sendonly transceiver');
      }
    };

    // Create offer and send to browser (like werift)
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    print('[Server] Created offer');

    // Log TWCC and simulcast-related SDP lines
    for (final line in offer.sdp.split('\n')) {
      if (line.contains('a=rid') ||
          line.contains('a=simulcast') ||
          line.contains('transport-cc') ||
          line.contains('abs-send-time')) {
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
              RTCSessionDescription(type: 'answer', sdp: msg['sdp'] as String),
            );
            print('[Server] Remote description set');
          }
        } catch (e) {
          print('[Server] Message error: $e');
        }
      },
      onDone: () async {
        print('[Server] Client disconnected');
        print('[Server] Final RID counts: $ridPackets');
        await pc.close();
      },
    );
  }
}

void main() async {
  final server = SimulcastTwccServer();
  await server.start(port: 8888);
}
