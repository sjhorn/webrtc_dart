// RTCDataChannel Answer Server for Automated Browser Testing
//
// This server tests Dart as the ANSWERER (browser is offerer):
// 1. Serves static HTML for browser to create offer
// 2. Browser creates PeerConnection + RTCDataChannel, sends offer
// 3. Dart creates answer and sends it back
// 4. RTCDataChannel opens and they exchange ping/pong messages
//
// Pattern: Browser is OFFERER, Dart is ANSWERER
// This is the opposite of most tests and may work better with Firefox

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:webrtc_dart/webrtc_dart.dart';

class DataChannelAnswerServer {
  HttpServer? _server;
  RTCPeerConnection? _pc;
  RTCDataChannel? _dc;
  final List<Map<String, dynamic>> _localCandidates = [];
  Completer<void> _connectionCompleter = Completer();
  DateTime? _startTime;
  DateTime? _connectedTime;
  String _currentBrowser = 'unknown';
  int _messagesReceived = 0;
  int _messagesSent = 0;
  bool _dcOpened = false;
  final List<String> _receivedMessages = [];

  Future<void> start({int port = 8775}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('[DC-Answer] Started on http://localhost:$port');

    await for (final request in _server!) {
      _handleRequest(request);
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    // Enable CORS
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
    print('[DC-Answer] ${request.method} $path');

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
        case '/candidate':
          await _handleCandidate(request);
          break;
        case '/candidates':
          await _handleCandidates(request);
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
      print('[DC-Answer] Error: $e');
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
    print('[DC-Answer] Starting RTCDataChannel answer test for: $_currentBrowser');

    // Reset state
    await _cleanup();
    _localCandidates.clear();
    _startTime = DateTime.now();
    _connectedTime = null;
    _connectionCompleter = Completer();
    _messagesReceived = 0;
    _messagesSent = 0;
    _dcOpened = false;
    _receivedMessages.clear();

    // Create peer connection (will wait for offer)
    _pc = RTCPeerConnection(RtcConfiguration(
      iceServers: [
        IceServer(urls: ['stun:stun.l.google.com:19302'])
      ],
    ));
    print('[DC-Answer] PeerConnection created (waiting for offer)');

    // Track connection state
    _pc!.onConnectionStateChange.listen((state) {
      print('[DC-Answer] Connection state: $state');
      if (state == PeerConnectionState.connected &&
          !_connectionCompleter.isCompleted) {
        _connectedTime = DateTime.now();
        _connectionCompleter.complete();
      }
    });

    _pc!.onIceConnectionStateChange.listen((state) {
      print('[DC-Answer] ICE state: $state');
    });

    // Track ICE candidates
    _pc!.onIceCandidate.listen((candidate) {
      print(
          '[DC-Answer] Local ICE candidate: ${candidate.type} ${candidate.host}:${candidate.port}');
      _localCandidates.add({
        'candidate': 'candidate:${candidate.toSdp()}',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      });
    });

    // Handle incoming datachannel (created by browser)
    _pc!.onDataChannel.listen((channel) {
      print('[DC-Answer] Received RTCDataChannel: ${channel.label}');
      _dc = channel;

      // Check if already open
      if (channel.state == DataChannelState.open) {
        _dcOpened = true;
        print('[DC-Answer] RTCDataChannel already open!');
      }

      channel.onStateChange.listen((state) {
        print('[DC-Answer] RTCDataChannel state: $state');
        if (state == DataChannelState.open) {
          _dcOpened = true;
          print('[DC-Answer] RTCDataChannel opened!');
        }
      });

      channel.onMessage.listen((message) {
        _messagesReceived++;
        final text =
            message is String ? message : 'binary(${(message as List).length})';
        _receivedMessages.add(text);
        print('[DC-Answer] Received: $text');

        // Reply to pings with pongs
        if (text.startsWith('ping')) {
          final reply = 'pong ${_messagesSent + 1}';
          channel.sendString(reply);
          _messagesSent++;
          print('[DC-Answer] Sent: $reply');
        }
      });
    });

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _handleOffer(HttpRequest request) async {
    if (_pc == null) {
      request.response.statusCode = 400;
      request.response.write('Call /start first');
      return;
    }

    final body = await utf8.decodeStream(request);
    final data = jsonDecode(body) as Map<String, dynamic>;

    final offer = RTCSessionDescription(
      type: data['type'] as String,
      sdp: data['sdp'] as String,
    );

    print('[DC-Answer] Received offer from browser');
    await _pc!.setRemoteDescription(offer);
    print('[DC-Answer] Remote description set');

    // Create answer
    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    print('[DC-Answer] Created answer, local description set');

    // Wait briefly for ICE gathering
    await Future.delayed(Duration(milliseconds: 500));

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'type': answer.type,
      'sdp': answer.sdp,
    }));
    print('[DC-Answer] Sent answer to browser');
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

