// Multi-Client Sendrecv Server for Automated Browser Testing
//
// This server handles multiple clients with bidirectional video:
// 1. Each browser gets its own PeerConnection
// 2. Browser sends camera video to Dart server
// 3. Dart echoes video back to each browser
//
// Pattern: Dart is OFFERER (sendrecv), Browser is ANSWERER (sendrecv)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:webrtc_dart/webrtc_dart.dart';
import 'package:webrtc_dart/src/nonstandard/media/track.dart' as nonstandard;

class ClientConnection {
  final String id;
  final RtcPeerConnection pc;
  final nonstandard.MediaStreamTrack sendTrack;
  final List<Map<String, dynamic>> candidates = [];
  DateTime? connectedTime;
  int rtpPacketsReceived = 0;
  int rtpPacketsEchoed = 0;
  bool isConnected = false;
  bool hasTrack = false;
  int echoFramesReported = 0;

  ClientConnection(this.id, this.pc, this.sendTrack);
}

class MultiClientSendrecvServer {
  HttpServer? _server;
  final Map<String, ClientConnection> _clients = {};
  int _clientCounter = 0;
  String _currentBrowser = 'unknown';
  int _maxConcurrentClients = 0;

  Future<void> start({int port = 8793}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('[MultiSendrecv] Started on http://localhost:$port');

    await for (final request in _server!) {
      _handleRequest(request);
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers
        .add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers
        .add('Access-Control-Allow-Headers', 'Content-Type');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = 200;
      await request.response.close();
      return;
    }

    final path = request.uri.path;
    print('[MultiSendrecv] ${request.method} $path');

    try {
      switch (path) {
        case '/':
        case '/index.html':
          await _serveTestPage(request);
          break;
        case '/start':
          await _handleStart(request);
          break;
        case '/connect':
          await _handleConnect(request);
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
          await _handleCandidates(request);
          break;
        case '/report':
          await _handleReport(request);
          break;
        case '/status':
          await _handleStatus(request);
          break;
        case '/result':
          await _handleResult(request);
          break;
        case '/reset':
          await _handleReset(request);
          break;
        default:
          request.response.statusCode = 404;
          request.response.write('Not found');
      }
    } catch (e, st) {
      print('[MultiSendrecv] Error: $e');
      print(st);
      request.response.statusCode = 500;
      request.response.write('Error: $e');
    }

    await request.response.close();
  }

  Future<void> _serveTestPage(HttpRequest request) async {
    request.response.headers.contentType = ContentType.html;
    request.response.write(_testPageHtml);
  }

