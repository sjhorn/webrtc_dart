// ICE Trickle test variant - PC created in /offer instead of /start
// This tests if timing of PC creation matters

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:webrtc_dart/webrtc_dart.dart';

class IceTrickleLateServer {
  HttpServer? _server;
  RtcPeerConnection? _pc;
  dynamic _dc;
  final List<Map<String, dynamic>> _localCandidates = [];
  Completer<void> _connectionCompleter = Completer();
  Completer<void> _dcOpenCompleter = Completer();
  String _currentBrowser = 'unknown';

  Future<void> start({int port = 8785}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('[Late] Started on http://localhost:$port');

    await for (final request in _server!) {
      _handleRequest(request);
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = 200;
      await request.response.close();
      return;
    }

    final path = request.uri.path;
    print('[Late] ${request.method} $path');

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
        default:
          request.response.statusCode = 404;
          request.response.write('Not found');
      }
    } catch (e, st) {
      print('[Late] Error: $e');
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
    print('[Late] Starting test for: $_currentBrowser');

    await _cleanup();
    _localCandidates.clear();
    _connectionCompleter = Completer();
    _dcOpenCompleter = Completer();

    // NOTE: PC is NOT created here - will be created in /offer
    print('[Late] Reset state, PC will be created in /offer');

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _handleOffer(HttpRequest request) async {
    // Create PC here instead of in /start (like multi_client does)
    _pc = RtcPeerConnection(RtcConfiguration(
      iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
    ));
    print('[Late] PeerConnection created (in /offer)');

    _pc!.onConnectionStateChange.listen((state) {
      print('[Late] Connection state: $state');
      if (state == PeerConnectionState.connected && !_connectionCompleter.isCompleted) {
        _connectionCompleter.complete();
      }
    });

    _pc!.onIceConnectionStateChange.listen((state) {
      print('[Late] ICE state: $state');
    });

    _pc!.onIceCandidate.listen((candidate) {
      print('[Late] Trickled candidate: ${candidate.type} ${candidate.host}:${candidate.port}');
      _localCandidates.add({
        'candidate': 'candidate:${candidate.toSdp()}',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      });
    });

    // Create DataChannel
    _dc = _pc!.createDataChannel('late-test');
    print('[Late] Created DataChannel: late-test');

    _dc!.onStateChange.listen((state) {
      print('[Late] DataChannel state: $state');
      if (state == DataChannelState.open && !_dcOpenCompleter.isCompleted) {
        _dcOpenCompleter.complete();
      }
    });

    _dc!.onMessage.listen((data) {
      final msg = String.fromCharCodes(data);
      print('[Late] Received message: $msg');
    });

    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    print('[Late] Created offer');

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'type': offer.type,
      'sdp': offer.sdp,
    }));
  }

  Future<void> _handleAnswer(HttpRequest request) async {
    if (_pc == null) {
      request.response.statusCode = 400;
      request.response.write('Call /offer first');
      return;
    }

    final body = await utf8.decodeStream(request);
    final data = jsonDecode(body) as Map<String, dynamic>;

    final answer = SessionDescription(
      type: data['type'] as String,
      sdp: data['sdp'] as String,
    );

    print('[Late] Received answer from browser');
    await _pc!.setRemoteDescription(answer);
    print('[Late] Remote description set');

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _handleCandidate(HttpRequest request) async {
    if (_pc == null) {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'status': 'ok'}));
      return;
    }

    final body = await utf8.decodeStream(request);
    final data = jsonDecode(body) as Map<String, dynamic>;

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
      await _pc!.addIceCandidate(candidate);
      print('[Late] Received candidate: ${candidate.type}');
    } catch (e) {
      print('[Late] Failed to add candidate: $e');
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
    print('[Late] Sent ping');

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _handleStatus(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'connectionState': _pc?.connectionState.toString() ?? 'none',
      'dcState': _dc?.state.toString() ?? 'none',
    }));
  }

  Future<void> _handleResult(HttpRequest request) async {
    final success = _pc?.connectionState == PeerConnectionState.connected &&
        _dc?.state == DataChannelState.open;

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'browser': _currentBrowser,
      'success': success,
    }));
  }

  Future<void> _cleanup() async {
    _dc = null;
    await _pc?.close();
    _pc = null;
  }

  // Use the EXACT same HTML as ice_trickle (just change port)
  static const String _testPageHtml = '''
<!DOCTYPE html>
<html>
<head>
    <title>ICE Trickle Late PC Test</title>
    <style>
        body { font-family: monospace; padding: 20px; background: #1a1a1a; color: #eee; }
        #log { background: #0a0a0a; padding: 10px; height: 300px; overflow-y: auto; border: 1px solid #333; }
        .info { color: #8af; }
        .success { color: #8f8; }
        .error { color: #f88; }
        h1 { color: #8af; }
    </style>
</head>
<body>
    <h1>ICE Trickle Late PC Test</h1>
    <p>Tests if creating PC in /offer vs /start matters.</p>
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

        async function runTest() {
            try {
                const browser = detectBrowser();
                log('Browser detected: ' + browser);

                await fetch(serverBase + '/start?browser=' + browser);
                log('Server peer started');

                pc = new RTCPeerConnection({
                    iceServers: [{ urls: 'stun:stun.l.google.com:19302' }]
                });

                pc.onicecandidate = async (e) => {
                    if (e.candidate) {
                        log('Trickled candidate');
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

                pc.onconnectionstatechange = () => {
                    log('Connection state: ' + pc.connectionState,
                        pc.connectionState === 'connected' ? 'success' : 'info');
                };

                pc.ondatachannel = (e) => {
                    dc = e.channel;
                    log('Received DataChannel: ' + dc.label, 'success');

                    dc.onopen = () => {
                        log('DataChannel open!', 'success');
                    };

                    dc.onmessage = (e) => {
                        log('Received message: ' + e.data, 'success');
                        dc.send('pong from browser');
                    };
                };

                const offerResp = await fetch(serverBase + '/offer');
                const offer = await offerResp.json();
                log('Received offer from Dart');

                await pc.setRemoteDescription(new RTCSessionDescription(offer));
                log('Remote description set (offer)');

                const answer = await pc.createAnswer();
                await pc.setLocalDescription(answer);
                log('Local description set (answer)');

                await fetch(serverBase + '/answer', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ type: answer.type, sdp: pc.localDescription.sdp })
                });
                log('Sent answer to Dart');

                // Poll for Dart's candidates
                for (let i = 0; i < 5; i++) {
                    await new Promise(resolve => setTimeout(resolve, 500));
                    const candidatesResp = await fetch(serverBase + '/candidates');
                    const dartCandidates = await candidatesResp.json();
                    for (const c of dartCandidates) {
                        if (!c._added) {
                            try {
                                await pc.addIceCandidate(new RTCIceCandidate(c));
                                c._added = true;
                                log('Added Dart candidate');
                            } catch (e) {}
                        }
                    }
                }

                log('Waiting for connection...');
                await waitForConnection();
                log('Connection established!', 'success');

                log('Waiting for DataChannel...');
                await waitForDataChannel();
                log('DataChannel ready!', 'success');

                // Ping test
                await fetch(serverBase + '/ping');
                log('Triggered ping from Dart');

                await new Promise(resolve => setTimeout(resolve, 1000));

                const resultResp = await fetch(serverBase + '/result');
                const result = await resultResp.json();

                if (result.success) {
                    log('TEST PASSED!', 'success');
                } else {
                    log('TEST FAILED', 'error');
                }

                console.log('TEST_RESULT:' + JSON.stringify(result));
                window.testResult = result;

            } catch (e) {
                log('Error: ' + e.message, 'error');
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
                    } else if (pc.connectionState === 'failed') {
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
  hierarchicalLoggingEnabled = true;
  WebRtcLogging.sctp.level = Level.FINE;
  WebRtcLogging.datachannel.level = Level.FINE;
  WebRtcLogging.transport.level = Level.FINE;
  Logger.root.onRecord.listen((record) {
    if (record.loggerName.startsWith('webrtc')) {
      print('[LOG] ${record.loggerName}: ${record.message}');
    }
  });

  final server = IceTrickleLateServer();
  await server.start(port: 8785);
}
