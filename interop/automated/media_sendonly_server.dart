// Media Sendonly Server for Automated Browser Testing
//
// This server:
// 1. Serves static HTML for browser to receive video
// 2. Creates a PeerConnection with sendonly video track
// 3. Uses FFmpeg to generate test video pattern
// 4. Sends video to browser via WebRTC
//
// Pattern: Dart is OFFERER (sendonly), Browser is ANSWERER (recvonly)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:webrtc_dart/webrtc_dart.dart';
import 'package:webrtc_dart/src/nonstandard/media/track.dart' as nonstandard;

class MediaTestResult {
  final String browser;
  final bool success;
  final bool videoReceived;
  final int framesReceived;
  final String? error;
  final Duration connectionTime;

  MediaTestResult({
    required this.browser,
    required this.success,
    required this.videoReceived,
    required this.framesReceived,
    this.error,
    required this.connectionTime,
  });

  Map<String, dynamic> toJson() => {
        'browser': browser,
        'success': success,
        'videoReceived': videoReceived,
        'framesReceived': framesReceived,
        'error': error,
        'connectionTimeMs': connectionTime.inMilliseconds,
      };
}

class MediaSendonlyServer {
  HttpServer? _server;
  RtcPeerConnection? _pc;
  nonstandard.MediaStreamTrack? _videoTrack;
  RawDatagramSocket? _udpSocket;
  Process? _ffmpegProcess;
  final List<Map<String, dynamic>> _localCandidates = [];
  Completer<void> _connectionCompleter = Completer();
  DateTime? _startTime;
  DateTime? _connectedTime;
  String _currentBrowser = 'unknown';
  int _rtpPacketsSent = 0;
  bool _stopped = false;

