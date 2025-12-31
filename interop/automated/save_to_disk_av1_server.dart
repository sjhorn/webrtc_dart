// Save to Disk AV1 Server for Automated Browser Testing
//
// This server:
// 1. Serves static HTML for browser to send camera video (AV1)
// 2. Creates a PeerConnection configured for AV1 codec
// 3. Records the video stream to a WebM file using MediaRecorder
// 4. Stops recording after a configurable duration
//
// Pattern: Dart is OFFERER (recvonly), Browser is ANSWERER (sendonly)
// Output: WebM file with AV1 video
//
// Note: AV1 is only supported by Chrome. Safari and Firefox do not support AV1.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:webrtc_dart/webrtc_dart.dart';
import 'package:webrtc_dart/src/nonstandard/recorder/media_recorder.dart';

class SaveToDiskAv1Server {
  HttpServer? _server;
  RtcPeerConnection? _pc;
  MediaRecorder? _recorder;
  final List<Map<String, dynamic>> _localCandidates = [];
  Completer<void> _connectionCompleter = Completer();
  DateTime? _startTime;
  DateTime? _connectedTime;
  String _currentBrowser = 'unknown';
  int _rtpPacketsReceived = 0;
  int _keyframesReceived = 0;
  String? _outputPath;
  Timer? _recordingTimer;
  final int _recordingDurationSeconds;

  SaveToDiskAv1Server({int recordingDurationSeconds = 5})
      : _recordingDurationSeconds = recordingDurationSeconds;

