// Dart Signaling Server for Automated Browser Testing
//
// This server:
// 1. Serves static files (HTML/JS) for browser
// 2. Creates a PeerConnection and generates an offer
// 3. Exchanges SDP via HTTP endpoints
// 4. Tests DataChannel communication

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:webrtc_dart/webrtc_dart.dart';

class TestResult {
  final String browser;
  final bool success;
  final int messagesSent;
  final int messagesReceived;
  final List<String> receivedMessages;
  final String? error;
  final Duration connectionTime;

  TestResult({
    required this.browser,
    required this.success,
    required this.messagesSent,
    required this.messagesReceived,
    required this.receivedMessages,
    this.error,
    required this.connectionTime,
  });

  Map<String, dynamic> toJson() => {
        'browser': browser,
        'success': success,
        'messagesSent': messagesSent,
        'messagesReceived': messagesReceived,
        'receivedMessages': receivedMessages,
        'error': error,
        'connectionTimeMs': connectionTime.inMilliseconds,
      };
}

class DartSignalingServer {
  HttpServer? _server;
  RtcPeerConnection? _pc;
  dynamic _channel; // Can be DataChannel or ProxyDataChannel
  final List<String> _receivedMessages = [];
  final List<Map<String, dynamic>> _localCandidates = [];
  int _messagesSent = 0;
  Completer<void> _connectionCompleter = Completer();
  Completer<void> _testCompleter = Completer();
  DateTime? _startTime;
  DateTime? _connectedTime;
  String _currentBrowser = 'unknown';

