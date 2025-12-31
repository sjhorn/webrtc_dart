/// Simulcast Layer Selection Example
///
/// Demonstrates manual layer selection for simulcast streams.
/// The SFU receives all simulcast layers but only forwards the
/// selected layer to the viewer.
///
/// API:
///   GET /select?layer=high|mid|low  - Switch forwarded layer
///
/// This is useful for:
/// - Bandwidth management (force low quality on slow connections)
/// - User preference (let users choose quality)
/// - Testing different quality levels
///
/// Usage: dart run example/mediachannel/simulcast/select.dart
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';

class SimulcastSelectServer {
  HttpServer? _server;
  RtcPeerConnection? _pc;
  final List<Map<String, dynamic>> _localCandidates = [];

  // Single sender transceiver for the selected layer
  RtpTransceiver? _outputSender;

  // All received simulcast layer tracks
  final Map<String, MediaStreamTrack> _layerTracks = {};

  // Currently selected layer
  String _selectedLayer = 'mid';

  // Stats
  final Map<String, int> _packetCounts = {};
  int _forwardedPackets = 0;

  Future<void> start({int port = 8889}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('Simulcast Layer Selection Server');
    print('=' * 50);
    print('Listening on http://localhost:$port');
    print('');
    print('Layer Selection API:');
    print('  GET /select?layer=high   - Forward high quality');
    print('  GET /select?layer=mid    - Forward medium quality (default)');
    print('  GET /select?layer=low    - Forward low quality');
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
      case '/select':
        await _handleSelect(request);
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
<head><title>Simulcast Layer Selection</title></head>
<body>
  <h1>Simulcast Layer Selection</h1>
  <div>
    <button onclick="selectLayer('high')">High Quality</button>
    <button onclick="selectLayer('mid')">Medium Quality</button>
    <button onclick="selectLayer('low')">Low Quality</button>
  </div>
  <div id="current">Current layer: loading...</div>
  <video id="local" autoplay muted playsinline width="320"></video>
  <video id="remote" autoplay playsinline width="320"></video>
  <div id="status"></div>
  <script>
    const serverUrl = window.location.origin;
    const log = msg => {
      console.log(msg);
      document.getElementById('status').innerHTML += msg + '<br>';
    };

    async function selectLayer(layer) {
      const res = await fetch(serverUrl + '/select?layer=' + layer);
      const data = await res.json();
      document.getElementById('current').textContent =
        'Current layer: ' + data.selectedLayer;
      log('Selected layer: ' + layer);
    }

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
        log('Received forwarded video from SFU');
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
        document.getElementById('current').textContent =
          'Current layer: ' + status.selectedLayer +
          ' | Forwarded: ' + status.forwardedPackets + ' packets';
      }, 1000);
    }

    start().catch(console.error);
  </script>
</body>
</html>
''');
    await request.response.close();
  }

  Future<void> _handleStart(HttpRequest request) async {
    print('[Select] Starting new session');

    await _pc?.close();
    _localCandidates.clear();
    _layerTracks.clear();
    _packetCounts.clear();
    _forwardedPackets = 0;
    _selectedLayer = 'mid';

    _pc = RtcPeerConnection(
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
      print('[Select] Connection: $state');
    });

    _pc!.onIceCandidate.listen((candidate) {
      _localCandidates.add({
        'candidate': 'candidate:${candidate.toSdp()}',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      });
    });

    // Receiver transceiver with simulcast layers
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
    print('[Select] Created receiver (simulcast: high/mid/low)');

    // Single sender for selected layer output
    _outputSender = _pc!.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.sendonly,
    );
    print('[Select] Created output sender');

    // Collect all incoming layer tracks
    _pc!.onTrack.listen((transceiver) {
      final track = transceiver.receiver.track;
      if (track.rid != null) {
        _registerLayerTrack(track);
      }

      transceiver.receiver.onTrack = (layerTrack) {
        _registerLayerTrack(layerTrack);
      };
    });

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
    await request.response.close();
  }

  void _registerLayerTrack(MediaStreamTrack track) {
    final rid = track.rid;
    if (rid == null) return;

    print('[Select] Received layer: $rid');
    _layerTracks[rid] = track;
    _packetCounts[rid] = 0;

    // Count packets for this layer
    track.onReceiveRtp.listen((rtp) {
      _packetCounts[rid] = (_packetCounts[rid] ?? 0) + 1;
    });

    // If this is the selected layer, start forwarding
    if (rid == _selectedLayer) {
      _switchToLayer(rid);
    }
  }

  void _switchToLayer(String layer) {
    if (!_layerTracks.containsKey(layer)) {
      print('[Select] Layer $layer not yet available');
      return;
    }

    print('[Select] Switching to layer: $layer');
    _selectedLayer = layer;

    final track = _layerTracks[layer]!;

    // Forward this layer's packets to the output sender
    _outputSender?.sender.registerTrackForForward(track);

    // Update forwarded packet counter
    track.onReceiveRtp.listen((rtp) {
      _forwardedPackets++;
    });
  }

  Future<void> _handleSelect(HttpRequest request) async {
    final layer = request.uri.queryParameters['layer'] ?? 'mid';

    if (!['high', 'mid', 'low'].contains(layer)) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write(jsonEncode({'error': 'Invalid layer'}));
      await request.response.close();
      return;
    }

    _switchToLayer(layer);

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'status': 'ok',
      'selectedLayer': _selectedLayer,
      'availableLayers': _layerTracks.keys.toList(),
    }));
    await request.response.close();
  }

  Future<void> _handleOffer(HttpRequest request) async {
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);

    print('[Select] Created offer');

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
        SessionDescription(type: 'answer', sdp: data['sdp'] as String);

    await _pc!.setRemoteDescription(answer);
    print('[Select] Remote description set');

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
      } catch (e) {
        print('[Select] Failed to add candidate: $e');
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
      'selectedLayer': _selectedLayer,
      'availableLayers': _layerTracks.keys.toList(),
      'packetCounts': _packetCounts,
      'forwardedPackets': _forwardedPackets,
    }));
    await request.response.close();
  }
}

void main() async {
  final server = SimulcastSelectServer();
  await server.start(port: 8889);
}
