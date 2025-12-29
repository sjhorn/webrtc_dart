// Save to Disk Opus Server for Automated Browser Testing
//
// This server:
// 1. Serves static HTML for browser to send microphone audio (Opus)
// 2. Creates a PeerConnection to receive audio from browser
// 3. Records the audio stream to a WebM file using MediaRecorder
// 4. Stops recording after a configurable duration
//
// Pattern: Dart is OFFERER (recvonly), Browser is ANSWERER (sendonly)
// Output: WebM file with Opus audio

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:webrtc_dart/webrtc_dart.dart';
import 'package:webrtc_dart/src/nonstandard/recorder/media_recorder.dart';

class SaveToDiskOpusServer {
  HttpServer? _server;
  RtcPeerConnection? _pc;
  MediaRecorder? _recorder;
  final List<Map<String, dynamic>> _localCandidates = [];
  Completer<void> _connectionCompleter = Completer();
  DateTime? _startTime;
  DateTime? _connectedTime;
  String _currentBrowser = 'unknown';
  int _rtpPacketsReceived = 0;
  String? _outputPath;
  Timer? _recordingTimer;
  final int _recordingDurationSeconds;

  SaveToDiskOpusServer({int recordingDurationSeconds = 5})
      : _recordingDurationSeconds = recordingDurationSeconds;

  Future<void> start({int port = 8772}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('[SaveToDisk-Opus] Started on http://localhost:$port');

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
    print('[SaveToDisk-Opus] ${request.method} $path');

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
      print('[SaveToDisk-Opus] Error: $e');
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
    print('[SaveToDisk-Opus] Starting Opus test for: $_currentBrowser');

    await _cleanup();
    _localCandidates.clear();
    _startTime = DateTime.now();
    _connectedTime = null;
    _connectionCompleter = Completer();
    _rtpPacketsReceived = 0;
    _outputPath =
        './recording-opus-${DateTime.now().millisecondsSinceEpoch}.webm';

    // Create peer connection - Opus is the default audio codec
    _pc = RtcPeerConnection(RtcConfiguration(
      iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
    ));
    print('[SaveToDisk-Opus] PeerConnection created');

    _pc!.onConnectionStateChange.listen((state) {
      print('[SaveToDisk-Opus] Connection state: $state');
      if (state == PeerConnectionState.connected &&
          !_connectionCompleter.isCompleted) {
        _connectedTime = DateTime.now();
        _connectionCompleter.complete();
      }
    });

    _pc!.onIceConnectionStateChange.listen((state) {
      print('[SaveToDisk-Opus] ICE state: $state');
    });

    _pc!.onIceCandidate.listen((candidate) {
      print(
          '[SaveToDisk-Opus] Local ICE candidate: ${candidate.type} ${candidate.host}:${candidate.port}');
      _localCandidates.add({
        'candidate': 'candidate:${candidate.toSdp()}',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      });
    });

    // Add recvonly audio transceiver
    _pc!.addTransceiver(
      MediaStreamTrackKind.audio,
      direction: RtpTransceiverDirection.recvonly,
    );
    print('[SaveToDisk-Opus] Added audio transceiver (recvonly)');

    _pc!.onTrack.listen((transceiver) async {
      print('[SaveToDisk-Opus] Received track: ${transceiver.kind}');
      final track = transceiver.receiver.track;

      final recordingTrack = RecordingTrack(
        kind: 'audio',
        codecName: 'opus',
        payloadType: 111, // Standard Opus payload type
        clockRate: 48000,
        onRtp: (handler) {
          track.onReceiveRtp.listen((rtp) {
            _rtpPacketsReceived++;
            handler(rtp);
            if (_rtpPacketsReceived % 100 == 0) {
              print(
                  '[SaveToDisk-Opus] Received $_rtpPacketsReceived RTP packets');
            }
          });
        },
      );

      _recorder = MediaRecorder(
        tracks: [recordingTrack],
        path: _outputPath,
        options: MediaRecorderOptions(
          disableLipSync: true, // Audio only, no video
          disableNtp: true,
        ),
      );

      await _recorder!.start();
      print('[SaveToDisk-Opus] Recording started to: $_outputPath');

      _recordingTimer =
          Timer(Duration(seconds: _recordingDurationSeconds), () async {
        print('[SaveToDisk-Opus] Recording duration reached, stopping...');
        await _stopRecording();
      });
    });

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok'}));
  }

