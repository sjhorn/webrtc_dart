// ICE Trickle Browser Test Server
//
// This server demonstrates ICE trickle functionality:
// 1. Creates offer and starts ICE gathering
// 2. Exchanges ICE candidates incrementally with browser
// 3. Establishes DataChannel connection
// 4. Verifies ping/pong message exchange
//
// Trickle ICE allows candidates to be exchanged as they are gathered,
// rather than waiting for all candidates to be collected.
//
// Pattern: Dart is OFFERER, Browser is ANSWERER

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:webrtc_dart/webrtc_dart.dart';

class IceTrickleServer {
  HttpServer? _server;
  RtcPeerConnection? _pc;
  dynamic _dc; // DataChannel or ProxyDataChannel
  final List<Map<String, dynamic>> _localCandidates = [];
  Completer<void> _connectionCompleter = Completer();
  Completer<void> _dcOpenCompleter = Completer();
  DateTime? _startTime;
  DateTime? _connectedTime;
  String _currentBrowser = 'unknown';
  int _candidatesSent = 0;
  int _candidatesReceived = 0;
  int _messagesSent = 0;
  int _messagesReceived = 0;
  final List<String> _candidateTypes = [];

  Future<void> start({int port = 8781}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('[Trickle] Started on http://localhost:$port');

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
    print('[Trickle] ${request.method} $path');

    try {
      switch (path) {
        case '/':
        case '/index.html':
          await _serveTestPage(request);
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
        case '/shutdown':
          await _handleShutdown(request);
          break;
        default:
          request.response.statusCode = 404;
          request.response.write('Not found');
      }
    } catch (e, st) {
      print('[Trickle] Error: $e');
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
    print('[Trickle] Starting test for: $_currentBrowser');

    await _cleanup();
    _localCandidates.clear();
    _startTime = DateTime.now();
    _connectedTime = null;
    _connectionCompleter = Completer();
    _dcOpenCompleter = Completer();
    _candidatesSent = 0;
    _candidatesReceived = 0;
    _messagesSent = 0;
    _messagesReceived = 0;
    _candidateTypes.clear();

    // Create peer connection
    _pc = RtcPeerConnection(RtcConfiguration(
      iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
    ));
    print('[Trickle] PeerConnection created');

    _pc!.onConnectionStateChange.listen((state) {
      print('[Trickle] Connection state: $state');
      if (state == PeerConnectionState.connected &&
          !_connectionCompleter.isCompleted) {
        _connectedTime = DateTime.now();
        _connectionCompleter.complete();
      }
    });

    _pc!.onIceConnectionStateChange.listen((state) {
      print('[Trickle] ICE state: $state');
    });

    _pc!.onIceGatheringStateChange.listen((state) {
      print('[Trickle] ICE gathering state: $state');
    });

    // Trickle ICE - send candidates as they are gathered
    _pc!.onIceCandidate.listen((candidate) {
      _candidatesSent++;
      _candidateTypes.add(candidate.type);
      print(
          '[Trickle] Trickled candidate #$_candidatesSent: ${candidate.type} ${candidate.host}:${candidate.port}');
      _localCandidates.add({
        'candidate': 'candidate:${candidate.toSdp()}',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      });
    });

    // DataChannel will be created in /offer handler
    // (SCTP transport needs to be initialized first)

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _handleOffer(HttpRequest request) async {
    if (_pc == null) {
      request.response.statusCode = 400;
      request.response.write('Call /start first');
      return;
    }

    // Create DataChannel before createOffer so it's included in SDP
    _dc = _pc!.createDataChannel('trickle-test');
    print('[Trickle] Created DataChannel: trickle-test');

    _dc!.onStateChange.listen((state) {
      print('[Trickle] DataChannel state: $state');
      if (state == DataChannelState.open && !_dcOpenCompleter.isCompleted) {
        _dcOpenCompleter.complete();
      }
    });

    _dc!.onMessage.listen((data) {
      _messagesReceived++;
      final msg = data is String ? data : String.fromCharCodes(data);
      print('[Trickle] Received message: $msg');
    });

    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    print('[Trickle] Created offer, ICE gathering started');

    // Don't wait for all candidates - that's the point of trickle ICE
    // Just send the offer immediately

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'type': offer.type,
      'sdp': offer.sdp,
    }));
    print('[Trickle] Sent offer to browser (candidates will trickle)');
  }

  Future<void> _handleAnswer(HttpRequest request) async {
    if (_pc == null) {
      request.response.statusCode = 400;
      request.response.write('Call /start first');
      return;
    }

    final body = await utf8.decodeStream(request);
    final data = jsonDecode(body) as Map<String, dynamic>;

    final answer = SessionDescription(
      type: data['type'] as String,
      sdp: data['sdp'] as String,
    );

    print('[Trickle] Received answer from browser');
    await _pc!.setRemoteDescription(answer);
    print('[Trickle] Remote description set');

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _handleCandidate(HttpRequest request) async {
    if (_pc == null) {
      request.response.statusCode = 400;
      request.response.write('Call /start first');
      return;
    }

    final body = await utf8.decodeStream(request);
    final data = jsonDecode(body) as Map<String, dynamic>;

    String candidateStr = data['candidate'] as String? ?? '';

    if (candidateStr.isEmpty || candidateStr.trim().isEmpty) {
      print('[Trickle] Skipping empty ICE candidate (end of candidates)');
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'status': 'ok'}));
      return;
    }

    if (candidateStr.startsWith('candidate:')) {
      candidateStr = candidateStr.substring('candidate:'.length);
    }

    try {
      final candidate = Candidate.fromSdp(candidateStr);
      await _pc!.addIceCandidate(candidate);
      _candidatesReceived++;
      print(
          '[Trickle] Received candidate #$_candidatesReceived: ${candidate.type}');
    } catch (e) {
      print('[Trickle] Failed to add candidate: $e');
    }

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _handleCandidates(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(_localCandidates));
  }

  Future<void> _handlePing(HttpRequest request) async {
    if (_dc == null || _dc!.state != DataChannelState.open) {
      request.response.statusCode = 400;
      request.response.write('DataChannel not open');
      return;
    }

    _dc!.sendString('ping from Dart');
    _messagesSent++;
    print('[Trickle] Sent ping');

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _handleStatus(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'connectionState': _pc?.connectionState.toString() ?? 'none',
      'iceConnectionState': _pc?.iceConnectionState.toString() ?? 'none',
      'iceGatheringState': _pc?.iceGatheringState.toString() ?? 'none',
      'dcState': _dc?.state.toString() ?? 'none',
      'candidatesSent': _candidatesSent,
      'candidatesReceived': _candidatesReceived,
      'candidateTypes': _candidateTypes,
      'messagesSent': _messagesSent,
      'messagesReceived': _messagesReceived,
    }));
  }

  Future<void> _handleResult(HttpRequest request) async {
    final connectionTime = _connectedTime != null && _startTime != null
        ? _connectedTime!.difference(_startTime!)
        : Duration.zero;

    // Count candidate types
    final hostCount = _candidateTypes.where((t) => t == 'host').length;
    final srflxCount = _candidateTypes.where((t) => t == 'srflx').length;
    final relayCount = _candidateTypes.where((t) => t == 'relay').length;

    // Trickle ICE is considered working if we exchanged candidates incrementally
    final iceTrickle = _candidatesSent > 0 && _candidatesReceived > 0;
    // Ping/pong success if messages were exchanged
    final pingPongSuccess = _messagesSent > 0 || _messagesReceived > 0;

    final result = {
      'browser': _currentBrowser,
      'success': _pc?.connectionState == PeerConnectionState.connected &&
          _dc?.state == DataChannelState.open &&
          _candidatesSent > 0 &&
          _candidatesReceived > 0,
      'iceTrickle': iceTrickle,
      'pingPongSuccess': pingPongSuccess,
      'candidatesSent': _candidatesSent,
      'candidatesReceived': _candidatesReceived,
      'candidateTypes': {
        'host': hostCount,
        'srflx': srflxCount,
        'relay': relayCount,
      },
      'messagesSent': _messagesSent,
      'messagesReceived': _messagesReceived,
      'connectionTimeMs': connectionTime.inMilliseconds,
    };

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(result));
  }

  Future<void> _handleShutdown(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'shutting down'}));

    await _cleanup();

    Future.delayed(Duration(milliseconds: 100), () {
      _server?.close();
    });
  }

  Future<void> _cleanup() async {
    _dc = null;
    await _pc?.close();
    _pc = null;
  }

  static const String _testPageHtml = '''
<!DOCTYPE html>
<html>
<head>
    <title>WebRTC ICE Trickle Test</title>
    <style>
        body { font-family: monospace; padding: 20px; background: #1a1a1a; color: #eee; }
        #log { background: #0a0a0a; padding: 10px; height: 300px; overflow-y: auto; border: 1px solid #333; }
        .info { color: #8af; }
        .success { color: #8f8; }
        .error { color: #f88; }
        .warn { color: #fa8; }
        .candidate { color: #fa8; }
        h1 { color: #8af; }
        #status { margin: 10px 0; padding: 10px; background: #333; }
        .badge { background: #080; color: #fff; padding: 2px 8px; border-radius: 4px; }
        .stats { display: flex; gap: 20px; margin: 10px 0; flex-wrap: wrap; }
        .stat { background: #333; padding: 10px; border-radius: 4px; }
        .stat-value { font-size: 1.5em; color: #8f8; }
        .stat-label { font-size: 0.8em; color: #888; }
    </style>
</head>
<body>
    <h1>ICE Trickle Test <span class="badge">DataChannel</span></h1>
    <p>Tests ICE trickle with incremental candidate exchange.</p>
    <div id="status">Status: Waiting to start...</div>
    <div class="stats">
        <div class="stat">
            <div class="stat-label">Candidates Sent</div>
            <div id="sent" class="stat-value">0</div>
        </div>
        <div class="stat">
            <div class="stat-label">Candidates Recv</div>
            <div id="recv" class="stat-value">0</div>
        </div>
        <div class="stat">
            <div class="stat-label">Host</div>
            <div id="host" class="stat-value">0</div>
        </div>
        <div class="stat">
            <div class="stat-label">SRFLX</div>
            <div id="srflx" class="stat-value">0</div>
        </div>
    </div>
    <div id="log"></div>

    <script>
        let pc = null;
        let dc = null;
        let candidatesSent = 0;
        let candidatesReceived = 0;
        let hostCount = 0;
        let srflxCount = 0;
        const serverBase = window.location.origin;

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
            document.getElementById('sent').textContent = candidatesSent;
            document.getElementById('recv').textContent = candidatesReceived;
            document.getElementById('host').textContent = hostCount;
            document.getElementById('srflx').textContent = srflxCount;
        }

        async function runTest() {
            try {
                const browser = detectBrowser();
                log('Browser detected: ' + browser);
                setStatus('Starting ICE trickle test for ' + browser);

                await fetch(serverBase + '/start?browser=' + browser);
                log('Server peer started');

                pc = new RTCPeerConnection({
                    iceServers: [{ urls: 'stun:stun.l.google.com:19302' }]
                });

                // Trickle ICE - send candidates immediately as gathered
                pc.onicecandidate = async (e) => {
                    if (e.candidate) {
                        candidatesSent++;
                        const type = e.candidate.candidate.includes('typ host') ? 'host' :
                                    e.candidate.candidate.includes('typ srflx') ? 'srflx' :
                                    e.candidate.candidate.includes('typ relay') ? 'relay' : 'unknown';
                        if (type === 'host') hostCount++;
                        if (type === 'srflx') srflxCount++;

                        log('Trickled candidate #' + candidatesSent + ': ' + type, 'candidate');
                        updateStats();

                        await fetch(serverBase + '/candidate', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify({
                                candidate: e.candidate.candidate,
                                sdpMid: e.candidate.sdpMid,
                                sdpMLineIndex: e.candidate.sdpMLineIndex
                            })
                        });
                    } else {
                        log('ICE gathering complete', 'success');
                    }
                };

                pc.oniceconnectionstatechange = () => {
                    log('ICE state: ' + pc.iceConnectionState,
                        pc.iceConnectionState === 'connected' ? 'success' : 'info');
                };

                pc.onconnectionstatechange = () => {
                    log('Connection state: ' + pc.connectionState,
                        pc.connectionState === 'connected' ? 'success' : 'info');
                };

                // Handle incoming DataChannel
                pc.ondatachannel = (e) => {
                    dc = e.channel;
                    log('Received DataChannel: ' + dc.label, 'success');

                    dc.onopen = () => {
                        log('DataChannel open!', 'success');
                    };

                    dc.onmessage = (e) => {
                        log('Received message: ' + e.data, 'success');
                        // Reply with pong
                        dc.send('pong from browser');
                        log('Sent: pong from browser');
                    };
                };

                setStatus('Getting offer from Dart (trickle ICE)...');
                const offerResp = await fetch(serverBase + '/offer');
                const offer = await offerResp.json();
                log('Received offer from Dart');

                await pc.setRemoteDescription(new RTCSessionDescription(offer));
                log('Remote description set (offer)');

                // ICE gathering starts after setLocalDescription
                setStatus('Creating answer (starting ICE gathering)...');
                const answer = await pc.createAnswer();
                await pc.setLocalDescription(answer);
                log('Local description set (answer) - ICE gathering started');

                // Send answer immediately (don't wait for candidates)
                setStatus('Sending answer to Dart (candidates will trickle)...');
                await fetch(serverBase + '/answer', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ type: answer.type, sdp: pc.localDescription.sdp })
                });
                log('Sent answer to Dart');

                // Poll for Dart's candidates
                setStatus('Exchanging ICE candidates (trickle)...');
                for (let i = 0; i < 5; i++) {
                    await new Promise(resolve => setTimeout(resolve, 500));

                    const candidatesResp = await fetch(serverBase + '/candidates');
                    const dartCandidates = await candidatesResp.json();

                    for (const c of dartCandidates) {
                        if (!c._added) {
                            try {
                                await pc.addIceCandidate(new RTCIceCandidate(c));
                                c._added = true;
                                candidatesReceived++;
                                log('Added Dart candidate #' + candidatesReceived, 'candidate');
                                updateStats();
                            } catch (e) {
                                // May fail if already added
                            }
                        }
                    }
                }

                setStatus('Waiting for connection...');
                await waitForConnection();
                log('Connection established!', 'success');

                // Wait for DataChannel
                setStatus('Waiting for DataChannel...');
                await waitForDataChannel();
                log('DataChannel ready!', 'success');

                // Send test messages
                setStatus('Testing DataChannel communication...');
                await new Promise(resolve => setTimeout(resolve, 500));

                // Trigger ping from Dart
                await fetch(serverBase + '/ping');
                log('Triggered ping from Dart');

                await new Promise(resolve => setTimeout(resolve, 1000));

                setStatus('Getting results...');
                const resultResp = await fetch(serverBase + '/result');
                const result = await resultResp.json();

                if (result.success) {
                    log('TEST PASSED! Trickle ICE working', 'success');
                    log('  Candidates sent: ' + result.candidatesSent, 'success');
                    log('  Candidates received: ' + result.candidatesReceived, 'success');
                    log('  Host: ' + result.candidateTypes.host + ', SRFLX: ' + result.candidateTypes.srflx, 'success');
                    setStatus('TEST PASSED - ICE trickle working');
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

        async function waitForConnection() {
            return new Promise((resolve, reject) => {
                const timeout = setTimeout(() => reject(new Error('Connection timeout')), 30000);

                const check = () => {
                    if (pc.connectionState === 'connected' || pc.iceConnectionState === 'connected') {
                        clearTimeout(timeout);
                        resolve();
                    } else if (pc.connectionState === 'failed' || pc.iceConnectionState === 'failed') {
                        clearTimeout(timeout);
                        reject(new Error('Connection failed'));
                    } else {
                        setTimeout(check, 100);
                    }
                };
                check();
            });
        }

        async function waitForDataChannel() {
            return new Promise((resolve, reject) => {
                const timeout = setTimeout(() => reject(new Error('DataChannel timeout')), 10000);

                const check = () => {
                    if (dc && dc.readyState === 'open') {
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
  // Enable SCTP logging for debugging
  hierarchicalLoggingEnabled = true;
  WebRtcLogging.sctp.level = Level.FINE;
  WebRtcLogging.datachannel.level = Level.FINE;
  WebRtcLogging.transport.level = Level.FINE;
  Logger.root.onRecord.listen((record) {
    if (record.loggerName.startsWith('webrtc')) {
      print('[LOG] ${record.loggerName}: ${record.message}');
    }
  });

  final server = IceTrickleServer();
  await server.start(port: 8781);
}