  Future<void> _handleStart(HttpRequest request) async {
    _currentBrowser = request.uri.queryParameters['browser'] ?? 'unknown';
    print('[MultiSendrecv] Starting test for: $_currentBrowser');

    await _cleanupAll();
    _clientCounter = 0;
    _maxConcurrentClients = 0;

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _handleConnect(HttpRequest request) async {
    final clientId = 'client_${++_clientCounter}';
    print('[MultiSendrecv] New connection: $clientId');

    // Create peer connection for this client
    final pc = RtcPeerConnection(RtcConfiguration(
      iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
    ));

    // Create send track for echoing
    final sendTrack =
        nonstandard.MediaStreamTrack(kind: nonstandard.MediaKind.video);

    final client = ClientConnection(clientId, pc, sendTrack);
    _clients[clientId] = client;

    // Track max concurrent clients
    if (_clients.length > _maxConcurrentClients) {
      _maxConcurrentClients = _clients.length;
    }
    print('[MultiSendrecv] Active clients: ${_clients.length}');

    pc.onConnectionStateChange.listen((state) {
      print('[MultiSendrecv] [$clientId] Connection state: $state');
      if (state == PeerConnectionState.connected) {
        client.isConnected = true;
        client.connectedTime = DateTime.now();
      }
    });

    pc.onIceConnectionStateChange.listen((state) {
      print('[MultiSendrecv] [$clientId] ICE state: $state');
    });

    pc.onIceCandidate.listen((candidate) {
      print('[MultiSendrecv] [$clientId] ICE candidate: ${candidate.type}');
      client.candidates.add({
        'candidate': 'candidate:${candidate.toSdp()}',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      });
    });

    // Handle incoming track and echo RTP packets back
    pc.onTrack.listen((transceiver) {
      print('[MultiSendrecv] [$clientId] Received track: ${transceiver.kind}');
      client.hasTrack = true;

      final track = transceiver.receiver.track;
      track.onReceiveRtp.listen((rtpPacket) {
        client.rtpPacketsReceived++;

        // Echo the RTP packet back to the browser
        sendTrack.writeRtp(rtpPacket);
        client.rtpPacketsEchoed++;

        if (client.rtpPacketsReceived % 100 == 0) {
          print(
              '[MultiSendrecv] [$clientId] Recv: ${client.rtpPacketsReceived}, Echo: ${client.rtpPacketsEchoed}');
        }
      });
    });

    // Add sendrecv video transceiver with send track
    pc.addTransceiverWithTrack(
      sendTrack,
      direction: RtpTransceiverDirection.sendrecv,
    );

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'clientId': clientId}));
  }

  Future<void> _handleOffer(HttpRequest request) async {
    final clientId = request.uri.queryParameters['clientId'];
    if (clientId == null) {
      request.response.statusCode = 400;
      request.response.write('Missing clientId');
      return;
    }

    final client = _clients[clientId];
    if (client == null) {
      request.response.statusCode = 400;
      request.response.write('Unknown client: $clientId');
      return;
    }

    // Create and send offer
    final offer = await client.pc.createOffer();
    await client.pc.setLocalDescription(offer);
    print('[MultiSendrecv] [$clientId] Created offer');

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'type': offer.type,
      'sdp': offer.sdp,
    }));
  }

  Future<void> _handleAnswer(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    final data = jsonDecode(body) as Map<String, dynamic>;
    final clientId = data['clientId'] as String;

    final client = _clients[clientId];
    if (client == null) {
      request.response.statusCode = 400;
      request.response.write('Unknown client: $clientId');
      return;
    }

    final answer = SessionDescription(
      type: data['type'] as String,
      sdp: data['sdp'] as String,
    );

    print('[MultiSendrecv] [$clientId] Received answer');
    await client.pc.setRemoteDescription(answer);
    print('[MultiSendrecv] [$clientId] Remote description set');

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _handleCandidate(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    final data = jsonDecode(body) as Map<String, dynamic>;
    final clientId = data['clientId'] as String;

    final client = _clients[clientId];
    if (client == null) {
      request.response.statusCode = 400;
      request.response.write('Unknown client: $clientId');
      return;
    }

    String candidateStr = data['candidate'] as String? ?? '';

    if (candidateStr.isEmpty || candidateStr.trim().isEmpty) {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'status': 'ok'}));
      return;
    }

    if (candidateStr.startsWith('candidate:')) {
      candidateStr = candidateStr.substring('candidate:'.length);
    }

    try {
      final candidate = Candidate.fromSdp(candidateStr);
      await client.pc.addIceCandidate(candidate);
      print('[MultiSendrecv] [$clientId] Added candidate: ${candidate.type}');
    } catch (e) {
      print('[MultiSendrecv] [$clientId] Failed to add candidate: $e');
    }

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _handleCandidates(HttpRequest request) async {
    final clientId = request.uri.queryParameters['clientId'];
    if (clientId == null) {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode([]));
      return;
    }

    final client = _clients[clientId];
    if (client == null) {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode([]));
      return;
    }

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(client.candidates));
  }

  Future<void> _handleReport(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    final data = jsonDecode(body) as Map<String, dynamic>;
    final clientId = data['clientId'] as String;
    final echoFrames = data['echoFrames'] as int? ?? 0;

    final client = _clients[clientId];
    if (client != null) {
      client.echoFramesReported = echoFrames;
      print('[MultiSendrecv] [$clientId] Browser reports $echoFrames echo frames');
    }

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _handleStatus(HttpRequest request) async {
    final clientStatuses = _clients.entries.map((e) {
      final c = e.value;
      return {
        'clientId': c.id,
        'connected': c.isConnected,
        'hasTrack': c.hasTrack,
        'rtpReceived': c.rtpPacketsReceived,
        'rtpEchoed': c.rtpPacketsEchoed,
        'echoFrames': c.echoFramesReported,
      };
    }).toList();

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'clientCount': _clients.length,
      'maxConcurrentClients': _maxConcurrentClients,
      'clients': clientStatuses,
    }));
  }

  Future<void> _handleResult(HttpRequest request) async {
    final connectedClients = _clients.values.where((c) => c.isConnected).length;
    final clientsWithTrack = _clients.values.where((c) => c.hasTrack).length;
    final totalRtpReceived = _clients.values
        .fold<int>(0, (sum, c) => sum + c.rtpPacketsReceived);
    final totalRtpEchoed = _clients.values
        .fold<int>(0, (sum, c) => sum + c.rtpPacketsEchoed);
    final totalEchoFrames = _clients.values
        .fold<int>(0, (sum, c) => sum + c.echoFramesReported);

    // Success if multiple clients connected, sent video, and received echoes
    final success = _maxConcurrentClients >= 2 &&
        connectedClients >= 2 &&
        totalRtpReceived > 0 &&
        totalEchoFrames > 0;

    final result = {
      'browser': _currentBrowser,
      'success': success,
      'maxConcurrentClients': _maxConcurrentClients,
      'connectedClients': connectedClients,
      'clientsWithTrack': clientsWithTrack,
      'totalRtpReceived': totalRtpReceived,
      'totalRtpEchoed': totalRtpEchoed,
      'totalEchoFrames': totalEchoFrames,
      'clients': _clients.entries.map((e) {
        final c = e.value;
        return {
          'id': c.id,
          'connected': c.isConnected,
          'hasTrack': c.hasTrack,
          'rtpReceived': c.rtpPacketsReceived,
          'rtpEchoed': c.rtpPacketsEchoed,
          'echoFrames': c.echoFramesReported,
        };
      }).toList(),
    };

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(result));
  }

  Future<void> _handleReset(HttpRequest request) async {
    await _cleanupAll();
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _cleanupAll() async {
    for (final client in _clients.values) {
      client.sendTrack.stop();
      await client.pc.close();
    }
    _clients.clear();
  }

  static const String _testPageHtml = '''
<!DOCTYPE html>
<html>
<head>
    <title>WebRTC Multi-Client Sendrecv Test</title>
    <style>
        body { font-family: monospace; padding: 20px; background: #1a1a1a; color: #eee; }
        #log { background: #0a0a0a; padding: 10px; height: 200px; overflow-y: auto; border: 1px solid #333; }
        .info { color: #8af; }
        .success { color: #8f8; }
        .error { color: #f88; }
        .client { color: #fa8; }
        h1 { color: #8af; }
        #status { margin: 10px 0; padding: 10px; background: #333; }
        .badge { background: #80a; color: #fff; padding: 2px 8px; border-radius: 4px; }
        .stats { display: flex; gap: 20px; margin: 10px 0; flex-wrap: wrap; }
        .stat { background: #333; padding: 10px; border-radius: 4px; }
        .stat-value { font-size: 1.5em; color: #8f8; }
        .stat-label { font-size: 0.8em; color: #888; }
        .clients { display: flex; gap: 10px; flex-wrap: wrap; }
        .client-card { background: #333; padding: 10px; border-radius: 4px; min-width: 150px; }
        .client-id { font-weight: bold; color: #fa8; }
        .videos { display: flex; gap: 5px; flex-wrap: wrap; margin: 10px 0; }
        .video-box { background: #000; padding: 3px; }
        .video-box video { width: 200px; height: 150px; }
        .video-label { font-size: 0.8em; color: #888; }
    </style>
</head>
<body>
    <h1>Multi-Client Sendrecv Test <span class="badge">Echo</span></h1>
    <p>Tests bidirectional video with multiple clients (each sends and receives echoed video).</p>
    <div id="status">Status: Waiting to start...</div>
    <div class="stats">
        <div class="stat">
            <div class="stat-label">Clients Connected</div>
            <div id="clientCount" class="stat-value">0</div>
        </div>
        <div class="stat">
            <div class="stat-label">Total Echo Frames</div>
            <div id="totalEcho" class="stat-value">0</div>
        </div>
    </div>
    <div id="videos" class="videos"></div>
    <div id="clients" class="clients"></div>
    <div id="log"></div>

    <script>
        const connections = new Map();
        const serverBase = window.location.origin;
        const NUM_CLIENTS = 3;

        function log(msg, className = 'info') {
            const logDiv = document.getElementById('log');
            const line = document.createElement('div');
            line.className = className;
            line.textContent = '[' + new Date().toISOString().substr(11, 12) + '] ' + msg;
            logDiv.appendChild(line);
            logDiv.scrollTop = logDiv.scrollHeight;
            console.log(msg);
        }

        function setStatus(msg) {
            document.getElementById('status').textContent = 'Status: ' + msg;
        }

        function updateStats() {
            const connected = Array.from(connections.values()).filter(c => c.connected).length;
            const totalEcho = Array.from(connections.values()).reduce((sum, c) => sum + c.echoFrames, 0);
            document.getElementById('clientCount').textContent = connected;
            document.getElementById('totalEcho').textContent = totalEcho;

            // Update client cards
            const clientsDiv = document.getElementById('clients');
            clientsDiv.innerHTML = '';
            for (const [id, conn] of connections) {
                const card = document.createElement('div');
                card.className = 'client-card';
                card.innerHTML = '<div class="client-id">' + id + '</div>' +
                    '<div>' + (conn.connected ? '+ Connected' : 'o Connecting') + '</div>' +
                    '<div>' + (conn.sending ? '+ Sending' : 'o Pending') + '</div>' +
                    '<div>Echo: ' + conn.echoFrames + '</div>';
                clientsDiv.appendChild(card);
            }
        }

        async function createClient(index) {
            log('Creating client ' + (index + 1) + '...', 'client');

            const connectResp = await fetch(serverBase + '/connect');
            const { clientId } = await connectResp.json();
            log('[' + clientId + '] Connected');

            // Create video elements
            const videosDiv = document.getElementById('videos');
            const container = document.createElement('div');
            container.className = 'video-box';
            container.innerHTML =
                '<div class="video-label">' + clientId + ' Echo</div>' +
                '<video id="echo_' + clientId + '" autoPlay muted playsinline></video>';
            videosDiv.appendChild(container);

            const pc = new RTCPeerConnection({
                iceServers: [{ urls: 'stun:stun.l.google.com:19302' }]
            });

            const conn = { pc, clientId, connected: false, sending: false, echoFrames: 0, stream: null };
            connections.set(clientId, conn);
            updateStats();

            pc.onicecandidate = async (e) => {
                if (e.candidate) {
                    await fetch(serverBase + '/candidate', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({
                            clientId,
                            candidate: e.candidate.candidate,
                            sdpMid: e.candidate.sdpMid,
                            sdpMLineIndex: e.candidate.sdpMLineIndex
                        })
                    });
                }
            };

            pc.onconnectionstatechange = () => {
                if (pc.connectionState === 'connected') {
                    conn.connected = true;
                    log('[' + clientId + '] Connected', 'success');
                    updateStats();
                }
            };

            // Handle echoed video from server
            pc.ontrack = (e) => {
                log('[' + clientId + '] Received echo track', 'success');
                const video = document.getElementById('echo_' + clientId);
                if (!video.srcObject) {
                    video.srcObject = new MediaStream();
                }
                video.srcObject.addTrack(e.track);

                // Count echo frames
                if ('requestVideoFrameCallback' in HTMLVideoElement.prototype) {
                    const countFrame = () => {
                        conn.echoFrames++;
                        updateStats();
                        video.requestVideoFrameCallback(countFrame);
                    };
                    video.requestVideoFrameCallback(countFrame);
                }
            };

            // Get camera stream
            const stream = await navigator.mediaDevices.getUserMedia({
                video: { width: 640, height: 480 }
            });
            conn.stream = stream;

            // Get offer from server
            const offerResp = await fetch(serverBase + '/offer?clientId=' + clientId);
            const offer = await offerResp.json();
            log('[' + clientId + '] Got offer');

            await pc.setRemoteDescription(new RTCSessionDescription(offer));

            // Add video track to send to server
            const track = stream.getVideoTracks()[0];
            pc.addTrack(track, stream);
            conn.sending = true;
            log('[' + clientId + '] Added video track', 'success');
            updateStats();

            const answer = await pc.createAnswer();
            await pc.setLocalDescription(answer);

            await fetch(serverBase + '/answer', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    clientId,
                    type: answer.type,
                    sdp: pc.localDescription.sdp
                })
            });

            // Get server ICE candidates
            for (let i = 0; i < 3; i++) {
                await new Promise(r => setTimeout(r, 300));
                const candidatesResp = await fetch(serverBase + '/candidates?clientId=' + clientId);
                const candidates = await candidatesResp.json();
                for (const c of candidates) {
                    if (!c._added) {
                        try {
                            await pc.addIceCandidate(new RTCIceCandidate(c));
                            c._added = true;
                        } catch (e) {}
                    }
                }
            }

            return conn;
        }

        async function runTest() {
            try {
                const browser = detectBrowser();
                log('Browser: ' + browser);
                setStatus('Starting multi-client sendrecv test...');

                await fetch(serverBase + '/start?browser=' + browser);
                log('Server started');

                // Create multiple clients
                setStatus('Creating ' + NUM_CLIENTS + ' clients...');
                for (let i = 0; i < NUM_CLIENTS; i++) {
                    await createClient(i);
                    await new Promise(r => setTimeout(r, 200));
                }

                // Wait for connections
                setStatus('Waiting for connections...');
                await waitForConnections();
                log('All clients connected!', 'success');

                // Wait for echo video
                setStatus('Waiting for echoed video...');
                await new Promise(r => setTimeout(r, 5000));

                // Report echo frames to server
                for (const [clientId, conn] of connections) {
                    await fetch(serverBase + '/report', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({
                            clientId,
                            echoFrames: conn.echoFrames
                        })
                    });
                }

                // Stop streams
                for (const [_, conn] of connections) {
                    if (conn.stream) {
                        conn.stream.getTracks().forEach(t => t.stop());
                    }
                }

                // Get results
                const resultResp = await fetch(serverBase + '/result');
                const result = await resultResp.json();

                if (result.success) {
                    log('TEST PASSED! ' + result.totalEchoFrames + ' echo frames', 'success');
                    setStatus('TEST PASSED');
                } else {
                    log('TEST FAILED', 'error');
                    setStatus('TEST FAILED');
                }

                console.log('TEST_RESULT:' + JSON.stringify(result));
                window.testResult = result;

            } catch (e) {
                log('Error: ' + e.message, 'error');
                setStatus('ERROR: ' + e.message);
                console.log('TEST_RESULT:' + JSON.stringify({ success: false, error: e.message }));
                window.testResult = { success: false, error: e.message };
            }
        }

        async function waitForConnections() {
            return new Promise((resolve, reject) => {
                const timeout = setTimeout(() => reject(new Error('Connection timeout')), 30000);
                const check = () => {
                    const allConnected = Array.from(connections.values()).every(c => c.connected);
                    if (allConnected && connections.size === NUM_CLIENTS) {
                        clearTimeout(timeout);
                        resolve();
                    } else {
                        setTimeout(check, 100);
                    }
                };
                check();
            });
        }

        // Create animated canvas stream as fallback for Safari headless
        function createCanvasStream(width, height, frameRate) {
            const canvas = document.createElement('canvas');
            canvas.width = width;
            canvas.height = height;
            const ctx = canvas.getContext('2d');
            let frame = 0;

            function draw() {
                ctx.fillStyle = '#1a1a2e';
                ctx.fillRect(0, 0, width, height);
                const x = width/2 + Math.sin(frame * 0.05) * (width/4);
                const y = height/2 + Math.cos(frame * 0.03) * (height/4);
                ctx.beginPath();
                ctx.arc(x, y, 40, 0, Math.PI * 2);
                ctx.fillStyle = '#ff6b6b';
                ctx.fill();
                ctx.fillStyle = '#fff';
                ctx.font = '20px sans-serif';
                ctx.fillText('Canvas Stream - Frame ' + frame, 20, 30);
                frame++;
                requestAnimationFrame(draw);
            }
            draw();
            return canvas.captureStream(frameRate);
        }

        function detectBrowser() {
            const ua = navigator.userAgent;
            if (ua.includes('Firefox')) return 'firefox';
            if (ua.includes('Safari') && !ua.includes('Chrome')) return 'safari';
            if (ua.includes('Chrome')) return 'chrome';
            return 'unknown';
        }

        window.addEventListener('load', () => {
            setTimeout(runTest, 500);
        });
    </script>
</body>
</html>
''';
}

void main() async {
  final server = MultiClientSendrecvServer();
  await server.start(port: 8793);
}
