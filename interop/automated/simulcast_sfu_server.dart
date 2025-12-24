// Simulcast SFU Fanout Test Server
//
// Demonstrates the SFU (Selective Forwarding Unit) pattern:
// - Receives simulcast video layers (high/mid/low) from browser
// - Forwards each layer to a separate sender transceiver
// - Matches werift's mediachannel_simulcast_answer example
//
// Pattern: Browser sends simulcast → Dart SFU → Dart sends back to browser
// (For testing, we send back to the same browser connection)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:webrtc_dart/webrtc_dart.dart';

class SimulcastSfuServer {
  HttpServer? _server;
  RtcPeerConnection? _pc;
  final List<Map<String, dynamic>> _localCandidates = [];

  // Sender transceivers for each layer
  RtpTransceiver? _highSender;
  RtpTransceiver? _midSender;
  RtpTransceiver? _lowSender;

  // Track which layers we've received
  final Map<String, bool> _layersReceived = {};
  int _rtpPacketsForwarded = 0;

  Future<void> start({int port = 8781}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('[SFU] Started on http://localhost:$port');

    await for (final request in _server!) {
      _handleRequest(request);
    }
  }

  void _handleRequest(HttpRequest request) async {
    // CORS headers
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    print('[SFU] ${request.method} ${request.uri.path}');

    switch (request.uri.path) {
      case '/':
        await _handleIndex(request);
        break;
      case '/start':
        await _handleStart(request);
        break;
      case '/offer':
        await _handleOffer(request);
        break;
      case '/answer':
        await _handleAnswer(request);
        break;
      case '/candidate':
        await _handleCandidate(request);
        break;
      case '/candidates':
        await _handleGetCandidates(request);
        break;
      case '/status':
        await _handleStatus(request);
        break;
      default:
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
    }
  }

  Future<void> _handleIndex(HttpRequest request) async {
    request.response.headers.contentType = ContentType.html;
    request.response.write('''
<!DOCTYPE html>
<html>
<head>
  <title>Simulcast SFU Test</title>
</head>
<body>
  <h1>Simulcast SFU Fanout Test</h1>
  <p>This server receives simulcast and forwards each layer to separate senders.</p>
  <p>Use the automated test client to connect.</p>

  <h2>Architecture</h2>
  <pre>
  Browser (sends simulcast) → Dart SFU → Dart (sends back)
                                ↓
                          Routes by RID:
                          - high → highSender.replaceTrack()
                          - mid  → midSender.replaceTrack()
                          - low  → lowSender.replaceTrack()
  </pre>
</body>
</html>
''');
    await request.response.close();
  }

  Future<void> _handleStart(HttpRequest request) async {
    final browser = request.uri.queryParameters['browser'] ?? 'unknown';
    print('[SFU] Starting test for: $browser');

    // Clean up any existing connection
    await _pc?.close();
    _localCandidates.clear();
    _layersReceived.clear();
    _rtpPacketsForwarded = 0;

    // Create peer connection with VP8
    _pc = RtcPeerConnection(
      RtcConfiguration(
        iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
        codecs: RtcCodecs(
          video: [
            RtpCodecParameters(
              mimeType: 'video/VP8',
              clockRate: 90000,
              rtcpFeedback: [
                RtcpFeedback(type: 'nack'),
                RtcpFeedback(type: 'nack', parameter: 'pli'),
              ],
            ),
          ],
        ),
      ),
    );
    print('[SFU] PeerConnection created with VP8');

    _pc!.onConnectionStateChange.listen((state) {
      print('[SFU] Connection state: $state');
    });

    _pc!.onIceConnectionStateChange.listen((state) {
      print('[SFU] ICE state: $state');
    });

    _pc!.onIceCandidate.listen((candidate) {
      print('[SFU] Local ICE candidate: ${candidate.type} ${candidate.host}:${candidate.port}');
      _localCandidates.add({
        'candidate': 'candidate:${candidate.toSdp()}',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      });
    });

    // === SFU FANOUT PATTERN (matching werift) ===

    // 1. Create receiver transceiver with simulcast layers
    final receiver = _pc!.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.recvonly,
    );
    receiver.addSimulcastLayer(
      RTCRtpSimulcastParameters(rid: 'high', direction: SimulcastDirection.recv),
    );
    receiver.addSimulcastLayer(
      RTCRtpSimulcastParameters(rid: 'mid', direction: SimulcastDirection.recv),
    );
    receiver.addSimulcastLayer(
      RTCRtpSimulcastParameters(rid: 'low', direction: SimulcastDirection.recv),
    );
    print('[SFU] Created receiver with simulcast (high/mid/low)');

