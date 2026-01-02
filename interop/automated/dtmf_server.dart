// DTMF (Dual-Tone Multi-Frequency) Test Server
//
// This server tests RTCDTMFSender functionality:
// 1. Browser creates audio track and sends offer
// 2. Dart answers with audio and gets RTCRtpSender with DTMF support
// 3. Dart inserts DTMF tones and reports ontonechange events
// 4. Browser verifies DTMF tones were sent via server status
//
// Pattern: Browser sends audio, Dart sends DTMF tones back

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:webrtc_dart/webrtc_dart.dart';

class DtmfServer {
  HttpServer? _server;
  RTCPeerConnection? _pc;
  RTCRtpSender? _audioSender;
  RTCDTMFSender? _dtmfSender;
  final List<Map<String, dynamic>> _localCandidates = [];
  Completer<void> _connectionCompleter = Completer();
  DateTime? _startTime;
  DateTime? _connectedTime;
  String _currentBrowser = 'unknown';

  // DTMF tracking
  final List<String> _sentTones = [];
  final List<String> _toneChangeEvents = [];
  bool _dtmfSupported = false;
  String _requestedTones = '';

  Future<void> start({int port = 8776}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('[DTMF] Server started on http://localhost:$port');

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
    print('[DTMF] ${request.method} $path');

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
        case '/send-dtmf':
          await _handleSendDtmf(request);
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
      print('[DTMF] Error: $e');
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
    print('[DTMF] Starting DTMF test for: $_currentBrowser');

    // Reset state
    await _cleanup();
    _localCandidates.clear();
    _startTime = DateTime.now();
    _connectedTime = null;
    _connectionCompleter = Completer();
    _sentTones.clear();
    _toneChangeEvents.clear();
    _dtmfSupported = false;
    _requestedTones = '';

    // Create peer connection
    _pc = RTCPeerConnection(RtcConfiguration(
      iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
    ));
    print('[DTMF] PeerConnection created');

    // Track connection state
    _pc!.onConnectionStateChange.listen((state) {
      print('[DTMF] Connection state: $state');
      if (state == PeerConnectionState.connected &&
          !_connectionCompleter.isCompleted) {
        _connectedTime = DateTime.now();
        _connectionCompleter.complete();
      }
    });

    _pc!.onIceConnectionStateChange.listen((state) {
      print('[DTMF] ICE state: $state');
    });

    // Track ICE candidates
    _pc!.onIceCandidate.listen((candidate) {
      print('[DTMF] Local ICE candidate: ${candidate.type} ${candidate.address}:${candidate.port}');
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

    final body = await utf8.decodeStream(request);
    final data = jsonDecode(body) as Map<String, dynamic>;

    final offer = RTCSessionDescription(
      type: data['type'] as String,
      sdp: data['sdp'] as String,
    );

    print('[DTMF] Received offer from browser');
    await _pc!.setRemoteDescription(offer);
    print('[DTMF] Remote description set');

    // Add audio track for sending DTMF
    final audioTrack = AudioStreamTrack(
      id: 'dtmf-audio',
      label: 'DTMF Audio Track',
    );
    _audioSender = _pc!.addTrack(audioTrack);
    print('[DTMF] Added audio track for DTMF');

    // Create answer
    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    print('[DTMF] Created answer, local description set');

    // Check if DTMF is supported
    if (_audioSender != null && _audioSender!.dtmf != null) {
      _dtmfSupported = true;
      _dtmfSender = _audioSender!.dtmf;
      print('[DTMF] DTMF sender available: canInsertDTMF=${_dtmfSender!.canInsertDTMF}');

      // Set up ontonechange listener
      _dtmfSender!.ontonechange = (event) {
        print('[DTMF] Tone change event: "${event.tone}"');
        _toneChangeEvents.add(event.tone);
        if (event.tone.isNotEmpty) {
          _sentTones.add(event.tone);
        }
      };
    } else {
      print('[DTMF] DTMF not supported on this sender');
    }

    // Wait briefly for ICE gathering
    await Future.delayed(Duration(milliseconds: 500));

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'type': answer.type,
      'sdp': answer.sdp,
      'dtmfSupported': _dtmfSupported,
    }));
    print('[DTMF] Sent answer to browser');
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
      print('[DTMF] Skipping empty ICE candidate');
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
      print('[DTMF] Added ICE candidate: ${candidate.type}');
    } catch (e) {
      print('[DTMF] Failed to add candidate: $e');
    }

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _handleCandidates(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(_localCandidates));
  }

  Future<void> _handleSendDtmf(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    final data = jsonDecode(body) as Map<String, dynamic>;
    final tones = data['tones'] as String? ?? '123';
    final duration = data['duration'] as int? ?? 100;
    final gap = data['gap'] as int? ?? 70;

    _requestedTones = tones;

    if (_dtmfSender == null || !_dtmfSender!.canInsertDTMF) {
      print('[DTMF] Cannot insert DTMF - sender not available or stopped');
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'status': 'error',
        'error': 'DTMF sender not available',
      }));
      return;
    }

    print('[DTMF] Inserting DTMF tones: "$tones" (duration=$duration, gap=$gap)');
    try {
      _dtmfSender!.insertDTMF(tones, duration: duration, interToneGap: gap);
      print('[DTMF] DTMF tones queued, toneBuffer: "${_dtmfSender!.toneBuffer}"');

      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'status': 'ok',
        'tones': tones,
        'toneBuffer': _dtmfSender!.toneBuffer,
      }));
    } catch (e) {
      print('[DTMF] Error inserting DTMF: $e');
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'status': 'error',
        'error': e.toString(),
      }));
    }
  }

  Future<void> _handleStatus(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'connectionState': _pc?.connectionState.toString() ?? 'none',
      'iceConnectionState': _pc?.iceConnectionState.toString() ?? 'none',
      'dtmfSupported': _dtmfSupported,
      'canInsertDTMF': _dtmfSender?.canInsertDTMF ?? false,
      'toneBuffer': _dtmfSender?.toneBuffer ?? '',
      'sentTones': _sentTones,
      'toneChangeEvents': _toneChangeEvents,
      'requestedTones': _requestedTones,
    }));
  }

  Future<void> _handleResult(HttpRequest request) async {
    final connectionTime = _connectedTime != null && _startTime != null
        ? _connectedTime!.difference(_startTime!)
        : Duration.zero;

    // Wait a bit for all tone events to complete
    await Future.delayed(Duration(milliseconds: 500));

    // Check if all requested tones were sent
    final allTonesSent = _requestedTones.isNotEmpty &&
        _sentTones.join('') == _requestedTones.toUpperCase();

    final result = {
      'browser': _currentBrowser,
      'success': _pc?.connectionState == PeerConnectionState.connected &&
          _dtmfSupported &&
          allTonesSent,
      'dtmfSupported': _dtmfSupported,
      'requestedTones': _requestedTones,
      'sentTones': _sentTones.join(''),
      'toneChangeEvents': _toneChangeEvents,
      'connectionTimeMs': connectionTime.inMilliseconds,
      'pattern': 'Browser sends audio, Dart sends DTMF',
    };

    print('[DTMF] Test result: success=${result['success']}, '
        'sent="${result['sentTones']}", requested="$_requestedTones"');

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
    _dtmfSender?.dispose();
    _dtmfSender = null;
    _audioSender?.stop();
    _audioSender = null;
    await _pc?.close();
    _pc = null;
  }

  static const String _testPageHtml = '''
<!DOCTYPE html>
<html>
<head>
    <title>WebRTC DTMF Test</title>
    <style>
        body { font-family: monospace; padding: 20px; background: #1a1a1a; color: #eee; }
        #log { background: #0a0a0a; padding: 10px; height: 300px; overflow-y: auto; border: 1px solid #333; }
        .info { color: #8af; }
        .success { color: #8f8; }
        .error { color: #f88; }
        .dtmf { color: #ff0; font-weight: bold; }
        h1 { color: #8af; }
        #status { margin: 10px 0; padding: 10px; background: #333; }
        .pattern-badge { background: #f80; color: #fff; padding: 2px 8px; border-radius: 4px; }
    </style>
</head>
<body>
    <h1>WebRTC DTMF Test <span class="pattern-badge">RTCDTMFSender</span></h1>
    <p>Tests RTCDTMFSender functionality (RFC 4733 telephone-event).</p>
    <p>Browser sends audio offer, Dart answers and sends DTMF tones.</p>
    <div id="status">Status: Waiting to start...</div>
    <div id="log"></div>

    <script>
        let pc = null;
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
                setStatus('Starting DTMF test for ' + browser);

                // Start server-side peer
                await fetch(serverBase + '/start?browser=' + browser);
                log('Server peer started');

                // Create browser peer connection with audio
                pc = new RTCPeerConnection({
                    iceServers: [{ urls: 'stun:stun.l.google.com:19302' }]
                });

                // Create audio stream (silent or from mic)
                let stream;
                try {
                    // Try to get real audio (works in headed mode)
                    stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: false });
                    log('Got microphone audio stream');
                } catch (e) {
                    // Create silent audio for headless
                    log('No mic access, creating silent audio');
                    const ctx = new AudioContext();
                    const oscillator = ctx.createOscillator();
                    oscillator.frequency.value = 0; // Silent
                    const dst = ctx.createMediaStreamDestination();
                    oscillator.connect(dst);
                    oscillator.start();
                    stream = dst.stream;
                }

                // Add audio track
                const audioTrack = stream.getAudioTracks()[0];
                pc.addTrack(audioTrack, stream);
                log('Added audio track to peer connection');

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

                // Create offer
                setStatus('Creating offer with audio...');
                const offer = await pc.createOffer();
                await pc.setLocalDescription(offer);
                log('Created offer with audio, local description set');

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
                log('Received answer from Dart, dtmfSupported=' + answer.dtmfSupported);

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

                // Wait for connection
                setStatus('Waiting for connection...');
                await waitForConnection();
                log('Connection established!', 'success');

                // Request Dart to send DTMF tones
                setStatus('Requesting Dart to send DTMF tones...');
                const dtmfTones = '123*#';
                log('Requesting DTMF tones: "' + dtmfTones + '"', 'dtmf');

                const dtmfResp = await fetch(serverBase + '/send-dtmf', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ tones: dtmfTones, duration: 100, gap: 70 })
                });
                const dtmfResult = await dtmfResp.json();
                log('DTMF send result: ' + JSON.stringify(dtmfResult), 'dtmf');

                // Wait for all tones to be sent
                // Each tone takes duration + gap, plus some buffer
                const waitTime = dtmfTones.length * (100 + 70) + 1000;
                log('Waiting ' + waitTime + 'ms for all tones to complete...');
                await new Promise(resolve => setTimeout(resolve, waitTime));

                // Get results
                setStatus('Getting results...');
                const resultResp = await fetch(serverBase + '/result');
                const result = await resultResp.json();

                log('DTMF Results:', 'dtmf');
                log('  Requested: "' + result.requestedTones + '"', 'dtmf');
                log('  Sent: "' + result.sentTones + '"', 'dtmf');
                log('  Events: ' + JSON.stringify(result.toneChangeEvents), 'dtmf');

                if (result.success) {
                    log('TEST PASSED! DTMF tones sent successfully', 'success');
                    setStatus('TEST PASSED - DTMF tones: ' + result.sentTones);
                } else {
                    log('TEST FAILED - Tones not sent correctly', 'error');
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
  final server = DtmfServer();
  await server.start(port: 8776);
}