  Future<void> _stopRecording() async {
    if (_recorder == null) return;

    print('[SaveToDisk-Opus] Stopping recorder...');
    await _recorder!.stop();
    _recorder = null;
    print('[SaveToDisk-Opus] Recording stopped');

    if (_outputPath != null) {
      final file = File(_outputPath!);
      if (await file.exists()) {
        final size = await file.length();
        print('[SaveToDisk-Opus] Output file: $_outputPath ($size bytes)');
      } else {
        print('[SaveToDisk-Opus] WARNING: Output file not created!');
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
    print('[SaveToDisk-Opus] Created offer, local description set');

    await Future.delayed(Duration(milliseconds: 500));

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'type': offer.type,
      'sdp': offer.sdp,
    }));
    print('[SaveToDisk-Opus] Sent offer to browser');
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

    print('[SaveToDisk-Opus] Received answer from browser');
    await _pc!.setRemoteDescription(answer);
    print('[SaveToDisk-Opus] Remote description set');

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
      print('[SaveToDisk-Opus] Skipping empty ICE candidate');
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
      print('[SaveToDisk-Opus] Added ICE candidate: ${candidate.type}');
    } catch (e) {
      print('[SaveToDisk-Opus] Failed to add candidate: $e');
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
      'outputFile': _outputPath,
      'fileSize': fileSize,
      'recording': _recorder != null,
      'codec': 'Opus',
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
      'outputFile': _outputPath,
      'fileSize': fileSize,
      'connectionTimeMs': connectionTime.inMilliseconds,
      'codec': 'Opus',
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
    <title>WebRTC Save to Disk Opus Test</title>
    <style>
        body { font-family: monospace; padding: 20px; background: #1a1a1a; color: #eee; }
        #log { background: #0a0a0a; padding: 10px; height: 200px; overflow-y: auto; border: 1px solid #333; }
        .info { color: #8af; }
        .success { color: #8f8; }
        .error { color: #f88; }
        h1 { color: #8af; }
        #status { margin: 10px 0; padding: 10px; background: #333; }
        #audioInfo { color: #ff8; margin: 5px 0; }
        .codec-badge { background: #a08; color: #fff; padding: 2px 8px; border-radius: 4px; }
        #meter { width: 200px; height: 20px; background: #333; margin: 10px 0; }
        #meterBar { height: 100%; width: 0%; background: #0f0; transition: width 0.1s; }
    </style>
</head>
<body>
    <h1>WebRTC Save to Disk Test <span class="codec-badge">Opus Audio</span></h1>
    <p>Browser sends Opus audio from microphone to Dart, which records it to a WebM file.</p>
    <div id="status">Status: Waiting to start...</div>
    <div id="meter"><div id="meterBar"></div></div>
    <div id="audioInfo">Waiting for microphone...</div>
    <div id="log"></div>

    <script>
        let pc = null;
        let localStream = null;
        let audioContext = null;
        let analyser = null;
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

        function updateMeter() {
            if (!analyser) return;
            const dataArray = new Uint8Array(analyser.frequencyBinCount);
            analyser.getByteFrequencyData(dataArray);
            const avg = dataArray.reduce((a, b) => a + b, 0) / dataArray.length;
            const level = Math.min(100, avg / 128 * 100);
            document.getElementById('meterBar').style.width = level + '%';
            requestAnimationFrame(updateMeter);
        }

        async function runTest() {
            try {
                const browser = detectBrowser();
                log('Browser detected: ' + browser);
                setStatus('Starting Opus save_to_disk test for ' + browser);

                // Get microphone audio (or use synthetic audio for Safari/headless)
                setStatus('Getting audio access...');
                if (browser === 'safari') {
                    // Safari headless doesn't support getUserMedia for audio
                    log('Safari detected, using synthetic audio stream');
                    localStream = createSyntheticAudioStream();
                    document.getElementById('audioInfo').textContent = 'Audio: Synthetic 440Hz tone';
                    log('Synthetic audio stream created', 'success');
                } else {
                    try {
                        localStream = await navigator.mediaDevices.getUserMedia({
                            audio: true,
                            video: false
                        });
                        log('Got microphone stream');
                        document.getElementById('audioInfo').textContent =
                            'Microphone: ' + localStream.getAudioTracks()[0].label;

                        // Set up audio meter
                        audioContext = new AudioContext();
                        const source = audioContext.createMediaStreamSource(localStream);
                        analyser = audioContext.createAnalyser();
                        analyser.fftSize = 256;
                        source.connect(analyser);
                        updateMeter();
                    } catch (e) {
                        log('Microphone unavailable: ' + e.message + ', using synthetic audio', 'info');
                        localStream = createSyntheticAudioStream();
                        document.getElementById('audioInfo').textContent = 'Audio: Synthetic 440Hz tone (fallback)';
                        log('Synthetic audio stream created', 'success');
                    }
                }

                await fetch(serverBase + '/start?browser=' + browser);
                log('Server peer started (Opus)');

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
                log('Received offer from Dart (Opus)');

                if (offer.sdp.includes('opus')) {
                    log('Opus codec found in offer', 'success');
                }

                await pc.setRemoteDescription(new RTCSessionDescription(offer));
                log('Remote description set (offer)');

                const audioTrack = localStream.getAudioTracks()[0];
                pc.addTrack(audioTrack, localStream);
                log('Added local audio track to send');

                setStatus('Creating answer...');
                const answer = await pc.createAnswer();

                if (answer.sdp.includes('opus')) {
                    log('Opus codec in answer', 'success');
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

                setStatus('Recording Opus audio (5 seconds)...');
                log('Sending Opus audio for recording...');

                for (let i = 0; i < 7; i++) {
                    await new Promise(resolve => setTimeout(resolve, 1000));
                    const statusResp = await fetch(serverBase + '/status');
                    const status = await statusResp.json();
                    log('Status: ' + status.rtpPacketsReceived + ' packets, file: ' + (status.fileSize || 0) + ' bytes');
                }

                setStatus('Getting results...');
                const resultResp = await fetch(serverBase + '/result');
                const result = await resultResp.json();

                if (result.success) {
                    log('TEST PASSED! Opus file created: ' + result.fileSize + ' bytes', 'success');
                    setStatus('TEST PASSED - ' + result.fileSize + ' bytes recorded (Opus)');
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

        // Create synthetic audio stream using Web Audio API (for headless browsers)
        function createSyntheticAudioStream() {
            const audioCtx = new (window.AudioContext || window.webkitAudioContext)();
            const oscillator = audioCtx.createOscillator();
            const gainNode = audioCtx.createGain();
            const destination = audioCtx.createMediaStreamDestination();

            // Create a simple 440Hz sine wave tone
            oscillator.type = 'sine';
            oscillator.frequency.setValueAtTime(440, audioCtx.currentTime);

            // Set volume low so it's not annoying
            gainNode.gain.setValueAtTime(0.1, audioCtx.currentTime);

            // Connect: oscillator -> gain -> destination
            oscillator.connect(gainNode);
            gainNode.connect(destination);
            oscillator.start();

            return destination.stream;
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
  final server = SaveToDiskOpusServer(recordingDurationSeconds: 5);
  await server.start(port: 8772);
}