    // Skip empty candidates
    if (candidateStr.isEmpty || candidateStr.trim().isEmpty) {
      print('[DC-Answer] Skipping empty ICE candidate');
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'status': 'ok'}));
      return;
    }

    if (candidateStr.startsWith('candidate:')) {
      candidateStr = candidateStr.substring('candidate:'.length);
    }

    try {
      final candidate = RTCIceCandidate.fromSdp(candidateStr);
      await _pc!.addIceCandidate(candidate);
      print('[DC-Answer] Added ICE candidate: ${candidate.type}');
    } catch (e) {
      print('[DC-Answer] Failed to add candidate: $e');
    }

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _handleCandidates(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(_localCandidates));
  }

  Future<void> _handleStatus(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'connectionState': _pc?.connectionState.toString() ?? 'none',
      'iceConnectionState': _pc?.iceConnectionState.toString() ?? 'none',
      'dcOpened': _dcOpened,
      'messagesReceived': _messagesReceived,
      'messagesSent': _messagesSent,
      'receivedMessages': _receivedMessages,
    }));
  }

  Future<void> _handleResult(HttpRequest request) async {
    final connectionTime = _connectedTime != null && _startTime != null
        ? _connectedTime!.difference(_startTime!)
        : Duration.zero;

    final result = {
      'browser': _currentBrowser,
      'success': _pc?.connectionState == PeerConnectionState.connected &&
          _dcOpened &&
          _messagesReceived > 0 &&
          _messagesSent > 0,
      'dcOpened': _dcOpened,
      'messagesReceived': _messagesReceived,
      'messagesSent': _messagesSent,
      'connectionTimeMs': connectionTime.inMilliseconds,
      'pattern': 'Browser=Offerer, Dart=Answerer',
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
    await _dc?.close();
    _dc = null;
    await _pc?.close();
    _pc = null;
  }

  static const String _testPageHtml = '''
<!DOCTYPE html>
<html>
<head>
    <title>WebRTC RTCDataChannel Answer Test</title>
    <style>
        body { font-family: monospace; padding: 20px; background: #1a1a1a; color: #eee; }
        #log { background: #0a0a0a; padding: 10px; height: 300px; overflow-y: auto; border: 1px solid #333; }
        .info { color: #8af; }
        .success { color: #8f8; }
        .error { color: #f88; }
        h1 { color: #8af; }
        #status { margin: 10px 0; padding: 10px; background: #333; }
        .pattern-badge { background: #f80; color: #fff; padding: 2px 8px; border-radius: 4px; }
    </style>
</head>
<body>
    <h1>WebRTC RTCDataChannel Test <span class="pattern-badge">Browser=Offerer</span></h1>
    <p>Browser creates offer with RTCDataChannel, Dart creates answer.</p>
    <p>This tests the Dart-as-Answerer pattern (opposite of most tests).</p>
    <div id="status">Status: Waiting to start...</div>
    <div id="log"></div>

    <script>
        let pc = null;
        let dc = null;
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

        async function runTest() {
            try {
                const browser = detectBrowser();
                log('Browser detected: ' + browser);
                setStatus('Starting RTCDataChannel answer test for ' + browser);

                // Start server-side peer
                await fetch(serverBase + '/start?browser=' + browser);
                log('Server peer started (Dart as Answerer)');

                // Create browser peer connection (we are the offerer!)
                pc = new RTCPeerConnection({
                    iceServers: [{ urls: 'stun:stun.l.google.com:19302' }]
                });

                // Create RTCDataChannel BEFORE creating offer
                dc = pc.createDataChannel('test-channel');
                log('Created RTCDataChannel: test-channel');

                dc.onopen = () => {
                    log('RTCDataChannel opened!', 'success');
                    // Send some ping messages
                    for (let i = 1; i <= 3; i++) {
                        setTimeout(() => {
                            if (dc.readyState === 'open') {
                                dc.send('ping ' + i);
                                log('Sent: ping ' + i);
                            }
                        }, i * 500);
                    }
                };

                dc.onmessage = (e) => {
                    log('Received: ' + e.data, 'success');
                };

                dc.onerror = (e) => {
                    log('RTCDataChannel error: ' + e, 'error');
                };

                // Set up ICE candidate handler
                pc.onicecandidate = async (e) => {
                    if (e.candidate) {
                        log('Sending ICE candidate to Dart');
                        await fetch(serverBase + '/candidate', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify({
                                candidate: e.candidate.candidate,
                                sdpMid: e.candidate.sdpMid,
                                sdpMLineIndex: e.candidate.sdpMLineIndex
                            })
                        });
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

                // Create offer (browser is offerer!)
                setStatus('Creating offer...');
                const offer = await pc.createOffer();
                await pc.setLocalDescription(offer);
                log('Created offer, local description set');

                // Wait for ICE gathering
                await new Promise(resolve => setTimeout(resolve, 500));

                // Send offer to Dart and get answer
                setStatus('Sending offer to Dart, getting answer...');
                const answerResp = await fetch(serverBase + '/offer', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ type: offer.type, sdp: pc.localDescription.sdp })
                });
                const answer = await answerResp.json();
                log('Received answer from Dart');

                // Set remote description (answer)
                await pc.setRemoteDescription(new RTCSessionDescription(answer));
                log('Remote description set (answer)');

                // Get Dart's ICE candidates
                setStatus('Exchanging ICE candidates...');
                await new Promise(resolve => setTimeout(resolve, 500));

                const candidatesResp = await fetch(serverBase + '/candidates');
                const dartCandidates = await candidatesResp.json();
                log('Received ' + dartCandidates.length + ' ICE candidates from Dart');

                for (const c of dartCandidates) {
                    try {
                        await pc.addIceCandidate(new RTCIceCandidate(c));
                        log('Added Dart ICE candidate');
                    } catch (e) {
                        log('Failed to add candidate: ' + e.message, 'error');
                    }
                }

                // Wait for connection and messages
                setStatus('Waiting for connection and messages...');
                await waitForConnection();
                log('Connection established!', 'success');

                // Wait for message exchange
                await new Promise(resolve => setTimeout(resolve, 3000));

                // Get results
                setStatus('Getting results...');
                const resultResp = await fetch(serverBase + '/result');
                const result = await resultResp.json();

                if (result.success) {
                    log('TEST PASSED! Sent=' + result.messagesSent +
                        ', Received=' + result.messagesReceived, 'success');
                    setStatus('TEST PASSED - RTCDataChannel ping/pong works (Dart as Answerer)');
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

        // Auto-start test
        window.addEventListener('load', () => {
            setTimeout(runTest, 500);
        });
    </script>
</body>
</html>
''';
}

void main() async {
  final server = DataChannelAnswerServer();
  await server.start(port: 8775);
}
