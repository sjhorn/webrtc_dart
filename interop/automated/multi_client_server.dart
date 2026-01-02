// Multi-Client Browser Test Server
//
// This server demonstrates handling multiple simultaneous clients:
// 1. Each browser gets its own PeerConnection
// 2. RTCDataChannel communication verified for each client
// 3. Tests broadcast/SFU architecture capability
//
// Pattern: Dart creates offer for each client (broadcast style)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:webrtc_dart/webrtc_dart.dart';

class ClientConnection {
  final String id;
  final RTCPeerConnection pc;
  dynamic dc; // RTCDataChannel or ProxyDataChannel
  final List<Map<String, dynamic>> candidates = [];
  DateTime? connectedTime;
  int messagesSent = 0;
  int messagesReceived = 0;
  bool isConnected = false;
  bool dcOpen = false;

  ClientConnection(this.id, this.pc);
}

class MultiClientServer {
  HttpServer? _server;
  final Map<String, ClientConnection> _clients = {};
  int _clientCounter = 0;
  String _currentBrowser = 'unknown';
  int _maxConcurrentClients = 0;

  Future<void> start({int port = 8783}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('[Multi] Started on http://localhost:$port');

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
    print('[Multi] ${request.method} $path');

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
          await _handleOffer2(request);
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
        case '/ping':
          await _handlePing(request);
          break;
        case '/status':
          await _handleStatus(request);
          break;
        case '/result':
          await _handleResult(request);
          break;
        case '/disconnect':
          await _handleDisconnect(request);
          break;
        case '/reset':
          await _handleReset(request);
          break;
        default:
          request.response.statusCode = 404;
          request.response.write('Not found');
      }
    } catch (e, st) {
      print('[Multi] Error: $e');
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
    print('[Multi] Starting test for: $_currentBrowser');

    await _cleanupAll();
    _clientCounter = 0;
    _maxConcurrentClients = 0;

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _handleConnect(HttpRequest request) async {
    final clientId = 'client_${++_clientCounter}';
    print('[Multi] New connection: $clientId');

    // Create peer connection for this client
    final pc = RTCPeerConnection(RtcConfiguration(
      iceServers: [
        IceServer(urls: ['stun:stun.l.google.com:19302'])
      ],
    ));

    final client = ClientConnection(clientId, pc);
    _clients[clientId] = client;

    // Track max concurrent clients
    if (_clients.length > _maxConcurrentClients) {
      _maxConcurrentClients = _clients.length;
    }
    print('[Multi] Active clients: ${_clients.length}');

    pc.onConnectionStateChange.listen((state) {
      print('[Multi] [$clientId] Connection state: $state');
      if (state == PeerConnectionState.connected) {
        client.isConnected = true;
        client.connectedTime = DateTime.now();
      }
    });

    pc.onIceConnectionStateChange.listen((state) {
      print('[Multi] [$clientId] ICE state: $state');
    });

    pc.onIceCandidate.listen((candidate) {
      print('[Multi] [$clientId] ICE candidate: ${candidate.type}');
      client.candidates.add({
        'candidate': 'candidate:${candidate.toSdp()}',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      });
    });

    // Return client ID - RTCDataChannel and offer will be created in /offer endpoint
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'clientId': clientId}));
  }

  Future<void> _handleOffer2(HttpRequest request) async {
    final clientId = request.uri.queryParameters['clientId'];
    if (clientId == null) {
      request.response.statusCode = 400;
      request.response.write('Missing clientId parameter');
      return;
    }

    final client = _clients[clientId];
    if (client == null) {
      request.response.statusCode = 400;
      request.response.write('Unknown client: $clientId');
      return;
    }

    // Create RTCDataChannel before createOffer (will be included in SDP)
    client.dc = client.pc.createDataChannel('client-$clientId');
    print('[Multi] [$clientId] Created RTCDataChannel');

    client.dc!.onStateChange.listen((state) {
      print('[Multi] [$clientId] RTCDataChannel state: $state');
      if (state == DataChannelState.open) {
        client.dcOpen = true;
      }
    });

    client.dc!.onMessage.listen((data) {
      client.messagesReceived++;
      final msg = data is String ? data : String.fromCharCodes(data);
      print('[Multi] [$clientId] Received: $msg');
    });

    // Create offer
    final offer = await client.pc.createOffer();
    await client.pc.setLocalDescription(offer);
    print('[Multi] [$clientId] Created offer');

    // Debug: Check if SDP includes SCTP (data channel)
    final hasSctp = offer.sdp.contains('m=application');
    print('[Multi] [$clientId] SDP has SCTP: $hasSctp');

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

    final answer = RTCSessionDescription(
      type: data['type'] as String,
      sdp: data['sdp'] as String,
    );

    print('[Multi] [$clientId] Received answer');
    // Debug: Print SCTP-related parts of answer SDP
    if (answer.sdp.contains('m=application')) {
      final lines = answer.sdp.split('\n').where((l) =>
          l.contains('m=application') ||
          l.contains('sctp-port') ||
          l.contains('sctpmap'));
      print('[Multi] [$clientId] Answer SCTP lines: ${lines.toList()}');
    }
    await client.pc.setRemoteDescription(answer);
    print('[Multi] [$clientId] Remote description set');

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
      final candidate = RTCIceCandidate.fromSdp(candidateStr);
      await client.pc.addIceCandidate(candidate);
      print('[Multi] [$clientId] Added candidate: ${candidate.type}');
    } catch (e) {
      print('[Multi] [$clientId] Failed to add candidate: $e');
    }

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _handleCandidates(HttpRequest request) async {
    final clientId = request.uri.queryParameters['clientId'];
    if (clientId == null) {
      request.response.statusCode = 400;
      request.response.write('Missing clientId parameter');
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

  Future<void> _handlePing(HttpRequest request) async {
    final clientId = request.uri.queryParameters['clientId'];
    if (clientId == null) {
      request.response.statusCode = 400;
      request.response.write('Missing clientId parameter');
      return;
    }

    final client = _clients[clientId];
    if (client == null || !client.dcOpen) {
      request.response.statusCode = 400;
      request.response.write('Client not ready: $clientId');
      return;
    }

    final msg = 'ping to $clientId';
    client.dc!.sendString(msg);
    client.messagesSent++;
    print('[Multi] [$clientId] Sent: $msg');

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _handleStatus(HttpRequest request) async {
    final clientStatuses = _clients.entries.map((e) {
      final c = e.value;
      return {
        'clientId': c.id,
        'connected': c.isConnected,
        'dcOpen': c.dcOpen,
        'messagesSent': c.messagesSent,
        'messagesReceived': c.messagesReceived,
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
    final dcOpenClients = _clients.values.where((c) => c.dcOpen).length;
    final totalMessagesSent =
        _clients.values.fold<int>(0, (sum, c) => sum + c.messagesSent);
    final totalMessagesReceived =
        _clients.values.fold<int>(0, (sum, c) => sum + c.messagesReceived);

    // Success if we had multiple clients connect and communicate
    final success = _maxConcurrentClients >= 2 &&
        connectedClients == _maxConcurrentClients &&
        dcOpenClients == _maxConcurrentClients &&
        totalMessagesSent > 0;

    final result = {
      'browser': _currentBrowser,
      'success': success,
      'maxConcurrentClients': _maxConcurrentClients,
      'connectedClients': connectedClients,
      'dcOpenClients': dcOpenClients,
      'totalClientConnections': _clientCounter,
      'messagesSent': totalMessagesSent,
      'messagesReceived': totalMessagesReceived,
      'clients': _clients.entries.map((e) {
        final c = e.value;
        return {
          'id': c.id,
          'connected': c.isConnected,
          'dcOpen': c.dcOpen,
          'sent': c.messagesSent,
          'recv': c.messagesReceived,
        };
      }).toList(),
    };

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(result));
  }

  Future<void> _handleDisconnect(HttpRequest request) async {
    final clientId = request.uri.queryParameters['clientId'];
    if (clientId != null) {
      final client = _clients.remove(clientId);
      if (client != null) {
        await client.pc.close();
        print('[Multi] [$clientId] Disconnected');
      }
    }

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _handleReset(HttpRequest request) async {
    await _cleanupAll();
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _cleanupAll() async {
    for (final client in _clients.values) {
      await client.pc.close();
    }
    _clients.clear();
  }

  static const String _testPageHtml = '''
<!DOCTYPE html>
<html>
<head>
    <title>WebRTC Multi-Client Test</title>
    <style>
        body { font-family: monospace; padding: 20px; background: #1a1a1a; color: #eee; }
        #log { background: #0a0a0a; padding: 10px; height: 300px; overflow-y: auto; border: 1px solid #333; }
        .info { color: #8af; }
        .success { color: #8f8; }
        .error { color: #f88; }
        .client { color: #fa8; }
        h1 { color: #8af; }
        #status { margin: 10px 0; padding: 10px; background: #333; }
        .badge { background: #a80; color: #fff; padding: 2px 8px; border-radius: 4px; }
        .stats { display: flex; gap: 20px; margin: 10px 0; flex-wrap: wrap; }
        .stat { background: #333; padding: 10px; border-radius: 4px; }
        .stat-value { font-size: 1.5em; color: #8f8; }
        .stat-label { font-size: 0.8em; color: #888; }
        .clients { display: flex; gap: 10px; margin: 10px 0; flex-wrap: wrap; }
        .client-card { background: #333; padding: 10px; border-radius: 4px; min-width: 100px; }
        .client-id { font-weight: bold; color: #fa8; }
        .client-status { font-size: 0.9em; }
    </style>
</head>
<body>
    <h1>Multi-Client Test <span class="badge">Broadcast</span></h1>
    <p>Tests handling multiple simultaneous browser connections.</p>
    <div id="status">Status: Waiting to start...</div>
    <div class="stats">
        <div class="stat">
            <div class="stat-label">Clients Connected</div>
            <div id="clientCount" class="stat-value">0</div>
        </div>
        <div class="stat">
            <div class="stat-label">DataChannels Open</div>
            <div id="dcCount" class="stat-value">0</div>
        </div>
        <div class="stat">
            <div class="stat-label">Messages</div>
            <div id="messages" class="stat-value">0</div>
        </div>
    </div>
    <div id="clients" class="clients"></div>
    <div id="log"></div>

    <script>
        const connections = new Map();
        let messageCount = 0;
        const serverBase = window.location.origin;
        const NUM_CLIENTS = 3; // Number of simultaneous connections to test

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
            const dcOpen = Array.from(connections.values()).filter(c => c.dcOpen).length;
            document.getElementById('clientCount').textContent = connected;
            document.getElementById('dcCount').textContent = dcOpen;
            document.getElementById('messages').textContent = messageCount;

            // Update client cards
            const clientsDiv = document.getElementById('clients');
            clientsDiv.innerHTML = '';
            for (const [id, conn] of connections) {
                const card = document.createElement('div');
                card.className = 'client-card';
                card.innerHTML = '<div class="client-id">' + id + '</div>' +
                    '<div class="client-status">' +
                    (conn.connected ? '✓ Connected' : '○ Connecting') + '<br>' +
                    (conn.dcOpen ? '✓ DC Open' : '○ DC Pending') +
                    '</div>';
                clientsDiv.appendChild(card);
            }
        }

        async function createClient(index) {
            const browser = detectBrowser();
            log('Creating client ' + (index + 1) + '...', 'client');

            // Step 1: Request new connection from server (creates PC)
            const connectResp = await fetch(serverBase + '/connect');
            const { clientId } = await connectResp.json();
            log('Got client ID: ' + clientId, 'client');

            const pc = new RTCPeerConnection({
                iceServers: [{ urls: 'stun:stun.l.google.com:19302' }]
            });

            const conn = { pc, clientId, connected: false, dcOpen: false, dc: null };
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

            pc.oniceconnectionstatechange = () => {
                if (pc.iceConnectionState === 'connected') {
                    conn.connected = true;
                    log('[' + clientId + '] ICE connected', 'success');
                    updateStats();
                }
            };

            pc.onconnectionstatechange = () => {
                log('[' + clientId + '] Connection state: ' + pc.connectionState);
                if (pc.connectionState === 'connected') {
                    conn.connected = true;
                    updateStats();
                }
            };

            pc.ondatachannel = (e) => {
                conn.dc = e.channel;
                log('[' + clientId + '] RTCDataChannel received: ' + e.channel.label, 'client');

                e.channel.onopen = () => {
                    conn.dcOpen = true;
                    log('[' + clientId + '] RTCDataChannel open!', 'success');
                    updateStats();
                };

                e.channel.onmessage = (ev) => {
                    messageCount++;
                    log('[' + clientId + '] Received: ' + ev.data, 'success');
                    e.channel.send('pong from ' + clientId);
                    updateStats();
                };
            };

            // Step 2: Request offer (creates DC and offer on server)
            const offerResp = await fetch(serverBase + '/offer?clientId=' + clientId);
            const offer = await offerResp.json();
            log('[' + clientId + '] Got offer', 'client');

            await pc.setRemoteDescription(new RTCSessionDescription(offer));
            log('[' + clientId + '] Remote description set');

            const answer = await pc.createAnswer();
            await pc.setLocalDescription(answer);
            log('[' + clientId + '] Local description set');

            await fetch(serverBase + '/answer', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    clientId,
                    type: answer.type,
                    sdp: pc.localDescription.sdp
                })
            });
            log('[' + clientId + '] Sent answer');

            // Poll for server candidates
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
                log('Browser detected: ' + browser);
                setStatus('Starting multi-client test for ' + browser);

                await fetch(serverBase + '/start?browser=' + browser);
                log('Server test started');

                // Create multiple clients simultaneously
                setStatus('Creating ' + NUM_CLIENTS + ' simultaneous connections...');
                const clientPromises = [];
                for (let i = 0; i < NUM_CLIENTS; i++) {
                    clientPromises.push(createClient(i));
                }

                // Wait for all clients to be created
                await Promise.all(clientPromises);
                log('All ' + NUM_CLIENTS + ' clients created');

                // Wait for all connections and DCs to open
                setStatus('Waiting for connections...');
                await waitForAllConnected();
                log('All clients connected!', 'success');

                await waitForAllDCOpen();
                log('All DataChannels open!', 'success');

                // Test messaging to each client
                setStatus('Testing communication with each client...');
                for (const [clientId, conn] of connections) {
                    await fetch(serverBase + '/ping?clientId=' + clientId);
                    log('[' + clientId + '] Ping sent');
                }

                await new Promise(r => setTimeout(r, 2000));

                // Get results
                setStatus('Getting results...');
                const resultResp = await fetch(serverBase + '/result');
                const result = await resultResp.json();

                if (result.success) {
                    log('TEST PASSED! Multi-client handling works', 'success');
                    log('  Max concurrent clients: ' + result.maxConcurrentClients, 'success');
                    log('  All clients connected and communicated', 'success');
                    setStatus('TEST PASSED - ' + result.maxConcurrentClients + ' clients handled');
                } else {
                    log('TEST FAILED', 'error');
                    log('  Connected: ' + result.connectedClients + '/' + result.maxConcurrentClients, 'error');
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

        async function waitForAllConnected() {
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

        async function waitForAllDCOpen() {
            return new Promise((resolve, reject) => {
                const timeout = setTimeout(() => reject(new Error('RTCDataChannel timeout')), 15000);
                const check = () => {
                    const allOpen = Array.from(connections.values()).every(c => c.dcOpen);
                    if (allOpen && connections.size === NUM_CLIENTS) {
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
  // Enable SCTP and RTCDataChannel logging
  hierarchicalLoggingEnabled = true;
  WebRtcLogging.sctp.level = Level.FINE;
  WebRtcLogging.datachannel.level = Level.FINE;
  WebRtcLogging.transport.level = Level.FINE;
  Logger.root.onRecord.listen((record) {
    if (record.loggerName.startsWith('webrtc')) {
      print('[LOG] ${record.loggerName}: ${record.message}');
    }
  });

  final server = MultiClientServer();
  await server.start(port: 8783);
}
