// Save to Disk GStreamer Server for Automated Browser Testing
//
// This server:
// 1. Serves static HTML for browser to send camera video (VP8)
// 2. Creates a PeerConnection to receive video from browser
// 3. Forwards raw RTP packets via UDP to GStreamer
// 4. GStreamer handles depacketization and muxing to WebM file
//
// Pattern: Dart is OFFERER (recvonly), Browser is ANSWERER (sendonly)
// Output: WebM file created by GStreamer
//
// Requirements: GStreamer 1.x with good/bad plugins (udpsrc, rtpvp8depay, webmmux)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:webrtc_dart/webrtc_dart.dart';

class SaveToDiskGstServer {
  HttpServer? _server;
  RtcPeerConnection? _pc;
  final List<Map<String, dynamic>> _localCandidates = [];
  Completer<void> _connectionCompleter = Completer();
  DateTime? _startTime;
  DateTime? _connectedTime;
  String _currentBrowser = 'unknown';
  int _rtpPacketsReceived = 0;
  int _rtpPacketsForwarded = 0;
  String? _outputPath;
  Timer? _recordingTimer;
  final int _recordingDurationSeconds;

  // UDP socket for forwarding to GStreamer
  RawDatagramSocket? _udpSocket;
  int? _gstPort;
  Process? _gstProcess;

  SaveToDiskGstServer({int recordingDurationSeconds = 5})
      : _recordingDurationSeconds = recordingDurationSeconds;

  Future<void> start({int port = 8777}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('[SaveToDisk-GST] Started on http://localhost:$port');

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
    print('[SaveToDisk-GST] ${request.method} $path');

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
      print('[SaveToDisk-GST] Error: $e');
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

  Future<int> _findFreePort() async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final port = socket.port;
    socket.close();
    return port;
  }

