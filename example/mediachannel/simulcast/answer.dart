/// Simulcast SFU Fanout Example
///
/// Demonstrates the SFU (Selective Forwarding Unit) pattern for simulcast:
/// 1. Receives simulcast video layers (high/mid/low) from browser
/// 2. Routes each layer to a separate sender transceiver
/// 3. Forwards packets to viewers (or back to sender for testing)
///
/// This matches werift's mediachannel_simulcast_answer pattern.
///
/// Usage: dart run example/mediachannel/simulcast/answer.dart
///        Then connect a browser client that sends simulcast video.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';

class SimulcastSfuServer {
  HttpServer? _server;
  RTCPeerConnection? _pc;
  final List<Map<String, dynamic>> _localCandidates = [];

  // Sender transceivers for each simulcast layer (SFU fanout)
  // In a real SFU, each would forward to different viewers
  final Map<String, RTCRtpTransceiver> _senders = {};

  // Stats
  final Map<String, int> _packetCounts = {};

  Future<void> start({int port = 8888}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('Simulcast SFU Server');
    print('=' * 50);
    print('Listening on http://localhost:$port');
    print('');
    print('SFU Architecture:');
    print('  Browser (simulcast) → Dart SFU → Output transceivers');
    print('                              ↓');
    print('                        high → sender[high]');
    print('                        mid  → sender[mid]');
    print('                        low  → sender[low]');
    print('');

    await for (final request in _server!) {
      _handleRequest(request);
    }
  }

  void _handleRequest(HttpRequest request) async {
    // CORS
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers
        .add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers
        .add('Access-Control-Allow-Headers', 'Content-Type');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    switch (request.uri.path) {
      case '/':
        await _serveIndex(request);
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

  Future<void> _serveIndex(HttpRequest request) async {
    request.response.headers.contentType = ContentType.html;
    request.response.write('''
<!DOCTYPE html>
<html>
<head><title>Simulcast SFU</title></head>
<body>
  <h1>Simulcast SFU Example</h1>
  <video id="local" autoplay muted playsinline width="320"></video>
  <video id="remote" autoplay playsinline width="320"></video>
  <div id="status"></div>
  <script>
    const serverUrl = window.location.origin;
    const log = msg => {
      console.log(msg);
      document.getElementById('status').innerHTML += msg + '<br>';
    };

    async function start() {
      await fetch(serverUrl + '/start');
      const offerRes = await fetch(serverUrl + '/offer');
      const offer = await offerRes.json();

      const pc = new RTCPeerConnection({
        iceServers: [{urls: 'stun:stun.l.google.com:19302'}]
      });

      pc.onicecandidate = async e => {
        if (e.candidate) {
          await fetch(serverUrl + '/candidate', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({candidate: e.candidate.candidate})
          });
        }
      };

      pc.ontrack = e => {
        log('Received track from SFU');
        document.getElementById('remote').srcObject = e.streams[0];
      };

      pc.onconnectionstatechange = () => log('Connection: ' + pc.connectionState);

      await pc.setRemoteDescription(offer);
      log('Remote offer set');

      const stream = await navigator.mediaDevices.getUserMedia({video: true});
      document.getElementById('local').srcObject = stream;
      stream.getTracks().forEach(t => pc.addTrack(t, stream));

      const answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);

      await fetch(serverUrl + '/answer', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({type: 'answer', sdp: answer.sdp})
      });
      log('Answer sent');

      const candRes = await fetch(serverUrl + '/candidates');
      const candidates = await candRes.json();
      for (const c of candidates) {
        await pc.addIceCandidate(new RTCIceCandidate(c));
      }

      setInterval(async () => {
        const statusRes = await fetch(serverUrl + '/status');
        const status = await statusRes.json();
        log('Packets by RID: ' + JSON.stringify(status.packetCounts));
      }, 2000);
    }

    start().catch(console.error);
  </script>
</body>
</html>
''');
    await request.response.close();
  }

  Future<void> _handleStart(HttpRequest request) async {
    print('[SFU] Starting new session');

    await _pc?.close();
    _localCandidates.clear();
    _senders.clear();
    _packetCounts.clear();

    _pc = RTCPeerConnection(
      RtcConfiguration(
        iceServers: [
          IceServer(urls: ['stun:stun.l.google.com:19302'])
        ],
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

    _pc!.onConnectionStateChange.listen((state) {
      print('[SFU] Connection: $state');
    });

    _pc!.onIceCandidate.listen((candidate) {
      _localCandidates.add({
        'candidate': 'candidate:${candidate.toSdp()}',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      });
    });

    // === SFU FANOUT PATTERN ===
    // Matching werift's mediachannel_simulcast_answer

    // 1. Receiver transceiver with simulcast layers
    final receiver = _pc!.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.recvonly,
    );
    receiver.addSimulcastLayer(
      RTCRtpSimulcastParameters(
          rid: 'high', direction: SimulcastDirection.recv),
    );
    receiver.addSimulcastLayer(
      RTCRtpSimulcastParameters(rid: 'mid', direction: SimulcastDirection.recv),
    );
    receiver.addSimulcastLayer(
      RTCRtpSimulcastParameters(rid: 'low', direction: SimulcastDirection.recv),
    );
    print('[SFU] Created receiver (simulcast: high/mid/low)');

    // 2. Sender transceivers for each layer (the "multiCast" object in werift)
    _senders['high'] = _pc!.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.sendonly,
    );
    _senders['mid'] = _pc!.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.sendonly,
    );
    _senders['low'] = _pc!.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.sendonly,
    );
    print('[SFU] Created 3 sender transceivers');

    // 3. Route incoming simulcast tracks to senders
    _pc!.onTrack.listen((transceiver) {
      final track = transceiver.receiver.track;
      if (track.rid != null) {
        _forwardTrackToSender(track);
      }

      // Listen for additional simulcast layers
      transceiver.receiver.onTrack = (layerTrack) {
        _forwardTrackToSender(layerTrack);
      };
    });

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
    await request.response.close();
  }

  void _forwardTrackToSender(MediaStreamTrack track) {
    final rid = track.rid;
    if (rid == null) return;

    print('[SFU] Forwarding layer: $rid');
    _packetCounts[rid] = 0;

    final sender = _senders[rid];
    if (sender != null) {
      // Use registerTrackForForward to forward RTP packets
      sender.sender.registerTrackForForward(track);

      // Count packets
      track.onReceiveRtp.listen((rtp) {
        _packetCounts[rid] = (_packetCounts[rid] ?? 0) + 1;
      });
    }
  }

  Future<void> _handleOffer(HttpRequest request) async {
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);

    print('[SFU] Created offer with simulcast');

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'type': 'offer',
      'sdp': offer.sdp,
    }));
    await request.response.close();
  }

  Future<void> _handleAnswer(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    final data = jsonDecode(body) as Map<String, dynamic>;
    final answer =
        RTCSessionDescription(type: 'answer', sdp: data['sdp'] as String);

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
        final candidate = RTCIceCandidate.fromSdp(candidateStr);
        await _pc!.addIceCandidate(candidate);
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
      'packetCounts': _packetCounts,
      'layersActive': _senders.keys.toList(),
    }));
    await request.response.close();
  }
}

void main() async {
  final server = SimulcastSfuServer();
  await server.start(port: 8888);
}