    // 2. Create sender transceivers for each layer (like werift's multiCast object)
    _highSender = _pc!.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.sendonly,
    );
    _midSender = _pc!.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.sendonly,
    );
    _lowSender = _pc!.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.sendonly,
    );
    print('[SFU] Created 3 sender transceivers (high/mid/low output)');

    // 3. When tracks arrive, route to appropriate sender
    _pc!.onTrack.listen((transceiver) {
      print('[SFU] onTrack: kind=${transceiver.kind}, mid=${transceiver.mid}');
      final primaryTrack = transceiver.receiver.track;

      if (primaryTrack.rid != null) {
        _handleSimulcastTrack(primaryTrack);
      }

      // Listen for additional simulcast layer tracks
      transceiver.receiver.onTrack = (track) {
        print('[SFU] receiver.onTrack: id=${track.id}, rid=${track.rid}');
        _handleSimulcastTrack(track);
      };
    });

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
    await request.response.close();
  }

  void _handleSimulcastTrack(MediaStreamTrack track) {
    final rid = track.rid;
    if (rid == null) {
      print('[SFU] Track has no RID, skipping');
      return;
    }

    print('[SFU] Handling simulcast track: rid=$rid');
    _layersReceived[rid] = true;

    // Route to appropriate sender using replaceTrack (werift pattern)
    RtpTransceiver? targetSender;
    switch (rid) {
      case 'high':
        targetSender = _highSender;
        break;
      case 'mid':
        targetSender = _midSender;
        break;
      case 'low':
        targetSender = _lowSender;
        break;
    }

    if (targetSender != null) {
      print('[SFU] Forwarding $rid layer to sender mid=${targetSender.mid}');

      // Use registerTrackForForward for RTP forwarding (our API)
      targetSender.sender.registerTrackForForward(track);

      // Count forwarded packets
      track.onReceiveRtp.listen((rtp) {
        _rtpPacketsForwarded++;
        if (_rtpPacketsForwarded % 50 == 0) {
          print('[SFU] Forwarded $_rtpPacketsForwarded packets');
        }
      });
    }
  }

  Future<void> _handleOffer(HttpRequest request) async {
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);

    // Log simulcast features in offer
    print('[SFU] Simulcast features in offer:');
    for (final line in offer.sdp.split('\n')) {
      if (line.contains('a=rid:') || line.contains('a=simulcast:') ||
          line.contains('rtp-stream-id')) {
        print(line.trim());
      }
    }

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'type': 'offer',
      'sdp': offer.sdp,
    }));
    print('[SFU] Sent offer to browser');
    await request.response.close();
  }

  Future<void> _handleAnswer(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    final data = jsonDecode(body) as Map<String, dynamic>;
    final sdp = data['sdp'] as String;

    print('[SFU] Received answer from browser');

    // Log simulcast in answer
    print('[SFU] Simulcast in answer:');
    for (final line in sdp.split('\n')) {
      if (line.contains('a=rid:') || line.contains('a=simulcast:') ||
          line.contains('rtp-stream-id')) {
        print(line.trim());
      }
    }

    final answer = SessionDescription(type: 'answer', sdp: sdp);
    await _pc!.setRemoteDescription(answer);
    print('[SFU] Remote description set');

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
    await request.response.close();
  }

  Future<void> _handleCandidate(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    final data = jsonDecode(body) as Map<String, dynamic>;
    final candidateStr = data['candidate'] as String?;

    if (candidateStr != null && candidateStr.isNotEmpty) {
      try {
        final candidate = Candidate.fromSdp(candidateStr);
        await _pc!.addIceCandidate(candidate);
        print('[SFU] Added ICE candidate: ${candidate.type}');
      } catch (e) {
        print('[SFU] Failed to add candidate: $e');
      }
    }

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
    await request.response.close();
  }

  Future<void> _handleGetCandidates(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(_localCandidates));
    await request.response.close();
  }

  Future<void> _handleStatus(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'connectionState': _pc?.connectionState.toString() ?? 'none',
      'iceConnectionState': _pc?.iceConnectionState.toString() ?? 'none',
      'rtpPacketsForwarded': _rtpPacketsForwarded,
      'layersReceived': _layersReceived,
      'sfuPattern': 'replaceTrack',
    }));
    await request.response.close();
  }

  Future<void> stop() async {
    await _pc?.close();
    await _server?.close();
  }
}

void main() async {
  final server = SimulcastSfuServer();
  await server.start(port: 8781);
}
