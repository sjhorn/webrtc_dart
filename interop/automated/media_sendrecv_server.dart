// Media Sendrecv Server for Automated Browser Testing
//
// This server:
// 1. Serves static HTML for browser to send and receive video
// 2. Creates a PeerConnection with sendrecv video transceiver
// 3. Receives video from browser's camera
// 4. Echoes video back using sender.replaceTrack()
//
// Pattern: Dart is OFFERER (sendrecv), Browser is ANSWERER (sendrecv)
// Browser should see both its local camera and the echoed remote video

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:webrtc_dart/webrtc_dart.dart';
import 'package:webrtc_dart/src/nonstandard/media/track.dart' as nonstandard;

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

class MediaSendrecvServer {
  HttpServer? _server;
  RtcPeerConnection? _pc;
  nonstandard.MediaStreamTrack? _sendTrack;
  final List<Map<String, dynamic>> _localCandidates = [];
  Completer<void> _connectionCompleter = Completer();
  DateTime? _startTime;
  DateTime? _connectedTime;
  String _currentBrowser = 'unknown';
  int _rtpPacketsReceived = 0;
  int _rtpPacketsEchoed = 0;
  bool _echoStarted = false;

  Future<void> start({int port = 8768}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('[MediaServer] Started on http://localhost:$port');

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
    print('[MediaServer] ${request.method} $path');

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
      print('[MediaServer] Error: $e');
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
    print('[MediaServer] Starting sendrecv test for browser: $_currentBrowser');

    // Reset state
    await _cleanup();
    _localCandidates.clear();
    _startTime = DateTime.now();
    _connectedTime = null;
    _connectionCompleter = Completer();
    _rtpPacketsReceived = 0;
    _rtpPacketsEchoed = 0;
    _echoStarted = false;

    // Create peer connection with STUN server
    _pc = RtcPeerConnection(RtcConfiguration(
      iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
    ));
    print('[MediaServer] PeerConnection created');

    // Track connection state
    _pc!.onConnectionStateChange.listen((state) {
      print('[MediaServer] Connection state: $state');
      if (state == PeerConnectionState.connected &&
          !_connectionCompleter.isCompleted) {
        _connectedTime = DateTime.now();
        _connectionCompleter.complete();
      }
    });

    _pc!.onIceConnectionStateChange.listen((state) {
      print('[MediaServer] ICE state: $state');
    });

    // Track ICE candidates
    _pc!.onIceCandidate.listen((candidate) {
      print(
          '[MediaServer] Local ICE candidate: ${candidate.type} ${candidate.host}:${candidate.port}');
      _localCandidates.add({
        'candidate': 'candidate:${candidate.toSdp()}',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      });
    });

    // Create a nonstandard track for sending echoed video
    _sendTrack =
        nonstandard.MediaStreamTrack(kind: nonstandard.MediaKind.video);

    // Add sendrecv video transceiver with our send track
    _pc!.addTransceiver(
      _sendTrack!,
      direction: RtpTransceiverDirection.sendrecv,
    );
    print('[MediaServer] Added video transceiver (sendrecv) with send track');

    // Handle incoming tracks - echo RTP packets back
    _pc!.onTrack.listen((transceiver) {
      print('[MediaServer] Received track: ${transceiver.kind}');
      final track = transceiver.receiver.track;

      // Listen for incoming RTP packets and echo them back
      track.onReceiveRtp.listen((rtpPacket) {
        _rtpPacketsReceived++;

        // Echo the RTP packet back to the browser
        if (_sendTrack != null) {
          _sendTrack!.writeRtp(rtpPacket);
          _rtpPacketsEchoed++;
        }

        if (_rtpPacketsReceived % 100 == 0) {
          print(
              '[MediaServer] Received $_rtpPacketsReceived, echoed $_rtpPacketsEchoed RTP packets');
        }
      });

      if (!_echoStarted && transceiver.kind == MediaStreamTrackKind.video) {
        _echoStarted = true;
        print('[MediaServer] Started echoing video track back to browser');
      }
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

    // Create offer (Dart is offerer)
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    print('[MediaServer] Created offer, local description set');

    // Wait briefly for ICE gathering
    await Future.delayed(Duration(milliseconds: 500));

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'type': offer.type,
      'sdp': offer.sdp,
    }));
    print('[MediaServer] Sent offer to browser');
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

