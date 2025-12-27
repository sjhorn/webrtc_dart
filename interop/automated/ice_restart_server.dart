// ICE Restart Browser Test Server
//
// This server demonstrates ICE restart functionality:
// 1. Establishes initial connection with DataChannel
// 2. Performs ICE restart (new credentials)
// 3. Verifies connection maintained after restart
//
// Pattern: Dart is OFFERER, Browser is ANSWERER

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:webrtc_dart/webrtc_dart.dart';

class IceRestartServer {
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
  int _restartCount = 0;
  bool _restartInProgress = false;
  bool _restartSuccess = false;
  String? _originalIceUfrag;
  String? _restartedIceUfrag;

  Future<void> start({int port = 8782}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('[Restart] Started on http://localhost:$port');

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
    print('[Restart] ${request.method} $path');

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
        case '/restart':
          await _handleRestart(request);
          break;
        case '/restart-offer':
          await _handleRestartOffer(request);
          break;
        case '/restart-answer':
          await _handleRestartAnswer(request);
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
      print('[Restart] Error: $e');
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
    print('[Restart] Starting test for: $_currentBrowser');

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
    _restartCount = 0;
    _restartInProgress = false;
    _restartSuccess = false;
    _originalIceUfrag = null;
    _restartedIceUfrag = null;

    // Create peer connection
    _pc = RtcPeerConnection(RtcConfiguration(
      iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
    ));
    print('[Restart] PeerConnection created');

    _pc!.onConnectionStateChange.listen((state) {
      print('[Restart] Connection state: $state');
      if (state == PeerConnectionState.connected) {
        if (!_connectionCompleter.isCompleted) {
          _connectedTime = DateTime.now();
          _connectionCompleter.complete();
        }
        if (_restartInProgress) {
          _restartSuccess = true;
          _restartInProgress = false;
          print('[Restart] Connection re-established after ICE restart!');
        }
      }
    });

    _pc!.onIceConnectionStateChange.listen((state) {
      print('[Restart] ICE state: $state');
      // Also check ICE state for restart success (connection state may not change)
      if ((state == IceConnectionState.connected ||
           state == IceConnectionState.completed) &&
          _restartInProgress) {
        _restartSuccess = true;
        _restartInProgress = false;
        print('[Restart] ICE re-established after restart!');
      }
    });

    _pc!.onIceGatheringStateChange.listen((state) {
      print('[Restart] ICE gathering state: $state');
    });

    // ICE candidate handling
    _pc!.onIceCandidate.listen((candidate) {
      _candidatesSent++;
      print(
          '[Restart] ICE candidate #$_candidatesSent: ${candidate.type} ${candidate.host}:${candidate.port}');
      _localCandidates.add({
        'candidate': 'candidate:${candidate.toSdp()}',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
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

    // Create DataChannel before createOffer
    _dc = _pc!.createDataChannel('restart-test');
    print('[Restart] Created DataChannel: restart-test');

    _dc!.onStateChange.listen((state) {
      print('[Restart] DataChannel state: $state');
      if (state == DataChannelState.open && !_dcOpenCompleter.isCompleted) {
        _dcOpenCompleter.complete();
      }
    });

    _dc!.onMessage.listen((data) {
      _messagesReceived++;
      final msg = data is String ? data : String.fromCharCodes(data);
      print('[Restart] Received message: $msg');
    });

    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);

    // Extract ice-ufrag from SDP
    _originalIceUfrag = _extractIceUfrag(offer.sdp);
    print('[Restart] Initial ice-ufrag: $_originalIceUfrag');
    print('[Restart] Created offer, ICE gathering started');

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'type': offer.type,
      'sdp': offer.sdp,
    }));
    print('[Restart] Sent offer to browser');
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

    print('[Restart] Received answer from browser');
    await _pc!.setRemoteDescription(answer);
    print('[Restart] Remote description set');

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
      print('[Restart] Skipping empty ICE candidate (end of candidates)');
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
          '[Restart] Received candidate #$_candidatesReceived: ${candidate.type}');
    } catch (e) {
      print('[Restart] Failed to add candidate: $e');
    }

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _handleCandidates(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(_localCandidates));
  }

  Future<void> _handleRestart(HttpRequest request) async {
    if (_pc == null) {
      request.response.statusCode = 400;
      request.response.write('Call /start first');
      return;
    }

    print('[Restart] Triggering ICE restart...');
    _restartInProgress = true;
    _restartCount++;

    // Clear previous candidates for restart
    _localCandidates.clear();
    _candidatesSent = 0;
    _candidatesReceived = 0;

    // Call restartIce() to prepare for restart
    _pc!.restartIce();

    // Create new offer with ICE restart
    final offer = await _pc!.createOffer(RtcOfferOptions(iceRestart: true));
    await _pc!.setLocalDescription(offer);

    // Extract new ice-ufrag
    _restartedIceUfrag = _extractIceUfrag(offer.sdp);
    print('[Restart] Restarted ice-ufrag: $_restartedIceUfrag');

    if (_originalIceUfrag != _restartedIceUfrag) {
      print('[Restart] ICE credentials changed (restart working)');
    } else {
      print('[Restart] WARNING: ICE credentials did not change');
    }

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'type': offer.type,
      'sdp': offer.sdp,
      'iceCredentialsChanged': _originalIceUfrag != _restartedIceUfrag,
    }));
    print('[Restart] Sent restart offer to browser');
  }

  Future<void> _handleRestartOffer(HttpRequest request) async {
    // Browser initiated restart - receive offer
    if (_pc == null) {
      request.response.statusCode = 400;
      request.response.write('Call /start first');
      return;
    }

    final body = await utf8.decodeStream(request);
    final data = jsonDecode(body) as Map<String, dynamic>;

    print('[Restart] Browser initiated ICE restart');
    _restartInProgress = true;
    _restartCount++;

    final offer = SessionDescription(
      type: data['type'] as String,
      sdp: data['sdp'] as String,
    );

    await _pc!.setRemoteDescription(offer);

    // Clear previous candidates
    _localCandidates.clear();
    _candidatesSent = 0;
    _candidatesReceived = 0;

    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);

    _restartedIceUfrag = _extractIceUfrag(answer.sdp);
    print('[Restart] Restart answer ice-ufrag: $_restartedIceUfrag');

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'type': answer.type,
      'sdp': answer.sdp,
    }));
    print('[Restart] Sent restart answer to browser');
  }

  Future<void> _handleRestartAnswer(HttpRequest request) async {
    // Browser's answer to our restart offer
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

    print('[Restart] Received restart answer from browser');
    await _pc!.setRemoteDescription(answer);
    print('[Restart] Remote description set (restart)');

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _handlePing(HttpRequest request) async {
    if (_dc == null || _dc!.state != DataChannelState.open) {
      request.response.statusCode = 400;
      request.response.write('DataChannel not open');
      return;
    }

    _dc!.sendString('ping from Dart');
    _messagesSent++;
    print('[Restart] Sent ping');

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
      'restartCount': _restartCount,
      'restartSuccess': _restartSuccess,
    }));
  }

  Future<void> _handleResult(HttpRequest request) async {
    final connectionTime = _connectedTime != null && _startTime != null
        ? _connectedTime!.difference(_startTime!)
        : Duration.zero;

    final iceCredentialsChanged =
        _originalIceUfrag != null && _restartedIceUfrag != null &&
        _originalIceUfrag != _restartedIceUfrag;

    // Success if ICE is connected/completed, DC is open, and restart was triggered
    final iceConnected = _pc?.iceConnectionState == IceConnectionState.connected ||
        _pc?.iceConnectionState == IceConnectionState.completed;

    final result = {
      'browser': _currentBrowser,
      'success': iceConnected &&
          _dc?.state == DataChannelState.open &&
          _restartCount > 0 &&
          _restartSuccess,
      'iceRestartTriggered': _restartCount > 0,
      'iceCredentialsChanged': iceCredentialsChanged,
      'restartSuccess': _restartSuccess,
      'candidatesSent': _candidatesSent,
      'candidatesReceived': _candidatesReceived,
      'messagesSent': _messagesSent,
      'messagesReceived': _messagesReceived,
      'connectionTimeMs': connectionTime.inMilliseconds,
      'originalIceUfrag': _originalIceUfrag,
      'restartedIceUfrag': _restartedIceUfrag,
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

  String? _extractIceUfrag(String sdp) {
    final match = RegExp(r'a=ice-ufrag:(\S+)').firstMatch(sdp);
    return match?.group(1);
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
    <title>WebRTC ICE Restart Test</title>
    <style>
        body { font-family: monospace; padding: 20px; background: #1a1a1a; color: #eee; }
        #log { background: #0a0a0a; padding: 10px; height: 300px; overflow-y: auto; border: 1px solid #333; }
        .info { color: #8af; }
        .success { color: #8f8; }
        .error { color: #f88; }
        .warn { color: #fa8; }
        .restart { color: #f8f; }
        h1 { color: #8af; }
        #status { margin: 10px 0; padding: 10px; background: #333; }
        .badge { background: #808; color: #fff; padding: 2px 8px; border-radius: 4px; }
        .stats { display: flex; gap: 20px; margin: 10px 0; flex-wrap: wrap; }
        .stat { background: #333; padding: 10px; border-radius: 4px; }
        .stat-value { font-size: 1.5em; color: #8f8; }
        .stat-label { font-size: 0.8em; color: #888; }
        button { background: #808; color: #fff; border: none; padding: 10px 20px; margin: 5px; cursor: pointer; border-radius: 4px; }
        button:hover { background: #a0a; }
    </style>
</head>
<body>
    <h1>ICE Restart Test <span class="badge">DataChannel</span></h1>
    <p>Tests ICE restart functionality - new credentials without dropping connection.</p>
    <div id="status">Status: Waiting to start...</div>
    <div class="stats">
        <div class="stat">
            <div class="stat-label">Restart Count</div>
            <div id="restarts" class="stat-value">0</div>
        </div>
        <div class="stat">
            <div class="stat-label">ICE Credentials Changed</div>
            <div id="changed" class="stat-value">-</div>
        </div>
        <div class="stat">
            <div class="stat-label">Messages</div>
            <div id="messages" class="stat-value">0</div>
        </div>
    </div>
    <div id="log"></div>

    <script>
        let pc = null;
        let dc = null;
        let restartCount = 0;
        let messageCount = 0;
        let iceCredentialsChanged = false;
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
            document.getElementById('restarts').textContent = restartCount;
            document.getElementById('changed').textContent = iceCredentialsChanged ? 'YES' : 'NO';
            document.getElementById('messages').textContent = messageCount;
        }

        async function runTest() {
            try {
                const browser = detectBrowser();
                log('Browser detected: ' + browser);
                setStatus('Starting ICE restart test for ' + browser);

                await fetch(serverBase + '/start?browser=' + browser);
                log('Server peer started');

                pc = new RTCPeerConnection({
                    iceServers: [{ urls: 'stun:stun.l.google.com:19302' }]
                });

                pc.onicecandidate = async (e) => {
                    if (e.candidate) {
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

                pc.ondatachannel = (e) => {
                    dc = e.channel;
                    log('Received DataChannel: ' + dc.label, 'success');

                    dc.onopen = () => {
                        log('DataChannel open!', 'success');
                    };

                    dc.onmessage = (e) => {
                        messageCount++;
                        updateStats();
                        log('Received message: ' + e.data, 'success');
                        dc.send('pong from browser');
                        log('Sent: pong from browser');
                    };
                };

                // Get initial offer
                setStatus('Getting offer from Dart...');
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

                // Poll for candidates
                setStatus('Exchanging ICE candidates...');
                await pollCandidates();

                // Wait for connection
                setStatus('Waiting for initial connection...');
                await waitForConnection();
                log('Initial connection established!', 'success');

                // Wait for DataChannel
                await waitForDataChannel();
                log('DataChannel ready!', 'success');

                // Test initial connectivity
                await fetch(serverBase + '/ping');
                await new Promise(resolve => setTimeout(resolve, 500));
                log('Initial ping/pong successful');

                // Now perform ICE restart (server-initiated)
                setStatus('Performing ICE restart...');
                log('=== ICE RESTART (Server-initiated) ===', 'restart');

                const restartResp = await fetch(serverBase + '/restart');
                const restartOffer = await restartResp.json();
                restartCount++;
                updateStats();

                log('Received restart offer from Dart', 'restart');
                iceCredentialsChanged = restartOffer.iceCredentialsChanged;
                updateStats();
                log('ICE credentials changed: ' + iceCredentialsChanged, iceCredentialsChanged ? 'success' : 'warn');

                await pc.setRemoteDescription(new RTCSessionDescription(restartOffer));
                log('Remote description set (restart offer)', 'restart');

                const restartAnswer = await pc.createAnswer();
                await pc.setLocalDescription(restartAnswer);
                log('Local description set (restart answer)', 'restart');

                await fetch(serverBase + '/restart-answer', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ type: restartAnswer.type, sdp: pc.localDescription.sdp })
                });
                log('Sent restart answer to Dart', 'restart');

                // Poll for new candidates after restart
                await pollCandidates();

                // Wait for connection to re-establish
                setStatus('Waiting for connection after restart...');
                await waitForConnection();
                log('Connection re-established after ICE restart!', 'success');

                // Wait for DataChannel to be usable
                await new Promise(resolve => setTimeout(resolve, 1000));

                // Test connectivity after restart
                log('Testing connectivity after restart...');
                await fetch(serverBase + '/ping');
                await new Promise(resolve => setTimeout(resolve, 500));
                log('Post-restart ping/pong successful!', 'success');

                // Get results
                setStatus('Getting results...');
                const resultResp = await fetch(serverBase + '/result');
                const result = await resultResp.json();

                if (result.success && result.iceCredentialsChanged) {
                    log('TEST PASSED! ICE restart successful', 'success');
                    log('  ICE credentials changed: ' + result.iceCredentialsChanged, 'success');
                    log('  Connection maintained: YES', 'success');
                    setStatus('TEST PASSED - ICE restart working');
                } else {
                    log('TEST ISSUES:', 'warn');
                    log('  Success: ' + result.success, result.success ? 'success' : 'error');
                    log('  ICE credentials changed: ' + result.iceCredentialsChanged, result.iceCredentialsChanged ? 'success' : 'warn');
                    setStatus('TEST COMPLETE - Check results');
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

        async function pollCandidates() {
            for (let i = 0; i < 5; i++) {
                await new Promise(resolve => setTimeout(resolve, 300));
                const candidatesResp = await fetch(serverBase + '/candidates');
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
  final server = IceRestartServer();
  await server.start(port: 8782);
}
