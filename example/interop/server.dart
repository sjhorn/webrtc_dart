/// Interop Server Example
///
/// HTTP server for browser interop testing. Accepts POST /offer
/// with browser's SDP offer, returns SDP answer. Echoes media
/// and datachannel messages back to browser.
///
/// Usage: dart run example/interop/server.dart [--port 8080]
library;

import 'dart:convert';
import 'dart:io';

import 'package:webrtc_dart/webrtc_dart.dart';

void main(List<String> args) async {
  final port = args.contains('--port')
      ? int.parse(args[args.indexOf('--port') + 1])
      : 8080;

  print('Interop Server Example');
  print('=' * 50);

  final server = await HttpServer.bind('0.0.0.0', port);
  print('Server running on http://0.0.0.0:$port');
  print('');
  print('Endpoints:');
  print('  POST /offer - Send browser offer, receive answer');
  print('  GET /       - Test page (if implemented)');

  await for (final request in server) {
    _handleRequest(request);
  }
}

Future<void> _handleRequest(HttpRequest request) async {
  // CORS headers for browser access
  request.response.headers.add('Access-Control-Allow-Origin', '*');
  request.response.headers
      .add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');

  if (request.method == 'OPTIONS') {
    request.response.statusCode = 200;
    await request.response.close();
    return;
  }

  final path = request.uri.path;

  if (path == '/offer' && request.method == 'POST') {
    await _handleOffer(request);
  } else if (path == '/' || path == '/index.html') {
    request.response.headers.contentType = ContentType.html;
    request.response.write(_testPageHtml);
    await request.response.close();
  } else {
    request.response.statusCode = 404;
    request.response.write('Not found');
    await request.response.close();
  }
}

Future<void> _handleOffer(HttpRequest request) async {
  try {
    final body = await utf8.decoder.bind(request).join();
    final offer = json.decode(body) as Map<String, dynamic>;

    print('[Server] Received offer from browser');

    final pc = RTCPeerConnection(RtcConfiguration(
      iceServers: [
        IceServer(urls: ['stun:stun.l.google.com:19302'])
      ],
    ));

    pc.onConnectionStateChange.listen((state) {
      print('[Server] Connection: $state');
    });

    // Echo incoming tracks back
    pc.onTrack.listen((transceiver) {
      print('[Server] Received ${transceiver.kind} track, echoing back');
      final track = transceiver.receiver.track;
      transceiver.sender.replaceTrack(track);
    });

    // Echo datachannel messages
    pc.onDataChannel.listen((dc) {
      print('[Server] RTCDataChannel: ${dc.label}');
      dc.onMessage.listen((msg) {
        print('[Server] DC message: ${String.fromCharCodes(msg)}');
        dc.send(msg); // Echo back
      });
    });

    // Set remote description (browser's offer)
    await pc.setRemoteDescription(RTCSessionDescription(
      type: offer['type'] as String,
      sdp: offer['sdp'] as String,
    ));

    // Create and set answer
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);

    // Send answer back
    request.response.headers.contentType = ContentType.json;
    request.response.write(json.encode({
      'type': answer.type,
      'sdp': answer.sdp,
    }));
    await request.response.close();

    print('[Server] Sent answer to browser');
  } catch (e) {
    print('[Server] Error: $e');
    request.response.statusCode = 500;
    request.response.write('Error: $e');
    await request.response.close();
  }
}

const _testPageHtml = '''
<!DOCTYPE html>
<html>
<head>
  <title>WebRTC Interop Test</title>
  <style>
    body { font-family: monospace; padding: 20px; }
    button { padding: 10px 20px; margin: 5px; }
    #log { height: 300px; overflow-y: auto; background: #f0f0f0; padding: 10px; margin-top: 20px; }
  </style>
</head>
<body>
  <h1>WebRTC Interop Test</h1>
  <button onclick="testDataChannel()">Test RTCDataChannel</button>
  <button onclick="testMedia()">Test Media</button>
  <div id="log"></div>

  <script>
    function log(msg) {
      const div = document.getElementById('log');
      div.innerHTML += msg + '<br>';
      div.scrollTop = div.scrollHeight;
      console.log(msg);
    }

    async function testDataChannel() {
      log('Starting RTCDataChannel test...');
      const pc = new RTCPeerConnection({
        iceServers: [{ urls: 'stun:stun.l.google.com:19302' }]
      });

      const dc = pc.createDataChannel('test');
      dc.onopen = () => {
        log('RTCDataChannel open, sending message');
        dc.send('Hello from browser!');
      };
      dc.onmessage = (e) => log('Received: ' + e.data);

      pc.onicecandidate = (e) => {
        if (!e.candidate) {
          sendOffer(pc.localDescription);
        }
      };

      const offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
    }

    async function testMedia() {
      log('Starting Media test...');
      const pc = new RTCPeerConnection({
        iceServers: [{ urls: 'stun:stun.l.google.com:19302' }]
      });

      const stream = await navigator.mediaDevices.getUserMedia({ video: true, audio: true });
      stream.getTracks().forEach(t => pc.addTrack(t, stream));

      pc.ontrack = (e) => log('Received track: ' + e.track.kind);
      pc.onicecandidate = (e) => {
        if (!e.candidate) {
          sendOffer(pc.localDescription);
        }
      };

      const offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
    }

    async function sendOffer(offer) {
      log('Sending offer to server...');
      const res = await fetch('/offer', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(offer)
      });
      const answer = await res.json();
      log('Received answer from server');
      // Note: Need to set remote description on the peer connection
    }
  </script>
</body>
</html>
''';