    print('[MediaServer] Received answer from browser');
    await _pc!.setRemoteDescription(answer);
    print('[MediaServer] Remote description set');

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
      print('[MediaServer] Skipping empty ICE candidate (end-of-candidates)');
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
      print('[MediaServer] Added ICE candidate: ${candidate.type}');
    } catch (e) {
      print('[MediaServer] Failed to add candidate: $e');
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
      'rtpPacketsReceived': _rtpPacketsReceived,
      'echoStarted': _echoStarted,
    }));
  }

  Future<void> _handleResult(HttpRequest request) async {
    final connectionTime = _connectedTime != null && _startTime != null
        ? _connectedTime!.difference(_startTime!)
        : Duration.zero;

    final result = MediaTestResult(
      browser: _currentBrowser,
      success: _pc?.connectionState == PeerConnectionState.connected &&
          _rtpPacketsReceived > 0 &&
          _echoStarted,
      videoReceived: _rtpPacketsReceived > 0,
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
    _sendTrack?.stop();
    _sendTrack = null;
    await _pc?.close();
    _pc = null;
  }

  static const String _testPageHtml = '''
<!DOCTYPE html>
<html>
<head>
    <title>WebRTC Media Sendrecv Test</title>
    <style>
        body { font-family: monospace; padding: 20px; background: #1a1a1a; color: #eee; }
        #log { background: #0a0a0a; padding: 10px; height: 150px; overflow-y: auto; border: 1px solid #333; }
        .info { color: #8af; }
        .success { color: #8f8; }
        .error { color: #f88; }
        h1 { color: #8af; }
        #status { margin: 10px 0; padding: 10px; background: #333; }
        .video-container { display: flex; gap: 20px; margin: 10px 0; }
        .video-box { text-align: center; }
        .video-box label { display: block; margin-bottom: 5px; color: #ff8; }
        video {
            width: 320px;
            height: 240px;
            background: #000;
            border: 2px solid #333;
        }
        #localVideo { border-color: #8af; }
        #remoteVideo { border-color: #8f8; }
        #videoInfo { color: #ff8; margin: 5px 0; }
    </style>
</head>
<body>
    <h1>WebRTC Media Sendrecv Test (Echo)</h1>
    <div id="status">Status: Waiting to start...</div>
    <div class="video-container">
        <div class="video-box">
            <label>Local Camera</label>
            <video id="localVideo" autoPlay muted playsinline></video>
        </div>
        <div class="video-box">
            <label>Remote (Echo from Dart)</label>
            <video id="remoteVideo" autoPlay muted playsinline></video>
        </div>
    </div>
    <div id="videoInfo">Waiting for video...</div>
    <div id="log"></div>

    <script>
        let pc = null;
        let localStream = null;
        let remoteFramesReceived = 0;
        let localFramesSent = 0;
        let videoStartTime = null;
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

        function updateVideoInfo() {
            const localVideo = document.getElementById('localVideo');
            const remoteVideo = document.getElementById('remoteVideo');
            const info = document.getElementById('videoInfo');
            const parts = [];

            if (localVideo.videoWidth > 0) {
                parts.push('Local: ' + localVideo.videoWidth + 'x' + localVideo.videoHeight);
            }
            if (remoteVideo.videoWidth > 0) {
                parts.push('Remote: ' + remoteVideo.videoWidth + 'x' + remoteVideo.videoHeight);
            }
            parts.push('Remote frames: ' + remoteFramesReceived);

            if (videoStartTime) {
                const elapsed = ((Date.now() - videoStartTime) / 1000).toFixed(1);
                parts.push('Time: ' + elapsed + 's');
            }

            info.textContent = parts.join(' | ');
        }

        async function runTest() {
            try {
                const browser = detectBrowser();
                log('Browser detected: ' + browser);
                setStatus('Starting sendrecv test for ' + browser);

                // Get local camera stream (with canvas fallback for Safari headless)
                setStatus('Getting camera access...');
                if (browser === 'safari') {

                    log('Safari detected, using canvas stream (avoids permission dialog)');

                    localStream = createCanvasStream(640, 480, 30);

                    log('Canvas stream created', 'success');

                } else {

                    try {

                        localStream = await navigator.mediaDevices.getUserMedia({

                            video: { width: 640, height: 480 },

                            audio: false

                        });

                        log('Camera access granted', 'success');

                    } catch (e) {

                        log('Camera unavailable: ' + e.message + ', using canvas fallback', 'warn');

                        localStream = createCanvasStream(640, 480, 30);

                        log('Canvas stream created', 'success');

                    }

                }
                document.getElementById('localVideo').srcObject = localStream;

                // Start server-side peer
                await fetch(serverBase + '/start?browser=' + browser);
                log('Server peer started');

                // Create browser peer connection with STUN server
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

                // Handle incoming video track (echoed from Dart)
                pc.ontrack = (e) => {
                    log('Received remote track: ' + e.track.kind, 'success');
                    const remoteVideo = document.getElementById('remoteVideo');
                    if (!remoteVideo.srcObject) {
                        remoteVideo.srcObject = new MediaStream();
                    }
                    remoteVideo.srcObject.addTrack(e.track);
                    videoStartTime = Date.now();

                    // Count frames
                    if ('requestVideoFrameCallback' in HTMLVideoElement.prototype) {
                        const countFrame = () => {
                            remoteFramesReceived++;
                            updateVideoInfo();
                            remoteVideo.requestVideoFrameCallback(countFrame);
                        };
                        remoteVideo.requestVideoFrameCallback(countFrame);
                    } else {
                        setInterval(updateVideoInfo, 100);
                    }
                };

                // Get offer from Dart server
                setStatus('Getting offer from Dart...');
                const offerResp = await fetch(serverBase + '/offer');
                const offer = await offerResp.json();
                log('Received offer from Dart');

                // Set remote description (offer from Dart)
                await pc.setRemoteDescription(new RTCSessionDescription(offer));
                log('Remote description set (offer)');

                // Add local video track to send to Dart
                const videoTrack = localStream.getVideoTracks()[0];
                pc.addTrack(videoTrack, localStream);
                log('Added local video track to send');

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

                setStatus('Waiting for connection and echo video...');

                // Wait for connection
                await waitForConnection();
                log('Connection established!', 'success');

                // Wait for remote video (echoed back)
                await waitForVideo();
                log('Echo video playing!', 'success');

                // Let video echo for a few seconds
                setStatus('Receiving echo video...');
                await new Promise(resolve => setTimeout(resolve, 5000));

                // Get results
                const resultResp = await fetch(serverBase + '/result');
                const result = await resultResp.json();
                result.remoteFramesReceived = remoteFramesReceived;
                result.echoReceived = remoteFramesReceived > 0;
                result.success = result.success && remoteFramesReceived > 0;

                if (result.success) {
                    log('TEST PASSED! Echo working - received ' + remoteFramesReceived + ' frames', 'success');
                    setStatus('TEST PASSED - Echo working');
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

        async function waitForVideo() {
            const video = document.getElementById('remoteVideo');
            return new Promise((resolve, reject) => {
                const timeout = setTimeout(() => reject(new Error('Remote video timeout')), 30000);

                const check = () => {
                    if (video.videoWidth > 0 && video.videoHeight > 0) {
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
  final server = MediaSendrecvServer();
  await server.start(port: 8768);
}