  Future<void> start({int port = 8766}) async {
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
    print('[MediaServer] Starting test for browser: $_currentBrowser');

    // Reset state
    await _cleanup();
    _localCandidates.clear();
    _startTime = DateTime.now();
    _connectedTime = null;
    _connectionCompleter = Completer();
    _rtpPacketsSent = 0;
    _stopped = false;

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
        // Start FFmpeg once connected
        _startVideoSource();
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

    // Create video track for sendonly
    _videoTrack = nonstandard.MediaStreamTrack(kind: nonstandard.MediaKind.video);

    // Add transceiver with sendonly direction
    _pc!.addTransceiverWithTrack(
      _videoTrack!,
      direction: RtpTransceiverDirection.sendonly,
    );
    print('[MediaServer] Added video transceiver (sendonly)');

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _startVideoSource() async {
    if (_stopped) return;

    // Create UDP socket to receive RTP from FFmpeg (bind to port 0 = any available)
    _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final udpPort = _udpSocket!.port;
    print('[MediaServer] UDP socket listening on port $udpPort');

    _udpSocket!.listen((event) {
      if (event == RawSocketEvent.read && !_stopped) {
        final datagram = _udpSocket!.receive();
        if (datagram != null && _videoTrack != null) {
          _videoTrack!.writeRtp(datagram.data);
          _rtpPacketsSent++;
          if (_rtpPacketsSent % 100 == 0) {
            print('[MediaServer] Sent $_rtpPacketsSent RTP packets');
          }
        }
      }
    });

    // Start FFmpeg with testsrc (generates color bars pattern)
    // VP8 encoding, output to RTP
    final ffmpegArgs = [
      '-re', // Real-time mode
      '-f', 'lavfi',
      '-i', 'testsrc=size=640x480:rate=30', // Color bars test pattern
      '-c:v', 'libvpx', // VP8 encoder
      '-deadline', 'realtime',
      '-cpu-used', '8', // Fast encoding
      '-b:v', '1M', // 1Mbps bitrate
      '-keyint_min', '30',
      '-g', '30', // Keyframe every 30 frames (1 second)
      '-f', 'rtp',
      '-payload_type', '96',
      'rtp://127.0.0.1:$udpPort',
    ];

    print('[MediaServer] Starting FFmpeg: ffmpeg ${ffmpegArgs.join(' ')}');

    try {
      _ffmpegProcess = await Process.start('ffmpeg', ffmpegArgs);

      // Log FFmpeg stderr for debugging
      _ffmpegProcess!.stderr.transform(utf8.decoder).listen((data) {
        // Only print important messages
        if (data.contains('error') || data.contains('Error')) {
          print('[FFmpeg] $data');
        }
      });

      _ffmpegProcess!.exitCode.then((code) {
        print('[MediaServer] FFmpeg exited with code $code');
      });

      print('[MediaServer] FFmpeg started');
    } catch (e) {
      print('[MediaServer] Failed to start FFmpeg: $e');
    }
  }

  Future<void> _handleOffer(HttpRequest request) async {
    // In sendonly mode, Dart creates the offer, not the browser
    // This endpoint returns the Dart's offer
    if (_pc == null) {
      request.response.statusCode = 400;
      request.response.write('Call /start first');
      return;
    }

    // Create offer
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
      'rtpPacketsSent': _rtpPacketsSent,
    }));
  }

  Future<void> _handleResult(HttpRequest request) async {
    final connectionTime = _connectedTime != null && _startTime != null
        ? _connectedTime!.difference(_startTime!)
        : Duration.zero;

    final result = MediaTestResult(
      browser: _currentBrowser,
      success: _pc?.connectionState == PeerConnectionState.connected &&
          _rtpPacketsSent > 0,
      videoReceived: _rtpPacketsSent > 0,
      framesReceived: _rtpPacketsSent ~/ 30, // Approximate frames (30fps)
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
    _stopped = true;
    _ffmpegProcess?.kill(ProcessSignal.sigint);
    _ffmpegProcess = null;
    _udpSocket?.close();
    _udpSocket = null;
    _videoTrack?.stop();
    _videoTrack = null;
    await _pc?.close();
    _pc = null;
  }

  static const String _testPageHtml = '''
<!DOCTYPE html>
<html>
<head>
    <title>WebRTC Media Sendonly Test</title>
    <style>
        body { font-family: monospace; padding: 20px; background: #1a1a1a; color: #eee; }
        #log { background: #0a0a0a; padding: 10px; height: 200px; overflow-y: auto; border: 1px solid #333; }
        .info { color: #8af; }
        .success { color: #8f8; }
        .error { color: #f88; }
        h1 { color: #8af; }
        #status { margin: 10px 0; padding: 10px; background: #333; }
        video {
            width: 640px;
            height: 480px;
            background: #000;
            border: 2px solid #333;
            margin: 10px 0;
        }
        #videoInfo { color: #ff8; margin: 5px 0; }
    </style>
</head>
<body>
    <h1>WebRTC Media Sendonly Test (Dart -> Browser)</h1>
    <div id="status">Status: Waiting to start...</div>
    <video id="remoteVideo" autoPlay muted playsinline></video>
    <div id="videoInfo">Waiting for video...</div>
    <div id="log"></div>

    <script>
        let pc = null;
        let framesReceived = 0;
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
            const video = document.getElementById('remoteVideo');
            const info = document.getElementById('videoInfo');
            if (video.videoWidth > 0) {
                const elapsed = videoStartTime ? ((Date.now() - videoStartTime) / 1000).toFixed(1) : 0;
                info.textContent = 'Video: ' + video.videoWidth + 'x' + video.videoHeight +
                    ' | Frames: ' + framesReceived + ' | Time: ' + elapsed + 's';
            }
        }

        async function runTest() {
            try {
                const browser = detectBrowser();
                log('Browser detected: ' + browser);
                setStatus('Starting test for ' + browser);

                // Start server-side peer
                await fetch(serverBase + '/start?browser=' + browser);
                log('Server peer started');

                // Create browser peer connection with STUN server
                pc = new RTCPeerConnection({
                    iceServers: [{ urls: 'stun:stun.l.google.com:19302' }]
                });

                // Set up ICE candidate handler EARLY (before setRemoteDescription)
                const pendingCandidates = [];
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

                // Handle incoming video track
                pc.ontrack = (e) => {
                    log('Received track: ' + e.track.kind, 'success');
                    const video = document.getElementById('remoteVideo');
                    if (!video.srcObject) {
                        video.srcObject = new MediaStream();
                    }
                    video.srcObject.addTrack(e.track);
                    videoStartTime = Date.now();

                    // Count frames via requestVideoFrameCallback if available
                    if ('requestVideoFrameCallback' in HTMLVideoElement.prototype) {
                        const countFrame = () => {
                            framesReceived++;
                            updateVideoInfo();
                            video.requestVideoFrameCallback(countFrame);
                        };
                        video.requestVideoFrameCallback(countFrame);
                    } else {
                        // Fallback: estimate based on time
                        setInterval(updateVideoInfo, 100);
                    }
                };

                // Get offer from Dart server
                setStatus('Getting offer from Dart...');
                const offerResp = await fetch(serverBase + '/offer');
                const offer = await offerResp.json();
                log('Received offer from Dart');
                log('Offer SDP has ' + (offer.sdp.match(/m=video/g) || []).length + ' video sections');

                // Set remote description (offer from Dart)
                await pc.setRemoteDescription(new RTCSessionDescription(offer));
                log('Remote description set (offer)');

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

                setStatus('Waiting for connection and video...');

                // Wait for connection
                await waitForConnection();
                log('Connection established!', 'success');

                // Wait for video to start playing
                await waitForVideo();
                log('Video playing!', 'success');

                // Let video play for a few seconds
                setStatus('Receiving video...');
                await new Promise(resolve => setTimeout(resolve, 5000));

                // Get results
                const resultResp = await fetch(serverBase + '/result');
                const result = await resultResp.json();
                result.framesReceived = framesReceived;
                result.videoReceived = framesReceived > 0;
                result.success = result.success && framesReceived > 0;

                if (result.success) {
                    log('TEST PASSED! Received ' + framesReceived + ' frames', 'success');
                    setStatus('TEST PASSED - ' + framesReceived + ' frames received');
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
                const timeout = setTimeout(() => reject(new Error('Video timeout')), 30000);

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
  final server = MediaSendonlyServer();
  await server.start(port: 8766);
}
