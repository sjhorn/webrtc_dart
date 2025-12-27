// Media Recvonly Server for Automated Browser Testing
//
// This server:
// 1. Serves static HTML for browser to send video
// 2. Creates a PeerConnection with recvonly video transceiver
// 3. Browser uses getUserMedia to capture and send video
// 4. Dart receives RTP packets and counts them
//
// Pattern: Dart is OFFERER (recvonly), Browser is ANSWERER (sendonly)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:webrtc_dart/webrtc_dart.dart';

class MediaTestResult {
  final String browser;
  final bool success;
  final bool videoReceived;
  final int packetsReceived;
  final String? error;
  final Duration connectionTime;

  MediaTestResult({
    required this.browser,
    required this.success,
    required this.videoReceived,
    required this.packetsReceived,
    this.error,
    required this.connectionTime,
  });

  Map<String, dynamic> toJson() => {
        'browser': browser,
        'success': success,
        'videoReceived': videoReceived,
        'packetsReceived': packetsReceived,
        'error': error,
        'connectionTimeMs': connectionTime.inMilliseconds,
      };
}

class MediaRecvonlyServer {
  HttpServer? _server;
  RtcPeerConnection? _pc;
  RtpTransceiver? _transceiver;
  final List<Map<String, dynamic>> _localCandidates = [];
  Completer<void> _connectionCompleter = Completer();
  DateTime? _startTime;
  DateTime? _connectedTime;
  String _currentBrowser = 'unknown';
  int _rtpPacketsReceived = 0;
  bool _trackReceived = false;