  Future<void> start({int port = 8765}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('[Server] Started on http://localhost:$port');

    await for (final request in _server!) {
      _handleRequest(request);
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    // Enable CORS
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = 200;
      await request.response.close();
      return;
    }

    final path = request.uri.path;
    print('[Server] ${request.method} $path');

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
        case '/message':
          await _handleMessage(request);
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
      print('[Server] Error: $e');
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
    // Read browser info from query params
    _currentBrowser = request.uri.queryParameters['browser'] ?? 'unknown';
    print('[Server] Starting test for browser: $_currentBrowser');

    // Reset state
    _receivedMessages.clear();
    _localCandidates.clear();
    _messagesSent = 0;
    _startTime = DateTime.now();
    _connectedTime = null;
    _connectionCompleter = Completer();
    _testCompleter = Completer();

    // Create peer connection
    _pc = RtcPeerConnection();
    print('[Server] PeerConnection created');

    // Wait for initialization
    await Future.delayed(Duration(milliseconds: 100));

    // Track connection state
    _pc!.onConnectionStateChange.listen((state) {
      print('[Server] Connection state: $state');
      if (state == PeerConnectionState.connected && !_connectionCompleter.isCompleted) {
        _connectedTime = DateTime.now();
        _connectionCompleter.complete();
      }
    });

    _pc!.onIceConnectionStateChange.listen((state) {
      print('[Server] ICE connection state: $state');
    });

    // Track ICE candidates from Dart side
    _pc!.onIceCandidate.listen((candidate) {
      print('[Server] Local ICE candidate: ${candidate.type} ${candidate.host}:${candidate.port}');
      _localCandidates.add({
        'candidate': 'candidate:${candidate.toSdp()}',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      });
    });

    // Dart is the ANSWERER - Browser creates DataChannel
    // Listen for incoming DataChannel from browser
    _pc!.onDataChannel.listen((channel) {
      print('[Server] Received DataChannel: ${channel.label}');
      _channel = channel;
      _setupChannel(channel);
    });

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  void _setupChannel(dynamic channel) {
    channel.onStateChange.listen((state) {
      print('[Server] DataChannel state: $state');
      if (state == DataChannelState.open) {
        print('[Server] DataChannel OPEN!');
        // Send greeting
        _sendMessage('Hello from Dart!');
      }
    });

    channel.onMessage.listen((message) {
      final text = message is String ? message : utf8.decode(message as List<int>);
      print('[Server] Received: $text');
      _receivedMessages.add(text);

      // Check if test is complete
      if (_receivedMessages.length >= 3) {
        if (!_testCompleter.isCompleted) {
          _testCompleter.complete();
        }
      }
    });
  }

  void _sendMessage(String message) {
    if (_channel != null && _channel.state == DataChannelState.open) {
      _channel.sendString(message);
      _messagesSent++;
      print('[Server] Sent: $message');
    }
  }

  Future<void> _handleOffer(HttpRequest request) async {
    // Browser sends offer (POST), Dart receives it
    if (_pc == null) {
      request.response.statusCode = 400;
      request.response.write('Call /start first');
      return;
    }

    final body = await utf8.decodeStream(request);
    final data = jsonDecode(body) as Map<String, dynamic>;

    final offer = SessionDescription(
      type: data['type'] as String,
      sdp: data['sdp'] as String,
    );

    print('[Server] Received offer from browser');
    await _pc!.setRemoteDescription(offer);
    print('[Server] Remote description set');

    // Create answer
    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    print('[Server] Local description set (answer)');

    // Wait briefly for ICE gathering
    await Future.delayed(Duration(milliseconds: 500));

    // Return the answer
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'type': answer.type,
      'sdp': answer.sdp,
    }));
    print('[Server] Sent answer to browser');
  }

  // Note: _handleAnswer is no longer needed in this flow, but keep for compatibility
  Future<void> _handleAnswer(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'not needed - browser is offerer'}));
  }

  Future<void> _handleCandidate(HttpRequest request) async {
    if (_pc == null) {
      request.response.statusCode = 400;
      request.response.write('Call /start first');
      return;
    }

    final body = await utf8.decodeStream(request);
    final data = jsonDecode(body) as Map<String, dynamic>;

    // Parse ICE candidate
    String candidateStr = data['candidate'] as String;
    if (candidateStr.startsWith('candidate:')) {
      candidateStr = candidateStr.substring('candidate:'.length);
    }

    try {
      final candidate = Candidate.fromSdp(candidateStr);
      await _pc!.addIceCandidate(candidate);
      print('[Server] Added ICE candidate: ${candidate.type}');
    } catch (e) {
      print('[Server] Failed to add candidate: $e');
    }

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _handleCandidates(HttpRequest request) async {
    // Return Dart's local ICE candidates for the browser to add
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(_localCandidates));
  }

  Future<void> _handleMessage(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    final data = jsonDecode(body) as Map<String, dynamic>;
    final message = data['message'] as String;

    // Send message to browser
    _sendMessage(message);

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _handleStatus(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'connectionState': _pc?.connectionState.toString() ?? 'none',
      'iceConnectionState': _pc?.iceConnectionState.toString() ?? 'none',
      'channelState': _channel?.state.toString() ?? 'none',
      'messagesSent': _messagesSent,
      'messagesReceived': _receivedMessages.length,
    }));
  }

  Future<void> _handleResult(HttpRequest request) async {
    final connectionTime = _connectedTime != null && _startTime != null
        ? _connectedTime!.difference(_startTime!)
        : Duration.zero;

    final result = TestResult(
      browser: _currentBrowser,
      success: _receivedMessages.isNotEmpty &&
               (_pc?.connectionState == PeerConnectionState.connected ||
                _pc?.iceConnectionState == IceConnectionState.connected),
      messagesSent: _messagesSent,
      messagesReceived: _receivedMessages.length,
      receivedMessages: _receivedMessages,
      connectionTime: connectionTime,
    );

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(result.toJson()));
  }

  Future<void> _handleShutdown(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'shutting down'}));

    // Close connection and server
    await _pc?.close();
    _pc = null;
    _channel = null;

    // Schedule server shutdown
    Future.delayed(Duration(milliseconds: 100), () {
      _server?.close();
    });
  }

  static const String _testPageHtml = '''
<!DOCTYPE html>
<html>
<head>
    <title>WebRTC Browser Interop Test</title>
    <style>
        body { font-family: monospace; padding: 20px; background: #1a1a1a; color: #eee; }
        #log { background: #0a0a0a; padding: 10px; height: 300px; overflow-y: auto; border: 1px solid #333; }
        .info { color: #8af; }
        .success { color: #8f8; }
        .error { color: #f88; }
        .send { color: #ff8; }
        .receive { color: #f8f; }
        h1 { color: #8af; }
        #status { margin: 10px 0; padding: 10px; background: #333; }
    </style>
</head>
<body>
    <h1>WebRTC Automated Browser Test</h1>
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
                // Detect browser
                const browser = detectBrowser();
                log('Browser detected: ' + browser);
                setStatus('Starting test for ' + browser);

                // Start server-side peer
                await fetch(serverBase + '/start?browser=' + browser);
                log('Server peer started');

                // Create browser peer connection (Browser is the OFFERER)
                pc = new RTCPeerConnection({ iceServers: [] });

                pc.oniceconnectionstatechange = () => {
                    log('ICE state: ' + pc.iceConnectionState,
                        pc.iceConnectionState === 'connected' ? 'success' : 'info');
                };

                pc.onconnectionstatechange = () => {
                    log('Connection state: ' + pc.connectionState,
                        pc.connectionState === 'connected' ? 'success' : 'info');
                };

                // Browser is the OFFERER, so create DataChannel
                dc = pc.createDataChannel('test');
                log('Created DataChannel: ' + dc.label);

                dc.onopen = () => {
                    log('DataChannel OPEN!', 'success');
                    setStatus('Connected! Exchanging messages...');
                    // Send test messages
                    for (let i = 1; i <= 3; i++) {
                        const msg = 'Browser message ' + i;
                        dc.send(msg);
                        log('Sent: ' + msg, 'send');
                    }
                };

                dc.onmessage = (e) => {
                    log('Received: ' + e.data, 'receive');
                };

                dc.onerror = (e) => {
                    log('DataChannel error: ' + e.error, 'error');
                };

                // Create offer
                setStatus('Creating offer...');
                const offer = await pc.createOffer();
                await pc.setLocalDescription(offer);
                log('Local description set (offer)');

                // Wait for ICE gathering
                await new Promise(resolve => setTimeout(resolve, 500));

                // Send offer to Dart and get answer back
                setStatus('Sending offer to Dart...');
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

                // Send ICE candidates to Dart
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

                // Fetch Dart's ICE candidates and add them
                setStatus('Exchanging ICE candidates...');
                await new Promise(resolve => setTimeout(resolve, 500)); // Wait for Dart to gather

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

                setStatus('Waiting for connection...');

                // Wait for connection
                await waitForConnection();

                // Wait for DTLS/SCTP/DataChannel setup and message exchange
                log('Waiting for DataChannel to open...');
                await waitForDataChannel();
                log('DataChannel is open!', 'success');

                // Give time for message exchange
                await new Promise(resolve => setTimeout(resolve, 3000));

                // Get results
                const resultResp = await fetch(serverBase + '/result');
                const result = await resultResp.json();

                if (result.success) {
                    log('TEST PASSED!', 'success');
                    setStatus('TEST PASSED - ' + result.messagesReceived + ' messages received');
                } else {
                    log('TEST FAILED', 'error');
                    setStatus('TEST FAILED');
                }

                // Report to console for Playwright
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
                const timeout = setTimeout(() => reject(new Error('DataChannel timeout')), 30000);

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
  final server = DartSignalingServer();
  await server.start(port: 8765);
}