  Future<void> start({int port = 8776}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('[SaveToDisk-AV1] Started on http://localhost:$port');

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
    print('[SaveToDisk-AV1] ${request.method} $path');

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
      print('[SaveToDisk-AV1] Error: $e');
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
    print('[SaveToDisk-AV1] Starting AV1 test for: $_currentBrowser');

    await _cleanup();
    _localCandidates.clear();
    _startTime = DateTime.now();
    _connectedTime = null;
    _connectionCompleter = Completer();
    _rtpPacketsReceived = 0;
    _keyframesReceived = 0;
    _outputPath =
        './recording-av1-${DateTime.now().millisecondsSinceEpoch}.webm';

    // Create peer connection with AV1 codec preference
    _pc = RtcPeerConnection(RtcConfiguration(
      iceServers: [
        IceServer(urls: ['stun:stun.l.google.com:19302'])
      ],
      codecs: RtcCodecs(
        video: [
          createAv1Codec(payloadType: 96),
        ],
      ),
    ));
    print('[SaveToDisk-AV1] PeerConnection created with AV1 codec');

    _pc!.onConnectionStateChange.listen((state) {
      print('[SaveToDisk-AV1] Connection state: $state');
      if (state == PeerConnectionState.connected &&
          !_connectionCompleter.isCompleted) {
        _connectedTime = DateTime.now();
        _connectionCompleter.complete();
      }
    });

    _pc!.onIceConnectionStateChange.listen((state) {
      print('[SaveToDisk-AV1] ICE state: $state');
    });

    _pc!.onIceCandidate.listen((candidate) {
      print(
          '[SaveToDisk-AV1] Local ICE candidate: ${candidate.type} ${candidate.host}:${candidate.port}');
      _localCandidates.add({
        'candidate': 'candidate:${candidate.toSdp()}',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      });
    });

    _pc!.addTransceiver(
      MediaStreamTrackKind.video,
      direction: RtpTransceiverDirection.recvonly,
    );
    print('[SaveToDisk-AV1] Added video transceiver (recvonly)');

    _pc!.onTrack.listen((transceiver) async {
      print('[SaveToDisk-AV1] Received track: ${transceiver.kind}');
      final track = transceiver.receiver.track;

      final recordingTrack = RecordingTrack(
        kind: 'video',
        codecName: 'AV1',
        payloadType: 96,
        clockRate: 90000,
        onRtp: (handler) {
          track.onReceiveRtp.listen((rtp) {
            _rtpPacketsReceived++;

            // Check for AV1 keyframe (N bit in aggregation header)
            if (rtp.payload.isNotEmpty) {
              final nBit = (rtp.payload[0] >> 3) & 0x01;
              if (nBit == 1) {
                _keyframesReceived++;
              }
            }

            handler(rtp);
            if (_rtpPacketsReceived % 100 == 0) {
              print(
                  '[SaveToDisk-AV1] Received $_rtpPacketsReceived RTP packets, $_keyframesReceived keyframes');
            }
          });
        },
      );

      _recorder = MediaRecorder(
        tracks: [recordingTrack],
        path: _outputPath,
        options: MediaRecorderOptions(
          width: 640,
          height: 480,
          disableLipSync: true,
          disableNtp: true,
        ),
      );

      await _recorder!.start();
      print('[SaveToDisk-AV1] Recording started to: $_outputPath');

      _recordingTimer =
          Timer(Duration(seconds: _recordingDurationSeconds), () async {
        print('[SaveToDisk-AV1] Recording duration reached, stopping...');
        await _stopRecording();
      });
    });

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _stopRecording() async {
    if (_recorder == null) return;

    print('[SaveToDisk-AV1] Stopping recorder...');
    await _recorder!.stop();
    _recorder = null;
    print('[SaveToDisk-AV1] Recording stopped');

    if (_outputPath != null) {
      final file = File(_outputPath!);
      if (await file.exists()) {
        final size = await file.length();
        print('[SaveToDisk-AV1] Output file: $_outputPath ($size bytes)');
      } else {
        print('[SaveToDisk-AV1] WARNING: Output file not created!');
      }
    }
  }

  Future<void> _handleOffer(HttpRequest request) async {
    if (_pc == null) {
      request.response.statusCode = 400;
      request.response.write('Call /start first');
      return;
    }

    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    print('[SaveToDisk-AV1] Created offer, local description set');

    await Future.delayed(Duration(milliseconds: 500));

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'type': offer.type,
      'sdp': offer.sdp,
    }));
    print('[SaveToDisk-AV1] Sent offer to browser');
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

    print('[SaveToDisk-AV1] Received answer from browser');
    await _pc!.setRemoteDescription(answer);
    print('[SaveToDisk-AV1] Remote description set');

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
      print('[SaveToDisk-AV1] Skipping empty ICE candidate');
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
      print('[SaveToDisk-AV1] Added ICE candidate: ${candidate.type}');
    } catch (e) {
      print('[SaveToDisk-AV1] Failed to add candidate: $e');
    }

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _handleCandidates(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(_localCandidates));
  }

  Future<void> _handleStatus(HttpRequest request) async {
    int? fileSize;
    if (_outputPath != null) {
      final file = File(_outputPath!);
      if (await file.exists()) {
        fileSize = await file.length();
      }
    }

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'connectionState': _pc?.connectionState.toString() ?? 'none',
      'iceConnectionState': _pc?.iceConnectionState.toString() ?? 'none',
      'rtpPacketsReceived': _rtpPacketsReceived,
      'keyframesReceived': _keyframesReceived,
      'outputFile': _outputPath,
      'fileSize': fileSize,
      'recording': _recorder != null,
      'codec': 'AV1',
    }));
  }

  Future<void> _handleResult(HttpRequest request) async {
    await _stopRecording();

    final connectionTime = _connectedTime != null && _startTime != null
        ? _connectedTime!.difference(_startTime!)
        : Duration.zero;

    int fileSize = 0;
    bool fileCreated = false;
    if (_outputPath != null) {
      final file = File(_outputPath!);
      if (await file.exists()) {
        fileSize = await file.length();
        fileCreated = fileSize > 0;
      }
    }

    final result = {
      'browser': _currentBrowser,
      'success': _pc?.connectionState == PeerConnectionState.connected &&
          _rtpPacketsReceived > 0 &&
          fileCreated,
      'packetsReceived': _rtpPacketsReceived,
      'keyframesReceived': _keyframesReceived,
      'outputFile': _outputPath,
      'fileSize': fileSize,
      'connectionTimeMs': connectionTime.inMilliseconds,
      'codec': 'AV1',
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
    _recordingTimer?.cancel();
    _recordingTimer = null;
    await _stopRecording();
    await _pc?.close();
    _pc = null;
  }

  static const String _testPageHtml = '''
<!DOCTYPE html>
<html>
<head>
    <title>WebRTC Save to Disk AV1 Test</title>
    <style>
        body { font-family: monospace; padding: 20px; background: #1a1a1a; color: #eee; }
        #log { background: #0a0a0a; padding: 10px; height: 200px; overflow-y: auto; border: 1px solid #333; }
        .info { color: #8af; }
        .success { color: #8f8; }
        .error { color: #f88; }
        .warn { color: #fa0; }
        h1 { color: #8af; }
        #status { margin: 10px 0; padding: 10px; background: #333; }
        video { width: 320px; height: 240px; background: #000; border: 2px solid #333; margin: 10px 0; }
        #videoInfo { color: #ff8; margin: 5px 0; }
        .codec-badge { background: #a08; color: #fff; padding: 2px 8px; border-radius: 4px; }
    </style>
</head>
<body>
    <h1>WebRTC Save to Disk Test <span class="codec-badge">AV1</span></h1>
    <p>Browser sends AV1 video to Dart, which records it to a WebM file.</p>
    <p><strong>Note:</strong> AV1 is only supported by Chrome. Safari and Firefox do not support AV1.</p>
    <div id="status">Status: Waiting to start...</div>
    <video id="localVideo" autoPlay muted playsinline></video>
    <div id="videoInfo">Waiting for camera...</div>
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

                // Check AV1 support
                if (browser !== 'chrome') {
                    throw new Error('AV1 is only supported by Chrome');
                }

                setStatus('Starting AV1 save_to_disk test for ' + browser);

                // Get local camera stream
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
                    log('Got local camera stream');
                    const localVideo = document.getElementById('localVideo');
                    localVideo.srcObject = localStream;
                    document.getElementById('videoInfo').textContent =
                        'Camera: ' + localStream.getVideoTracks()[0].label;
                } catch (e) {

                        log('Camera unavailable: ' + e.message + ', using canvas fallback', 'info');

                        localStream = createCanvasStream(640, 480, 30);

                        log('Canvas stream created', 'success');

                    }

                }

                await fetch(serverBase + '/start?browser=' + browser);
                log('Server peer started (AV1)');

                pc = new RTCPeerConnection({
                    iceServers: [{ urls: 'stun:stun.l.google.com:19302' }]
                });

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

                setStatus('Getting offer from Dart...');
                const offerResp = await fetch(serverBase + '/offer');
                const offer = await offerResp.json();
                log('Received offer from Dart (AV1)');

                if (offer.sdp.includes('AV1')) {
                    log('AV1 codec found in offer', 'success');
                } else {
                    log('Warning: AV1 not found in offer', 'warn');
                }

                await pc.setRemoteDescription(new RTCSessionDescription(offer));
                log('Remote description set (offer)');

                const videoTrack = localStream.getVideoTracks()[0];
                pc.addTrack(videoTrack, localStream);
                log('Added local video track to send');

                setStatus('Creating answer...');
                const answer = await pc.createAnswer();

                if (answer.sdp.includes('AV1')) {
                    log('AV1 codec in answer', 'success');
                }

                await pc.setLocalDescription(answer);
                log('Local description set (answer)');

                await new Promise(resolve => setTimeout(resolve, 500));

                setStatus('Sending answer to Dart...');
                await fetch(serverBase + '/answer', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ type: answer.type, sdp: pc.localDescription.sdp })
                });
                log('Sent answer to Dart');

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
                await waitForConnection();
                log('Connection established!', 'success');

                setStatus('Recording AV1 video (5 seconds)...');
                log('Sending AV1 video for recording...');

                for (let i = 0; i < 7; i++) {
                    await new Promise(resolve => setTimeout(resolve, 1000));
                    const statusResp = await fetch(serverBase + '/status');
                    const status = await statusResp.json();
                    log('Status: ' + status.rtpPacketsReceived + ' packets, ' + status.keyframesReceived + ' keyframes, file: ' + (status.fileSize || 0) + ' bytes');
                }

                setStatus('Getting results...');
                const resultResp = await fetch(serverBase + '/result');
                const result = await resultResp.json();

                if (result.success) {
                    log('TEST PASSED! AV1 file created: ' + result.fileSize + ' bytes', 'success');
                    setStatus('TEST PASSED - ' + result.fileSize + ' bytes recorded (AV1)');
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

        window.addEventListener('load', () => {
            setTimeout(runTest, 500);
        });
    </script>
</body>
</html>
''';
}

void main() async {
  final server = SaveToDiskAv1Server(recordingDurationSeconds: 5);
  await server.start(port: 8776);
}
