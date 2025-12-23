/// Simulcast Layer Selection Example
///
/// Demonstrates manual layer selection for simulcast streams,
/// allowing clients to request specific quality levels.
///
/// Usage: dart run example/mediachannel/simulcast/select.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';

void main() async {
  print('Simulcast Layer Selection Example');
  print('=' * 50);

  // Track active layers per client
  final clientLayers = <String, String>{};
  var clientCounter = 0;

  // HTTP + WebSocket server
  final httpServer = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
  print('Server listening on http://localhost:8080');

  httpServer.listen((request) async {
    if (request.uri.path == '/ws' && WebSocketTransformer.isUpgradeRequest(request)) {
      // WebSocket connection
      final socket = await WebSocketTransformer.upgrade(request);
      final clientId = 'client_${++clientCounter}';
      clientLayers[clientId] = 'mid';
      print('[$clientId] Connected, default layer: mid');

      final pc = RtcPeerConnection(RtcConfiguration(
        iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
      ));

      pc.onConnectionStateChange.listen((state) {
        print('[$clientId] Connection: $state');
        if (state == PeerConnectionState.closed) {
          clientLayers.remove(clientId);
        }
      });

      // Receive simulcast
      pc.addTransceiver(
        MediaStreamTrackKind.video,
        direction: RtpTransceiverDirection.recvonly,
      );

      pc.onTrack.listen((transceiver) {
        print('[$clientId] Received layer: ${transceiver.mid}');
      });

      // Send client ID for API reference
      socket.add(jsonEncode({'type': 'client_id', 'id': clientId}));

      // Handle signaling
      socket.listen((data) async {
        final msg = jsonDecode(data as String);
        if (msg['type'] == 'offer') {
          final offer = SessionDescription(type: 'offer', sdp: msg['sdp']);
          await pc.setRemoteDescription(offer);

          final answer = await pc.createAnswer();
          await pc.setLocalDescription(answer);
          socket.add(jsonEncode({
            'type': 'answer',
            'sdp': answer.sdp,
          }));
        }
      }, onDone: () {
        pc.close();
        clientLayers.remove(clientId);
      });
    } else if (request.uri.path == '/select') {
      // Layer selection API
      final clientId = request.uri.queryParameters['client'];
      final layer = request.uri.queryParameters['layer'];

      if (clientId != null && layer != null) {
        clientLayers[clientId] = layer;
        print('[API] Client $clientId selected layer: $layer');
        request.response
          ..statusCode = HttpStatus.ok
          ..write('Layer set to $layer')
          ..close();
      } else {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write('Missing client or layer parameter')
          ..close();
      }
    } else if (request.uri.path == '/') {
      // Status page
      final clientList = clientLayers.entries
          .map((e) => '<li>${e.key}: ${e.value}</li>')
          .join('\n');

      request.response
        ..headers.contentType = ContentType.html
        ..write('''
<!DOCTYPE html>
<html>
<head><title>Simulcast Status</title></head>
<body>
  <h1>Simulcast Layer Selection</h1>
  <h2>Connected Clients</h2>
  <ul>$clientList</ul>
  <h2>Change Layer</h2>
  <form action="/select" method="get">
    <input name="client" placeholder="client_id">
    <select name="layer">
      <option value="high">High (1080p)</option>
      <option value="mid" selected>Mid (720p)</option>
      <option value="low">Low (360p)</option>
    </select>
    <button type="submit">Set Layer</button>
  </form>
</body>
</html>
''')
        ..close();
    } else {
      request.response
        ..statusCode = HttpStatus.notFound
        ..close();
    }
  });

  print('\n--- Layer Selection API ---');
  print('');
  print('Select layer for client:');
  print('  GET /select?client=ID&layer=high|mid|low');
  print('');
  print('View status:');
  print('  GET /');
  print('');
  print('WebSocket:');
  print('  ws://localhost:8080/ws');

  print('\nWaiting for connections...');
}
