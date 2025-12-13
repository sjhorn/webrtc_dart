/// Simple WebSocket Signaling Server
///
/// This example provides a minimal signaling server for WebRTC peers.
/// It broadcasts messages from one connected peer to all others.
///
/// Usage: dart run examples/signaling/signaling_server.dart [port]
/// Default port: 8888
library;

import 'dart:io';
import 'dart:convert';

void main(List<String> args) async {
  final port = args.isNotEmpty ? int.parse(args[0]) : 8888;

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  print('Signaling server listening on ws://localhost:$port');
  print('Waiting for WebSocket connections...\n');

  final clients = <WebSocket>[];

  await for (final request in server) {
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      final socket = await WebSocketTransformer.upgrade(request);
      clients.add(socket);
      print('[Server] New client connected (total: ${clients.length})');

      socket.listen(
        (data) {
          // Decode the message
          final message =
              data is String ? data : utf8.decode(data as List<int>);

          // Try to parse as JSON to log nicely
          try {
            final json = jsonDecode(message);
            final type = json['type'] ?? 'unknown';
            print('[Server] Received $type from client');
          } catch (e) {
            print('[Server] Received message (${message.length} bytes)');
          }

          // Broadcast to all other clients
          for (final client in clients) {
            if (client != socket && client.readyState == WebSocket.open) {
              client.add(message);
              print('[Server] Forwarded to another client');
            }
          }
        },
        onDone: () {
          clients.remove(socket);
          print('[Server] Client disconnected (remaining: ${clients.length})');
        },
        onError: (error) {
          print('[Server] Client error: $error');
          clients.remove(socket);
        },
      );
    } else {
      // Return a simple status page for HTTP requests
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write('''
<!DOCTYPE html>
<html>
<head><title>WebRTC Signaling Server</title></head>
<body>
  <h1>WebRTC Signaling Server</h1>
  <p>Status: Running on port $port</p>
  <p>Connected clients: ${clients.length}</p>
  <p>Use WebSocket URL: ws://localhost:$port</p>
</body>
</html>
''')
        ..close();
    }
  }
}