  Future<void> _handleStart(HttpRequest request) async {
    _currentBrowser = request.uri.queryParameters['browser'] ?? 'unknown';
    print('[SaveToDisk-GST] Starting GStreamer test for: $_currentBrowser');

    await _cleanup();
    _localCandidates.clear();
    _startTime = DateTime.now();
    _connectedTime = null;
    _connectionCompleter = Completer();
    _rtpPacketsReceived = 0;
    _rtpPacketsForwarded = 0;
    _outputPath = './recording-gst-${DateTime.now().millisecondsSinceEpoch}.webm';

    // Find a free port for GStreamer UDP listener
    _gstPort = await _findFreePort();
    print('[SaveToDisk-GST] GStreamer UDP port: $_gstPort');

    // Create UDP socket for forwarding RTP to GStreamer
    _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    print('[SaveToDisk-GST] UDP forwarding socket on port: ${_udpSocket!.port}');

    // Start GStreamer pipeline
    final gstCommand = [
      '-e', // Handle EOS properly
      'udpsrc',
      'port=$_gstPort',
      'caps=application/x-rtp,media=video,encoding-name=VP8,clock-rate=90000,payload=96',
      '!',
      'rtpjitterbuffer',
      '!',
      'rtpvp8depay',
      '!',
      'webmmux',
      '!',
      'filesink',
      'location=$_outputPath',
    ];

    print('[SaveToDisk-GST] Starting GStreamer: gst-launch-1.0 ${gstCommand.join(' ')}');
    _gstProcess = await Process.start('gst-launch-1.0', gstCommand);

    _gstProcess!.stdout.transform(utf8.decoder).listen((data) {
      print('[GStreamer] $data');
    });
    _gstProcess!.stderr.transform(utf8.decoder).listen((data) {
      print('[GStreamer ERR] $data');
    });

    // Wait for GStreamer to initialize
    await Future.delayed(Duration(milliseconds: 500));

    // Create peer connection with VP8 codec
    _pc = RtcPeerConnection(RtcConfiguration(
      iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
      codecs: RtcCodecs(
        video: [
          createVp8Codec(
            payloadType: 96,
            rtcpFeedback: [
              RtcpFeedbackTypes.nack,
              RtcpFeedbackTypes.pli,
            ],
          ),
        ],
      ),
    ));
    print('[SaveToDisk-GST] PeerConnection created with VP8 codec');

    _pc!.onConnectionStateChange.listen((state) {
      print('[SaveToDisk-GST] Connection state: $state');
      if (state == PeerConnectionState.connected &&
          !_connectionCompleter.isCompleted) {
        _connectedTime = DateTime.now();
        _connectionCompleter.complete();
      }
    });

    _pc!.onIceConnectionStateChange.listen((state) {
      print('[SaveToDisk-GST] ICE state: $state');
    });

    _pc!.onIceCandidate.listen((candidate) {
      print(
          '[SaveToDisk-GST] Local ICE candidate: ${candidate.type} ${candidate.host}:${candidate.port}');
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
    print('[SaveToDisk-GST] Added video transceiver (recvonly)');

    _pc!.onTrack.listen((transceiver) async {
      print('[SaveToDisk-GST] Received track: ${transceiver.kind}');
      final track = transceiver.receiver.track;

      // Forward RTP packets to GStreamer via UDP
      track.onReceiveRtp.listen((rtp) {
        _rtpPacketsReceived++;

        // Serialize and forward to GStreamer (check socket is still open)
        if (_udpSocket != null && _gstPort != null) {
          final rtpBytes = rtp.serialize();
          _udpSocket!.send(rtpBytes, InternetAddress.loopbackIPv4, _gstPort!);
          _rtpPacketsForwarded++;
        }

        if (_rtpPacketsReceived % 100 == 0) {
          print(
              '[SaveToDisk-GST] Received $_rtpPacketsReceived, forwarded $_rtpPacketsForwarded RTP packets');
        }
      });

      // Set up recording timer
      _recordingTimer =
          Timer(Duration(seconds: _recordingDurationSeconds), () async {
        print('[SaveToDisk-GST] Recording duration reached, stopping...');
        await _stopRecording();
      });
    });

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'ok', 'gstPort': _gstPort}));
  }

  Future<void> _stopRecording() async {
    print('[SaveToDisk-GST] Stopping recording...');

    // Close UDP socket to stop forwarding
    _udpSocket?.close();
    _udpSocket = null;

    // Send SIGINT to GStreamer to trigger proper file finalization
    if (_gstProcess != null) {
      print('[SaveToDisk-GST] Sending SIGINT to GStreamer...');
      _gstProcess!.kill(ProcessSignal.sigint);

      // Wait for GStreamer to finish
      final exitCode = await _gstProcess!.exitCode.timeout(
        Duration(seconds: 5),
        onTimeout: () {
          print('[SaveToDisk-GST] GStreamer timeout, killing...');
          _gstProcess!.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      print('[SaveToDisk-GST] GStreamer exited with code: $exitCode');
      _gstProcess = null;
    }

    // Check output file
    if (_outputPath != null) {
      final file = File(_outputPath!);
      if (await file.exists()) {
        final size = await file.length();
        print('[SaveToDisk-GST] Output file: $_outputPath ($size bytes)');
      } else {
        print('[SaveToDisk-GST] WARNING: Output file not created!');
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
    print('[SaveToDisk-GST] Created offer, local description set');

    await Future.delayed(Duration(milliseconds: 500));

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'type': offer.type,
      'sdp': offer.sdp,
    }));
    print('[SaveToDisk-GST] Sent offer to browser');
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

    print('[SaveToDisk-GST] Received answer from browser');
    await _pc!.setRemoteDescription(answer);
    print('[SaveToDisk-GST] Remote description set');

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
      print('[SaveToDisk-GST] Skipping empty ICE candidate');
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
      print('[SaveToDisk-GST] Added ICE candidate: ${candidate.type}');
    } catch (e) {
      print('[SaveToDisk-GST] Failed to add candidate: $e');
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
      'rtpPacketsForwarded': _rtpPacketsForwarded,
      'gstPort': _gstPort,
      'outputFile': _outputPath,
      'fileSize': fileSize,
      'gstRunning': _gstProcess != null,
      'codec': 'VP8 (GStreamer)',
    }));
  }

  Future<void> _handleResult(HttpRequest request) async {
    await _stopRecording();

    // Give GStreamer a moment to finalize the file
    await Future.delayed(Duration(milliseconds: 500));

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
          _rtpPacketsForwarded > 0 &&
          fileCreated,
      'packetsReceived': _rtpPacketsReceived,
      'packetsForwarded': _rtpPacketsForwarded,
      'outputFile': _outputPath,
      'fileSize': fileSize,
      'connectionTimeMs': connectionTime.inMilliseconds,
      'codec': 'VP8 (GStreamer)',
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
    <title>WebRTC Save to Disk GStreamer Test</title>
    <style>
        body { font-family: monospace; padding: 20px; background: #1a1a1a; color: #eee; }
        #log { background: #0a0a0a; padding: 10px; height: 200px; overflow-y: auto; border: 1px solid #333; }
        .info { color: #8af; }
        .success { color: #8f8; }
        .error { color: #f88; }
        h1 { color: #8af; }
        #status { margin: 10px 0; padding: 10px; background: #333; }
        video { width: 320px; height: 240px; background: #000; border: 2px solid #333; margin: 10px 0; }
        #videoInfo { color: #ff8; margin: 5px 0; }
        .codec-badge { background: #080; color: #fff; padding: 2px 8px; border-radius: 4px; }
        .gst-badge { background: #a00; color: #fff; padding: 2px 8px; border-radius: 4px; margin-left: 5px; }
    </style>
</head>
<body>
    <h1>WebRTC Save to Disk Test <span class="codec-badge">VP8</span><span class="gst-badge">GStreamer</span></h1>
    <p>Browser sends VP8 video to Dart, which forwards RTP packets to GStreamer for recording.</p>
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
                setStatus('Starting GStreamer save_to_disk test for ' + browser);

                // Get local camera stream
                setStatus('Getting camera access...');
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
                    throw new Error('Failed to get camera: ' + e.message);
                }

                const startResp = await fetch(serverBase + '/start?browser=' + browser);
                const startData = await startResp.json();
                log('Server peer started, GStreamer port: ' + startData.gstPort);

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
                log('Received offer from Dart (VP8 -> GStreamer)');

                await pc.setRemoteDescription(new RTCSessionDescription(offer));
                log('Remote description set (offer)');

                const videoTrack = localStream.getVideoTracks()[0];
                pc.addTrack(videoTrack, localStream);
                log('Added local video track to send');

                setStatus('Creating answer...');
                const answer = await pc.createAnswer();
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

                setStatus('Recording via GStreamer (5 seconds)...');
                log('Sending VP8 video -> Dart -> GStreamer...');

                for (let i = 0; i < 7; i++) {
                    await new Promise(resolve => setTimeout(resolve, 1000));
                    const statusResp = await fetch(serverBase + '/status');
                    const status = await statusResp.json();
                    log('Status: recv=' + status.rtpPacketsReceived + ' fwd=' + status.rtpPacketsForwarded + ' file=' + (status.fileSize || 0) + ' bytes');
                }

                setStatus('Getting results...');
                const resultResp = await fetch(serverBase + '/result');
                const result = await resultResp.json();

                if (result.success) {
                    log('TEST PASSED! GStreamer file created: ' + result.fileSize + ' bytes', 'success');
                    setStatus('TEST PASSED - ' + result.fileSize + ' bytes recorded (GStreamer)');
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
  final server = SaveToDiskGstServer(recordingDurationSeconds: 5);
  await server.start(port: 8777);
}