  Future<void> start({int port = 8767}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('[RecvServer] Started on http://localhost:$port');

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
    print('[RecvServer] ${request.method} $path');

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
      print('[RecvServer] Error: $e');
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
    print('[RecvServer] Starting test for browser: $_currentBrowser');

    // Reset state
    await _cleanup();
    _localCandidates.clear();
    _startTime = DateTime.now();
    _connectedTime = null;
    _connectionCompleter = Completer();
    _rtpPacketsReceived = 0;
    _trackReceived = false;

    // Create peer connection with STUN server
    _pc = RtcPeerConnection(RtcConfiguration(
      iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
    ));
    print('[RecvServer] PeerConnection created');

    // Track connection state
    _pc!.onConnectionStateChange.listen((state) {
      print('[RecvServer] Connection state: $state');
      if (state == PeerConnectionState.connected &&
          !_connectionCompleter.isCompleted) {
        _connectedTime = DateTime.now();
        _connectionCompleter.complete();
      }
    });

    _pc!.onIceConnectionStateChange.listen((state) {
      print('[RecvServer] ICE state: $state');
    });

    // Track ICE candidates
    _pc!.onIceCandidate.listen((candidate) {
      print(
          '[RecvServer] Local ICE candidate: ${candidate.type} ${candidate.host}:${candidate.port}');
      _localCandidates.add({
        'candidate': 'candidate:${candidate.toSdp()}',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      });
    });

    // Listen for incoming track from browser
    _pc!.onTrack.listen((transceiver) {
      print('[RecvServer] Received track: ${transceiver.kind}, mid=${transceiver.mid}');
      _trackReceived = true;

      // Count received RTP packets
      final track = transceiver.receiver.track;
      track.onReceiveRtp.listen((packet) {
        _rtpPacketsReceived++;
        if (_rtpPacketsReceived % 100 == 0) {
          print('[RecvServer] Received $_rtpPacketsReceived RTP packets');
        }
      });
    });

    // Add recvonly video transceiver
    _transceiver = _pc!.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.recvonly,
    );
    print('[RecvServer] Added video transceiver (recvonly), mid=${_transceiver!.mid}');

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _handleOffer(HttpRequest request) async {
    // Dart creates the offer with recvonly
    if (_pc == null) {
      request.response.statusCode = 400;
      request.response.write('Call /start first');
      return;
    }

    // Create offer
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    print('[RecvServer] Created offer, local description set');

    // Wait briefly for ICE gathering
    await Future.delayed(Duration(milliseconds: 500));

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'type': offer.type,
      'sdp': offer.sdp,
    }));
    print('[RecvServer] Sent offer to browser');
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

    print('[RecvServer] Received answer from browser');
    await _pc!.setRemoteDescription(answer);
    print('[RecvServer] Remote description set');

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

    // Skip empty or end-of-candidates signals
    if (candidateStr.isEmpty || candidateStr.trim().isEmpty) {
      print('[RecvServer] Skipping empty ICE candidate');
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
      print('[RecvServer] Added ICE candidate: ${candidate.type}');
    } catch (e) {
      print('[RecvServer] Failed to add candidate: $e');
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
      'trackReceived': _trackReceived,
      'rtpPacketsReceived': _rtpPacketsReceived,
    }));
  }

  Future<void> _handleResult(HttpRequest request) async {
    final connectionTime = _connectedTime != null && _startTime != null
        ? _connectedTime!.difference(_startTime!)
        : Duration.zero;

    final result = MediaTestResult(
      browser: _currentBrowser,
      success: _pc?.connectionState == PeerConnectionState.connected &&
          _rtpPacketsReceived > 0,
      videoReceived: _trackReceived && _rtpPacketsReceived > 0,
      packetsReceived: _rtpPacketsReceived,
      connectionTime: connectionTime,
    );

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(result.toJson()));
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
    await _pc?.close();
    _pc = null;
  }

  static const String _testPageHtml = '''
<!DOCTYPE html>
<html>
<head>
    <title>WebRTC Media Recvonly Test</title>
    <style>
        body { font-family: monospace; padding: 20px; background: #1a1a1a; color: #eee; }
        #log { background: #0a0a0a; padding: 10px; height: 200px; overflow-y: auto; border: 1px solid #333; }
        .info { color: #8af; }
        .success { color: #8f8; }
        .error { color: #f88; }
        h1 { color: #8af; }
        #status { margin: 10px 0; padding: 10px; background: #333; }
        video {
            width: 320px;
            height: 240px;
            background: #000;
            border: 2px solid #333;
            margin: 10px 0;
        }
        #videoInfo { color: #ff8; margin: 5px 0; }
    </style>
</head>
<body>
    <h1>WebRTC Media Recvonly Test (Browser -> Dart)</h1>
    <div id="status">Status: Waiting to start...</div>
    <video id="localVideo" autoPlay muted playsinline></video>
    <div id="videoInfo">Local camera preview</div>
    <div id="log"></div>

    <script>
        let pc = null;
        let localStream = null;
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
                setStatus('Starting test for ' + browser);

                // Get video stream - try camera first, fall back to canvas
                setStatus('Requesting video stream...');
                try {
                    localStream = await navigator.mediaDevices.getUserMedia({
                        video: { width: 640, height: 480 },
                        audio: false
                    });
                    log('Camera access granted', 'success');
                } catch (e) {
                    log('Camera unavailable: ' + e.message + ', using canvas fallback', 'warn');
                    // Create canvas stream as fallback (works in Safari headless)
                    localStream = createCanvasStream(640, 480, 30);
                    log('Canvas stream created', 'success');
                }

                // Show local preview
                const localVideo = document.getElementById('localVideo');
                localVideo.srcObject = localStream;

                // Start server-side peer
                await fetch(serverBase + '/start?browser=' + browser);
                log('Server peer started');

                // Create browser peer connection with STUN
                pc = new RTCPeerConnection({
                    iceServers: [{ urls: 'stun:stun.l.google.com:19302' }]
                });

                // Set up ICE candidate handler EARLY
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

                // Get offer from Dart (which has recvonly)
                setStatus('Getting offer from Dart...');
                const offerResp = await fetch(serverBase + '/offer');
                const offer = await offerResp.json();
                log('Received offer from Dart');

                // Set remote description
                await pc.setRemoteDescription(new RTCSessionDescription(offer));
                log('Remote description set (offer)');

                // Add local video track to send to Dart
                localStream.getTracks().forEach(track => {
                    pc.addTrack(track, localStream);
                    log('Added local track: ' + track.kind);
                });

                // Create answer
                setStatus('Creating answer...');
                const answer = await pc.createAnswer();
                await pc.setLocalDescription(answer);
                log('Local description set (answer)');

                // Wait for ICE gathering
                await new Promise(resolve => setTimeout(resolve, 500));

                // Send answer to Dart
                setStatus('Sending answer to Dart...');
                await fetch(serverBase + '/answer', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ type: answer.type, sdp: pc.localDescription.sdp })
                });
                log('Sent answer to Dart');

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

                setStatus('Waiting for connection...');

                // Wait for connection
                await waitForConnection();
                log('Connection established!', 'success');

                // Send video for a few seconds
                setStatus('Sending video to Dart...');
                await new Promise(resolve => setTimeout(resolve, 5000));

                // Get results
                const resultResp = await fetch(serverBase + '/result');
                const result = await resultResp.json();

                if (result.success) {
                    log('TEST PASSED! Dart received ' + result.packetsReceived + ' RTP packets', 'success');
                    setStatus('TEST PASSED - ' + result.packetsReceived + ' packets received by Dart');
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
  final server = MediaRecvonlyServer();
  await server.start(port: 8767);
}
